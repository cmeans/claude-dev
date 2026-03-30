#!/usr/bin/env bash
# Generate a short-lived GitHub App installation token.
# Prints the token to stdout. Requires: openssl, curl, jq.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config"

# Expand tilde in PRIVATE_KEY path
PRIVATE_KEY="${PRIVATE_KEY/#\~/$HOME}"

if [[ ! -f "$PRIVATE_KEY" ]]; then
  echo "Error: Private key not found at $PRIVATE_KEY" >&2
  exit 1
fi

# Build JWT header and payload
NOW=$(date +%s)
IAT=$((NOW - 60))       # 60 seconds in the past to account for clock drift
EXP=$((NOW + 600))      # 10 minute expiry (max allowed)

HEADER=$(printf '{"alg":"RS256","typ":"JWT"}' | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
PAYLOAD=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$IAT" "$EXP" "$APP_ID" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')

# Sign with RSA private key
SIGNATURE=$(printf '%s.%s' "$HEADER" "$PAYLOAD" | \
  openssl dgst -sha256 -sign "$PRIVATE_KEY" -binary | \
  openssl base64 -e -A | tr '+/' '-_' | tr -d '=')

JWT="${HEADER}.${PAYLOAD}.${SIGNATURE}"

# Exchange JWT for installation token
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens")

TOKEN=$(echo "$RESPONSE" | jq -r '.token // empty')

if [[ -z "$TOKEN" ]]; then
  echo "Error: Failed to get installation token" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

echo "$TOKEN"

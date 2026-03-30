# GitHub App Setup Implementation Plan

> **For agentic workers:** This plan has manual steps (GitHub UI) interleaved with scripting steps. Tasks 1-2 require the user to act in the browser. Tasks 3-6 are scripting/config that Claude Code can execute.

**Goal:** Create a GitHub App (`claude-dev`) that gives Claude Code its own commit identity with verified signatures.

**Architecture:** GitHub App with private key on local disk, a shell script to generate short-lived installation tokens, and environment variables to set git committer identity.

**Tech Stack:** Shell (bash), openssl, curl, jq — no external packages.

---

### Task 1: Create the GitHub App (USER — browser)

The user creates the app at github.com. Claude Code cannot do this.

- [ ] **Step 1: Navigate to github.com/settings/apps/new**

- [ ] **Step 2: Fill in the form**

| Field | Value |
|-------|-------|
| GitHub App name | `claude-dev` |
| Homepage URL | `https://github.com/cmeans/claude-dev` |
| Webhook Active | **Uncheck** (disable) |

Permissions (Repository):
| Permission | Access |
|-----------|--------|
| Contents | Read & write |
| Pull requests | Read & write |
| Issues | Read & write |
| Metadata | Read-only |

Where can this GitHub App be installed: **Only on this account**

- [ ] **Step 3: Click "Create GitHub App"**

- [ ] **Step 4: Note the App ID from the "About" section on the resulting page**

Tell Claude Code: "App ID is XXXXXX"

### Task 2: Generate key and install on repos (USER — browser)

- [ ] **Step 1: On the app settings page, scroll to "Private keys" and click "Generate a private key"**

The browser will download a `.pem` file.

- [ ] **Step 2: Move the key to the right location**

```bash
mkdir -p ~/.claude/github-app
mv ~/Downloads/*.private-key.pem ~/.claude/github-app/claude-dev.pem
chmod 600 ~/.claude/github-app/claude-dev.pem
```

- [ ] **Step 3: Install the app — click "Install App" in the left sidebar**

Select "Only select repositories" and check:
- `mcp-awareness`
- `awareness-edge`
- `awareness-canvas`
- `mcpawareness.com`
- `mcp-awareness-infra`

Click "Install".

- [ ] **Step 4: Note the Installation ID from the URL**

After install, the URL will be `github.com/settings/installations/NNNNN`. The number is the Installation ID.

Tell Claude Code: "Installation ID is YYYYYY"

### Task 3: Create .gitignore

**Files:**
- Create: `claude-dev/.gitignore`

- [ ] **Step 1: Write .gitignore**

```
*.pem
*.key
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "Add .gitignore to exclude private keys"
```

### Task 4: Write config file

**Files:**
- Create: `claude-dev/github-app/config`

- [ ] **Step 1: Create github-app directory and config**

```bash
mkdir -p github-app
```

Write `github-app/config`:

```
APP_ID=<from Task 1 Step 4>
INSTALLATION_ID=<from Task 2 Step 4>
PRIVATE_KEY=~/.claude/github-app/claude-dev.pem
```

- [ ] **Step 2: Commit**

```bash
git add github-app/config
git commit -m "Add GitHub App config (IDs only, no secrets)"
```

### Task 5: Write token generation script

**Files:**
- Create: `claude-dev/github-app/get-token.sh`

- [ ] **Step 1: Write the script**

```bash
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
```

- [ ] **Step 2: Make executable**

```bash
chmod 755 github-app/get-token.sh
```

- [ ] **Step 3: Commit**

```bash
git add github-app/get-token.sh
git commit -m "Add GitHub App token generation script"
```

### Task 6: Write activation script

**Files:**
- Create: `claude-dev/github-app/activate.sh`

- [ ] **Step 1: Write the activation script**

This script is sourced (not executed) to set up the environment for a Claude Code session.

```bash
#!/usr/bin/env bash
# Source this script to activate claude-dev[bot] identity.
# Usage: source github-app/activate.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config"

TOKEN=$("$SCRIPT_DIR/get-token.sh")
if [[ $? -ne 0 ]]; then
  echo "Failed to get GitHub App token" >&2
  return 1
fi

export GH_TOKEN="$TOKEN"
export GIT_COMMITTER_NAME="claude-dev[bot]"
export GIT_COMMITTER_EMAIL="${APP_ID}+claude-dev[bot]@users.noreply.github.com"
export GIT_AUTHOR_NAME="claude-dev[bot]"
export GIT_AUTHOR_EMAIL="${APP_ID}+claude-dev[bot]@users.noreply.github.com"

echo "Activated claude-dev[bot] identity (token expires in ~1 hour)"
```

- [ ] **Step 2: Make executable**

```bash
chmod 755 github-app/activate.sh
```

- [ ] **Step 3: Commit**

```bash
git add github-app/activate.sh
git commit -m "Add activation script for claude-dev[bot] identity"
```

### Task 7: Verify

- [ ] **Step 1: Generate a token**

```bash
cd ~/github.com/cmeans/claude-dev
github-app/get-token.sh
```

Expected: prints a token starting with `ghs_`

- [ ] **Step 2: Verify token scope — should NOT work for user endpoint**

```bash
GH_TOKEN=$(github-app/get-token.sh) gh api user 2>&1
```

Expected: 403 error (app tokens can't access user endpoint)

- [ ] **Step 3: Verify token scope — should work for installed repos**

```bash
GH_TOKEN=$(github-app/get-token.sh) gh api repos/cmeans/mcp-awareness --jq .full_name
```

Expected: `cmeans/mcp-awareness`

- [ ] **Step 4: Activate and verify git identity**

```bash
source github-app/activate.sh
git config --get user.name  # should still be Chris (activate sets env vars, not config)
echo $GIT_AUTHOR_NAME       # should be claude-dev[bot]
echo $GH_TOKEN | head -c 4  # should be ghs_
```

- [ ] **Step 5: Test commit with bot identity (on a throwaway branch)**

```bash
cd ~/github.com/cmeans/claude-dev
source github-app/activate.sh
git checkout -b test/bot-identity
echo "test" >> .gitignore
git add .gitignore
git commit -m "test: verify bot commit identity"
git push -u origin test/bot-identity
```

Check on GitHub: the commit should show `claude-dev[bot]` as author with a "Verified" badge.

- [ ] **Step 6: Clean up test branch**

```bash
git checkout main
git branch -D test/bot-identity
git push origin --delete test/bot-identity
```

### Task 8: Push to remote

- [ ] **Step 1: Push all committed work**

```bash
git push origin main
```

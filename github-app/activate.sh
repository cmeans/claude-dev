#!/usr/bin/env bash
# Source this script to activate cmeans-claude-dev[bot] identity.
# Usage: source github-app/activate.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config"

TOKEN=$("$SCRIPT_DIR/get-token.sh")
if [[ $? -ne 0 ]]; then
  echo "Failed to get GitHub App token" >&2
  return 1
fi

export GH_TOKEN="$TOKEN"
export GIT_COMMITTER_NAME="cmeans-claude-dev[bot]"
export GIT_COMMITTER_EMAIL="${APP_ID}+cmeans-claude-dev[bot]@users.noreply.github.com"
export GIT_AUTHOR_NAME="cmeans-claude-dev[bot]"
export GIT_AUTHOR_EMAIL="${APP_ID}+cmeans-claude-dev[bot]@users.noreply.github.com"

echo "Activated cmeans-claude-dev[bot] identity (token expires in ~1 hour)"

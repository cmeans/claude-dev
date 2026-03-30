# GitHub App: claude-dev Bot Identity

## Goal

Give Claude Code a distinct commit identity (`claude-dev[bot]`) with GitHub-verified signatures on all awareness repos. Commits from Claude Code should be visually distinguishable from Chris's commits in git log and on GitHub.

## Scope

Configuration and scripting only. No changes to any application code.

## GitHub App Configuration

### Create the App

- **Location:** github.com/settings/apps/new (personal account)
- **Name:** `claude-dev`
- **Homepage URL:** `https://github.com/cmeans/claude-dev`
- **Webhook:** Disabled (no server-side events needed)
- **Permissions:**
  - Contents: Read & write (push commits)
  - Pull requests: Read & write (create/update PRs)
  - Issues: Read & write (add/remove labels)
  - Metadata: Read (required baseline)
- **Where can this be installed:** Only on this account

### Generate Private Key

- After creation, generate a private key from the app settings page
- Download to `~/.claude/github-app/claude-dev.pem`
- `chmod 600 ~/.claude/github-app/claude-dev.pem`

### Install on Repos

Install the app on these 5 repositories:

1. `cmeans/mcp-awareness`
2. `cmeans/awareness-edge`
3. `cmeans/awareness-canvas`
4. `cmeans/mcpawareness.com`
5. `cmeans/mcp-awareness-infra` (private)

More repos can be added later from Settings > Applications > Configure without reinstalling.

### Record IDs

After creation and installation, note:
- **App ID** — visible on the app's settings page (General tab, "About" section)
- **Installation ID** — visible in the URL when configuring the installation (`/installations/NNNNN`)

Store both in the claude-dev repo (`github-app/config`):

```
APP_ID=XXXXXX
INSTALLATION_ID=YYYYYY
PRIVATE_KEY=~/.claude/github-app/claude-dev.pem
```

This file is safe to commit — it contains only IDs and a path, not secrets. The `.pem` file stays outside the repo at the referenced path.

## Token Generation Script

`github-app/get-token.sh` — generates a short-lived installation token from the app's private key.

### How it works

1. Build a JWT (RS256-signed) with the App ID as `iss` claim, 10-minute expiry
2. POST to `https://api.github.com/app/installations/{INSTALLATION_ID}/access_tokens` with the JWT as Bearer auth
3. Extract the `token` field from the JSON response
4. Print the token to stdout (callers capture it)

### Dependencies

- `openssl` (for RS256 signing — available on all systems)
- `curl` (for GitHub API call)
- `jq` (for JSON parsing — already installed on Fedora workstation)

No Python, no npm, no external packages. Pure shell.

### Token lifetime

Installation tokens are valid for 1 hour. The script generates a fresh one on each invocation — no caching needed for typical Claude Code session lengths.

## Claude Code Integration

### Git committer identity

When Claude Code uses the app token, git needs to know the bot identity:

```
GIT_COMMITTER_NAME="claude-dev[bot]"
GIT_COMMITTER_EMAIL="APP_ID+claude-dev[bot]@users.noreply.github.com"
GIT_AUTHOR_NAME="claude-dev[bot]"
GIT_AUTHOR_EMAIL="APP_ID+claude-dev[bot]@users.noreply.github.com"
```

The `APP_ID` in the email is replaced with the actual numeric app ID. This is GitHub's convention for bot commit attribution — commits will show the bot avatar and "Verified" badge.

### Activation

A wrapper script or shell hook sources `get-token.sh` and sets the environment:

```sh
export GH_TOKEN=$(~/.claude/github-app/get-token.sh)
export GIT_COMMITTER_NAME="claude-dev[bot]"
export GIT_COMMITTER_EMAIL="APP_ID+claude-dev[bot]@users.noreply.github.com"
export GIT_AUTHOR_NAME="claude-dev[bot]"
export GIT_AUTHOR_EMAIL="APP_ID+claude-dev[bot]@users.noreply.github.com"
```

This is sourced when launching Claude Code in dev mode (e.g., the `claude-dev` alias).

### What changes

| Action | Before | After |
|--------|--------|-------|
| `git commit` | Chris Means | claude-dev[bot] (Verified) |
| `gh pr create` | Chris's PAT | App installation token |
| `gh pr merge` | Chris's PAT | App installation token |
| Co-Authored-By trailer | Still included | Still included |

Chris's own commits (outside Claude Code) are unaffected — they continue using his personal git config and PAT.

## Files Created

| Path | Purpose |
|------|---------|
| `claude-dev/github-app/config` | App ID, Installation ID, key path (committed) |
| `~/.claude/github-app/claude-dev.pem` | RSA private key (chmod 600, NOT in repo) |
| `claude-dev/github-app/get-token.sh` | Token generation script (chmod 755, committed) |
| `claude-dev/.gitignore` | Prevents accidental commit of secrets |

### .gitignore

```
*.pem
*.key
```

## Security

- Private key stored with 600 permissions in `~/.claude/github-app/`
- Installation tokens are short-lived (1 hour) and scoped to the installed repos
- The private key never leaves the workstation
- The app has minimal permissions (Contents + PRs only)
- `.claude/github-app/` is not inside any git repo

## Verification

After setup, verify with:

1. `github-app/get-token.sh` — should print a token starting with `ghs_`
2. `GH_TOKEN=$(get-token.sh) gh api user` — should fail (app tokens can't access user endpoint, confirming it's an app token not a PAT)
3. `GH_TOKEN=$(get-token.sh) gh api repos/cmeans/mcp-awareness` — should succeed
4. Create a test commit with bot identity, push, check GitHub shows "Verified" badge and bot avatar

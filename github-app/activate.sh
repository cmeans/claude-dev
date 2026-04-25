#!/usr/bin/env bash
# Source this script to activate cmeans-claude-dev[bot] identity.
# Usage: source github-app/activate.sh
#
# What this does (and why):
#
#   1. Mints a fresh installation token from the GitHub App private key and
#      exports it as $GH_TOKEN. Used by `gh` CLI calls.
#
#   2. Replaces the session's git global config (~/.gitconfig) with a curated
#      bot config (github-app/git-global.config) by exporting
#      GIT_CONFIG_GLOBAL. The curated file carries everything that defines
#      bot git identity: user.name / user.email, gpgSign disables,
#      pushInsteadOf for github.com (forces SSH→HTTPS for push), and the
#      credential helper that returns $GH_TOKEN.
#
# Why a config-file swap rather than environment-variable overrides:
# `GIT_CONFIG_COUNT/KEY/VALUE` env vars LOSE to the user's global insteadOf
# rule (verified during PRs #358/#373/#377 on mcp-awareness). A curated
# global config sidesteps that fight entirely — the user's global
# `url.git@github.com:.insteadOf=https://github.com/` is simply not loaded
# during a bot session, so the bot's `pushInsteadOf` rule is the only URL
# rewrite that applies.
#
# Per-process isolation: GIT_CONFIG_GLOBAL is an environment variable, so
# subprocesses inherit it automatically. A non-bot terminal in the same
# clone does not inherit it (env is per-process), so QA / human sessions
# read ~/.gitconfig as normal and push as the human.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
source "$SCRIPT_DIR/config"

TOKEN=$("$SCRIPT_DIR/get-token.sh")
if [[ $? -ne 0 ]]; then
  echo "Failed to get GitHub App token" >&2
  return 1
fi

# Render git-global.config.template → .git-global.config with $SCRIPT_DIR
# substituted in. Rendered every time so it tracks the template + script
# location automatically; rendered file is gitignored. Plain `sed` because
# the template only carries one placeholder and we want to keep this
# dependency-free.
RENDERED_GIT_CONFIG="$SCRIPT_DIR/.git-global.config"
sed "s|__SCRIPT_DIR__|$SCRIPT_DIR|g" \
  "$SCRIPT_DIR/git-global.config.template" > "$RENDERED_GIT_CONFIG"

export GH_TOKEN="$TOKEN"
export GIT_CONFIG_GLOBAL="$RENDERED_GIT_CONFIG"

# Clear any residual GIT_CONFIG_* env-var matrix from a prior activation
# (the v1 design used these and they would shadow GIT_CONFIG_GLOBAL via
# git's `command line:` precedence layer if left set in the same shell).
# Idempotent: unset on a never-set var is a no-op.
unset GIT_CONFIG_COUNT
for i in 0 1 2 3 4 5 6 7 8 9; do
  unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"
done

# Also clear the v1 commit-identity env vars; they're now in
# git-global.config as [user] keys. Leaving them set wouldn't break
# anything, but it duplicates the source of truth and would make a
# `git config user.email` lookup show the env var instead of the file.
unset GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL

# Drop the shell-function `git` wrapper from the v1 design. With
# GIT_CONFIG_GLOBAL doing the work, a wrapper is redundant — and a
# function defined in a prior `source` would still shadow the real
# git binary in this shell until explicitly unset.
unset -f git 2>/dev/null || true

echo "Activated cmeans-claude-dev[bot] identity (token expires in ~1 hour; GIT_CONFIG_GLOBAL → $GIT_CONFIG_GLOBAL)"

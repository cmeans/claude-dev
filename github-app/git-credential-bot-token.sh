#!/usr/bin/env bash
# Git credential helper for cmeans-claude-dev[bot].
# Returns the bot's installation token from $GH_TOKEN on "get" operations
# when the target host is github.com (or api.github.com). Stays silent for
# every other host so the normal helper chain (e.g. ``credential.helper=store``)
# can respond for non-GitHub remotes.
#
# Installed as the first entry in the global ``credential.helper`` list by
# activate.sh so it runs before ``store`` — URL-scoped registration alone is
# not enough because the global helper list is consulted first by git's push
# path even for URL-matching lookups.
#
# Why this exists: GitHub's require_last_push_approval ruleset attributes the
# PushEvent to the *authenticating user* of the git push. If git's credential
# store returns a human PAT (e.g. cmeans), that's the last pusher — and if the
# same human approves, GitHub treats it as self-approval and blocks merge.
set -u

OP="${1:-}"

# git credentials protocol: read stdin `key=value\n…\n\n`
HOST=""
while IFS= read -r line && [[ -n "$line" ]]; do
  case "$line" in
    host=*) HOST="${line#host=}" ;;
  esac
done

# Strip any :port suffix so host matching is consistent.
HOST_ONLY="${HOST%%:*}"

case "$OP" in
  get)
    if [[ -n "${GH_TOKEN:-}" ]] && { [[ "$HOST_ONLY" == "github.com" ]] || [[ "$HOST_ONLY" == "api.github.com" ]]; }; then
      printf 'username=x-access-token\n'
      printf 'password=%s\n' "$GH_TOKEN"
    fi
    # Any other host / no token: emit nothing, let the next helper in the
    # chain respond.
    ;;
  store|erase)
    # Never persist the installation token.
    :
    ;;
esac

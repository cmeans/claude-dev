#!/usr/bin/env bash
# Helper invoked by the `git` shell function in activate.sh for `git push …`.
# Re-implements the push with a concrete bash process so we can use proper
# arrays instead of fighting zsh word-splitting.
#
# Behavior:
#   - If the push targets a github.com remote AND $GH_TOKEN is set, rewrite
#     the remote to its HTTPS URL and run `GIT_CONFIG_GLOBAL=/dev/null git push`
#     (neutralizing the user's global `url.git@github.com:.insteadOf` rule).
#   - Otherwise, pass through untouched.
#
# Called with argv = "push" <all original args>. The wrapper strips "push"
# and forwards the rest so this script owns the full refspec+flags parse.

set -euo pipefail

# First positional is always "push" (the wrapper enforces that). Drop it.
if [ "${1:-}" = "push" ]; then
  shift
fi

# Fast paths: no token, or caller asked for help / version / etc. without a
# remote ever being resolvable.
if [ -z "${GH_TOKEN:-}" ]; then
  exec git push "$@"
fi

# Single pass: identify remote (first positional) and refspec (second
# positional). Flags before the remote stay before it; everything after the
# refspec goes in `trailing`.
declare -a pre=()
declare -a trailing=()
remote=""
refspec=""
seen_remote=0
seen_refspec=0
is_delete=0

for arg in "$@"; do
  case "$arg" in
    --delete|-d)
      is_delete=1
      if [ "$seen_remote" -eq 0 ]; then
        pre+=("$arg")
      else
        trailing+=("$arg")
      fi
      ;;
    -*)
      if [ "$seen_remote" -eq 0 ]; then
        pre+=("$arg")
      else
        trailing+=("$arg")
      fi
      ;;
    *)
      if [ "$seen_remote" -eq 0 ]; then
        remote="$arg"; seen_remote=1
      elif [ "$seen_refspec" -eq 0 ]; then
        refspec="$arg"; seen_refspec=1
      else
        trailing+=("$arg")
      fi
      ;;
  esac
done

# No remote was provided → user is relying on upstream tracking. Rewriting it
# to an explicit URL would break tracking-ref-based --force-with-lease checks,
# so just pass through and let the caller deal with the insteadOf fallout.
if [ -z "$remote" ]; then
  exec git push "$@"
fi

# Resolve remote name → URL. If the token already looks like a URL, keep it.
url="$remote"
case "$url" in
  *://*|*@*:*) ;;
  *)
    url=$(git remote get-url "$remote" 2>/dev/null || echo "")
    ;;
esac

# Not a github.com push → pass through.
case "$url" in
  *github.com*) ;;
  *)
    exec git push "$@"
    ;;
esac

# Normalize SSH forms (scp-style and ssh://) to HTTPS.
https_url="$url"
case "$https_url" in
  git@github.com:*)
    https_url="https://github.com/${https_url#git@github.com:}"
    ;;
  ssh://git@github.com/*)
    https_url="https://github.com/${https_url#ssh://git@github.com/}"
    ;;
esac

# Force same-name refspec when the user gave a bare branch name — the bypass
# URL has no `origin/…` tracking ref to fall back on, so we want to be
# explicit about the destination. Skip for --delete / -d: that mode requires
# a plain target ref name and rejects the src:dst form.
if [ -n "$refspec" ] && [ "$is_delete" -eq 0 ]; then
  case "$refspec" in
    *:*) ;;  # explicit src:dst
    *)   refspec="${refspec}:${refspec}" ;;
  esac
fi

# Build the final push argv: [pre-remote flags] <https_url> [refspec] [trailing]
declare -a push_args=()
if [ "${#pre[@]}" -gt 0 ]; then push_args+=("${pre[@]}"); fi
push_args+=("$https_url")
if [ -n "$refspec" ]; then push_args+=("$refspec"); fi
if [ "${#trailing[@]}" -gt 0 ]; then push_args+=("${trailing[@]}"); fi

exec env GIT_CONFIG_GLOBAL=/dev/null git push "${push_args[@]}"

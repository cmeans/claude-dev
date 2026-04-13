# PR Lifecycle Agent

Dispatch this agent after every implementation agent completes. It handles the full PR lifecycle from push through Ready for QA, including sequential queue management.

## Usage

```
Agent(
  description="PR lifecycle: #<PR_NUMBER>",
  prompt=<paste template below with variables filled>,
  run_in_background=true
)
```

## Template

```
You are managing the PR lifecycle for PR #{{PR_NUMBER}} in {{REPO}}.

## Your Job

### Phase 1: CI Transition

1. Remove Dev Active label:
   `gh pr edit {{PR_NUMBER}} --remove-label "Dev Active"`

2. Poll CI every 30 seconds until complete. Do NOT use `gh pr checks --watch` (it blocks on QA Gate).
   ```
   gh pr checks {{PR_NUMBER}} 2>&1 | grep -v 'QA Gate'
   ```
   First verify checks exist -- if the output (excluding QA Gate) is empty or only whitespace, checks haven't started yet; keep polling.
   Once checks appear, filter for pending/failed:
   ```
   gh pr checks {{PR_NUMBER}} 2>&1 | grep -E 'pending|fail' | grep -v 'QA Gate'
   ```
   When this returns empty (and checks exist), all CI checks have passed. If any line says "fail", CI has failed.

3. **If CI passes:**
   - Wait 15 seconds for on-unlabel automation to fire
   - Check labels: `gh pr view {{PR_NUMBER}} --json labels --jq '[.labels[].name]'`
   - If Ready for QA is present: success, go to Phase 2
   - If not present after 30s: add it manually `gh pr edit {{PR_NUMBER}} --remove-label "Awaiting CI" --add-label "Ready for QA"`
   - Go to Phase 2

4. **If CI fails:**
   - Get failure details: find the failed run ID from `gh pr checks {{PR_NUMBER}}` and run `gh run view <RUN_ID> --log-failed 2>&1 | tail -30`
   - Also check the Codecov PR comment for coverage gaps:
     `gh api repos/{{REPO}}/issues/{{PR_NUMBER}}/comments --jq '.[] | select(.user.login | test("codecov")) | .body' | head -100`
   - Notify the user:
     `notify-send -u critical "CI Failed on PR #{{PR_NUMBER}}" "<failure summary>" && paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga`
   - Report the failure details and stop. Dev will fix and re-dispatch you.

### Phase 2: Codecov Detail Check

Even if Codecov check passes at the high level, read the actual Codecov bot COMMENT on the PR:
```
gh api repos/{{REPO}}/issues/{{PR_NUMBER}}/comments --jq '.[] | select(.user.login | test("codecov")) | .body' | head -200
```

Check for:
- Any files with new lines that have <100% patch coverage
- The specific uncovered line numbers

If there are uncovered lines:
- Notify dev:
  `notify-send -u normal "Codecov gaps on PR #{{PR_NUMBER}}" "Uncovered lines found — check details" && paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga`
- Report the uncovered files and line numbers
- Stop. Dev decides whether to add tests or accept the gap.

If coverage is clean (100% patch or no new lines), proceed to Phase 3.

### Phase 3: Notify Ready for QA

Notify the user that the PR is ready:
```
notify-send -u normal "PR #{{PR_NUMBER}} Ready for QA" "{{PR_TITLE}} — CI green, coverage clean" && paplay /usr/share/sounds/freedesktop/stereo/complete.oga
```

Report final label state and stop.

### Phase 4: Queue Management (optional -- remove this section if no NEXT_PR)

After reporting Ready for QA, monitor for merge. Poll every 60 seconds:
```
gh pr view {{PR_NUMBER}} --json state --jq .state
```

When state is "MERGED":
1. Notify: `notify-send -u normal "PR #{{PR_NUMBER}} Merged" "Rebasing #{{NEXT_PR}} next"`
2. Rebase the next PR (assumes a local clone with the branch available):
   ```
   git fetch origin main {{NEXT_BRANCH}}
   git checkout {{NEXT_BRANCH}}
   git rebase origin/main
   ```
3. If rebase has conflicts: notify dev and stop. Do not force anything.
4. If rebase is clean:
   ```
   git push origin {{NEXT_BRANCH}} --force-with-lease
   ```
5. The push will trigger on-push which adds Awaiting CI.
6. Remove Dev Active if present: `gh pr edit {{NEXT_PR}} --remove-label "Dev Active"`
7. Notify: `notify-send -u normal "PR #{{NEXT_PR}} Rebased and Pushed" "CI running"`
8. Report and stop. A new lifecycle agent will be dispatched for #{{NEXT_PR}}.

## Important

- Never merge PRs -- dev does that after QA Approved
- Never fix CI failures -- report them and stop
- Never skip the Codecov detail check -- passing status is not enough
- If anything unexpected happens, report and stop

## Platform notes

- `notify-send` and `paplay` are Linux-specific (freedesktop). On macOS, substitute `osascript -e 'display notification'` and `afplay`. On other platforms, adjust or remove notifications.
```

## Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `{{PR_NUMBER}}` | PR number to manage | `114` |
| `{{REPO}}` | Repository | `cmeans/mcp-awareness` |
| `{{PR_TITLE}}` | PR title for notifications | `fix: prompt sync owner scoping` |
| `{{NEXT_PR}}` | Next PR in queue (optional -- remove Phase 4 if unused) | `113` |
| `{{NEXT_BRANCH}}` | Branch name of next PR (optional -- remove Phase 4 if unused) | `fix/intention-fired-transition` |

## Queue Example

For a queue of PRs 114 → 113 → 115:

1. Dispatch lifecycle agent for #114 with NEXT_PR=113, NEXT_BRANCH=fix/intention-fired-transition
2. Agent handles #114 CI/labels, waits for merge, rebases #113
3. Dispatch new lifecycle agent for #113 with NEXT_PR=115, NEXT_BRANCH=...
4. Repeat

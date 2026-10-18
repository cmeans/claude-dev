# Pre-QA Review Agent

Dispatch this agent **before every push to a PR branch**: the first push, and each fix push
after `QA Failed`. It reviews the change the way QA does, so findings get fixed before QA's
round trip: a QA round, then a full CI rerun for each fix push (on mcp-synology, about 12–16
minutes with vdsm on a cache hit).

The checklist below comes from QA's review comments on the 80 most recent mcp-synology PRs
(#104–#288, mined 2026-10-18): 203 findings across 60 PRs with a QA Failed round. 119 of them
(about 60%) were about the docs, the PR body, the CHANGELOG or scope, not the code. Sections are
ordered by how often QA caught each kind. The per-section counts are approximate: categories were
merged, and a few findings fit none of them.

## Usage

Commit locally, but don't push. Then:

```
Agent(
  description="Pre-QA review: <branch>",
  subagent_type="general-purpose",
  prompt=<template below with variables filled>,
)
```

Use a fresh agent (not a fork) so it doesn't share the author's reasoning. Fix what it
confirms, rerun it if the fixes were non-trivial, then push once. Record the result in the
PR body: `Pre-QA review: N findings (M fixed, K declined: see below)`, or
`Pre-QA review: clean`. Don't cite a SHA there, since a later rebase changes it.

The reviewer reports and doesn't fix. Dev decides what to change, and anything Dev decides not
to fix goes into the PR body with a reason.

## Variables

| Variable | Value |
|---|---|
| `{{REPO}}` | `owner/name`, e.g. `cmeans/mcp-synology` |
| `{{WORKTREE}}` | absolute path of the branch's worktree, with the change committed |
| `{{BRANCH}}` | the branch name |
| `{{ISSUE_LINE}}` | `Issue: #N (read it with gh issue view N --comments).` If there's no issue, a sentence stating the intent instead |
| `{{BODY_LINE}}` | First push: `PR body draft: <absolute path>` (write the draft to the session scratchpad first). Fix push: `PR: #N (gh pr view N --comments), including QA's latest round` |
| `{{SCRATCH}}` | an absolute path in the session scratchpad, for the reviewer's repros and worktrees |

`gh` needs a valid token in the reviewer's shell. If the session uses the bot identity, tell the
reviewer to `source ~/github.com/cmeans/claude-dev/github-app/activate.sh` in each Bash call that
runs `gh`.

## Template

```
You are reviewing a change before it goes to QA in {{REPO}} (worktree: {{WORKTREE}}).
Branch {{BRANCH}}, diff: `git -C {{WORKTREE}} diff origin/main...HEAD`. {{ISSUE_LINE}}
{{BODY_LINE}} Read the repo's CLAUDE.md and the specs it names for the area the diff touches.

Your job is to find what QA would find. Try to break the change. Report a finding only if
you reproduced it: a command and its output, a failing test, or a scratch-repo or
test-environment probe. Label anything else "suspected", with what would confirm it.
Don't edit {{WORKTREE}}. Do repros, mutation checks and old-version comparisons under
{{SCRATCH}}: `git -C {{WORKTREE}} worktree add {{SCRATCH}}/<name> <ref>`, then
`git -C {{WORKTREE}} worktree remove --force {{SCRATCH}}/<name>` when you're done.
Shell commands such as git grep, pytest and piped tails are fine here.

Work through the checklist in ~/github.com/cmeans/claude-dev/prompts/pre-qa-review-agent.md,
including the addendum for {{REPO}} if there is one. For each section, either give findings
or write "checked: <how>".

Return a table: # | severity (bug / nit / doc) | file:line | finding | evidence | suggested fix.
End with what you couldn't check, and why.
```

## Checklist

### 1. Unverified claims (about 28 findings)

Can each factual sentence in the PR body, CHANGELOG, specs and docs point to evidence?
- Re-read every "as before", "never", "only", "every", "no user-visible change",
  "verified", "can't", "N in M" and percentage. Prove each by running old vs new
  (a scratch worktree of `origin/main`) or quoting the code line or doc URL.
- Produce example outputs by running the real code, never by hand.
- Recompute rates and totals from the PR's own tables.
- Check repo-config claims (rulesets, labels, required checks) with `gh api`.
- Don't call a manual probe a test. If the body says a test covers X, grep the test for X.
- Read dependency versions from the lockfile, never from a Dependabot trailer.

### 2. Stale statements elsewhere in the repo (about 27)

What did this change make false, and where else is it stated?
- List the old claim's key phrases, names and defaults, using 3–4 wordings. One grep with
  one phrase took three QA rounds on one PR.
- `git grep -niE '<phrase1>|<phrase2>|<old name>|<old default>'` across README, CLAUDE.md,
  docs/, specs, docstrings, test docstrings, code comments, CONTRIBUTING, examples/,
  workflow comments and model-facing text (server instructions, tool descriptions). Older
  CHANGELOG entries are history, but check the new entry doesn't contradict them.
- Run every documented command the change touches.
- Grep again after each fix round: fixes cause drift too.

### 3. Edge cases not enumerated (about 19)

For each new parameter, flag, pattern or filter, make a table of odd inputs and what each
does:
- numbers: 0, -1, negative, inf, nan, 1e400, non-ASCII digits (`"²".isdigit()` is true;
  pair it with `isascii()`);
- strings and paths: empty, `/`, NUL, `../`, different case, `~user`, a trailing slash,
  duplicates after normalization, a parent and its child, two items with the same output name;
- filesystem: dangling symlink, symlink loop, a directory where a file is expected;
- config: `enabled: false` vs absent vs empty list;
- git and shell: renames (`git diff --name-only` lists only the new path; use
  `--no-renames`), an empty diff, multi-line regex matches, bash vs zsh (CI runs bash; test
  scripts with `bash -c`);
- order: the first call in a fresh process, a mixed list vs a single ID.

Each row gets a parametrized test asserting a structured error, or a scratch-repo repro.

### 4. CHANGELOG and release notes (about 17)

- The entry exists under Unreleased, in the repo's format and categories, with the PR number.
  No `@handles`. Security content is called out.
- Write "used to" and "previously" against the last released tag, not an intermediate
  commit: probe a scratch worktree of `v<last>`. Check `git tag --contains` before
  logging a revert.
- Releases: the tag date, the supported-versions table, any status line.
- American spelling and idiom ("behavior", not "behaviour"; no "belt-and-braces").

### 5. Body, title and counts after each push (about 14; the most common exact repeat)

- `pytest -q | tail -1`, `git rev-parse --short HEAD` and per-directory `--collect-only`
  counts match every number in the body and CHANGELOG.
- The title covers the whole diff.
- A "QA round N" section lists that round's fixes.
- Prefer wording that won't go stale: leave out counts nobody needs.

### 6. Scope and follow-ups (about 13)

Re-read the issue, its later comments and any design addendum line by line. Each item is
done, declared in the body as a deviation, or filed as an issue before QA. Close duplicates.

### 7. Tests that don't pin the claim (about 13)

- Mutation check: in a scratch worktree of `HEAD`, revert the source hunk (or the single
  line); each new test must fail there.
- Assert the exact value or code the body names (`== 1`, not `<= 1`; `==`, not `endswith`).
- A CI check fails, rather than skips or warns, when the thing it guards is broken.

### 8. Failure paths and exceptions (about 12)

What can each new call raise, and what does the caller see?
- Check the library docs for what each new call raises (HTTP transport errors, a 200
  `text/html` reply where JSON was expected, `ValueError` and `RuntimeError` from path
  resolution). Run on the oldest and newest supported Python.
- No raw tracebacks: every failure gets a structured error with an actionable suggestion.
- No `except` clause narrower than the cleanup it guards. No `|| true` or `2>/dev/null` that
  hides API errors in workflows. Under `set -e`, one bad item mustn't stop a loop.
- Crashes are logged at WARNING or ERROR, with `exc_info`.

### 9. External-API behavior assumed, not captured (about 12)

- Every reply shape the code relies on comes from a real capture, for every supported
  version.
- Probe every state: own, another user's or missing; active, paused or finished; admin vs
  non-admin; per-item errors vs the call's overall success.
- Anything not captured is marked unverified in the spec and body.

### 10. CI exercises what ships (about 12)

- A dependency range change: resolve fresh (`uv lock --upgrade-package X` in a scratch
  worktree) and import it. CI's lockfile isn't what users install.
- List the affected workflows that don't run on a PR (publish, `pull_request_target`,
  main-only steps such as cache saves).
- Check the failure modes: a bad cache, a forgotten version bump, a wait longer than the
  job's budget.
- State what CI can't cover, and add a maintainer gate for it.

### 11. Reply and error text (about 9)

Is every sentence in each reply true on every path that reaches it?
- Say "stopped", "deleted" or "created" only after it's confirmed.
- An error's parameter name is the tool's own argument name.
- A retryable flag matches idempotency.
- No doubled period from composed strings.

### 12. Sibling parity (about 6)

Grep the sibling tools and actions for each convention this change touches (caps,
refusing an update with nothing to change, per-item error lists, listing candidates for an
ambiguous name, skip guards, hints), and match them.

### 13. Secrets (about 6)

- Mask new secret-bearing parameters in logs.
- Never log raw API objects.
- Probe at debug log level with marker secrets, and grep stdout and stderr for them. Include
  fields the server derives from URLs (titles, query strings).

### 14. MCP annotations (about 4)

Annotate for the worst case of any argument: relative or partial actions are not
idempotent, and anything that can leave things half done is destructive.

### 15. Merge state

`git fetch && git merge-tree --write-tree origin/main HEAD` shows no conflicts, especially
in the CHANGELOG.

## Repo addenda

### mcp-synology

- **DSM captures:** Download Station fixtures come from real replies
  (`tests/modules/downloadstation/fixtures/`), and its mocks route by `api`/`method`/`version`
  (`tests/modules/downloadstation/dsm.py`). New reply shapes in any module need a capture. Check both DSM 7.1 and 7.2.2, and admin vs
  non-admin (`mcptest`). A per-task 405 vs a whole-call 101 was described wrongly three
  times; count per-item `error` fields.
- **JSON-quoted values:** free-text DSM parameters go through `dsm_str()` (#121).
- **Secrets:** new secret-bearing parameters go in `_SENSITIVE_PARAMS`. Probe with
  `SYNOLOGY_LOG_LEVEL=debug`.
- **Background tasks:** `try/finally` cleanup, and the hand-off rules in CLAUDE.md (#162, #245).
- **Specs:** `tests/test_module_specs.py` checks tool names, tiers, parameters and
  descriptions. Response shapes and annotations in the spec need a manual read.
- **vdsm:** a bake change bumps `BAKE_VERSION`. Run vdsm locally on both DSM versions before
  pushing a vdsm or bake change.
- **CHANGELOG:** only Added, Changed or Fixed, in the form `- **Title** (#N) — …`, adding
  `closes #M` when there's an issue.

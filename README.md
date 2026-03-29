# claude-dev

Developer role configuration for [Claude Code](https://claude.ai/code).

## What this is

A `CLAUDE.md` that configures Claude Code as a **Developer agent** — scoped to writing code, managing PRs, running tests, and updating docs. Boundaries are explicit: no QA reviews, no ops work.

## Usage

```bash
claude --add-dir ~/github.com/cmeans/claude-dev
```

This loads the Developer role alongside your project's own `CLAUDE.md`. Use the alias `claude-dev` if configured.

## Companion

The QA counterpart is [claude-qa](https://github.com/cmeans/claude-qa) — a separate role for independent code review and testing.

---

*Part of the [Awareness](https://github.com/cmeans/mcp-awareness) ecosystem. Copyright (c) 2026 Chris Means.*

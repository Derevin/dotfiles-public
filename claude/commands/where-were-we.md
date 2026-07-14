---
description: Where were we in this worktree
disable-model-invocation: true
context: fork
agent: general-purpose
model: haiku
---

Identify what work is in progress in *this* worktree.

1. Run `task-list.sh --status active planning`. The first two lines of output are `Tasks: <project>` and `Worker: <worker>`. Rows have `[worker]` brackets — filter to rows whose bracket matches the `Worker:` value.

2. If no matching claimed task, answer `no work in progress in this wt` and stop. Otherwise read the task file at `~/repos/tasks/<project>/<status>/<filename>` (status per the section it was listed under) for context.

3. Run `git log --oneline -5` for recent commit context.

4. If `~/repos/context/<project>/CONTEXT.md` exists (resolve `<project>` via `find-project.sh`), glance at the glossary so the summary uses canonical domain terms. Skip silently if not present.

Answer in 2–3 sentences max: what we were working on, current status, obvious next step if any. No preamble.

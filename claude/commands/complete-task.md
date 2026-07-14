---
description: Mark the single active task as completed
disable-model-invocation: true
context: fork
agent: general-purpose
model: haiku
---

Complete the current active task. Assumes exactly one active task for this worker — if zero or multiple, stop and tell the user (they can run `/complete-task-with-context` for the multi case).

1. **Find.** Run `task-list.sh --status active`. The first two lines are `Tasks: <project>` and `Worker: <worker>`. Filter active rows to those with `[worker]` matching `Worker:`. If not exactly one match, stop and report.

2. **PR check.** Run `gh pr view --json state -q .state` for the current branch. If a PR exists and its state is not `MERGED`, stop and tell the user. If no PR exists, continue.

3. **Resolve.** Read the task file at `~/repos/tasks/<project>/active/<filename>`. Append a `## Resolution` section: brief summary, branch name (from `git branch --show-current`), PR link if any.

4. **Done.** Run `task-done.sh <filename>` — moves to done, commits, pushes.

5. **Cleanup.** Run `task-cleanup-branch.sh` — detaches to `origin/<base>` and deletes the task branch. Refuses if PR isn't merged or if not on a branch.

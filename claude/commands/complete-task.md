---
description: Mark a task as completed — the argument, else the lab's own
argument-hint: [task]
disable-model-invocation: true
context: fork
background: false
agent: general-purpose
model: haiku
---

Complete one active task.

1. **Find.** The task id comes from the argument (`055`, `055-some-slug`, `N055-some-slug`), else from the lab name `lab-current.sh` prints (`hlab-055-…` → `055`). Its filename is the matching line of `taskania list --status active --ids`. No match: stop and tell the user to rerun with the task as the argument.

2. **PR check.** Run `gh pr view --json state -q .state` for the current branch. If a PR exists and its state is not `MERGED`, stop and tell the user. If no PR exists, continue.

3. **Resolve.** Read the task file at `~/repos/tasks/<project>/active/<filename>` (`<project>` from `taskania project`). Append a `## Resolution` section: brief summary, branch name (from `git branch --show-current`), PR link if any.

4. **Done.** Run `taskania done <filename>` — moves to done, commits, pushes.

5. **Cleanup.** Run `task-cleanup-branch.sh` — detaches to `origin/<base>` and deletes the task branch. Refuses if PR isn't merged or if not on a branch.

6. **Offer the drop.** Run `lab-current.sh`. If it prints a name, print `lab-drop.sh <name>` for the user to paste — do NOT run it. Dropping is irreversible and always theirs to trigger.

7. **Offer the retro.** Print `/retro` for the user to run in their main session — it mines this task's session for environment improvements, and wants the full context and a strong model this closing fork lacks. Do NOT run it here.

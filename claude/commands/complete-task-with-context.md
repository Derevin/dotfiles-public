---
allowed-tools: Bash(task-*),Bash(git *),Bash(gh *),Read(~/repos/tasks/**),Edit(~/repos/tasks/**)
description: Mark current task as completed
disable-model-invocation: true
---

Complete the current active task.

1. **Find.** Run `task-list.sh --status active` to find active task(s). If multiple, ask which.

2. **PR check.** Run `gh pr view --json state -q .state` for the current branch. If a PR exists and its state is not `MERGED`, stop and tell the user. If no PR exists, continue.

3. **Resolve.** Read the task file. Append a `## Resolution` section: brief summary, branch name (from `git branch --show-current`), PR link if any.

4. **Done.** Run `task-done.sh <filename>` — moves to done, commits, pushes.

5. **Cleanup.** Run `task-cleanup-branch.sh` — detaches to `origin/<base>` and deletes the task branch. Refuses if PR isn't merged or if not on a branch.

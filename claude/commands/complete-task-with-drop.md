---
allowed-tools: Bash(task-*),Bash(lab-current.sh),Bash(lab-drop.sh *),Bash(git *),Bash(gh *),Read(~/repos/tasks/**),Edit(~/repos/tasks/**)
description: Mark current task as completed, then drop its lab
disable-model-invocation: true
---

Complete the current active task, then destroy the lab it was done in. `/complete-task-with-context` with the last step run rather than printed — invoking this command by name is the explicit trigger the drop otherwise waits for.

1. **Find.** Run `task-list.sh --status active` to find active task(s). If multiple, ask which.

2. **PR check.** Run `gh pr view --json state -q .state` for the current branch. If a PR exists and its state is not `MERGED`, stop and tell the user. If no PR exists, continue.

3. **Resolve.** Read the task file. Append a `## Resolution` section: brief summary, branch name (from `git branch --show-current`), PR link if any.

4. **Done.** Run `task-done.sh <filename>` — moves to done, commits, pushes.

5. **Cleanup.** Run `task-cleanup-branch.sh` — detaches to `origin/<base>` and deletes the task branch. Refuses if PR isn't merged or if not on a branch.

6. **Drop.** Run `lab-current.sh`. Nothing printed: no lab, stop. A name: run `lab-drop.sh <name>`.

   Never `--force`. Its refusals — an attached task outside `planned/` or `done/`, a dirty worktree, a HEAD no remote ref can reach — are this command's only test that the task really is done. Report one and stop; don't work around it.

   Steps 2, 3 and 5 only work where the task branch is checked out, so this runs inside the lab, and dropping it reverts this pane to a launchpad. That ends the session: write the summary of 1-5 out before the drop call, not after. The drop itself survives — it hands the destruction to a copy outside this pane's process group and returns `dropping <name>` rather than `dropped`.

---
allowed-tools: Bash(task-*),Bash(git *),Read(~/repos/tasks/**),Edit(~/repos/tasks/**)
description: Refresh the claimed task file with current state. Reached by the fork that `/forkwc-update-task` spawns.
user-invocable: false
---

Refresh the active task file with current state — what's done, what's left, where to pick up. So a future session (you, after compaction, or a fresh start) reads the file and knows the lay of the land without retracing the whole conversation.

Only the fork that `/forkwc-update-task` spawns runs this. Reached any other way, stop and invoke `/forkwc-update-task` instead — it forks, so the git reads and the commit don't land in the caller's session.

Write it self-sufficient. Whoever picks this up gets this file and the context store, nothing else: the plan, the affected files, and any gotchas explicit. A terse jog-my-memory note doesn't survive a cold handoff. Where the file's original body contradicts what was agreed in this conversation, rewrite it rather than leaving both.

1. **Find.** Run `task-list.sh --status active planning`. The first two lines are `Tasks: <project>` and `Worker: <worker>`. Filter rows to those with `[worker]` matching `Worker:`. If not exactly one match, stop and report.

2. **Read.** Read the task file at `~/repos/tasks/<project>/<status>/<filename>` (status per the section it was listed under) so you know its existing structure (sections, prior status notes, user-written Context).

3. **Ground.** Run `git log --oneline -20` and `git status` so the update reflects committed work + in-flight changes, not just conversation memory.

4. **Update.** Edit the task file in place:
   - **Preserve**: `# Title`, `Depends:`, user-written background `## Context`, any user-written `## Notes`. An agent-written `## Context` the user has since superseded is not background — correct it.
   - **Refresh or add**: the progress sections that match the task's existing shape (e.g. `## What's done` / `## What's left` / `## How to pick up <X>`). Don't invent boilerplate sections the task doesn't need. No `## Status:` line — the directory is the status.
   - **Capture the resume breadcrumb**: branch name, commands to re-enter the loop, gotchas surfaced this session, anything a cold reader would otherwise miss.
   - **Do NOT** add `## Resolution` — that's for `/complete-task`.

5. **Commit.** Run `task-commit.sh "Update: <slug> [<worker>]"`.

**Return** one line: that the file is written, and its path. Whoever called this agreed the plan and doesn't need it read back.

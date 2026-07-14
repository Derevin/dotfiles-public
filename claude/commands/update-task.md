---
allowed-tools: Bash(task-*),Bash(git *),Read(~/repos/tasks/**),Edit(~/repos/tasks/**)
description: Update claimed task file with current state so next session can resume — self-invoke only as a grill flow step, not as a mid-work checkpoint
---

Refresh the active task file with current state — what's done, what's left, where to pick up. So a future session (you, after compaction, or a fresh start) reads the file and knows the lay of the land without retracing the whole conversation.

The user can invoke this whenever. Self-invoke only as a step of `/grill-task` — not on your own initiative mid-implementation; commits and the conversation already carry that state.

1. **Find.** Run `task-list.sh --status active planning`. The first two lines are `Tasks: <project>` and `Worker: <worker>`. Filter rows to those with `[worker]` matching `Worker:`. If not exactly one match, stop and report.

2. **Read.** Read the task file at `~/repos/tasks/<project>/<status>/<filename>` (status per the section it was listed under) so you know its existing structure (sections, prior status notes, user-written Context).

3. **Ground.** Run `git log --oneline -20` and `git status` so the update reflects committed work + in-flight changes, not just conversation memory.

4. **Update.** Edit the task file in place:
   - **Preserve**: `# Title`, `Depends:`, original background `## Context`, any user-written `## Notes`.
   - **Refresh or add**: the progress sections that match the task's existing shape (e.g. `## What's done` / `## What's left` / `## How to pick up <X>`). Don't invent boilerplate sections the task doesn't need. No `## Status:` line — the directory is the status.
   - **Capture the resume breadcrumb**: branch name, commands to re-enter the loop, gotchas surfaced this session, anything a cold reader would otherwise miss.
   - **Do NOT** add `## Resolution` — that's for `/complete-task`.

5. **Commit.** Run `task-commit.sh "Update: <slug> [<worker>]"`.

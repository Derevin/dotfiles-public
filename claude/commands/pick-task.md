---
allowed-tools: Bash(task-*),Read(~/repos/tasks/**)
description: Pick and start the next available task
disable-model-invocation: true
---

Pick the next task from the queue and start working on it.

1. **List.** Run `task-list.sh --status todo` to see available tasks.

2. **Pick.** Take the first one (highest priority). If it has `Depends:`, check if those IDs exist in done/ (use `task-list.sh --status done` or read the file).

3. **Claim.** Run `task-claim.sh <filename>` — syncs, moves to active, commits, and outputs task content.

4. **Grill.** Read the task file.
   - **Reminder-only task** (just `# Title`, no real body): you have zero context. Do NOT explore the codebase, propose a plan, or guess intent. Your only permitted response is to ask the user to give you more context so you can invoke grill. The moment they reply, invoke `/grill-me-with-docs` — no preamble, no analysis in between.
   - **Task with a real body**: invoke `/grill-me-with-docs` directly.

   Grill interviews the user about scope and design until you reach a shared plan. Don't proceed until the user is satisfied.

5. **Wait for go.** Docs approval ≠ impl approval. After grilling+docs commits, stop and ask explicitly before implementing.

6. **Snapshot the plan.** The moment impl is approved — before writing code — invoke `/update-task` to record the agreed plan in the task file: a handoff so a cold resume (compaction, fresh session) starts from the confirmed approach, not the original description.

7. **Implement.** Implement the agreed plan.

8. **Self-review.** Invoke `/review-branch-medium` on the first implementation pass.

9. **Hand off.** When done, stop and tell the user what you did — nothing more. Do NOT run `/complete-task` or suggest it, and do NOT announce that you're leaving the task in `active/` or that you're not completing it — leaving it there is the silent default; narrating the non-action is noise. What follows is the user's manual review, possibly PR creation, review cycles, and merge. Task stays in `active/` until the user explicitly says it's done (typically after the branch is merged into main/master) and runs `/complete-task` themselves.

---
allowed-tools: Bash(task-*),Read(~/repos/tasks/**)
description: Pick the next todo task, grill it to an agreed plan, and park it in planned/
disable-model-invocation: true
---

Groom the next task: pick it, grill it to an agreed plan, snapshot that plan, and park it in `planned/` — stopping at the agreed plan, not implementing. An implementer picks it up later via `/implement-task`, possibly in another pane with no access to this conversation — so the snapshot must stand on its own.

1. **List.** Run `task-list.sh --status todo` to see available tasks.

2. **Pick.** Take the first one (highest priority). If it has `Depends:`, check if those IDs exist in done/ (use `task-list.sh --status done` or read the file).

3. **Claim.** Run `task-claim.sh <filename>` — syncs, moves to planning/, commits, and outputs task content.

4. **Grill.** Read the task file.
   - **Reminder-only task** (just `# Title`, no real body): you have zero context. Do NOT explore the codebase, propose a plan, or guess intent. Your only permitted response is to ask the user to give you more context so you can invoke grill. The moment they reply, invoke `/grill-me-with-docs` — no preamble, no analysis in between.
   - **Task with a real body**: first recap the task in one paragraph (what it asks, not a plan) so the user — who filed it a while ago and may have forgotten — knows what they're answering before grilling's first question. Then invoke `/grill-me-with-docs`.

   Grill interviews the user about scope and design until you reach a shared plan. Don't proceed until the user is satisfied.

5. **Wait for go.** Don't snapshot a half-agreed plan. Approving the doc writes at grilling's end is not agreement that the plan is settled — they're separate gates. After the docs commit, ask explicitly whether the plan itself is final; only a clear yes here unlocks step 6.

6. **Snapshot + park.** Invoke `/update-task` to record the agreed plan — written as a self-sufficient brief, because the implementer will have only this file plus the context store (CONTEXT.md, ADRs), not this conversation. Make the plan, the affected files, and any gotchas explicit; a terse jog-my-memory note is not enough across a cold handoff. Then run `task-planned.sh <filename>` to move the task into `planned/` (this strips the worker — the task is now unowned and groomed). Stop there: do NOT implement, do NOT run `/complete-task`. Tell the user it's parked in `planned/`, ready for `/implement-task`.

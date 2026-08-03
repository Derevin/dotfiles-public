---
allowed-tools: Bash(task-*),Read(~/repos/tasks/**)
description: Pick the next todo task, grill it to an agreed plan, and park it in planned/
disable-model-invocation: true
---

Groom the next task: pick it, grill it to an agreed plan, snapshot that plan, and park it in `planned/` — stopping at the agreed plan, not implementing. An implementer picks it up later via `/implement-task`, possibly in another pane with no access to this conversation — so the snapshot must stand on its own.

1. **List.** Run `task-list.sh --status todo` to see available tasks.

2. **Pick.** Take the first one (highest priority). If it has `Depends:`, check if those IDs exist in done/ (use `task-list.sh --status done` or read the file).

3. **Claim.** Run `task-claim.sh <filename>` — syncs, moves to planning/, commits, and outputs task content.

4. **Frame.** Read the task file. Either path ends with a task body in hand.
   - **Reminder-only task** (just `# Title`, no real body): you have zero context. Do NOT explore the codebase, propose a plan, or guess intent. Your only permitted response is to ask the user what the task is about. Their answer is the body — skip the recap, they just told you.
   - **Task with a real body**: recap it in one paragraph (what it asks, not a plan) so the user — who filed it a while ago and may have forgotten — knows what they're answering before grilling's first question.

5. **Recon.** Dispatch one `Explore` subagent, seeded with the body: which files and modules the change would touch, how that area behaves today, existing patterns or prior art for this kind of change, anything in the code that contradicts the task's premise. A compact brief, not file dumps. Grilling mandates looking facts up rather than asking the user for them; front-loading that keeps the interview from stalling on greps and keeps the dumps out of a conversation that has to stay coherent for many turns. Targeted lookups mid-grill still happen inline — recon doesn't replace them. Skip only when you already know exactly which files change and why. Narrate nothing at the user here: recon is a tool call, not a preamble.

6. **Grill.** Invoke `/grill-me-with-docs`, handing it the recon brief. It interviews the user about scope and design until you reach a shared plan. Don't proceed until the user is satisfied.

7. **Wait for go.** Don't snapshot a half-agreed plan. Approving the doc writes at grilling's end is not agreement that the plan is settled — they're separate gates. After the docs commit, ask explicitly whether the plan itself is final; only a clear yes here unlocks step 8.

8. **Snapshot + park.** Invoke `/update-task` to record the agreed plan — written as a self-sufficient brief, because the implementer will have only this file plus the context store (CONTEXT.md, ADRs), not this conversation. Make the plan, the affected files, and any gotchas explicit; a terse jog-my-memory note is not enough across a cold handoff.

   **Cold-read it before parking.** You are the worst judge of whether the brief stands alone — you have the whole conversation in context. Dispatch one subagent with only the task file path and the context store, no summary from you, and ask what it could not implement from those alone. Fold genuine gaps back into the file and leave them uncommitted; `task-planned.sh` sweeps them into the park commit. Ignore anything that redesigns the plan or nitpicks wording — this tests for missing context, it does not reopen the design.

   Then run `task-planned.sh <filename>` to move the task into `planned/` (this strips the worker — the task is now unowned and groomed). Stop there: do NOT implement, do NOT run `/complete-task`. Tell the user it's parked in `planned/`, ready for `/implement-task`.

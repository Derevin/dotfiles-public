---
allowed-tools: Bash(task-*),Read(~/repos/tasks/**),Edit(~/repos/tasks/**)
description: Pick the next todo task, grill it to an agreed plan, and park it in planned/
disable-model-invocation: true
---

Groom the next task: pick it, grill it to an agreed plan, snapshot that plan, and park it in `planned/` — stopping at the agreed plan, not implementing. An implementer picks it up later via `/implement-task`, possibly in another pane with no access to this conversation — so the snapshot must stand on its own.

1. **List.** Run `task-list.sh --status todo` to see available tasks.

2. **Pick.** Take the first one (highest priority). If it has `Depends:`, check if those IDs exist in done/ (use `task-list.sh --status done` or read the file).

3. **Claim.** Run `task-claim.sh <filename>` — syncs, moves to planning/, commits, and outputs task content.

4. **Frame.** Read the task file. Either path ends with a framing the user wrote. A pre-written body is *additional context*, never the spec — an agent likely wrote it and nobody has verified it since.
   - **Reminder-only task** (just `# Title`, no real body): you have zero context. Do NOT explore the codebase, propose a plan, or guess intent. Your only permitted response is to ask the user what the task is about. Their answer is the body — skip the recap, they just told you.
   - **Task with a real body**: recap it in one paragraph — what it asks and what it assumes, not a plan — so the user sees the premises before endorsing or replacing them; they may never have read this body. Then ask what they want the task to actually be about, exactly as in the reminder-only path, and wait. Their answer is authoritative: where it and the file disagree, the file is wrong. Don't defend the body's premises, and don't ask the user to justify departing from them.

5. **Recon.** Dispatch one `recon` subagent, seeded with the framing from step 4 — plus the file body where the framing left it standing: which files and modules the change would touch, how that area behaves today, existing patterns or prior art for this kind of change, anything in the code that contradicts the task's premise. A compact brief, not file dumps. Grilling mandates looking facts up rather than asking the user for them; front-loading that keeps the interview from stalling on greps and keeps the dumps out of a conversation that has to stay coherent for many turns. Targeted lookups mid-grill still happen inline — recon doesn't replace them. Skip only when you already know exactly which files change and why. Narrate nothing at the user here: recon is a tool call, not a preamble.

6. **Grill.** Invoke `/grill-me-with-docs`, handing it the step 4 framing and the recon brief. The first round's frontier comes off that framing, not the file body. It interviews the user about scope and design until you reach a shared plan. Don't proceed until the user is satisfied.

7. **Wait for go.** Don't snapshot a half-agreed plan. Approving the doc writes at grilling's end is not agreement that the plan is settled — they're separate gates. After the docs commit, ask explicitly whether the plan itself is final; only a clear yes here unlocks step 8.

8. **Snapshot.** Invoke `/update-task` to record the agreed plan. This step stays in this conversation on purpose — the brief is written out of the grill, and only you hold it. Write it self-sufficient: the implementer gets this file and the context store, nothing else. Make the plan, the affected files, and any gotchas explicit; a terse jog-my-memory note doesn't survive a cold handoff. Where the file's original body contradicts what was agreed, rewrite it rather than leaving both.

9. **Cold-read.** Invoke `/fork-cold-read`: forked, it puts a context-free reader on the brief and returns the gaps that survive triage. The reader's report and the triage stay in the fork. Answer each returned gap into the task file yourself — the fork returns questions rather than filling them because you hold the grill and it doesn't. Leave those edits uncommitted; `task-planned.sh` sweeps them into the park commit. A gap you can't answer means the plan wasn't final after all: take it to the user, then run the cold read again.

10. **Park.** Run `task-planned.sh <filename>` to move the task into `planned/` (this strips the worker — the task is now unowned and groomed). Stop there: do NOT implement, do NOT run `/complete-task`. Tell the user it's parked in `planned/`, ready for `/implement-task`.

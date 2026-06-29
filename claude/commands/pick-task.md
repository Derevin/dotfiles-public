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
   - **Task with a real body**: first recap the task in one paragraph (what it asks, not a plan) so the user — who filed it a while ago and may have forgotten — knows what they're answering before grilling's first question. Then invoke `/grill-me-with-docs`.

   Grill interviews the user about scope and design until you reach a shared plan. Don't proceed until the user is satisfied.

5. **Wait for go.** Docs approval ≠ impl approval. After grilling+docs commits, stop and ask explicitly before implementing.

6. **Snapshot the plan.** The moment impl is approved — before writing code — invoke `/update-task` to record the agreed plan in the task file: a handoff so a cold resume (compaction, fresh session) starts from the confirmed approach, not the original description.

7. **Implement.** Implement the agreed plan.

8. **Converge.** Loop a cheap review to a fixed point. Each round: get the diff with `cc-review-diff.sh`, scan it in one inline pass — no subagent fan-out, that's what keeps it cheap — for substantial, high-confidence problems only (real bugs, missing guards, dead code, clear correctness/consistency errors), and fix those in place. Then re-run. Stop when a round finds no new substantial problem, or after 3 rounds — whichever first. Holding the bar at high-confidence is what makes it converge instead of dredging nitpicks.

9. **Deep review.** Once, as a backstop, invoke `/review-branch-medium` — the multi-perspective subagent fan-out the loop deliberately skipped. Apply its substantial, clear-cut findings automatically (same bar as step 8), in place, uncommitted. Set the judgment calls aside — architectural shifts, refactors, anything intent-dependent or sprawling across files — they're not yours to decide; carry them to the handoff.

10. **Hand off.** If the deep review left judgment calls, open with them — the handoff is where the user enters the loop, so lead with the decisions waiting on them: each as `file:line — one-line description — proposed fix`. Then summarize the implementation as a whole — the net of everything since you began implementing, folding the review rounds and fixes into a single picture rather than reporting only the sub-step that happened to finish last. Nothing more — do NOT run `/complete-task` or suggest it, and do NOT announce that you're leaving the task in `active/` or that you're not completing it — leaving it there is the silent default; narrating the non-action is noise. What follows is the user's manual review, possibly PR creation, review cycles, and merge. Task stays in `active/` until the user explicitly says it's done (typically after the branch is merged into main/master) and runs `/complete-task` themselves.

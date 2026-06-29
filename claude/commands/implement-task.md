---
allowed-tools: Bash(task-*),Read(~/repos/tasks/**)
description: Pick the next groomed task from planned/ and implement it
disable-model-invocation: true
---

Pick a groomed task from `planned/` and implement it from its snapshotted plan. The task file plus the context store is your entire brief.

1. **List.** Run `task-list.sh --status planned` to see groomed tasks (highest priority first).

2. **Pick.** Take the first one, or the one the user names.

3. **Claim.** Run `task-claim.sh <filename>` — syncs, moves planned/ → active/, stamps you as worker, outputs task content.

4. **Orient.** Read the task file — the recorded plan and status sections are your brief. Read the referenced CONTEXT.md / ADRs. If the brief has a genuine gap that blocks implementation, surface it to the user before writing code rather than guessing — a well-groomed task shouldn't have one, so a gap is a signal worth raising. Then invoke `/update-task` to set `## Status: implementing`, so the active task's phase is unambiguous and an unclaim returns it to `planned/`, not `todo/`.

5. **Implement.** Implement the agreed plan.

6. **Converge.** Loop a cheap review to a fixed point. Each round: get the diff with `cc-review-diff.sh`, scan it in one inline pass — no subagent fan-out, that's what keeps it cheap — for substantial, high-confidence problems only (real bugs, missing guards, dead code, clear correctness/consistency errors), and fix those in place. Then re-run. Stop when a round finds no new substantial problem, or after 3 rounds — whichever first. Holding the bar at high-confidence is what makes it converge instead of dredging nitpicks.

7. **Deep review.** Once, as a backstop, invoke `/review-branch-medium` — the multi-perspective subagent fan-out the loop deliberately skipped. Apply its substantial, clear-cut findings automatically (same bar as step 6), in place, uncommitted. Set the judgment calls aside — architectural shifts, refactors, anything intent-dependent or sprawling across files — they're not yours to decide; carry them to the handoff.

8. **Hand off.** If the deep review left judgment calls, open with them — the handoff is where the user enters the loop, so lead with the decisions waiting on them: each as `file:line — one-line description — proposed fix`. Then summarize the implementation as a whole — the net of everything since you began implementing, folding the review rounds and fixes into a single picture rather than reporting only the sub-step that happened to finish last. Nothing more — do NOT run `/complete-task` or suggest it, and do NOT announce that you're leaving the task in `active/` or that you're not completing it — leaving it there is the silent default; narrating the non-action is noise. What follows is the user's manual review, possibly PR creation, review cycles, and merge. Task stays in `active/` until the user explicitly says it's done (typically after the branch is merged into main/master) and runs `/complete-task` themselves.

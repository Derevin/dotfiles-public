---
allowed-tools: Bash(task-*),Read(~/repos/tasks/**)
description: Pick the next groomed task from planned/ and implement it
disable-model-invocation: true
---

Pick a groomed task from `planned/` and implement it from its snapshotted plan. The task file plus the context store is your entire brief.

1. **List.** Run `task-list.sh --status planned` to see groomed tasks (highest priority first).

2. **Pick.** Take the first one, or the one the user names.

3. **Claim.** Run `task-claim.sh <filename>` — syncs, moves planned/ → active/, stamps you as worker, outputs task content.

4. **Orient.** Read the task file — the recorded plan and status sections are your brief. Read the referenced CONTEXT.md / ADRs. If the brief has a genuine gap that blocks implementation, surface it to the user before writing code rather than guessing — a well-groomed task shouldn't have one, so a gap is a signal worth raising.

5. **Implement.** Invoke `/fork-implement`: it inherits everything you know, implements the plan, proves the tests red-green, and returns the decisions the diff can't show. The reading and build output stay behind in the fork, so the review and handoff below run on a context that carries no implementation baggage. If it returns a question instead of an implementation, the brief had a gap — take it to the user, then dispatch again.

6. **Converge.** Invoke `/converge-review`: one generalist reads the whole diff and proposes, you adopt or drop, looped to a fixed point. Keep the diff out of your own context — dispatching is what makes it cheap.

7. **Deep review.** Once, as a backstop, invoke `/review-branch-medium` — the multi-perspective fan-out that the loop's single generalist can't give you. Sort every finding through the gate below: apply the **Apply** bucket in place and uncommitted, resolve the **Drop** bucket yourself, carry only the **Ask** bucket to the handoff.

   **The gate.** Sort on cost of being wrong, not on how weighty the idea sounds. A cheap, locally revertible change is cheaper to make than to ask about — the user's own review at the handoff is the safety net.

   - **Apply** if any holds: it's a defect (wrong behaviour, missing guard, dead code); it violates a documented rule (CLAUDE.md, CONTEXT.md, an ADR); or it's cheap, local, revertible in one hunk *and* the pattern it proposes already exists elsewhere in the repo.
   - **Drop** if any holds: no defect, no documented rule, and no in-repo precedent — taste with nothing behind it; it targets pre-existing code the diff merely touched rather than introduced; or it adds an abstraction, parameter, or hook with no second call site in the diff.
   - **Ask** only what survives both: wide blast radius *and* a real argument behind it.

   The in-repo precedent test carries the most weight — "the codebase already does this" is what separates consistency from novelty. Check it, don't assume it.

   Every item you ask about must carry the strongest case *against* adopting it, not just the proposed fix. If the against-case is plainly stronger, the item was a **Drop** — resolve it there rather than asking. State how many findings you dropped; list them only if the user asks.

8. **Hand off.** If the deep review left judgment calls, open with them — the handoff is where the user enters the loop, so lead with the decisions waiting on them: a numbered list (so the user can refer to one by number), each as `file:line — one-line description — proposed fix — strongest case against`. Then summarize the implementation as a whole — the net of everything since you began implementing, folding the review rounds and fixes into a single picture rather than reporting only the sub-step that happened to finish last. Nothing more — do NOT run `/complete-task` or suggest it, and do NOT announce that you're leaving the task in `active/` or that you're not completing it — leaving it there is the silent default; narrating the non-action is noise. What follows is the user's manual review, possibly PR creation, review cycles, and merge. Task stays in `active/` until the user explicitly says it's done (typically after the branch is merged into main/master) and runs `/complete-task` themselves.

---
allowed-tools: Bash(task-*),Read(~/repos/tasks/**)
description: Pick the next groomed task from planned/ and implement it
disable-model-invocation: true
---

Pick a groomed task from `planned/` and implement it from its snapshotted plan. The task file plus the context store is your entire brief.

1. **List.** Run `task-list.sh --status planned` to see groomed tasks (highest priority first). Skip when an id was given.

2. **Pick.** An id in the arguments (`039`, `039-some-slug`, or the filename `N039-some-slug`) names the task: resolve it to the filename in `planned/` and go straight to step 3. Otherwise take the first one, or the one the user names.

3. **Claim.** Run `task-claim.sh <filename>` — syncs, moves planned/ → active/, stamps you as worker, outputs task content.

4. **Orient.** Read the task file — the recorded plan and status sections are your brief. Read the referenced CONTEXT.md / ADRs. If the brief has a genuine gap that blocks implementation, surface it to the user before writing code rather than guessing — a well-groomed task shouldn't have one, so a gap is a signal worth raising.

5. **Implement.** Invoke `/forkwc-implement`: it dispatches a fork that inherits this conversation — the plan, the orientation above, and any steer the user has given — implements the plan, proves the tests red-green, and returns the decisions the diff can't show. The reading and build output stay behind in the fork, so the review and handoff below run on a context that carries no implementation baggage. If it returns a question instead of an implementation, the plan had a gap — take it to the user, then dispatch again.

6. **Deep review.** As a backstop, invoke `/fork-review` — a multi-perspective fan-out over the diff, run in its own fork with the Apply/Drop/Ask gate applied inside it. It comes in cold and returns only the judgment calls that survived, so carry those to the handoff. Hand it nothing: reviewing the diff on its own terms is what makes it an independent check.

7. **Hand off.** Filter the review's judgment calls before showing any. It came in cold, so drop what this conversation already settled — you hold the steers it never saw — and drop what you can now answer yourself. Often nothing survives; that's a clean handoff, not a thin one. Open with one line of counts carried up from the deep review's return — items fixed — e.g. `Deep review: 2 items fixed.` Then whatever survived the filter, since the handoff is where the user enters the loop: a numbered list (so the user can refer to one by number), each as `file:line — one-line description — proposed fix — strongest case against`. Then summarize the implementation as a whole — the net of everything since you began implementing, folding the review's fixes into a single picture rather than reporting only the step that finished last. Nothing more — do NOT run `/complete-task` or suggest it, and do NOT announce that you're leaving the task in `active/` or that you're not completing it — leaving it there is the silent default; narrating the non-action is noise. What follows is the user's manual review, possibly PR creation, review cycles, and merge. Task stays in `active/` until the user explicitly says it's done (typically after the branch is merged into main/master) and runs `/complete-task` themselves.

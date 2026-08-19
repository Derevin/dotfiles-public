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

5. **Implement.** Invoke `/fork-implement`: forked, it takes the task file and the context store as its brief, implements the plan, proves the tests red-green, and returns the decisions the diff can't show. The reading and build output stay behind in the fork, so the review and handoff below run on a context that carries no implementation baggage. If it returns a question instead of an implementation, the brief had a gap — take it to the user, then dispatch again.

6. **Converge.** Invoke `/forkwc-converge`: it dispatches a seeded fork that inherits this conversation — the plan, the steers, and what the implementer decided — and loops one generalist reviewer against the diff, adopting or dropping to a fixed point. The diff, the rounds, and the edit churn stay in the fork; only the net comes back.

7. **Deep review.** Once, as a backstop, invoke `/fork-review` — the multi-perspective fan-out that the loop's single generalist can't give you, run in its own fork with the Apply/Drop/Ask gate applied inside it. It returns only the judgment calls that survived, so carry those to the handoff. Hand it nothing: what converge dropped died with that fork, and reviewing the diff on its own terms is what makes this an independent check rather than a second lap.

8. **Hand off.** If the deep review left judgment calls, open with them — the handoff is where the user enters the loop, so lead with the decisions waiting on them: a numbered list (so the user can refer to one by number), each as `file:line — one-line description — proposed fix — strongest case against`. Then summarize the implementation as a whole — the net of everything since you began implementing, folding the review rounds and fixes into a single picture rather than reporting only the sub-step that happened to finish last. Nothing more — do NOT run `/complete-task` or suggest it, and do NOT announce that you're leaving the task in `active/` or that you're not completing it — leaving it there is the silent default; narrating the non-action is noise. What follows is the user's manual review, possibly PR creation, review cycles, and merge. Task stays in `active/` until the user explicitly says it's done (typically after the branch is merged into main/master) and runs `/complete-task` themselves.

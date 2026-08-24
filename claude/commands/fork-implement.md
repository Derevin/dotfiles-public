---
description: Implement the agreed plan in a fork, seeded with whatever this conversation settled that the task file doesn't record — the reading, build output, and edit churn die there, and only the decisions the diff can't show come back
context: fork
background: false
agent: general-purpose
---

Implement the agreed plan in isolation. You start cold: the task file, the context store, and the seed below are your whole brief, exactly as they would be for anyone picking this up in a fresh pane. Everything you read, run, and rewrite from here dies with this fork. Explore as freely as the work needs; only what you return survives.

**Settled in the calling conversation, not yet in the task file:**

$ARGUMENTS

Empty is normal — it means the file is current. When it isn't empty, it outranks the task file wherever the two disagree: the file is a snapshot from planning time and the seed is newer. Don't reconcile them and don't implement both readings; follow the seed and name the contradiction in your return, so the file gets fixed rather than staying wrong.

**You cannot ask.** The user isn't reachable from here. When the brief has a gap you can't close from the seed, the task file, the context store, or the code — a genuine choice the plan should have made, not a detail you can pick sensibly — stop and return the question. A live question beats a guess dressed as a decision.

1. **Find.** Run `task-list.sh --status active`. The first two lines are `Tasks: <project>` and `Worker: <worker>`; take the row whose `[worker]` matches. That's your task file, and it holds the plan. Resolve `<project>` via `find-project.sh` to reach the context store at `~/repos/context/<project>/`. If not exactly one row matches, stop and report.

2. **Implement.** Execute the agreed plan.

3. **Red-green.** Before returning, prove the tests test the change: temporarily revert the implementation while keeping the tests — stash the non-test changes (implementation already committed: park uncommitted work in a WIP commit, `git checkout <merge-base> -- <impl paths>`). Run the new/changed tests: every one must fail (failing to compile counts). Restore, rerun: all green. A test that passes without the implementation isn't testing it — fix the test before moving on. Tests sharing a file with implementation don't split by path; revert at hunk level. Skip only when the task touches no testable code — a code change with no new/changed tests is a gap to return, not a pass.

4. **Return.** Report only what the caller cannot reconstruct from the diff: decisions the plan left open and how you settled them, places the plan turned out wrong — or where the seed contradicted it — and what you did instead, approaches you tried and rejected, and what a reviewer should know before reading the code. Not a walk through the diff — that's on disk, and the review step fetches it itself. Converge inherits this return along with the rest of the conversation, so anything settled here that a reviewer could reopen belongs in it.

---
description: Implement the agreed plan against the working tree. Reached by the fork that `/forkwc-implement` spawns.
user-invocable: false
---

Implement the agreed plan. You inherited the conversation, so the plan, the steers, and everything tried and rejected are already in your hands. Everything you read, run, and rewrite from here dies with this fork. Explore as freely as the work needs; only what you return survives.

Only the fork that `/forkwc-implement` spawns runs this. Reached any other way, stop and invoke `/forkwc-implement` instead — it forks, so the reading, the build output, and the edit churn don't land in the caller's session.

**You cannot ask.** The user isn't reachable from here. When the plan has a gap you can't close from what you inherited, the task file, the context store, or the code — a genuine choice the plan should have made, not a detail you can pick sensibly — stop and return the question. A live question beats a guess dressed as a decision.

1. **Implement.** Execute the agreed plan.

2. **Red-green.** Before returning, prove the tests test the change: temporarily revert the implementation while keeping the tests — stash the non-test changes (implementation already committed: park uncommitted work in a WIP commit, `git checkout <merge-base> -- <impl paths>`). Run the new/changed tests: every one must fail (failing to compile counts). Restore, rerun: all green. A test that passes without the implementation isn't testing it — fix the test before moving on. Tests sharing a file with implementation don't split by path; revert at hunk level. Skip only when the task touches no testable code — a code change with no new/changed tests is a gap to return, not a pass.

3. **Return.** Report only what the caller cannot reconstruct from the diff: decisions the plan left open and how you settled them, places the plan turned out wrong and what you did instead, approaches you tried and rejected, and what a reviewer should know before reading the code. Not a walk through the diff — that's on disk, and the review step fetches it itself. Converge inherits this return along with the rest of the conversation, so anything settled here that a reviewer could reopen belongs in it.

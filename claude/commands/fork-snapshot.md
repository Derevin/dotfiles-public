---
description: Snapshot the agreed plan and cold-read it in a fork — the brief-writing and the fold die there, only the verdict comes back
context: fork
background: false
agent: general-purpose
---

Turn the conversation you inherited into a task brief that stands without it. You have the whole grilling session — the framing, the recon, every decision and the reasoning behind it — and the drafting, the re-reads, and the gap-folding all die with this fork.

**Dispatch.** The cold read is a subagent's job by construction: you are the worst judge of whether the brief stands alone, because the conversation that produced it is still in your context. Spawning that reader is the work you were given, not a way of passing it on.

**You cannot ask.** The user isn't reachable from here. If the plan itself has an open question, don't invent an answer and don't write it in as settled — return it.

1. **Snapshot.** Invoke `/update-task` to record the agreed plan. Write it as a self-sufficient brief: the implementer gets this file and the context store, nothing else. Make the plan, the affected files, and any gotchas explicit — a terse jog-my-memory note doesn't survive a cold handoff. Where the file's original body contradicts what was agreed, rewrite it rather than leaving both.

2. **Cold-read.** Invoke `/cold-read-task`. Leave its edits uncommitted; the caller's `task-planned.sh` sweeps them into the park commit.

3. **Return.** One or two lines: that the brief is written and cold-read, plus the substance of any folded-in gap that changes what the plan says, plus any open question from above. Not a summary of the plan — the caller agreed it, and the file holds it now.

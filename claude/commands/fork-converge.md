---
description: Converge the working diff to a fixed point in a fork — each round a subagent proposes substantial fixes, you adopt or drop them, up to 3 rounds
context: fork
background: false
agent: general-purpose
---

Converge the working diff to a fixed point. A subagent reads the diff and proposes; you decide. You inherit the whole conversation — the plan, the steers, what was tried and rejected — and the rounds you collect, the hunks you read, and the edits you make die with this fork. Never fetch the diff yourself; that's what the subagent is for.

**Dispatch.** Spawning the reviewer each round is the work you were given, not a way of passing it on. Run the rounds.

**You cannot ask.** The user isn't reachable from here. Decide with what you inherited.

Each round:

1. **Dispatch.** Launch one `converge-reviewer` subagent. Hand it the task file path, the context store path (`~/repos/context/<project>/`, `<project>` via `find-project.sh`), what earlier rounds considered and dropped, and what's already settled: approaches tried and rejected, steers the user gave, omissions that were deliberate. Only you hold that last part, and without it the reviewer spends the round relitigating decisions you already made.

2. **Decide.** The reviewer already held the bar for substance; your job is the context it didn't have. Drop a finding when it targets something already tried and rejected, contradicts a steer from the user, or misreads an intent the diff doesn't show. Adopt what survives that, and carry the dropped ones into the next round's dispatch. Read only the hunks you're patching.

3. **Apply.** Make the adopted changes in place.

Stop when a round adopts nothing, or after 3 rounds — whichever first.

**Return** the net: what you adopted, and how many findings you dropped. Your rejections stay here. A deep review may follow, and it is worth more as an independent backstop than as a continuation of this loop, so don't hand it a list of what you already refused.

---
allowed-tools: Bash(find-project.sh*),Read,Edit
description: Converge the working diff to a fixed point — each round a subagent proposes substantial fixes, you adopt or drop them, up to 3 rounds
---

Converge the working diff to a fixed point. A subagent reads the diff and proposes; you decide. Keeping the diff out of your context is the point — never fetch it yourself.

Each round:

1. **Dispatch.** Launch one `converge-reviewer` subagent. Hand it the task file path, the context store path (`~/repos/context/<project>/`, `<project>` via `find-project.sh`), what earlier rounds considered and dropped, and what's already settled: approaches tried and rejected, steers the user gave, omissions that were deliberate. Only you hold that last part, and without it the reviewer spends the round relitigating decisions you already made.

2. **Decide.** The reviewer already held the bar for substance; your job is the context it didn't have. Drop a finding when it targets something already tried and rejected, contradicts a steer from the user, or misreads an intent the diff doesn't show. Adopt what survives that, and carry the dropped ones into the next round's dispatch. Read only the hunks you're patching.

3. **Apply.** Make the adopted changes in place.

Stop when a round adopts nothing, or after 3 rounds — whichever first. Report the net: what you adopted, and how many findings you dropped.

---
description: Converge the working diff to a fixed point in a fork — each round a subagent proposes substantial fixes, you adopt or drop them, up to 3 rounds
context: fork
background: false
agent: general-purpose
argument-hint: <handoff — what the implementer decided, plus any steers since>
---

Converge the working diff to a fixed point. A subagent reads the diff and proposes; you decide. Never fetch the diff yourself; that's what the subagent is for.

**You start cold.** You did not inherit the conversation. The handoff below is all you have of it; everything else you read off disk — the task file, the context store, the diff. The rounds you collect, the hunks you read, and the edits you make die with this fork.

## Handoff

$ARGUMENTS

## Rounds

**Dispatch.** Spawning the reviewer each round is the work you were given, not a way of passing it on. Run the rounds.

**You cannot ask.** The user isn't reachable from here. Decide with the handoff and what's on disk. If the handoff arrived empty, run the rounds anyway and say so in your return — a reviewer with no record of what was already settled will relitigate, and the caller needs to know that's what it got.

**Find.** Run `task-list.sh --status active`. The first two lines are `Tasks: <project>` and `Worker: <worker>`; take the row whose `[worker]` matches. That's your task file. Resolve `<project>` via `find-project.sh` for the context store path.

Each round:

1. **Dispatch.** Launch one `converge-reviewer` subagent. Hand it the task file path, the context store path (`~/repos/context/<project>/`), what earlier rounds considered and dropped, and what the handoff records as settled — decisions the implementer made, approaches it tried and rejected, steers from the user, omissions that were deliberate. Without that last part the reviewer spends the round relitigating what's already decided.

2. **Decide.** The reviewer already held the bar for substance; your job is the context it didn't have. Drop a finding when the handoff records it as tried and rejected, when it contradicts a steer, or when it misreads an intent the diff doesn't show. Adopt what survives that, and carry the dropped ones into the next round's dispatch. Read only the hunks you're patching.

3. **Apply.** Make the adopted changes in place.

Stop when a round adopts nothing, or after 3 rounds — whichever first.

**Return** the net: what you adopted, and how many findings you dropped. Your rejections stay here. A deep review may follow, and it is worth more as an independent backstop than as a continuation of this loop, so don't hand it a list of what you already refused.

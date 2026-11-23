---
description: Implement the agreed plan against the working tree. Reached by the fork that `/forkwc-implement` or `/fork-implement` spawns.
user-invocable: false
---

Implement the agreed plan. Either you inherited the conversation, so the plan, the steers, and everything tried and rejected are already in your hands, or you started cold and the task file and the handoff you were given carry them. Everything you read, run, and rewrite from here dies with this fork. Explore as freely as the work needs; only what you return survives.

Only a fork that `/forkwc-implement` or `/fork-implement` spawns runs this. Reached any other way, stop and invoke `/forkwc-implement` instead — it forks, so the reading, the build output, and the edit churn don't land in the caller's session.

**You cannot ask.** The user isn't reachable from here. When the plan has a gap, look to what you inherited or were handed, the task file, the context store, and the code. If an unresolved choice changes observable behaviour or scope, or is costly to reverse, stop and return the question. Pick everything below that bar.

**You are already a fork.** Don't invoke another fork command (`/fork-*`, `/forkwc-*`) — that spawns a run nobody is waiting on, editing the same tree the caller is about to push. And a background-task notification is not an answer: it carries no user input, whatever you asked before you stopped. Once you have returned you are done — stay stopped, and leave no background command running to wake you.

**Keep your cache warm.** Your prompt cache expires after 5 minutes without a request, and the turn after re-sends your whole context. When something runs longer — a build, a full test suite — don't block on it in one call or stop until its notification wakes you: run it in the background and wait in chunks under 4 minutes (`timeout 230 tail --pid=<pid> -f /dev/null`), checking on it between chunks. A check costs a cached read; a lapsed cache costs a re-send.

@~/.claude/prompts/implement-steps.md

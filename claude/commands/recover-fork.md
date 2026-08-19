---
allowed-tools: Bash(fork-recover.sh*),Bash(git status*),Bash(git diff*),Bash(git log*),Read
description: Reconstruct what a fork was doing when it died
disable-model-invocation: true
---

A fork died before it could return. Its edits are in the working tree, its reasoning is in its transcript, and neither reached the caller. Rebuild the briefing it never delivered.

1. **Find it.** Run `fork-recover.sh`. Every row started and never returned; the status column is only a guess at why. `DEAD` means the owning session is gone. `STALE` means the session lives but the fork's transcript has been silent — usually dead, occasionally just mid-build, so read `IDLE` before deciding. `running` means the transcript is still moving; leave it alone unless the user says otherwise, since forks share the session's pid and cannot be told apart by process. Take the fork the user names, else the most recent non-`running` one. If nothing is listed for this directory, try `--all`.

2. **Read it.** Run `fork-recover.sh <agent-id>`. You get the scratchpad the fork kept, its last 25 actions, and where it stopped. The scratchpad is what it chose to save; the action trail is what it actually did. Trust the trail where they disagree — the scratchpad may predate the last stretch of work.

3. **Check the tree.** Run `git status` and `git diff` (and `git log --oneline` against the base). The fork edited in place, so the work itself is on disk. What the transcript adds is *why*, and what was still ahead.

4. **Report.** Answer the two questions the caller actually has: what landed, and what was left. Specifically — the decisions the fork made and their reasoning, anything it tried and abandoned, the step it died on and whether that step is half-applied, and what remains of the original plan. Flag any edit that looks partial; a fork killed mid-step can leave a file inconsistent, and that is the one thing the diff alone will not tell you.

Do not resume the work in this session. Report, then let the user decide whether to re-dispatch.

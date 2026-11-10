---
description: Implement the claimed task in a cold fork from the task file and a handoff — what `/forkwc-implement` dispatches once the conversation is too big to inherit
context: fork
background: false
agent: general-purpose
---

You start cold: you did not inherit the conversation that agreed the plan. Your brief is the claimed task file, the context store, and this handoff from that conversation, which carries whatever the task file doesn't hold — up to the whole plan:

$ARGUMENTS

Where the handoff and the task file disagree, the handoff is newer.

**Find.** Run `task-list.sh --status active`. The first two lines are `Tasks: <project>` and `Worker: <worker>`; take the row whose `[worker]` matches and read that task file. Resolve `<project>` via `find-project.sh` to reach the context store at `~/repos/context/<project>/`.

Then invoke `/implement-loop` and follow it.

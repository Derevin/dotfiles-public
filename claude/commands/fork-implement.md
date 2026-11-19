---
description: Implement the claimed task in a cold fork from the task file and a handoff — what `/forkwc-implement` dispatches once the conversation is too big to inherit
context: fork
background: false
agent: general-purpose
---

You start cold: you did not inherit the conversation that agreed the plan. Your brief is the claimed task file, the context store, and a handoff from that conversation, which carries whatever the task file doesn't hold — up to the whole plan. The argument's first line is the task's filename; everything after it is the handoff:

$ARGUMENTS

Where the handoff and the task file disagree, the handoff is newer.

**Find.** Read the task file at `~/repos/tasks/<project>/active/<filename>`, `<project>` from `taskania project`; the context store is at `~/repos/context/<p>/`, `<p>` from `find-project.sh`.

Then invoke `/implement-loop` and follow it.

---
description: Record current state in the claimed task file, in a fork that inherits the conversation — a grill flow step, not a mid-work checkpoint
---

Spawn one fork with the Agent tool (`subagent_type: "fork"`) and prompt it: *Invoke `/update-task` and follow it.* Nothing more — it inherits this conversation, so the agreed plan and the steers behind it are already in its hands.

The user can invoke this whenever. Self-invoke only as a step of the `/plan-task` flow — not on your own initiative mid-implementation; commits and the conversation already carry that state.

The git reads, the file re-reads, and the commit die with the fork; you get one line back saying the file is written. Don't write the task file yourself.

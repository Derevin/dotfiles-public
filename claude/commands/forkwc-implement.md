---
description: Implement the agreed plan in a fork that inherits the conversation — the reading, build output, and edit churn die there, only the decisions the diff can't show come back
---

Spawn one fork with the Agent tool (`subagent_type: "fork"`) and prompt it: *Invoke `/implement-loop` and follow it.* Nothing more — it inherits this conversation, so the plan, the steers, and everything tried and rejected are already in its hands.

Dispatching is the work you were given, not a way of passing it on. Don't implement yourself. When the fork returns, relay its decisions.

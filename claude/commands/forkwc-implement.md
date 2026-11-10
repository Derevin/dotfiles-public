---
description: Implement the agreed plan in a fork — inheriting the conversation while it's small, cold from the task file and a handoff once it's big; the reading, build output, and edit churn die there, only the decisions the diff can't show come back
---

Run `session-tokens.sh`: it prints this conversation's size in tokens.

**Under 150000, or the script fails:** spawn one fork with the Agent tool (`subagent_type: "fork"`) and prompt it: *Invoke `/implement-loop` and follow it.* Nothing more — it inherits this conversation, so the plan, the steers, and everything tried and rejected are already in its hands.

**150000 or more:** an inheriting fork would re-read all of it on every turn. Invoke `/fork-implement` instead, passing a handoff as its argument: what this conversation settled that the task file doesn't hold — steers, decisions, approaches tried and rejected, where the relevant code is. Write `none` when the task file already holds it all. When the plan lives only in this conversation, the handoff is the plan.

Dispatching is the work you were given, not a way of passing it on. Don't implement yourself. When the fork returns, relay its decisions.

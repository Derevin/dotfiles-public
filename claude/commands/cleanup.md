---
description: Detach to origin/base and delete current branch
disable-model-invocation: true
context: fork
agent: general-purpose
model: haiku
---

Run `task-cleanup-branch.sh`. It detaches to `origin/<base>` and deletes the current branch. Refuses if PR isn't merged (or branch tip not in base) or if not on a branch.

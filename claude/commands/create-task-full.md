---
allowed-tools: Bash(task-*),Read,Write(~/repos/tasks/**)
description: Create one or more tasks from rough descriptions
disable-model-invocation: true
---

Create tasks from $argument per `~/repos/tasks/CLAUDE.md`. Multiple tasks OK (bullets, numbered, or prose).

Focus: *what* and *why*, not *how* — the implementing agent plans the *how*.

- Detect project via `task-list.sh`. Create `~/repos/tasks/$PROJECT/{todo,active,done,canceled}` if missing.
- Get next ID via `task-next-id.sh <project>` — never scan IDs by hand.
- Ask only when genuinely ambiguous.
- Show created files, await approval, then `task-commit.sh "Add: <slug>"` (single) or `task-commit.sh "Add: <count> tasks for <project>"` (multi).

---
allowed-tools: Bash(taskania *),Read(~/repos/tasks/**)
description: /implement-task with the implement step on Codex
disable-model-invocation: true
---

Run `/implement-task`, below, exactly as if the user had typed `/implement-task $ARGUMENTS --codex`. It can't go through the Skill tool, which refuses a command that disables model invocation.

@~/.claude/commands/implement-task.md

---
allowed-tools: Bash(taskania *),Read(~/repos/tasks/**),Edit(~/repos/tasks/**)
description: /plan-task with the cold read on Codex
disable-model-invocation: true
---

Run `/plan-task`, below, exactly as if the user had typed `/plan-task $ARGUMENTS --codex`. It can't go through the Skill tool, which refuses a command that disables model invocation.

@~/.claude/commands/plan-task.md

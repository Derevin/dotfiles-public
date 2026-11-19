---
allowed-tools: Bash(taskania *),Read
description: Change a task's priority letter
argument-hint: <task> <priority>
disable-model-invocation: true
context: fork
background: false
agent: general-purpose
model: haiku
---

Re-prioritize one task. `$1` is the task, `$2` is the new priority.

Act immediately: no clarifying questions, no approval step, no preamble.

- Both args required. Either missing → say which, change nothing.
- Priority: a bare letter A-Z passes through as-is. Tier words map per the table in `~/repos/tasks/CLAUDE.md` — high → H, normal → N, unimportant/low → U; anything vaguer ("just above normal") picks a letter from that table's in-between ranges, and you name the letter you chose.
- Run `taskania reprioritize <task> <letter>`. It takes a filename or a bare ID directly — for a slug or partial name, resolve the filename with `taskania list` first.
- Never `mv` or `git mv` under `~/repos/tasks/` yourself. The verb refuses a task it can't find or that matches several; re-run it with an exact filename instead.
- Report its rename line, nothing after it. `done/` and `canceled/` are out of scope — priority means nothing there.

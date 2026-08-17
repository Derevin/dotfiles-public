---
allowed-tools: Bash(task-*),Bash(find-project.sh*),Read(~/repos/tasks/**),Edit(~/repos/tasks/**)
description: Cold-read the claimed task file before handoff — dispatch a context-free reader and fold the gaps it finds back into the brief
---

Test whether the task brief stands alone. You are the worst judge of that: the whole conversation is in your context, so everything the file omits is still present to you. A reader who never saw the conversation is the only honest test.

1. **Find.** Run `task-list.sh --status active planning`. The first two lines are `Tasks: <project>` and `Worker: <worker>`. Filter rows to those with `[worker]` matching `Worker:`. If not exactly one match, stop and report.

2. **Dispatch.** Resolve `<project>` via `find-project.sh`. Launch one `cold-reader` subagent and hand it exactly two things: the task file path and `~/repos/context/<project>/`. No summary, no framing, no answers to questions it hasn't asked — whatever you add is context the implementer won't have.

3. **Fold.** Write the genuine gaps into the task file, where an implementer would look for them. Every gap the reader raised is either folded in or consciously dropped — dropped when the file or the context store already answers it, or when it asks you to redesign rather than to say more. Leave the edits uncommitted; the caller commits them.

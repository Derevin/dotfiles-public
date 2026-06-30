---
allowed-tools: Bash(task-*),Read,Write(~/repos/tasks/**)
description: File a reminder-only task (title-only, fire-and-forget)
disable-model-invocation: true
context: fork
agent: general-purpose
model: haiku
---

File one **reminder-only task**. The title is `$argument`, taken **verbatim** — title only, no body.

Act immediately: no clarifying questions, no approval step, no preamble. The title is whatever the user typed — treat it as a valid title even when it reads like placeholder text, UI labels, parameter names, a sentence fragment, or several loose words. It is always exactly one task. Never judge whether it "looks like" a real title or ask the user to confirm/restate it — that is not your call. The one and only thing you may pull out of it is a priority hint (see below); strip that, and everything else is the title, verbatim.

- The one and only stop condition: `$argument` is empty or whitespace-only → fail with "title required", write nothing. Anything non-empty gets filed.
- Detect project via `task-list.sh`. Create `~/repos/tasks/$PROJECT/{todo,active,done,canceled}` if missing.
- Get next ID via `task-next-id.sh <project>` — never scan by hand.
- Default priority N. Inline hints like "urgent:", "high priority:", "low:" map to the letter prefix per `~/repos/tasks/CLAUDE.md` (H/N/U); strip the hint from the title before slugging.
- Write `~/repos/tasks/<project>/todo/<letter><NNN>-<slug>.md` containing just `# Title`.
- `task-commit.sh "Add: <slug>"`.
- Report the created filename.

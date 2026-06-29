---
allowed-tools: Bash(task-*),Read,Write(~/repos/tasks/**)
description: File a reminder-only task (title-only, fire-and-forget)
disable-model-invocation: true
context: fork
agent: general-purpose
model: haiku
---

File one **reminder-only task** from $argument. Title only, no body. No clarifying questions. No approval step.

- If $argument is empty or whitespace-only, fail with "title required" — don't write anything.
- Detect project via `task-list.sh`. Create `~/repos/tasks/$PROJECT/{todo,active,done,canceled}` if missing.
- Get next ID via `task-next-id.sh <project>` — never scan by hand.
- Default priority N. Inline hints like "urgent:", "high priority:", "low:" map to the letter prefix per `~/repos/tasks/CLAUDE.md` (H/N/U); strip the hint from the title before slugging.
- Write `~/repos/tasks/<project>/todo/<letter><NNN>-<slug>.md` containing just `# Title`.
- `task-commit.sh "Add: <slug>"`.
- Report the created filename.

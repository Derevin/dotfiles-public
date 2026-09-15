---
allowed-tools: Bash(task-*),Read,Write(~/repos/tasks/**)
description: File a reminder-only task (title-only, fire-and-forget)
disable-model-invocation: true
context: fork
background: false
agent: general-purpose
model: haiku
---

File one **reminder-only task**. The title is `$argument`, taken **verbatim** — title only, no body.

Act immediately: no clarifying questions, no approval step, no preamble. The title is whatever the user typed — treat it as a valid title even when it reads like placeholder text, UI labels, parameter names, a sentence fragment, or several loose words. It is always exactly one task. Never judge whether it "looks like" a real title or ask the user to confirm/restate it — that is not your call. The one and only thing you may pull out of it is a priority hint (see below); strip that, and everything else is the title, verbatim.

- The one and only stop condition: `$argument` is empty or whitespace-only → fail with "title required", write nothing. Anything non-empty gets filed.
- Detect project via `task-list.sh`. Create `~/repos/tasks/$PROJECT/{todo,planning,planned,active,done,canceled}` if missing.
- Get next ID via `task-next-id.sh <project>` — never scan by hand.
- Default priority N. A priority hint at either end of `$argument` sets the letter and is stripped — with its separator (`:`, `,`, `-`) — before slugging. A hint mid-title is title text, not a hint.
  - Bare letter + "priority"/"prio", either order → that letter verbatim, any A-Z. `K priority, fix-network-checks` files `K012-fix-network-checks.md`; the hint never survives into the slug as `k-prio-…`.
  - Word hints ("urgent", "high priority", "low") → H/N/U per `~/repos/tasks/CLAUDE.md`.
- Write `~/repos/tasks/<project>/todo/<letter><NNN>-<slug>.md` containing just `# Title`.
- `task-commit.sh "Add: <slug>"`.
- Report the created filename.

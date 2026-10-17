---
allowed-tools: Bash(task-*),Read(~/repos/tasks/**),Edit(~/repos/tasks/**)
description: Fast-path a bugfix from todo to a reviewed implementation in one session - frame, recon, one gate, then full implement
disable-model-invocation: true
---

Fast-path a bugfix: a compressed `/plan-task` front-end (frame, recon, one endorsement gate — no grill, no doc writes) flowing straight into the full `/implement-task` back-end, all in one conversation. The plan lives in this conversation, never the task file — nothing is written into it on the happy path. Use this when the change is a bugfix with little design space; the moment real design space appears, bail (step 4) and the task goes back to `todo/` for a proper `/plan-task`.

1. **List.** Run `task-list.sh --status todo`. Skip when an id was given.

2. **Pick.** An id in the arguments (`039`, `039-some-slug`, or the filename `N039-some-slug`) names the task: resolve it to the filename in `todo/`. Otherwise take the first (highest priority). If it has `Depends:`, check those IDs are in done/.

3. **Claim.** Run `task-claim.sh <filename>` — syncs, moves to `planning/`, commits, outputs the task content.

4. **Frame — or bail.** Read the task file. The body is *additional context*, never the spec — an agent likely wrote it and nobody has verified it since.
   - **Reminder-only task** (just `# Title`, no real body): you have zero context. Don't explore the codebase or guess intent — ask the user what the task is about. Their answer is the body; skip the recap.
   - **Task with a real body**: recap it in one paragraph — what it asks and assumes, not a plan — then ask what they want the task to actually be about, and wait. Their answer is authoritative; where it and the file disagree, the file is wrong.

5. **Recon.** Dispatch one `recon` subagent, seeded with the step-4 framing: which files the fix touches, how that area behaves today, prior art for this kind of change, anything in the code contradicting the task's premise. A compact brief, not file dumps. Always run it — locating the cause is most of a bugfix. Targeted lookups still happen inline. Narrate nothing at the user here: recon is a tool call, not a preamble.

6. **Endorse — or bail.** Present the fix in one checkpoint, not an interview: root cause, the change, blast radius.
   - **Go** → step 7.
   - **Bail** when a real design choice surfaces, the cause isn't clear, or the scope is outgrowing a bugfix — you raise it or the user calls it. Write the step-4 framing and the open design question into the task file, run `task-unclaim.sh <filename>` (moves `planning/` → `todo/`, sweeping your edit into the commit), and stop. Tell the user to run `/plan-task` when ready. This is the only path that writes to the task file.

7. **Park and claim in.** Run `task-planned.sh <filename>` (`planning/` → `planned/`, a file move only — nothing written into the file), then `task-claim.sh <filename>` (`planned/` → `active/`, stamps you as worker). The two land as commits `Plan` then `Claim` a second apart — the lifecycle, not a bug. The plan stays in this conversation throughout.

8. **Implement.** Invoke `/forkwc-implement`: the fork inherits this conversation, so it holds the plan without any file snapshot. It implements, proves the tests red-green, and returns the decisions the diff can't show. If it returns a question, the plan had a gap: take it to the user, then dispatch again.

9. **Deep review.** As a backstop, invoke `/fork-review` — the full multi-perspective fan-out, run cold in its own fork with the Apply/Drop/Ask gate applied inside it. Hand it nothing; reviewing the diff on its own terms is what makes it an independent check.

10. **Hand off.** As `/implement-task` closes: filter the review's judgment calls — drop what this conversation already settled, drop what you can now answer yourself. Open with one line of counts (items fixed), then a numbered list of survivors, each `file:line — one-line description — proposed fix — strongest case against`. Then summarize the fix as a whole. Leave it in `active/`; do NOT run `/complete-task` or suggest it. The task stays there until the user says it's done and runs `/complete-task` themselves.

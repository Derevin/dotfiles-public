---
description: Implement the agreed plan in a fork — inheriting the conversation while it's small, cold from the task file and a handoff once it's big; the reading, build output, and edit churn die there, only the decisions the diff can't show come back
---

A `--claude` anywhere in the arguments is a flag; what remains is what this command takes without it (nothing, or a fix round's input). Without it, Codex implements (**Codex** below). With it, or when Codex is near its usage limit, a Claude fork does (**Claude** below).

A cold implementer gets a **handoff**: what this conversation settled that the task file doesn't hold — steers, decisions, approaches tried and rejected, where the relevant code is. Write `none` when the task file already holds it all. When the plan lives only in this conversation, the handoff is the plan.

**Codex.** Codex can't inherit a conversation, so it always starts cold from the task file and the handoff, written straight into its prompt. Run this as a background Bash command (`run_in_background`) from this session, with no fork around it — Codex keeps its churn in its own session store. `<project>` is from `taskania project`:

```bash
{ cat ~/.claude/prompts/codex-implement.md; echo; cat ~/.claude/prompts/implement-steps.md
  printf '\n## Task file\n\n%s\n\n## Handoff\n\n' ~/repos/tasks/<project>/active/<filename>
  cat <<'HANDOFF'
<the handoff>
HANDOFF
} | codex-run.sh -l implement -e xhigh -s bypass
```

The bypass matches a Claude session in a lab, which runs without an OS sandbox too. Its first output line is the run id: note it, and use `fork-recover.sh <id>` to check on the run while it goes — there is no time cap. You are re-invoked when it exits. Exit 0: its final message, in `~/.claude/forks/<id>/scratch/final.md`, is the fork's return — decisions, a question, or local CI red. Exit 75: Codex is near its usage limit and nothing ran; say so in one line and go to **Claude**. Any other non-zero: stop and report the failure to the user with its stderr, and say that a run which died midway may have left edits in the tree. No fallback there: a Claude fork would build on those edits unseen.

A fix round, or a dispatch after the user answered a question the run returned, resumes that Codex session instead of starting cold — it already holds what it read. Pipe in only the new input, again in the background: `codex-run.sh --resume-latest -l implement -e xhigh -s bypass`. Exit 3 means no session to resume: run cold as above, the new input added to the handoff. Exit 75 goes to **Claude**.

**Claude.** Run `session-tokens.sh`: it prints this conversation's size in tokens.

- **Under 150000, or the script fails:** spawn one fork with the Agent tool (`subagent_type: "fork"`) and prompt it: *Invoke `/implement-loop` and follow it.* Nothing more — it inherits this conversation, so the plan, the steers, and everything tried and rejected are already in its hands.
- **150000 or more:** an inheriting fork would re-read all of it on every turn. Invoke `/fork-implement` instead. Its argument is the claimed task's filename on the first line, then the handoff.

Dispatching is the work you were given, not a way of passing it on. Don't implement yourself. When the fork returns, relay its decisions.

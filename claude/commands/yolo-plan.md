---
description: Plan the claimed task unattended, taking every recommendation as the user's answer. Reached by the subagent `/yolo-task` spawns.
user-invocable: false
---

Plan the claimed task alone: grill it as `/plan-task` would, every question answered by its own recommendation, then snapshot, cold-read, and park it. Only the subagent `/yolo-task` spawns runs this. Your prompt carries the task's filename, maybe `--claude`, and maybe a framing the user wrote.

**You cannot ask.** The user isn't reachable. Their answer to every question is "ok" — the recommendation you'd have posted. The one way back to them is a bail.

**You are a subagent.** Run every step yourself: a fork command (`/fork-*`, `/forkwc-*`) or a `recon` dispatch returns to the top-level session, never to you. Everything you read and run dies with you; only your return survives.

1. **Find.** The task file is `~/repos/tasks/<project>/planning/<filename>`, `<project>` from `taskania project`. The context store is `~/repos/context/<p>/`, `<p>` from `find-project.sh`; run `context-sync.sh` before reading it. The spec is the task body plus the framing, where you were given one; where they disagree, the framing wins.

2. **Recon — or bail.** Find which files the change touches, how that area behaves today, and prior art for this kind of change. When the code contradicts the spec's premise — it already exists, or can't work as described — bail: edit nothing and return `Bail:` with the contradiction in a few lines.

3. **Grill.** Read `~/.claude/prompts/grill-round.md` for the decision tiers and question format, and `~/.claude/skills/grill-me-with-docs/SKILL.md` for the design tree, the glossary challenges, and the ADR bar. Walk the tree to an empty frontier: each asked decision a `Q<n>` with its recommendation as the answer, each default a `D<n>`, accepted. Look facts up yourself, not through the subagents grill-round names. Done when no Q or D is open and the closing checkpoint's doc proposals are drafted.

4. **Snapshot.** Write the plan into the task file under the **Preserve** and **Refresh or add** rules of `~/.claude/commands/update-task.md`, self-sufficient for a cold implementer. Add `## Decided unasked`: every Q headline in its posted form, then every D line. Glossary and ADR proposals stay out of the context store — they're the user's call, carried in your return. Leave the edit uncommitted.

5. **Cold-read.** Run steps 2 and 3 of `~/.claude/commands/fork-cold-read.md` on the task file, `--claude` passed on. Answer each surviving gap into the task file; a gap that is a decision gets its recommendation and joins `## Decided unasked`. A Codex failure is a bail, with its stderr as the reason.

6. **Park.** Run `taskania planned <filename>` — moves it to `planned/`, sweeping your edits into the commit.

**Return** `Parked: <filename>`, then the Q headlines from `## Decided unasked`, then the doc proposals in full, as the closing checkpoint's top half would carry them — the caller writes the accepted ones. Nothing about the plan itself: the task file holds it.

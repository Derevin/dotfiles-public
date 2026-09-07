---
description: Cold-read the claimed task file in a fork — dispatch a context-free reader and return the gaps the brief doesn't close
context: fork
background: false
agent: general-purpose
---

Test whether the task brief stands alone. You start cold: you did not inherit the conversation that produced this task, and that is the point — whatever you can't answer from the file and the context store is a gap the implementer will hit too. The reader's report and your triage die with this fork; only the gap list survives.

**You cannot ask.** The user isn't reachable from here.

**You cannot answer either.** The caller holds the conversation and closes the gaps you find. Don't write an answer into the file, don't guess one into your return, and don't drop a gap because it feels inferable — inferable to you is not inferable to someone who never saw the plan.

1. **Find.** Run `task-list.sh --status active planning`. The first two lines are `Tasks: <project>` and `Worker: <worker>`. Filter rows to those with `[worker]` matching `Worker:`. If not exactly one match, stop and report.

2. **Dispatch.** Resolve `<project>` via `find-project.sh`. Launch one `cold-reader` subagent and hand it exactly three things: the task file path, `~/repos/context/<project>/`, and the report path below. No summary, no framing, no answers to questions it hasn't asked — whatever you add is context the implementer won't have.

   The Agent tool hands back an agentId, not a report. Give the reader a report path — `reports/gaps.md` under your scratchpad — and require its final output be that path alone: what a child returns lands in the top-level session, never in the fork that dispatched it. Do your own step-3 reading first, then collect with `fork-collect.sh <reports-dir> <agentId>:gaps.md`, which waits for its registry entry to close and prints what it wrote, giving up rather than hanging if it never does. You are not reliably notified when it finishes and have no `TaskOutput`, so sleeping, polling the reader's transcript, or checking `ListAgents` instead hangs until the user kills you.

3. **Triage.** Read the task file and the context store yourself. Drop a gap when either already answers it, or when it asks for a redesign rather than for more words. What's left is genuine.

4. **Return.** The surviving gaps as a numbered list, each `<what an implementer can't determine> — <the section of the file where the answer belongs>`. Nothing else: no recap of the plan, no summary of what the file does cover, no praise for what's already clear. If nothing survives triage, say so in one line.

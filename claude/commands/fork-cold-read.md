---
description: Cold-read the claimed task file in a fork — dispatch a context-free reader and return the gaps the brief doesn't close
context: fork
background: false
agent: general-purpose
model: opus  # /implement-task's model: the read stands in for the implementer
argument-hint: <task-filename> [--codex]
---

Test whether the task brief stands alone. You start cold: you did not inherit the conversation that produced this task, and that is the point — whatever you can't answer from the file and the context store is a gap the implementer will hit too. The reader's report and your triage die with this fork; only the gap list survives.

**You cannot ask.** The user isn't reachable from here.

**You cannot answer either.** The caller holds the conversation and closes the gaps you find. Don't write an answer into the file, don't guess one into your return, and don't drop a gap because it feels inferable — inferable to you is not inferable to someone who never saw the plan.

**You are already a fork.** Don't invoke another fork command (`/fork-*`, `/forkwc-*`) — that spawns a run nobody is waiting on, editing the same tree the caller is about to push. And a background-task notification is not an answer: it carries no user input, whatever you asked before you stopped. Once you have returned you are done — stay stopped, and leave no background command running to wake you.

1. **Find.** The argument is the task's filename. A `--codex` anywhere in the arguments is a flag, not part of it, and sends the read to Codex (step 2). No filename given: stop and report.

2. **Dispatch.** The task file is `~/repos/tasks/<project>/planning/<filename>`, `<project>` from `taskania project`; the context store is `~/repos/context/<p>/`, `<p>` from `find-project.sh`. Launch one `cold-reader` subagent and hand it exactly three things: the task file path, the context store, and the report path below. No summary, no framing, no answers to questions it hasn't asked — whatever you add is context the implementer won't have.

   The Agent tool hands back an agentId, not a report. Give the reader a report path — `reports/gaps.md` under your scratchpad — and require its final output be that path alone: what a child returns lands in the top-level session, never in the fork that dispatched it. Do your own step-3 reading first, then collect with `fork-collect.sh <reports-dir> <agentId>:gaps.md`, which waits for its registry entry to close and prints what it wrote, giving up rather than hanging if it never does. You are not reliably notified when it finishes and have no `TaskOutput`, so sleeping, polling the reader's transcript, or checking `ListAgents` instead hangs until the user kills you.

   **With `--codex`**, Codex reads in place of the `cold-reader` subagent, in one foreground Bash call (timeout 600000 ms) with the same three things and the `cold-reader` agent's own instructions, its frontmatter stripped:

   ```bash
   { awk 'n >= 2; /^---$/ && n < 2 { n++ }' ~/.claude/agents/cold-reader.md
     printf '\nTask file: %s\nContext store: %s\nReport path: %s\n\nYour sandbox is read-only, so write no file: your final message is the report, saved to that path for you.\n' \
         <task-file> <context-store> <report-path>
   } | timeout 540 codex-run.sh -l cold-read -e low -s read-only -o <report-path>
   ```

   It returns when Codex is done, so there is nothing to collect: read the report and go on to step 3. A non-zero exit is the return: stop and report the failure with its stderr. The caller chose Codex, so never fall back to the `cold-reader` subagent.

3. **Triage.** Read the task file and the context store yourself. Drop a gap when either already answers it, or when it asks for a redesign rather than for more words. What's left is genuine.

4. **Return.** The surviving gaps as a numbered list, each `<what an implementer can't determine> — <the section of the file where the answer belongs>`. Nothing else: no recap of the plan, no summary of what the file does cover, no praise for what's already clear. If nothing survives triage, say so in one line.

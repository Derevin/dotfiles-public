---
allowed-tools: Bash(cc-review-diff.sh*),Read
description: Review current branch changes (effort=max)
disable-model-invocation: true
effort: max
---

Review the current branch's diff against its merge base. Works offline — no PR needed.

## Steps

1. **Gather changes.** Run exactly `cc-review-diff.sh` (no arguments, no fallbacks, no shell wrappers) to get the commit log and full diff. The script handles merge-base discovery internally.

1a. **Read project domain docs.** Resolve `<project>` via `find-project.sh`. If `~/repos/context/<project>/CONTEXT.md` (or `CONTEXT-MAP.md` + per-context files) exists, read it and note any terms the diff renames, repurposes, or contradicts. If `adr/` exists, skim for decisions the diff might violate. Hold these findings for step 3. Skip silently if the context store doesn't exist.

2. **Dispatch subagent reviewers.** Launch all five in parallel, passing each the full output:

   - **code-quality-reviewer** — readability, naming, error handling, dead code, code smells
   - **system-architecture-reviewer** — design patterns, coupling, separation of concerns, API design
   - **performance-reviewer** — algorithmic complexity, unnecessary allocations, hot paths, caching
   - **test-coverage-reviewer** — missing tests, edge cases, test quality, untested error paths
   - **security-code-reviewer** — injection, auth issues, secrets, unsafe operations, input validation

   Instruct each to only report noteworthy findings. No praise, no minor style nits. Omit feedback on pre-existing code not affected by the branch changes.

3. **Synthesize.** Review all subagent feedback. Post only findings you also deem noteworthy. Group by file, quote relevant diff context. Include any domain-term drift or ADR violations from step 1a. End with a short summary and suggested next steps.

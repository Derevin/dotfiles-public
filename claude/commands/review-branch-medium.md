---
allowed-tools: Bash(cc-review-diff.sh*),Read
description: Review current branch changes (effort=medium)
effort: medium
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

   Additionally, hand the **code-quality-reviewer** this smell baseline to screen the diff against (Fowler, *Refactoring* ch.3) — beyond its generic brief. Each is a judgement call, not a hard rule: a documented repo or CONTEXT.md convention overrides it, and skip anything tooling already enforces. Name the smell and quote the hunk.

   - **Mysterious Name** — a function/variable/type whose name doesn't reveal what it does or holds.
   - **Duplicated Code** — the same logic shape in more than one hunk or file.
   - **Feature Envy** — a method reaching into another object's data more than its own.
   - **Data Clumps** — the same few fields/params repeatedly travelling together.
   - **Primitive Obsession** — a primitive or string standing in for a domain concept that deserves a type.
   - **Repeated Switches** — the same switch/if-cascade on the same type recurring across the change.
   - **Shotgun Surgery** — one logical change forcing scattered edits across many files.
   - **Divergent Change** — one module edited for several unrelated reasons.
   - **Speculative Generality** — abstraction, params, or hooks added for needs the change doesn't have.
   - **Message Chains** — long `a.b().c().d()` navigation the caller shouldn't depend on.
   - **Middle Man** — a unit that mostly just delegates onward.
   - **Refused Bequest** — a subclass/implementer ignoring or overriding most of what it inherits.

3. **Synthesize.** Review all subagent feedback. Post only findings you also deem noteworthy. Group by file, quote relevant diff context. Include any domain-term drift or ADR violations from step 1a. End with a short summary and suggested next steps.

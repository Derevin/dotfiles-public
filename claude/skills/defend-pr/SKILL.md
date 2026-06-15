---
name: defend-pr
description: Produce a 3-bullet defense of the implementation choice in pending changes plus an exact blast-radius assessment, framed for expert reviewers. Use when user is about to submit a PR to senior engineers, asks to defend a design, justify an implementation, or wants blast radius / impact of pending changes.
disable-model-invocation: true
---

I'm submitting this branch as a PR to senior engineers — experts in the domain.

Read the diff first (`git diff origin/main...HEAD`). Grep callers of changed signatures before writing anything.

Resolve `<project>` via `find-project.sh`. If `~/repos/context/<project>/adr/` exists, scan ADRs whose subject overlaps the diff (architectural shape, integration patterns, tech lock-in, deliberate deviations). Reference relevant ones in the defense — either "aligns with ADR-NNNN <slug>" or, if the change deviates, name the ADR and justify the deviation explicitly. Skip silently if no ADRs exist.

Then give me:

**3-bullet defense.** Why *this* implementation. Each bullet names the alternative considered and the constraint that ruled it out. No filler — every bullet must survive a senior reviewer asking "so what?"

**Blast radius.** Be exact:
- Files/functions touched.
- Callers of changed signatures.
- Externally-visible behavior changes (returns, errors, perf, ordering).
- Compatibility (API, on-disk, wire, config, env).
- Implicit dependents (tests, scripts, CI, docs, downstream).
- Risk surfaces (concurrency, security, error paths).

If a category doesn't apply, say "none" — don't omit.

---
name: retro
description: "Retrospective on a finished coding session: proposes environment improvements (navigation, checks, steering, reviewer coverage, tool economy) for the next run."
disable-model-invocation: true
---

You are running a **retrospective**: mining a finished coding session for improvements to the agent's *environment*, not its code. The output is a list of concrete changes, each tied to a moment in the session, ranked by severity, for the user to accept one by one.

## Steps

1. Call the Skill tool with `write-a-skill` — any steering text you propose follows that style guide.

2. Read the session's primary sources. Default to the current session; if the user names another, find its transcript under `~/.claude/projects/`. Every finding cites the moment that motivates it: quote it, don't paraphrase a vibe.

3. Resolve `<project>` with `find-project.sh`, then run `context-sync.sh` before reading the context store at `~/repos/context/<project>/`.

4. Scan for candidates across the categories below.

5. Present them ranked by severity. Each one: what happened (with the citation), the fix, and where it lands (which file, agent, or check). Wait for the user to accept, defer, or drop each.

## Categories

- **Navigation** — did finding the right file take too long, or was there hidden coupling between files? Propose a **navigation pointer** in the narrowest CLAUDE.md layer or context doc that covers it. _When_ the session burned time locating something.
- **Automated checks** — a mistake a linter, typecheck, test, pre-commit hook, or CI job could have caught. Read the repo's own check command first (its build-tool scripts, `.pre-commit-config`, CI workflow) so an existing-but-unwired or silently-broken check is the finding, not a reinvention. A repo with no **guardrail** at all is itself a finding. _When_ the agent made a mechanically-catchable mistake.
- **Coding standards** — classify before you act. A **mechanical** violation (a fixed pattern, a banned API, an import or file-location rule) gets a deterministic check — a linter rule, a pre-commit hook, a CI job — never prose. Reserve a CLAUDE.md rule or a **reviewer agent** brief for genuine **judgement calls** (cross-file consistency, "matches the surrounding style"). Default to the check. _When_ a rule kept getting broken, or review let one through.
- **Reviewer coverage** — should one of the `/review-branch` agents get a new rule, or is a whole dimension unreviewed and owed a new reviewer? Standards sit on the **reviewer agent**, which reads a diff under the least **context pressure**, never on the implementer. _When_ a class of defect reached the branch.
- **Steering bloat** — a CLAUDE.md line (global or project) that's a **no-op** the agent already obeys, has gone stale, or belongs in a doc behind a pointer. Bloat buries the rules that bite. _When_ a steering file is large, or a rule didn't fire.
- **Context store** — a term that caused confusion earns a `CONTEXT.md` glossary entry; a decision relitigated mid-session earns an ADR. Durable knowledge capture past the environment is `promote-memory`'s job: hand off, don't duplicate. _When_ vocabulary or a settled decision churned.
- **Tool economy** — an expensive or token-noisy tool or script call worth streamlining. _When_ a call was slow or flooded the context.
- **Information access** — a crucial fact the agent couldn't reach: teed dev-server logs, read-only access to a service, a value locked behind a dashboard. _When_ missing information blocked progress.

## Reference

### Where a finding lands

- Mechanical rule → a check. Prose can't enforce what a linter, hook, or CI job enforces for free.
- Judgement call → the narrowest steering layer that covers it (module CLAUDE.md, then project, then global `~/.claude/CLAUDE.md`), or a **reviewer agent**'s brief.
- Durable term, decision, or recipe → `promote-memory`'s targets (`CONTEXT.md`, `adr/`, a done task). retro proposes the *environment* change; `promote-memory` carries the *knowledge*. Keep each in one place.

### Implementation vs review

Work runs in two stages under different **context pressure**. The implementer explores, writes, and debugs — the most pressure. The reviewer receives a diff — the least. So standards enforcement belongs on the reviewer (the `/review-branch` agents), never loaded onto the implementer, where it competes with the build for attention.

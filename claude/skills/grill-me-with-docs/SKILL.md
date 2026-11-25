---
name: grill-me-with-docs
description: Grilling session that challenges your plan against the existing domain model, sharpens terminology, and updates documentation (GLOSSARY.md, ADRs) inline as decisions crystallise. Use when user wants to stress-test a plan against their project's language and documented decisions.
---

Interview me relentlessly about every decision that meets the bar for a question until we reach a shared understanding. Map this as a **design tree** where each decision branches into the decisions that depend on it.

Work the tree in **rounds**. The **frontier** is every question or default whose prerequisites are settled. Post all of them in one round, questions first. Recompute the frontier after each reply.

@~/.claude/prompts/grill-round.md

Post the closing checkpoint once the frontier is empty and all questions and defaults are settled. Glossary and ADR proposals belong in it. Wait for me to confirm we have reached a shared understanding before enacting the plan.

## Domain awareness

Domain knowledge lives **outside** the project repo at `~/repos/context/<project>/`. Resolve `<project>` with `~/repos/dotfiles/scripts/find-project.sh` (or `find-project.sh` on PATH).

If `~/repos/context/` does not exist, stop and tell the user.

Run `context-sync.sh` before reading any context files so you don't grill against stale terminology.

During codebase exploration, also look at the project's existing documentation under `~/repos/context/<project>/`.

### File structure

Single-context project (default):

```
~/repos/context/<project>/
├── GLOSSARY.md
└── adr/
    ├── 0001-event-sourced-orders.md
    └── 0002-postgres-for-write-model.md
```

Multi-context project (only when one `GLOSSARY.md` grew unwieldy and you split it):

```
~/repos/context/<project>/
├── GLOSSARY-MAP.md
├── adr/                          ← system-wide decisions
├── ordering/
│   ├── GLOSSARY.md
│   └── adr/                      ← context-specific decisions
└── billing/
    ├── GLOSSARY.md
    └── adr/
```

`GLOSSARY-MAP.md` records each context's external dir and its in-repo path — see [GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md).

Create files lazily — only when you have something to write. If no `GLOSSARY.md` exists for the project, create `~/repos/context/<project>/GLOSSARY.md` when the first term is resolved. If no `adr/` exists, create it when the first ADR is needed.

Don't pre-sort. Start single-context. Split into `GLOSSARY-MAP.md` + per-context dirs only when the single `GLOSSARY.md` grows unwieldy.

When the project is multi-context, infer which one the current conversation relates to from the files and modules being discussed. If unclear, ask.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `GLOSSARY.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update GLOSSARY.md inline (optional)

If a term gets clearly resolved mid-session and you're confident it belongs in the glossary, capture it right then via the format in [GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md). Don't force it — the mandatory checkpoint below catches anything missed.

`GLOSSARY.md` should be totally devoid of implementation details. Do not treat `GLOSSARY.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Before handoff to implementation (mandatory)

Before the grilling can end — before the user can sensibly say "go" — STOP and post one checkpoint message. Both halves in one go, split by a rule:

```
<proposed GLOSSARY.md diffs, proposed ADR drafts>

---

<the plan as it now stands, whole>
```

Top half: every term sharpened, introduced, or pinned down this session; every decision that meets the ADR bar (see below). If nothing qualifies, say so explicitly ("no glossary updates, no ADRs") — don't silently skip.

Bottom half: the plan, including accepted defaults, for the user to call final or reopen.

One reply settles both — yes/no per doc item, plus the plan's verdict. Write the accepted docs, commit via `context-commit.sh` (format below). A reopened plan doesn't hold up the doc writes; the terms already resolved stand.

Then stop and ask explicitly whether to start implementation. A final plan is not approval to implement — separate steps.

### ADR bar

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

### Commit each change

After each meaningful write (term added/updated, ADR created, split), commit and push via `context-commit.sh "<message>"`:

- term added/updated: `<project>: term — <term>`
- ADR created: `<project>: adr — <slug>`
- split: `<project>: split — <context>`

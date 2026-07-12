---
name: grill-me-with-docs
description: Grilling session that challenges your plan against the existing domain model, sharpens terminology, and updates documentation (CONTEXT.md, ADRs) inline as decisions crystallise. Use when user wants to stress-test a plan against their project's language and documented decisions.
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing. Asking multiple questions at once is bewildering.

If a *fact* can be found by exploring the codebase, look it up rather than asking me. The *decisions*, though, are mine — put each one to me and wait for my answer.

Do not enact the plan until I confirm we have reached a shared understanding.

## Domain awareness

Domain knowledge lives **outside** the project repo at `~/repos/context/<project>/`. Resolve `<project>` with `~/repos/dotfiles/scripts/find-project.sh` (or `find-project.sh` on PATH).

If `~/repos/context/` does not exist, stop and tell the user.

Run `context-sync.sh` before reading any context files so you don't grill against stale terminology.

During codebase exploration, also look at the project's existing documentation under `~/repos/context/<project>/`.

### File structure

Single-context project (default):

```
~/repos/context/<project>/
├── CONTEXT.md
└── adr/
    ├── 0001-event-sourced-orders.md
    └── 0002-postgres-for-write-model.md
```

Multi-context project (only when one `CONTEXT.md` grew unwieldy and you split it):

```
~/repos/context/<project>/
├── CONTEXT-MAP.md
├── adr/                          ← system-wide decisions
├── ordering/
│   ├── CONTEXT.md
│   └── adr/                      ← context-specific decisions
└── billing/
    ├── CONTEXT.md
    └── adr/
```

`CONTEXT-MAP.md` records each context's external dir and its in-repo path — see [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

Create files lazily — only when you have something to write. If no `CONTEXT.md` exists for the project, create `~/repos/context/<project>/CONTEXT.md` when the first term is resolved. If no `adr/` exists, create it when the first ADR is needed.

Don't pre-sort. Start single-context. Split into `CONTEXT-MAP.md` + per-context dirs only when the single `CONTEXT.md` grows unwieldy.

When the project is multi-context, infer which one the current conversation relates to from the files and modules being discussed. If unclear, ask.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update CONTEXT.md inline (optional)

If a term gets clearly resolved mid-session and you're confident it belongs in the glossary, capture it right then via the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md). Don't force it — the mandatory checkpoint below catches anything missed.

`CONTEXT.md` should be totally devoid of implementation details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Before handoff to implementation (mandatory)

Before the grilling can end — before summarizing the plan, before the user can sensibly say "go" — STOP and run a checkpoint:

1. List every term sharpened, introduced, or pinned down during the session. Show proposed `CONTEXT.md` diffs.
2. List every decision that meets the ADR bar (see below). Show proposed ADR drafts.
3. Get yes/no per item. Write the accepted ones, commit via `context-commit.sh` (format below).
4. Stop. Ask the user explicitly whether to start implementation. Approving the doc writes is not approval to implement — they're separate steps.

If nothing qualifies, say so explicitly ("no glossary updates, no ADRs") — don't silently skip.

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

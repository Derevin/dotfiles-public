---
name: promote-memory
description: Triage auto-memory toward pristine — purge most entries, promote the rare durable ones into CLAUDE.md, CONTEXT.md, ADR, or done task.
disable-model-invocation: true
---

# Promote memory to project docs

Auto-memory is instance-local — sessions on another machine, worktree, or surface never see it. This skill partly exists to serve those instances: durable knowledge must move into shared, git-synced files. Ideal outcome of a run: memory left **pristine** — nothing lingering that's captured (or belongs) elsewhere.

## Scope

Read all memory files in the current project's memory directory (path appears in the auto-memory section of the system prompt). Memory entries there can be of any type — `user`, `feedback`, `project`, `reference`. All types are eligible candidates; type informs the natural promotion target.

There are four destination kinds:

1. **CLAUDE.md** (global `~/.claude/CLAUDE.md`, project root, or module subdir) — rules, conventions, gotchas, preferences. In-repo.
2. **`~/repos/context/<project>/CONTEXT.md`** — domain glossary terms / project-specific vocabulary. Out-of-repo, separate git repo.
3. **`~/repos/context/<project>/adr/NNNN-slug.md`** — architectural decisions meeting the ADR bar (hard to reverse + surprising + real trade-off). Out-of-repo.
4. **`~/repos/tasks/<project>/done/<letter><NNN>-<slug>.md`** — archived investigations, troubleshooting logs, completed incident context. Out-of-repo.

Resolve `<project>` with `find-project.sh` (on PATH). See [CONTEXT-FORMAT.md](../grill-me-with-docs/CONTEXT-FORMAT.md) and [ADR-FORMAT.md](../grill-me-with-docs/ADR-FORMAT.md) for context-store formats; `~/repos/tasks/CLAUDE.md` for task naming, priority letters, commit messages.

If `~/repos/context/` doesn't exist, skip destinations 2/3 silently. If `~/repos/tasks/` doesn't exist, skip destination 4. Don't prompt the user to set them up — this skill is the wrong moment for that.

## Discover existing destinations

Run `context-sync.sh` first so duplicate detection sees the current state of CONTEXT.md and ADRs.

For duplicate detection, scan everything a candidate might already live in:

- All CLAUDE.md files: `find` from project root + `~/.claude/CLAUDE.md`
- `~/repos/context/<project>/CONTEXT.md` (or `CONTEXT-MAP.md` + per-context `CONTEXT.md` when split)
- All ADRs in `~/repos/context/<project>/adr/*.md` (and per-context `adr/` dirs when split)
- `~/repos/tasks/<project>/done/*.md`

## Classify each memory file

Default is **purge only** — most memories are spent or thin and earn no promotion. A doc target (CLAUDE.md / CONTEXT.md / ADR) takes an entry only when it adds genuine value not yet captured anywhere; done tasks carry no such bar — archive into them freely.

For each memory file, decide target kind:

- **Purge only** (default) — already captured in some destination, value spent, or too thin to earn doc space. Delete, no edit.
- **CLAUDE.md** — rule, preference, convention, gotcha. Forward-looking ("do this", "don't do that"). `user`/`feedback` usually → global CLAUDE.md (cross-project, cross-PC via dotfiles symlink); `project` → project root or module subdir CLAUDE.md.
- **CONTEXT.md** — defines / clarifies / disambiguates a domain term, names a project-specific concept, pins vocabulary. Tight one-sentence "what it IS" definitions, no rationale.
- **adr/** — decision meeting all three ADR bar criteria: hard to reverse, surprising without context, real trade-off. Architecture shape, integration patterns, tech lock-in, deliberate deviations.
- **Done task** — completed investigation, incident timeline, troubleshooting log, or reusable recipe/technique tied to a specific event. Backward-looking ("here's what was tried" / "here's what worked"). `project`-type memories with status/timeline headers and `reference`-type how-to procedures both fit here when the body has archival value but no forward-looking rule worth promoting elsewhere. When unsure whether a body deserves keeping at all, archiving here beats a doc promotion.
- **Keep as memory** — ephemeral state (active work, deadlines), pointers to fast-changing external systems, or rich Why context that wouldn't survive any target file's style.

Disambiguation:
- **CLAUDE.md vs done task** — CLAUDE.md is forward-looking behavior; done task is backward-looking archive of an event or recipe.
- **CLAUDE.md vs CONTEXT.md** — CLAUDE.md is *how to behave*; CONTEXT.md is *what things mean*. "Use `task-commit.sh`, not raw git" → CLAUDE.md. "An **Order** is a customer's request to purchase" → CONTEXT.md.

## Propose

Present each promote candidate with:

- source memory file
- target file (proposed via the heuristic; user can override)
- **target location** within that file — for CLAUDE.md, existing section by topic match or new section name; for CONTEXT.md, the `## Language` subsection (or relationships); for ADR, the proposed `NNNN-slug.md` filename; for done task, the proposed `<letter><NNN>-<slug>.md` filename (get next ID via `task-next-id.sh <project>`). User must confirm or override.
- terse target-style prose to insert — rewrite memory body in the host file's voice:
  - CLAUDE.md: telegraphic, no Why/How structure
  - CONTEXT.md: one-sentence "what it IS", no rationale
  - ADR: 1–3 sentences total
  - Done task: preserve memory body largely as-is (it's archival); strip frontmatter, add `## Resolution` noting it was archived from memory
- purge memory file after promotion? Default **purge** for every target — the content now lives where all instances see it, and purging is what leaves memory pristine. User overrides to keep (e.g. rationale still wanted at hand next session).

For each purge-only, present:

- source memory file
- why it earns no promotion (where the duplicate lives, or what makes it spent/thin)
- recommend purge

Wait for user confirmation. User can skip items, override target file, change section, flip purge/keep.

## Apply

1. **CLAUDE.md edits** — write via Edit. Do NOT commit. Leave commit to the user (they handle via `/pushcommit` or manually).
2. **Context-store edits (CONTEXT.md / ADR)** — write via Edit/Write. Commit each via `context-commit.sh "<message>"` immediately after the write:
   - term added/updated: `<project>: term — <term>`
   - ADR created: `<project>: adr — <slug>`
3. **Tasks repo edits** — write via Write. Commit via `task-commit.sh "Done: <slug> [<worker>]"` (`<worker>` = worktree suffix or `main`). Multiple files per run: a single `task-commit.sh` call with a freeform message ("Archive X + Y") since the script does `git add -A` — splitting requires raw git.
4. **Purges** — delete the memory file AND remove its line from MEMORY.md index. Leave commit to the user.

Report changes grouped: CLAUDE.md edits, context-store edits (with commit hashes), tasks edits (with commit hashes), purges.

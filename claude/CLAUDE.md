## Style

Sacrifice grammar for being concise.

Every prose draft gets a trim pass: could this say the same in half the words? Cut whole sentences before reformulating any — one that rephrases the sentence before it, a frame with no claim behind it ("worth dwelling on") — grammar-tightening pays 5%, not 50%. Then re-ask. Stop when a cut would drop a claim, not just words; a claim stated twice is one claim.

Don't open a sentence with a lowercase symbol/path/identifier (`modules/gui/...`, `foo()`) — rephrase so it starts with a capital letter; a lowercase start looks malformed.

Comments: sparse — only the surprising, the non-obvious, or the *why*; never narrate the code below. No history-relative phrasing ("previously", "originally", "used to", "now instead of") — describe the present, standalone. No ADR/CONTEXT.md citations — the store is outside the repo, so state the fact instead.

## Git

Commits: title-only when possible, max 50 chars. Capitalize first word. If a body is needed, keep it brief. No caveat bodies about deferred/related/out-of-scope work.

Optional `Tag: Message` format only when a tag adds clarity. Single tag prefix only — `Recovery: X`, not `GUI: Recovery: X`. Tag = one word naming what changed, not which file (`Tasks:`, not `Global CLAUDE:`). Use "Fix" only for genuine bugs; refactors take neutral verbs (Load, Reorder, Move, Use).

Before opening a PR, draft title and body per the `pr-body` skill, show them, and wait for user's OK. Don't run `gh pr create` until they approve.

Branch off `origin/main` (or `origin/master`), not local.

Don't assert scope superlatives ("last/only/first X") in PR or commit bodies without verifying — grep to confirm it holds; if unsure, drop the superlative and state only the local fact.

Amend HEAD for review fixes (`git commit --amend --no-edit`); don't fixup+autosquash when target is HEAD. Don't auto force-push after amend — wait for explicit direction.

After splitting or extracting work into its own PR, stop: leave HEAD on the split branch, don't restack the parent or branch the remainder until that PR merges. After splitting an orthogonal fix, don't auto-switch back.

Skip the rebuild/test cycle when a rebase resolution is purely mechanical (list ordering, formatting).

## Data processing

Prefer built-in tools (Read, Grep, Glob) and CLI tools (jq, sort, cut, tr, uniq, diff, comm, column, paste) over `python`/`uv run python` for data parsing.

## Bash

Just run commands directly — the working directory is already set. No `cd dir && cmd`, no `git -C`, no `git --git-dir`, no path workarounds. Run `pwd` first if unsure. If you genuinely need a different directory, run `cd` as a separate command first — but never into another worktree; read it with `git show <ref>:<path>`.

`pgrep -f` / `pkill -f` match the matcher's own command line — `pgrep -f ctest` in a shell whose argv contains "ctest" never goes false. Match exact name (`-x`), or exclude `$$`.

## Output handling

Large command output: dump once to a file — `/tmp` unless you have a better place (`> /tmp/<name>.out 2>&1`) — re-read slices via `Read` offset/limit. Don't rerun command with different ranges.

A background fork's `<new-diagnostics>` lag the tree it just edited — they index its mid-flight states, so a flood right after a fork lands is usually stale. Verify with one build/test run, not the diagnostics.

## API errors

The API is flaky — retry a call that trips an API error, up to 10 attempts, before giving up.

## Red-green workflow

When fixing bugs or implementing new features in a project that has tests: write a failing test first, run it and verify it fails, then make the change, then verify the test passes.

## Tasks

Task data lives in `~/repos/tasks/` — personal, not shared with collaborators. Don't reference task IDs or contents in PRs, commits, or any external comms. See its CLAUDE.md for conventions (naming, priorities, format, claiming). Don't auto-complete on PR merge — user's call.

Listing tasks and every state change (claim/complete/cancel/move) go through `taskania <verb>`. **Never `git mv` or `mv` task files by hand** — the verbs commit and push; a manual move leaves the repo out of sync with origin.

## Context store

Per-project domain knowledge — a glossary (`CONTEXT.md`) and decision records (`adr/`) — lives in `~/repos/context/<project>/`, external to the code repo (keeps it out of possibly-public repos). Read before planning non-trivial work; `context-sync.sh` first to avoid stale reads. Resolve `<project>` with `find-project.sh` — not always the dir basename.

After editing, commit and push via `context-commit.sh "<project>: term|adr — …"`. Never run Git by hand in the store.

## .claude directory

When deleting inside `.claude/`, target the specific file — never `rm -rf .claude/`.

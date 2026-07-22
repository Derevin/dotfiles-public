## Style

Sacrifice grammar for being concise.

Don't open a sentence with a lowercase symbol/path/identifier (`modules/gui/...`, `foo()`) — rephrase so it starts with a capital letter; a lowercase start looks malformed.

Comments: sparse — don't write one that just narrates the code below it; reserve them for the surprising, the non-obvious, or the *why*.

No history-relative comments — "previously…", "originally", "the original X", "used to", "now instead of" mean nothing to a reader who never saw the old code. Describe the present, standalone. Such phrasing is usually leftover editing scaffolding — delete it.

## Git

Never add Co-Authored-By, Signed-off-by, or any other trailer attributing Claude to git commits.

Commits: title-only when possible, max 50 chars. Capitalize first word. Optional `Tag: Message` format only when a tag adds clarity. If a body is needed, keep it brief. No caveat bodies about deferred/related/out-of-scope work. Sacrifice grammar for brevity.

PR descriptions: as short as the change allows. Plain text, no headers/checklists/bullets. Why, not what — never restate the diff. No test plans, no "This PR..." preamble, no background already in the linked issue. Every sentence must earn its place; if one is enough, stop there.

To swap two commits in a non-interactive rebase: `GIT_SEQUENCE_EDITOR='sed -i "1{h;d}; 2G"' git rebase -i HEAD~2`

Branch off `origin/main` (or `origin/master`), not local.

Single tag prefix only — `Recovery: X`, not `GUI: Recovery: X`. Tag = one word naming what changed, not which file (`Tasks:`, not `Global CLAUDE:`). Use "Fix" only for genuine bugs; refactors take neutral verbs (Load, Reorder, Move, Use).

Trim PR bodies hard — usually one sentence stating the why. Drop tail clauses, impact numbers, "so that…" purpose tails, named-pattern references. When user edits a PR body, apply exactly the requested change — never reintroduce previously dropped text.

Don't assert scope superlatives ("last/only/first X") in PR or commit bodies without verifying — grep to confirm it holds; if unsure, drop the superlative and state only the local fact.

Amend HEAD for review fixes (`git commit --amend --no-edit`); don't fixup+autosquash when target is HEAD. Don't auto force-push after amend — wait for explicit direction.

After splitting a commit into its own PR, leave HEAD on the split branch and don't restack the parent until the split PR merges. After splitting an orthogonal fix, don't auto-switch back.

Skip the rebuild/test cycle when a rebase resolution is purely mechanical (list ordering, formatting).

When asked to "extract X first" into a separate PR, stop after creating that PR — don't preemptively branch the remainder.

Don't `cd` into other worktrees; use `git show <ref>:<path>` instead.

## Data processing

Prefer built-in tools (Read, Grep, Glob) and CLI tools (jq, sort, cut, tr, uniq, diff, comm, column, paste) over `python`/`uv run python` for data parsing.

## Bash

Just run commands directly — the working directory is already set. No `cd dir && cmd`, no `git -C`, no `git --git-dir`, no path workarounds. Run `pwd` first if unsure. If you genuinely need a different directory, run `cd` as a separate command first.

Don't use `$(...)` command substitution — each subshell is a separate permission prompt. Hardcode values (e.g. `-j4`, not `-j$(nproc)`).

## Output handling

Large command output: dump once to `/tmp` (`> /tmp/<name>.out 2>&1`), re-read slices via `Read` offset/limit. Don't rerun command with different ranges.

## Red-green workflow

When fixing bugs or implementing new features in a project that has tests: write a failing test first, run it and verify it fails, then make the change, then verify the test passes.

## Tasks

Task data lives in `~/repos/tasks/` — personal, not shared with collaborators. Don't reference task IDs or contents in PRs, commits, or any external comms. See its CLAUDE.md for conventions (naming, priorities, format, claiming). Task scripts (`task-list.sh`, etc.) are on PATH — invoke them directly, never with a `~/repos/tasks/` prefix. Use `/plan-task`, `/implement-task`, `/complete-task`, `/list-tasks` commands when working on tasks. Don't auto-complete on PR merge — user's call; leave it in `active/` silently, don't narrate the non-action.

**All state changes (claim/complete/cancel/move) go through the task scripts** — `task-done.sh`, `task-pick.sh`, `task-cancel.sh`, etc. Never `git mv` or `mv` files under `~/repos/tasks/{todo,planning,planned,active,done,canceled}/`. The scripts handle the commit message + remote sync atomically; manual moves leave the repo out of sync with origin.

Verify pwd before any task script — project (via `find-project.sh`) and worker both derive from it; wrong cwd → wrong project listed or wrong worker stamped.

## Context store

Per-project domain knowledge — a glossary (`CONTEXT.md`) and decision records (`adr/`) — lives in `~/repos/context/<project>/`, external to the code repo (keeps it out of possibly-public repos). Read before planning non-trivial work; `context-sync.sh` first to avoid stale reads. Resolve `<project>` with `find-project.sh` — not always the dir basename.

## .claude directory

When deleting inside `.claude/`, target the specific file — never `rm -rf .claude/`.

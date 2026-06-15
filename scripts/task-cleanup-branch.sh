#!/bin/bash
# Detach to origin/<base> and delete the current branch.
# Safety: refuses detached HEAD and base branch — only deletes the branch we were on.
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Detach to origin/<base> and delete the current branch (only if merged)."
    echo "Usage: task-cleanup-branch.sh"
    exit 0
fi

current=$(git branch --show-current)
if [[ -z "$current" ]]; then
    echo "error: detached HEAD — no current branch to delete" >&2
    exit 1
fi

if [[ "$current" == "main" || "$current" == "master" ]]; then
    echo "error: refusing to delete $current" >&2
    exit 1
fi

base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||') || true
if [[ -z "$base" ]]; then
    for candidate in master main; do
        if git rev-parse --verify "origin/$candidate" &>/dev/null; then
            base="$candidate"
            break
        fi
    done
fi
if [[ -z "$base" ]]; then
    echo "error: could not detect base branch (no origin/HEAD, master, or main)" >&2
    exit 1
fi

if [[ "$current" == "$base" ]]; then
    echo "error: refusing to delete base branch $base" >&2
    exit 1
fi

git fetch origin "$base"

pr_state=$(gh pr view "$current" --json state -q .state 2>/dev/null) || pr_state=""
if [[ -n "$pr_state" ]]; then
    if [[ "$pr_state" != "MERGED" ]]; then
        echo "error: PR for $current is $pr_state, not MERGED" >&2
        exit 1
    fi
else
    if ! git merge-base --is-ancestor "$current" "origin/$base"; then
        echo "error: no PR for $current and its tip is not in origin/$base" >&2
        exit 1
    fi
fi

git checkout --detach "origin/$base"
git branch -D "$current"

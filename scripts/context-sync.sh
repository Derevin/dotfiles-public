#!/usr/bin/env bash
# Sync context repo. Usage: context-sync.sh
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Sync ~/repos/context via git pull --rebase. No-op if missing; exits 1 if the tree is dirty or the rebase fails."
    echo "Usage: context-sync.sh"
    exit 0
fi

[[ -d ~/repos/context/.git ]] || exit 0

cd ~/repos/context

if [[ -n "$(git status --porcelain)" ]]; then
    echo "context-sync: ~/repos/context has uncommitted changes — commit or stash before syncing." >&2
    exit 1
fi

if ! git pull --rebase; then
    git rebase --abort 2>/dev/null || true
    echo "context-sync: git pull --rebase failed; repo left unchanged." >&2
    exit 1
fi

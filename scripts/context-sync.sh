#!/usr/bin/env bash
# Sync context repo. Usage: context-sync.sh
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Sync ~/repos/context via git pull --rebase. No-op if missing."
    echo "Usage: context-sync.sh"
    exit 0
fi

[[ -d ~/repos/context/.git ]] || exit 0

cd ~/repos/context
git pull --rebase 2>/dev/null || true

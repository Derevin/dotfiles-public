#!/usr/bin/env bash
# Commit in context repo. Usage: context-commit.sh <message>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Commit in context repo and push."
    echo "Usage: context-commit.sh <message>"
    exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "usage: context-commit.sh <message>" >&2; exit 1
fi

cd ~/repos/context
git pull --rebase 2>/dev/null || true
git add -A
git commit -m "$1"
git push

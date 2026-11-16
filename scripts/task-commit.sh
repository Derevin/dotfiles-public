#!/usr/bin/env bash
# Commit in tasks repo. Usage: task-commit.sh <message>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Commit in tasks repo and push."
    echo "Usage: task-commit.sh <message>"
    exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "usage: task-commit.sh <message>" >&2; exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

cd "$TASKS_ROOT"
git pull --rebase 2>/dev/null || true
git add -A
git commit -m "$1"
git push

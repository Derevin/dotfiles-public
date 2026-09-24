#!/usr/bin/env bash
# Set a started task aside. Usage: task-stale.sh <filename>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Set a started task aside (move active/ -> stale/, keep the worker)."
    echo "Usage: task-stale.sh <filename>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

if [[ $# -lt 1 ]]; then
  echo "usage: task-stale.sh <filename>" >&2; exit 1
fi

filename=$(task_filename "$1")
detect_project

src="$TASKS_DIR/active/$filename"
dst="$TASKS_DIR/stale/$filename"

if [[ ! -f "$src" ]]; then
  echo "error: not found: $src" >&2; exit 1
fi

# The Worker: line rides along — a stale task's lab usually outlives it, and the
# stamp is how you find the lab that still holds the partial work.
worker=$(sed -n 's/^Worker: //p' "$src" | head -1)
[[ -n "$worker" ]] || worker=main

mkdir -p "$TASKS_DIR/stale"
cd "$TASKS_ROOT"
git pull --rebase 2>/dev/null || true

mv "$src" "$dst"

slug=$(slug_from_filename "$filename")
git add -A
git commit -m "Stale: $slug [$worker]"
git pull --rebase
git push

echo "--- Set aside: $filename ---"

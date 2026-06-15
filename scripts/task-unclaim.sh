#!/usr/bin/env bash
# Unclaim a task (move active -> todo). Usage: task-unclaim.sh <filename>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Unclaim a task (move active/ -> todo/)."
    echo "Usage: task-unclaim.sh <filename>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

if [[ $# -lt 1 ]]; then
  echo "usage: task-unclaim.sh <filename>" >&2; exit 1
fi

filename=$1
detect_project
detect_worker

src="$TASKS_DIR/active/$filename"
dst="$TASKS_DIR/todo/$filename"

if [[ ! -f "$src" ]]; then
  echo "error: not found in active/: $filename" >&2; exit 1
fi

cd "$TASKS_ROOT"
git pull --rebase 2>/dev/null || true

mv "$src" "$dst"
sed -i '/^Worker: /d' "$dst"

slug=$(slug_from_filename "$filename")
git add -A
git commit -m "Unclaim: $slug [$WORKER]"
git pull --rebase
git push

echo "--- Unclaimed: $filename ---"

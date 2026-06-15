#!/usr/bin/env bash
# Complete a task. Usage: task-done.sh <filename>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Complete a task (move active/ -> done/)."
    echo "Usage: task-done.sh <filename>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

if [[ $# -lt 1 ]]; then
  echo "usage: task-done.sh <filename>" >&2; exit 1
fi

filename=$1
detect_project
detect_worker

src="$TASKS_DIR/active/$filename"
dst="$TASKS_DIR/done/$filename"

if [[ ! -f "$src" ]]; then
  echo "error: not found: $src" >&2; exit 1
fi

# Move and strip worker stamp
mv "$src" "$dst"
sed -i '/^Worker: /d' "$dst"

# Commit + push
slug=$(slug_from_filename "$filename")
cd "$TASKS_ROOT"
git add -A
git commit -m "Done: $slug [$WORKER]"
git pull --rebase
git push

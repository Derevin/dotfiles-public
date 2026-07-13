#!/usr/bin/env bash
# Unclaim a task (planning -> todo, active -> planned). Usage: task-unclaim.sh <filename>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Unclaim a task (planning/ -> todo/, active/ -> planned/)."
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

# Return to where the claim came from — the directory encodes the phase: a
# mid-grill task has nothing groomed to keep; an implementing task's plan survives.
if [[ -f "$TASKS_DIR/planning/$filename" ]]; then
  src="$TASKS_DIR/planning/$filename"
  dst="$TASKS_DIR/todo/$filename"
elif [[ -f "$TASKS_DIR/active/$filename" ]]; then
  src="$TASKS_DIR/active/$filename"
  dst="$TASKS_DIR/planned/$filename"
else
  echo "error: $filename not found in planning/ or active/" >&2; exit 1
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

#!/usr/bin/env bash
# Cancel a task. Usage: task-cancel.sh <filename>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Cancel a task (move todo/, planned/, or active/ -> canceled/)."
    echo "Usage: task-cancel.sh <filename>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

if [[ $# -lt 1 ]]; then
  echo "usage: task-cancel.sh <filename>" >&2; exit 1
fi

filename=$1
detect_project

# Find in todo, planned, or active
if [[ -f "$TASKS_DIR/todo/$filename" ]]; then
  src="$TASKS_DIR/todo/$filename"
elif [[ -f "$TASKS_DIR/planned/$filename" ]]; then
  src="$TASKS_DIR/planned/$filename"
elif [[ -f "$TASKS_DIR/active/$filename" ]]; then
  src="$TASKS_DIR/active/$filename"
else
  echo "error: $filename not found in todo/, planned/, or active/" >&2; exit 1
fi

dst="$TASKS_DIR/canceled/$filename"

mv "$src" "$dst"
sed -i '/^Worker: /d' "$dst"

cd "$TASKS_ROOT"
git pull --rebase 2>/dev/null || true

slug=$(slug_from_filename "$filename")
git add -A
git commit -m "Cancel: $slug"
git pull --rebase
git push

#!/usr/bin/env bash
# Park a groomed task. Usage: task-planned.sh <filename>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Park a groomed task (move active/ -> planned/, strip worker)."
    echo "Usage: task-planned.sh <filename>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

if [[ $# -lt 1 ]]; then
  echo "usage: task-planned.sh <filename>" >&2; exit 1
fi

filename=$1
detect_project
detect_worker

src="$TASKS_DIR/active/$filename"
dst="$TASKS_DIR/planned/$filename"

if [[ ! -f "$src" ]]; then
  echo "error: not found: $src" >&2; exit 1
fi

# Move and strip worker stamp — planned/ tasks are unowned, like todo/.
mv "$src" "$dst"
sed -i '/^Worker: /d' "$dst"

# Commit + push
slug=$(slug_from_filename "$filename")
cd "$TASKS_ROOT"
git add -A
git commit -m "Plan: $slug [$WORKER]"
git pull --rebase
git push

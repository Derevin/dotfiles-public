#!/usr/bin/env bash
# Re-stamp a claimed task's Worker: line. Usage: task-restamp.sh <filename> <worker>
#
# Claiming a lab renames it, and the task's Worker: line is one of the things
# that rename has to carry. task-claim.sh only inserts the line and
# task-unclaim.sh only deletes it, so this is the third edit — here rather than
# in the caller because the sync, commit and push have to stay atomic.
#
# A task with no Worker: line yet (still in todo/) is left alone: the slash
# command's own task-claim.sh will stamp it, from inside the lab, correctly.
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Re-stamp a claimed task's Worker: line (no-op when the task has none)."
    echo "Usage: task-restamp.sh <filename> <worker>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

if [[ $# -lt 2 ]]; then
  echo "usage: task-restamp.sh <filename> <worker>" >&2; exit 1
fi

filename=$1
worker=$2
detect_project

path=""
for dir in planning active planned todo; do
  if [[ -f "$TASKS_DIR/$dir/$filename" ]]; then path="$TASKS_DIR/$dir/$filename"; break; fi
done
[[ -n "$path" ]] || { echo "error: $filename not found in $TASKS_DIR" >&2; exit 1; }

grep -q '^Worker: ' "$path" || exit 0
[[ "$(sed -n 's/^Worker: //p' "$path" | head -1)" == "$worker" ]] && exit 0

cd "$TASKS_ROOT"
git pull --rebase 2>/dev/null || true

sed -i "0,/^Worker: .*/s//Worker: $worker/" "$path"

slug=$(slug_from_filename "$filename")
git add -A
git commit -m "Restamp: $slug [$worker]"
git pull --rebase
git push

echo "--- Restamped: $filename -> $worker ---"

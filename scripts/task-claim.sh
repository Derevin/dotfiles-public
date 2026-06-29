#!/usr/bin/env bash
# Claim a task. Usage: task-claim.sh <filename>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Claim a task (move todo/ or planned/ -> active/, stamp worker)."
    echo "Usage: task-claim.sh <filename>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

if [[ $# -lt 1 ]]; then
  echo "usage: task-claim.sh <filename>" >&2; exit 1
fi

filename=$1
detect_project
detect_worker

# Claim from todo/ (raw) or planned/ (groomed) — source inferred from location.
if [[ -f "$TASKS_DIR/todo/$filename" ]]; then
  src="$TASKS_DIR/todo/$filename"
elif [[ -f "$TASKS_DIR/planned/$filename" ]]; then
  src="$TASKS_DIR/planned/$filename"
else
  echo "error: $filename not found in todo/ or planned/" >&2; exit 1
fi
dst="$TASKS_DIR/active/$filename"

# Sync first
cd "$TASKS_ROOT"
git pull --rebase 2>/dev/null || true

# Move and stamp worker
mv "$src" "$dst" || { echo "error: mv failed (race condition?)" >&2; exit 1; }
sed -i "1a\\Worker: $WORKER" "$dst"

# Commit + push
slug=$(slug_from_filename "$filename")
git add -A
git commit -m "Claim: $slug [$WORKER]"
git pull --rebase
git push

# Output task content
echo "--- Claimed: $filename ---"
echo ""
cat "$dst"

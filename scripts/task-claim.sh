#!/usr/bin/env bash
# Claim a task. Usage: task-claim.sh <filename>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Claim a task (todo/ -> planning/, planned/ or stale/ -> active/; stamps worker)."
    echo "Usage: task-claim.sh <filename>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

if [[ $# -lt 1 ]]; then
  echo "usage: task-claim.sh <filename>" >&2; exit 1
fi

filename=$(task_filename "$1")
detect_project
detect_worker

# Claim from todo/ (raw -> grooming), planned/ (groomed -> implementation), or
# stale/ (set aside -> resume).
if [[ -f "$TASKS_DIR/todo/$filename" ]]; then
  src="$TASKS_DIR/todo/$filename"
  dst="$TASKS_DIR/planning/$filename"
elif [[ -f "$TASKS_DIR/planned/$filename" ]]; then
  src="$TASKS_DIR/planned/$filename"
  dst="$TASKS_DIR/active/$filename"
elif [[ -f "$TASKS_DIR/stale/$filename" ]]; then
  src="$TASKS_DIR/stale/$filename"
  dst="$TASKS_DIR/active/$filename"
else
  echo "error: $filename not found in todo/, planned/, or stale/" >&2; exit 1
fi

# Sync first
cd "$TASKS_ROOT"
git pull --rebase 2>/dev/null || true

# Move, then stamp the worker: drop any existing Worker: line (a resumed stale
# task carries one) and insert ours after the title. awk, not `sed 1a`, so an
# empty reminder task — no line 1 to append after — is still stamped.
mv "$src" "$dst" || { echo "error: mv failed (race condition?)" >&2; exit 1; }
awk -v w="Worker: $WORKER" '
  /^Worker: / { next }
  { print; if (!stamped) { print w; stamped = 1 } }
  END { if (!stamped) print w }
' "$dst" > "$dst.tmp" && mv "$dst.tmp" "$dst"

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

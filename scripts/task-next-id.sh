#!/usr/bin/env bash
# Output next available task ID (zero-padded 3 digits). Usage: task-next-id.sh [PROJECT]
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Output next available task ID (zero-padded 3 digits)."
    echo "Usage: task-next-id.sh [PROJECT]"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

if [[ $# -ge 1 ]]; then
  PROJECT=$1
  TASKS_DIR="$TASKS_ROOT/$PROJECT"
  if [[ ! -d "$TASKS_DIR" ]]; then
    echo "error: tasks dir not found: $TASKS_DIR" >&2; exit 1
  fi
else
  detect_project
fi

# Sync to avoid drift (route to stderr so stdout stays just the ID)
(cd "$TASKS_ROOT" && git pull --rebase >&2) || true

max_id=0
for dir in todo planned active done canceled; do
  if [[ -d "$TASKS_DIR/$dir" ]]; then
    for f in "$TASKS_DIR/$dir"/*.md; do
      [[ -f "$f" ]] || continue
      name=$(basename "$f")
      # Extract 3-digit ID (chars 2-4 of filename, i.e. after the letter prefix)
      if [[ "$name" =~ ^[A-Z]([0-9]{3})- ]]; then
        id=${BASH_REMATCH[1]}
        # Strip leading zeros for arithmetic
        id_num=$((10#$id))
        if (( id_num > max_id )); then
          max_id=$id_num
        fi
      fi
    done
  fi
done

printf "%03d\n" $((max_id + 1))

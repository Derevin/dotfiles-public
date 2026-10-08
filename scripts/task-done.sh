#!/usr/bin/env bash
# Complete a task. Usage: task-done.sh [--force] <filename>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Complete a task (move active/ -> done/; --force from any state)."
    echo "Usage: task-done.sh [--force] <filename>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) force=1; shift ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "usage: task-done.sh [--force] <filename>" >&2; exit 1
fi

filename=$(task_filename "$1")
detect_project
detect_worker

dst="$TASKS_DIR/done/$filename"

# Normal flow completes from active/. --force finishes a task stuck in any other
# state — the groom/implement pipeline skipped, so take it from wherever it sits.
if [[ "$force" -eq 1 ]]; then
  src=""
  for state in active planned planning stale todo canceled; do
    if [[ -f "$TASKS_DIR/$state/$filename" ]]; then
      src="$TASKS_DIR/$state/$filename"
      break
    fi
  done
  if [[ -z "$src" ]]; then
    echo "error: $filename not found in any state" >&2; exit 1
  fi
else
  src="$TASKS_DIR/active/$filename"
  if [[ ! -f "$src" ]]; then
    echo "error: not found: $src" >&2; exit 1
  fi
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

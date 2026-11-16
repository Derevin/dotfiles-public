#!/usr/bin/env bash
# Move a task between statuses by hand. Usage: task-move.sh <filename> <status>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Move a task by hand: into todo/, planned/, done/ or canceled/ from any other status, into stale/ only from active/."
    echo "Usage: task-move.sh <filename> <status>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

if [[ $# -lt 2 ]]; then
  echo "usage: task-move.sh <filename> <status>" >&2; exit 1
fi

filename=$(task_filename "$1")
to=$2

# Claims (planning/, active/) stamp a worker and need a lab to work in.
case $to in
  todo|planned|stale|done|canceled) ;;
  planning|active) echo "error: $to/ is a claim, made by task-claim.sh" >&2; exit 1 ;;
  *) echo "error: unknown status: $to (todo, planned, stale, done, canceled)" >&2; exit 1 ;;
esac

detect_project

# Sync first: another machine may have moved the task already.
cd "$TASKS_ROOT"
git pull --rebase 2>/dev/null || true

found=()
for s in todo planning planned active stale done canceled; do
  if [[ -f "$TASKS_DIR/$s/$filename" ]]; then found+=("$s"); fi
done
if [[ ${#found[@]} -eq 0 ]]; then
  echo "error: $filename not found in $PROJECT" >&2; exit 1
elif [[ ${#found[@]} -gt 1 ]]; then
  echo "error: $filename is in more than one status: ${found[*]}" >&2; exit 1
fi
from=${found[0]}

if [[ "$from" == "$to" ]]; then
  echo "error: $filename is already in $to/" >&2; exit 1
fi
# Stale is started work set aside; it resumes to active/.
if [[ "$to" == stale && "$from" != active ]]; then
  echo "error: only an active task goes stale ($filename is in $from/)" >&2; exit 1
fi

mkdir -p "$TASKS_DIR/$to"
mv "$TASKS_DIR/$from/$filename" "$TASKS_DIR/$to/$filename"
# The worker rides along only into stale/, where it names the lab holding the
# partial work; everywhere else the task is unowned.
if [[ "$to" != stale ]]; then
  sed -i '/^Worker: /d' "$TASKS_DIR/$to/$filename"
fi

slug=$(slug_from_filename "$filename")
git add -A
git commit -m "Move: $slug $from->$to"
git pull --rebase
git push

echo "--- Moved: $filename $from -> $to ---"

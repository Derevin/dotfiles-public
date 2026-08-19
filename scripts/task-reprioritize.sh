#!/usr/bin/env bash
# Re-prioritize a task. Usage: task-reprioritize.sh <filename|ID> <letter>
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Re-prioritize a task (rewrite its letter prefix; ID and status stay)."
    echo "Usage: task-reprioritize.sh <filename|ID> <letter A-Z>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

if [[ $# -lt 2 ]]; then
  echo "usage: task-reprioritize.sh <filename|ID> <letter A-Z>" >&2; exit 1
fi

arg=$(basename -- "$1")
letter=${2^^}

if [[ ! "$letter" =~ ^[A-Z]$ ]]; then
  echo "error: priority must be a single letter A-Z (see ~/repos/tasks/CLAUDE.md)" >&2; exit 1
fi

detect_project

# Sync first — another machine may have renamed or moved the task already.
cd "$TASKS_ROOT"
git pull --rebase 2>/dev/null || true

# The ID is the stable handle, so accept it bare; the letter is what we're replacing.
if [[ "$arg" =~ ^[0-9]{1,3}$ ]]; then
  pattern="[A-Z]$(printf '%03d' "$((10#$arg))")-*.md"
else
  pattern=$arg
fi

matches=()
for dir in todo planning planned active; do
  for f in "$TASKS_DIR/$dir"/$pattern; do
    [[ -f "$f" ]] && matches+=("$f")
  done
done

if [[ ${#matches[@]} -eq 0 ]]; then
  echo "error: $1 not found in todo/, planning/, planned/, or active/" >&2; exit 1
elif [[ ${#matches[@]} -gt 1 ]]; then
  echo "error: $1 matches ${#matches[@]} tasks: ${matches[*]##*/}" >&2; exit 1
fi

src=${matches[0]}
name=${src##*/}
status=${src%/*}; status=${status##*/}

if [[ ! "$name" =~ ^[A-Z][0-9]{3}- ]]; then
  echo "error: not a <letter><NNN>-slug.md task file: $name" >&2; exit 1
fi

old_letter=${name:0:1}
new_name="$letter${name:1}"

if [[ "$letter" == "$old_letter" ]]; then
  echo "$name already at priority $letter"
  exit 0
fi

dst="${src%/*}/$new_name"
if [[ -e "$dst" ]]; then
  echo "error: $new_name already exists in $status/ (duplicate ID?)" >&2; exit 1
fi

mv "$src" "$dst"

slug=$(slug_from_filename "$name")
git add -A
git commit -m "Reprioritize: $slug $old_letter->$letter"
git pull --rebase
git push

echo "--- $name -> $new_name ($status) ---"

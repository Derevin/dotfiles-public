#!/usr/bin/env bash
# Create a reminder task in the project's todo/ and commit. The file is empty;
# the title only names it (slug + priority letter).
# Usage: task-create.sh [-p LETTER] <title>
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Create a reminder task in the project's todo/ (empty file, title names it) and commit."
    echo "Usage: task-create.sh [-p LETTER] <title>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

prio=N
while getopts ":p:h" opt; do
  case $opt in
    p) prio=$OPTARG ;;
    h) echo "Usage: task-create.sh [-p LETTER] <title>"; exit 0 ;;
    :) echo "error: -p needs a letter" >&2; exit 1 ;;
    \?) echo "error: unknown option -$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

prio=$(printf '%s' "$prio" | tr '[:lower:]' '[:upper:]')
if [[ ! "$prio" =~ ^[A-Z]$ ]]; then
  echo "error: priority must be a single letter A-Z" >&2; exit 1
fi

title="$*"
if [[ ! "$title" =~ [^[:space:]] ]]; then
  echo "error: title required" >&2; exit 1
fi

slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
if [[ -z "$slug" ]]; then
  echo "error: title has no alphanumeric characters to slug" >&2; exit 1
fi

PROJECT=$(find-project.sh) || exit 1
TASKS_DIR="$TASKS_ROOT/$PROJECT"
mkdir -p "$TASKS_DIR"/{todo,planning,planned,active,stale,done,canceled}

id=$(task-next-id.sh "$PROJECT")
: > "$TASKS_DIR/todo/${prio}${id}-${slug}.md"

cd "$TASKS_ROOT"
git add -A
git commit -m "Add: $slug"
git pull --rebase
git push

echo "${prio}${id}-${slug}.md"

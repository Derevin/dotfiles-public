#!/usr/bin/env bash
# List tasks for a project. Usage: task-list.sh [--status STATUS...] [--verbose] [PROJECT]
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "List tasks for a project (defaults to detected project)."
    echo "Usage: task-list.sh [--status STATUS...] [--verbose] [PROJECT]"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

status_list=()
verbose=false
explicit_project=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --status)
      shift
      while [[ $# -gt 0 ]]; do
        case $1 in
          todo|planning|planned|active|done|canceled) status_list+=("$1"); shift ;;
          *) break ;;
        esac
      done
      ;;
    --verbose) verbose=true; shift ;;
    *) explicit_project=$1; shift ;;
  esac
done

if [[ -n "$explicit_project" ]]; then
  PROJECT=$explicit_project
  TASKS_DIR="$TASKS_ROOT/$PROJECT"
  if [[ ! -d "$TASKS_DIR" ]]; then
    echo "error: tasks dir not found: $TASKS_DIR" >&2; exit 1
  fi
else
  detect_project
fi
detect_worker

list_dir() {
  local dir=$1 label=$2
  local files=()

  if [[ -d "$TASKS_DIR/$dir" ]]; then
    while IFS= read -r -d '' f; do
      files+=("$(basename "$f")")
    done < <(find "$TASKS_DIR/$dir" -maxdepth 1 -name '*.md' -print0 2>/dev/null | sort -z)
  fi

  echo "## ${label} (${#files[@]})"
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "  (none)"
  else
    for f in "${files[@]}"; do
      local suffix=""
      if [[ "$dir" == "active" || "$dir" == "planning" ]]; then
        local worker
        worker=$(grep -m1 '^Worker: ' "$TASKS_DIR/$dir/$f" 2>/dev/null | sed 's/^Worker: //') || true
        [[ -n "$worker" ]] && suffix=" [$worker]" || true
      fi
      echo "  $f$suffix"
      if $verbose; then
        echo ""
        sed 's/^/    /' "$TASKS_DIR/$dir/$f"
        echo ""
      fi
    done
  fi
  echo ""
}

statuses=(canceled done active planned planning todo)

if [[ ${#status_list[@]} -gt 0 ]]; then
  statuses=("${status_list[@]}")
fi

echo "# Tasks: $PROJECT"
echo "# Worker: $WORKER"
echo ""
for s in "${statuses[@]}"; do
  label=$(echo "$s" | tr '[:lower:]' '[:upper:]')
  list_dir "$s" "$label"
done

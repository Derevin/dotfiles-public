#!/usr/bin/env bash
# List tasks for a project. Usage: task-list.sh [--status STATUS...] [--all] [--verbose] [--no-header] [--ids] [--recent DAYS] [PROJECT]
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "List tasks for a project (defaults to detected project)."
    echo "Usage: task-list.sh [--status STATUS...] [--all] [--verbose] [--no-header] [--ids] [--recent DAYS] [PROJECT]"
    echo "Statuses: todo planning planned active stale done canceled"
    echo "--no-header drops the project/worker lines, for callers short on rows."
    echo "--ids prints bare <letter><id>-<slug> lines, for fzf choosers."
    echo "Shows open statuses only (todo planning planned active stale); done and"
    echo "canceled need an explicit --status or --all."
    echo "--recent DAYS appends done then canceled from the last DAYS days (each if any)."
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

status_list=()
show_all=false
verbose=false
no_header=false
ids_only=false
recent_days=""
explicit_project=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --status)
      shift
      while [[ $# -gt 0 ]]; do
        case $1 in
          todo|planning|planned|active|stale|done|canceled) status_list+=("$1"); shift ;;
          *) break ;;
        esac
      done
      ;;
    --all) show_all=true; shift ;;
    --verbose) verbose=true; shift ;;
    --no-header) no_header=true; shift ;;
    --ids) ids_only=true; shift ;;
    --recent)
      shift
      recent_days=${1:-}
      [[ $recent_days =~ ^[0-9]+$ ]] || { echo "error: --recent needs a whole-number day count" >&2; exit 1; }
      shift ;;
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

# max_age (days, optional) windows the listing to files touched that recently —
# used to cap the accumulating done/canceled dirs to their recent tail.
list_dir() {
  local dir=$1 label=$2 max_age=${3:-}
  local files=()
  local find_args=("$TASKS_DIR/$dir" -maxdepth 1 -name '*.md')
  [[ -n "$max_age" ]] && find_args+=(-mtime "-$max_age")

  if [[ -d "$TASKS_DIR/$dir" ]]; then
    while IFS= read -r -d '' f; do
      files+=("$(basename "$f")")
    done < <(find "${find_args[@]}" -print0 2>/dev/null | sort -z)
  fi

  # Omit empty categories entirely; a global "(none)" covers the all-empty case.
  [[ ${#files[@]} -eq 0 ]] && return
  total_shown=$((total_shown + ${#files[@]}))

  # --ids: the filename, one line each, nothing else to strip. The letter prefix
  # stays so a chooser shows priority; readers take the id back out themselves.
  if $ids_only; then
    for f in "${files[@]}"; do
      echo "${f%.md}"
    done
    return
  fi

  echo "${label} (${#files[@]})"
  for f in "${files[@]}"; do
    local suffix=""
    if [[ "$dir" == "active" || "$dir" == "planning" || "$dir" == "stale" ]]; then
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
}

statuses=(active planned planning stale todo)

if [[ ${#status_list[@]} -gt 0 ]]; then
  statuses=("${status_list[@]}")
elif $show_all; then
  statuses=(canceled done active planned planning stale todo)
fi

# The worker is the header's only consumer, so detecting it is header-only work
# (it shells out to git).
if ! $no_header && ! $ids_only; then
  detect_worker
  echo "Tasks: $PROJECT"
  echo "Worker: $WORKER"
  echo ""
fi
total_shown=0
for s in "${statuses[@]}"; do
  label=$(echo "$s" | tr '[:lower:]' '[:upper:]')
  list_dir "$s" "$label"
done

# Recent terminal states below the open queue: done then canceled, windowed and
# each shown only when non-empty. Skipped for --ids, and for a status already
# listed above (so --all stays one unwindowed section, not two).
if [[ -n "$recent_days" ]] && ! $ids_only; then
  recent=()
  for s in done canceled; do
    printf '%s\n' "${statuses[@]}" | grep -qx "$s" && continue
    [[ -n "$(find "$TASKS_DIR/$s" -maxdepth 1 -name '*.md' -mtime "-$recent_days" -print -quit 2>/dev/null)" ]] \
      && recent+=("$s")
  done
  # One blank line sets the recent tail off from the open queue, printed only when
  # the tail has something to follow it.
  if [[ ${#recent[@]} -gt 0 ]]; then
    echo ""
    for s in "${recent[@]}"; do
      label=$(echo "$s" | tr '[:lower:]' '[:upper:]')
      list_dir "$s" "$label" "$recent_days"
    done
  fi
fi

if [[ $total_shown -eq 0 ]] && ! $ids_only; then
  echo "(none)"
fi

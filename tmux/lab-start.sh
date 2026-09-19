#!/usr/bin/env bash
# Put a task in front of you: find or create its lab, claim it if it is new, and
# take over the caller's quadrant with Claude running the given prompt.
#
# The task id is bare (238) because ids repeat across projects — the caller
# pane's cwd is what says which project, exactly as it does for the task
# scripts. Creating the lab is the moment its backend is decided, and a
# launchpad stands for no backend — so it comes from the argument, else the
# caller pane's lab, else the project's declared default.
#
# Usage: lab-start.sh <task-id> <prompt> [backend]
#   backend  omit to take the caller pane's lab, else the project's default.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Find or create a task's lab and take over the caller's quadrant with a prompt."
    echo "Usage: lab-start.sh <task-id> <prompt> [backend]"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# lab-lib.sh sits beside this script once installed; in the repo the tmux and
# script helpers are kept apart, and the private tmux scripts a level further.
LIB_DIR=""
for d in "$SCRIPT_DIR" "$SCRIPT_DIR/../scripts" "$SCRIPT_DIR/../public/scripts"; do
    [ -f "$d/lab-lib.sh" ] && { LIB_DIR=$d; break; }
done
[ -n "$LIB_DIR" ] || { echo "lab-start: cannot find lab-lib.sh" >&2; exit 1; }
source "$LIB_DIR/lab-lib.sh"
source "$LIB_DIR/task-lib.sh"

ID="${1:-}"
PROMPT="${2:-}"
BACKEND_ARG="${3:-}"
[ -n "$ID" ] && [ -n "$PROMPT" ] || { echo "usage: lab-start.sh <task-id> <prompt> [backend]" >&2; exit 2; }

# Accept anything the id can be read out of, so a chooser can show something
# readable (N238-fix-the-nasty-bug) rather than three bare digits: a filename, a
# path, or the id alone. The letter prefix is priority, never identity.
ID="${ID##*/}"
ID="${ID%.md}"
ID="${ID#[A-Z]}"
ID="${ID%%-*}"
[[ "$ID" =~ ^[0-9]{3}$ ]] || { echo "lab-start: cannot read a three-digit task id out of '${1}'" >&2; exit 2; }

export TMUX=
CALLER=$(tmux show-environment -g JUST_CALLER 2>/dev/null | cut -d= -f2-) || true
[ -n "$CALLER" ] || CALLER="${TMUX_PANE:-}"
[ -n "$CALLER" ] || { echo "lab-start: no caller pane" >&2; exit 1; }

PROJECT=$(lab_project_from_cwd) || { echo "lab-start: not in a project checkout" >&2; exit 1; }
lab_project_paths "$PROJECT"

# A pane already showing a lab answers before the project does: standing in one
# backend and asking for a task is not a request to leave it. A launchpad is a
# plain host shell and answers nothing, which is where the project's default is
# the whole point.
BACKEND="$BACKEND_ARG"
[ -n "$BACKEND" ] || BACKEND=$(tmux show-options -pvt "$CALLER" @backend 2>/dev/null || true)
[ -n "$BACKEND" ] || BACKEND="$LAB_DEFAULT_BACKEND"
[ -n "$BACKEND" ] || { echo "lab-start: no backend given, the caller pane names none, and $PROJECT declares none (see $LAB_CONF)" >&2; exit 1; }
BACKEND=$(lab_backend "$BACKEND") || { echo "lab-start: unknown backend '$BACKEND'" >&2; exit 1; }

TASK_PATH=$(lab_task_find "$PROJECT" "$ID")
SLUG=$(slug_from_filename "$(basename "$TASK_PATH")")
NAME=$(lab_claimed_name "$BACKEND" "$ID" "$SLUG" "$LAB_PREFIX")

# One lab per (backend, task): reuse the existing one rather than growing a
# suffix that would stop the id identifying the lab.
if ! LAB_PROJECT_OVERRIDE="$PROJECT" lab_exists "$NAME"; then
    NEW=$(LAB_PROJECT_OVERRIDE="$PROJECT" lab-new.sh "$BACKEND")
    NAME=$(LAB_PROJECT_OVERRIDE="$PROJECT" lab-claim.sh "$NEW" "$ID")
fi

exec lab-attach.sh --pane "$CALLER" "$NAME" "$PROMPT"

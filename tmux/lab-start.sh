#!/usr/bin/env bash
# Put a task in front of you: find or create its lab, claim it if it is new, and
# take over the caller's quadrant with Claude running the given prompt.
#
# The task id is bare (238) because ids repeat across projects — the caller
# pane's cwd is what says which project, exactly as it does for the task
# scripts. Creating the lab is the moment its backend is decided, and a
# launchpad stands for no backend — so it comes from the argument, else the
# caller pane's lab, else the project's default.
#
# Usage: lab-start.sh <task-id> <prompt> [backend [claude-arg...]]
#   backend     omit or leave empty to take the caller pane's lab, else the
#               project's default.
#   claude-arg  passed to Claude ahead of the prompt (e.g. --model fable).
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Find or create a task's lab and take over the caller's quadrant with a prompt."
    echo "Usage: lab-start.sh <task-id> <prompt> [backend [claude-arg...]]"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-view-lib.sh"

ID="${1:-}"
PROMPT="${2:-}"
BACKEND="${3:-}"
[ -n "$ID" ] && [ -n "$PROMPT" ] || { echo "usage: lab-start.sh <task-id> <prompt> [backend [claude-arg...]]" >&2; exit 2; }

export TMUX=
CALLER=$(lab_recipe_caller)
[ -n "$CALLER" ] || { echo "lab-start: no caller pane" >&2; exit 1; }

# A pane already showing a lab answers before the project does: standing in one
# backend and asking for a task is not a request to leave it.
[ -n "$BACKEND" ] || BACKEND=$(lab_pane_backend "$CALLER")
NAME=$(lab-for-task.sh "$ID" "$BACKEND")

exec lab-attach.sh --pane "$CALLER" "$NAME" "${@:4}" "$PROMPT"

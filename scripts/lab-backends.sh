#!/usr/bin/env bash
# Print the backends a new lab can go in for the current project, best first.
#
# The first line is the default — the M-j picker passes it without asking and
# shows it in the preview, so what leads here is what Enter does. That is the
# caller pane's lab, else the project's declared backend; the rest follow, for
# the time it is the exception. A backend the project has no provisioner for is
# left out: offering it is offering a failure at creation.
#
# Nothing at all when the project declares no backend. The recipes this feeds
# cannot run outside a configured project anyway, and a list leading with some
# backend would make one up.
#
# Usage: lab-backends.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Print the backends a new lab can go in for the current project, best first."
    echo "Usage: lab-backends.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-lib.sh"

PROJECT=$(lab_project_from_cwd) || exit 0
lab_project_paths "$PROJECT" 2>/dev/null || exit 0

# The popup runs a tmux server of its own, so bare tmux has to be sent to the
# one that holds the pane M-j was pressed in.
export TMUX=
CALLER=$(tmux show-environment -g JUST_CALLER 2>/dev/null | cut -d= -f2-) || true

FIRST=$(lab_backend_fallback "$CALLER")
[ -n "$FIRST" ] || exit 0
FIRST=$(lab_backend "$FIRST") || exit 0

printf '%s\n' "$FIRST"
for b in host docker coder; do
    [ "$b" = "$FIRST" ] && continue
    # Host is a worktree and a shell; the other two are somebody's provisioner.
    [ "$b" = host ] || [ -n "$LAB_PROVISIONER" ] || continue
    printf '%s\n' "$b"
done

#!/usr/bin/env bash
# Print the backends a new lab can go in for the current project, best first.
#
# The first line is the default — the M-j picker passes it without asking and
# shows it in the preview, so what leads here is what Enter does. That is the
# caller pane's lab, else the project's default backend; the rest follow, for
# the time it is the exception. A backend the project has no provisioner for is
# left out: offering it is offering a failure at creation.
#
# Nothing at all when a project with a provisioner declares no backend — a list
# leading with some backend would make one up — or outside any repo.
#
# Usage: lab-backends.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Print the backends a new lab can go in for the current project, best first."
    echo "Usage: lab-backends.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-view-lib.sh" || exit 1

PROJECT=$(lab_project_from_cwd) || exit 0
lab_project_paths "$PROJECT" 2>/dev/null || exit 0

# The popup runs a tmux server of its own, so bare tmux has to be sent to the
# one that holds the pane M-j was pressed in.
export TMUX=
CALLER=$(lab_just_caller) || true

FIRST=$(lab_backend_fallback "$(lab_pane_backend "$CALLER")")
[ -n "$FIRST" ] || exit 0
FIRST=$(lab_backend "$FIRST") || exit 0

printf '%s\n' "$FIRST"
for b in host docker coder; do
    [ "$b" = "$FIRST" ] && continue
    # Host is a worktree and a shell; the other two are somebody's provisioner.
    [ "$b" = host ] || [ -n "$LAB_PROVISIONER" ] || continue
    printf '%s\n' "$b"
done

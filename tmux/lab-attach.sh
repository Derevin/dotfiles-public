#!/usr/bin/env bash
# Take over a pane with a lab: convert a launchpad quadrant into a view of the
# lab, and launch Claude in it.
#
# A pane is a view. Attaching does not create the lab and releasing does not
# destroy it — lab-new.sh and lab-drop.sh are the only two that do.
#
# Usage: lab-attach.sh [--pane <id>] <lab> [claude-arg...]
#   --pane  which pane to take over; default is the just caller, else this pane.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Take over a pane with a lab and launch Claude in it."
    echo "Usage: lab-attach.sh [--pane <id>] <lab> [claude-arg...]"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# lab-lib.sh sits beside this script once installed; in the repo the tmux and
# script helpers are kept apart, and the private tmux scripts a level further.
for d in "$SCRIPT_DIR" "$SCRIPT_DIR/../scripts" "$SCRIPT_DIR/../public/scripts"; do
    [ -f "$d/lab-lib.sh" ] && { source "$d/lab-lib.sh"; break; }
done
# A miss is otherwise silent: every lab_* call expands to nothing and the caller
# degrades instead of stopping — a pane with no Claude, a recipe on the host.
declare -F lab_resolve >/dev/null || { echo "lab-attach.sh: cannot find lab-lib.sh" >&2; exit 1; }

PANE=""
if [ "${1:-}" = "--pane" ]; then PANE="${2:-}"; shift 2; fi
LAB="${1:-}"
[ -n "$LAB" ] || { echo "usage: lab-attach.sh [--pane <id>] <lab> [claude-arg...]" >&2; exit 2; }
shift

# The popup that runs a just recipe is its own tmux server, so bare tmux calls
# have to reach the main one.
SELF_SOCKET="${TMUX:-}"; SELF_SOCKET="${SELF_SOCKET%%,*}"
export TMUX=
[ -n "$PANE" ] || PANE=$(lab_caller_pane "$SELF_SOCKET")
[ -n "$PANE" ] || { echo "lab-attach: no target pane (not in tmux, and no --pane)" >&2; exit 1; }

lab_resolve "$LAB" || exit 1

# respawn-pane -k kills the target pane's process group, and when the target is
# the pane we were typed into, that group is ours — the tagging, the placement
# row and the Claude launch below would all die with the pane they are for.
# Hand the rest to a detached copy that nothing about this pane can reach.
if [ "$PANE" = "${TMUX_PANE:-}" ] && [ -z "${LAB_ATTACH_DETACHED:-}" ]; then
    LAB_ATTACH_DETACHED=1 setsid "$SCRIPT_DIR/lab-attach.sh" --pane "$PANE" "$LAB" "$@" \
        </dev/null >/dev/null 2>&1 &
    exit 0
fi

# Reap whatever the pane was showing before: respawn-pane -k only SIGHUPs the
# local docker-exec / coder-ssh client, orphaning everything behind it.
PREV=$(tmux show-options -pvt "$PANE" @lab 2>/dev/null || true)
if [ -n "$PREV" ] && [ "$PREV" != "$LAB" ]; then
    setsid lab-cleanup.sh "$PREV" "$PANE" </dev/null >/dev/null 2>&1 &
fi

# Host-side cwd of the pane process: popups (M-j, M-g) resolve the project
# justfile from pane_current_path, and tmux -c needs the dir to exist. A coder
# lab has no host worktree, so the project checkout stands in.
CWD="$LAB_WORKTREE"
[ -d "$CWD" ] || CWD="$LAB_CHECKOUT"
[ -d "$CWD" ] || CWD="$HOME"

tmux respawn-pane -k -c "$CWD" -t "$PANE" "lab-shell $(lab_sq "$LAB")"
tmux set-option -pt "$PANE" @lab "$LAB"
tmux set-option -pt "$PANE" @backend "$LAB_BACKEND"

# Remember where the lab was put, keyed on window name: launchpad
# allocates labs, labs2, … deterministically, so two windows of one
# project do not fight. Only quadrants are tracked — a stray split is not a
# placement anyone wants restored.
# '|' rather than spaces: a window name may hold one, and default IFS would
# shift the quadrant out of the field it belongs to.
IFS='|' read -r WINDOW QUADRANT <<<"$(tmux display-message -t "$PANE" -p '#{window_name}|#{@quadrant}')"
[ -n "${QUADRANT:-}" ] && lab_state_put "$LAB_PROJECT" "$WINDOW" "$QUADRANT" "$LAB"

# Claude goes in by send-keys, after the pane exists at its final size:
# launching it as the pane command renders it against the pre-split geometry.
# docker exec / coder ssh do not reliably size their pty to the pane either, so
# force the winsize we know is correct right now.
CMD=""
if [ "$LAB_BACKEND" != host ]; then
    read -r H W <<<"$(tmux display-message -p -t "$PANE" '#{pane_height} #{pane_width}')"
    CMD="stty rows $H cols $W; "
    CMD+=$(lab_claude_cmd --no-auto-memory "$(lab_head "$LAB")" "$@")
else
    CMD+=$(lab_claude_cmd "$(lab_head "$LAB")" "$@")
fi
tmux send-keys -t "$PANE" "$CMD" Enter

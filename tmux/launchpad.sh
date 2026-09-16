#!/usr/bin/env bash
# Open a lab window: four launchpad quadrants, then restore whatever was last
# put in them.
#
# A launchpad is a plain shell at the project's main checkout with a backend set
# and no lab attached — what a quadrant is before and after a lab.
# lab-attach.sh converts one in place; lab-release.sh converts it back.
#
# Four quadrants is the cap, and they are @unclosable: a quadrant changes what
# it shows, not whether it exists.
#
# Usage: launchpad.sh <host|docker|coder> <checkout> [--window NAME]
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Open a 2x2 lab window of launchpads for a project, then restore its labs."
    echo "Usage: launchpad.sh <host|docker|coder> <checkout> [--window NAME]"
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
declare -F lab_resolve >/dev/null || { echo "launchpad.sh: cannot find lab-lib.sh" >&2; exit 1; }

BACKEND=$(lab_backend "${1:-}") || { echo "usage: launchpad.sh <host|docker|coder> <checkout> [--window NAME]" >&2; exit 2; }
DIR="${2:-}"
[ -d "$DIR" ] || { echo "launchpad: no checkout at '$DIR'" >&2; exit 1; }
shift 2
WINDOW="labs"
[ "${1:-}" = "--window" ] && { WINDOW="${2:-labs}"; shift 2; }

PROJECT=$(cd "$DIR" && find-project.sh) || { echo "launchpad: cannot name the project at $DIR" >&2; exit 1; }

# Own window-name family, allocated deterministically: the placement state keys
# on the name, and sharing the overview family would let an *o4 window shift
# which name a lab window gets.
if [[ -n "${TMUX:-}" ]]; then
    while tmux list-windows -F '#{window_name}' | grep -qx "$WINDOW"; do
        NUM="${WINDOW#labs}"
        NUM="${NUM:-1}"
        WINDOW="labs$((NUM + 1))"
    done
    tmux new-window -n "$WINDOW" -c "$DIR"
else
    if tmux has-session -t "$WINDOW" 2>/dev/null; then
        exec tmux attach-session -t "$WINDOW"
    fi
    tmux new-session -d -s "$WINDOW" -c "$DIR"
    tmux rename-window -t "${WINDOW}:1" "$WINDOW"
fi

W=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "$WINDOW")
W="${W}:${WINDOW}"
tmux setw -t "$W" automatic-rename off
# On the window, so releasing a quadrant reverts it to the backend the window
# opened with rather than to whatever lab last occupied it.
tmux set-option -wt "$W" @backend "$BACKEND"

# Row-based 2x2 so the horizontal mid-line is shared and up/down resize moves
# both columns together. Spatial: 1 TL, 2 BL, 3 TR, 4 BR. Pane ids, not indices
# — tmux renumbers indices by position as panes are added.
P1=$(tmux display-message -t "$W.1" -p '#{pane_id}')
P2=$(tmux split-window -v -c "$DIR" -t "$P1" -P -F '#{pane_id}')
P3=$(tmux split-window -h -c "$DIR" -t "$P1" -P -F '#{pane_id}')
P4=$(tmux split-window -h -c "$DIR" -t "$P2" -P -F '#{pane_id}')

q=1
for ID in "$P1" "$P2" "$P3" "$P4"; do
    tmux set-option -pt "$ID" @unclosable 1
    tmux set-option -pt "$ID" @quadrant "$q"
    # Tops are the odd quadrants (1 TL, 3 TR).
    if (( q % 2 == 1 )); then
        tmux set-option -pt "$ID" @split-dir up
    else
        tmux set-option -pt "$ID" @split-dir down
    fi
    tmux set-option -pt "$ID" @backend "$BACKEND"
    q=$((q + 1))
done

lab-restore.sh "$PROJECT" "$WINDOW"

tmux select-pane -t "$P1"

if [[ -z "${TMUX:-}" ]]; then
    exec tmux attach-session -t "$WINDOW"
fi

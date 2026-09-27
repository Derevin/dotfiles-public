#!/usr/bin/env bash
# Open a lab window: four launchpad quadrants, then restore whatever was last
# put in them.
#
# A launchpad is a plain shell at the project's main checkout with no lab
# attached — what a quadrant is before and after a lab. It stands for no backend:
# which one a lab lives in is decided when the lab is created, not by the
# quadrant it was started from.
# lab-attach.sh converts one in place; lab-release.sh converts it back.
#
# Four quadrants is the cap, and they are @unclosable: a quadrant changes what
# it shows, not whether it exists.
#
# Usage: launchpad.sh <checkout> [--window NAME]
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Open a 2x2 lab window of launchpads for a project, then restore its labs."
    echo "Usage: launchpad.sh <checkout> [--window NAME]"
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

DIR="${1:-}"
[ -d "$DIR" ] || { echo "launchpad: no checkout at '${DIR}'" >&2; exit 1; }
shift
WINDOW="labs"
[ "${1:-}" = "--window" ] && { WINDOW="${2:-labs}"; shift 2; }

PROJECT=$(cd "$DIR" && find-project.sh) || { echo "launchpad: cannot name the project at $DIR" >&2; exit 1; }

# Own window-name family, allocated deterministically: the placement state keys
# on the name, so a second labs window of the same project gets a distinct name
# rather than collide in the state file.
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
# Row-based 2x2 so the horizontal mid-line is shared and up/down resize moves
# both columns together. Spatial: 1 TL, 2 TR, 3 BL, 4 BR (row-first). Pane ids,
# not indices — tmux renumbers indices by position as panes are added.
TL=$(tmux display-message -t "$W.1" -p '#{pane_id}')
BL=$(tmux split-window -v -c "$DIR" -t "$TL" -P -F '#{pane_id}')
TR=$(tmux split-window -h -c "$DIR" -t "$TL" -P -F '#{pane_id}')
BR=$(tmux split-window -h -c "$DIR" -t "$BL" -P -F '#{pane_id}')

q=1
for ID in "$TL" "$TR" "$BL" "$BR"; do
    tmux set-option -pt "$ID" @unclosable 1
    tmux set-option -pt "$ID" @quadrant "$q"
    q=$((q + 1))
done

# @split-dir per row: top quadrants split upward, bottom downward — each away
# from the shared mid-line.
tmux set-option -pt "$TL" @split-dir up
tmux set-option -pt "$TR" @split-dir up
tmux set-option -pt "$BL" @split-dir down
tmux set-option -pt "$BR" @split-dir down

lab-restore.sh "$PROJECT" "$WINDOW"

tmux select-pane -t "$TL"

if [[ -z "${TMUX:-}" ]]; then
    exec tmux attach-session -t "$WINDOW"
fi

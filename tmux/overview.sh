#!/usr/bin/env bash
# Launch a multi-pane tmux workspace.
# 1-4 dirs → 2x2 quadrant layout.
# 5-6 dirs → 2x3 layout (33%/34%/33% columns).
# Inside tmux: creates a window in current session.
# Outside tmux: creates a new session.
# Usage: overview.sh [--window NAME] [--claude] [dir1] ... [dir4|dir6]

WINDOW="overview"
LAUNCH_CLAUDE=0
DIRS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --window) WINDOW="$2"; shift 2 ;;
        --claude) LAUNCH_CLAUDE=1; shift ;;
        *) DIRS+=("$1"); shift ;;
    esac
done

PANE_COUNT=4
if [[ ${#DIRS[@]} -gt 4 ]]; then
    PANE_COUNT=6
fi

DIR1="${DIRS[0]:-$PWD}"
DIR2="${DIRS[1]:-$PWD}"
DIR3="${DIRS[2]:-$PWD}"
DIR4="${DIRS[3]:-$PWD}"
DIR5="${DIRS[4]:-$PWD}"
DIR6="${DIRS[5]:-$PWD}"

# Find next available window name
if [[ -n "$TMUX" ]]; then
    while tmux list-windows -F '#{window_name}' | grep -qx "$WINDOW"; do
        NUM="${WINDOW#overview}"
        NUM="${NUM:-1}"
        WINDOW="overview$((NUM + 1))"
    done
    tmux new-window -n "$WINDOW" -c "$DIR1"
else
    if tmux has-session -t "$WINDOW" 2>/dev/null; then
        exec tmux attach-session -t "$WINDOW"
    fi
    tmux new-session -d -s "$WINDOW" -c "$DIR1"
    tmux rename-window -t "${WINDOW}:1" "$WINDOW"
fi

W=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "$WINDOW")
W="${W}:${WINDOW}"

tmux setw -t "$W" automatic-rename off

if [[ $PANE_COUNT -eq 6 ]]; then
    # 2x3: 33%/34%/33% columns
    tmux split-window -v -t "$W.1" -c "$DIR4" -l 50%
    tmux split-window -h -t "$W.1" -c "$DIR2" -l 67%
    tmux split-window -h -t "$W.2" -c "$DIR3" -l 50%
    tmux split-window -h -t "$W.4" -c "$DIR5" -l 67%
    tmux split-window -h -t "$W.5" -c "$DIR6" -l 50%

    # Row-based: tops are the first row (indices 1..half).
    half=$((PANE_COUNT / 2))
    for p in $(seq 1 $PANE_COUNT); do
        tmux set-option -pt "$W.$p" @unclosable 1
        tmux set-option -pt "$W.$p" @quadrant "$p"
        (( p <= half )) && split_dir=up || split_dir=down
        tmux set-option -pt "$W.$p" @split-dir "$split_dir"
    done
else
    # 2x2 quadrant, row-based: root is a top/bottom split so the horizontal
    # mid-line is shared — up/down resize moves both columns together and the
    # DIR1/DIR2 and DIR3/DIR4 dividers stay one line. Spatial: DIR1 TL, DIR2 BL,
    # DIR3 TR, DIR4 BR. Pane IDs (not indices) so quadrant tags follow position,
    # not tmux's layout-tree numbering, keeping quadrants 1 3 / 2 4.
    P1=$(tmux display-message -t "$W.1" -p '#{pane_id}')
    P2=$(tmux split-window -v -t "$P1" -c "$DIR2" -P -F '#{pane_id}')
    P3=$(tmux split-window -h -t "$P1" -c "$DIR3" -P -F '#{pane_id}')
    P4=$(tmux split-window -h -t "$P2" -c "$DIR4" -P -F '#{pane_id}')

    q=1
    for ID in "$P1" "$P2" "$P3" "$P4"; do
        tmux set-option -pt "$ID" @unclosable 1
        tmux set-option -pt "$ID" @quadrant "$q"
        # Tops are the odd quadrants (DIR1 TL=1, DIR3 TR=3).
        (( q % 2 == 1 )) && split_dir=up || split_dir=down
        tmux set-option -pt "$ID" @split-dir "$split_dir"
        q=$((q + 1))
    done
fi

if [[ $LAUNCH_CLAUDE -eq 1 ]]; then
    for p in $(seq 1 $PANE_COUNT); do
        d="${DIRS[p-1]:-$PWD}"
        name="${d##*/}"
        [[ "$name" =~ -[a-z]?wt[0-9]+$ ]] && name="${name##*-}"
        tmux send-keys -t "$W.$p" "claude --effort max -n $name /where-were-we" Enter
    done
fi

tmux select-pane -t "$W.1"

if [[ -z "$TMUX" ]]; then
    exec tmux attach-session -t "$WINDOW"
fi

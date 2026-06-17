#!/usr/bin/env bash
# Dual-claude workspace: claude left + right-top; two empty panes below (right col 50/25/25).
# Usage: workspace-dual.sh <repo-path>
#   <repo-path>  repo to open; the window is named after its basename.
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]]; then
    echo "Dual-claude tmux workspace: claude left + right-top, two terminals below."
    echo "Usage: workspace-dual.sh <repo-path>"
    exit 0
fi

DIR="$1"
BASE="$(basename "$DIR")"
WINDOW="$BASE"
TAKEOVER=0

if [[ -n "$TMUX" ]]; then
    # Disambiguate window name: <base> → <base>2 → <base>3 ...
    while tmux list-windows -F '#{window_name}' | grep -qx "$WINDOW"; do
        NUM="${WINDOW#"$BASE"}"
        NUM="${NUM:-1}"
        WINDOW="$BASE$((NUM + 1))"
    done

    pane_count=$(tmux list-panes -F x | wc -l)
    if [[ $pane_count -eq 1 ]]; then
        TAKEOVER=1
        tmux rename-window "$WINDOW"
        W=$(tmux display-message -p '#{session_name}:#{window_index}')
    else
        W=$(tmux new-window -n "$WINDOW" -c "$DIR" -P -F '#{session_name}:#{window_index}')
    fi
else
    if tmux has-session -t "$WINDOW" 2>/dev/null; then
        exec tmux attach-session -t "$WINDOW"
    fi
    tmux new-session -d -s "$WINDOW" -c "$DIR"
    tmux rename-window -t "${WINDOW}:1" "$WINDOW"
    W="${WINDOW}:${WINDOW}"
fi

tmux setw -t "$W" automatic-rename off
tmux split-window -h -t "$W.1" -c "$DIR"
tmux split-window -v -t "$W.2" -c "$DIR"
tmux split-window -v -t "$W.3" -c "$DIR"

tmux set-option -pt "$W.1" @split-dir down
tmux set-option -pt "$W.2" @split-dir up
tmux set-option -pt "$W.3" @split-dir down
tmux set-option -pt "$W.4" @split-dir down
tmux set-option -pt "$W.1" @unclosable 1
tmux set-option -pt "$W.2" @unclosable 1
tmux set-option -pt "$W.3" @unclosable 1
tmux set-option -pt "$W.4" @unclosable 1

if [[ $TAKEOVER -eq 1 ]]; then
    # Script is running in pane 1 — queue cd + claude for after it exits
    tmux send-keys -t "$W.1" "cd $DIR && CLAUDE_LABEL=${BASE}1 claude --effort max" Enter
else
    tmux send-keys -t "$W.1" "CLAUDE_LABEL=${BASE}1 claude --effort max" Enter
fi

tmux send-keys -t "$W.2" "CLAUDE_LABEL=${BASE}2 claude --effort max" Enter

tmux select-pane -t "$W.1"

if [[ -z "$TMUX" ]]; then
    exec tmux attach-session -t "$WINDOW"
fi

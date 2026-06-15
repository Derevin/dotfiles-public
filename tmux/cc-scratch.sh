#!/usr/bin/env bash
# Toggle scratch window. Alt+t opens it zoomed; close returns to previous window.

WINDOW_NAME=$(tmux display-message -p '#{window_name}')

# Already on scratch → return to previous window.
# Use tmux's last-window so navigation-based entry (Alt+[ / Alt+]) also returns correctly.
if [[ "$WINDOW_NAME" == "scratch" ]]; then
    tmux last-window
    exit 0
fi

CALLER_PATH=$(tmux display-message -p '#{pane_current_path}')

# Create scratch window if it doesn't exist
if ! tmux list-windows -F '#{window_name}' | grep -q '^scratch$'; then
    tmux new-window -n scratch -c "$CALLER_PATH"
    tmux setw -t :scratch automatic-rename off
    tmux setw -t :scratch @hidden 1
    tmux set-window-option -t :scratch pane-border-status top
    tmux set-window-option -t :scratch pane-border-format " scratch "
    exit 0
fi

# Scratch exists — find idle pane, cd, switch, zoom
TARGET=$(tmux list-panes -t :scratch -F '#{pane_index} #{pane_current_command}' \
    | awk '$2 ~ /^(bash|zsh)$/ {print $1; exit}')

if [[ -z "$TARGET" ]]; then
    tmux select-window -t :scratch
    TARGET=$(tmux split-window -t :scratch -v -P -F '#{pane_index}' -c "$CALLER_PATH")
else
    tmux send-keys -t ":scratch.$TARGET" "cd '$CALLER_PATH'" Enter
    tmux select-window -t :scratch
fi

tmux select-pane -t ":scratch.$TARGET"
[[ "$(tmux display-message -p '#{window_zoomed_flag}')" != "1" ]] && tmux resize-pane -Z 2>/dev/null

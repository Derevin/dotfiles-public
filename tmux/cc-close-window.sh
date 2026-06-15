#!/usr/bin/env bash
# Close current window. If inspect window, swap Claude back to overview first.
# Otherwise, kill any inspect windows that were spawned from this window.

WINDOW_NAME=$(tmux display-message -p '#{window_name}')

if [[ "$WINDOW_NAME" =~ ^i[0-9]*[1-9]$ ]]; then
    STORED_PANE=$(tmux show-window-options -vt ":${WINDOW_NAME}" @overview_pane_id 2>/dev/null)
    if [[ -n "$STORED_PANE" ]]; then
        INSPECT_CLAUDE_PANE=$(tmux display-message -t ":${WINDOW_NAME}.2" -p '#{pane_id}')
        tmux swap-pane -s "$STORED_PANE" -t "$INSPECT_CLAUDE_PANE"
    fi
elif [[ "$WINDOW_NAME" != "scratch" ]]; then
    tmux list-windows -F '#{window_name}' | grep -E '^i[0-9]*[1-9]$' | while read -r w; do
        src=$(tmux show-window-options -vt ":$w" @source_window 2>/dev/null)
        [[ "$src" == "$WINDOW_NAME" ]] && tmux kill-window -t ":$w" 2>/dev/null || true
    done
fi

tmux kill-window -t ":${WINDOW_NAME}"

#!/usr/bin/env bash
# Close current window, reaping the in-backend process tree of every worktree pane.

if [[ "${1:-}" == "--help" ]]; then
    echo "Close the current window, reaping worktree backend processes first."
    echo "Usage: close-window.sh"
    exit 0
fi

WINDOW_NAME=$(tmux display-message -p '#{window_name}')

# Reap each worktree pane's in-backend process tree before the window dies —
# kill-window only SIGHUPs the local docker-exec/coder-ssh clients, orphaning
# everything inside the container/workspace (see wt-cleanup.sh). Detached
# so the window closes instantly.
tmux list-panes -t ":${WINDOW_NAME}" -F '#{pane_id} #{@wt}' | while read -r pid wt; do
    [[ -n "$wt" ]] || continue
    setsid wt-cleanup.sh "$wt" "$pid" </dev/null >/dev/null 2>&1 &
done

tmux kill-window -t ":${WINDOW_NAME}"

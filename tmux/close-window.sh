#!/usr/bin/env bash
# Close current window, reaping the in-backend process tree of every lab pane.

if [[ "${1:-}" == "--help" ]]; then
    echo "Close the current window, reaping lab backend processes first."
    echo "Usage: close-window.sh"
    exit 0
fi

WINDOW_NAME=$(tmux display-message -p '#{window_name}')

# Reap each lab pane's in-backend process tree before the window dies —
# kill-window only SIGHUPs the local docker-exec/coder-ssh clients, orphaning
# everything inside the container/workspace (see lab-cleanup.sh). Detached
# so the window closes instantly.
tmux list-panes -t ":${WINDOW_NAME}" -F '#{pane_id} #{@lab}' | while read -r pid lab; do
    [[ -n "$lab" ]] || continue
    setsid lab-cleanup.sh "$lab" "$pid" </dev/null >/dev/null 2>&1 &
done

tmux kill-window -t ":${WINDOW_NAME}"

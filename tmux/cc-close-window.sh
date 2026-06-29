#!/usr/bin/env bash
# Close current window. If inspect window, swap Claude back to overview first.
# Otherwise, reap the in-backend process tree of every worktree pane, then kill
# any inspect windows that were spawned from this window.

WINDOW_NAME=$(tmux display-message -p '#{window_name}')

if [[ "$WINDOW_NAME" =~ ^i[0-9]*[1-9]$ ]]; then
    # Inspect window: its pane is a swapped-in view of a live overview pane —
    # swap it back to safety, and do NOT reap (the work lives on in the overview).
    STORED_PANE=$(tmux show-window-options -vt ":${WINDOW_NAME}" @overview_pane_id 2>/dev/null)
    if [[ -n "$STORED_PANE" ]]; then
        INSPECT_CLAUDE_PANE=$(tmux display-message -t ":${WINDOW_NAME}.2" -p '#{pane_id}')
        tmux swap-pane -s "$STORED_PANE" -t "$INSPECT_CLAUDE_PANE"
    fi
elif [[ "$WINDOW_NAME" != "scratch" ]]; then
    # Reap each worktree pane's in-backend process tree before the window dies —
    # kill-window only SIGHUPs the local docker-exec/coder-ssh clients, orphaning
    # everything inside the container/workspace (see cc-wt-cleanup.sh). Detached
    # so the window closes instantly.
    tmux list-panes -t ":${WINDOW_NAME}" -F '#{pane_id} #{@wt}' | while read -r pid wt; do
        [[ -n "$wt" ]] || continue
        setsid cc-wt-cleanup.sh "$wt" "$pid" </dev/null >/dev/null 2>&1 &
    done
    tmux list-windows -F '#{window_name}' | grep -E '^i[0-9]*[1-9]$' | while read -r w; do
        src=$(tmux show-window-options -vt ":$w" @source_window 2>/dev/null)
        [[ "$src" == "$WINDOW_NAME" ]] && tmux kill-window -t ":$w" 2>/dev/null || true
    done
fi

tmux kill-window -t ":${WINDOW_NAME}"

#!/usr/bin/env bash
# Close pane with context-aware behavior (Alt+w).
# 1. Zoomed  → unzoom
# 2. Default → kill pane

if [[ "${1:-}" == "--help" ]]; then
    echo "Close the current pane; a zoomed pane unzooms instead."
    echo "Usage: close-pane.sh"
    exit 0
fi

ZOOMED=$(tmux display-message -p '#{window_zoomed_flag}')

# Zoomed → just unzoom
if [[ "$ZOOMED" == "1" ]]; then
    tmux resize-pane -Z
    exit 0
fi

# Unclosable pane (e.g. overview originals) → no-op
if [[ "$(tmux show-options -pv @unclosable 2>/dev/null)" == "1" ]]; then
    exit 0
fi

# Default → save editor (if any), reap any in-backend process tree, then kill pane.
# A docker-exec/coder-ssh lab pane leaves its in-container processes running on
# kill-pane (the client has no signal proxying); lab-cleanup.sh SIGTERMs them by
# their inherited LAB_PANE_ID tag. Detached so the pane closes instantly. The
# lab itself is untouched — closing a pane is not a teardown.
save-editor.sh
LAB=$(tmux show-options -pv @lab 2>/dev/null)
if [[ -n "$LAB" ]]; then
    PANE_ID=$(tmux display-message -p '#{pane_id}')
    setsid lab-cleanup.sh "$LAB" "$PANE_ID" </dev/null >/dev/null 2>&1 &
fi
tmux kill-pane

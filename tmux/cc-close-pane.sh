#!/usr/bin/env bash
# Close pane with context-aware behavior (Alt+w).
# 1. Zoomed         → unzoom
# 2. Inspect window → toggle back via cc-inspect.sh
# 3. Default        → kill pane

if [[ "${1:-}" == "--help" ]]; then
    echo "Close the current pane; zoomed and inspect windows get their own behaviour."
    echo "Usage: cc-close-pane.sh"
    exit 0
fi

WINDOW_NAME=$(tmux display-message -p '#{window_name}')
ZOOMED=$(tmux display-message -p '#{window_zoomed_flag}')

# Zoomed → just unzoom
if [[ "$ZOOMED" == "1" ]]; then
    tmux resize-pane -Z
    exit 0
fi

# Inspect window → toggle back
if [[ "$WINDOW_NAME" =~ ^i[0-9]*[1-9]$ ]]; then
    exec cc-inspect.sh
fi

# Unclosable pane (e.g. overview originals) → no-op
if [[ "$(tmux show-options -pv @unclosable 2>/dev/null)" == "1" ]]; then
    exit 0
fi

# Default → save editor (if any), reap any in-backend process tree, then kill pane.
# A docker-exec/coder-ssh worktree pane leaves its in-container processes running
# on kill-pane (the client has no signal proxying); cc-wt-cleanup.sh SIGTERMs them
# by their inherited WT_PANE_ID tag. Detached so the pane closes instantly.
cc-save-editor.sh
WT=$(tmux show-options -pv @wt 2>/dev/null)
if [[ -n "$WT" ]]; then
    PANE_ID=$(tmux display-message -p '#{pane_id}')
    setsid cc-wt-cleanup.sh "$WT" "$PANE_ID" </dev/null >/dev/null 2>&1 &
fi
tmux kill-pane

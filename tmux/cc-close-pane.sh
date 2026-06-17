#!/usr/bin/env bash
# Close pane with context-aware behavior (Alt+w).
# 1. Scratch        → kill pane if idle, return to caller
# 2. Zoomed other   → unzoom
# 3. Inspect window → toggle back via cc-inspect.sh
# 4. Default        → kill pane

WINDOW_NAME=$(tmux display-message -p '#{window_name}')
ZOOMED=$(tmux display-message -p '#{window_zoomed_flag}')

# Scratch → kill pane if idle, return to previous window
if [[ "$WINDOW_NAME" == "scratch" ]]; then
    [[ "$ZOOMED" == "1" ]] && tmux resize-pane -Z
    # Capture target BEFORE kill — tmux's last-window updates if the kill destroys scratch.
    TARGET=$(tmux display-message -t '{last}' -p '#{window_id}' 2>/dev/null)
    PANE_CMD=$(tmux display-message -p '#{pane_current_command}')
    [[ "$PANE_CMD" =~ ^(bash|zsh)$ ]] && tmux kill-pane
    # If still on scratch (busy pane skipped kill, or other panes alive), navigate to target.
    # If scratch died, tmux already auto-focused to last-window (= captured target).
    if [[ -n "$TARGET" ]] && [[ "$(tmux display-message -p '#{window_name}')" == "scratch" ]]; then
        tmux select-window -t "$TARGET" 2>/dev/null
    fi
    exit 0
fi

# Zoomed (not scratch) → just unzoom
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

# Default → save editor (if any), then kill pane
cc-save-editor.sh
tmux kill-pane

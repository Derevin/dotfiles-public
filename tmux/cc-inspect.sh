#!/usr/bin/env bash
# Toggle between overview and inspect window for a quadrant.

WINDOW_NAME=$(tmux display-message -p '#{window_name}')

# In inspect window → swap Claude back to overview, keep inspect window alive
if [[ "$WINDOW_NAME" =~ ^i[0-9]*[1-9]$ ]]; then
    STORED_PANE=$(tmux show-window-options -vt ":${WINDOW_NAME}" @overview_pane_id 2>/dev/null)
    SOURCE_WIN=$(tmux show-window-options -vt ":${WINDOW_NAME}" @source_window 2>/dev/null)
    SOURCE_WIN="${SOURCE_WIN:-overview}"
    if [[ -n "$STORED_PANE" ]]; then
        INSPECT_CLAUDE_PANE=$(tmux display-message -t ":${WINDOW_NAME}.2" -p '#{pane_id}')
        tmux swap-pane -s "$STORED_PANE" -t "$INSPECT_CLAUDE_PANE"
    fi
    tmux select-window -t ":${SOURCE_WIN}"
    exit 0
fi

# In source window → inspect current pane's quadrant
PANE_INDEX=$(tmux display-message -p '#{pane_index}')
PANE_PATH=$(tmux display-message -p '#{pane_current_path}')
PANE_ID=$(tmux display-message -p '#{pane_id}')
# Derive inspect prefix from overview suffix (overview→i, overview2→i2, etc.)
SUFFIX=""
if [[ "$WINDOW_NAME" == overview* ]]; then
    SUFFIX="${WINDOW_NAME#overview}"
fi
INSPECT_WIN="i${SUFFIX}${PANE_INDEX}"

# Inspect window exists → re-swap Claude in and switch (preserves nvim/console context)
if tmux list-windows -F '#{window_name}' | grep -q "^${INSPECT_WIN}$"; then
    PLACEHOLDER=$(tmux show-window-options -vt ":${INSPECT_WIN}" @overview_pane_id 2>/dev/null)
    if [[ -n "$PLACEHOLDER" ]]; then
        tmux swap-pane -s "$PANE_ID" -t "$PLACEHOLDER"
    fi
    tmux select-window -t ":${INSPECT_WIN}"
    tmux select-pane -t ":${INSPECT_WIN}.2"
    exit 0
fi

# Create 3-pane inspect layout:
#   pane 1 (left 50%)         — code/nvim
#   pane 2 (right top 75%)    — Claude (will be swapped with overview pane)
#   pane 3 (right bottom 25%) — console
tmux new-window -n "$INSPECT_WIN" -c "$PANE_PATH"
tmux setw -t ":${INSPECT_WIN}" automatic-rename off
tmux setw -t ":${INSPECT_WIN}" @hidden 1
tmux split-window -t ":${INSPECT_WIN}" -h -c "$PANE_PATH" -l 50%
tmux split-window -t ":${INSPECT_WIN}.2" -v -c "$PANE_PATH" -l 25%
tmux send-keys -t ":${INSPECT_WIN}.1" "nvim" Enter

# Tag default panes as unclosable
for p in 1 2 3; do
    tmux set-option -pt ":${INSPECT_WIN}.$p" @unclosable 1
done

# Swap the overview Claude pane into the inspect window's Claude slot (pane 2)
INSPECT_CLAUDE_PANE=$(tmux display-message -t ":${INSPECT_WIN}.2" -p '#{pane_id}')
tmux swap-pane -s "$PANE_ID" -t "$INSPECT_CLAUDE_PANE"

# Store placeholder pane ID — it bounces between inspect pos 2 and overview on each toggle
tmux set-window-option -t ":${INSPECT_WIN}" @overview_pane_id "$INSPECT_CLAUDE_PANE"
tmux set-window-option -t ":${INSPECT_WIN}" @source_window "$WINDOW_NAME"

tmux select-pane -t ":${INSPECT_WIN}.2"

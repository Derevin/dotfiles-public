#!/usr/bin/env bash
# Toggle pane zoom (Alt+z), then briefly overstate the pane's height.
#
# The width change makes Claude Code re-render, but only as much as fits the
# pane, so the rest of the message keeps the old width's wrapping. Rows are the
# only lever on how much it redraws — a taller pane buys a taller re-render,
# which lands in scrollback intact. Restored straight after, so the input box
# isn't laid out for a height that isn't there.

if [[ "${1:-}" == "--help" ]]; then
    echo "Toggle zoom on the current pane, forcing a taller re-render after the resize."
    echo "Usage: zoom.sh"
    exit 0
fi

ROWS_FACTOR=2
SETTLE=0.2

WIDTH_BEFORE=$(tmux display-message -p '#{pane_width}')
tmux resize-pane -Z
read -r TTY CMD COLS ROWS <<<"$(tmux display-message -p '#{pane_tty} #{pane_current_command} #{pane_width} #{pane_height}')"

# Nothing re-wraps unless the width moved (a sole pane zooms to the same size),
# and only Claude Code re-renders on resize — any other pane just gets a lie.
[[ "$COLS" != "$WIDTH_BEFORE" ]] || exit 0
[[ "$CMD" == "claude" ]] || exit 0

trap 'stty -F "$TTY" rows "$ROWS" 2>/dev/null' EXIT
stty -F "$TTY" rows $((ROWS * ROWS_FACTOR))
sleep "$SETTLE"

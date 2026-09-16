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
# '|' rather than spaces: @backend and @lab are both empty off a lab, and default
# IFS collapses the gap and shifts every field after it.
IFS='|' read -r TTY CMD COLS ROWS BACKEND LAB <<<"$(tmux display-message -p '#{pane_tty}|#{pane_current_command}|#{pane_width}|#{pane_height}|#{@backend}|#{@lab}')"

# Nothing re-wraps unless the width moved (a sole pane zooms to the same size).
[[ "$COLS" != "$WIDTH_BEFORE" ]] || exit 0
# Only Claude Code re-renders on resize — any other pane just gets a lie. A
# docker/coder lab runs it behind a client, which is all the host sees as the
# pane command, so @lab stands in and the resize proxies to the backend pty. A
# host lab reports its own command and needs no stand-in.
[[ "$CMD" == "claude" || ( -n "$LAB" && "$BACKEND" != host ) ]] || exit 0

trap 'stty -F "$TTY" rows "$ROWS" 2>/dev/null' EXIT
stty -F "$TTY" rows $((ROWS * ROWS_FACTOR))
sleep "$SETTLE"

#!/usr/bin/env bash
# Toggle pane zoom (Alt+z).

if [[ "${1:-}" == "--help" ]]; then
    echo "Toggle zoom on the current pane."
    echo "Usage: zoom.sh"
    exit 0
fi

tmux resize-pane -Z

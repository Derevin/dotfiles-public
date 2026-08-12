#!/bin/bash
# Select pane by quadrant tag, fallback to index. Stays zoomed if the window is.
# Usage: cc-select-pane.sh <number>

if [[ "${1:-}" == "--help" ]]; then
    echo "Select a pane by quadrant tag, falling back to index. Keeps the window zoomed."
    echo "Usage: cc-select-pane.sh <number>"
    exit 0
fi

n=$1
p=$(tmux list-panes -F '#{@quadrant} #{pane_id}' 2>/dev/null | awk -v n="$n" '$1==n{print $2; exit}')
tmux select-pane -Z -t "${p:-$n}" 2>/dev/null || true

#!/bin/bash
# Select pane by quadrant tag, fallback to index.
# Usage: cc-select-pane.sh <number>
n=$1
p=$(tmux list-panes -F '#{@quadrant} #{pane_id}' 2>/dev/null | awk -v n="$n" '$1==n{print $2; exit}')
tmux select-pane -t "${p:-$n}" 2>/dev/null || true

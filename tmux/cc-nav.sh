#!/usr/bin/env bash
# Navigate to next/prev window, skipping any window tagged with @hidden.
# Usage: cc-nav.sh next|prev

if [[ "${1:-}" == "--help" ]]; then
    echo "Navigate to next/prev window, skipping windows tagged with @hidden."
    echo "Usage: cc-nav.sh next|prev"
    exit 0
fi

TARGETS=$(tmux list-windows -F '#{?@hidden,,#{window_index}}' | awk 'NF')
CURRENT=$(tmux display-message -p '#{window_index}')

WINS=($TARGETS)
COUNT=${#WINS[@]}
[[ $COUNT -eq 0 ]] && exit 0

# Find current position
for i in "${!WINS[@]}"; do
    [[ "${WINS[$i]}" == "$CURRENT" ]] && POS=$i && break
done

# Sole visible window: no-op if already there, otherwise escape to it
if [[ $COUNT -eq 1 ]]; then
    [[ -z "$POS" ]] && tmux select-window -t "${WINS[0]}"
    exit 0
fi

# Hidden caller: pick visible neighbor by index proximity, wrap on miss
if [[ -z "$POS" ]]; then
    if [[ "$1" == "next" ]]; then
        for w in "${WINS[@]}"; do
            (( w > CURRENT )) && { tmux select-window -t "$w"; exit 0; }
        done
        tmux select-window -t "${WINS[0]}"
    else
        for ((i=COUNT-1; i>=0; i--)); do
            (( ${WINS[$i]} < CURRENT )) && { tmux select-window -t "${WINS[$i]}"; exit 0; }
        done
        tmux select-window -t "${WINS[$((COUNT-1))]}"
    fi
    exit 0
fi

if [[ "$1" == "next" ]]; then
    tmux select-window -t "${WINS[$(( (POS + 1) % COUNT ))]}"
else
    tmux select-window -t "${WINS[$(( (POS - 1 + COUNT) % COUNT ))]}"
fi

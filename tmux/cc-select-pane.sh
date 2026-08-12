#!/bin/bash
# Select a pane by quadrant tag (fallback index), or move focus in a direction.
# Keeps the window zoomed either way.
# Usage: cc-select-pane.sh <number|L|R|U|D>

if [[ "${1:-}" == "--help" ]]; then
    echo "Select a pane by quadrant tag/index, or move focus L/R/U/D. Keeps the window zoomed."
    echo "Usage: cc-select-pane.sh <number|L|R|U|D>"
    exit 0
fi

n=$1

case "$n" in
[LRUD])
    # select-pane wraps at the window edge, so the move needs an edge guard, and
    # a zoomed pane spans the window: #{pane_at_left} and friends report it at
    # all four edges. The layout string keeps the unzoomed geometry, so the guard
    # reads off that; unzooming to run the test would make an edge press churn.
    read -r pid layout <<<"$(tmux display-message -p '#{pane_id} #{window_layout}')"
    root=${layout#*,}   # drop the checksum: <win-w>x<win-h>,0,0<cells>
    rh=${root#*x}
    # Cells are WxH,X,Y for containers, WxH,X,Y,pane-id for panes.
    at_edge=$(grep -oE '[0-9]+x[0-9]+,[0-9]+,[0-9]+,[0-9]+' <<<"$layout" |
        awk -F'[x,]' -v id="${pid#%}" -v rw="${root%%x*}" -v rh="${rh%%,*}" -v d="$n" '
            $5 != id { next }
            { print (d == "L") ? ($3 == 0) :
                    (d == "U") ? ($4 == 0) :
                    (d == "R") ? ($3 + $1 == rw) : ($4 + $2 == rh); exit }')
    [[ $at_edge == 1 ]] && exit 0
    tmux select-pane -Z "-$n" 2>/dev/null || true
    ;;
*)
    p=$(tmux list-panes -F '#{@quadrant} #{pane_id}' 2>/dev/null | awk -v n="$n" '$1==n{print $2; exit}')
    tmux select-pane -Z -t "${p:-$n}" 2>/dev/null || true
    ;;
esac

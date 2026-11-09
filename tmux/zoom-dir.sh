#!/bin/bash
# Store a direction arrow for the active pane's place in the window, read by the
# status bar beside the zoom "Z". Window-thirds -> one of eight arrows; blank for
# a centred or sole pane, where no direction is meaningful.
# Usage: zoom-dir.sh

if [[ "${1:-}" == "--help" ]]; then
    echo "Set @zoom_dir to a direction arrow for the active pane's position (status-bar zoom indicator)."
    echo "Usage: zoom-dir.sh"
    exit 0
fi

read -r pid layout <<<"$(tmux display-message -p '#{pane_id} #{window_layout}')"
# A zoomed pane spans the window and reports itself at all four edges, so read
# geometry off the layout, which keeps the unzoomed cells: <win-w>x<win-h>,0,0...
root=${layout#*,}   # drop the checksum
rw=${root%%x*}
rh=${root#*x}; rh=${rh%%,*}

# Cells are WxH,X,Y for containers, WxH,X,Y,pane-id for panes. Match the active
# pane, place its centre in a 3x3 grid, name the quadrant.
arrow=$(grep -oE '[0-9]+x[0-9]+,[0-9]+,[0-9]+,[0-9]+' <<<"$layout" |
    awk -F'[x,]' -v id="${pid#%}" -v rw="$rw" -v rh="$rh" '
        $5 != id { next }
        {
            cx = $3 + $1 / 2; cy = $4 + $2 / 2
            h = (cx * 3 < rw) ? "L" : (cx * 3 > rw * 2) ? "R" : "C"
            v = (cy * 3 < rh) ? "U" : (cy * 3 > rh * 2) ? "D" : "C"
            m["UL"] = "↖"; m["UC"] = "↑"; m["UR"] = "↗"
            m["CL"] = "←"; m["CC"] = "";  m["CR"] = "→"
            m["DL"] = "↙"; m["DC"] = "↓"; m["DR"] = "↘"
            print m[v h]; exit
        }')
tmux set-option -w @zoom_dir "$arrow"

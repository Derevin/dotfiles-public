#!/bin/bash
# Left-pad the window list so the middle window sits at the screen centre: with
# an odd visible count the middle window's centre lands there, with an even count
# the gap between the two middle windows does. Printed into status-left, which
# status-justify left then places the list after. Recomputed each status-interval
# via the #() job in .tmux.conf.
# Usage: window-center.sh <client_width> <session>

if [[ "${1:-}" == "--help" ]]; then
    echo "Print the left padding that centres the window list on its middle window (odd) or middle gap (even)."
    echo "Usage: window-center.sh <client_width> <session>"
    exit 0
fi

set -uo pipefail

# Pure, tmux-free so tests can drive it: given the bar width, the separator
# width, and each window's rendered width (0 = hidden), echo the left padding in
# columns. Centre is width/2 - the clock on the right is drawn independently and
# does not shift it. Visible = width > 0; the centre reference is the middle
# visible window (odd) or the midpoint between the two middle ones (even),
# measured in half-columns to stay integer.
window_center_pad() {
    local width=$1 sep=$2
    shift 2
    local -a w=("$@")
    local n=${#w[@]}
    ((n == 0)) && { echo 0; return; }

    # off[i]: first column of window i. A separator sits between every adjacent
    # pair, including around hidden (zero-width) windows, so i of them precede i.
    local -a off=()
    local acc=0 i
    for ((i = 0; i < n; i++)); do
        off[i]=$((acc + i * sep))
        acc=$((acc + ${w[i]}))
    done

    local -a vis=()
    for ((i = 0; i < n; i++)); do ((${w[i]} > 0)) && vis+=("$i"); done
    local nv=${#vis[@]}
    ((nv == 0)) && { echo 0; return; }

    # ref2 = 2x the reference column, so the odd-case half-window stays integer.
    local ref2
    if ((nv % 2 == 1)); then
        local m=${vis[nv / 2]}
        ref2=$((2 * ${off[m]} + ${w[m]}))
    else
        local a=${vis[nv / 2 - 1]} b=${vis[nv / 2]}
        ref2=$((${off[a]} + ${w[a]} + ${off[b]}))
    fi

    # pad = centre - ref = (width - ref2) / 2, rounded, clamped at 0.
    local twice=$((width - ref2))
    ((twice <= 0)) && { echo 0; return; }
    echo $(((twice + 1) / 2))
}

_strip_width() {
    # Drop #[...] style directives, then count characters (display columns for
    # the ASCII indices, names, and single-cell zoom arrows in play here).
    local s=${1//$'\n'/}
    while [[ $s == *'#['*']'* ]]; do
        local pre=${s%%'#['*}
        local post=${s#*']'}
        s=$pre$post
    done
    echo ${#s}
}

_main() {
    local width=${1:-0} session=${2:-}
    [[ -n $session ]] || { printf ''; return; }

    local sep_s
    sep_s=$(tmux display-message -p -t "$session" '#{window-status-separator}' 2>/dev/null) || return
    local sep=${#sep_s}

    # One call for every window's rendered label, in order.
    local -a widths=()
    local label
    while IFS= read -r label; do
        widths+=("$(_strip_width "$label")")
    done < <(tmux list-windows -t "$session" -F '#{T:window-status-format}' 2>/dev/null)
    ((${#widths[@]})) || { printf ''; return; }

    local pad
    pad=$(window_center_pad "$width" "$sep" "${widths[@]}")
    printf '%*s' "$pad" ''
}

# Run only when executed; tests source the file for window_center_pad alone.
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    _main "$@"
fi

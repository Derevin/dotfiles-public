#!/usr/bin/env bash
# One pane per existing lab, in a window of its own.
#
# The panes are shells, not resumed Claude sessions: this window is for looking,
# and for running something against a lab you are already standing in. Not
# @unclosable. Past four labs it keeps splitting and gets cramped — accepted,
# it is a list to scan rather than a place to work.
#
# Usage: lab-inflight.sh
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Open a window with one shell pane per existing lab."
    echo "Usage: lab-inflight.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# lab-lib.sh sits beside this script once installed; in the repo the tmux and
# script helpers are kept apart, and the private tmux scripts a level further.
for d in "$SCRIPT_DIR" "$SCRIPT_DIR/../scripts" "$SCRIPT_DIR/../public/scripts"; do
    [ -f "$d/lab-lib.sh" ] && { source "$d/lab-lib.sh"; break; }
done
# A miss is otherwise silent: every lab_* call expands to nothing and the caller
# degrades instead of stopping — a pane with no Claude, a recipe on the host.
declare -F lab_resolve >/dev/null || { echo "lab-inflight.sh: cannot find lab-lib.sh" >&2; exit 1; }

mapfile -t LABS < <(lab-list.sh | while read -r n; do lab_is_lab "$n" && echo "$n"; done)
[ "${#LABS[@]}" -gt 0 ] || { echo "no labs"; exit 0; }

WINDOW="inflight"
if [[ -n "${TMUX:-}" ]]; then
    while tmux list-windows -F '#{window_name}' | grep -qx "$WINDOW"; do
        NUM="${WINDOW#inflight}"
        NUM="${NUM:-1}"
        WINDOW="inflight$((NUM + 1))"
    done
    tmux new-window -n "$WINDOW"
else
    tmux new-session -d -s "$WINDOW"
    tmux rename-window -t "${WINDOW}:1" "$WINDOW"
fi

W=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "$WINDOW")
W="${W}:${WINDOW}"
tmux setw -t "$W" automatic-rename off

FIRST=$(tmux display-message -t "$W.1" -p '#{pane_id}')
tmux respawn-pane -k -t "$FIRST" "lab-shell $(lab_sq "${LABS[0]}")"
tmux set-option -pt "$FIRST" @lab "${LABS[0]}"

for lab in "${LABS[@]:1}"; do
    ID=$(tmux split-window -t "$W" -P -F '#{pane_id}' "lab-shell $(lab_sq "$lab")")
    tmux set-option -pt "$ID" @lab "$lab"
    tmux select-layout -t "$W" tiled >/dev/null
done

tmux select-pane -t "$FIRST"

if [[ -z "${TMUX:-}" ]]; then
    exec tmux attach-session -t "$WINDOW"
fi

#!/usr/bin/env bash
# Repopulate a lab window's quadrants from the placement state file.
#
# Only placement is stored; existence is derived. So a row whose lab is gone is
# not an error — the quadrant stays a launchpad and says why. The row survives,
# because a coder round-trip that failed once must not silently erase where
# things were.
#
# Usage: lab-restore.sh <project> <window>
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Repopulate a lab window's quadrants from the saved placements."
    echo "Usage: lab-restore.sh <project> <window>"
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
declare -F lab_resolve >/dev/null || { echo "lab-restore.sh: cannot find lab-lib.sh" >&2; exit 1; }

PROJECT="${1:-}"
WINDOW="${2:-}"
[ -n "$PROJECT" ] && [ -n "$WINDOW" ] || { echo "usage: lab-restore.sh <project> <window>" >&2; exit 2; }

export TMUX=

while IFS=$'\t' read -r quadrant lab; do
    [ -n "$lab" ] || continue
    pane=$(tmux list-panes -t "$WINDOW" -F '#{@quadrant} #{pane_id}' 2>/dev/null \
        | awk -v q="$quadrant" '$1 == q { print $2; exit }')
    [ -n "$pane" ] || continue
    if lab_exists "$lab"; then
        # --continue picks the conversation back up out of the lab's own
        # ~/.claude/projects entry, which the name — and so the path — carries.
        lab-attach.sh --pane "$pane" "$lab" --continue
    else
        # The name comes off the state file and is typed into an interactive
        # shell, so it is quoted rather than interpolated into the literal.
        tmux send-keys -t "$pane" "echo $(lab_sq "lab $lab no longer exists — quadrant left as a launchpad")" Enter
    fi
done < <(lab_state_rows "$PROJECT" "$WINDOW")

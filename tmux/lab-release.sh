#!/usr/bin/env bash
# Revert a quadrant to a launchpad: a plain shell at the project's main
# checkout, backend still set, no lab attached.
#
# Releasing is not a teardown. The lab keeps running; only the view goes away.
# The in-backend process tree this pane started does get reaped, for the same
# reason closing the pane reaps it — the local docker-exec / coder-ssh client
# has no signal proxying, so everything behind it would be orphaned.
#
# Usage: lab-release.sh [--pane <id>]
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Revert a lab quadrant to a launchpad (the lab keeps running)."
    echo "Usage: lab-release.sh [--pane <id>]"
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
declare -F lab_resolve >/dev/null || { echo "lab-release.sh: cannot find lab-lib.sh" >&2; exit 1; }

PANE=""
[ "${1:-}" = "--pane" ] && { PANE="${2:-}"; shift 2; }

SELF_SOCKET="${TMUX:-}"; SELF_SOCKET="${SELF_SOCKET%%,*}"
export TMUX=
[ -n "$PANE" ] || PANE=$(lab_caller_pane "$SELF_SOCKET")
[ -n "$PANE" ] || { echo "lab-release: no target pane" >&2; exit 1; }

LAB=$(tmux show-options -pvt "$PANE" @lab 2>/dev/null || true)
[ -n "$LAB" ] || { echo "lab-release: pane is already a launchpad"; exit 0; }

lab_resolve "$LAB" || exit 1

# respawn-pane -k below kills the target pane's process group, ours included when
# we were typed into that pane. Everything after it — the untag, the backend, the
# dropped placement row — would be lost, leaving a plain shell still claiming a
# lab. Hand the rest to a detached copy.
if [ "$PANE" = "${TMUX_PANE:-}" ] && [ -z "${LAB_RELEASE_DETACHED:-}" ]; then
    LAB_RELEASE_DETACHED=1 setsid "$SCRIPT_DIR/lab-release.sh" --pane "$PANE" \
        </dev/null >/dev/null 2>&1 &
    exit 0
fi

setsid lab-cleanup.sh "$LAB" "$PANE" </dev/null >/dev/null 2>&1 &

# respawn-pane with no command re-runs the pane's ORIGINAL one, which attach set
# to `lab-shell <lab>` — the release would hand the lab straight back, and
# lab-shell would re-tag the pane on its way in. A launchpad runs whatever a
# fresh pane runs, so say so: tmux's own rule is default-command, falling back to
# default-shell as a login shell when it is empty.
LAUNCHPAD_CMD=$(tmux show-options -gv default-command 2>/dev/null || true)
if [ -z "$LAUNCHPAD_CMD" ]; then
    LAUNCHPAD_CMD="$(tmux show-options -gv default-shell 2>/dev/null || echo "${SHELL:-/bin/sh}") -l"
fi
tmux respawn-pane -k -c "$LAB_CHECKOUT" -t "$PANE" "$LAUNCHPAD_CMD"
tmux set-option -pu -t "$PANE" @lab

# A launchpad names no backend, so the released lab's goes with it. Leaving one
# behind would have the quadrant answering for a lab it no longer shows.
tmux set-option -pu -t "$PANE" @backend

# A launchpad is the absence of a row, so the release leaves nothing behind.
IFS='|' read -r WINDOW QUADRANT <<<"$(tmux display-message -t "$PANE" -p '#{window_name}|#{@quadrant}')"
[ -n "${QUADRANT:-}" ] && lab_state_drop "$LAB_PROJECT" "$WINDOW" "$QUADRANT"

echo "released $LAB"

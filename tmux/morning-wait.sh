#!/usr/bin/env bash
# The detached tail of the `go` morning bootstrap: block until sync has finished,
# then open the launchpad and focus the workspace window. go.sh spawns this with
# setsid before handing its pane to the workspace opener, so it outlives that
# takeover and talks only to the tmux server — never the pane it came from.
#
# The sync wait is what makes the launchpad land in a current fleet: sync updates
# every running lab's Claude, and `sync.sh --wait` returns once that has finished
# (or timed out — it never wedges). The epoch is captured by go.sh before the
# workspace opener starts sync, so a stale marker from an earlier sync is ignored.
#
# Usage: morning-wait.sh <epoch> <workspace-window> <launchpad-cmd> [args...]
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Wait for sync to finish, open the launchpad, focus the workspace window."
    echo "Usage: morning-wait.sh <epoch> <workspace-window> <launchpad-cmd> [args...]"
    exit 0
fi

EPOCH="${1:-}"
WINDOW="${2:-}"
[ -n "$EPOCH" ] && [ -n "$WINDOW" ] || { echo "usage: morning-wait.sh <epoch> <window> <launchpad-cmd> [args...]" >&2; exit 2; }
shift 2

sync.sh --wait "$EPOCH"
"$@"
# The window may be gone (closed between launch and now); its absence is not a
# bootstrap failure, so don't let a missing target take the whole flow down.
tmux select-window -t "$WINDOW" 2>/dev/null || true

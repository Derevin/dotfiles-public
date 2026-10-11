#!/usr/bin/env bash
# The detached tail of the `go` morning bootstrap: block until sync has finished,
# open the launchpad, then land where the outcome points — on the labs window the
# launchpad just opened if sync was clean, back on the workspace window if it was
# not. go.sh spawns this with setsid before handing its pane to the workspace
# opener, so it outlives that takeover and talks only to the tmux server — never
# the pane it came from.
#
# The sync wait is what makes the launchpad land in a current fleet: sync updates
# every running lab's Claude, and `sync.sh --wait` returns once that has finished
# (or timed out — it never wedges), exiting with the sync's status. The epoch is
# captured by go.sh before the workspace opener starts sync, so a stale marker
# from an earlier sync is ignored.
#
# Usage: morning-wait.sh <epoch> <workspace-window> <launchpad-cmd> [args...]
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Wait for sync, open the launchpad; land on labs if sync was clean, else the workspace."
    echo "Usage: morning-wait.sh <epoch> <workspace-window> <launchpad-cmd> [args...]"
    exit 0
fi

EPOCH="${1:-}"
WINDOW="${2:-}"
[ -n "$EPOCH" ] && [ -n "$WINDOW" ] || { echo "usage: morning-wait.sh <epoch> <window> <launchpad-cmd> [args...]" >&2; exit 2; }
shift 2

# Wait for sync and remember its outcome: --wait exits non-zero if the sync had
# issues or never finished. The `|| sync_rc=$?` keeps that from tripping set -e,
# so the launchpad opens either way.
sync_rc=0
sync.sh --wait "$EPOCH" || sync_rc=$?
"$@"
# Land where the outcome points: a clean sync leaves focus on the labs window the
# launchpad just opened and focused; a failed one returns to the workspace, whose
# sync strip stays open for inspection. The workspace window may be gone (closed
# between launch and now) — not a bootstrap failure, so swallow a missing target.
if [[ "$sync_rc" -ne 0 ]]; then
    tmux select-window -t "$WINDOW" 2>/dev/null || true
fi

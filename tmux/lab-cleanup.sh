#!/usr/bin/env bash
# Kill the in-backend process tree left behind by a closing or released lab pane.
#
# `tmux kill-pane` only SIGHUPs the LOCAL `docker exec` / `coder ssh` client.
# That client has no signal proxying, so everything it started INSIDE the
# container/workspace — the leader bash and whatever it launched (GUIs, mock
# daemons, `just` recipes) — is orphaned and keeps running. Those processes are
# reachable only by the LAB_PANE_ID env tag that lab-shell/lab-run injected; every
# child inherits it, even after reparenting to init (so a host-side pstree walk
# would miss them). Match on it, SIGTERM, then SIGKILL stragglers.
#
# Usage: lab-cleanup.sh <lab> <pane-id>
#   lab:      a lab or legacy fixture; a host lab is a no-op (kill-pane reaps
#             ordinary children itself)
#   pane-id:  tmux pane id, e.g. %12  (matches LAB_PANE_ID set at launch)
#
# Meant to be run detached — it sleeps through a SIGTERM grace period, so callers
# background it (setsid … &) and the pane closes instantly.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Kill the in-backend process tree of a closing or released lab pane (by LAB_PANE_ID)."
    echo "Usage: lab-cleanup.sh <lab> <pane-id>"
    exit 0
fi

LAB="${1:-}"
PANE_ID="${2:-}"
if [[ -z "$LAB" || -z "$PANE_ID" ]]; then
    echo "usage: lab-cleanup.sh <lab> <pane-id>" >&2
    exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# lab-lib.sh sits beside this script once installed; in the repo the tmux and
# script helpers are kept apart, and the private tmux scripts a level further.
for d in "$SCRIPT_DIR" "$SCRIPT_DIR/../scripts" "$SCRIPT_DIR/../public/scripts"; do
    [ -f "$d/lab-lib.sh" ] && { source "$d/lab-lib.sh"; break; }
done
# A miss is otherwise silent: every lab_* call expands to nothing and the caller
# degrades instead of stopping — a pane with no Claude, a recipe on the host.
declare -F lab_resolve >/dev/null || { echo "lab-cleanup.sh: cannot find lab-lib.sh" >&2; exit 1; }

# Remote killer (runs inside the backend). Anchors the LAB_PANE_ID match on the
# value end so %1 doesn't also match %12/%13 — environ entries are NUL-separated,
# so grep -z makes the trailing $ bind to the value, not a substring. No `set -e`:
# killing an already-dead pid must not abort the sweep.
read -r -d '' KILLER <<'SH' || true
pane_id="$1"
pids=""
for f in $(grep -alzE "LAB_PANE_ID=${pane_id}\$" /proc/*/environ 2>/dev/null); do
    p=${f#/proc/}; pids="$pids ${p%/environ}"
done
[ -n "${pids// }" ] || exit 0
kill -TERM $pids 2>/dev/null || true
for _ in $(seq 1 20); do
    sleep 0.25
    alive=""
    for p in $pids; do [ -e "/proc/$p" ] && alive="$alive $p"; done
    pids="$alive"
    [ -n "${pids// }" ] || exit 0
done
kill -KILL $pids 2>/dev/null || true
SH

# Single-quote each token so `coder ssh --` (which space-joins remote argv and
# lets the workspace shell re-tokenize) reparses the script back into one word.
_coder_cmdline() {
    local a out=""
    for a in "$@"; do out+=" '${a//\'/\'\\\'\'}'"; done
    printf '%s' "$out"
}

lab_resolve "$LAB" 2>/dev/null || exit 0
case "$LAB_BACKEND" in
    docker) docker exec "$LAB_CONTAINER" bash -c "$KILLER" _ "$PANE_ID" ;;
    coder) coder ssh "$LAB_CONTAINER" -- "$(_coder_cmdline bash -c "$KILLER" _ "$PANE_ID")" ;;
    *) exit 0 ;;
esac

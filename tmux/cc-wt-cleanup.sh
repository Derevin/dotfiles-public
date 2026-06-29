#!/usr/bin/env bash
# Kill the in-backend process tree left behind by a closing worktree pane.
#
# `tmux kill-pane` only SIGHUPs the LOCAL `docker exec` / `coder ssh` client.
# That client has no signal proxying, so everything it started INSIDE the
# container/workspace — the leader bash and whatever it launched (GUIs, mock
# daemons, `just` recipes) — is orphaned and keeps running. Those processes are
# reachable only by the WT_PANE_ID env tag that wt-shell/wt-run injected; every
# child inherits it, even after reparenting to init (so a host-side pstree walk
# would miss them). Match on it, SIGTERM, then SIGKILL stragglers.
#
# Usage: cc-wt-cleanup.sh <wt-slot> <pane-id>
#   wt-slot:  dwtN | cwtN  (backend from first letter: d→docker, c→coder)
#   pane-id:  tmux pane id, e.g. %12  (matches WT_PANE_ID set at launch)
#
# Meant to be run detached — it sleeps through a SIGTERM grace period, so callers
# background it (setsid … &) and the pane closes instantly.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Kill the in-backend process tree of a closing worktree pane (by WT_PANE_ID)."
    echo "Usage: cc-wt-cleanup.sh <wt-slot> <pane-id>"
    exit 0
fi

WT="${1:-}"
PANE_ID="${2:-}"
if [[ -z "$WT" || -z "$PANE_ID" ]]; then
    echo "usage: cc-wt-cleanup.sh <wt-slot> <pane-id>" >&2
    exit 2
fi

# Worktree backend config (private; absent on public installs → empty defaults).
WT_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/worktree.conf"
[ -f "$WT_CONF" ] && . "$WT_CONF"
WT_CONTAINER_PREFIX="${WT_CONTAINER_PREFIX:-}"

# Remote killer (runs inside the backend). Anchors the WT_PANE_ID match on the
# value end so %1 doesn't also match %12/%13 — environ entries are NUL-separated,
# so grep -z makes the trailing $ bind to the value, not a substring. No `set -e`:
# killing an already-dead pid must not abort the sweep.
read -r -d '' KILLER <<'SH' || true
pane_id="$1"
pids=""
for f in $(grep -alzE "WT_PANE_ID=${pane_id}\$" /proc/*/environ 2>/dev/null); do
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

case "${WT:0:1}" in
    d) docker exec "${WT_CONTAINER_PREFIX}$WT" bash -c "$KILLER" _ "$PANE_ID" ;;
    c) coder ssh "${WT_CONTAINER_PREFIX}$WT" -- "$(_coder_cmdline bash -c "$KILLER" _ "$PANE_ID")" ;;
    *) exit 0 ;;
esac

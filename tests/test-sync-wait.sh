#!/usr/bin/env bash
# Tests sync.sh --wait: the gate the `go` bootstrap blocks on before opening the
# launchpad. It must return at once on a fresh done-marker, and time out to 0 on
# a stale, absent, or never-touched one — a stalled sync must never wedge.
#
# --wait short-circuits before any network or install work, so this runs the real
# sync.sh safely; the non-wait flow is never entered.
# Usage: test-sync-wait.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the sync.sh --wait unit tests."
    echo "Usage: test-sync-wait.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
SYNC="$SCRIPT_DIR/../scripts/sync.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export XDG_RUNTIME_DIR="$TMP/run"
mkdir -p "$XDG_RUNTIME_DIR"
MARKER="$XDG_RUNTIME_DIR/dotfiles-sync.done"

# --- fresh marker returns at once --------------------------------------------
t0=$(date +%s)
touch -d "@$((t0 + 5))" "$MARKER"
"$SYNC" --wait "$t0"; ok "returns 0 on fresh marker" "$?" 0

# --- stale marker times out to 0 (does not accept an earlier sync) ------------
touch -d "@$((t0 - 100))" "$MARKER"
start=$(date +%s)
DOTFILES_SYNC_WAIT_TIMEOUT=1 "$SYNC" --wait "$t0"; rc=$?
end=$(date +%s)
ok "times out to 0 on stale marker" "$rc" 0
[ "$((end - start))" -le 4 ]; ok "timeout is bounded" "$?" 0

# --- absent marker times out to 0 --------------------------------------------
rm -f "$MARKER"
DOTFILES_SYNC_WAIT_TIMEOUT=1 "$SYNC" --wait "$(date +%s)"; ok "exits 0 with no marker" "$?" 0

report

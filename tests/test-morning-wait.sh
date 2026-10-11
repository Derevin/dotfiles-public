#!/usr/bin/env bash
# Unit tests for morning-wait.sh: the detached step of the `go` bootstrap. It
# waits for sync, opens the launchpad, then lands where the outcome points — on
# the labs window the launchpad opened when sync was clean, back on the workspace
# window when it was not.
#
# Self-contained: no real sync or tmux. `sync.sh`, `tmux` and the launchpad
# opener are faked on a prepended PATH, each logging its call to $CALLS, so the
# order the log records is the order morning-wait.sh ran them. The sync fake exits
# FAKE_SYNC_RC, so both outcomes can be driven.
# Usage: test-morning-wait.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the morning-wait.sh unit tests."
    echo "Usage: test-morning-wait.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
MW="$SCRIPT_DIR/../tmux/morning-wait.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"
export CALLS="$TMP/calls"

# Fakes: each logs its invocation so order is observable. sync.sh and tmux are
# called by bare name from morning-wait.sh; the launchpad opener is passed in.
cat > "$BIN/sync.sh" <<'EOF'
#!/usr/bin/env bash
echo "sync:$*" >> "$CALLS"
exit "${FAKE_SYNC_RC:-0}"
EOF
cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
echo "tmux:$*" >> "$CALLS"
EOF
cat > "$BIN/fake-launchpad.sh" <<'EOF'
#!/usr/bin/env bash
echo "launchpad:$*" >> "$CALLS"
EOF
chmod +x "$BIN/sync.sh" "$BIN/tmux" "$BIN/fake-launchpad.sh"

# --- clean sync: wait, launchpad, then stay on labs (no select-window) --------
: > "$CALLS"
FAKE_SYNC_RC=0 "$MW" 12345 dotbee fake-launchpad.sh go; rc=$?
ok "exit 0 on a clean sync" "$rc" 0
got=$(cat "$CALLS")
want=$(printf '%s\n' "sync:--wait 12345" "launchpad:go")
ok "clean sync: waits, opens launchpad, leaves focus on labs" "$got" "$want"

# --- failed sync: wait, launchpad, then return to the workspace window --------
: > "$CALLS"
FAKE_SYNC_RC=1 "$MW" 999 dotspell fake-launchpad.sh go; rc=$?
ok "exit 0 on a failed sync" "$rc" 0
got=$(cat "$CALLS")
want=$(printf '%s\n' "sync:--wait 999" "launchpad:go" "tmux:select-window -t dotspell")
ok "failed sync: waits, opens launchpad, returns to workspace" "$got" "$want"

# --- a failing select-window must not fail the bootstrap ----------------------
cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
echo "tmux:$*" >> "$CALLS"
exit 1
EOF
chmod +x "$BIN/tmux"
: > "$CALLS"
FAKE_SYNC_RC=1 "$MW" 1 dotspell fake-launchpad.sh; ok "survives a missing workspace window" "$?" 0

report

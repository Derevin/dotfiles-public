#!/usr/bin/env bash
# Unit tests for morning-wait.sh: the detached step of the `go` bootstrap. It
# waits for sync to finish, opens the launchpad, then focuses the workspace
# window — and must do exactly that, in that order.
#
# Self-contained: no real sync or tmux. `sync.sh`, `tmux` and the launchpad
# opener are faked on a prepended PATH, each logging its call to $CALLS, so the
# order the log records is the order morning-wait.sh ran them.
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

# --- the whole flow, in order ------------------------------------------------
: > "$CALLS"
"$MW" 12345 dotbee fake-launchpad.sh go; rc=$?
ok "exit 0" "$rc" 0
got=$(cat "$CALLS")
want=$(printf '%s\n' "sync:--wait 12345" "launchpad:go" "tmux:select-window -t dotbee")
ok "waits on sync, then launchpad, then selects window" "$got" "$want"

# --- a failing select-window must not fail the bootstrap ----------------------
cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
echo "tmux:$*" >> "$CALLS"
exit 1
EOF
chmod +x "$BIN/tmux"
: > "$CALLS"
"$MW" 1 dotspell fake-launchpad.sh; ok "survives a missing workspace window" "$?" 0

report

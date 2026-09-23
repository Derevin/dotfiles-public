#!/usr/bin/env bash
# Unit tests for claude-update.sh: which install locations it updates (host once,
# one running container per docker project, each running coder workspace, the rest
# skipped), its output shape, the host marker, and --wait-host.
#
# Self-contained: no docker, coder or tmux. `lab-list.sh`, `lab-run` and `claude`
# are faked on a prepended PATH; the script calls all three by bare name, so the
# fakes are what run. Each fake logs its call to $CU_CALLS.
# Usage: test-claude-update.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the claude-update.sh unit tests."
    echo "Usage: test-claude-update.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
CU="$SCRIPT_DIR/../scripts/claude-update.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"
export XDG_RUNTIME_DIR="$TMP/run"
mkdir -p "$XDG_RUNTIME_DIR"
MARKER="$XDG_RUNTIME_DIR/claude-update-host.done"
export CU_CALLS="$TMP/calls"

# Fake `claude`: log the host update, honour $CLAUDE_RC to simulate a failure.
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
echo "host:$*" >> "$CU_CALLS"
exit "${CLAUDE_RC:-0}"
EOF
chmod +x "$BIN/claude"

# Fake `lab-run <lab> -- claude install latest`: log the lab, fail those named in
# $LABRUN_FAIL (space-separated).
cat > "$BIN/lab-run" <<'EOF'
#!/usr/bin/env bash
echo "labrun:$1" >> "$CU_CALLS"
case " ${LABRUN_FAIL:-} " in *" $1 "*) exit 1 ;; esac
exit 0
EOF
chmod +x "$BIN/lab-run"

# Fake `lab-list.sh --long`: emit the fixture table in $LABLIST.
cat > "$BIN/lab-list.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$LABLIST"
EOF
chmod +x "$BIN/lab-list.sh"

# A mixed fleet (fictional projects alpha/beta/delta/gamma): two running docker
# labs in one project (dedup to one) plus an exited docker lab in its own project
# (skipped by state, not by dedup), two running coder workspaces (both updated), a
# present host lab (no lab-run — the local host update covers it), a stopped coder
# and an unresolved '?' row (both skipped).
export LABLIST="dlab-100-a  docker  alpha  running
dlab-101-b  docker  alpha  running
dlab-102-c  docker  delta  exited
clab-200-x  coder   beta   running
clab-201-y  coder   beta   running
hlab-300-z  host    gamma  present
clab-202-w  coder   beta   stopped
mystery     ?       ?      ?"

# --- happy path: dedup + output + marker -------------------------------------
: > "$CU_CALLS"
rm -f "$MARKER"
out=$("$CU" 2>&1); rc=$?
ok "success exit" "$rc" 0
ok "success line" "$out" "claude update: ✓"

got=$(sort "$CU_CALLS")
want=$(printf '%s\n' "host:install latest" "labrun:dlab-100-a" "labrun:clab-200-x" "labrun:clab-201-y" | sort)
ok "updates host once, docker one-per-project, each coder" "$got" "$want"

[ -f "$MARKER" ]; ok "host success touches marker" "$?" 0

# --- no labs: host only ------------------------------------------------------
: > "$CU_CALLS"
out=$(LABLIST="" "$CU" 2>&1); rc=$?
ok "no-labs exit" "$rc" 0
ok "no-labs line" "$out" "claude update: ✓"
ok "no-labs updates host only" "$(cat "$CU_CALLS")" "host:install latest"

# --- host failure: one line, non-zero, no marker -----------------------------
: > "$CU_CALLS"
rm -f "$MARKER"
out=$(CLAUDE_RC=1 LABLIST="" "$CU" 2>&1); rc=$?
ok "host-fail exit" "$rc" 1
ok "host-fail line" "$out" "claude update: host failed"
[ -f "$MARKER" ]; ok "host failure leaves no marker" "$?" 1

# --- lab failure: one line per failed target, host still ok ------------------
: > "$CU_CALLS"
out=$(LABRUN_FAIL="clab-200-x" "$CU" 2>&1); rc=$?
ok "lab-fail exit" "$rc" 1
ok "lab-fail names the target" "$out" "claude update: clab-200-x failed"

# --- --wait-host: fresh marker returns at once -------------------------------
t0=$(date +%s)
touch -d "@$((t0 + 5))" "$MARKER"
"$CU" --wait-host "$t0"; ok "wait returns 0 on fresh marker" "$?" 0

# --- --wait-host: stale marker times out to 0 (does not accept the old build) -
touch -d "@$((t0 - 100))" "$MARKER"
start=$(date +%s)
CLAUDE_UPDATE_WAIT_TIMEOUT=1 "$CU" --wait-host "$t0"; rc=$?
end=$(date +%s)
ok "wait times out to 0 on stale marker" "$rc" 0
[ "$((end - start))" -le 4 ]; ok "wait timeout is bounded" "$?" 0

# --- --wait-host: absent marker times out to 0 -------------------------------
rm -f "$MARKER"
CLAUDE_UPDATE_WAIT_TIMEOUT=1 "$CU" --wait-host "$(date +%s)"; ok "wait exits 0 with no marker" "$?" 0

report

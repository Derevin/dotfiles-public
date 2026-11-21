#!/usr/bin/env bash
# Unit tests for codex-review.sh: what it hands codex (the review-diff.sh output on
# stdin, a read-only sandbox, the model, the report as -o) and that it never fails
# the review — a missing, failing or silent codex still leaves a report saying why.
#
# Self-contained: `codex` and `review-diff.sh` are faked on a prepended PATH. The fake
# codex logs its argv and stdin, then acts on $FAKE_CODEX (ok|fail|silent).
# Usage: test-codex-review.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the codex-review.sh unit tests."
    echo "Usage: test-codex-review.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
CR="$SCRIPT_DIR/../scripts/codex-review.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"
mkdir -p "$BIN"
export CR_LOG="$TMP/log"
export FORK_REGISTRY_ROOT="$TMP/forks"
export CODEX_HOME="$TMP/codex"

cat > "$BIN/review-diff.sh" <<'EOF'
#!/usr/bin/env bash
echo "=== DIFF ==="
echo "+fake hunk"
EOF

cat > "$BIN/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CR_LOG.argv"
cat > "$CR_LOG.stdin"
out=
while [ $# -gt 0 ]; do
    [ "$1" = -o ] && { out=$2; shift; }
    shift
done
case "${FAKE_CODEX:-ok}" in
    ok) echo "src/a.c:3 off-by-one" > "$out" ;;
    fail) echo "error: not logged in" >&2; exit 1 ;;
    silent) : ;;
esac
EOF
chmod +x "$BIN/review-diff.sh" "$BIN/codex"

SYS_PATH=/usr/local/bin:/usr/bin:/bin

run() { PATH="$BIN:$SYS_PATH" bash "$CR" "$@"; }

# --help: describes itself, exits 0, touches nothing.
out=$(run --help); rc=$?
ok "help exit" "$rc" 0
ok "help usage line" "$(grep -c '^Usage: codex-review.sh' <<<"$out")" 1
ok "help ran no codex" "$(test -e "$CR_LOG.argv" && echo ran || echo none)" none

# No report path: a usage error, not a silent run.
fails run

# Success: codex's final message is the report.
REPORT="$TMP/reports/codex.md"
FAKE_CODEX=ok run "$REPORT"; rc=$?
ok "ok exit" "$rc" 0
ok "ok report" "$(cat "$REPORT")" "src/a.c:3 off-by-one"
ok "diff on stdin" "$(grep -c '^+fake hunk$' "$CR_LOG.stdin")" 1
ok "prompt on stdin" "$(grep -c '^You are one reviewer' "$CR_LOG.stdin")" 1
ok "diff inside stdin block" "$(sed -n '/^<stdin>$/,/^<\/stdin>$/p' "$CR_LOG.stdin" | grep -c '^+fake hunk$')" 1
ok "exec subcommand" "$(head -1 "$CR_LOG.argv")" exec
ok "read-only sandbox" "$(grep -A1 -x -- -s "$CR_LOG.argv" | tail -1)" read-only
ok "model" "$(grep -A1 -x -- -m "$CR_LOG.argv" | tail -1)" gpt-6.2-sol
ok "report as -o" "$(grep -A1 -x -- -o "$CR_LOG.argv" | tail -1)" "$REPORT"
# The run registers like any Codex run, under the review label.
review_meta() { jq -r "select(.label == \"review\") | .$1" "$FORK_REGISTRY_ROOT"/*/meta.json 2>/dev/null; }
ok "review registered" "$(review_meta status)" closed

# Failure: exit 0, the report names the failure and carries codex's stderr.
REPORT="$TMP/fail.md"
FAKE_CODEX=fail run "$REPORT"; rc=$?
ok "fail exit" "$rc" 0
ok "fail report headline" "$(grep -c '^Codex review unavailable' "$REPORT")" 1
ok "fail report first line" "$(head -1 "$REPORT")" "Codex review unavailable: codex exited 1"
ok "fail report stderr" "$(grep -c 'not logged in' "$REPORT")" 1

# Silent: codex exits 0 without a final message.
REPORT="$TMP/silent.md"
FAKE_CODEX=silent run "$REPORT"; rc=$?
ok "silent exit" "$rc" 0
ok "silent report" "$(cat "$REPORT")" "Codex review unavailable: codex returned no final message"

# No codex installed: the report says so instead of the review failing. The
# system dirs may hold a real codex, so the PATH is every tool the script reaches
# before the check, alone.
nocodex="$TMP/nocodex"
mkdir -p "$nocodex"
for t in bash dirname mkdir; do
    ln -s "$(command -v "$t")" "$nocodex/$t"
done
rm -f "$CR_LOG.argv"
REPORT="$TMP/missing.md"
PATH="$nocodex" bash "$CR" "$REPORT"; rc=$?
ok "missing exit" "$rc" 0
ok "missing report" "$(cat "$REPORT")" "Codex review unavailable: codex not installed"
# ok, fail and silent reached codex; the missing run did not.
ok "only runs that reached codex registered" "$(find "$FORK_REGISTRY_ROOT" -name meta.json | wc -l)" 3

report

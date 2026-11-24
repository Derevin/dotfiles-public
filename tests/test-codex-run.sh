#!/usr/bin/env bash
# Unit tests for codex-run.sh: what it hands codex (prompt on stdin, model, effort,
# sandbox, cwd, output file, resume), the fork-registry entry it keeps for the run
# (open while codex runs, closed on every exit), and how it finds a session to
# resume.
#
# Self-contained: `codex` is faked on a prepended PATH and the registry and Codex
# home live in a temp dir. The fake logs its argv and stdin, then acts on
# $FAKE_CODEX (ok|fail|silent|hold).
# Usage: test-codex-run.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the codex-run.sh unit tests."
    echo "Usage: test-codex-run.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
CRUN="$SCRIPT_DIR/../scripts/codex-run.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"
mkdir -p "$BIN" "$TMP/work" "$TMP/other"
export FORK_REGISTRY_ROOT="$TMP/forks"
export CODEX_HOME="$TMP/codex"
export CLAUDE_CONFIG_DIR="$TMP/claude"
export CLAUDE_CODE_SESSION_ID=sess-1
export CR_LOG="$TMP/log"
export CR_RELEASE="$TMP/release"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/-w"
: > "$CLAUDE_CONFIG_DIR/projects/-w/sess-1.jsonl"

# The thread id is the resumed session's (the argument before the trailing `-`),
# $FAKE_SID otherwise. Codex names its rollout file after it, under a date directory.
cat > "$BIN/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CR_LOG.argv"
cat > "$CR_LOG.stdin"
echo $$ > "$CR_LOG.pid"
sid=${FAKE_SID:-sid-1}
[ "$2" = resume ] && sid=${*: -2:1}
out=
while [ $# -gt 0 ]; do
    [ "$1" = -o ] && { out=$2; shift; }
    shift
done
rollout() {
    mkdir -p "$CODEX_HOME/sessions/2026/11/19"
    echo '{}' >> "$CODEX_HOME/sessions/2026/11/19/rollout-2026-11-19T10-00-00-$sid.jsonl"
}
case "${FAKE_CODEX:-ok}" in
    ok) printf '{"type":"thread.started","thread_id":"%s"}\n' "$sid"; rollout
        echo "final from $sid" > "$out" ;;
    fail) echo "error: not logged in" >&2; exit 1 ;;
    silent) printf '{"type":"thread.started","thread_id":"%s"}\n' "$sid" ;;
    hold) printf '{"type":"thread.started","thread_id":"%s"}\n' "$sid"; rollout
        [ -n "${FAKE_CHILD:-}" ] && { sleep 1000 & echo $! > "$CR_LOG.child"; }
        while [ ! -e "$CR_RELEASE" ]; do sleep 0.1; done
        echo "held" > "$out" ;;
esac
EOF
chmod +x "$BIN/codex"

SYS_PATH=/usr/local/bin:/usr/bin:/bin

run() { PATH="$BIN:$SYS_PATH" bash "$CRUN" "$@"; }
meta() { jq -r ".$2 // empty" "$FORK_REGISTRY_ROOT/$1/meta.json"; }
argv_after() { grep -A1 -x -- "$1" "$CR_LOG.argv" | tail -1; }
has_arg() { grep -cx -- "$1" "$CR_LOG.argv"; }
entries() { find "$FORK_REGISTRY_ROOT" -name meta.json 2>/dev/null | wc -l; }
has_field() { [ -n "$(meta "$1" "$2" 2>/dev/null)" ]; }
# wait_for <what> <cmd...>: poll up to 10s for a condition a background run reaches.
wait_for() {
    local i
    for i in $(seq 100); do "${@:2}" && return 0; sleep 0.1; done
    echo "timed out waiting for $1" >&2
    return 1
}

# --help: describes itself, exits 0, touches nothing.
out=$(run --help); rc=$?
ok "help exit" "$rc" 0
ok "help usage line" "$(grep -c '^Usage: codex-run.sh' <<<"$out")" 1
ok "help ran no codex" "$(test -e "$CR_LOG.argv" && echo ran || echo none)" none
ok "help registered nothing" "$(entries)" 0

fails run --bogus

# Fresh run: stdout is the run id alone, and the entry is the run's home.
id=$(echo "implement this" | FAKE_CODEX=ok run -l implement -e xhigh -s read-only -C "$TMP/work"); rc=$?
ok "ok exit" "$rc" 0
ok "stdout is one run id" "$(grep -cE '^codex-[0-9a-f]+$' <<<"$id")" 1
ok "agent type" "$(meta "$id" agent_type)" codex
ok "agent id" "$(meta "$id" agent_id)" "$id"
ok "label" "$(meta "$id" label)" implement
ok "status closed" "$(meta "$id" status)" closed
ok "exit recorded" "$(meta "$id" exit)" 0
ok "ended recorded" "$(meta "$id" ended | grep -c .)" 1
ok "cwd" "$(meta "$id" cwd)" "$TMP/work"
ok "calling session" "$(meta "$id" session_id)" sess-1
ok "session transcript" "$(meta "$id" session_transcript)" "$CLAUDE_CONFIG_DIR/projects/-w/sess-1.jsonl"
ok "codex session id" "$(meta "$id" codex_session_id)" sid-1
ok "rollout as transcript" "$(meta "$id" fork_transcript)" \
    "$CODEX_HOME/sessions/2026/11/19/rollout-2026-11-19T10-00-00-sid-1.jsonl"
SCRATCH="$FORK_REGISTRY_ROOT/$id/scratch"
ok "prompt kept" "$(cat "$SCRATCH/prompt.md")" "implement this"
ok "events kept" "$(grep -c thread.started "$SCRATCH/events.jsonl")" 1
ok "final message in scratch" "$(cat "$SCRATCH/final.md")" "final from sid-1"
ok "output recorded" "$(meta "$id" output)" "$SCRATCH/final.md"
ok "prompt on stdin" "$(cat "$CR_LOG.stdin")" "implement this"
ok "exec subcommand" "$(head -1 "$CR_LOG.argv")" exec
ok "prompt from stdin arg" "$(tail -1 "$CR_LOG.argv")" -
ok "model" "$(argv_after -m)" gpt-6.2-sol
ok "json events" "$(has_arg --json)" 1
ok "effort" "$(argv_after -c)" 'model_reasoning_effort="xhigh"'
ok "sandbox" "$(argv_after -s)" read-only
ok "cwd as -C" "$(argv_after -C)" "$TMP/work"
ok "output as -o" "$(argv_after -o)" "$SCRATCH/final.md"

# Caller's output path; no effort leaves Codex's default; bypass replaces -s.
echo p | FAKE_CODEX=ok run -o "$TMP/out/final.md" -s bypass -C "$TMP/work" >/dev/null
ok "caller output" "$(cat "$TMP/out/final.md")" "final from sid-1"
ok "caller output as -o" "$(argv_after -o)" "$TMP/out/final.md"
ok "no effort" "$(grep -c model_reasoning_effort "$CR_LOG.argv")" 0
ok "bypass" "$(has_arg --dangerously-bypass-approvals-and-sandbox)" 1
ok "bypass drops -s" "$(has_arg -s)" 0

# A relative -o is the caller's, not -C's; a symlinked one is replaced, its target kept.
( cd "$TMP" && echo p | FAKE_CODEX=ok run -o rel/final.md -C "$TMP/work" >/dev/null )
ok "relative -o from caller cwd" "$(cat "$TMP/rel/final.md")" "final from sid-1"
ok "relative -o absolutized" "$(argv_after -o)" "$TMP/rel/final.md"
echo keep > "$TMP/target.md"
ln -s "$TMP/target.md" "$TMP/link.md"
echo p | FAKE_CODEX=fail run -o "$TMP/link.md" -C "$TMP/work" >/dev/null 2>&1
ok "symlinked -o target kept" "$(cat "$TMP/target.md")" keep

# Failure: non-zero, codex's stderr passed on, the entry still closed.
before=$(entries)
err=$(echo p | FAKE_CODEX=fail run -l cold-read -C "$TMP/work" 2>&1 >"$TMP/fail.id"); rc=$?
ok "fail exit" "$([ "$rc" -ne 0 ] && echo nonzero || echo zero)" nonzero
ok "fail stderr" "$(grep -c 'not logged in' <<<"$err")" 1
fid=$(cat "$TMP/fail.id")
ok "fail entry closed" "$(meta "$fid" status)" closed
ok "fail exit recorded" "$(meta "$fid" exit)" 1
ok "fail registered once" "$(entries)" $((before + 1))

# Silent: codex exits 0 with no final message, which is a failure too.
err=$(echo p | FAKE_CODEX=silent run -C "$TMP/work" 2>&1 >"$TMP/silent.id"); rc=$?
ok "silent exit" "$([ "$rc" -ne 0 ] && echo nonzero || echo zero)" nonzero
ok "silent stderr" "$(grep -c 'no final message' <<<"$err")" 1
ok "silent entry closed" "$(meta "$(cat "$TMP/silent.id")" status)" closed
ok "silent exit recorded" "$(meta "$(cat "$TMP/silent.id")" exit)" 1

# While codex runs the entry is open and already names the session and rollout,
# so fork-recover.sh can ping it; it closes once codex finishes.
rm -f "$CR_RELEASE"
# A plain backgrounded command, so $! is the wrapper's own pid.
FAKE_SID=sid-hold FAKE_CODEX=hold PATH="$BIN:$SYS_PATH" bash "$CRUN" -l implement -C "$TMP/other" \
    <<<p >"$TMP/hold.id" 2>/dev/null &
wpid=$!
wait_for "hold run id" test -s "$TMP/hold.id"
hid=$(cat "$TMP/hold.id")
wait_for "hold rollout" has_field "$hid" fork_transcript
ok "running entry open" "$(meta "$hid" status)" open
ok "running entry pid is the wrapper" "$(meta "$hid" pid)" "$wpid"
ok "running entry session" "$(meta "$hid" codex_session_id)" sid-hold
touch "$CR_RELEASE"
wait "$wpid"
ok "released entry closed" "$(meta "$hid" status)" closed

# Killed mid-run: codex and what it started go with it, and the entry still closes.
rm -f "$CR_RELEASE" "$CR_LOG.pid" "$CR_LOG.child"
FAKE_SID=sid-kill FAKE_CODEX=hold FAKE_CHILD=1 PATH="$BIN:$SYS_PATH" bash "$CRUN" -C "$TMP/other" \
    <<<p >"$TMP/kill.id" 2>/dev/null &
wpid=$!
wait_for "kill run child" test -s "$CR_LOG.child"
kid=$(cat "$TMP/kill.id")
wait_for "kill run session" has_field "$kid" codex_session_id
kill -TERM "$wpid"
wait "$wpid"
ok "killed wrapper exit" "$?" 143
ok "killed entry closed" "$(meta "$kid" status)" closed
ok "killed exit recorded" "$(meta "$kid" exit)" 143
gone() { ! kill -0 "$(cat "$1")" 2>/dev/null; }
wait_for "codex killed" gone "$CR_LOG.pid"
ok "killed codex too" "$?" 0
wait_for "codex child killed" gone "$CR_LOG.child"
ok "killed codex child too" "$?" 0
kill "$(cat "$CR_LOG.child")" 2>/dev/null
touch "$CR_RELEASE"

# Resume by id: resume takes neither -s nor -C, so sandbox goes through -c and the
# cwd through the process's own directory.
rid=$(echo "fix this" | FAKE_CODEX=ok run --resume sid-1 -s read-only -l implement -C "$TMP/work"); rc=$?
ok "resume exit" "$rc" 0
ok "resume subcommand" "$(sed -n 2p "$CR_LOG.argv")" resume
ok "resume session arg" "$(tail -2 "$CR_LOG.argv" | head -1)" sid-1
ok "resume prompt from stdin" "$(tail -1 "$CR_LOG.argv")" -
ok "resume prompt" "$(cat "$CR_LOG.stdin")" "fix this"
ok "resume sandbox via config" "$(grep -cx 'sandbox_mode="read-only"' "$CR_LOG.argv")" 1
ok "resume has no -s" "$(has_arg -s)" 0
ok "resume has no -C" "$(has_arg -C)" 0
ok "resume entry session" "$(meta "$rid" codex_session_id)" sid-1
ok "resume entry rollout" "$(meta "$rid" fork_transcript)" \
    "$CODEX_HOME/sessions/2026/11/19/rollout-2026-11-19T10-00-00-sid-1.jsonl"
ok "resume entry is its own" "$([ "$rid" != "$id" ] && echo new || echo reused)" new

# Resume latest: the newest closed codex entry with this label and cwd.
mkentry() { # mkentry <id> <type> <status> <label> <cwd> <sid> <started>
    mkdir -p "$FORK_REGISTRY_ROOT/$1/scratch"
    jq -n --arg id "$1" --arg t "$2" --arg st "$3" --arg l "$4" --arg c "$5" \
        --arg s "$6" --arg at "$7" \
        '{agent_id: $id, agent_type: $t, status: $st, label: $l, cwd: $c,
          codex_session_id: $s, started: $at}' > "$FORK_REGISTRY_ROOT/$1/meta.json"
}
rm -rf "$FORK_REGISTRY_ROOT"
mkentry old codex closed implement "$TMP/work" sid-old 2026-11-19T09:00:00+01:00
mkentry want codex closed implement "$TMP/work" sid-want 2026-11-19T10:00:00+01:00
mkentry running codex open implement "$TMP/work" sid-open 2026-11-19T11:00:00+01:00
mkentry other-label codex closed cold-read "$TMP/work" sid-label 2026-11-19T12:00:00+01:00
mkentry other-cwd codex closed implement "$TMP/other" sid-cwd 2026-11-19T12:00:00+01:00
mkentry claude fork closed implement "$TMP/work" sid-claude 2026-11-19T12:00:00+01:00
mkentry no-sid codex closed implement "$TMP/work" "" 2026-11-19T12:00:00+01:00
# A hook-written entry cut short mid-write must not hide the rest.
mkdir -p "$FORK_REGISTRY_ROOT/broken"
printf '{"agent_id": "broken", "agent_type": "fo' > "$FORK_REGISTRY_ROOT/broken/meta.json"
lid=$(echo "fix" | FAKE_CODEX=ok run --resume-latest -l implement -C "$TMP/work"); rc=$?
ok "latest exit" "$rc" 0
ok "latest picks newest closed match" "$(tail -2 "$CR_LOG.argv" | head -1)" sid-want
ok "latest entry session" "$(meta "$lid" codex_session_id)" sid-want

# The fix round's own flags: bypass stays a flag on resume, effort a config key.
echo "fix" | FAKE_CODEX=ok run --resume-latest -l implement -e xhigh -s bypass -C "$TMP/work" >/dev/null
ok "fix round resumes" "$(sed -n 2p "$CR_LOG.argv")" resume
ok "fix round bypass" "$(has_arg --dangerously-bypass-approvals-and-sandbox)" 1
ok "fix round no sandbox key" "$(grep -c sandbox_mode "$CR_LOG.argv")" 0
ok "fix round effort" "$(argv_after -c)" 'model_reasoning_effort="xhigh"'

# One session to resume, named two ways, is a usage error.
before=$(entries)
echo "fix" | FAKE_CODEX=ok run --resume sid-1 --resume-latest -l implement -C "$TMP/work" >/dev/null 2>&1; rc=$?
ok "resume and latest exclusive" "$rc" 2
ok "exclusive registered nothing" "$(entries)" "$before"

# Nothing to resume: exit 3 before any side effect, so the caller runs fresh.
rm -f "$CR_LOG.argv"
before=$(entries)
out=$(echo "fix" | FAKE_CODEX=ok run --resume-latest -l review -C "$TMP/work" 2>/dev/null); rc=$?
ok "latest none exit" "$rc" 3
ok "latest none stdout" "$out" ""
ok "latest none ran no codex" "$(test -e "$CR_LOG.argv" && echo ran || echo none)" none
ok "latest none registered nothing" "$(entries)" "$before"

# Near the usage limit (by default 5h >= 93% or weekly >= 98%): exit 75 before any side
# effect, so the caller falls back to Claude. A window past its reset is empty.
snap="$CODEX_HOME/sessions/2026/11/20/rollout-snap.jsonl"
mkdir -p "$(dirname "$snap")"
snapshot() { # <5h%> <5h reset> <wk%> <wk reset>
    printf '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":%s,"resets_at":%s},"secondary":{"used_percent":%s,"resets_at":%s}}}}\n' \
        "$@" > "$snap"
}
later=$(( $(date +%s) + 3600 ))
earlier=$(( $(date +%s) - 3600 ))
snapshot 93 "$later" 10 "$later"
rm -f "$CR_LOG.argv"
before=$(entries)
err=$(echo p | FAKE_CODEX=ok run -C "$TMP/work" 2>&1 >/dev/null); rc=$?
ok "5h limit exit" "$rc" 75
ok "5h limit says why" "$(grep -c 'usage limit' <<<"$err")" 1
ok "5h limit ran no codex" "$(test -e "$CR_LOG.argv" && echo ran || echo none)" none
ok "5h limit registered nothing" "$(entries)" "$before"
snapshot 10 "$later" 98 "$later"
echo p | FAKE_CODEX=ok run -C "$TMP/work" >/dev/null 2>&1
ok "weekly limit exit" "$?" 75
snapshot 92.4 "$later" 97.4 "$later"
echo p | FAKE_CODEX=ok run -C "$TMP/work" >/dev/null 2>&1
ok "under limits runs" "$?" 0
# That run left the newest log, with no snapshot in it: the gate reads past it.
snapshot 99 "$later" 10 "$later"
touch -d '1 minute ago' "$snap"
echo p | FAKE_CODEX=ok run -C "$TMP/work" >/dev/null 2>&1
ok "reads past a log without a snapshot" "$?" 75
snapshot 99 "$earlier" 10 "$later"
echo p | FAKE_CODEX=ok run -C "$TMP/work" >/dev/null 2>&1
ok "reset window is empty" "$?" 0
# A caller's own limits replace the defaults.
snapshot 95 "$later" 98 "$later"
echo p | FAKE_CODEX=ok run --max-5h 97 --max-week 99 -C "$TMP/work" >/dev/null 2>&1
ok "raised limits run" "$?" 0
snapshot 97 "$later" 10 "$later"
echo p | FAKE_CODEX=ok run --max-5h 97 --max-week 99 -C "$TMP/work" >/dev/null 2>&1
ok "raised 5h limit exit" "$?" 75
snapshot 10 "$later" 99 "$later"
echo p | FAKE_CODEX=ok run --max-5h 97 --max-week 99 -C "$TMP/work" >/dev/null 2>&1
ok "raised weekly limit exit" "$?" 75
echo p | FAKE_CODEX=ok run --max-5h 97.5 -C "$TMP/work" >/dev/null 2>&1
ok "fractional limit is a usage error" "$?" 2

# No codex installed: fails before registering. The system dirs may hold a real
# codex, so the PATH is every tool the script reaches before the check, alone.
nocodex="$TMP/nocodex"
mkdir -p "$nocodex"
for t in bash jq grep cat od tr mkdir rm dirname realpath date; do
    ln -s "$(command -v "$t")" "$nocodex/$t"
done
before=$(entries)
err=$(echo p | PATH="$nocodex" bash "$CRUN" -C "$TMP/work" 2>&1 >/dev/null); rc=$?
ok "missing exit" "$([ "$rc" -ne 0 ] && echo nonzero || echo zero)" nonzero
ok "missing stderr" "$(grep -c 'codex not found' <<<"$err")" 1
ok "missing registered nothing" "$(entries)" "$before"

report

#!/usr/bin/env bash
# Unit tests for scripts/fork-recover.sh: the detail view of a Codex run, whose
# recovery is resuming its Codex session rather than reading a Claude transcript.
# Usage: test-fork-recover.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the fork-recover.sh unit tests."
    echo "Usage: test-fork-recover.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
FREC="$SCRIPT_DIR/../scripts/fork-recover.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export FORK_REGISTRY_ROOT="$TMP/forks"

# entry <id> <json>: a registry entry with that meta.json.
entry() {
    mkdir -p "$FORK_REGISTRY_ROOT/$1/scratch"
    printf '%s\n' "$2" > "$FORK_REGISTRY_ROOT/$1/meta.json"
}

# A Codex rollout is JSONL too, but not a Claude transcript: nothing in it is an
# assistant message for the action trail to show.
echo '{"type":"session_meta","payload":{"id":"sid-1"}}' > "$TMP/rollout.jsonl"
entry codex-1 "{\"agent_id\":\"codex-1\",\"agent_type\":\"codex\",\"status\":\"open\",
    \"codex_session_id\":\"sid-1\",\"fork_transcript\":\"$TMP/rollout.jsonl\"}"
echo "the prompt" > "$FORK_REGISTRY_ROOT/codex-1/scratch/prompt.md"
out=$("$FREC" codex-1)
ok "codex resume line" "$(grep -c '^  codex exec resume sid-1$' <<<"$out")" 1
ok "codex scratch shown" "$(grep -c 'the prompt' <<<"$out")" 1
ok "codex no claude action trail" "$(grep -c 'last 25 actions' <<<"$out")" 0

# Died before Codex named its session: nothing to resume, and it says so.
entry codex-2 '{"agent_id":"codex-2","agent_type":"codex","status":"open","codex_session_id":""}'
out=$("$FREC" codex-2)
ok "codex without session" "$(grep -c 'no Codex session' <<<"$out")" 1
ok "codex without session has no resume" "$(grep -c 'codex exec resume' <<<"$out")" 0

# A Claude fork keeps its transcript trail.
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"working on it"}],"stop_reason":"end_turn"}}' \
    > "$TMP/fork.jsonl"
entry fork-1 "{\"agent_id\":\"fork-1\",\"agent_type\":\"fork\",\"status\":\"open\",
    \"fork_transcript\":\"$TMP/fork.jsonl\"}"
out=$("$FREC" fork-1)
ok "fork action trail" "$(grep -c 'working on it' <<<"$out")" 1
ok "fork no resume line" "$(grep -c 'codex exec resume' <<<"$out")" 0

# --since filters the token rollup by start time. tok-dst starts 22:30Z, before
# the 23:00Z cutoff, though its +02:00 string sorts after the cutoff's +01:00.
TOK='"status":"closed","tokens":{"turns":3,"kept":1000,"returned":10,"output":500}'
entry tok-old "{\"agent_id\":\"tok-old\",\"started\":\"2026-11-20T10:00:00+01:00\",$TOK}"
entry tok-dst "{\"agent_id\":\"tok-dst\",\"started\":\"2026-11-21T00:30:00+02:00\",$TOK}"
entry tok-new "{\"agent_id\":\"tok-new\",\"started\":\"2026-11-21T09:00:00+01:00\",$TOK}"
out=$(TZ=UTC "$FREC" --tokens --all --since 2026-11-21T00:00:00+01:00)
ok "since keeps newer" "$(grep -c '^tok-new ' <<<"$out")" 1
ok "since drops older" "$(grep -c '^tok-old ' <<<"$out")" 0
ok "since compares instants, not strings" "$(grep -c '^tok-dst ' <<<"$out")" 0
ok "since resolved in summary" "$(grep -c '^1 fork kept .* since 2026-11-20 23:00,' <<<"$out")" 1
out=$("$FREC" --tokens --all)
ok "no since keeps all" "$(grep -c '^tok-' <<<"$out")" 3
"$FREC" --tokens --since 'not a date' >/dev/null 2>&1
ok "since rejects bad date" "$?" 2
"$FREC" --since today >/dev/null 2>&1
ok "since needs tokens" "$?" 2

report

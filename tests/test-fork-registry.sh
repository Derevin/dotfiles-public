#!/usr/bin/env bash
# Unit tests for scripts/fork-registry.sh.
# Usage: test-fork-registry.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the fork-registry.sh unit tests."
    echo "Usage: test-fork-registry.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
FR="$SCRIPT_DIR/../scripts/fork-registry.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export FORK_REGISTRY_ROOT="$TMP/forks"
export FORK_REGISTRY_RETAIN_DAYS=7

# entry <id> <status>: a registry entry; age <id> <days> backdates it.
entry() {
    mkdir -p "$FORK_REGISTRY_ROOT/$1/scratch"
    printf '{"agent_id": "%s", "status": "%s"}\n' "$1" "$2" > "$FORK_REGISTRY_ROOT/$1/meta.json"
}
age() { touch -d "$2 days ago" "$FORK_REGISTRY_ROOT/$1"; }

entry stale closed
entry open open
entry fresh closed
entry review closed
mkdir -p "$FORK_REGISTRY_ROOT/review/scratch/reports"
echo "branch: x" > "$FORK_REGISTRY_ROOT/review/scratch/reports/triage.md"
echo "finding" > "$FORK_REGISTRY_ROOT/review/scratch/reports/code.md"
entry untriaged closed
mkdir -p "$FORK_REGISTRY_ROOT/untriaged/scratch/reports"
echo "finding" > "$FORK_REGISTRY_ROOT/untriaged/scratch/reports/code.md"
age stale 10
age open 10
age fresh 1
age review 10
age untriaged 10

start() {
    printf '{"hook_event_name":"SubagentStart","agent_id":"%s","agent_type":"fork","session_id":"s","cwd":"/w","transcript_path":"%s/s.jsonl"}' \
        "$1" "$TMP" | "$FR" >/dev/null
}
start new

exists() { [ -e "$FORK_REGISTRY_ROOT/$1" ] && echo yes || echo no; }

ok "help exits 0" "$("$FR" --help >/dev/null; echo $?)" 0
ok "start registers the fork" "$(jq -r .status "$FORK_REGISTRY_ROOT/new/meta.json")" open
ok "start prunes a stale closed entry" "$(exists stale)" no
ok "an open entry is never pruned" "$(exists open)" yes
ok "a fresh closed entry is kept" "$(exists fresh)" yes
ok "a review's triage survives the prune" "$(exists review/scratch/reports/triage.md)" yes
ok "a review's reports survive the prune" "$(exists review/scratch/reports/code.md)" yes
ok "reports without triage are pruned" "$(exists untriaged)" no

report

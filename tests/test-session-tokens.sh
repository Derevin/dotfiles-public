#!/usr/bin/env bash
# Unit tests for scripts/session-tokens.sh.
# Usage: test-session-tokens.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the session-tokens.sh unit tests."
    echo "Usage: test-session-tokens.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
ST="$SCRIPT_DIR/../scripts/session-tokens.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export CLAUDE_CONFIG_DIR="$TMP/claude"
PROJ="$CLAUDE_CONFIG_DIR/projects/-work"
mkdir -p "$PROJ"

# assistant <input> <cache-write> <cache-read> [sidechain] — one transcript line.
assistant() {
    printf '{"type":"assistant","isSidechain":%s,"message":{"usage":{"input_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d,"output_tokens":7}}}\n' \
        "${4:-false}" "$1" "$2" "$3"
}

# A transcript repeats a request's usage on each of its content blocks, and a
# synthetic reply records all zeros.
{
    echo '{"type":"user","message":{"content":"hi"}}'
    assistant 5 100 1000
    assistant 2 300 4000
    assistant 2 300 4000
    assistant 9 900 90000 true
    assistant 0 0 0
    echo '{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}'
} > "$PROJ/s1.jsonl"

ok "help exits 0" "$("$ST" --help >/dev/null; echo $?)" 0
ok "last main-thread request" "$(CLAUDE_CODE_SESSION_ID=s1 "$ST")" 4302
fails env -u CLAUDE_CODE_SESSION_ID "$ST"
fails env CLAUDE_CODE_SESSION_ID=missing "$ST"

echo '{"type":"user","message":{"content":"hi"}}' > "$PROJ/s2.jsonl"
fails env CLAUDE_CODE_SESSION_ID=s2 "$ST"

report

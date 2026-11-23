#!/usr/bin/env bash
# Unit tests for scripts/fable-usage.sh: which cache it reads, and when and how
# it refreshes its own. A stub curl stands for the usage API.
# Usage: test-fable-usage.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the fable-usage.sh unit tests."
    echo "Usage: test-fable-usage.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
FU="$SCRIPT_DIR/../scripts/fable-usage.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
CACHE="$HOME/.cache/claude-usage.json"

# Records what it was called with and answers with curl.reply, failing without one.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<EOF
#!/bin/sh
echo "\$*" >> "$TMP/curl.args"
cat >> "$TMP/curl.stdin"
[ -z "\${CURL_SLEEP:-}" ] || sleep "\$CURL_SLEEP"
[ -f "$TMP/curl.reply" ] || exit 22
cat "$TMP/curl.reply"
EOF
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"

now=$(date +%s)
later=$(date -u -d "@$((now + 3600))" +%FT%T.123456+00:00)
earlier=$(date -u -d "@$((now - 3600))" +%FT%T.123456+00:00)
limits() {  # <fable %> <fable reset>
    printf '{"limits":[
        {"kind":"weekly_all","percent":99,"resets_at":"%s","scope":null},
        {"kind":"weekly_scoped","percent":%s,"resets_at":"%s","scope":{"model":{"display_name":"Fable"}}}]}' \
        "$later" "$1" "$2"
}
claude_code_cache() { printf '{"cachedUsageUtilization":{"utilization":%s}}' "$(limits "$@")" > "$HOME/.claude.json"; }
calls() { if [ -f "$TMP/curl.args" ]; then wc -l < "$TMP/curl.args"; else echo 0; fi; }
# The refresh runs in the background: wait for curl to have been called <n>
# times and for the refresh's temp file to be gone.
settle() {
    local i
    for i in $(seq 50); do
        [ "$(calls)" -ge "$1" ] && ! compgen -G "$CACHE.*" >/dev/null && return
        sleep 0.1
    done
}

fails "$FU"

claude_code_cache 51.4 "$later"
ok "falls back on Claude Code's cache" "$("$FU")" 51
claude_code_cache 51 "$earlier"
ok "zeroes a window past its reset" "$("$FU")" 0
claude_code_cache 51 null
ok "keeps a window without a reset" "$("$FU")" 51

mkdir -p "$HOME/.cache"
limits 70 "$later" > "$CACHE"
ok "prefers its own cache" "$("$FU")" 70
ok "fetches nothing without credentials" "$(calls)" 0

mkdir -p "$HOME/.claude"
echo '{"claudeAiOauth":{"accessToken":"tok-123"}}' > "$HOME/.claude/.credentials.json"
"$FU" >/dev/null
ok "leaves a fresh cache alone" "$(calls)" 0

limits 80 "$later" > "$TMP/curl.reply"
touch -d '10 minutes ago' "$CACHE"
ok "answers from a stale cache without waiting" "$("$FU")" 70
settle 1
ok "refreshes a stale cache" "$("$FU")" 80
ok "sends the token on stdin" "$(cat "$TMP/curl.stdin")" "Authorization: Bearer tok-123"
ok "keeps the token off the command line" "$(grep -c tok-123 "$TMP/curl.args")" 0
"$FU" >/dev/null
ok "refreshes once per window" "$(calls)" 1

rm "$TMP/curl.reply"
touch -d '10 minutes ago' "$CACHE"
"$FU" >/dev/null
settle 2
ok "keeps the cache when a refresh fails" "$("$FU")" 80

echo '{"error":"nope"}' > "$TMP/curl.reply"
touch -d '10 minutes ago' "$CACHE"
"$FU" >/dev/null
settle 3
ok "keeps the cache over a reply without limits" "$("$FU")" 80

touch -d '10 minutes ago' "$CACHE"
start=$(date +%s%N)
out=$(CURL_SLEEP=3 "$FU")
ok "returns before a slow refresh" "$(( ($(date +%s%N) - start) / 1000000 < 1500 ))" 1
settle 4

report

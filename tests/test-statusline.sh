#!/usr/bin/env bash
# Unit tests for claude/statusline.sh: the model segment.
# Usage: test-statusline.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the statusline.sh unit tests."
    echo "Usage: test-statusline.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
SL="$SCRIPT_DIR/../claude/statusline.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A fresh rate cache keeps the script from fetching; a non-repo cwd and no label
# leave the model as the only segment.
export HOME="$TMP"
mkdir -p "$HOME/.cache"
echo 23 > "$HOME/.cache/claude-statusline-usd-czk"
unset CLAUDE_LABEL
cd "$TMP" || exit 1

model() { printf '{"model":{"display_name":"%s"}}' "$1" | "$SL"; }

ok "keeps the version" "$(model 'Opus 4.8')" "Opus 4.8"
ok "drops the context suffix" "$(model 'Opus 5.5 (1M context)')" "Opus 5.5"
ok "keeps a long name whole" "$(model 'Sonnet 5')" "Sonnet 5"

# Codex usage comes from the rate-limit snapshot in its newest session log and
# rides beside Claude's: block <claude>/<codex>, wk <claude>/<codex>.
# A stub codex on PATH and an auth file stand for an installed, logged-in Codex.
mkdir -p "$TMP/bin" "$HOME/.codex"
printf '#!/bin/sh\n' > "$TMP/bin/codex"
chmod +x "$TMP/bin/codex"
export PATH="$TMP/bin:$PATH"
touch "$HOME/.codex/auth.json"
usage() { echo '{"rate_limits":{"five_hour":{"used_percentage":20},"seven_day":{"used_percentage":40}}}' | "$SL"; }
snapshot() {  # <5h%> <5h reset> <wk%> <wk reset>
    printf '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":%s,"window_minutes":300,"resets_at":%s},"secondary":{"used_percent":%s,"window_minutes":10080,"resets_at":%s}}}}\n' "$@"
}

ok "shows Claude alone without codex logs" "$(usage)" "(block 20% · wk 40%)"

now=$(date +%s)
later=$((now + 3600))
earlier=$((now - 3600))
old="$HOME/.codex/sessions/2026/11/18"
new="$HOME/.codex/sessions/2026/11/19"
mkdir -p "$old" "$new"
snapshot 90 "$later" 90 "$later" > "$old/rollout-a.jsonl"
{ snapshot 1 "$later" 2 "$later"; snapshot 12.4 "$later" 30.6 "$later"; } > "$new/rollout-b.jsonl"
touch -d '1 hour ago' "$old/rollout-a.jsonl"

ok "pairs codex usage from the newest snapshot" "$(usage)" "(block 20%/12% · wk 40%/31%)"
ok "skips codex without Claude usage" "$(model 'Opus 5.5')" "Opus 5.5"

snapshot 12 "$earlier" 30 "$later" > "$new/rollout-b.jsonl"
ok "zeroes a window that has reset" "$(usage)" "(block 20%/0% · wk 40%/30%)"

touch -d '2 hours ago' "$new/rollout-b.jsonl"
ok "reads a session that spans days by mtime" "$(usage)" "(block 20%/90% · wk 40%/90%)"

rm -r "$old"
ok "reads a lone day dir" "$(usage)" "(block 20%/0% · wk 40%/30%)"

echo '{}' > "$new/rollout-c.jsonl"
ok "reads past a newest log without a snapshot" "$(usage)" "(block 20%/0% · wk 40%/30%)"

# Fable's weekly limit comes from the usage Claude Code caches in ~/.claude.json
# and sits between Claude's and Codex's: wk <claude>/<fable>/<codex>.
fable() {  # <percent> <reset epoch>
    printf '{"cachedUsageUtilization":{"utilization":{"limits":[
        {"kind":"weekly_all","percent":99,"resets_at":"%s","scope":null},
        {"kind":"weekly_scoped","percent":%s,"resets_at":"%s","scope":{"model":{"display_name":"Fable"}}}]}}}' \
        "$(date -u -d "@$2" +%FT%T.123456+00:00)" "$1" "$(date -u -d "@$2" +%FT%T.123456+00:00)" \
        > "$HOME/.claude.json"
}
fable 51.4 "$later"
ok "puts fable between Claude and Codex weekly" "$(usage)" "(block 20%/0% · wk 40%/51%/30%)"
fable 51 "$earlier"
ok "zeroes fable past its reset" "$(usage)" "(block 20%/0% · wk 40%/0%/30%)"
rm "$HOME/.claude.json"

rm "$HOME/.codex/auth.json"
ok "locks codex usage when logged out" "$(usage)" "(block 20%/🔒 · wk 40%/🔒)"

# Every tool the script runs except codex, so its absence is the only difference.
nocodex="$TMP/nocodex"
mkdir -p "$nocodex"
for t in bash jq git cut date stat cat tac grep awk mkdir readlink dirname; do
    ln -s "$(command -v "$t")" "$nocodex/$t"
done
ok "skips codex when not installed" "$(PATH="$nocodex" usage)" "(block 20% · wk 40%)"

report

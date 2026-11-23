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

# A non-repo cwd and no label leave the model as the only segment.
export HOME="$TMP"
unset CLAUDE_LABEL
cd "$TMP" || exit 1

model() { printf '{"model":{"display_name":"%s"}}' "$1" | "$SL"; }

ok "abbreviates the family" "$(model 'Opus 4.8')" "O4.8"
ok "drops the context suffix" "$(model 'Opus 5.5 (1M context)')" "O5.5"
ok "keeps a versionless name whole" "$(model 'Opus')" "Opus"

effort() { printf '{"model":{"display_name":"Opus 5.5"},"effort":{"level":"%s"}}' "$1" | "$SL"; }
fills=""
for level in low medium high xhigh max; do fills+="$(effort "$level") "; done
ok "fills a circle per effort level" "$fills" "O5.5○ O5.5◔ O5.5◑ O5.5◕ O5.5● "
ok "skips an unknown effort level" "$(effort turbo)" "O5.5"
ok "shows cost in whole USD" "$(echo '{"cost":{"total_cost_usd":1.234}}' | "$SL")" '$1'
ok "joins model, context and cost in one segment" \
    "$(echo '{"model":{"display_name":"Opus 5.5"},"context_window":{"used_percentage":23.4},"cost":{"total_cost_usd":3.21}}' | "$SL")" \
    'O5.5 23% $3'

# Codex usage comes from the rate-limit snapshot in its newest session log and
# rides beside Claude's: 5h <claude>/<codex>%, 7d <claude>/<codex>%.
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

ok "shows Claude alone without codex logs" "$(usage)" "5h 20% · 7d 40%"

now=$(date +%s)
later=$((now + 3600))
earlier=$((now - 3600))
old="$HOME/.codex/sessions/2026/11/18"
new="$HOME/.codex/sessions/2026/11/19"
mkdir -p "$old" "$new"
snapshot 90 "$later" 90 "$later" > "$old/rollout-a.jsonl"
{ snapshot 1 "$later" 2 "$later"; snapshot 12.4 "$later" 30.6 "$later"; } > "$new/rollout-b.jsonl"
touch -d '1 hour ago' "$old/rollout-a.jsonl"

ok "pairs codex usage from the newest snapshot" "$(usage)" "5h 20/12% · 7d 40/31%"
ok "skips codex without Claude usage" "$(model 'Opus 5.5')" "O5.5"

snapshot 12 "$earlier" 30 "$later" > "$new/rollout-b.jsonl"
ok "zeroes a window that has reset" "$(usage)" "5h 20/0% · 7d 40/30%"

touch -d '2 hours ago' "$new/rollout-b.jsonl"
ok "reads a session that spans days by mtime" "$(usage)" "5h 20/90% · 7d 40/90%"

rm -r "$old"
ok "reads a lone day dir" "$(usage)" "5h 20/0% · 7d 40/30%"

echo '{}' > "$new/rollout-c.jsonl"
ok "reads past a newest log without a snapshot" "$(usage)" "5h 20/0% · 7d 40/30%"

# Fable's weekly limit comes from the usage Claude Code caches in ~/.claude.json
# and sits between Claude's and Codex's: 7d <claude>/<fable>/<codex>%.
fable() {  # <percent> <reset epoch>
    printf '{"cachedUsageUtilization":{"utilization":{"limits":[
        {"kind":"weekly_all","percent":99,"resets_at":"%s","scope":null},
        {"kind":"weekly_scoped","percent":%s,"resets_at":"%s","scope":{"model":{"display_name":"Fable"}}}]}}}' \
        "$(date -u -d "@$2" +%FT%T.123456+00:00)" "$1" "$(date -u -d "@$2" +%FT%T.123456+00:00)" \
        > "$HOME/.claude.json"
}
fable 51.4 "$later"
ok "puts fable between Claude and Codex weekly" "$(usage)" "5h 20/0% · 7d 40/51/30%"
fable 51 "$earlier"
ok "zeroes fable past its reset" "$(usage)" "5h 20/0% · 7d 40/0/30%"
rm "$HOME/.claude.json"

rm "$HOME/.codex/auth.json"
ok "locks codex usage when logged out" "$(usage)" "5h 20%/🔒 · 7d 40%/🔒"

# Every tool the script runs except codex, so its absence is the only difference.
nocodex="$TMP/nocodex"
mkdir -p "$nocodex"
for t in bash jq git cut date stat cat tac grep awk mkdir readlink dirname; do
    ln -s "$(command -v "$t")" "$nocodex/$t"
done
ok "skips codex when not installed" "$(PATH="$nocodex" usage)" "5h 20% · 7d 40%"

report

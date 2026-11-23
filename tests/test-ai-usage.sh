#!/usr/bin/env bash
# Unit tests for tmux/ai-usage.sh: the usage segment of the tmux status bar.
# Usage: test-ai-usage.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the ai-usage.sh unit tests."
    echo "Usage: test-ai-usage.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
AU="$SCRIPT_DIR/../tmux/ai-usage.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP" TZ=UTC
mkdir -p "$HOME/.cache"
CACHE="$HOME/.cache/claude-usage.json"
OUT="$HOME/.cache/ai-usage.txt"

now=$(date +%s)
later=$(( (now + 3600) / 60 * 60 ))
earlier=$((now - 3600))
iso() { date -u -d "@$1" +%FT%T.123456+00:00; }
hhmm() { date -d "@$1" +%H%M; }
dowhh() { local d; d=$(date -d "@$1" +%a); echo "${d:0:2}$(date -d "@$1" +%H)"; }

# Claude's windows as the usage API reports them; the reset times stay "later".
claude() {  # <5h%> <wk%> [fable%]
    local fable=""
    [ -n "${3:-}" ] && fable=$(printf ',{"kind":"weekly_scoped","percent":%s,"resets_at":"%s","scope":{"model":{"display_name":"Fable"}}}' "$3" "$(iso "$later")")
    printf '{"limits":[{"kind":"session","percent":%s,"resets_at":"%s","scope":null},{"kind":"weekly_all","percent":%s,"resets_at":"%s","scope":null}%s]}' \
        "$1" "$(iso "$later")" "$2" "$(iso "$later")" "$fable" > "$CACHE"
}
usage() { rm -f "$OUT"; "$AU"; }

# Codex usage comes from the rate-limit snapshot in its newest session log and
# rides beside Claude's: 5h <claude>/<codex>%, 7d <claude>/<fable>/<codex>%.
# A stub codex on PATH and an auth file stand for an installed, logged-in Codex.
mkdir -p "$TMP/bin" "$HOME/.codex"
printf '#!/bin/sh\n' > "$TMP/bin/codex"
chmod +x "$TMP/bin/codex"
export PATH="$TMP/bin:$PATH"
touch "$HOME/.codex/auth.json"
snapshot() {  # <5h%> <5h reset> <wk%> <wk reset>
    printf '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":%s,"window_minutes":300,"resets_at":%s},"secondary":{"used_percent":%s,"window_minutes":10080,"resets_at":%s}}}}\n' "$@"
}

r5=$(hhmm "$later")
r7=$(dowhh "$later")

ok "prints nothing without Claude usage" "$(usage)" ""

claude 20.4 40
ok "shows Claude alone without codex logs, with resets" "$(usage)" "5h 20% $r5 · 7d 40% $r7"

printf '{"limits":[{"kind":"session","percent":20,"resets_at":"%s","scope":null},{"kind":"weekly_all","percent":40,"resets_at":null,"scope":null}]}' \
    "$(iso "$earlier")" > "$CACHE"
ok "zeroes a window past its reset, dropping the reset" "$(usage)" "5h 0% · 7d 40%"

# The API puts a reset a fraction of a second before the hour it means.
printf '{"limits":[{"kind":"session","percent":20,"resets_at":"2099-01-01T16:29:59.62+00:00","scope":null},{"kind":"weekly_all","percent":40,"resets_at":"2099-01-01T09:59:59.62+00:00","scope":null}]}' > "$CACHE"
ok "rounds a reset to the minute" "$(usage)" "5h 20% 1630 · 7d 40% Th10"

claude 20 40 51.4
ok "puts fable beside Claude weekly" "$(usage)" "5h 20% $r5 · 7d 40/51% $r7"

claude 20 40
old="$HOME/.codex/sessions/2026/11/18"
new="$HOME/.codex/sessions/2026/11/19"
mkdir -p "$old" "$new"
snapshot 90 "$later" 90 "$later" > "$old/rollout-a.jsonl"
{ snapshot 1 "$later" 2 "$later"; snapshot 12.4 "$later" 30.6 "$later"; } > "$new/rollout-b.jsonl"
touch -d '1 hour ago' "$old/rollout-a.jsonl"

ok "pairs codex usage from the newest snapshot" "$(usage)" "5h 20/12% $r5 · 7d 40/31% $r7"
claude 20 40 51
ok "puts fable between Claude and Codex weekly" "$(usage)" "5h 20/12% $r5 · 7d 40/51/31% $r7"

rm "$CACHE"
ok "skips codex without Claude usage" "$(usage)" ""

claude 20 40
rm "$HOME/.codex/auth.json"
ok "locks codex usage when logged out" "$(usage)" "5h 20%/🔒 $r5 · 7d 40%/🔒 $r7"

# Every tool the script runs except codex, so its absence is the only difference.
nocodex="$TMP/nocodex"
mkdir -p "$nocodex"
for t in bash jq cat date stat mkdir mv readlink dirname touch; do
    ln -s "$(command -v "$t")" "$nocodex/$t"
done
ok "skips codex when not installed" "$(rm -f "$OUT"; PATH="$nocodex" "$AU")" "5h 20% $r5 · 7d 40% $r7"

# tmux asks every status-interval; a fresh answer is served as is.
usage >/dev/null
claude 60 70
ok "answers from a fresh cache" "$("$AU")" "5h 20%/🔒 $r5 · 7d 40%/🔒 $r7"
touch -d '1 minute ago' "$OUT"
ok "recomputes a stale cache" "$("$AU")" "5h 60%/🔒 $r5 · 7d 70%/🔒 $r7"

report

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
hhmm() { date -d "@$1" +%H:%M; }
dowhh() { local d; d=$(date -d "@$1" +%a); echo "${d:0:2}$(date -d "@$1" +%H)"; }

# Claude's windows as the usage API reports them; the reset times stay "later".
claude() {  # <5h%> <wk%> [fable%]
    local fable=""
    [ -n "${3:-}" ] && fable=$(printf ',{"kind":"weekly_scoped","percent":%s,"resets_at":"%s","scope":{"model":{"display_name":"Fable"}}}' "$3" "$(iso "$later")")
    printf '{"limits":[{"kind":"session","percent":%s,"resets_at":"%s","scope":null},{"kind":"weekly_all","percent":%s,"resets_at":"%s","scope":null}%s]}' \
        "$1" "$(iso "$later")" "$2" "$(iso "$later")" "$fable" > "$CACHE"
}
usage() { rm -f "$OUT"; "$AU"; }

# Each window leads with its reset, then a glyph per provider: Nerd Font asterisk
# Claude, ƒ Fable, Nerd Font hexagon Codex. Codex's come from the rate-limit
# snapshot in its newest session log.
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
ok "shows Claude alone without codex logs, with resets" "$(usage)" "$r5 󰛄20% · $r7 󰛄40%"

printf '{"limits":[{"kind":"session","percent":20,"resets_at":"%s","scope":null},{"kind":"weekly_all","percent":40,"resets_at":null,"scope":null}]}' \
    "$(iso "$earlier")" > "$CACHE"
ok "zeroes a window past its reset, dropping the reset" "$(usage)" "󰛄0% · 󰛄40%"

# The API puts a reset a fraction of a second before the hour it means.
printf '{"limits":[{"kind":"session","percent":20,"resets_at":"2099-01-01T16:29:59.62+00:00","scope":null},{"kind":"weekly_all","percent":40,"resets_at":"2099-01-01T09:59:59.62+00:00","scope":null}]}' > "$CACHE"
ok "rounds a reset to the minute" "$(usage)" "16:30 󰛄20% · Th10 󰛄40%"

claude 20 40 51.4
ok "puts fable beside Claude weekly" "$(usage)" "$r5 󰛄20% · $r7 󰛄40% ƒ51%"

claude 20 40
old="$HOME/.codex/sessions/2026/11/18"
new="$HOME/.codex/sessions/2026/11/19"
mkdir -p "$old" "$new"
snapshot 90 "$later" 90 "$later" > "$old/rollout-a.jsonl"
{ snapshot 1 "$later" 2 "$later"; snapshot 12.4 "$later" 30.6 "$later"; } > "$new/rollout-b.jsonl"
touch -d '1 hour ago' "$old/rollout-a.jsonl"

ok "pairs codex usage from the newest snapshot" "$(usage)" "$r5 󰛄20% 󰋙12% · $r7 󰛄40% 󰋙31%"
claude 20 40 51
ok "puts fable between Claude and Codex weekly" "$(usage)" "$r5 󰛄20% 󰋙12% · $r7 󰛄40% ƒ51% 󰋙31%"

# Codex's 5h reset rides on Claude's as an offset in whole minutes, as both
# clocks would read; none when they read the same.
claude 20 40
snapshot 12 $((later + 10 * 60 + 32)) 31 "$later" > "$new/rollout-b.jsonl"
ok "offsets a later codex 5h reset" "$(usage)" "$r5+10 󰛄20% 󰋙12% · $r7 󰛄40% 󰋙31%"
snapshot 12 $((later - 15 * 60)) 31 "$later" > "$new/rollout-b.jsonl"
ok "offsets an earlier codex 5h reset" "$(usage)" "$r5-15 󰛄20% 󰋙12% · $r7 󰛄40% 󰋙31%"
snapshot 12 $((later + 90 * 60)) 31 "$later" > "$new/rollout-b.jsonl"
ok "offsets up to 90 minutes in minutes" "$(usage)" "$r5+90 󰛄20% 󰋙12% · $r7 󰛄40% 󰋙31%"
snapshot 12 $((later + 95 * 60)) 31 "$later" > "$new/rollout-b.jsonl"
ok "offsets past 90 minutes as h:mm" "$(usage)" "$r5+1:35 󰛄20% 󰋙12% · $r7 󰛄40% 󰋙31%"
snapshot 12 "$earlier" 31 "$later" > "$new/rollout-b.jsonl"
ok "drops the offset past codex's 5h reset" "$(usage)" "$r5 󰛄20% 󰋙0% · $r7 󰛄40% 󰋙31%"
snapshot 12 $((later + 10 * 60)) 31 "$later" > "$new/rollout-b.jsonl"
printf '{"limits":[{"kind":"session","percent":20,"resets_at":"%s","scope":null},{"kind":"weekly_all","percent":40,"resets_at":"%s","scope":null}]}' \
    "$(iso "$earlier")" "$(iso "$later")" > "$CACHE"
ok "drops the offset past Claude's 5h reset" "$(usage)" "󰛄0% 󰋙12% · $r7 󰛄40% 󰋙31%"

# The weekly offset is in hours, as the weekly reset shows, to the nearest.
claude 20 40
snapshot 12 "$later" 31 $((later + 3 * 3600)) > "$new/rollout-b.jsonl"
ok "offsets a later codex weekly reset" "$(usage)" "$r5 󰛄20% 󰋙12% · $r7+3 󰛄40% 󰋙31%"
snapshot 12 "$later" 31 $((later + 2 * 3600 + 31 * 60)) > "$new/rollout-b.jsonl"
ok "rounds the weekly offset up" "$(usage)" "$r5 󰛄20% 󰋙12% · $r7+3 󰛄40% 󰋙31%"
snapshot 12 "$later" 31 $((later + 3 * 3600 + 29 * 60)) > "$new/rollout-b.jsonl"
ok "rounds the weekly offset down" "$(usage)" "$r5 󰛄20% 󰋙12% · $r7+3 󰛄40% 󰋙31%"
snapshot 12 "$later" 31 $((later + 29 * 60)) > "$new/rollout-b.jsonl"
ok "drops a weekly offset under half an hour" "$(usage)" "$r5 󰛄20% 󰋙12% · $r7 󰛄40% 󰋙31%"
snapshot 12 "$later" 31 $((later + 26 * 3600)) > "$new/rollout-b.jsonl"
ok "keeps a day or more in hours" "$(usage)" "$r5 󰛄20% 󰋙12% · $r7+26 󰛄40% 󰋙31%"
snapshot 12 "$earlier" 31 $((later + 3 * 3600)) > "$new/rollout-b.jsonl"
ok "offsets weekly past codex's 5h reset" "$(usage)" "$r5 󰛄20% 󰋙0% · $r7+3 󰛄40% 󰋙31%"
week=$((later + 5 * 3600))
printf '{"limits":[{"kind":"session","percent":20,"resets_at":"%s","scope":null},{"kind":"weekly_all","percent":40,"resets_at":"%s","scope":null}]}' \
    "$(iso "$later")" "$(iso "$week")" > "$CACHE"
snapshot 12 "$later" 31 "$later" > "$new/rollout-b.jsonl"
ok "offsets an earlier codex weekly reset" "$(usage)" "$r5 󰛄20% 󰋙12% · $(dowhh "$week")-5 󰛄40% 󰋙31%"

rm "$CACHE"
ok "skips codex without Claude usage" "$(usage)" ""

claude 20 40
rm "$HOME/.codex/auth.json"
ok "locks codex usage when logged out" "$(usage)" "$r5 󰛄20% 󰋙🔒 · $r7 󰛄40% 󰋙🔒"

# Every tool the script runs except codex, so its absence is the only difference.
nocodex="$TMP/nocodex"
mkdir -p "$nocodex"
for t in bash jq cat date stat mkdir mv readlink dirname touch; do
    ln -s "$(command -v "$t")" "$nocodex/$t"
done
ok "skips codex when not installed" "$(rm -f "$OUT"; PATH="$nocodex" "$AU")" "$r5 󰛄20% · $r7 󰛄40%"

# tmux asks every status-interval; a fresh answer is served as is.
usage >/dev/null
claude 60 70
ok "answers from a fresh cache" "$("$AU")" "$r5 󰛄20% 󰋙🔒 · $r7 󰛄40% 󰋙🔒"
touch -d '1 minute ago' "$OUT"
ok "recomputes a stale cache" "$("$AU")" "$r5 󰛄60% 󰋙🔒 · $r7 󰛄70% 󰋙🔒"

report

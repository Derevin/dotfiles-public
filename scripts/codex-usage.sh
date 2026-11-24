#!/usr/bin/env bash
# Print Codex's rate-limit usage as two whole percents, the 5-hour window's then
# the week's, then their two reset epochs in the same order. Codex logs an
# account-wide snapshot after each turn; the newest log holding one has the
# latest. A window past its reset prints 0, and - for its reset. Exits 1 when no
# log holds a snapshot.
# Usage: codex-usage.sh
set -uo pipefail
shopt -s nullglob

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Print Codex's latest 5-hour and weekly usage in whole percents, then their resets."
    echo "Usage: codex-usage.sh"
    exit 0
fi

# Logs sit in YYYY/MM/DD dirs by session start, so a session spanning midnight is
# in yesterday's: scan the last two. A log still on its first turn has no
# snapshot yet, so newest first, past any without one.
days=( "${CODEX_HOME:-$HOME/.codex}"/sessions/*/*/* )
skip=$(( ${#days[@]} > 2 ? ${#days[@]} - 2 : 0 ))
logs=()
for d in "${days[@]:skip}"; do
    logs+=( "$d"/*.jsonl )
done
[ "${#logs[@]}" -gt 0 ] || exit 1

while read -r log; do
    # Not the pipeline's status: grep -m1 quitting early SIGPIPEs tac.
    snap=$(tac "$log" | grep -m1 '"rate_limits":{')
    [ -n "$snap" ] || continue
    jq -r '.payload.rate_limits | [.primary, .secondary]
        | map(if .resets_at > now then . else {used_percent: 0, resets_at: "-"} end)
        | [(.[].used_percent | round), .[].resets_at]
        | map(tostring) | join(" ")' <<<"$snap" 2>/dev/null && exit 0
done < <(ls -t -- "${logs[@]}")
exit 1

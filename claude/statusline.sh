#!/usr/bin/env bash
input=$(cat)

dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // ""')
branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)
ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' | cut -d. -f1)
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
model=${model%% (*}   # "Opus 5.5 (1M context)"→"Opus 5.5"
cost=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // empty')
rl5=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl5_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl7=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl7_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# USD→CZK rate (cached daily, refreshed in background — never blocks statusline)
rate_file=~/.cache/claude-statusline-usd-czk
mkdir -p ~/.cache 2>/dev/null
if [[ ! -f $rate_file ]] || (( $(date +%s) - $(stat -c %Y "$rate_file" 2>/dev/null || echo 0) > 86400 )); then
    ( curl -fsSL -m 5 'https://api.frankfurter.app/latest?from=USD&to=CZK' 2>/dev/null \
        | jq -r '.rates.CZK // empty' > "$rate_file.tmp" 2>/dev/null \
        && [[ -s $rate_file.tmp ]] && mv "$rate_file.tmp" "$rate_file" ) &
    disown 2>/dev/null
fi
czk_rate=$(cat "$rate_file" 2>/dev/null)

# Codex logs an account-wide rate-limit snapshot after each turn; the newest log
# holds the latest. Logs sit in YYYY/MM/DD dirs by session start, so a session
# spanning midnight is in yesterday's — scan the last two, pick by mtime.
# Logged out, the snapshot is stale and Codex unusable: a lock replaces it.
cx5="" cx7="" codex_log=""
codex_home="${CODEX_HOME:-$HOME/.codex}"
if ! command -v codex >/dev/null; then
    :  # not installed: no Codex segment at all
elif [[ ! -f $codex_home/auth.json ]]; then
    cx5="🔒" cx7="🔒"
else
    codex_days=( "$codex_home"/sessions/*/*/* )
    skip=$(( ${#codex_days[@]} > 2 ? ${#codex_days[@]} - 2 : 0 ))
    for d in "${codex_days[@]:skip}"; do
        for f in "$d"/*.jsonl; do
            [[ $f -nt $codex_log ]] && codex_log=$f
        done
    done
    # A window past its reset is empty, however stale the snapshot.
    [[ -n "$codex_log" ]] && read -r cx5 cx7 < <(tac "$codex_log" | grep -m1 '"rate_limits":{' \
        | jq -r '.payload.rate_limits | [.primary, .secondary]
            | map(if .resets_at > now then .used_percent | round else 0 end)
            | "\(.[0])% \(.[1])%"' 2>/dev/null)
fi

parts=()
# CLAUDE_LABEL is set at launch by the workspace scripts; unlike a Claude session
# name it survives /clear (env, not conversation state). Falls back to the dir.
if [[ -n "${CLAUDE_LABEL:-}" ]]; then
    parts+=("$CLAUDE_LABEL")
elif [[ -n "$dir" ]]; then
    label="${dir##*/}"
    [[ "$label" =~ -c?wt[0-9]+$ ]] && label="${label##*-}"
    parts+=("$label")
fi
[[ -n "$ctx" ]] && parts+=("ctx ${ctx}%")
[[ -n "$model" ]] && parts+=("$model")

extras=()
if [[ -n "$rl5" ]]; then
    p="block $(printf '%.0f' "$rl5")%"
    [[ -n "$cx5" ]] && p="$p/$cx5"
    [[ -n "$rl5_reset" ]] && p="$p $(date -d "@$rl5_reset" +%H%M)"
    extras+=("$p")
fi
if [[ -n "$cost" ]]; then
    usd=$(printf '$%.2f' "$cost")
    if [[ -n "$czk_rate" ]]; then
        czk=$(awk -v c="$cost" -v r="$czk_rate" 'BEGIN{printf "%.0f", c*r}')
        extras+=("$usd ${czk} Kč")
    else
        extras+=("$usd")
    fi
fi
if [[ -n "$rl7" ]]; then
    p="wk $(printf '%.0f' "$rl7")%"
    [[ -n "$cx7" ]] && p="$p/$cx7"
    if [[ -n "$rl7_reset" ]]; then
        dow=$(date -d "@$rl7_reset" +%a)
        p="$p ${dow:0:2}$(date -d "@$rl7_reset" +%H)"
    fi
    extras+=("$p")
fi

sep=' · '
out=""
for p in "${parts[@]}"; do
    [[ -n "$out" ]] && out="$out$sep"
    out="$out$p"
done
if (( ${#extras[@]} )); then
    inner=""
    for e in "${extras[@]}"; do
        [[ -n "$inner" ]] && inner="$inner$sep"
        inner="$inner$e"
    done
    [[ -n "$out" ]] && out="$out$sep"
    out="$out($inner)"
fi
if [[ -n "$branch" ]]; then
    [[ -n "$out" ]] && out="$out$sep"
    out="$out$branch"
fi
printf '%s\n' "$out"

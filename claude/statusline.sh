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

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../scripts"

# Logged out, the snapshot is stale and Codex unusable: a lock replaces it.
cx5="" cx7=""
if ! command -v codex >/dev/null; then
    :  # not installed: no Codex segment at all
elif [[ ! -f ${CODEX_HOME:-$HOME/.codex}/auth.json ]]; then
    cx5="🔒" cx7="🔒"
elif read -r cx5 cx7 < <("$scripts/codex-usage.sh"); then
    cx5="$cx5%" cx7="$cx7%"
fi

fb7=$("$scripts/fable-usage.sh") && fb7="$fb7%"

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
[[ -n "$cost" ]] && extras+=("$(printf '$%.2f' "$cost")")
if [[ -n "$rl7" ]]; then
    p="wk $(printf '%.0f' "$rl7")%"
    [[ -n "$fb7" ]] && p="$p/$fb7"
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

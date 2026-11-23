#!/usr/bin/env bash
input=$(cat)

dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // ""')
branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)
ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' | cut -d. -f1)
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
model=${model%% (*}   # "Opus 5.5 (1M context)"→"Opus 5.5"
[[ $model == *' '* ]] && model="${model:0:1}${model##* }"   # "Opus 5.5"→"O5.5"
if [[ -n $model ]]; then
    case $(printf '%s' "$input" | jq -r '.effort.level // empty') in
        low) model+="○" ;;
        medium) model+="◔" ;;
        high) model+="◑" ;;
        xhigh) model+="◕" ;;
        max) model+="●" ;;
    esac
fi
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
else
    read -r cx5 cx7 < <("$scripts/codex-usage.sh")
fi

fb7=$("$scripts/fable-usage.sh") || fb7=""

# Joins percentages under one sign, 20/12%; a lock trails it, 20%/🔒.
pcts() {
    local nums=() lock="" v
    for v; do
        case $v in
            '') ;;
            🔒) lock="/🔒" ;;
            *) nums+=("$v") ;;
        esac
    done
    local IFS=/
    printf '%s%%%s' "${nums[*]}" "$lock"
}

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

session=()
[[ -n "$model" ]] && session+=("$model")
[[ -n "$ctx" ]] && session+=("${ctx}%")
[[ -n "$cost" ]] && session+=("$(printf '$%.0f' "$cost")")
(( ${#session[@]} )) && parts+=("${session[*]}")

if [[ -n "$rl5" ]]; then
    p="5h $(pcts "$(printf '%.0f' "$rl5")" "$cx5")"
    [[ -n "$rl5_reset" ]] && p="$p $(date -d "@$rl5_reset" +%H%M)"
    parts+=("$p")
fi
if [[ -n "$rl7" ]]; then
    p="7d $(pcts "$(printf '%.0f' "$rl7")" "$fb7" "$cx7")"
    if [[ -n "$rl7_reset" ]]; then
        dow=$(date -d "@$rl7_reset" +%a)
        p="$p ${dow:0:2}$(date -d "@$rl7_reset" +%H)"
    fi
    parts+=("$p")
fi
[[ -n "$branch" ]] && parts+=("$branch")

sep=' · '
out=""
for p in "${parts[@]}"; do
    [[ -n "$out" ]] && out="$out$sep"
    out="$out$p"
done
printf '%s\n' "$out"

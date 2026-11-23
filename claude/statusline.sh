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
[[ -n "$ctx" ]] && session+=("${ctx}%")
[[ -n "$model" ]] && session+=("$model")
[[ -n "$cost" ]] && session+=("$(printf '$%.0f' "$cost")")
(( ${#session[@]} )) && parts+=("${session[*]}")
[[ -n "$branch" ]] && parts+=("$branch")

sep=' · '
out=""
for p in "${parts[@]}"; do
    [[ -n "$out" ]] && out="$out$sep"
    out="$out$p"
done
printf '%s\n' "$out"

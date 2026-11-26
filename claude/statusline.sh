#!/usr/bin/env bash
input=$(cat)

dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // ""')
branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)
ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' | cut -d. -f1)
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
model=${model%% (*}   # "Opus 5.5 (1M context)"→"Opus 5.5"
{ read -r effort; read -r transcript; } <<<"$(printf '%s' "$input" | jq -r '(.effort.level // ""), (.transcript_path // "")')"

# Nerd Font circle slices, one style and drawn to the cell; ◑ isn't in the font,
# so a fallback draws it bigger than its ○◔◕● siblings.
if [[ -n $model ]]; then
    case $effort in
        low) model+=" 󰝦" ;;     # nf-md-circle_outline
        medium) model+=" 󰪟" ;;  # nf-md-circle_slice_2
        high) model+=" 󰪡" ;;    # nf-md-circle_slice_4
        xhigh) model+=" 󰪣" ;;   # nf-md-circle_slice_6
        max) model+=" 󰪥" ;;     # nf-md-circle_slice_8
    esac
fi

# Record the live effort beside the transcript for a lab relaunch
# (lab_claude_cmd --recorded-effort). The statusline re-renders on /effort
# itself, so a change made just before closing still lands. The rename keeps a
# reader from seeing a half-written file.
case $effort in
    low|medium|high|xhigh|max)
        if [[ $transcript == /* && -f $transcript ]]; then
            rec="${transcript%/*}/.effort"
            cur=""
            { read -r cur <"$rec"; } 2>/dev/null
            if [[ $cur != "$effort" ]]; then
                { printf '%s\n' "$effort" >"$rec.$$" && mv -f "$rec.$$" "$rec"; } 2>/dev/null \
                    || rm -f "$rec.$$"
            fi
        fi
        ;;
esac

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
(( ${#session[@]} )) && parts+=("${session[*]}")
[[ -n "$branch" ]] && parts+=("$branch")

sep=' · '
out=""
for p in "${parts[@]}"; do
    [[ -n "$out" ]] && out="$out$sep"
    out="$out$p"
done
printf '%s\n' "$out"

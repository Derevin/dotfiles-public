#!/usr/bin/env bash
# Print account-wide AI usage for the tmux status bar: Claude's 5-hour and weekly
# windows with their resets, Fable's week and Codex's windows beside them, e.g.
# "5h 20/12% 1630 · 7d 40/51/31% We10". Claude's numbers come from the usage API
# cache fable-usage.sh keeps, not a session, so they cover sessions in containers
# too. tmux asks every status-interval; the answer is cached for CACHE_TTL.
# Usage: ai-usage.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Print Claude, Fable and Codex usage for the tmux status bar."
    echo "Usage: ai-usage.sh"
    exit 0
fi

CACHE_TTL=15
out=$HOME/.cache/ai-usage.txt
if (( $(date +%s) - $(stat -c %Y "$out" 2>/dev/null || echo 0) < CACHE_TTL )); then
    cat "$out"
    exit 0
fi

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../scripts"
cache=$HOME/.cache/claude-usage.json

# Before reading the cache: this call is what keeps it fresh.
fb7=$("$scripts/fable-usage.sh") || fb7=""

# Logged out, the snapshot is stale and Codex unusable: a lock replaces it.
cx5="" cx7=""
if ! command -v codex >/dev/null; then
    :  # not installed: no Codex segment at all
elif [[ ! -f ${CODEX_HOME:-$HOME/.codex}/auth.json ]]; then
    cx5="🔒" cx7="🔒"
else
    read -r cx5 cx7 < <("$scripts/codex-usage.sh")
fi

# One of Claude's windows as "<whole percent> <reset epoch>"; past its reset it
# reads 0, with no reset. Prints nothing when the cache doesn't hold it.
claude_window() {
    local pct reset
    read -r pct reset < <(jq -r --arg k "$1" \
        '.limits[]? | select(.kind == $k) | "\(.percent) \(.resets_at)"' "$cache" 2>/dev/null)
    [[ -n ${pct:-} ]] || return
    if [[ $reset == null ]] || ! reset=$(date -d "$reset" +%s 2>/dev/null); then
        reset=""
    else
        # The API stamps a reset a fraction of a second before the hour it means.
        reset=$(( (reset + 30) / 60 * 60 ))
    fi
    if [[ -n $reset ]] && (( reset <= $(date +%s) )); then
        echo 0
    else
        printf '%.0f %s\n' "$pct" "$reset"
    fi
}

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
if read -r p reset < <(claude_window session); then
    seg="5h $(pcts "$p" "$cx5")"
    [[ -n $reset ]] && seg+=" $(date -d "@$reset" +%H%M)"
    parts+=("$seg")
fi
if read -r p reset < <(claude_window weekly_all); then
    seg="7d $(pcts "$p" "$fb7" "$cx7")"
    if [[ -n $reset ]]; then
        dow=$(date -d "@$reset" +%a)
        seg+=" ${dow:0:2}$(date -d "@$reset" +%H)"
    fi
    parts+=("$seg")
fi

line=""
for p in "${parts[@]}"; do
    line+="${line:+ · }$p"
done

mkdir -p "${out%/*}"
printf '%s\n' "$line" > "$out.$$" && mv "$out.$$" "$out"
printf '%s\n' "$line"

#!/usr/bin/env bash
# Print account-wide AI usage for the tmux status bar: the 5-hour then the weekly
# window, each led by its reset, then a glyph per provider, e.g.
# "16:30+10 󰛄20% 󰋙12% · We10+3 󰛄40% ƒ51% 󰋙31%", where +10 and +3 put
# Codex's resets ten minutes and three hours after Claude's. Claude's numbers come
# from the usage API cache fable-usage.sh keeps, not a session, so they cover
# sessions in containers too. tmux asks every status-interval; the answer is
# cached for CACHE_TTL.
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
cx5="" cx7="" cx5_reset="" cx7_reset=""
if ! command -v codex >/dev/null; then
    :  # not installed: no Codex segment at all
elif [[ ! -f ${CODEX_HOME:-$HOME/.codex}/auth.json ]]; then
    cx5="🔒" cx7="🔒"
else
    read -r cx5 cx7 cx5_reset cx7_reset < <("$scripts/codex-usage.sh")
fi

# Codex's 5h reset against Claude's, in whole minutes as both clocks read: "+10",
# "-15"; past 90 as h:mm, "+1:35". Nothing when Codex's is unknown or the same.
codex_offset_5h() {  # <claude reset> <codex reset>
    [[ -n $2 && $2 != - ]] || return
    local d=$(( $2 / 60 - $1 / 60 )) sign=+
    (( d < 0 )) && { sign=-; d=$(( -d )); }
    if (( d > 90 )); then
        printf '%s%d:%02d' "$sign" $(( d / 60 )) $(( d % 60 ))
    elif (( d > 0 )); then
        printf '%s%d' "$sign" "$d"
    fi
}

# Hours from Claude's weekly reset to Codex's next one, to the nearest: "+3",
# "+163". Both repeat weekly, so the offset wraps into 0-167. Nothing when Codex's
# is unknown or within half an hour of Claude's.
codex_offset_7d() {  # <claude reset> <codex reset>
    [[ -n $2 && $2 != - ]] || return
    local week=$(( 168 * 3600 ))
    local d=$(( (($2 - $1) % week + week + 1800) % week / 3600 ))
    if (( d > 0 )); then
        printf '+%d' "$d"
    fi
}

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

# Adds <glyph><percent>% to seg; a logged-out Codex adds <glyph>🔒, an unknown
# percent nothing.
tag() {
    case $2 in
        '') ;;
        🔒) seg+=("$1🔒") ;;
        *) seg+=("$1$2%") ;;
    esac
}

# Nerd Font icons: drawn to the cell, where a fallback font's glyph spills into
# the digit after it. Fable's ƒ is in the font itself.
CLAUDE=󰛄  # nf-md-asterisk
CODEX=󰋙   # nf-md-hexagon_outline

parts=()
if read -r p reset < <(claude_window session); then
    seg=()
    [[ -n $reset ]] && seg+=("$(date -d "@$reset" +%H:%M)$(codex_offset_5h "$reset" "$cx5_reset")")
    tag "$CLAUDE" "$p"
    tag "$CODEX" "$cx5"
    parts+=("${seg[*]}")
fi
if read -r p reset < <(claude_window weekly_all); then
    seg=()
    if [[ -n $reset ]]; then
        dow=$(date -d "@$reset" +%a)
        seg+=("${dow:0:2}$(date -d "@$reset" +%H)$(codex_offset_7d "$reset" "$cx7_reset")")
    fi
    tag "$CLAUDE" "$p"
    tag ƒ "$fb7"
    tag "$CODEX" "$cx7"
    parts+=("${seg[*]}")
fi

line=""
for p in "${parts[@]}"; do
    line+="${line:+ · }$p"
done

mkdir -p "${out%/*}"
printf '%s\n' "$line" > "$out.$$" && mv "$out.$$" "$out"
printf '%s\n' "$line"

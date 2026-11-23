#!/usr/bin/env bash
# Print Fable's weekly usage as a whole percent; a window past its reset prints
# 0. Exits 1 when no usage is known.
#
# Claude Code hands its statusline only the all-models limits, so this reads the
# usage API behind /usage. The reply is cached and, once older than MAX_AGE,
# refreshed in the background: a call never waits on the network, and the tmux
# status bar makes one (via ai-usage.sh) every few seconds, so the cache trails by
# about that. Until a refresh lands it reads Claude Code's own cache, which
# Claude Code refreshes only when it reads usage itself.
# Usage: fable-usage.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Print Fable's weekly usage limit, in whole percent."
    echo "Usage: fable-usage.sh"
    exit 0
fi

MAX_AGE=60
cache=$HOME/.cache/claude-usage.json
creds=$HOME/.claude/.credentials.json

if [[ -f $creds ]] && (( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) > MAX_AGE )); then
    mkdir -p "${cache%/*}"
    # Claims the refresh, so the sessions calling meanwhile don't each start one.
    touch "$cache"
    (
        tmp=$(mktemp "$cache.XXXXXX") || exit
        # The token goes in on stdin, kept out of the process list.
        if jq -r '"Authorization: Bearer \(.claudeAiOauth.accessToken)"' "$creds" \
            | curl -fsS -m 5 -H @- -H 'anthropic-beta: oauth-2025-04-20' \
                https://api.anthropic.com/api/oauth/usage > "$tmp" \
            && jq -e '.limits | arrays' "$tmp" >/dev/null; then
            mv "$tmp" "$cache"
        else
            rm -f "$tmp"
        fi
    ) </dev/null >/dev/null 2>&1 &  # Holding stdout open would make $(...) wait on it.
    disown
fi

src=$cache
[[ -s $src ]] || src=$HOME/.claude.json
read -r pct reset < <(jq -r '(.cachedUsageUtilization.utilization // .).limits[]?
    | select(.kind == "weekly_scoped" and (.scope.model.display_name? // "" | startswith("Fable")))
    | "\(.percent) \(.resets_at)"' "$src" 2>/dev/null) || exit 1

if [[ $reset != null ]] && (( $(date -d "$reset" +%s 2>/dev/null || echo 0) <= $(date +%s) )); then
    echo 0
else
    printf '%.0f\n' "$pct"
fi

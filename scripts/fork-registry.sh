#!/usr/bin/env bash
# Register forks (subagents) so a dead one can be recovered.
# Usage: fork-registry.sh          (SubagentStart/SubagentStop hook; payload on stdin)

set -uo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,3p' "$0" | sed 's/^# \?//'
    exit 0
fi

ROOT="${FORK_REGISTRY_ROOT:-$HOME/.claude/forks}"
RETAIN_DAYS="${FORK_REGISTRY_RETAIN_DAYS:-7}"
NUDGE_SECS="${FORK_REGISTRY_NUDGE_SECS:-600}"

payload=$(cat)
[ -n "$payload" ] || exit 0

# PostToolUse fires on every tool call and carries the whole tool_response, so
# these two run on the raw text rather than parsing megabytes of JSON. Both
# fields are emitted before tool_input/tool_response, hence head -1.
field() { printf '%s' "$payload" | grep -o "\"$1\":\"[^\"]*\"" | head -1 | cut -d'"' -f4; }

event=$(field hook_event_name)
agent=$(field agent_id)
[ -n "$agent" ] || exit 0

dir="$ROOT/$agent"

case "$event" in
SubagentStart)
    mkdir -p "$dir/scratch" || exit 0
    # Write via tmp: a jq failure here would otherwise leave a truncated
    # meta.json, which lists as neither open nor closed and never prunes.
    # Fork transcript lands beside the parent's, under <session>/subagents/.
    if printf '%s' "$payload" | jq \
        --arg started "$(date -Iseconds)" \
        --arg pid "${CLAUDE_PID:-}" \
        '{
            agent_id, agent_type, session_id, cwd,
            session_transcript: .transcript_path,
            fork_transcript: ((.transcript_path | sub("\\.jsonl$"; "")) + "/subagents/agent-" + .agent_id + ".jsonl"),
            pid: $pid, started: $started, status: "open"
        }' >"$dir/meta.json.tmp" 2>/dev/null; then
        mv "$dir/meta.json.tmp" "$dir/meta.json"
    else
        rm -f "$dir/meta.json.tmp"
    fi

    # Only a fork told its own scratchpad can write to it: it inherits the
    # parent's session id and never learns its own agent id.
    jq -n --arg d "$dir/scratch" '{
        hookSpecificOutput: {
            hookEventName: "SubagentStart",
            additionalContext: ("Fork scratchpad: " + $d + " — a durable dir only this fork owns, and the only thing besides your transcript that survives if you die before returning. Append to it as you go, never saved up for the end: each decision you settle and the reason, each approach you tried and rejected, each step you finish, anything the caller would have to redo from scratch. A few lines each time is enough; keep it current rather than tidy. It is insurance, not output — do not mention it in what you return.")
        }
    }'

    # Opportunistic prune of long-settled entries.
    find "$ROOT" -maxdepth 1 -mindepth 1 -type d -mtime "+$RETAIN_DAYS" \
        -exec grep -lq '"status": *"closed"' {}/meta.json \; \
        -exec rm -rf {} + 2>/dev/null
    ;;
PostToolUse)
    # Only forks this registry knows about, and only when they have gone quiet.
    dir="$ROOT/$agent"
    [ -d "$dir/scratch" ] || exit 0

    now=$(date +%s)
    last=0
    for f in "$dir/scratch"/* "$dir/nudged"; do
        [ -e "$f" ] || continue
        t=$(stat -c %Y "$f" 2>/dev/null) || continue
        [ "$t" -gt "$last" ] && last="$t"
    done
    # Never written and never nudged: measure from spawn instead.
    if [ "$last" = 0 ]; then
        t=$(stat -c %Y "$dir/meta.json" 2>/dev/null) && last="$t"
    fi
    [ "$last" != 0 ] || exit 0
    [ $(( now - last )) -gt "$NUDGE_SECS" ] || exit 0

    touch "$dir/nudged"
    jq -n --arg d "$dir/scratch" --arg m "$(( (now - last) / 60 ))" '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: ("Scratchpad check: nothing recorded for " + $m + " min. Append what you have settled since — decisions and their reasons, approaches rejected, steps finished — to " + $d + ". Keep working after; this is insurance against dying mid-run, not a request for a status report.")
        }
    }'
    ;;
SubagentStop)
    [ -f "$dir/meta.json" ] || exit 0
    tmp="$dir/meta.json.tmp"
    jq --slurpfile p <(printf '%s' "$payload") \
        --arg ended "$(date -Iseconds)" \
        '. + {
            status: "closed", ended: $ended,
            fork_transcript: ($p[0].agent_transcript_path // .fork_transcript),
            last_message: ($p[0].last_assistant_message // "")
        }' "$dir/meta.json" >"$tmp" 2>/dev/null && mv "$tmp" "$dir/meta.json"
    ;;
esac

exit 0

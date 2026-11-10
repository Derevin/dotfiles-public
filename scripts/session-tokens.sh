#!/usr/bin/env bash
# The calling Claude Code session's context size: input, cache-write and
# cache-read tokens of its last main-thread request, read from the session
# transcript. One request behind — the one in flight isn't recorded yet.

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Print the calling Claude Code session's context size in tokens."
    echo "Usage: session-tokens.sh"
    exit 0
fi

set -u

id=${CLAUDE_CODE_SESSION_ID:-}
if [[ -z $id ]]; then
    echo "session-tokens.sh: not inside a Claude Code session" >&2
    exit 1
fi

shopt -s nullglob
transcripts=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$id".jsonl)
if (( ${#transcripts[@]} == 0 )); then
    echo "session-tokens.sh: no transcript for session $id" >&2
    exit 1
fi

# A line still being appended fails to parse; the stderr drop keeps what came before it.
tokens=$(jq -r 'select(.type == "assistant" and (.isSidechain | not))
    | .message.usage // empty
    | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
    | select(. > 0)' "${transcripts[0]}" 2>/dev/null | tail -n 1)
if [[ -z $tokens ]]; then
    echo "session-tokens.sh: no request recorded yet" >&2
    exit 1
fi
echo "$tokens"

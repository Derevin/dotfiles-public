#!/usr/bin/env bash
# Claude Code PreToolUse gate for `git push` (wired in claude/settings.json:
# hooks.PreToolUse, matcher Bash). Reads the hook JSON on stdin.
#   bare `git push`                       -> exit 0 -> settings `allow` runs it silently
#   `git push origin main` / `... master` -> exit 0 -> settings `allow` runs it silently
#   `git push <anything else>`            -> permissionDecision "ask" -> Claude Code prompts
#   anything else                         -> exit 0 (defer)
# Only the bare push and the explicit origin main/master push are auto-allowed
# (a trailing `2>&1` redirect and/or a trailing `| tail|head|cat` with numeric
# args are tolerated); -u, --force, other remotes/branches, other redirects,
# other pipes, compound all prompt.
#
# Note: this Claude Code version ignores a hook `if:` filter, so the hook fires on EVERY
# Bash command. The cheap substring early-out below avoids spawning jq for non-push commands.
#
# Usage: git-push-gate.sh [--help]   (invoked as a hook, not by hand)
set -uo pipefail

case "${1:-}" in
  -h|--help)
    echo "Claude Code PreToolUse gate: auto-allow bare 'git push' and 'git push origin main|master'; prompt otherwise."
    echo "Usage: git-push-gate.sh   (reads hook JSON on stdin)"
    exit 0 ;;
esac

IFS= read -r -d '' input || true

# Cheap early-out: skip the jq spawn unless the payload even mentions a push.
case "$input" in
  *'git push'*) ;;
  *) exit 0 ;;
esac

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

# Only gate git push invocations; defer everything else.
printf '%s' "$cmd" | grep -qE '^[[:space:]]*git[[:space:]]+push([[:space:]]|$)' || exit 0

# Bare `git push` or `git push origin main|master` (with an optional trailing
# `2>&1` redirect and/or `| tail|head|cat <nums>`) -> defer so settings `allow` runs it.
printf '%s' "$cmd" | grep -qE '^[[:space:]]*git[[:space:]]+push([[:space:]]+origin[[:space:]]+(main|master))?([[:space:]]+2>&1)?([[:space:]]*\|[[:space:]]*(tail|head|cat)[[:space:]0-9nN-]*)?[[:space:]]*$' && exit 0

# Otherwise it is `git push` with other arguments -> force a prompt.
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"only bare git push and git push origin main|master are auto-allowed"}}'

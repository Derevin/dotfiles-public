#!/usr/bin/env bash
# Inspect the fork registry: what never returned, and what forks kept out of the caller.
# Usage: fork-recover.sh [--all] [--session ID] [--idle SECS] [--tokens] [--prune] [AGENT_ID]

set -uo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,3p' "$0" | sed 's/^# \?//'
    echo
    echo "  (no args)      unreturned forks dispatched from this directory"
    echo "  --all          every project, not just this directory"
    echo "  --session ID   only forks of that parent session"
    echo "  --idle SECS    transcript silence before STALE (default 300)"
    echo "  AGENT_ID       full detail: scratchpad, transcript trail, last words"
    echo "  --tokens       what returned forks kept out of the caller's context"
    echo "  --prune        drop settled entries"
    echo
    echo "Status: DEAD = owning session gone. STALE = session alive but the fork's"
    echo "transcript has been silent (may be dead, or mid-build). running = active."
    echo
    echo "KEPT: how far a fork's context grew past its own briefing, so what the"
    echo "caller would have carried had the work run inline. RET: what came back."
    exit 0
fi

ROOT="${FORK_REGISTRY_ROOT:-$HOME/.claude/forks}"
[ -d "$ROOT" ] || { echo "No fork registry at $ROOT"; exit 0; }

ALL=0
SESSION=""
TOKENS=0
TARGET=""
IDLE_SECS=300
SCRATCH_CAP=400

while [ $# -gt 0 ]; do
    case "$1" in
    --all) ALL=1 ;;
    --tokens) TOKENS=1 ;;
    --session)
        [ $# -ge 2 ] || { echo "--session needs an ID" >&2; exit 2; }
        SESSION="$2"; shift ;;
    --idle)
        [ $# -ge 2 ] || { echo "--idle needs seconds" >&2; exit 2; }
        IDLE_SECS="$2"; shift ;;
    --prune)
        find "$ROOT" -maxdepth 1 -mindepth 1 -type d \
            -exec grep -lq '"status": *"closed"' {}/meta.json \; \
            -exec rm -rf {} + 2>/dev/null
        echo "Pruned settled entries."
        exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) TARGET="$1" ;;
    esac
    shift
done

# The registry records what a fork kept out of its caller when the fork closes
# (see fork-registry.sh), so open entries and ones predating the accounting have
# no numbers to show.
if [ "$TOKENS" = 1 ]; then
    if [ "$ALL" = 1 ]; then
        mode=all; scope=""; label="every project"
    elif [ -n "$SESSION" ]; then
        mode=session; scope="$SESSION"; label="session ${SESSION%%-*}"
    elif [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
        mode=session; scope="$CLAUDE_CODE_SESSION_ID"; label="this session"
    else
        mode=cwd; scope="$PWD"; label="this directory"
    fi

    report=$(jq -sr --arg mode "$mode" --arg scope "$scope" --arg label "$label" '
        def k: if . == null then "-"
               elif . >= 10000 then "\(. / 1000 | floor)k"
               elif . >= 1000 then "\(. / 100 | floor / 10)k"
               else "\(.)" end;
        def l(n): tostring | . + ((" " * (n - length)) // "");
        def r(n): tostring | ((" " * (n - length)) // "") + .;
        [ .[] | select($mode == "all"
                       or ($mode == "session" and .session_id == $scope)
                       or ($mode == "cwd" and .cwd == $scope)) ] as $scoped
        | ([ $scoped[] | select(.tokens) ] | sort_by(.started // "")) as $rows
        | ([ $scoped[] | select(.tokens | not) ] | length) as $bare
        | ($rows | map(.tokens.kept) | add // 0) as $kept
        | ($rows | map(.tokens.returned) | add // 0) as $ret
        | (if $bare > 0 then
               "\($bare) more with no accounting: still open, or closed before it was recorded."
           else null end) as $note
        | if ($rows | length) == 0 then "Nothing metered for \($label).", ($note // empty)
          else
              ("AGENT" | l(19)) + ("TYPE" | l(21)) + ("TURNS" | r(6))
                  + ("KEPT" | r(8)) + ("RET" | r(8)) + ("OUT" | r(8)),
              ($rows[] | (.agent_id | l(19)) + ((.agent_type // "?") | l(21))
                  + (.tokens.turns | r(6)) + ((.tokens.kept | k) | r(8))
                  + (("~" + (.tokens.returned | k)) | r(8))
                  + ((.tokens.output | k) | r(8))),
              "",
              "\($rows | length) fork\(if ($rows | length) == 1 then "" else "s" end) kept \($kept | k) out of \($label), returned ~\($ret | k) (net ~\(($kept - $ret) | k))",
              ($note // empty)
          end' "$ROOT"/*/meta.json 2>/dev/null)
    if [ -n "$report" ]; then
        printf '%s\n' "$report"
    else
        echo "No accounting found in $ROOT."
    fi
    exit 0
fi

# Forks are in-process and share the CLI's pid, so the pid alone cannot tell a
# dead fork from a live one. Transcript mtime is the only per-fork heartbeat.
fork_state() {
    local pid="$1" transcript="$2" now idle mtime
    if [ -n "$pid" ] && [ "$pid" != "null" ] && ! kill -0 "$pid" 2>/dev/null; then
        echo "DEAD"; return
    fi
    if [ ! -f "$transcript" ]; then echo "STALE"; return; fi
    now=$(date +%s)
    mtime=$(stat -c %Y "$transcript" 2>/dev/null) || { echo "STALE"; return; }
    idle=$(( now - mtime ))
    if [ "$idle" -gt "$IDLE_SECS" ]; then echo "STALE"; else echo "running"; fi
}

idle_of() {
    local transcript="$1" now mtime
    [ -f "$transcript" ] || { echo "-"; return; }
    now=$(date +%s)
    mtime=$(stat -c %Y "$transcript" 2>/dev/null) || { echo "-"; return; }
    echo "$(( (now - mtime) / 60 ))m"
}

if [ -n "$TARGET" ]; then
    meta="$ROOT/$TARGET/meta.json"
    [ -f "$meta" ] || { echo "No such fork: $TARGET"; exit 1; }
    echo "=== fork $TARGET ==="
    jq -r 'to_entries[] | select(.key != "last_message") | "  \(.key): \(.value)"' "$meta" 2>/dev/null

    scratch="$ROOT/$TARGET/scratch"
    if [ -n "$(ls -A "$scratch" 2>/dev/null)" ]; then
        echo
        echo "=== scratchpad ==="
        find "$scratch" -type f | while read -r f; do
            echo "--- ${f#"$scratch"/}"
            head -c 20000 "$f"
            lines=$(wc -l <"$f" 2>/dev/null || echo 0)
            [ "$lines" -gt "$SCRATCH_CAP" ] && echo "[... $lines lines total, truncated]"
        done
    else
        echo
        echo "=== scratchpad: empty (fork wrote nothing) ==="
    fi

    tr_path=$(jq -r '.fork_transcript // empty' "$meta" 2>/dev/null)
    if [ -f "$tr_path" ]; then
        echo
        echo "=== last 25 actions ==="
        jq -r 'select(.type=="assistant") | .message.content[]?
               | if .type=="tool_use" then
                     "  [tool] \(.name): \((.input | tostring)[0:160])"
                 elif .type=="text" and (.text | length) > 0 then
                     "  [said] \((.text | gsub("\n"; " "))[0:200])"
                 else empty end' "$tr_path" 2>/dev/null | tail -25
        echo
        echo "=== where it stopped ==="
        tail -1 "$tr_path" | jq -r '"  stop_reason: \(.message.stop_reason // "none — died mid-step")"' 2>/dev/null
        echo "  transcript idle: $(idle_of "$tr_path")"
    else
        echo
        echo "=== transcript missing: $tr_path ==="
    fi
    exit 0
fi

printf '%-18s %-9s %-7s %-7s %-22s %s\n' AGENT STATUS AGE IDLE TYPE CWD
found=0
filtered=0
for d in "$ROOT"/*/; do
    meta="${d%/}/meta.json"
    [ -f "$meta" ] || continue
    status=$(jq -r '.status // "?"' "$meta" 2>/dev/null)
    [ "$status" = "open" ] || continue

    cwd=$(jq -r '.cwd // ""' "$meta" 2>/dev/null)
    sess=$(jq -r '.session_id // ""' "$meta" 2>/dev/null)
    if { [ "$ALL" != 1 ] && [ "$cwd" != "$PWD" ]; } \
        || { [ -n "$SESSION" ] && [ "$sess" != "$SESSION" ]; }; then
        filtered=$((filtered + 1))
        continue
    fi

    tr_path=$(jq -r '.fork_transcript // ""' "$meta" 2>/dev/null)
    pid=$(jq -r '.pid // ""' "$meta" 2>/dev/null)

    started=$(jq -r '.started // ""' "$meta" 2>/dev/null)
    age="?"
    if [ -n "$started" ]; then
        s=$(date -d "$started" +%s 2>/dev/null) && n=$(date +%s) \
            && age="$(( (n - s) / 60 ))m"
    fi

    printf '%-18s %-9s %-7s %-7s %-22s %s\n' \
        "$(basename "$d")" "$(fork_state "$pid" "$tr_path")" "$age" \
        "$(idle_of "$tr_path")" "$(jq -r '.agent_type // "?"' "$meta" 2>/dev/null)" "$cwd"
    found=1
done

if [ "$found" != 1 ]; then
    if [ "$filtered" -gt 0 ]; then
        echo "(none here — $filtered elsewhere; try --all)"
    else
        echo "(none — every fork returned)"
    fi
fi

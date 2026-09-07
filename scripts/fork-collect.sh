#!/usr/bin/env bash
# Wait for dispatched subagents to finish, then print the reports they wrote.
# Usage: fork-collect.sh [--timeout SECS] REPORT_DIR AGENT_ID:REPORT_FILE...

set -uo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,3p' "$0" | sed 's/^# \?//'
    echo
    echo "  REPORT_DIR          the directory you told the children to write into"
    echo "  AGENT_ID:REPORT_FILE  one per child: the id the Agent tool handed back,"
    echo "                      and the file name you gave that child"
    echo "  --timeout           seconds to wait for the whole set (default 900)"
    echo
    echo "A dispatching subagent is not reliably notified when a child finishes and"
    echo "has no TaskOutput, so the registry is what a fork has: a child is done when"
    echo "its entry closes. Naming the file per child is what makes a silent one"
    echo "visible; exits 1 if any child never closed or left no usable report."
    exit 0
fi

ROOT="${FORK_REGISTRY_ROOT:-$HOME/.claude/forks}"
TIMEOUT=900
POLL=5

while [ $# -gt 0 ]; do
    case "$1" in
    --timeout)
        [ $# -ge 2 ] || { echo "--timeout needs seconds" >&2; exit 2; }
        # Unchecked, this reaches an arithmetic expansion, where bash evaluates a
        # non-numeric value's contents rather than reading a number.
        case "$2" in '' | *[!0-9]*) echo "--timeout: want seconds, got '$2'" >&2; exit 2 ;; esac
        TIMEOUT="$2"; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) break ;;
    esac
    shift
done

[ $# -ge 2 ] || { echo "Usage: fork-collect.sh [--timeout SECS] REPORT_DIR AGENT_ID:REPORT_FILE..." >&2; exit 2; }

DIR="$1"
shift

ids=()
files=()
for arg in "$@"; do
    case "$arg" in *:*) ;; *) echo "Want AGENT_ID:REPORT_FILE, got: $arg" >&2; exit 2 ;; esac
    a="${arg%%:*}"
    f="${arg#*:}"
    case "$a" in '' | *[!a-zA-Z0-9_-]*) echo "Not an agent id: $a" >&2; exit 2 ;; esac
    case "$f" in '' | */*) echo "Want a file name, not a path: $f" >&2; exit 2 ;; esac
    ids+=("$a")
    files+=("$f")
done

# 10# because a caller-supplied 08 or 09 is a valid count of seconds and an
# invalid octal literal.
deadline=$(($(date +%s) + 10#$TIMEOUT))
pending=("${!ids[@]}")
bailed=0
pass=0
while [ ${#pending[@]} -gt 0 ]; do
    still=()
    noentry=0
    for i in "${pending[@]}"; do
        meta="$ROOT/${ids[$i]}/meta.json"
        if [ ! -f "$meta" ]; then
            noentry=1
            still+=("$i")
            continue
        fi
        grep -q '"status": *"closed"' "$meta" 2>/dev/null && continue
        still+=("$i")
    done
    pending=("${still[@]}")
    [ ${#pending[@]} -eq 0 ] && break
    # The start hook writes the entry at spawn, so a missing one won't appear later.
    if [ "$noentry" = 1 ] && [ "$pass" -gt 0 ]; then bailed=1; break; fi
    [ "$(date +%s)" -lt "$deadline" ] || break
    pass=$((pass + 1))
    sleep "$POLL"
done

status=0
if [ ! -d "$DIR" ]; then
    # Checked here rather than up front: the directory can be the children's to create.
    echo "!! no such directory: $DIR" >&2
    status=1
else
    for i in "${!ids[@]}"; do
        report="$DIR/${files[$i]}"
        if [ -L "$report" ]; then
            echo "!! not a report, a symlink: ${files[$i]}" >&2
            status=1
        elif [ -s "$report" ]; then
            echo "########## ${files[$i]}"
            cat "$report" || { echo "!! unreadable: ${files[$i]}" >&2; status=1; }
            echo
        elif [ -f "$report" ]; then
            # Distinct from missing: the child got there and lost the content.
            echo "!! ${ids[$i]} wrote an empty ${files[$i]}" >&2
            status=1
        else
            echo "!! ${ids[$i]} wrote no ${files[$i]}" >&2
            status=1
        fi
    done
fi

for i in ${pending[@]+"${pending[@]}"}; do
    if [ ! -f "$ROOT/${ids[$i]}/meta.json" ]; then
        echo "!! no registry entry, so a wrong id or the start hook didn't run: ${ids[$i]}" >&2
    elif [ "$bailed" = 1 ]; then
        echo "!! not waited for, the batch stopped on a missing entry: ${ids[$i]}" >&2
    else
        echo "!! never closed: ${ids[$i]}" >&2
    fi
    status=1
done
exit "$status"

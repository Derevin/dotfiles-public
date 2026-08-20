#!/usr/bin/env bash
# Live task list: rerun task-list.sh when the project's tasks dir changes.
#
# Polling, not inotify: this has to work from a tmux pane on WSL and Git Bash
# too, and a find over a few hundred task files costs a rounding error of the
# poll interval. A detected change is rendered only after a settle delay, so a
# burst (a git pull, a task script's mv + commit) redraws once, once it has
# landed, instead of once per file. Nothing here runs git, so it can never
# contend for the tasks repo's index lock.
set -uo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Live task list: rerun task-list.sh when the project's tasks dir changes."
    echo "Usage: task-watch.sh [--project NAME] [--poll SECS] [--settle SECS] [-- task-list.sh args...]"
    echo "Keys: q quits, any other key redraws. Resizing the pane redraws too."
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

POLL=2
SETTLE=6
PROJECT=""
LIST_ARGS=()

# Called as need_value "$@" so a flag missing its value errors out instead of
# leaving a failed `shift 2` to spin the parse loop forever.
need_value() {
    [[ $# -ge 2 ]] || { echo "error: $1 needs a value" >&2; exit 1; }
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --project) need_value "$@"; PROJECT=$2; shift 2 ;;
        --poll) need_value "$@"; POLL=$2; shift 2 ;;
        --settle) need_value "$@"; SETTLE=$2; shift 2 ;;
        --) shift; LIST_ARGS=("$@"); break ;;
        *) echo "error: unexpected argument: $1" >&2; exit 1 ;;
    esac
done

if ! [[ $POLL =~ ^[0-9]+$ && $SETTLE =~ ^[0-9]+$ ]]; then
    echo "error: --poll and --settle take whole seconds" >&2; exit 1
fi

if [[ -n "$PROJECT" ]]; then
    TASKS_DIR="$TASKS_ROOT/$PROJECT"
    if [[ ! -d "$TASKS_DIR" ]]; then
        echo "error: tasks dir not found: $TASKS_DIR" >&2; exit 1
    fi
else
    detect_project
fi

signature() {
    find "$TASKS_DIR" -maxdepth 2 -name '*.md' -printf '%P %T@ %s\n' 2>/dev/null | sort
}

# One fork for both dimensions and no terminfo lookup: stty reads the pane's tty
# off stdin. Piped stdin has no size, hence the fallback.
term_size() {
    local sz
    sz=$(stty size 2>/dev/null)
    [[ $sz =~ ^[0-9]+\ [0-9]+$ ]] || sz="24 80"
    printf '%s' "$sz"
}

# Trailing status line owns the last row, and the body stays a line short of the
# pane so printing it can't scroll the top away. The list runs headerless: the
# status line already names the project, and three rows matter in a short pane.
render() {
    local out rows avail total
    out=$(task-list.sh --no-header "${LIST_ARGS[@]}" "$PROJECT" 2>&1)
    size=$(term_size)
    rows=${size%% *}
    avail=$((rows - 1))
    total=$(wc -l <<<"$out")
    clear
    if ((total > avail)); then
        head -n $((avail - 1)) <<<"$out"
        printf '  +%d more\n' "$((total - avail + 1))"
    else
        printf '%s\n' "$out"
    fi
    printf '%s, updated %s (q quits)' "$PROJECT" "$(date +%H:%M:%S)"
}

finish() {
    printf '\n'
    exit 0
}

trap render WINCH
trap finish INT TERM

sig=$(signature)
render

while :; do
    # read doubles as the poll timer: a keypress redraws at once, and the wait is
    # short enough that a change nothing signalled can't sit stale for long.
    if [[ -t 0 ]]; then
        if read -rsn1 -t "$POLL" key; then
            [[ $key == q ]] && finish
            render
            continue
        fi
    else
        sleep "$POLL"
    fi
    # A resize is polled rather than left to the WINCH trap above: a shell that
    # has sat in this loop for hours can end up catching the signal and never
    # running the trap, leaving the view stale until the next keypress.
    if [[ "$(term_size)" != "$size" ]]; then
        render
        continue
    fi
    if [[ "$(signature)" != "$sig" ]]; then
        sleep "$SETTLE"
        sig=$(signature)
        render
    fi
done

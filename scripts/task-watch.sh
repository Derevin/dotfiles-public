#!/usr/bin/env bash
# Live task list: rerun task-list.sh when the project's tasks dir changes.
#
# Polling, not inotify: this has to work from a tmux pane on WSL and Git Bash
# too, and a find over a few hundred task files costs a rounding error of the
# poll interval. A detected change is rendered only after a settle delay, so a
# burst (a git pull, a task script's mv + commit) redraws once, once it has
# landed, instead of once per file. Nothing here runs git, so it can never
# contend for the tasks repo's index lock.
#
# --with puts a second project's list in a right-aligned column beside the
# first, for a pane parked in a repo whose queue is not the only one worth
# watching.
set -uo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo "Live task list: rerun task-list.sh when the project's tasks dir changes."
    echo "Usage: task-watch.sh [--project NAME] [--with NAME] [--poll SECS] [--settle SECS] [--once] [-- task-list.sh args...]"
    echo "--with draws a second project's list right-aligned beside the first."
    echo "--once prints one frame and exits, leaving the screen alone."
    echo "Keys: q quits, any other key redraws. Resizing the pane redraws too."
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/task-lib.sh"

POLL=2
SETTLE=6
PROJECT=""
WITH_PROJECT=""
ONCE=false
LIST_ARGS=()
GUTTER=2

# Called as need_value "$@" so a flag missing its value errors out instead of
# leaving a failed `shift 2` to spin the parse loop forever.
need_value() {
    [[ $# -ge 2 ]] || { echo "error: $1 needs a value" >&2; exit 1; }
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --project) need_value "$@"; PROJECT=$2; shift 2 ;;
        --with) need_value "$@"; WITH_PROJECT=$2; shift 2 ;;
        --once) ONCE=true; shift ;;
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

# A second column of the project already in the first is the same list twice,
# so it collapses back to one — the caller can then pass --with unconditionally.
[[ "$WITH_PROJECT" == "$PROJECT" ]] && WITH_PROJECT=""

WATCH_DIRS=("$TASKS_DIR")
if [[ -n "$WITH_PROJECT" ]]; then
    WITH_DIR="$TASKS_ROOT/$WITH_PROJECT"
    if [[ ! -d "$WITH_DIR" ]]; then
        echo "error: tasks dir not found: $WITH_DIR" >&2; exit 1
    fi
    WATCH_DIRS+=("$WITH_DIR")
fi

# %p rather than %P: two roots can hold the same relative path, and a change
# that only moves a file between them still has to read as a change.
signature() {
    find "${WATCH_DIRS[@]}" -maxdepth 2 -name '*.md' -printf '%p %T@ %s\n' 2>/dev/null | sort
}

# One fork for both dimensions and no terminfo lookup: stty reads the pane's tty
# off stdin. Piped stdin has no size, so an exported LINES/COLUMNS gets a say
# before the last-resort default.
term_size() {
    local sz
    sz=$(stty size 2>/dev/null)
    [[ $sz =~ ^[0-9]+\ [0-9]+$ ]] || sz="${LINES:-24} ${COLUMNS:-80}"
    printf '%s' "$sz"
}

list_for() {
    task-list.sh --no-header "${LIST_ARGS[@]}" "$1" 2>&1
}

# A list cut down to one column of the pane: every line clipped to the width,
# because a line that wrapped would push the row below it off the bottom, and
# the tail traded for a count when the list is taller than the rows on offer.
fit_column() {
    local width=$1 rows=$2 text=$3
    local -a lines
    mapfile -t lines <<<"$text"
    local total=${#lines[@]} i
    if ((total > rows)); then
        for ((i = 0; i < rows - 1; i++)); do printf '%s\n' "${lines[i]:0:width}"; done
        printf '  +%d more\n' "$((total - rows + 1))"
    else
        for ((i = 0; i < total; i++)); do printf '%s\n' "${lines[i]:0:width}"; done
    fi
}

# The second column takes only the width its own longest line needs, up to half
# the pane, leaving the rest to the project the pane is parked in.
columns() {
    local cols=$1 avail=$2
    local -a left right
    local lw rw i l r n
    rw=$(awk '{ if (length > m) m = length } END { print m+0 }' <<<"$SECOND")
    ((rw > (cols - GUTTER) / 2)) && rw=$(((cols - GUTTER) / 2))
    ((rw < 1)) && rw=1
    lw=$((cols - rw - GUTTER))
    ((lw < 1)) && lw=1
    mapfile -t left < <(fit_column "$lw" "$avail" "$FIRST")
    mapfile -t right < <(fit_column "$rw" "$avail" "$SECOND")
    n=${#left[@]}
    ((${#right[@]} > n)) && n=${#right[@]}
    for ((i = 0; i < n; i++)); do
        l=${left[i]-}
        r=${right[i]-}
        # Pad only where something follows the padding; a row the second column
        # has run out of ends at its own last character.
        if [[ -z "$r" ]]; then
            printf '%s\n' "$l"
        else
            printf '%-*s%*s%s\n' "$lw" "$l" "$GUTTER" "" "$r"
        fi
    done
}

# Trailing status line owns the last row, and the body stays a line short of the
# pane so printing it can't scroll the top away. The lists run headerless: the
# status line already names them, and three rows matter in a short pane.
render() {
    local rows cols avail stat
    FIRST=$(list_for "$PROJECT")
    [[ -n "$WITH_PROJECT" ]] && SECOND=$(list_for "$WITH_PROJECT")
    size=$(term_size)
    rows=${size%% *}
    cols=${size##* }
    avail=$((rows - 1))
    $ONCE || clear
    if [[ -n "$WITH_PROJECT" ]]; then
        columns "$cols" "$avail"
    else
        fit_column "$cols" "$avail" "$FIRST"
    fi
    stat=$(printf '%s, updated %s (q quits)' "$PROJECT" "$(date +%H:%M:%S)")
    # Right-aligning the second project's name is what labels its column: the
    # status row is the only one that can name it without costing the lists one.
    if [[ -n "$WITH_PROJECT" ]] && ((${#stat} + ${#WITH_PROJECT} < cols)); then
        printf '%-*s%s' "$((cols - ${#WITH_PROJECT}))" "$stat" "$WITH_PROJECT"
    else
        printf '%s' "$stat"
    fi
}

finish() {
    printf '\n'
    exit 0
}

# The pane is a display, not a prompt: keys are read unechoed, so the only
# thing a cursor does here is sit on the status line's last character.
if ! $ONCE; then
    trap 'tput cnorm 2>/dev/null' EXIT
    tput civis 2>/dev/null
fi

sig=$(signature)
render
$ONCE && { printf '\n'; exit 0; }

trap render WINCH
trap finish INT TERM

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

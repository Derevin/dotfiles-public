#!/usr/bin/env bash
# Unit tests for task-watch.sh — how one frame is laid out.
#
# Self-contained: a temp tasks root, no git, no project detection. Every frame
# is rendered with --once and stdin closed, so term_size falls through stty to
# the LINES/COLUMNS given here and the layout is deterministic.
# Usage: test-task-watch.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the task-watch.sh unit tests."
    echo "Usage: test-task-watch.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/proj/todo" "$TMP/dotfiles/todo"
printf '# Sensor\n' > "$TMP/proj/todo/H003-fix-sensor-bug.md"
printf '# Conf\n' > "$TMP/dotfiles/todo/N001-tweak-conf.md"

export TASKS_ROOT="$TMP"
# task-watch.sh calls task-list.sh by name — the working tree's, not the
# installed one.
export PATH="$SCRIPT_DIR/../scripts:$PATH"

COLS=60
watch() { LINES=24 COLUMNS=$COLS "$SCRIPT_DIR/../scripts/task-watch.sh" --once "$@" </dev/null; }

# The footer marker, computed the same way the script does: a two-letter weekday
# and MM-DD for the day the window reaches back to.
sincefmt() { local s; s=$(LC_TIME=C date -d "$1 days ago" '+%a %m-%d'); printf '%s%s' "${s:0:2}" "${s:3}"; }

solo=$(watch --project proj)
ok "one project lists only its own tasks" \
    "$(grep -c 'N001' <<<"$solo")" 0

both=$(watch --project proj --with dotfiles)
ok "--with keeps the primary list" "$(grep -c 'H003' <<<"$both")" 1
ok "--with adds the second project" "$(grep -c 'N001' <<<"$both")" 1
ok "both lists share a row" \
    "$(grep -c 'H003-fix-sensor-bug.md .* N001-tweak-conf.md' <<<"$both")" 1

# The second column is flush with the right edge: its widest line, the task
# name, ends in the pane's last cell.
ok "the second column is right-aligned" \
    "$(awk '/N001/ { print length }' <<<"$both")" "$COLS"
ok "the status line names the second column at that edge" \
    "$(tail -1 <<<"$both" | sed 's/.*[^a-z]//')" dotfiles
ok "the status line reaches the same edge" \
    "$(tail -1 <<<"$both" | wc -c)" "$((COLS + 1))"

# A pane is a fixed grid: a line that wrapped would push the row below it off
# the bottom, so every line is cut to fit instead.
printf '# Long\n' > "$TMP/dotfiles/todo/N002-a-task-whose-name-runs-well-past-half-the-pane.md"
printf '# Long\n' > "$TMP/proj/todo/H004-another-very-long-task-name-that-would-wrap.md"
wide=$(watch --project proj --with dotfiles)
ok "no line overflows the pane" \
    "$(awk -v c="$COLS" 'length > c { n++ } END { print n+0 }' <<<"$wide")" 0
ok "the second column is capped at half the pane" \
    "$(awk '/N002/ { print length }' <<<"$wide")" "$COLS"

# A block cursor parked in the last cell sits on top of the status line's last
# character. Keys are read unechoed, so the live view has no use for one.
civis=$(TERM=xterm tput civis)
cnorm=$(TERM=xterm tput cnorm)
live=$(TERM=xterm LINES=24 COLUMNS=$COLS timeout 2 \
    "$SCRIPT_DIR/../scripts/task-watch.sh" --project proj --with dotfiles --poll 1 </dev/null 2>&1)
ok "the live view hides the cursor" "${live:0:${#civis}}" "$civis"
ok "and puts it back on the way out" "${live: -${#cnorm}}" "$cnorm"
ok "--once leaves the cursor alone" "$(grep -cF "$civis" <<<"$both")" 0

# So the workspace script can pass --with unconditionally.
ok "--with naming the primary renders one column" \
    "$(watch --project proj --with proj | head -n -1)" \
    "$(watch --project proj | head -n -1)"

fails "$SCRIPT_DIR/../scripts/task-watch.sh" --project proj --with nope
fails "$SCRIPT_DIR/../scripts/task-watch.sh" --project proj --with

# task-watch.sh asks task-list.sh for done + canceled from the last 7 days, so a
# recently finished task surfaces in the frame and a long-finished one does not.
mkdir -p "$TMP/proj/done"
printf '# Shipped\n' > "$TMP/proj/done/N050-shipped.md"
touch -d '2 days ago' "$TMP/proj/done/N050-shipped.md"
printf '# Ancient\n' > "$TMP/proj/done/N051-ancient.md"
touch -d '40 days ago' "$TMP/proj/done/N051-ancient.md"
frame=$(watch --project proj)
ok "the frame shows a recently done task" "$(grep -c 'N050-shipped' <<<"$frame")" 1
ok "the frame hides a long-done task" "$(grep -c 'N051-ancient' <<<"$frame")" 0

# The footer carries a "done since" marker: the day the window reaches back to.
ok "the footer shows the done-since marker at the default window" \
    "$(tail -1 <<<"$frame" | grep -oE 'done since [A-Za-z]{2} [0-9]{2}-[0-9]{2}')" \
    "done since $(sincefmt 7)"

# --recent sets where the window starts: it moves the marker and the cutoff.
narrow=$(watch --project proj --recent 3)
ok "--recent moves the marker" \
    "$(tail -1 <<<"$narrow" | grep -oE 'done since [A-Za-z]{2} [0-9]{2}-[0-9]{2}')" \
    "done since $(sincefmt 3)"
ok "--recent narrows the window, hiding the 40-day-old done" \
    "$(grep -c 'N051-ancient' <<<"$narrow")" 0
widewin=$(watch --project proj --recent 50)
ok "--recent widens the window, revealing it" \
    "$(grep -c 'N051-ancient' <<<"$widewin")" 1

report

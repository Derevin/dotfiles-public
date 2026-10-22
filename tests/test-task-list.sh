#!/usr/bin/env bash
# Unit tests for task-list.sh — what each output mode prints.
#
# Self-contained: a temp tasks root, no git, no project detection.
# Usage: test-task-list.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the task-list.sh unit tests."
    echo "Usage: test-task-list.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/proj"/{todo,planned,active,stale}
printf '# Sensor\n' > "$TMP/proj/todo/H003-fix-sensor-bug.md"
printf '# Readme\n' > "$TMP/proj/todo/U012-update-readme.md"
printf '# Api\n' > "$TMP/proj/planned/N007-refactor-api.md"
printf '# Being\n\nWorker: hlab-9\n' > "$TMP/proj/active/H001-being-done.md"
printf '# Paused\n\nWorker: hlab-5\n' > "$TMP/proj/stale/H002-paused.md"

mkdir -p "$TMP/proj"/{done,canceled}
printf '# Shipped\n' > "$TMP/proj/done/N020-recent-done.md"
touch -d '2 days ago' "$TMP/proj/done/N020-recent-done.md"
printf '# Shipped long ago\n' > "$TMP/proj/done/N021-old-done.md"
touch -d '30 days ago' "$TMP/proj/done/N021-old-done.md"
printf '# Dropped\n' > "$TMP/proj/canceled/N022-recent-cancel.md"
touch -d '1 day ago' "$TMP/proj/canceled/N022-recent-cancel.md"

export TASKS_ROOT="$TMP"
list() { "$SCRIPT_DIR/../scripts/task-list.sh" "$@" proj; }

# The chooser feeds lab-start.sh, which reads the id back out of whatever it is
# given — so the letter can stay, and priority stays visible while choosing.
ok "--ids keeps the priority letter" \
    "$(list --status todo --ids)" \
    "$(printf 'H003-fix-sensor-bug\nU012-update-readme')"
ok "--ids sorts by priority" \
    "$(list --status todo planned --ids | head -1)" \
    H003-fix-sensor-bug
ok "--ids drops the header" "$(list --status planned --ids)" N007-refactor-api

ok "listing names files" "$(list --status planned --no-header)" \
    "$(printf 'PLANNED (1)\n  N007-refactor-api.md')"

# A set-aside task lives in stale/, listed above todo, and keeps its Worker: so
# the lab holding the partial work stays named.
ok "default view puts stale above todo, worker kept" \
    "$(list --no-header)" \
    "$(printf 'ACTIVE (1)\n  H001-being-done.md [hlab-9]\nPLANNED (1)\n  N007-refactor-api.md\nSTALE (1)\n  H002-paused.md [hlab-5]\nTODO (2)\n  H003-fix-sensor-bug.md\n  U012-update-readme.md')"
ok "--status stale is accepted, shows the worker" \
    "$(list --status stale --no-header)" \
    "$(printf 'STALE (1)\n  H002-paused.md [hlab-5]')"

# --recent appends done then canceled below the open queue, each windowed to the
# last N days by file mtime and shown only when its window holds something.
recent=$(list --no-header --recent 7)
ok "--recent shows done inside the window" "$(grep -c 'N020-recent-done' <<<"$recent")" 1
ok "--recent hides done outside the window" "$(grep -c 'N021-old-done' <<<"$recent")" 0
ok "--recent counts only the windowed files" "$(grep -c '^DONE (1)$' <<<"$recent")" 1
ok "--recent shows canceled inside the window" "$(grep -c 'N022-recent-cancel' <<<"$recent")" 1
ok "--recent appends DONE then CANCELED below the open queue" \
    "$(grep -oE '^[A-Z]+' <<<"$recent" | paste -sd' ')" \
    "ACTIVE PLANNED STALE TODO DONE CANCELED"
ok "--recent sets the recent tail off with one blank line" \
    "$(awk '/^DONE /{print (prev=="") ? 1 : 0} {prev=$0}' <<<"$recent")" 1

ok "a wider window reaches older done" \
    "$(list --no-header --recent 100 | grep -c 'N021-old-done')" 1

# A category empty within the window prints no header.
mkdir -p "$TMP/fresh"/{todo,done,canceled}
printf '# New\n' > "$TMP/fresh/todo/N001-new.md"
ok "--recent omits an empty done/canceled" \
    "$("$SCRIPT_DIR/../scripts/task-list.sh" --no-header --recent 7 fresh | grep -cE '^(DONE|CANCELED)')" 0

report

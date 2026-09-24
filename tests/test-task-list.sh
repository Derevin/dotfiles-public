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

report

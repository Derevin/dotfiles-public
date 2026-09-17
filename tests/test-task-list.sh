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

mkdir -p "$TMP/proj"/{todo,planned}
printf '# Sensor\n' > "$TMP/proj/todo/H003-fix-sensor-bug.md"
printf '# Readme\n' > "$TMP/proj/todo/U012-update-readme.md"
printf '# Api\n' > "$TMP/proj/planned/N007-refactor-api.md"

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

report

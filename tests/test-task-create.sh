#!/usr/bin/env bash
# Unit tests for task-create.sh: title-only task creation, -p priority, slugging,
# ID allocation, and the refusals (empty title, bad priority) that write nothing.
#
# Self-contained: a throwaway tasks repo with its own origin (the script pushes)
# and a throwaway checkout naming its project through .find-project.conf.
# Usage: test-task-create.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the task-create.sh unit tests."
    echo "Usage: test-task-create.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"

# The working tree, not whatever the installer last linked.
export PATH="$SCRIPT_DIR/../scripts:$PATH"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

q() { git "$@" >/dev/null 2>&1; }

git init -q --bare "$TMP/tasks-origin.git"
git clone -q "$TMP/tasks-origin.git" "$TMP/tasks" 2>/dev/null
q -C "$TMP/tasks" config user.email t@t
q -C "$TMP/tasks" config user.name T
echo tasks > "$TMP/tasks/README.md"
q -C "$TMP/tasks" add -A
q -C "$TMP/tasks" commit -m init
q -C "$TMP/tasks" branch -M main
q -C "$TMP/tasks" push -u origin main

export TASKS_ROOT="$TMP/tasks"
TASKS="$TMP/tasks/widget"

# find-project.sh reads the cwd; the override file names the project without
# going through projects.conf. task-create.sh makes the project dir itself.
git init -q "$TMP/widget"
printf 'project = widget\n' > "$TMP/widget/.find-project.conf"
cd "$TMP/widget"

run() { "$@" >/dev/null 2>&1; }
empty() { [ -f "$1" ] && [ ! -s "$1" ] && echo y; }
there() { [ -f "$TASKS/todo/$1.md" ] && echo y; }

# --- creation ----------------------------------------------------------------

run task-create.sh "Fix the thing"
ok "default priority N, first id"      "$(there N001-fix-the-thing)" y
ok "file created empty"                "$(empty "$TASKS/todo/N001-fix-the-thing.md")" y
ok "commit subject is Add: <slug>"     "$(git -C "$TASKS_ROOT" log -1 --format=%s)" "Add: fix-the-thing"

run task-create.sh -p H "Urgent thing"
ok "-p sets the letter"                "$(there H002-urgent-thing)" y

run task-create.sh -p u "Minor thing"
ok "-p lowercases to upper"            "$(there U003-minor-thing)" y

run task-create.sh "Fix: the (API)!!"
ok "slug drops punctuation/collapses"  "$(there N004-fix-the-api)" y

run task-create.sh these are loose words
ok "unquoted multi-word title joins"   "$(there N005-these-are-loose-words)" y

# --- refusals write nothing --------------------------------------------------

before=$(ls "$TASKS/todo" | wc -l)
fails task-create.sh ""
fails task-create.sh "   "
fails task-create.sh -p HH "two-letter prio"
fails task-create.sh -p 3 "digit prio"
fails task-create.sh "!!!"
after=$(ls "$TASKS/todo" | wc -l)
ok "refusals create no file"           "$before" "$after"

# an id is consumed only by a successful create: the next one is 006, not higher
run task-create.sh "After the failures"
ok "failed creates consume no id"      "$(there N006-after-the-failures)" y

# --- help --------------------------------------------------------------------

ok "--help prints a Usage line"        "$(task-create.sh --help | grep -c '^Usage:')" 1

report

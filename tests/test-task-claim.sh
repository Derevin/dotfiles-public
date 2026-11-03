#!/usr/bin/env bash
# Unit tests for task-claim.sh worker stamping. The focus is the empty reminder
# task (task-create.sh writes an empty file): the claim must stamp a Worker:
# line even with no line 1 to append after, including the plan-then-reclaim that
# /fix-task does.
#
# Self-contained: a throwaway tasks repo with its own origin (the scripts push)
# and a throwaway checkout naming its project through .find-project.conf.
# Usage: test-task-claim.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the task-claim.sh worker-stamping unit tests."
    echo "Usage: test-task-claim.sh"
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

# Deterministic worker: LAB_NAME wins in detect_worker; clear the Coder override.
unset CODER_WORKSPACE_NAME
export LAB_NAME=dlab-326

run()    { "$@" >/dev/null 2>&1; }
wcount() { grep -c '^Worker: ' "$1"; }
wval()   { sed -n 's/^Worker: //p' "$1" | head -1; }

# --- empty reminder task: claim must stamp (the bug) -------------------------

file=N001-fix-99-percent.md
run task-create.sh "fix 99 percent"
ok "reminder task starts empty"   "$([ -s "$TASKS/todo/$file" ] && echo n || echo y)" y

run task-claim.sh "$file"                        # todo/ -> planning/
ok "claim stamps empty task"      "$(wcount "$TASKS/planning/$file")" 1
ok "claim stamps right worker"    "$(wval "$TASKS/planning/$file")" dlab-326

# --- the reclaim (/fix-task step 7): plan strips, claim re-stamps -------------

run task-planned.sh "$file"                      # planning/ -> planned/, strip
ok "plan strips worker"           "$(wcount "$TASKS/planned/$file")" 0

run task-claim.sh "$file"                         # planned/ -> active/, re-stamp
ok "reclaim stamps empty task"    "$(wcount "$TASKS/active/$file")" 1
ok "reclaim stamps right worker"  "$(wval "$TASKS/active/$file")" dlab-326

# --- normal task: worker lands after the title, nothing else disturbed --------

printf '# normal task\n\nbody line\n' > "$TASKS/todo/N010-normal-task.md"
q -C "$TASKS_ROOT" add -A
q -C "$TASKS_ROOT" commit -m "Add: normal-task"
run task-claim.sh N010-normal-task.md
norm="$TASKS/planning/N010-normal-task.md"
ok "normal claim: one worker line"    "$(wcount "$norm")" 1
ok "normal claim: title stays line 1" "$(sed -n '1p' "$norm")" "# normal task"
ok "normal claim: worker on line 2"   "$(sed -n '2p' "$norm")" "Worker: dlab-326"
ok "normal claim: body preserved"     "$(grep -c '^body line$' "$norm")" 1

# --- resume a task that already carries a worker: re-stamp, no duplicate -------

printf '# resume me\nWorker: hlab-old\n\nbody\n' > "$TASKS/stale/N011-resume.md"
q -C "$TASKS_ROOT" add -A
q -C "$TASKS_ROOT" commit -m "Stale: resume"
run task-claim.sh N011-resume.md                  # stale/ -> active/, re-stamp
res="$TASKS/active/N011-resume.md"
ok "resume: exactly one worker line"  "$(wcount "$res")" 1
ok "resume: re-stamped to new worker" "$(wval "$res")" dlab-326

# --- help --------------------------------------------------------------------

ok "--help prints a Usage line"   "$(task-claim.sh --help | grep -c '^Usage:')" 1

report

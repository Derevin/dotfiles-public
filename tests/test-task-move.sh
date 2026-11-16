#!/usr/bin/env bash
# Unit tests for task-move.sh, the manual move: which landings it allows, the
# refusals that change nothing, the Worker: line, the commit subject. Also the
# TASK_PROJECT override (task-move.sh, task-create.sh) and task-commit.sh's
# TASKS_ROOT.
#
# Self-contained: a throwaway tasks repo with its own origin (the scripts push)
# and a throwaway checkout naming its project through .find-project.conf. HOME
# points into the temp dir too, so a script that ignored TASKS_ROOT would find no
# ~/repos/tasks to commit in rather than the real one.
# Usage: test-task-move.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the task-move.sh unit tests."
    echo "Usage: test-task-move.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"

# The working tree, not whatever the installer last linked.
export PATH="$SCRIPT_DIR/../scripts:$PATH"
unset TASK_PROJECT

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

q() { git "$@" >/dev/null 2>&1; }

git init -q --bare "$TMP/tasks-origin.git"
git clone -q "$TMP/tasks-origin.git" "$TMP/tasks" 2>/dev/null
q -C "$TMP/tasks" config user.email t@t
q -C "$TMP/tasks" config user.name T
for p in widget proj; do
    mkdir -p "$TMP/tasks/$p"/{todo,planning,planned,active,stale,done,canceled}
done
echo tasks > "$TMP/tasks/README.md"
q -C "$TMP/tasks" add -A
q -C "$TMP/tasks" commit -m init
q -C "$TMP/tasks" branch -M main
q -C "$TMP/tasks" push -u origin main

export TASKS_ROOT="$TMP/tasks"

# The override file names the project to find-project.sh without going
# through projects.conf. Outside any checkout it has nothing to read.
git init -q "$TMP/widget"
printf 'project = widget\n' > "$TMP/widget/.find-project.conf"
mkdir -p "$TMP/elsewhere"
cd "$TMP/widget"

run() { "$@" >/dev/null 2>&1; }
at() { [ -f "$TASKS_ROOT/${3:-widget}/$1/$2.md" ] && echo y; }
wcount() { grep -c '^Worker: ' "$TASKS_ROOT/widget/$1/$2.md" 2>/dev/null; }
head_sha() { git -C "$TASKS_ROOT" rev-parse HEAD; }
origin_sha() { git -C "$TASKS_ROOT" rev-parse origin/main; }
subject() { git -C "$TASKS_ROOT" log -1 --format=%s; }

N=0
# seed <status> [project] — a fresh task there, stamped with a worker and
# committed like any other. Sets $T; a command substitution would increment N in
# a subshell and hand every case the same name.
seed() {
    N=$((N + 1))
    T=$(printf 'N%03d-task-%d' "$N" "$N")
    printf '# T\nWorker: hlab-5\n\nbody\n' > "$TASKS_ROOT/${2:-widget}/$1/$T.md"
    q -C "$TASKS_ROOT" add -A
    q -C "$TASKS_ROOT" commit -m "seed $T"
    q -C "$TASKS_ROOT" push
}

# --- every legal landing -------------------------------------------------------

legal() {
    case $1 in
        todo) echo planned done canceled ;;
        planning|stale) echo todo planned done canceled ;;
        planned) echo todo done canceled ;;
        active) echo todo planned stale done canceled ;;
        done) echo todo planned canceled ;;
        canceled) echo todo planned done ;;
    esac
}

for from in todo planning planned active stale done canceled; do
    for to in $(legal "$from"); do
        seed "$from"
        run task-move.sh "$T" "$to"
        ok "$from -> $to lands" "$(at "$to" "$T")" y
        ok "$from -> $to leaves $from" "$(at "$from" "$T")" ""
        ok "$from -> $to commit subject" "$(subject)" "Move: task-$N $from->$to"
    done
done
ok "the moves reach origin" "$(origin_sha)" "$(head_sha)"

seed todo
run task-move.sh "$T.md" done
ok "takes a filename with .md" "$(at done "$T")" y

# --- the Worker: line ------------------------------------------------------------

seed active
run task-move.sh "$T" todo
ok "a move strips the worker" "$(wcount todo "$T")" 0
seed stale
run task-move.sh "$T" planned
ok "leaving stale strips it too" "$(wcount planned "$T")" 0
seed active
run task-move.sh "$T" stale
ok "landing in stale keeps it" "$(wcount stale "$T")" 1

# --- refusals change nothing -----------------------------------------------------

# refused <status the task stays in, or empty> <args...> — exits non-zero, says
# why on stderr, and leaves the file where it was with no commit made.
refused() {
    local stays=$1 before err rc
    shift
    before=$(head_sha)
    err=$(task-move.sh "$@" 2>&1 >/dev/null); rc=$?
    ok "refuses: $*" "$([ "$rc" -ne 0 ] && echo y)" y
    ok "says why: $*" "$([ -n "$err" ] && echo y)" y
    ok "no commit: $*" "$(head_sha)" "$before"
    if [ -n "$stays" ]; then ok "file stays: $*" "$(at "$stays" "$T")" y; fi
}

for from in todo planning planned done canceled; do
    seed "$from"
    refused "$from" "$T" stale
done
seed todo
refused todo "$T" planning
seed planned
refused planned "$T" active
seed active
refused active "$T" active
seed todo
refused todo "$T" todo
seed done
refused done "$T" done
seed todo
refused todo "$T" bogus
refused todo "$T"
refused "" N099-no-such-task todo
refused ""
seed todo
cp "$TASKS_ROOT/widget/todo/$T.md" "$TASKS_ROOT/widget/done/"
q -C "$TASKS_ROOT" add -A
q -C "$TASKS_ROOT" commit -m "dup $T"
refused todo "$T" planned
ok "file stays: the second copy" "$(at done "$T")" y

# --- TASK_PROJECT ----------------------------------------------------------------

seed todo
(cd "$TMP/elsewhere" && TASK_PROJECT=widget task-move.sh "$T" done) >/dev/null 2>&1
ok "TASK_PROJECT moves from outside the project" "$(at done "$T")" y

seed todo proj
TASK_PROJECT=proj run task-move.sh "$T" planned
ok "TASK_PROJECT beats the cwd's project" "$(at planned "$T" proj)" y

seed todo
fails env TASK_PROJECT=nope task-move.sh "$T" done
ok "an unknown TASK_PROJECT moves nothing" "$(at todo "$T")" y

# An empty value is no override: the cwd's project still answers.
TASK_PROJECT= run task-move.sh "$T" done
ok "an empty TASK_PROJECT falls back to the cwd" "$(at done "$T")" y

(cd "$TMP/elsewhere" && TASK_PROJECT=proj task-create.sh "from afar") >/dev/null 2>&1
ok "TASK_PROJECT creates from outside the project" \
    "$(ls "$TASKS_ROOT/proj/todo" | grep -c -- '-from-afar\.md$')" 1

fails env TASK_PROJECT=nope task-create.sh "typo"
ok "an unknown TASK_PROJECT creates no project" "$([ -e "$TASKS_ROOT/nope" ] || echo y)" y

# --- task-commit.sh --------------------------------------------------------------

seed todo
echo edited >> "$TASKS_ROOT/widget/todo/$T.md"
run task-commit.sh "Edit: task-$N"
ok "task-commit.sh commits under TASKS_ROOT" "$(subject)" "Edit: task-$N"
ok "and pushes" "$(origin_sha)" "$(head_sha)"

# --- help --------------------------------------------------------------------

ok "--help prints a Usage line" "$(task-move.sh --help | grep -c '^Usage:')" 1
ok "--help needs no project" \
    "$(cd "$TMP/elsewhere" && task-move.sh --help >/dev/null 2>&1 && echo y)" y

report

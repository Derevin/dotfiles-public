#!/usr/bin/env bash
# Unit tests for the task scripts' filename argument — every one of them names a
# task either way, `N042-some-slug` or `N042-some-slug.md`.
#
# Self-contained: a throwaway tasks repo with its own origin (each script commits
# and pushes) and a throwaway checkout naming its project through
# .find-project.conf.
# Usage: test-task-args.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the task script argument-form unit tests."
    echo "Usage: test-task-args.sh"
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
TASKS="$TMP/tasks/widget"
mkdir -p "$TASKS"/{todo,planning,planned,active,stale,done,canceled}
echo tasks > "$TMP/tasks/README.md"
q -C "$TMP/tasks" add -A
q -C "$TMP/tasks" commit -m init
q -C "$TMP/tasks" branch -M main
q -C "$TMP/tasks" push -u origin main

export TASKS_ROOT="$TMP/tasks"

# detect_project and detect_worker both read the cwd; the override file names
# the project without going through projects.conf.
git init -q "$TMP/widget"
printf 'project = widget\n' > "$TMP/widget/.find-project.conf"
cd "$TMP/widget"

run() { "$@" >/dev/null 2>&1; }
at() { [ -f "$TASKS/$1/$2.md" ] && echo y; }
worker() { sed -n 's/^Worker: //p' "$TASKS/$1/$2.md" | head -1; }

N=0
# next <dir> — a fresh task there, named by a counter and committed like any
# other. Sets $T; a command substitution would increment N in a subshell and
# hand every case the same name.
next() {
    N=$((N + 1))
    T=$(printf 'N%03d-task-%d' "$N" "$N")
    printf '# T\n\nbody\n' > "$TASKS/$1/$T.md"
    q -C "$TMP/tasks" add -A
    q -C "$TMP/tasks" commit -m "seed $T"
    q -C "$TMP/tasks" push
}

# The slash commands name a task as `N042-some-slug` and the argument is often
# handed straight on, extension and all left off. Each case gets a fresh task:
# the scripts move files, so no two can share one.
for suffix in "" ".md"; do
    what=$([ -n "$suffix" ] && echo "a filename" || echo "a bare name")

    next planned
    run task-claim.sh "$T$suffix"
    ok "claim takes $what (planned/)" "$(at active "$T")" y
    run task-restamp.sh "$T$suffix" hlab-9
    ok "restamp takes $what" "$(worker active "$T")" hlab-9
    run task-unclaim.sh "$T$suffix"
    ok "unclaim takes $what" "$(at planned "$T")" y
    run task-reprioritize.sh "$T$suffix" H
    ok "reprioritize takes $what" "$(at planned "H${T#N}")" y

    next todo
    run task-claim.sh "$T$suffix"
    ok "claim takes $what (todo/)" "$(at planning "$T")" y
    run task-planned.sh "$T$suffix"
    ok "planned takes $what" "$(at planned "$T")" y

    next active
    run task-done.sh "$T$suffix"
    ok "done takes $what" "$(at done "$T")" y

    next todo
    run task-cancel.sh "$T$suffix"
    ok "cancel takes $what" "$(at canceled "$T")" y

    # stale round-trip: active -> stale keeps the worker (the lab lives on next
    # to it); stale -> active resumes without doubling the Worker: line.
    next planned
    run task-claim.sh "$T$suffix"
    run task-stale.sh "$T$suffix"
    ok "stale takes $what" "$(at stale "$T")" y
    ok "stale keeps worker ($what)" "$(worker stale "$T")" main
    run task-claim.sh "$T$suffix"
    ok "claim resumes from stale/ ($what)" "$(at active "$T")" y
    ok "resume leaves one Worker line ($what)" \
        "$(grep -c '^Worker: ' "$TASKS/active/$T.md" 2>/dev/null)" 1

    # a lab renamed while its task sits stale carries the Worker: with it
    run task-stale.sh "$T$suffix"
    run task-restamp.sh "$T$suffix" hlab-7
    ok "restamp reaches stale/ ($what)" "$(worker stale "$T")" hlab-7

    # cancel reaches a stale task directly, no resume first
    run task-cancel.sh "$T$suffix"
    ok "cancel reaches stale/ ($what)" "$(at canceled "$T")" y
done

fails task-claim.sh N099-no-such-task

report

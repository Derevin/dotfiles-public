#!/usr/bin/env bash
# Destroy a lab's backend and worktree, keeping its conversation history.
#
# Refuses while the lab still holds work: a dirty worktree, a HEAD no remote ref
# can reach, or an attached task not groomed, done or canceled. --force
# overrides all three.
#
# --check runs the guards and stops without destroying anything: exit 0 droppable,
# exit 1 not, the reason on stdout. The picker resolves every lab through it.
#
# Usage: lab-destroy.sh [--force] [--check] <lab>
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Destroy a lab: its worktree and its container or workspace."
    echo "Usage: lab-destroy.sh [--force] [--check] <lab>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-lib.sh"

FORCE=0
CHECK=0
while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        --check) CHECK=1; shift ;;
        *) break ;;
    esac
done
NAME="${1:-}"
[ -n "$NAME" ] || { echo "usage: lab-destroy.sh [--force] [--check] <lab>" >&2; exit 2; }

lab_resolve "$NAME"

# In check mode the reason is data the picker captures, so it goes to stdout bare;
# a real drop addresses the user, naming the lab and the escape hatch.
refuse() {
    [ "$CHECK" -eq 1 ] && { printf '%s\n' "$1"; exit 1; }
    echo "lab-destroy: $NAME $1 — use --force to drop anyway" >&2
    exit 1
}

# Uncommitted or unpushed work. The common case is a detached HEAD with no
# branch and no upstream, so the guard is on HEAD itself: reachable from some
# remote ref or it exists only here. A branch with an upstream is the same check
# by another name.
if [ "$FORCE" -eq 0 ]; then
    if [ "$LAB_BACKEND" = coder ]; then
        # A clab's code lives inside the workspace, so the check has to run
        # there. Unreachable means unverifiable, which is not the same as clean.
        state=$(LAB_PROJECT_OVERRIDE="$LAB_PROJECT_KEY" lab-run "$NAME" -- bash -lc '
            test -n "$(git status --porcelain)" && echo dirty
            for r in $(git for-each-ref --format="%(refname)" refs/remotes); do
                git merge-base --is-ancestor HEAD "$r" 2>/dev/null && exit 0
            done
            echo unreachable' 2>/dev/null) \
            || refuse "workspace is not reachable, so its state cannot be checked"
        case "$state" in
            *dirty*) refuse "has uncommitted changes" ;;
            *unreachable*) refuse "has commits no remote ref can reach" ;;
        esac
    elif [ -d "$LAB_WORKTREE" ]; then
        [ -n "$(git -C "$LAB_WORKTREE" status --porcelain)" ] && refuse "has uncommitted changes"
        reachable=0
        while read -r ref; do
            git -C "$LAB_WORKTREE" merge-base --is-ancestor HEAD "$ref" 2>/dev/null && { reachable=1; break; }
        done < <(git -C "$LAB_WORKTREE" for-each-ref --format='%(refname)' refs/remotes)
        [ "$reachable" -eq 1 ] || refuse "has commits no remote ref can reach"
    fi

    # An attached task still queued or in flight. Groomed (planned), finished
    # (done) or abandoned (canceled): the states that leave nothing to do.
    id=$(lab_task_id "$NAME") || true
    if [ -n "$id" ]; then
        task_path=$(lab_task_find "$LAB_PROJECT" "$id" todo planning planned active stale done canceled 2>/dev/null) || rc=$?
        # A task that cannot be found is a lab whose task was deleted — nothing
        # left to hold it. A task id that resolves to two files is the opposite:
        # one of them may well be in flight, and refusing to guess is the whole
        # point of the ambiguity error.
        case "${rc:-0}" in
            0)
                dir=$(basename "$(dirname "$task_path")")
                case "$dir" in
                    planned|done|canceled) ;;
                    *) refuse "is attached to a task in $dir/" ;;
                esac
                ;;
            2) refuse "has an ambiguous task id $id" ;;
        esac
    fi
fi

[ "$CHECK" -eq 1 ] && exit 0

case "$LAB_BACKEND" in
    docker) lab_container_exists "$LAB_CONTAINER" && docker rm -f "$LAB_CONTAINER" >/dev/null ;;
    coder) lab_workspace_exists "$LAB_CONTAINER" && coder delete "$LAB_CONTAINER" -y ;;
esac

if [ "$LAB_BACKEND" != coder ] && [ -d "$LAB_WORKTREE" ]; then
    git -C "$LAB_CHECKOUT" worktree remove --force "$LAB_WORKTREE"
fi

echo "dropped $NAME"

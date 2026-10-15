#!/usr/bin/env bash
# Rebuild a dropped lab around the Claude conversation that outlived it.
#
# A drop destroys the worktree and the container or workspace but deliberately
# keeps ~/.claude/projects/<encoded> — the conversation, keyed on the worktree
# path, which the lab name and so the task id determine. This re-creates the lab
# at that same name and resumes the conversation in it. A task retitled across
# claims can leave more than one: the newest becomes the lab, the rest fold in
# beside it as resumable sessions.
#
# The name is recovered from the surviving dir, not from the task, so a rebuild
# works whatever became of the task — done and canceled included. Refuses when a
# live lab already holds the task (attach it instead) and when the task left no
# conversation (nothing to rebuild — plan-task/implement-task make a fresh one).
# Backend: the argument, else the one backend whose history holds the id; an id
# saved under more than one must name which.
#
# --list prints the task ids a rebuild can still recover for this project, newest
# first: the chooser behind the `reconstruct` recipe.
#
# Usage: lab-reconstruct.sh [--list] | <task-id> [host|docker|coder]
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Rebuild a dropped lab around its surviving Claude conversation and resume it."
    echo "Usage: lab-reconstruct.sh [--list] | <task-id> [host|docker|coder]"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# lab-lib.sh sits beside this once installed; in the repo the tmux and script
# helpers are kept apart.
for d in "$SCRIPT_DIR" "$SCRIPT_DIR/../scripts" "$SCRIPT_DIR/../public/scripts"; do
    [ -f "$d/lab-lib.sh" ] && { source "$d/lab-lib.sh"; break; }
done
declare -F lab_resolve >/dev/null || { echo "lab-reconstruct.sh: cannot find lab-lib.sh" >&2; exit 1; }

# --- the chooser: ids a rebuild can recover for this project -----------------
if [ "${1:-}" = "--list" ]; then
    PROJECT=$(lab_project_from_cwd) || exit 0
    lab_project_paths "$PROJECT" 2>/dev/null || exit 0

    # The ids a live lab still holds, from the canonical lister scoped by its
    # project column — so an id a rebuild would refuse is never offered.
    declare -A LIVE
    while read -r name _ proj _; do
        [ "$proj" = "$PROJECT" ] || continue
        [[ "$name" =~ ^([hdc])lab-([0-9]{3}) ]] && LIVE["${BASH_REMATCH[1]}${BASH_REMATCH[2]}"]=1
    done < <(lab-list.sh --long 2>/dev/null)

    # One row per surviving (backend, id): newest first, its newest slug and how
    # many conversations it kept. Grouped from the per-dir scan, which arrives
    # newest-first so the first row seen for a key is the one to show.
    lab_history_scan "$LAB_CHECKOUT" \
        | sort -t$'\t' -k1,1rn \
        | awk -F'\t' '
            { key = $2 SUBSEP $3 }
            !(key in seen) { seen[key]; order[++n] = key
                             letter[key]=$2; id[key]=$3; slug[key]=$4 }
            { count[key]++ }
            END { for (i=1;i<=n;i++){ k=order[i]
                     printf "%s\t%s\t%s\t%s\n", letter[k], id[k], slug[k], count[k] } }
          ' \
        | while IFS=$'\t' read -r letter id slug count; do
            [ -n "${LIVE[$letter$id]:-}" ] && continue
            label="$id"; [ -n "$slug" ] && label="$id-$slug"
            printf '%s\t(%s saved · %s)\n' "$label" "$count" "$(lab_backend "$letter")"
          done
    exit 0
fi

# --- rebuild -----------------------------------------------------------------
RAW="${1:-}"
BACKEND_ARG="${2:-}"
[ -n "$RAW" ] || { echo "usage: lab-reconstruct.sh [--list] | <task-id> [host|docker|coder]" >&2; exit 2; }
ID=$(lab_read_id "$RAW") || { echo "lab-reconstruct: cannot read a three-digit task id out of '$RAW'" >&2; exit 2; }

export TMUX=
CALLER=$(tmux show-environment -g JUST_CALLER 2>/dev/null | cut -d= -f2-) || true
[ -n "$CALLER" ] || CALLER="${TMUX_PANE:-}"
[ -n "$CALLER" ] || { echo "lab-reconstruct: no caller pane" >&2; exit 1; }

PROJECT=$(lab_project_from_cwd) || { echo "lab-reconstruct: not in a project checkout" >&2; exit 1; }
lab_project_paths "$PROJECT"

# Backend: the argument, else the one backend whose saved history holds this id.
# More than one is ambiguous — recovery must not guess which lab to rebuild.
if [ -n "$BACKEND_ARG" ]; then
    BACKEND=$(lab_backend "$BACKEND_ARG") || { echo "lab-reconstruct: unknown backend '$BACKEND_ARG'" >&2; exit 2; }
    LETTER=$(lab_backend_letter "$BACKEND")
else
    LETTER=""
    for l in h d c; do
        [ -n "$(lab_history_dirs "$LAB_CHECKOUT" "$l" "$ID")" ] || continue
        [ -z "$LETTER" ] || { echo "lab-reconstruct: task $ID has saved conversations in more than one backend — name one: lab-reconstruct.sh $ID <backend>" >&2; exit 1; }
        LETTER="$l"
    done
    [ -n "$LETTER" ] || { echo "lab-reconstruct: no saved conversation for task $ID in $PROJECT — plan-task/implement-task make a fresh lab" >&2; exit 1; }
    BACKEND=$(lab_backend "$LETTER")
fi

# The conversations that survived the drop, newest first.
STRANDED=()
while IFS= read -r d; do STRANDED+=("$d"); done < <(lab_history_dirs "$LAB_CHECKOUT" "$LETTER" "$ID")
[ "${#STRANDED[@]}" -gt 0 ] || { echo "lab-reconstruct: no saved conversation for $BACKEND task $ID" >&2; exit 1; }

# A live lab already holds the task: two labs for one (backend, task) is the state
# the naming scheme exists to prevent. Attach it, or drop it to rebuild afresh.
EXISTING=$(lab_task_lab "$BACKEND" "$ID") || { echo "lab-reconstruct: task $ID already has more than one $BACKEND lab" >&2; exit 1; }
[ -z "$EXISTING" ] || { echo "lab-reconstruct: task $ID already has the $BACKEND lab $EXISTING — attach it, or drop it to rebuild from the saved conversation" >&2; exit 1; }

# The newest surviving conversation names the lab: its project dir already sits at
# the path the name derives, so --continue finds it with nothing moved. Recover
# the name from that dir — slug characters pass through the encoding unchanged.
ENCCK=$(lab_claude_project_dir "$LAB_CHECKOUT"); ENCCK=${ENCCK##*/}
NAME=${STRANDED[0]##*/}; NAME=${NAME#"${ENCCK}-"}
[[ "$NAME" =~ ^${LETTER}lab-${ID}(-.+)?$ ]] || { echo "lab-reconstruct: ${STRANDED[0]} does not decode to a task-$ID lab name" >&2; exit 1; }

# Provision the backend at that exact name.
lab_provision "$BACKEND" "$NAME" || exit 1

# Fold the older conversations in beside the newest as resumable sessions. The
# newest IS the lab's own project dir, so it is skipped; the rest copy in without
# clobber, mtimes preserved so --continue still lands on the most recent.
NEW_PROJ=$(lab_claude_project_dir "${LAB_CHECKOUT}-${NAME}")
for d in "${STRANDED[@]}"; do
    [ "$d" = "$NEW_PROJ" ] && continue
    mkdir -p "$NEW_PROJ"
    cp -an "$d/." "$NEW_PROJ/" 2>/dev/null || true
done

# Still in the queue → mark it ours, the stamp a claim would set. Gone to done or
# canceled → nothing to stamp, and recovery does not reopen it.
if TASK_PATH=$(lab_task_find "$PROJECT" "$ID" 2>/dev/null); then
    (cd "$LAB_CHECKOUT" && task-restamp.sh "$(basename "$TASK_PATH")" "$(lab_head "$NAME")") >/dev/null 2>&1 || true
fi

exec lab-attach.sh --pane "$CALLER" "$NAME" --continue

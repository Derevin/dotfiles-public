#!/usr/bin/env bash
# Release every view of a lab and destroy it after checking for work it holds.
#
# Usage: lab-drop.sh [--force] [--check] <lab>
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Release every pane showing a lab, then destroy its worktree and container or workspace."
    echo "Usage: lab-drop.sh [--force] [--check] <lab>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-view-lib.sh"

ARGS=("$@")
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
[ -n "$NAME" ] || { echo "usage: lab-drop.sh [--force] [--check] <lab>" >&2; exit 2; }

lab_resolve "$NAME"
PROJECT="$LAB_PROJECT"

if [ "$CHECK" -eq 1 ]; then
    LAB_PROJECT_OVERRIDE="$LAB_PROJECT_KEY" exec lab-destroy.sh "${ARGS[@]}"
fi
if [ "$FORCE" -eq 0 ]; then
    rc=0
    reason=$(LAB_PROJECT_OVERRIDE="$LAB_PROJECT_KEY" lab-destroy.sh --check "$NAME") || rc=$?
    # Only a guard refusal (exit 1 with a reason) is one --force can override.
    if [ "$rc" -eq 1 ] && [ -n "$reason" ]; then
        echo "lab-drop: $NAME $reason — use --force to drop anyway" >&2
        exit 1
    fi
    [ "$rc" -eq 0 ] || exit "$rc"
fi

PANES=()
while read -r pane; do
    PANES+=("$pane")
    # Releasing the caller respawns it and kills this process group. TMUX_PANE is
    # cleared so the copy does not defer itself again.
    if [ "$pane" = "${TMUX_PANE:-}" ]; then
        LAB_PROJECT_OVERRIDE="$LAB_PROJECT_KEY" TMUX_PANE= setsid "$SCRIPT_DIR/lab-drop.sh" --force "$NAME" </dev/null >/dev/null 2>&1 &
        echo "dropping $NAME"
        exit 0
    fi
done < <(lab_panes_showing "$NAME")

# Release resolves the lab, so the backend still has to exist.
for pane in ${PANES+"${PANES[@]}"}; do
    lab-release.sh --pane "$pane" >/dev/null
done
LAB_PROJECT_OVERRIDE="$LAB_PROJECT_KEY" lab-destroy.sh --force "$NAME"
lab_state_drop_lab "$PROJECT" "$NAME"

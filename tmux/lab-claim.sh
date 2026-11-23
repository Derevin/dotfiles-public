#!/usr/bin/env bash
# Claim an anonymous lab for a task and resume its conversation in every view.
#
# Usage: lab-claim.sh <lab> <task-id>
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Claim an anonymous lab for a task and resume it in every pane showing it."
    echo "Usage: lab-claim.sh <lab> <task-id>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-view-lib.sh"

OLD="${1:-}"
ID="${2:-}"
if [ -z "$OLD" ] || [ -z "$ID" ]; then
    echo "usage: lab-claim.sh <lab> <task-id>" >&2
    exit 2
fi
# Let the core reject invalid claims before trying to resolve the lab.
if [[ ! "$ID" =~ ^[0-9]{3}$ ]] || ! lab_is_anonymous "$OLD"; then
    exec lab-rename.sh "$OLD" "$ID"
fi

lab_resolve "$OLD"
PROJECT="$LAB_PROJECT"
PANES=()
while read -r pane; do PANES+=("$pane"); done < <(lab_panes_showing "$OLD")

NEW=$(LAB_PROJECT_OVERRIDE="$LAB_PROJECT_KEY" lab-rename.sh "$OLD" "$ID")
lab_state_rename "$PROJECT" "$OLD" "$NEW"

# The rename moved the worktree out from under a claim typed inside it, and
# lab-attach falls back to the cwd to find an undeclared project.
[ ! -d "$LAB_CHECKOUT" ] || cd "$LAB_CHECKOUT"
SELF=""
for pane in ${PANES+"${PANES[@]}"}; do
    if [ "$pane" = "${TMUX_PANE:-}" ]; then
        SELF="$pane"
    else
        LAB_PROJECT_OVERRIDE="$LAB_PROJECT_KEY" lab-attach.sh --pane "$pane" "$NEW" --continue
    fi
done
# The caller respawns last so it cannot interrupt the other reattachments.
if [ -n "$SELF" ]; then
    LAB_PROJECT_OVERRIDE="$LAB_PROJECT_KEY" lab-attach.sh --pane "$SELF" "$NEW" --continue
fi
echo "$NEW"

#!/usr/bin/env bash
# Find or provision the lab for a task and print its name.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Find or create a task's lab and print its name."
    echo "Usage: lab-for-task.sh <task-id> [backend]"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-lib.sh"

# A chooser shows a readable N238-slug, not three bare digits; read the id back
# out of whatever form it arrives in.
RAW="${1:-}"
[ -n "$RAW" ] || { echo "usage: lab-for-task.sh <task-id> [backend]" >&2; exit 2; }
ID=$(lab_read_id "$RAW") || { echo "lab-for-task: cannot read a three-digit task id out of '$RAW'" >&2; exit 2; }

PROJECT=$(lab_project_from_cwd) || { echo "lab-for-task: not in a project checkout" >&2; exit 1; }
lab_project_paths "$PROJECT"

WANT=$(lab_backend_fallback "${2:-}")
[ -n "$WANT" ] || { echo "lab-for-task: no backend given, and $PROJECT declares none (see $LAB_CONF)" >&2; exit 1; }
BACKEND=$(lab_backend "$WANT") || { echo "lab-for-task: unknown backend '$WANT'" >&2; exit 1; }

# A missing or ambiguous task would strand an anonymous lab.
lab_task_find "$PROJECT" "$ID" >/dev/null

# One lab per (backend, task), keyed on the id. A task retitled since its lab was
# claimed derives a different name now, and asking after that name would mint a
# second lab beside the one already holding the work. The lab keeps the name it
# was claimed under: the slug was never the identity.
NAME=$(lab_task_lab "$BACKEND" "$ID")
if [ -n "$NAME" ]; then
    echo "$NAME"
else
    NEW=$(LAB_PROJECT_OVERRIDE="$PROJECT" lab-new.sh "$BACKEND")
    LAB_PROJECT_OVERRIDE="$PROJECT" lab-rename.sh "$NEW" "$ID"
fi

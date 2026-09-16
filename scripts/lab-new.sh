#!/usr/bin/env bash
# Create an anonymous lab and print its name.
#
# The lab is <b>lab-tmp<N> at the lowest free index — where investigation starts
# before it is worth filing. Claiming it later renames it (lab-claim.sh).
#
# Usage: lab-new.sh <host|docker|coder>
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Create an anonymous lab (<b>lab-tmp<N>) for the current project and print its name."
    echo "Usage: lab-new.sh <host|docker|coder>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-lib.sh"

BACKEND=$(lab_backend "${1:-}") || { echo "usage: lab-new.sh <host|docker|coder>" >&2; exit 2; }
LETTER=$(lab_backend_letter "$BACKEND")

PROJECT="${LAB_PROJECT_OVERRIDE:-}"
[ -n "$PROJECT" ] || PROJECT=$(lab_project_from_cwd) || { echo "lab-new: not in a project checkout" >&2; exit 1; }
lab_project_paths "$PROJECT"

# Lowest free index, derived rather than remembered: a worktree dir for host and
# docker, the container or workspace for the backends that have one.
NAME=""
for n in $(seq 1 99); do
    candidate="${LETTER}lab-tmp${n}"
    [ -d "${LAB_CHECKOUT}-${candidate}" ] && continue
    case "$BACKEND" in
        docker) lab_container_exists "${LAB_PREFIX}${candidate}" && continue ;;
        coder) lab_workspace_exists "${LAB_PREFIX}${candidate}" && continue ;;
    esac
    NAME="$candidate"; break
done
[ -n "$NAME" ] || { echo "lab-new: no free ${LETTER}lab-tmp index" >&2; exit 1; }

WORKTREE="${LAB_CHECKOUT}-${NAME}"

# The name on stdout is this script's whole output — lab-start.sh and the claim
# read it back. Everything else provisioning says goes to stderr.

# Coder workspaces clone the repo themselves at /workspace, so there is no host
# worktree to create — the provisioner is the whole job there.
if [ "$BACKEND" != coder ]; then
    [ -d "$LAB_CHECKOUT" ] || { echo "lab-new: no checkout at $LAB_CHECKOUT" >&2; exit 1; }
    BASE=$(lab_base_branch "$LAB_CHECKOUT")
    # Fetch so the detach lands on a current tip.
    git -C "$LAB_CHECKOUT" fetch --quiet origin "$BASE" || { echo "lab-new: fetch failed" >&2; exit 1; }
    # Detached: no script invents a branch name. Branch creation stays with
    # whoever starts committing.
    git -C "$LAB_CHECKOUT" worktree add --detach "$WORKTREE" "origin/$BASE" >&2
fi

if [ -n "$LAB_PROVISIONER" ]; then
    [ -x "$LAB_PROVISIONER" ] || { echo "lab-new: provisioner not executable: $LAB_PROVISIONER" >&2; exit 1; }
    if ! "$LAB_PROVISIONER" "$BACKEND" "$NAME" "$WORKTREE" >&2; then
        echo "lab-new: provisioning failed — removing $WORKTREE" >&2
        [ "$BACKEND" != coder ] && git -C "$LAB_CHECKOUT" worktree remove --force "$WORKTREE" >/dev/null 2>&1
        exit 1
    fi
elif [ "$BACKEND" != host ]; then
    echo "lab-new: no provisioner configured for $PROJECT — $BACKEND needs one (see $LAB_CONF)" >&2
    exit 1
fi

echo "$NAME"

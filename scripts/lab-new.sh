#!/usr/bin/env bash
# Create an anonymous lab and print its name.
#
# The lab is <b>lab-tmp<N> at the lowest free index — where investigation starts
# before it is worth filing. Claiming it later renames it (lab-claim.sh).
#
# Usage: lab-new.sh [host|docker|coder]
#   backend  omit to take the project's declared default (lab.conf).
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Create an anonymous lab (<b>lab-tmp<N>) for the current project and print its name."
    echo "Usage: lab-new.sh [host|docker|coder]"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-lib.sh"

PROJECT="${LAB_PROJECT_OVERRIDE:-}"
[ -n "$PROJECT" ] || PROJECT=$(lab_project_from_cwd) || { echo "lab-new: not in a project checkout" >&2; exit 1; }
lab_project_paths "$PROJECT"

# Most projects only ever use one backend, so the project declares it and the
# argument is for the exception. Nothing declared is not permission to guess: a
# lab in the wrong backend is provisioned, named and claimed before it shows.
WANT="${1:-$LAB_DEFAULT_BACKEND}"
[ -n "$WANT" ] || { echo "lab-new: no backend given, and $PROJECT declares none (see $LAB_CONF)" >&2; exit 2; }
BACKEND=$(lab_backend "$WANT") || { echo "lab-new: unknown backend '$WANT'" >&2; exit 2; }
LETTER=$(lab_backend_letter "$BACKEND")

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

# The name on stdout is this script's whole output — lab-start.sh and the claim
# read it back. Everything provisioning says goes to stderr.
lab_provision "$BACKEND" "$NAME" || exit 1

echo "$NAME"

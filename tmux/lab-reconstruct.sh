#!/usr/bin/env bash
# Rebuild a dropped lab and resume its conversation in the caller's pane.
# The reconstruct recipe uses --list to offer recoverable tasks.
#
# Usage: lab-reconstruct.sh [--list] | <task-id> [host|docker|coder]
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Rebuild a dropped lab around its surviving Claude conversation and resume it."
    echo "Usage: lab-reconstruct.sh [--list] | <task-id> [host|docker|coder]"
    exit 0
fi

if [ "${1:-}" = "--list" ]; then
    exec lab-rebuild.sh "$@"
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-view-lib.sh"

[ -n "${1:-}" ] || { echo "usage: lab-reconstruct.sh [--list] | <task-id> [host|docker|coder]" >&2; exit 2; }

export TMUX=
CALLER=$(lab_recipe_caller)
[ -n "$CALLER" ] || { echo "lab-reconstruct: no caller pane" >&2; exit 1; }

NAME=$(lab-rebuild.sh "$@")
exec lab-attach.sh --pane "$CALLER" "$NAME" --continue

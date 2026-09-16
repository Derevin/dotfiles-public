#!/usr/bin/env bash
# Print the lab the caller is standing in. Nothing, and a non-zero exit, outside
# one. Complements the task scripts' worker stamp, which is the head only.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Print the name of the lab the current shell is in (nothing outside one)."
    echo "Usage: lab-current.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-lib.sh"

lab_current || exit 1
echo

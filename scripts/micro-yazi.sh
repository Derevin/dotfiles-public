#!/usr/bin/env bash
# yazi file browser for micro, driven from init.lua (Ctrl-B = browse).
# Runs yazi in chooser mode: it draws to the terminal (micro suspends its screen),
# and on "open" writes the chosen path(s) to a temp file instead of opening them.
# We print those paths so init.lua can open the selection in micro.
# Usage: micro-yazi.sh [start-dir]

set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "yazi file browser for micro; prints the chosen file path(s)."
    echo "Usage: micro-yazi.sh [start-dir]"
    exit 0
fi

# Public clones don't vendor the binary (the bin/ tools are private). Exit 0 so
# micro just shows nothing rather than surfacing an error.
if ! command -v yazi >/dev/null 2>&1; then
    echo "micro-yazi.sh: yazi not installed" >&2
    exit 0
fi

chooser="$(mktemp)"
trap 'rm -f "$chooser"' EXIT

# yazi keeps its TUI on the terminal and writes only the chosen paths to the
# chooser file, so stdout stays clean for the cat below (same design as fzf).
yazi "${1:-.}" --chooser-file="$chooser"

cat -- "$chooser"
exit 0

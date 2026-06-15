#!/usr/bin/env bash
# Per-directory session store for micro's restore popup. Maps a directory -> the
# list of files (tabs) open there, so the popup reopens every tab per directory.
# init.lua records the full tab list on buffer open/switch; micro-session.sh
# reads it on launch. One path per line; a lone path (old format) still restores
# as a single tab. Store: ${XDG_CACHE_HOME:-~/.cache}/micro/lastfiles/<dir, / as %>
#
# Usage:
#   micro-lastfile.sh get [dir]         print files recorded for dir, one per line (default $PWD)
#   micro-lastfile.sh set <dir> [blob]  record blob (newline-separated files) as dir's session;
#                                        empty or omitted blob clears it
set -euo pipefail

store="${XDG_CACHE_HOME:-$HOME/.cache}/micro/lastfiles"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || -z "${1:-}" ]]; then
    echo "Per-directory session (open tabs) store for micro restore."
    echo "Usage:"
    echo "  micro-lastfile.sh get [dir]         print files recorded for dir, one per line (default \$PWD)"
    echo "  micro-lastfile.sh set <dir> [blob]  record blob (newline-separated files) as dir's session"
    exit 0
fi

# Flatten a directory path into a single store filename ('/' -> '%').
keyfile() {
    local dir="${1:-$PWD}"
    dir="${dir%/}"
    printf '%s/%s' "$store" "${dir//\//%}"
}

case "$1" in
    get)
        f="$(keyfile "${2:-}")"
        [[ -f "$f" ]] && cat -- "$f" || true
        ;;
    set)
        mkdir -p -- "$store"
        kf="$(keyfile "${2:-}")"
        if [[ -n "${3:-}" ]]; then
            printf '%s\n' "$3" > "$kf"
        else
            : > "$kf"
        fi
        ;;
    *)
        echo "micro-lastfile.sh: unknown subcommand '$1' (use get|set)" >&2
        exit 1
        ;;
esac

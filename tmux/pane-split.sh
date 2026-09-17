#!/usr/bin/env bash
# Lab-aware split helper for tmux bindings.
#
# Usage: pane-split.sh <h|v> [extra split-window args...]
#   h → horizontal split (-h)
#   v → vertical split (-v); honors the caller's @split-dir tag (up → above)
#
# If the calling pane has @lab set, the new pane runs `lab-shell` into the same
# lab — landing in its checkout with claude-less bash. Otherwise: a host shell
# inheriting pane_current_path.
#
# A front end and nothing more: it exists because a tmux binding cannot source a
# shell library. Anything already running in a shell calls pane_split itself.
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
    echo "Lab-aware split for tmux bindings; the new pane follows the caller's lab."
    echo "Usage: pane-split.sh <h|v> [extra split-window args...]"
    exit 0
fi

case "${1:-}" in
    h) DIR="-h" ;;
    v) DIR="-v" ;;
    *) echo "usage: $0 <h|v> [extra...]" >&2; exit 1 ;;
esac
shift

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# pane-lib.sh sits beside this script once installed; in the repo the tmux and
# script helpers are kept apart, and the private tmux scripts a level further.
for d in "$SCRIPT_DIR" "$SCRIPT_DIR/../scripts" "$SCRIPT_DIR/../public/scripts"; do
    [ -f "$d/pane-lib.sh" ] && { source "$d/pane-lib.sh"; break; }
done
declare -F pane_split >/dev/null || { echo "pane-split.sh: cannot find pane-lib.sh" >&2; exit 1; }

# Name the pane the binding fired in once, rather than letting three separate
# commands each resolve the default target.
ANCHOR=$(tmux display-message -p '#{pane_id}')
lab=$(tmux show-options -pvt "$ANCHOR" @lab 2>/dev/null || true)
cwd=$(tmux display-message -t "$ANCHOR" -p '#{pane_current_path}')
# pane_current_path can point at a stale host path (e.g. a renamed worktree
# dir); tmux -c requires the dir to exist. Fall back to $HOME if it doesn't.
[ -d "$cwd" ] || cwd="$HOME"

# run-shell puts anything on stdout in front of the user, so the pane id goes
# nowhere.
if [ -n "$lab" ]; then
    # New pane joins the same lab. The HOST cwd of the new docker-exec /
    # coder-ssh process is what pane_current_path returns — popups (M-j, M-g,
    # etc.) use it to find the right project justfile. lab-shell still sets the
    # IN-BACKEND cwd via -w / `cd`, so this -c only affects host-side path
    # resolution.
    pane_split "$DIR" -c "$cwd" "$ANCHOR" "lab-shell $lab" -- "$@" >/dev/null
else
    pane_split "$DIR" -c "$cwd" "$ANCHOR" -- "$@" >/dev/null
fi

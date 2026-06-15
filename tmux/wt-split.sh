#!/usr/bin/env bash
# wt-aware split helper for tmux bindings.
#
# Usage: wt-split.sh <h|v> [extra split-window args...]
#   h → horizontal split (-h)
#   v → vertical split (-v); honors the caller's @split-dir tag (up → above)
#
# If the calling pane has @wt set (a dwt or cwt pane), the new pane runs
# `wt-shell` into the same backend — landing in the worktree checkout with
# claude-less bash. Otherwise it behaves like the original binding: a host
# shell that inherits pane_current_path.
set -euo pipefail

case "${1:-}" in
    h) DIR="-h" ;;
    v) DIR="-v" ;;
    *) echo "usage: $0 <h|v> [extra...]" >&2; exit 1 ;;
esac
shift

# Vertical splits honor the caller's @split-dir tag so manual splits land on the
# same side as justfile dispatch (keep in sync with cc-just.sh): up → new pane
# above, down → below. Untagged panes keep the default (below) unless small and
# in the upper half.
BEFORE=""
if [ "$DIR" = "-v" ]; then
    split_dir=$(tmux show-options -pv @split-dir 2>/dev/null || true)
    if [ "$split_dir" = "up" ]; then
        BEFORE="-b"
    elif [ "$split_dir" != "down" ]; then
        pane_pos=$(tmux display-message -p '#{pane_top} #{pane_height} #{window_height}')
        read -r ptop pheight wheight <<< "$pane_pos"
        if (( ptop < wheight / 2 && pheight <= wheight / 2 )); then
            BEFORE="-b"
        fi
    fi
fi

wt=$(tmux show-options -pv @wt 2>/dev/null || true)
cwd=$(tmux display-message -p '#{pane_current_path}')
# pane_current_path can point at a stale host path (e.g. a renamed worktree
# dir); tmux -c requires the dir to exist. Fall back to $HOME if it doesn't.
[ -d "$cwd" ] || cwd="$HOME"
if [ -n "$wt" ]; then
    # New pane joins the same worktree backend. The HOST cwd of the new
    # docker-exec / coder-ssh process is what pane_current_path returns —
    # popups (M-j, M-g, etc.) use it to find the right project justfile.
    # wt-shell still sets the IN-BACKEND cwd via -w / `cd`, so this -c only
    # affects host-side path resolution.
    exec tmux split-window "$DIR" $BEFORE -c "$cwd" "$@" "wt-shell $wt"
else
    exec tmux split-window "$DIR" $BEFORE -c "$cwd" "$@"
fi

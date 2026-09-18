#!/usr/bin/env bash
# Dotfiles workspace: claude on left, live task list over a terminal on the
# right, sync strip on top.
#
# The top-right pane is parked in the workspace's own repo and runs
# task-watch.sh, a live queue view: the pane is rarely typed in, and Ctrl-C
# leaves a shell there when it is.
#
# Optional args: <extra-repo-path> [window-name] [claude-name]. When given, both
# right-hand panes are rooted in that repo, the bottom one runs its own claude
# instead of a plain dotfiles terminal, the window is named <window-name>
# (default "dotx"), and that claude's display name is <claude-name> (default:
# repo basename). A private recipe supplies these.
#
# Pane references are by pane_id (the stable %N) rather than index, because
# tmux re-numbers pane indices by spatial position when panes are added or
# removed — adding the sync strip above pane 1 reshuffles everything otherwise.
if [[ "${1:-}" == "--help" ]]; then
    echo "Dotfiles workspace: claude left, live task list over a terminal right."
    echo "Usage: workspace-dotfiles.sh [extra-repo-path] [window-name] [claude-name]"
    exit 0
fi

DIR=~/repos/dotfiles
EXTRA_REPO="${1:-}"

BASE="dotfiles"
RIGHT_DIR="$DIR"
if [[ -n "$EXTRA_REPO" ]]; then
    BASE="${2:-dotx}"
    RIGHT_DIR="$EXTRA_REPO"
    P3NAME="${3:-$(basename "$EXTRA_REPO")}"
fi
WINDOW="$BASE"
TAKEOVER=0

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# lab-lib.sh sits beside this script once installed; in the repo the tmux and
# script helpers are kept apart, and the private tmux scripts a level further.
for d in "$SCRIPT_DIR" "$SCRIPT_DIR/../scripts" "$SCRIPT_DIR/../public/scripts"; do
    [ -f "$d/lab-lib.sh" ] && { source "$d/lab-lib.sh"; break; }
done
# A miss is otherwise silent: every lab_* call expands to nothing and the caller
# degrades instead of stopping — a pane with no Claude, a recipe on the host.
declare -F lab_resolve >/dev/null || { echo "workspace-dotfiles.sh: cannot find lab-lib.sh" >&2; exit 1; }

if [[ -n "$TMUX" ]]; then
    # Disambiguate window name: $BASE → ${BASE}2 → ${BASE}3 ...
    while tmux list-windows -F '#{window_name}' | grep -qx "$WINDOW"; do
        NUM="${WINDOW#"$BASE"}"
        NUM="${NUM:-1}"
        WINDOW="$BASE$((NUM + 1))"
    done

    pane_count=$(tmux list-panes -F x | wc -l)
    if [[ $pane_count -eq 1 ]]; then
        TAKEOVER=1
        tmux rename-window "$WINDOW"
        W=$(tmux display-message -p '#{session_name}:#{window_index}')
    else
        W=$(tmux new-window -n "$WINDOW" -c "$DIR" -P -F '#{session_name}:#{window_index}')
    fi
else
    if tmux has-session -t "$WINDOW" 2>/dev/null; then
        exec tmux attach-session -t "$WINDOW"
    fi
    tmux new-session -d -s "$WINDOW" -c "$DIR"
    tmux rename-window -t "${WINDOW}:1" "$WINDOW"
    W="${WINDOW}:${WINDOW}"
fi

tmux setw -t "$W" automatic-rename off

# Lay out three panes and capture each pane_id before adding the sync strip.
P1=$(tmux display-message -t "$W.1" -p '#{pane_id}')
P2=$(tmux split-window -h -t "$P1" -c "$RIGHT_DIR" -P -F '#{pane_id}')
P3=$(tmux split-window -v -t "$P2" -c "$RIGHT_DIR" -P -F '#{pane_id}')

tmux set-option -pt "$P1" @split-dir down
tmux set-option -pt "$P2" @split-dir up
tmux set-option -pt "$P3" @split-dir down
tmux set-option -pt "$P1" @unclosable 1
tmux set-option -pt "$P2" @unclosable 1
tmux set-option -pt "$P3" @unclosable 1

# A dispatch pane ABOVE pane 1 (-b = before target for -v = vertical split),
# running sync: it closes itself once everything is up to date and holds
# otherwise, so the user can see what wasn't. The side is passed rather than
# derived — pane 1 is tagged @split-dir down for the recipes that anchor on it,
# and this one belongs above. Created before send-keys so claude in pane 1
# starts at its final height.
pane_dispatch "$P1" "sync.sh" "" -b

# Pin the vertical divider to floor(width/2). A bare `split-window -h` is 50/50
# at creation, but if the client width changed between creation and now (e.g. an
# even→odd resize), tmux's column re-rounding can leave claude's pane 1 col wider
# than a centered split, sitting the divider off-center. Forcing the width here
# pins the divider to the exact center. Before send-keys so claude reads final size.
WCOLS=$(tmux display-message -t "$P1" -p '#{window_width}')
tmux resize-pane -t "$P1" -x $((WCOLS / 2))

if [[ $TAKEOVER -eq 1 ]]; then
    # Script is running in pane 1 — queue cd + claude for after it exits
    tmux send-keys -t "$P1" "cd $DIR && $(lab_claude_cmd dotfiles)" Enter
else
    tmux send-keys -t "$P1" "$(lab_claude_cmd dotfiles)" Enter
fi

# Guarded on the tasks repo: a clone without it keeps a plain shell here.
# --with is unconditional: in extra-repo mode this pane is parked in that repo
# and the dotfiles queue would otherwise be invisible, and outside it the
# second column is the same project and collapses away.
if [[ -d ~/repos/tasks ]]; then
    tmux send-keys -t "$P2" "task-watch.sh --with dotfiles" Enter
fi

# Extra-repo mode: bottom-right pane runs claude in the given repo.
if [[ -n "$EXTRA_REPO" ]]; then
    tmux send-keys -t "$P3" "$(lab_claude_cmd "$P3NAME")" Enter
fi

tmux select-pane -t "$P1"

if [[ -z "$TMUX" ]]; then
    exec tmux attach-session -t "$WINDOW"
fi

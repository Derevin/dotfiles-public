#!/usr/bin/env bash
# Dotfiles workspace: claude on left, two terminals on right, sync strip on top.
#
# Optional args: <extra-repo-path> [window-name]. When given, the bottom-right
# pane opens in that repo with its own claude instead of a plain dotfiles
# terminal, and the window is named <window-name> (default "dotx"). A private
# recipe supplies the extra repo path.
#
# Pane references are by pane_id (the stable %N) rather than index, because
# tmux re-numbers pane indices by spatial position when panes are added or
# removed — adding the sync strip above pane 1 reshuffles everything otherwise.
DIR=~/repos/dotfiles
EXTRA_REPO="${1:-}"

BASE="dotfiles"
P3DIR="$DIR"
if [[ -n "$EXTRA_REPO" ]]; then
    BASE="${2:-dotx}"
    P3DIR="$EXTRA_REPO"
fi
WINDOW="$BASE"
TAKEOVER=0

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
P2=$(tmux split-window -h -t "$P1" -c "$DIR" -P -F '#{pane_id}')
P3=$(tmux split-window -v -t "$P2" -c "$P3DIR" -P -F '#{pane_id}')

tmux set-option -pt "$P1" @split-dir down
tmux set-option -pt "$P2" @split-dir up
tmux set-option -pt "$P3" @split-dir down
tmux set-option -pt "$P1" @unclosable 1
tmux set-option -pt "$P2" @unclosable 1
tmux set-option -pt "$P3" @unclosable 1

# Sync strip ABOVE pane 1 (-b = before target for -v = vertical split).
# remain-on-exit=failed: closes on exit 0 (sync clean), stays open otherwise
# so the user can inspect what wasn't up to date. Splitting before send-keys
# so claude in pane 1 starts at its final height.
SYNC_ID=$(tmux split-window -vb -t "$P1" -l 4 -P -F '#{pane_id}' \
    "~/repos/dotfiles/scripts/sync.sh")
tmux set-option -p -t "$SYNC_ID" remain-on-exit failed

# Pin the vertical divider to floor(width/2). A bare `split-window -h` is 50/50
# at creation, but if the client width changed between creation and now (e.g. an
# even→odd resize), tmux's column re-rounding can leave claude's pane 1 col wider
# than a centered split, sitting the divider off-center. Forcing the width here
# pins the divider to the exact center. Before send-keys so claude reads final size.
WCOLS=$(tmux display-message -t "$P1" -p '#{window_width}')
tmux resize-pane -t "$P1" -x $((WCOLS / 2))

if [[ $TAKEOVER -eq 1 ]]; then
    # Script is running in pane 1 — queue cd + claude for after it exits
    tmux send-keys -t "$P1" "cd $DIR && claude --effort max" Enter
else
    tmux send-keys -t "$P1" "claude --effort max" Enter
fi

# Extra-repo mode: bottom-right pane runs claude in the given repo.
if [[ -n "$EXTRA_REPO" ]]; then
    tmux send-keys -t "$P3" "claude --effort max" Enter
fi

tmux select-pane -t "$P1"

if [[ -z "$TMUX" ]]; then
    exec tmux attach-session -t "$WINDOW"
fi

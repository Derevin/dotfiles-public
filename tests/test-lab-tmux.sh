#!/usr/bin/env bash
# Pane-level test of attach and release — the two scripts that take over the pane
# they are invoked from. They are the only ones that respawn the caller's own
# pane, which is the thing that needs a real server to show, so they get a suite
# of their own; the other two suites never start one.
#
# Safety: TMUX_TMPDIR points at a socket dir inside the temp dir and TMUX is
# unset, so every bare `tmux` — here and inside the scripts under test, which
# clear TMUX themselves — reaches a server of ours. Nothing names the default
# socket, and the kill-server at teardown cannot reach it.
#
# Usage: test-lab-tmux.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the pane-level lab test (attach and release against a private tmux server)."
    echo "Usage: test-lab-tmux.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"

command -v tmux >/dev/null || { echo "tmux not installed — skipping"; exit 0; }

export PATH="$SCRIPT_DIR/../scripts:$SCRIPT_DIR/../tmux:$PATH"

TMP=$(mktemp -d)
cleanup() {
    tmux kill-server >/dev/null 2>&1
    rm -rf "$TMP"
}
trap cleanup EXIT

q() { git "$@" >/dev/null 2>&1; }

export TMUX_TMPDIR="$TMP/tmux"
mkdir -p "$TMUX_TMPDIR"
unset TMUX

# Two of the pane assertions below call the library directly rather than through
# a script — the split-empty ordering is the thing under test, not its callers.
# Sourced past the two lines above, so anything it ever runs at source time is
# already pinned to this test's own server.
source "$SCRIPT_DIR/../scripts/pane-lib.sh"

# A home of our own. The panes run `bash -l`, and the real profile prepends
# ~/.local/bin — which holds an installed claude that would shadow the stub and
# start a session for real. No profile to read, no shadowing.
export HOME="$TMP/home"
mkdir -p "$HOME"

mkdir -p "$TMP/bin"
export CLAUDE_STUB_LOG="$TMP/claude.log"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s\n' "${CLAUDE_LABEL:-}" "$*" >> "$CLAUDE_STUB_LOG"
STUB
for stub in docker coder; do
    printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/$stub"
done
chmod +x "$TMP/bin"/*
export PATH="$TMP/bin:$PATH"

git init -q --bare "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/Widget" 2>/dev/null
q -C "$TMP/Widget" config user.email t@t
q -C "$TMP/Widget" config user.name T
echo hi > "$TMP/Widget/README.md"
q -C "$TMP/Widget" add -A
q -C "$TMP/Widget" commit -m init
q -C "$TMP/Widget" branch -M main
q -C "$TMP/Widget" push -u origin main

cat > "$TMP/lab.conf" <<CONF
LAB_WIDGET_CHECKOUT=$TMP/Widget
LAB_WIDGET_CONTAINER_PREFIX=widget-
LAB_WIDGET_PROVISIONER=
CONF
export LAB_CONF="$TMP/lab.conf" LAB_STATE_DIR="$TMP/state"
cd "$TMP/Widget"

# --- fixtures ----------------------------------------------------------------
# A respawned pane, a login shell and the script's own work all race an
# assertion made the instant send-keys returns.
wait_for() {
    local i
    for i in $(seq 1 100); do
        "$@" >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    return 1
}
yn() { if "$@" >/dev/null 2>&1; then echo y; else echo n; fi; }

pane_opt() { tmux show-options -pvt "$1" "$2" 2>/dev/null; }
claude_ran() { grep -q "^$1|" "$CLAUDE_STUB_LOG" 2>/dev/null; }
tagged() { [ "$(pane_opt "$1" @lab)" = "$2" ]; }
untagged() { [ -z "$(pane_opt "$1" @lab)" ]; }
placed() { cut -f3 "$TMP/state/widget.tsv" 2>/dev/null | grep -qx "$1"; }
unplaced() { ! placed "$1"; }

# -a: append after the current window rather than claim an index already taken.
# The name is fixed because the placement row is keyed on it and automatic-rename
# would retitle the window as its command changed — launchpad.sh turns the same
# option off for the same reason.
new_pane() {
    local id
    id=$(tmux new-window -a -t t: -P -F '#{pane_id}' 'bash --norc')
    tmux setw -t "$id" automatic-rename off
    tmux rename-window -t "$id" labs
    printf '%s' "$id"
}

A=$(lab-new.sh host 2>/dev/null)
B=$(lab-new.sh host 2>/dev/null)
C=$(lab-new.sh host 2>/dev/null)

tmux new-session -d -s t -x 80 -y 24 'bash --norc'
tmux set-option -g default-command 'bash --norc'

# --- attach from outside the target pane (the M-j path) ----------------------
# lab-start.sh always passes --pane, so this is the path every recipe takes.
P1=$(new_pane)
tmux set-option -pt "$P1" @quadrant 1
lab-attach.sh --pane "$P1" "$A" >/dev/null 2>&1
wait_for claude_ran "$A"
ok "attach from outside launches claude" "$(yn claude_ran "$A")" y
ok "attach from outside tags the pane" "$(yn tagged "$P1" "$A")" y
ok "attach from outside records the placement" "$(yn placed "$A")" y

# --- attach from inside the target pane (typed by hand) ----------------------
# respawn-pane -k kills the pane's process group, and the script is in it.
P2=$(new_pane)
tmux set-option -pt "$P2" @quadrant 2
tmux send-keys -t "$P2" "lab-attach.sh $B" Enter
wait_for claude_ran "$B"
ok "attach from inside launches claude" "$(yn claude_ran "$B")" y
ok "attach from inside tags the pane" "$(yn tagged "$P2" "$B")" y

# --- a stale JUST_CALLER must not steal a hand-typed attach ------------------
# The M-j keybind sets it globally and nothing clears it, so one is almost
# always left over from whichever pane last opened a popup.
P3=$(new_pane)
tmux set-option -pt "$P3" @quadrant 3
STALE=$(new_pane)
tmux set-environment -g JUST_CALLER "$STALE"
tmux send-keys -t "$P3" "lab-attach.sh $C" Enter
wait_for claude_ran "$C"
ok "hand-typed attach takes over the pane it was typed in" "$(yn tagged "$P3" "$C")" y
ok "hand-typed attach leaves the stale caller alone" "$(yn untagged "$STALE")" y
tmux set-environment -gu JUST_CALLER

# --- a recipe dispatched into a background split ------------------------------
# just.sh runs a `@# background` recipe in an ephemeral split of the caller's
# window, on this same server. The pane to act on is JUST_CALLER, not the split
# the script happens to be running in.
P4=$(new_pane)
tmux set-option -pt "$P4" @quadrant 4
tmux set-environment -g JUST_CALLER "$P4"
D=$(lab-new.sh host 2>/dev/null)
tmux split-window -d -v -t "$P4" "lab-attach.sh $D"
wait_for claude_ran "$D"
ok "dispatched attach takes over the caller, not the split" "$(yn tagged "$P4" "$D")" y
tmux set-environment -gu JUST_CALLER

# --- release from inside the pane --------------------------------------------
tmux send-keys -t "$P2" "lab-release.sh" Enter
# The row is dropped after the untag, so it is the later of the two to wait on.
wait_for unplaced "$B"
ok "release from inside untags the pane" "$(yn untagged "$P2")" y
ok "release from inside drops the placement" "$(yn unplaced "$B")" y
# A launchpad names no backend either, or the quadrant still answers for a lab
# it stopped showing.
ok "release from inside clears the backend" "$(pane_opt "$P2" @backend)" ""

# --- drop reverts a pane still showing the lab --------------------------------
# Otherwise the quadrant keeps a Claude running in a worktree that no longer
# exists, and the pane still claims a lab nothing can resolve.
P5=$(new_pane)
tmux set-option -pt "$P5" @quadrant 5
E=$(lab-new.sh host 2>/dev/null)
lab-attach.sh --pane "$P5" "$E" >/dev/null 2>&1
wait_for claude_ran "$E"
lab-drop.sh "$E" >/dev/null 2>&1
wait_for untagged "$P5"
ok "drop reverts the pane showing the lab" "$(yn untagged "$P5")" y
ok "drop drops the placement" "$(yn unplaced "$E")" y

# --- what a background split leaves behind ------------------------------------
# The split is ephemeral, so a recipe that fails would take its own error
# message off the screen with it. Driving just.sh needs the two commands it
# shells out to: `just`, answering the listing, the --show and the recipe run,
# and `fzf`, picking the recipe FZF_PICK names.
cat > "$TMP/bin/just" <<'STUB'
#!/usr/bin/env bash
GLOBAL=0
for a in "$@"; do [ "$a" = -g ] && GLOBAL=1; done
case "$*" in
    *--dump*) [ "$GLOBAL" = 1 ] && echo '{}'; exit 0 ;;
    *--list*) [ "$GLOBAL" = 1 ] && printf 'boom\nfine\n'; exit 0 ;;
    *--show*) printf '%s:\n    @# background\n' "${@: -1}"; exit 0 ;;
esac
[ "${@: -1}" = boom ] || exit 0
echo "recipe blew up" >&2
exit 3
STUB
printf '#!/usr/bin/env bash\ngrep -m1 -- "$FZF_PICK"\n' > "$TMP/bin/fzf"
chmod +x "$TMP/bin/just" "$TMP/bin/fzf"

split_of() { tmux list-panes -t "$1" -F '#{pane_id}' | grep -vx "$1" | head -1; }
# tmux reads an empty -t as "the active pane", so an assertion handed the id of
# a split that never happened would quietly answer about some other pane — and
# pass. Every question below goes through here first.
is_pane() { [ -n "$1" ] && tmux display-message -pt "$1" -p '#{pane_id}' 2>/dev/null | grep -qx -- "$1"; }
# -S -: the whole history. A dispatch pane is three rows and tmux scrolls one
# off to write the dead-pane banner at the bottom, so the error a two-line
# command printed is already out of the visible screen by the time we look.
pane_shows() { is_pane "$1" && tmux capture-pane -p -S - -t "$1" 2>/dev/null | grep -q -- "$2"; }
alone() { is_pane "$1" && [ "$(tmux list-panes -t "$1" -F x | wc -l)" = 1 ]; }
dead() { is_pane "$1" && [ "$(tmux display-message -pt "$1" -p '#{pane_dead}')" = 1 ]; }
alive() { is_pane "$1" && [ "$(tmux display-message -pt "$1" -p '#{pane_dead}')" = 0 ]; }
tag_cleared() { alive "$1" && [ -z "$(pane_opt "$1" "$2")" ]; }

P6=$(new_pane)
tmux set-environment -g JUST_CALLER "$P6"
FZF_PICK=boom just.sh >/dev/null 2>&1
S6=$(split_of "$P6")
ok "a failed background recipe keeps its split" "$(yn wait_for pane_shows "$S6" 'recipe blew up')" y
ok "the kept split names the exit status" "$(yn wait_for pane_shows "$S6" 'status 3')" y
tmux kill-pane -t "$S6" 2>/dev/null

P7=$(new_pane)
tmux set-environment -g JUST_CALLER "$P7"
FZF_PICK=fine just.sh >/dev/null 2>&1
ok "a background recipe that succeeds closes its split" "$(yn wait_for alone "$P7")" y
tmux set-environment -gu JUST_CALLER

# --- a dispatch pane outlives a command that fails instantly ------------------
# The race the split-empty order closes. Handed straight to split-window, a
# command this fast destroys its own pane before remain-on-exit lands, and the
# error goes with it — there is nothing left to set the option on. Split empty
# and the option is already in force when the command dies.
P8=$(new_pane)
pane_dispatch "$P8" 'echo "instant boom" >&2; exit 3'
D8=$(split_of "$P8")
ok "a dispatch pane outlives an instant failure" "$(yn wait_for dead "$D8")" y
ok "the held pane keeps the error" "$(yn wait_for pane_shows "$D8" 'instant boom')" y
ok "the held pane names the exit status" "$(yn wait_for pane_shows "$D8" 'status 3')" y
tmux kill-pane -t "$D8" 2>/dev/null

# --- a split pane whose lab cannot be entered degrades -----------------------
# Quadrants are @unclosable, so a dead one cannot be cleared with M-w and the
# slot is lost until the window is rebuilt. The pane must stay interactive, keep
# the error above the prompt, and shed the tag — or just.sh goes on routing
# recipes at a lab that is not there.
F=$(lab-new.sh host 2>/dev/null)
rm -rf "$TMP/Widget-$F"

P9=$(new_pane)
pane_split -d "$P9" "lab-shell $F" >/dev/null
S9=$(split_of "$P9")
ok "a pane whose lab will not open says so" "$(yn wait_for pane_shows "$S9" 'no worktree at')" y
ok "a pane whose lab will not open stays alive" "$(yn alive "$S9")" y
ok "a pane whose lab will not open sheds the tag" "$(yn wait_for tag_cleared "$S9" @lab)" y
ok "a pane whose lab will not open sheds the backend" "$(yn tag_cleared "$S9" @backend)" y

# --- the same lab in a dispatch pane holds instead of degrading ---------------
# The other half of the rule above, and the half that carries the cost of being
# wrong: handed an inner command, lab-shell is running in a dispatch pane. A
# shell there would neither run the command nor ever close, so remain-on-exit
# has to be what keeps the error.
PA=$(new_pane)
pane_dispatch "$PA" "lab-shell $F true"
DA=$(split_of "$PA")
ok "a dispatch pane's lab-shell does not degrade" "$(yn wait_for dead "$DA")" y
ok "the held dispatch pane keeps the lab error" "$(yn wait_for pane_shows "$DA" 'no worktree at')" y
tmux kill-pane -t "$DA" 2>/dev/null

report

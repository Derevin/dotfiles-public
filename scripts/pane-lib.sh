#!/usr/bin/env bash
# Shared pane creation for the tmux scripts and bindings. Source, don't execute.
#
# Two kinds of pane, told apart by mechanism rather than by what they run:
#
#   dispatch pane — runs one command and nothing else. Closes itself when the
#     command succeeds, holds when it fails so the error stays readable.
#   split pane — interactive, lives until its shell exits. Never holds: bash
#     exits with the last command's status, so `false` then Ctrl-D would leave
#     a corpse behind every ordinary close.
#
# A dispatch pane is split empty, told to hold, and only then handed its
# command. Handing it to split-window instead is a race a fast failure wins:
# the pane self-destructs before set-option lands, taking the error with it.

# pane_split_before <anchor> — "-b" to open above the anchor, "" for below.
# The anchor's @split-dir tag decides; untagged, a small pane in the upper half
# grows upward so the new pane doesn't land off the bottom of the window.
# Advisory: a caller that owns a fixed layout passes its own side instead.
pane_split_before() {
  local anchor=$1 dir pos ptop pheight wheight
  dir=$(tmux show-options -pvt "$anchor" @split-dir 2>/dev/null)
  if [ "$dir" = up ]; then
    printf '%s' -b
  elif [ "$dir" != down ]; then
    pos=$(tmux display-message -t "$anchor" -p '#{pane_top} #{pane_height} #{window_height}' 2>/dev/null)
    read -r ptop pheight wheight <<< "$pos"
    if [ -n "$wheight" ] && (( ptop < wheight / 2 && pheight <= wheight / 2 )); then
      printf '%s' -b
    fi
  fi
  return 0
}

# pane_split [-h|-v] [-c <dir>] [-l <rows>] [-d] [--caller <pane>]
#            [--lab <lab> --backend <backend>] <anchor> [cmd] [-- <split args>]
# An interactive split of <anchor>; prints the new pane id. Vertical splits pick
# their side with pane_split_before.
#
# Every axis is an option because the call sites agree on none of them: M-= is
# horizontal, the bindings hand the new pane focus while recipe dispatch detaches
# it, and only dispatch wants the pane tagged. Tagging is opt-in for a reason —
# @just_caller is what makes a pane an idle-reuse target for the next recipe, so
# a hand-made split must ask before it becomes a landing spot.
pane_split() {
  local dir_flag=-v start_dir="" rows="" detach="" caller="" lab="" backend=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|-v) dir_flag=$1; shift ;;
      -c) start_dir=$2; shift 2 ;;
      -l) rows=$2; shift 2 ;;
      -d) detach=-d; shift ;;
      --caller) caller=$2; shift 2 ;;
      --lab) lab=$2; shift 2 ;;
      --backend) backend=$2; shift 2 ;;
      *) break ;;
    esac
  done

  local anchor=$1 cmd=""
  shift
  if [ $# -gt 0 ] && [ "$1" != -- ]; then cmd=$1; shift; fi
  [ "${1:-}" = -- ] && shift

  local before=""
  [ "$dir_flag" = -v ] && before=$(pane_split_before "$anchor")

  local args=(split-window "$dir_flag" -P -F '#{pane_id}' -t "$anchor")
  [ -n "$before" ] && args+=("$before")
  [ -n "$detach" ] && args+=("$detach")
  [ -n "$rows" ] && args+=(-l "$rows")
  [ -n "$start_dir" ] && args+=(-c "$start_dir")
  # Caller extras before the command: split-window takes the command last.
  args+=("$@")
  [ -n "$cmd" ] && args+=("$cmd")

  local pane
  pane=$(tmux "${args[@]}") || return 1
  [ -n "$lab" ] && tmux set-option -pt "$pane" @lab "$lab"
  [ -n "$backend" ] && tmux set-option -pt "$pane" @backend "$backend"
  [ -n "$caller" ] && tmux set-option -pt "$pane" @just_caller "$caller"
  printf '%s' "$pane"
}

# pane_dispatch <anchor> <cmd> [rows] [side] [dir] — a dispatch pane at the
# anchor. Three rows by default, and it never resizes: nothing runs after the
# command, so there is nothing left to grow it. No pane id comes back — a pane
# that closes itself is nothing a caller can hold on to.
#
# side is passed, not derived: the pane a window opens above its first quadrant
# sits above one tagged @split-dir down, so asking pane_split_before would flip
# it below and rearrange the layout. A caller with no layout of its own passes
# $(pane_split_before <anchor>).
#
# dir reaches both the split and the respawn — splitting empty separates the
# pane's own start directory from the command's, so it has to be given twice.
pane_dispatch() {
  local anchor=$1 cmd=$2 rows=${3:-3} side=${4:-} dir=${5:-} pane
  local args=(split-window -v -d -P -F '#{pane_id}' -l "$rows" -t "$anchor")
  [ -n "$side" ] && args+=("$side")
  [ -n "$dir" ] && args+=(-c "$dir")
  pane=$(tmux "${args[@]}") || return 1
  pane_into_dispatch "$pane" "$cmd" "$dir"
}

# pane_into_dispatch <pane> <cmd> [dir] — turn an existing pane into a dispatch
# pane. The order is the whole point: hold first, run second.
pane_into_dispatch() {
  local pane=$1 cmd=$2 dir=${3:-}
  tmux set-option -pt "$pane" remain-on-exit failed
  local args=(respawn-pane -k -t "$pane")
  [ -n "$dir" ] && args+=(-c "$dir")
  args+=("$cmd")
  tmux "${args[@]}"
}

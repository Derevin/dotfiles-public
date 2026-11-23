#!/usr/bin/env bash
# Shared caller lookup and saved placements for lab views. Source this file.

if [ "${BASH_SOURCE[0]}" = "$0" ] && [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Define shared caller and placement functions for lab views."
  echo "Usage: source lab-view-lib.sh"
  exit 0
fi

# Installed scripts share a directory. The repository keeps the libraries apart.
lab_view_dir=$(dirname "${BASH_SOURCE[0]}")
for lab_lib_dir in "$lab_view_dir" "$lab_view_dir/../scripts" "$lab_view_dir/../public/scripts"; do
  [ -f "$lab_lib_dir/lab-lib.sh" ] && { source "$lab_lib_dir/lab-lib.sh"; break; }
done
unset lab_view_dir lab_lib_dir
if ! declare -F lab_resolve >/dev/null; then
  echo "lab-view-lib.sh: cannot find lab-lib.sh" >&2
  return 1
fi

LAB_STATE_DIR="${LAB_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/labs}"

lab_just_caller() { tmux show-environment -g JUST_CALLER 2>/dev/null | cut -d= -f2-; }

# Task recipes prefer the popup's caller, with a fallback for direct runs.
lab_recipe_caller() {
  local pane
  pane=$(lab_just_caller) || true
  printf '%s' "${pane:-${TMUX_PANE:-}}"
}

lab_pane_backend() {
  [ -n "$1" ] || return 0
  tmux show-options -pvt "$1" @backend 2>/dev/null || true
}

lab_panes_showing() {
  local pane lab
  command -v tmux >/dev/null 2>&1 || return 0
  while read -r pane lab; do
    [ "$lab" != "$1" ] || printf '%s\n' "$pane"
  done < <(TMUX= tmux list-panes -a -F '#{pane_id} #{@lab}' 2>/dev/null)
}

# lab_caller_pane <self-socket> — which pane a script that takes over a pane
# should act on. Call it after clearing TMUX, passing the socket field TMUX held
# before ($TMUX is "<socket>,<pid>,<session>"), because the answer depends on
# where we were started from and three places disagree about what "here" means:
#
#   the M-j popup       a tmux server of its own, so TMUX_PANE is not a pane of
#                       the server we are about to drive at all → JUST_CALLER.
#   a dispatch split    a `@# background` recipe runs in an ephemeral split of
#                       the caller's window, on this same server. just.sh makes
#                       it with -d, so it is never the active pane → JUST_CALLER.
#   typed by hand       the pane in front of you, which is active. JUST_CALLER is
#                       global and nothing clears it, so it names whichever pane
#                       last opened a popup — stale, and not what you meant.
lab_caller_pane() {
  local self_socket="$1"
  if [ -n "${TMUX_PANE:-}" ] &&
     [ "$self_socket" = "$(tmux display-message -p '#{socket_path}' 2>/dev/null)" ] &&
     [ "$(tmux display-message -t "$TMUX_PANE" -p '#{pane_active}' 2>/dev/null)" = 1 ]; then
    printf '%s' "$TMUX_PANE"
    return 0
  fi
  lab_just_caller
}

# --- quadrant state ---------------------------------------------------------
#
# Rows are (window, quadrant, lab). Existence is never stored — only where a lab
# was last put — so the file can never disagree with reality about what exists.
# Keyed on window NAME because launchpad allocates labs, labs2, …
# deterministically, so two windows of one project do not fight.

lab_state_file() { printf '%s/%s.tsv' "$LAB_STATE_DIR" "$1"; }

# lab_state_put <project> <window> <quadrant> <lab>
lab_state_put() {
  local f; f=$(lab_state_file "$1")
  mkdir -p "$LAB_STATE_DIR"
  [ -f "$f" ] || : > "$f"
  local tmp; tmp=$(mktemp)
  awk -F'\t' -v w="$2" -v q="$3" '!($1 == w && $2 == q)' "$f" > "$tmp"
  printf '%s\t%s\t%s\n' "$2" "$3" "$4" >> "$tmp"
  sort -o "$f" "$tmp"
  rm -f "$tmp"
}

# lab_state_drop <project> <window> <quadrant> — a launchpad is the absence of a
# row, so releasing a quadrant leaves nothing behind.
lab_state_drop() {
  local f; f=$(lab_state_file "$1")
  [ -f "$f" ] || return 0
  local tmp; tmp=$(mktemp)
  awk -F'\t' -v w="$2" -v q="$3" '!($1 == w && $2 == q)' "$f" > "$tmp"
  mv "$tmp" "$f"
}

# lab_state_drop_lab <project> <lab> — forget every quadrant a dropped lab held.
lab_state_drop_lab() {
  local f; f=$(lab_state_file "$1")
  [ -f "$f" ] || return 0
  local tmp; tmp=$(mktemp)
  awk -F'\t' -v l="$2" '$3 != l' "$f" > "$tmp"
  mv "$tmp" "$f"
}

# lab_state_rename <project> <old> <new> — the claim rename, in the state file.
lab_state_rename() {
  local f; f=$(lab_state_file "$1")
  [ -f "$f" ] || return 0
  local tmp; tmp=$(mktemp)
  awk -F'\t' -v OFS='\t' -v o="$2" -v n="$3" '{ if ($3 == o) $3 = n; print }' "$f" > "$tmp"
  mv "$tmp" "$f"
}

# lab_state_rows <project> <window> — the (quadrant, lab) rows of one window.
lab_state_rows() {
  local f; f=$(lab_state_file "$1")
  [ -f "$f" ] || return 0
  awk -F'\t' -v OFS='\t' -v w="$2" '$1 == w { print $2, $3 }' "$f"
}

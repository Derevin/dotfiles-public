#!/usr/bin/env bash
# Shared functions for the lab scripts. Source, don't execute.
#
# A lab is a provisioned place for one piece of work, in one of three backends
# carried by the name's first letter: hlab (host worktree), dlab (docker over a
# worktree), clab (coder workspace). Anonymous labs are <b>lab-tmp<N>; claiming
# one renames it to <b>lab-<id>-<slug>. The name is the path, so every derivation
# below is a pure function of it plus the project's five config keys.

# Pane creation lives next door, in the repo and once installed. The dependency
# runs one way only: pane-lib knows nothing about labs.
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/pane-lib.sh" || true
declare -F pane_split >/dev/null || { echo "lab-lib.sh: cannot find pane-lib.sh beside it" >&2; return 1; }

LAB_CONF="${LAB_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/lab.conf}"
LAB_STATE_DIR="${LAB_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/labs}"

# Coder rejects a workspace name over 32 characters (codersdk NameValid), and
# the workspace is <container-prefix><lab-name>. Truncating the slug on every
# backend rather than only on coder keeps one name per (backend, task).
LAB_NAME_CAP=32

# Single-quote a value for safe embedding in a shell command line.
lab_sq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

# Same, but left bare when nothing in it needs quoting — these strings end up in
# send-keys, where the pane shows the user what it typed.
lab_arg() {
  case "$1" in
    ''|*[!A-Za-z0-9_/.:=-]*) lab_sq "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

# --- config -----------------------------------------------------------------

# lab_conf_load — source lab.conf and set LAB_PROJECTS to the declared projects.
# Idempotent; every entry point calls it.
lab_conf_load() {
  [ -n "${LAB_PROJECTS+x}" ] && return 0
  # shellcheck disable=SC1090
  [ -f "$LAB_CONF" ] && . "$LAB_CONF"
  LAB_PROJECTS=""
  local v
  for v in $(compgen -v LAB_ 2>/dev/null); do
    case "$v" in
      LAB_*_CHECKOUT) v=${v#LAB_}; LAB_PROJECTS+="${v%_CHECKOUT} " ;;
    esac
  done
  LAB_PROJECTS=${LAB_PROJECTS% }
}

# lab_conf_key <PROJECT_KEY> <SUFFIX> — print one config value ("" if unset).
lab_conf_key() {
  local var="LAB_${1}_${2}"
  printf '%s' "${!var:-}"
}

# lab_project_key <project> — the config-key spelling of a project name:
# uppercased with non-alphanumerics mapped to _, since find-project.sh output is
# not guaranteed to be a shell identifier.
lab_project_key() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_'
}

# --- name derivation --------------------------------------------------------

# lab_backend <name> — host | docker | coder, from the name's first letter.
# Also accepts a bare backend word, so callers can pass either.
lab_backend() {
  case "$1" in
    host|docker|coder) printf '%s' "$1"; return 0 ;;
  esac
  case "${1:0:1}" in
    h) printf 'host' ;;
    d) printf 'docker' ;;
    c) printf 'coder' ;;
    *) return 1 ;;
  esac
}

# lab_backend_letter <backend> — the h/d/c letter for a backend word.
lab_backend_letter() {
  case "$1" in
    host) printf 'h' ;;
    docker) printf 'd' ;;
    coder) printf 'c' ;;
    *) return 1 ;;
  esac
}

# lab_head <name> — the worker stamp and Claude label: <b>lab-<id> for a claimed
# lab, the whole name for an anonymous one. Legacy fixtures are already heads.
lab_head() {
  local name=$1
  if [[ "$name" =~ ^([hdc]lab-[0-9]{3})- ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$name"
  fi
}

# lab_is_lab <name> — true for a name this tooling creates, false for a legacy
# fixture (dwt1, hwt4, cwt2), which carries no task and so cannot be claimed.
lab_is_lab() { [[ "$1" =~ ^[hdc]lab-(tmp[0-9]+|[0-9]{3}-.+)$ ]]; }

# lab_is_anonymous <name> — true for <b>lab-tmp<N>.
lab_is_anonymous() { [[ "$1" =~ ^[hdc]lab-tmp[0-9]+$ ]]; }

# lab_task_id <name> — the 3-digit task id of a claimed lab, empty otherwise.
lab_task_id() {
  [[ "$1" =~ ^[hdc]lab-([0-9]{3})- ]] && printf '%s' "${BASH_REMATCH[1]}"
}

# lab_claimed_name <backend> <id> <slug> <container-prefix> — the claimed name,
# slug truncated to what LAB_NAME_CAP leaves after the prefix and the id. Cutting
# mid-word can leave a trailing hyphen, which coder rejects, so strip it.
lab_claimed_name() {
  local letter budget head
  letter=$(lab_backend_letter "$(lab_backend "$1")") || return 1
  head="${letter}lab-${2}"
  budget=$(( LAB_NAME_CAP - ${#4} - ${#head} - 1 ))
  if [ "$budget" -lt 1 ]; then
    printf '%s' "$head"
    return 0
  fi
  local slug="${3:0:$budget}"
  while [[ "$slug" == *- ]]; do slug="${slug%-}"; done
  [ -n "$slug" ] && printf '%s-%s' "$head" "$slug" || printf '%s' "$head"
}

# --- project resolution -----------------------------------------------------

# lab_strip_prefix <container-or-workspace-name> — the lab name inside it. Which
# project's prefix it carries is exactly what a bare container name does not say,
# so every declared prefix is tried.
lab_strip_prefix() {
  local p prefix
  lab_conf_load
  for p in $LAB_PROJECTS; do
    prefix=$(lab_conf_key "$p" CONTAINER_PREFIX)
    [ -n "$prefix" ] || continue
    case "$1" in "$prefix"*) printf '%s' "${1#"$prefix"}"; return 0 ;; esac
  done
  printf '%s' "$1"
}

# lab_current — the lab the caller is standing in, or nothing. The head that
# detect_worker returns is deliberately not the whole name, and the whole name is
# what lab-drop.sh and lab-attach.sh take, so this is the other half.
lab_current() {
  if [ -n "${CODER_WORKSPACE_NAME:-}" ]; then lab_strip_prefix "$CODER_WORKSPACE_NAME"; return 0; fi
  if [ -n "${LAB_NAME:-}" ]; then printf '%s' "$LAB_NAME"; return 0; fi
  # A host lab has no env marker: the worktree dir is the name. Walk up rather
  # than resolving the toplevel, so a symlinked checkout keeps its own spelling.
  local dir=$PWD base
  while [ "$dir" != "/" ]; do
    base=${dir##*/}
    if [[ "$base" =~ -([hdc](lab-(tmp[0-9]+|[0-9]{3}(-.+)?)|wt[0-9]+))$ ]]; then
      printf '%s' "${BASH_REMATCH[1]}"; return 0
    fi
    dir=$(dirname -- "$dir")
  done
  return 1
}

# lab_project_from_cwd — the project of $PWD. A launchpad stands in the
# project's main checkout, so the cwd is the project selector.
lab_project_from_cwd() { find-project.sh 2>/dev/null; }

# lab_resolve <name> — set every derived path for a lab or legacy fixture:
#   LAB_PROJECT LAB_PROJECT_KEY LAB_CHECKOUT LAB_PREFIX LAB_PROVISIONER
#   LAB_BASE_OVERRIDE LAB_DEFAULT_BACKEND LAB_BACKEND LAB_WORKTREE LAB_CONTAINER
#
# LAB_BACKEND is this lab's, read off its name; LAB_DEFAULT_BACKEND is the
# project's, and only the creation paths have any use for it.
#
# The name carries the backend but not the project, so the project comes from
# whichever declared one owns it: a single declared project is unambiguous, else
# the worktree dir or the container settles it (both local checks), and a coder
# lab — which has neither on the host — falls back to the caller's cwd.
lab_resolve() {
  local name=$1 p key checkout prefix
  lab_conf_load
  LAB_BACKEND=$(lab_backend "$name") || { echo "lab: unknown backend for '$name'" >&2; return 1; }

  key="${LAB_PROJECT_OVERRIDE:-}"
  [ -n "$key" ] && key=$(lab_project_key "$key")

  set -- $LAB_PROJECTS
  # One declared project cannot be ambiguous.
  [ -z "$key" ] && [ $# -eq 1 ] && key=$1

  # Local evidence: the worktree dir, then the container. The backend gates both
  # — a coder lab has no worktree, only docker has a container — so nothing asks
  # the docker daemon about a name that could never name a container.
  if [ -z "$key" ]; then
    for p in "$@"; do
      checkout=$(lab_conf_key "$p" CHECKOUT)
      prefix=$(lab_conf_key "$p" CONTAINER_PREFIX)
      if { [ "$LAB_BACKEND" != coder ] && [ -n "$checkout" ] && [ -d "${checkout}-${name}" ]; } ||
         { [ "$LAB_BACKEND" = docker ] && [ -n "$prefix" ] && lab_container_exists "${prefix}${name}"; }; then
        key=$p; break
      fi
    done
  fi

  # The caller's cwd: a launchpad stands in its project's main checkout, so the
  # cwd is the project selector. Only trusted when that project is configured —
  # otherwise this is a shell that happens to be somewhere else.
  if [ -z "$key" ]; then
    local from_cwd
    from_cwd=$(lab_project_from_cwd) || from_cwd=""
    if [ -n "$from_cwd" ]; then
      p=$(lab_project_key "$from_cwd")
      [ -n "$(lab_conf_key "$p" CHECKOUT)" ] && key=$p
    fi
  fi

  # Last resort. A coder lab has no worktree and no container, so when the cwd
  # could not answer either, the workspace list is the only thing left to ask —
  # one round-trip, cached for the process.
  if [ -z "$key" ] && [ "$LAB_BACKEND" = coder ]; then
    for p in "$@"; do
      prefix=$(lab_conf_key "$p" CONTAINER_PREFIX)
      [ -n "$prefix" ] && lab_workspace_exists "${prefix}${name}" && { key=$p; break; }
    done
  fi

  if [ -z "$key" ]; then
    echo "lab: cannot tell which project '$name' belongs to" >&2
    return 1
  fi

  LAB_PROJECT_KEY="$key"
  LAB_CHECKOUT=$(lab_conf_key "$key" CHECKOUT)
  LAB_PREFIX=$(lab_conf_key "$key" CONTAINER_PREFIX)
  LAB_PROVISIONER=$(lab_conf_key "$key" PROVISIONER)
  LAB_BASE_OVERRIDE=$(lab_conf_key "$key" BASE)
  LAB_DEFAULT_BACKEND=$(lab_conf_key "$key" BACKEND)
  if [ -z "$LAB_CHECKOUT" ]; then
    echo "lab: no checkout configured for project '$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')' (see $LAB_CONF)" >&2
    return 1
  fi
  # The project NAME (not the key) indexes ~/repos/tasks and the state file, and
  # the key is lossy — uppercased with separators flattened. Ask find-project.sh
  # in the checkout, which is what task-lib.sh answers with inside the lab. It is
  # a pure function of the checkout, and it forks a bash per call on paths as hot
  # as every pane spawn and every popup keypress, so it is answered once.
  local cached="LAB_PROJECT_CACHE_$key"
  if [ -n "${!cached+x}" ]; then
    LAB_PROJECT="${!cached}"
  else
    LAB_PROJECT=$(cd "$LAB_CHECKOUT" 2>/dev/null && find-project.sh 2>/dev/null) || LAB_PROJECT=""
    [ -n "$LAB_PROJECT" ] || LAB_PROJECT=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
    printf -v "$cached" '%s' "$LAB_PROJECT"
  fi

  LAB_WORKTREE="${LAB_CHECKOUT}-${name}"
  LAB_CONTAINER="${LAB_PREFIX}${name}"
}

# lab_project_paths <project> — the same config lookup keyed by project name
# rather than by lab name, for the scripts that start from a cwd.
lab_project_paths() {
  lab_conf_load
  LAB_PROJECT="$1"
  LAB_PROJECT_KEY=$(lab_project_key "$1")
  LAB_CHECKOUT=$(lab_conf_key "$LAB_PROJECT_KEY" CHECKOUT)
  LAB_PREFIX=$(lab_conf_key "$LAB_PROJECT_KEY" CONTAINER_PREFIX)
  LAB_PROVISIONER=$(lab_conf_key "$LAB_PROJECT_KEY" PROVISIONER)
  LAB_BASE_OVERRIDE=$(lab_conf_key "$LAB_PROJECT_KEY" BASE)
  LAB_DEFAULT_BACKEND=$(lab_conf_key "$LAB_PROJECT_KEY" BACKEND)
  [ -n "$LAB_CHECKOUT" ] || { echo "lab: no checkout configured for project '$1' (see $LAB_CONF)" >&2; return 1; }
}

# lab_backend_fallback [caller-pane] — the backend a creation path takes when
# none is named: the caller pane's lab, else the project's declared default.
# Empty when neither answers — nothing here invents one. Needs the project
# resolved first (LAB_DEFAULT_BACKEND), and TMUX cleared by the caller, since a
# popup's own server knows nothing about the pane it was opened from.
lab_backend_fallback() {
  local pane=${1:-} b=""
  [ -n "$pane" ] && b=$(tmux show-options -pvt "$pane" @backend 2>/dev/null)
  [ -n "$b" ] || b="${LAB_DEFAULT_BACKEND:-}"
  printf '%s' "$b"
}

# --- existence --------------------------------------------------------------

# lab_container_exists <container> / lab_workspaces / lab_workspace_exists
lab_container_exists() { docker container inspect "$1" >/dev/null 2>&1; }
# One round trip, cached for the process — the by-task lookup below reads the
# same list, and a coder call has no timeout to spend twice.
lab_workspaces() {
  [ -n "${LAB_WORKSPACES+x}" ] || LAB_WORKSPACES=$(coder list --output json 2>/dev/null | jq -r '.[].name' 2>/dev/null)
  printf '%s\n' "$LAB_WORKSPACES"
}
lab_workspace_exists() { lab_workspaces | grep -qxF "$1"; }

# lab_exists <name> — existence is always derived, never stored, so it cannot
# disagree with reality.
lab_exists() {
  lab_resolve "$1" || return 1
  case "$LAB_BACKEND" in
    coder) lab_workspace_exists "$LAB_CONTAINER" ;;
    docker) lab_container_exists "$LAB_CONTAINER" ;;
    *) [ -d "$LAB_WORKTREE" ] ;;
  esac
}

# lab_task_lab <backend> <id> — the lab that exists for a (backend, task), found
# by id alone. Needs the project resolved first (LAB_CHECKOUT, LAB_PREFIX).
#
# This is the probe that "one lab per (backend, task)" needs. The id identifies
# a lab and the slug only describes it, so a task retitled between its grooming
# claim and its implementation claim derives a different name for the same lab —
# and a caller that asks lab_exists about that derived name is told no, and mints
# a second lab beside the one holding the work.
#
# Prints the name, or nothing. Returns 2 for more than one and names them on
# stderr: that is the state this exists to prevent, and choosing between them is
# the guess lab_task_find refuses to make in the other direction. Matched against
# what lab_claimed_name emits — <head>-<slug>, or the bare head where the cap
# left no room for a slug.
lab_task_lab() {
  local backend head n hits=()
  backend=$(lab_backend "$1") || return 1
  head="$(lab_backend_letter "$backend")lab-${2}"
  # Every caller resolves the project first, and a checkout is the one key a
  # project cannot leave out — so an empty one is a caller that skipped it, not a
  # configuration. Said out loud, because the callers read this in an assignment
  # under set -e, where a bare non-zero return ends them with nothing printed.
  [ -n "${LAB_CHECKOUT:-}" ] || { echo "lab: lab_task_lab needs the project resolved first" >&2; return 1; }

  # Whichever registry lab_exists would ask for this backend, so the two can
  # never disagree about what exists.
  if [ "$backend" = host ]; then
    local d base="${LAB_CHECKOUT##*/}"
    for d in "$LAB_CHECKOUT-$head" "$LAB_CHECKOUT-$head"-*; do
      [ -d "$d" ] || continue
      n="${d##*/}"
      hits+=("${n#"$base"-}")
    done
  else
    local names
    case "$backend" in
      coder) names=$(lab_workspaces) ;;
      docker) names=$(docker ps -a --format '{{.Names}}' 2>/dev/null) ;;
    esac
    while read -r n; do
      n=${n#"${LAB_PREFIX:-}"}
      case "$n" in "$head"|"$head"-*) hits+=("$n") ;; esac
    done <<< "$names"
  fi

  [ "${#hits[@]}" -gt 0 ] || return 0
  if [ "${#hits[@]}" -gt 1 ]; then
    echo "lab: task $2 has more than one $backend lab:" >&2
    printf '  %s\n' "${hits[@]}" >&2
    return 2
  fi
  printf '%s' "${hits[0]}"
}

# --- git --------------------------------------------------------------------

# lab_base_branch <repo> — the base to create labs off: the project's override,
# else origin/HEAD, else master, else main.
lab_base_branch() {
  local repo=$1 base
  if [ -n "${LAB_BASE_OVERRIDE:-}" ]; then printf '%s' "$LAB_BASE_OVERRIDE"; return 0; fi
  base=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||') || true
  if [ -z "$base" ]; then
    local c
    for c in master main; do
      git -C "$repo" rev-parse --verify "origin/$c" >/dev/null 2>&1 && { base=$c; break; }
    done
  fi
  [ -n "$base" ] || { echo "lab: cannot detect base branch in $repo" >&2; return 1; }
  printf '%s' "$base"
}

# --- claude -----------------------------------------------------------------

# lab_claude_project_dir <path> — where Claude keeps the session state for a cwd.
# It keys on the encoded path, which is why the claim rename has to carry this
# directory along with the worktree.
lab_claude_project_dir() {
  printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g')"
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
  tmux show-environment -g JUST_CALLER 2>/dev/null | cut -d= -f2-
}

# lab_claude_cmd [--no-auto-memory] <label> [claude-arg...] — the one definition
# of how Claude is launched. Every workspace and lab script goes
# through it, so "the normal command plus --continue" means something.
lab_claude_cmd() {
  local prefix="" a out
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-auto-memory) prefix="CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 "; shift ;;
      *) break ;;
    esac
  done
  out="CLAUDE_LABEL=$(lab_arg "$1") ${prefix}claude --effort max"
  shift
  for a in "$@"; do
    [ -n "$a" ] && out+=" $(lab_arg "$a")"
  done
  printf '%s' "$out"
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

# --- tasks ------------------------------------------------------------------

# Through TASKS_ROOT, so relocating the queue moves lab_task_find and the task
# scripts together — two roots that can disagree would let a claim restamp a
# same-numbered task in the other tree.
LAB_TASKS_ROOT="${LAB_TASKS_ROOT:-${TASKS_ROOT:-$HOME/repos/tasks}}"

# lab_task_find <project> <id> [dir...] — the task path for a bare 3-digit id.
# Ids repeat across projects and the letter prefix is priority
# (task-reprioritize.sh rewrites it), so the glob matches on the digits alone.
# More than one hit is an error: nothing here may guess which task a lab is for.
# Exits 1 for "none" and 2 for "ambiguous" — a caller that treats a missing task
# as permission to proceed must not read an unresolved one the same way.
lab_task_find() {
  local project=$1 id=$2 dir f hits=()
  shift 2
  [ $# -gt 0 ] || set -- todo planning planned active
  for dir in "$@"; do
    for f in "$LAB_TASKS_ROOT/$project/$dir/"?"$id"-*.md; do
      [ -e "$f" ] && hits+=("$f")
    done
  done
  if [ "${#hits[@]}" -eq 0 ]; then
    echo "lab: no task $id in $LAB_TASKS_ROOT/$project" >&2; return 1
  fi
  if [ "${#hits[@]}" -gt 1 ]; then
    echo "lab: task id $id is ambiguous:" >&2
    printf '  %s\n' "${hits[@]}" >&2
    return 2
  fi
  printf '%s' "${hits[0]}"
}

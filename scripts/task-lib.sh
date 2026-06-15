#!/usr/bin/env bash
# Shared functions for task management scripts. Source, don't execute.

TASKS_ROOT=~/repos/tasks

# detect_project — sets PROJECT and TASKS_DIR
detect_project() {
  PROJECT=$(find-project.sh) || exit 1
  TASKS_DIR="$TASKS_ROOT/$PROJECT"

  if [[ ! -d "$TASKS_DIR" ]]; then
    echo "error: tasks dir not found: $TASKS_DIR" >&2; exit 1
  fi
}

# detect_worker — sets WORKER
detect_worker() {
  # Worktree backend config (private; absent on public installs → empty default).
  local wt_conf="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/worktree.conf"
  [ -f "$wt_conf" ] && . "$wt_conf"
  # Inside a coder workspace, the cwd is /workspace (no per-worktree symlink) —
  # take the slot from CODER_WORKSPACE_NAME directly. Same idea for docker dwts.
  if [[ -n "${CODER_WORKSPACE_NAME:-}" ]]; then
    WORKER="${CODER_WORKSPACE_NAME#${WT_CONTAINER_PREFIX:-}}"
    return
  fi
  if [[ -n "${DWT_NAME:-}" ]]; then
    WORKER="$DWT_NAME"
    return
  fi

  local toplevel logical_top dirname
  toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "$toplevel" ]]; then
    logical_top=$PWD
    while [[ "$logical_top" != "/" && "$(readlink -f -- "$logical_top" 2>/dev/null)" != "$toplevel" ]]; do
      logical_top=$(dirname -- "$logical_top")
    done
    [[ "$logical_top" == "/" ]] && logical_top=$toplevel
    dirname=$(basename "$logical_top")
  fi

  if [[ "${dirname:-}" =~ -([hdc]wt[0-9]+)$ ]]; then
    WORKER="${BASH_REMATCH[1]}"
  else
    WORKER="main"
  fi
}

# slug_from_filename — extract slug from task filename (strip letter+digits prefix and .md suffix)
slug_from_filename() {
  local name=$1
  name=${name%.md}
  name=${name#[A-Z][0-9][0-9][0-9]-}
  echo "$name"
}

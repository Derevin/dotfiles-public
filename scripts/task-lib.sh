#!/usr/bin/env bash
# Shared functions for task management scripts. Source, don't execute.

TASKS_ROOT="${TASKS_ROOT:-$HOME/repos/tasks}"

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
  # Required, not optional: the name derivations below are lab-lib.sh's. An
  # install that predates it — a docker backend only relinks on `just
  # dwt-refresh` — must say so, because the alternative is a worker stamped
  # from a half-derivation, which is the silent mis-stamp this function ends.
  local lab_lib="$(dirname "${BASH_SOURCE[0]}")/lab-lib.sh"
  if [[ ! -f "$lab_lib" ]]; then
    echo "task-lib: $lab_lib is missing — re-run dotfiles_install.py" >&2
    return 1
  fi
  source "$lab_lib"

  # Inside a coder workspace the cwd is /workspace, with no path to read the
  # name back out of — take it from the workspace name. A docker lab exports
  # LAB_NAME for the same reason.
  local name=""
  if [[ -n "${CODER_WORKSPACE_NAME:-}" ]]; then
    name=$(lab_strip_prefix "$CODER_WORKSPACE_NAME")
  elif [[ -n "${LAB_NAME:-}" ]]; then
    name="$LAB_NAME"
  fi
  if [[ -n "$name" ]]; then
    WORKER=$(lab_head "$name")
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

  # The stamp is the head only — it lands in Worker: lines and in commit
  # subjects, where the slug would be noise.
  if [[ "${dirname:-}" =~ -([hdc]wt[0-9]+)$ ]]; then
    WORKER="${BASH_REMATCH[1]}"
  elif [[ "${dirname:-}" =~ -([hdc]lab-(tmp[0-9]+|[0-9]{3}))(-|$) ]]; then
    WORKER="${BASH_REMATCH[1]}"
  else
    WORKER="main"
  fi
}

# task_filename — the file name, from either form a task is named by: the slash
# commands say `N042-some-slug` and that argument is often handed straight on.
task_filename() {
  echo "${1%.md}.md"
}

# slug_from_filename — extract slug from task filename (strip letter+digits prefix and .md suffix)
slug_from_filename() {
  local name=$1
  name=${name%.md}
  name=${name#[A-Z][0-9][0-9][0-9]-}
  echo "$name"
}

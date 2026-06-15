#!/usr/bin/env bash
# Print the project name for the current git repo.
# A .find-project.conf in $PWD or any ancestor overrides everything; otherwise
# looks up ~/repos/dotfiles/projects.conf, falling back to lowercase basename.
# Worktree suffixes -hwt<N>, -dwt<N>, -cwt<N> are stripped before lookup.

set -euo pipefail

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
  cat <<'EOF'
find-project.sh — print the project name for the current git repo.

Usage:
  find-project.sh

Override: a .find-project.conf in $PWD or any ancestor wins over the
basename/projects.conf guessing (first match walking up from $PWD). Use it
when the checkout path carries no useful name, e.g. a repo mounted at
/workspace in a container. Content: a `project = NAME` line, or a bare name;
'#' comments allowed.
EOF
  exit 0
fi

PROJECTS_CONF=~/repos/dotfiles/projects.conf
OVERRIDE_FILE=.find-project.conf

toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "error: not in a git repo" >&2; exit 1
}

# Override file walks up from $PWD; first match wins. A `project = NAME` line
# takes precedence, else the first non-comment line is used as a bare name.
# An empty/nameless file falls through to the usual guessing below.
dir=$PWD
while [[ "$dir" != "/" ]]; do
  if [[ -f "$dir/$OVERRIDE_FILE" ]]; then
    override_name=$(grep -v '^[[:space:]]*#' "$dir/$OVERRIDE_FILE" \
      | grep -E '^[[:space:]]*project[[:space:]]*=' \
      | head -1 | sed 's/.*=[[:space:]]*//; s/[[:space:]]*$//') || true
    if [[ -z "${override_name:-}" ]]; then
      override_name=$(grep -v '^[[:space:]]*#' "$dir/$OVERRIDE_FILE" \
        | grep -v '^[[:space:]]*$' \
        | head -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//') || true
    fi
    if [[ -n "${override_name:-}" ]]; then
      echo "$override_name"
      exit 0
    fi
    break
  fi
  dir=$(dirname -- "$dir")
done

# Prefer a symlinked ancestor of $PWD when one resolves to $toplevel, so names
# like 'myrepo-hwt4' survive across symlinked checkouts.
logical_top=$PWD
while [[ "$logical_top" != "/" && "$(readlink -f -- "$logical_top" 2>/dev/null)" != "$toplevel" ]]; do
  logical_top=$(dirname -- "$logical_top")
done
[[ "$logical_top" == "/" ]] && logical_top=$toplevel

basename=$(basename "$logical_top")
stripped=${basename%%-hwt[0-9]*}
stripped=${stripped%%-dwt[0-9]*}
stripped=${stripped%%-cwt[0-9]*}

if [[ -f "$PROJECTS_CONF" ]]; then
  project_name=$(grep -v '^#' "$PROJECTS_CONF" \
    | grep "^${stripped} *= *" \
    | head -1 \
    | sed 's/.*= *//') || true
fi

echo "${project_name:-$(echo "$stripped" | tr '[:upper:]' '[:lower:]')}"

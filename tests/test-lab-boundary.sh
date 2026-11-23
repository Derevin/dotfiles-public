#!/usr/bin/env bash
# Keep view dependencies out of the lab core.
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Check that lab core scripts have no tmux dependencies."
    echo "Usage: test-lab-boundary.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"

matches=$(grep -nE '(^|[^[:alnum:]_])(tmux|TMUX|TMUX_PANE|JUST_CALLER|pane-lib\.sh|@lab|@backend|@quadrant|lab-view-lib\.sh|LAB_STATE_DIR|lab_state_[a-z_]+|lab_caller_pane|lab_panes_showing|lab_pane_backend|lab_just_caller|lab_recipe_caller)([^[:alnum:]_]|$)' \
    "$SCRIPT_DIR"/../scripts/lab-*.sh)
rc=$?
ok "lab core stays independent of tmux" "$matches" ""
if [ "$rc" -gt 1 ]; then exit "$rc"; fi
report

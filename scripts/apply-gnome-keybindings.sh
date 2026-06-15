#!/usr/bin/env bash
# Apply GNOME keybinding policy. Source of truth for WM key bindings — dconf is a
# binary DB and can't be symlinked, so the repo declares them here and the
# installer runs this. Idempotent; no-op without GNOME (WSL, headless, other DE).
set -euo pipefail

case "${1:-}" in
  -h|--help)
    echo "Apply GNOME keybinding policy via gsettings. Idempotent; no-op without GNOME."
    echo "Usage: apply-gnome-keybindings.sh"
    exit 0
    ;;
esac

command -v gsettings >/dev/null 2>&1 || exit 0
gsettings list-keys org.gnome.desktop.wm.keybindings >/dev/null 2>&1 || exit 0

wm=org.gnome.desktop.wm.keybindings

# Free Ctrl+Alt+Shift+arrows for tmux fine pane-resize (tmux/.tmux.conf). GNOME
# defaults bind them to move-to-workspace; keep that on Super for left/right,
# drop its Ctrl alias, and unbind up/down (no-ops on horizontal-workspace GNOME).
gsettings set "$wm" move-to-workspace-left  "['<Super><Shift>Page_Up', '<Super><Shift><Alt>Left']"
gsettings set "$wm" move-to-workspace-right "['<Super><Shift>Page_Down', '<Super><Shift><Alt>Right']"
gsettings set "$wm" move-to-workspace-up    "[]"
gsettings set "$wm" move-to-workspace-down  "[]"

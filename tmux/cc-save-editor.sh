#!/usr/bin/env bash
# Save the active pane's editor (micro) before an Alt+w close, so unsaved
# edits aren't lost. No-op for anything else. Uses bare tmux, so it targets the
# server it's invoked from — the main server from cc-close-pane.sh, the popup
# server from the popup's M-w binding.
# Usage: cc-save-editor.sh

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Save the active pane's editor (micro) before it is closed."
    echo "Usage: cc-save-editor.sh"
    exit 0
fi

case "$(tmux display-message -p '#{pane_current_command}')" in
    micro)
        # F9 is bound to SaveAll, so every open tab is written, not just the active one.
        tmux send-keys F9
        ;;
    *)
        exit 0
        ;;
esac

# Let the editor flush to disk before the caller kills the pane.
sleep 0.2

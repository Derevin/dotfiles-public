#!/usr/bin/env bash
# Unit tests for zoom-dir.sh: the arrow it stores in @zoom_dir for the status-bar
# zoom indicator, derived from the active pane's place in the window layout.
#
# Self-contained: no real tmux. A fake tmux on a prepended PATH answers the
# layout query from FAKE_PID/FAKE_LAYOUT and logs the value passed to
# `set-option -w @zoom_dir`, which is what each case asserts.
# Usage: test-zoom-dir.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the zoom-dir.sh unit tests."
    echo "Usage: test-zoom-dir.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
ZD="$SCRIPT_DIR/../tmux/zoom-dir.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"
export CALLS="$TMP/calls"

cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  display-message) printf '%s %s\n' "$FAKE_PID" "$FAKE_LAYOUT" ;;
  set-option)      printf '%s\n' "$4" > "$CALLS" ;;  # -w @zoom_dir <value>
esac
EOF
chmod +x "$BIN/tmux"

# arrow <pane-id> <layout> -> the value zoom-dir.sh stored in @zoom_dir
arrow() {
    FAKE_PID="$1" FAKE_LAYOUT="$2" "$ZD"
    cat "$CALLS"
}

# Four tiles: 2x2. ids 0/3 on top, 1/2 on the bottom.
T='d45b,200x50,0,0[200x24,0,0{99x24,0,0,0,100x24,100,0,3},200x25,0,25{99x25,0,25,1,100x25,100,25,2}]'
ok "top-left tile"     "$(arrow %0 "$T")" "↖"
ok "top-right tile"    "$(arrow %3 "$T")" "↗"
ok "bottom-left tile"  "$(arrow %1 "$T")" "↙"
ok "bottom-right tile" "$(arrow %2 "$T")" "↘"

# Side-by-side: a half-width pane lands in the left/right third, not the centre.
LR='abcd,200x50,0,0{100x50,0,0,0,99x50,100,0,1}'
ok "left of a vertical split"  "$(arrow %0 "$LR")" "←"
ok "right of a vertical split" "$(arrow %1 "$LR")" "→"

# Stacked: full-width halves map to up/down.
TB='abcd,200x50,0,0[200x25,0,0,0,200x24,0,25,1]'
ok "top of a horizontal split"    "$(arrow %0 "$TB")" "↑"
ok "bottom of a horizontal split" "$(arrow %1 "$TB")" "↓"

# No clear direction -> blank, so the status shows a plain Z.
S='abcd,200x50,0,0,0'
ok "sole pane is blank" "$(arrow %0 "$S")" ""
T3='abcd,200x50,0,0{66x50,0,0,0,66x50,67,0,1,65x50,134,0,2}'
ok "middle of three columns is blank" "$(arrow %1 "$T3")" ""

report

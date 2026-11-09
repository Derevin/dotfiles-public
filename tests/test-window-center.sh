#!/usr/bin/env bash
# Unit tests for window-center.sh: the left pad that centres the window list on
# its middle window (odd visible count) or the gap between the two middle ones
# (even). window_center_pad is pure and tested directly; _main is tested through
# a fake tmux on a prepended PATH that answers from FAKE_SEP / FAKE_LABELS.
# Usage: test-window-center.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the window-center.sh unit tests."
    echo "Usage: test-window-center.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
source "$SCRIPT_DIR/../tmux/window-center.sh"   # guard keeps _main from running

# --- window_center_pad: width sep w0 w1 ... -> pad columns (bar width 80) ---
# Centre is width/2 = 40; the clock does not enter the calculation.
# Odd count centres the middle window.
ok "odd 3"            "$(window_center_pad 80 1 9 6 11)" 27
ok "odd 3, sep 0"     "$(window_center_pad 80 0 9 6 11)" 28
ok "single window"    "$(window_center_pad 80 1 5)"      38
# Even count centres the gap between the two middle windows.
ok "even 2"           "$(window_center_pad 80 1 9 6)"    31
ok "even 4"           "$(window_center_pad 80 1 9 6 11 6)" 24
# A hidden window is width 0 but still borders two separators; it drops out of
# the visible count, so 9/0/11 centres on the gap (here, the hidden span).
ok "hidden middle"    "$(window_center_pad 80 1 9 0 11)" 30
ok "hidden -> odd 1"  "$(window_center_pad 80 1 9 0 0)"  36
# Degenerate: nothing to centre, or the list cannot fit -> no pad.
ok "no windows"       "$(window_center_pad 80 1)"        0
ok "all hidden"       "$(window_center_pad 80 1 0 0)"    0
ok "overflow"         "$(window_center_pad 20 1 30 30 30)" 0

# --- _main through a fake tmux ---------------------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"
cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  display-message) printf '%s\n' "$FAKE_SEP" ;;   # window-status-separator
  list-windows)    printf '%s\n' "$FAKE_LABELS" ;;
esac
EOF
chmod +x "$BIN/tmux"

# padlen <separator> <labels> -> number of pad columns _main emits (80-col bar)
padlen() {
    local out
    out=$(FAKE_SEP="$1" FAKE_LABELS="$2" _main 80 x)
    printf '%s' "${#out}"
}

# labels one per line (empty line = hidden window).
ok "_main odd 3"        "$(padlen ' ' ' 1:alpha '$'\n'' 2:bb '$'\n'' 3:ccccccc ')" 27
# #[...] directives carry no width; stripped, the wrapped label measures as bare.
ok "_main strips style" "$(padlen ' ' ' 1:alpha '$'\n'' #[bold]2:bb#[nobold] '$'\n'' 3:ccccccc ')" 27
# A hidden window renders empty; it must still count as a separator-bordered gap.
ok "_main hidden mid"   "$(padlen ' ' ' 1:alpha '$'\n\n'' 3:ccccccc ')" 30

report

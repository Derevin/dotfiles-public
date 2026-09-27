#!/usr/bin/env bash
# Unit test for lab-drop-pick.sh's non-interactive subcommands: the render/header
# pair that fzf reloads, the mode toggle, and resolve — including the coder gate
# that marks a stopped backend held-back without probing it. The fzf front end is
# not exercised here (no server, like the rest of the suite).
#
# Usage: test-lab-drop-pick.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Test lab-drop-pick.sh render/header/toggle/resolve (no fzf)."
    echo "Usage: test-lab-drop-pick.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"

PICK="$SCRIPT_DIR/../scripts/lab-drop-pick.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- render / header: driven purely off the state dir ------------------------
S="$TMP/state"; mkdir -p "$S/v"; echo droppable > "$S/mode"
# name backend project state — the columns lab-list.sh --long emits.
{
    printf 'hlab-238-fix   host    widget  present\n'
    printf 'dlab-239-thing docker  widget  running\n'
    printf 'clab-240-x     coder   widget  stopped\n'
    printf 'hlab-tmp1      host    widget  present\n'
} > "$S/labs"
printf 'ok\n'                                   > "$S/v/hlab-238-fix"
printf 'no\thas uncommitted changes\n'          > "$S/v/dlab-239-thing"
printf 'no\tis attached to a task in active/\n' > "$S/v/hlab-tmp1"
# clab-240-x left unresolved.

ok "render droppable shows only passing labs" \
    "$("$PICK" render "$S" | cut -f1 | tr '\n' ' ')" "hlab-238-fix "
ok "header counts held and unresolved" \
    "$("$PICK" header "$S")" "ctrl-a: show all   |   2 hidden, 1 unresolved"

ok "toggle flips the mode" "$("$PICK" toggle "$S"; cat "$S/mode")" all
ok "render all keeps every lab" \
    "$("$PICK" render "$S" | cut -f1 | tr '\n' ' ')" "hlab-238-fix dlab-239-thing clab-240-x hlab-tmp1 "
ok "render all annotates a held lab" \
    "$("$PICK" render "$S" | awk -F'\t' '$1=="dlab-239-thing"{print $2}')" "(has uncommitted changes)"
ok "render all marks an unresolved lab" \
    "$("$PICK" render "$S" | awk -F'\t' '$1=="clab-240-x"{print $2}')" "(resolving...)"
ok "header all drops the held count" \
    "$("$PICK" header "$S")" "ctrl-a: droppable only   |   1 unresolved"

# --- resolve: coder gate, then the lab-drop.sh --check verdict ---------------
# Stub lab-drop.sh so the verdict is fixed per lab and no real backend is touched.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/lab-drop.sh" <<'STUB'
#!/usr/bin/env bash
lab="${@: -1}"
case "$lab" in
    dirtyhost) echo "has uncommitted changes"; exit 1 ;;
    *)         exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/lab-drop.sh"
export PATH="$TMP/bin:$PATH"

R="$TMP/resolve"; mkdir -p "$R/v"; echo droppable > "$R/mode"
{
    printf 'stopcoder coder widget stopped\n'
    printf 'okcoder   coder widget running\n'
    printf 'okhost    host  widget present\n'
    printf 'dirtyhost host  widget present\n'
} > "$R/labs"

"$PICK" resolve "$R" stopcoder
ok "resolve gates a stopped coder without probing" \
    "$(cat "$R/v/stopcoder")" "$(printf 'no\tbackend stopped, cannot verify')"
"$PICK" resolve "$R" okcoder
ok "resolve probes a running coder" "$(cat "$R/v/okcoder")" ok
"$PICK" resolve "$R" okhost
ok "resolve passes a clean lab" "$(cat "$R/v/okhost")" ok
"$PICK" resolve "$R" dirtyhost
ok "resolve records the refusal reason" \
    "$(cat "$R/v/dirtyhost")" "$(printf 'no\thas uncommitted changes')"

report

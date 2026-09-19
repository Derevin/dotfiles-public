#!/usr/bin/env bash
# Unit test for just.sh's parameter handling: which params it asks about.
#
# A param the recipe gives a default is filled without asking — from the
# chooser's first line where there is one, else the default itself — and ctrl-o
# on the recipe picker is what asks. A param with no default is asked either
# way. The preview names the value that will be passed, so the choice is
# visible before it is made.
#
# Self-contained: stub `just` and `fzf`, so no real recipe is ever listed or
# run. TMUX_TMPDIR points at a socket dir inside the temp dir and TMUX is unset,
# so the JUST_CALLER lookup reaches no server — without that, a dispatch would
# land in whatever pane the real one last stashed.
#
# Usage: test-just-params.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the just.sh parameter-handling test (defaults filled, ctrl-o asks)."
    echo "Usage: test-just-params.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"

TMP=$(mktemp -d)
cleanup() {
    tmux kill-server >/dev/null 2>&1
    rm -rf "$TMP"
}
trap cleanup EXIT

export TMUX_TMPDIR="$TMP/tmux"
mkdir -p "$TMUX_TMPDIR"
unset TMUX

# Two global recipes: one with a required param and a chooser behind its
# defaulted one — the shape every lab recipe has — and one whose default has no
# chooser at all.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/just" <<'STUB'
#!/usr/bin/env bash
GLOBAL=0
for a in "$@"; do [ "$a" = -g ] && GLOBAL=1; done
case "$*" in
    *--dump*)
        [ "$GLOBAL" = 1 ] &&
            echo '{"source":"g","recipes":{
                "lab":{"body":[],"parameters":[{"name":"id","default":null},{"name":"backend","default":""}]},
                "_lab-backend":{"body":[]},
                "solo":{"body":[],"parameters":[{"name":"model","default":"haiku"}]}}}' ||
            echo '{"source":"p","recipes":{}}'
        exit 0 ;;
    *--list*)
        # just renders each recipe's params into the row, and pads to align the
        # descriptions.
        [ "$GLOBAL" = 1 ] && printf '%s\n' \
            "lab id backend=''  # A lab recipe" \
            "solo model='haiku' # A solo recipe"
        exit 0 ;;
    *--show*)
        case "${*: -1}" in
            lab) printf "lab id backend='':\n    @# host_only\n" ;;
            solo) printf "solo model='haiku':\n    @# host_only\n" ;;
        esac
        exit 0 ;;
esac
[ "${*: -1}" = _lab-backend ] && { printf '%s\n' host docker coder; exit 0; }
# Any other private recipe is absent, and absent is what just says loudly.
case "${*: -1}" in _*) echo "error: unknown recipe" >&2; exit 1 ;; esac
# The run. Each argument bracketed: an empty one has to be visible.
printf 'RUN'; printf ' [%s]' "$@"; printf '\n'
STUB
cat > "$TMP/bin/fzf" <<'STUB'
#!/usr/bin/env bash
# The recipe picker is the call carrying --expect, where fzf prints the
# accepting key on a line of its own before the selection. Anything else is a
# chooser, which takes the top entry.
case "$*" in
    *--expect=*) printf '%s\n' "${FZF_KEY:-}"; tee "$FZF_LIST" | grep -m1 -- "$FZF_PICK" ;;
    *) head -1 ;;
esac
STUB
chmod +x "$TMP/bin/just" "$TMP/bin/fzf"

# No caller pane and no server to name one, so just.sh runs the recipe inline
# and the run reaches stdout. The id has no default, so it is typed.
run() {
    PATH="$TMP/bin:$PATH" FZF_KEY="${1:-}" FZF_PICK="${2:-lab}" FZF_LIST="$TMP/listing" \
        bash "$SCRIPT_DIR/../tmux/just.sh" <<< 238
}

out=$(run)
ok "a param with no default is asked" "$(grep -c '^id: ' <<< "$out")" 1
# A chooser leads with the answer it would pick, so taking its first line is
# what keeps the previewed value and the passed one the same value.
ok "a defaulted param takes the chooser's first line" "$(grep -o 'RUN.*' <<< "$out")" \
    "RUN [-g] [lab] [238] [host]"

out=$(run ctrl-o)
ok "ctrl-o still asks" "$(grep -o 'RUN.*' <<< "$out")" "RUN [-g] [lab] [238] [host]"

out=$(run '' solo)
ok "a default with no chooser is passed as written" "$(grep -o 'RUN.*' <<< "$out")" \
    "RUN [-g] [solo] [haiku]"

# The listing is the row that gets read, so the value shows there first. A
# default with no chooser stays as just rendered it — already what is passed.
ok "the row names the value enter passes" \
    "$(grep -c 'lab id backend=host' "$TMP/listing")" 1
ok "a default with no chooser is left alone" \
    "$(grep -c "solo model='haiku'" "$TMP/listing")" 1
# Substituting a value of another width would leave the descriptions ragged.
ok "the descriptions stay in one column" \
    "$(awk '{print index($0, "#")}' "$TMP/listing" | sort -u | wc -l)" 1

# And again in the preview, for the recipe under the cursor.
out=$(PATH="$TMP/bin:$PATH" bash "$SCRIPT_DIR/../tmux/just.sh" --preview global lab)
ok "the preview names what enter passes" "$(grep -o 'enter passes:.*' <<< "$out")" \
    "enter passes: backend=host   (ctrl-o to choose)"
ok "the preview still shows the recipe" "$(grep -c "^lab id backend=''" <<< "$out")" 1

report

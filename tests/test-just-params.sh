#!/usr/bin/env bash
# Unit test for just.sh's parameter handling: which params it asks about.
#
# A param the recipe gives a default is filled with it and never asked; ctrl-o
# on the recipe picker is what asks for those too. A param without one is asked
# either way.
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

# One global recipe with a required param and a defaulted one, and a chooser for
# the defaulted one — the shape every lab recipe has.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/just" <<'STUB'
#!/usr/bin/env bash
GLOBAL=0
for a in "$@"; do [ "$a" = -g ] && GLOBAL=1; done
case "$*" in
    *--dump*)
        [ "$GLOBAL" = 1 ] &&
            echo '{"source":"g","recipes":{"lab":{"body":[]},"_lab-backend":{"body":[]}}}' ||
            echo '{"source":"p","recipes":{}}'
        exit 0 ;;
    *--list*) [ "$GLOBAL" = 1 ] && echo lab; exit 0 ;;
    *--show*) printf "lab id backend='':\n    @# host_only\n"; exit 0 ;;
esac
[ "${*: -1}" = _lab-backend ] && { printf '%s\n' host docker coder; exit 0; }
# The run. Each argument bracketed: an empty one has to be visible.
printf 'RUN'; printf ' [%s]' "$@"; printf '\n'
STUB
cat > "$TMP/bin/fzf" <<'STUB'
#!/usr/bin/env bash
# The recipe picker is the call carrying --expect, where fzf prints the
# accepting key on a line of its own before the selection. Anything else is a
# chooser, which takes the top entry.
case "$*" in
    *--expect=*) printf '%s\n' "${FZF_KEY:-}"; grep -m1 -- lab ;;
    *) head -1 ;;
esac
STUB
chmod +x "$TMP/bin/just" "$TMP/bin/fzf"

# No caller pane and no server to name one, so just.sh runs the recipe inline
# and the run reaches stdout. The id has no default, so it is typed.
run() { PATH="$TMP/bin:$PATH" FZF_KEY="${1:-}" bash "$SCRIPT_DIR/../tmux/just.sh" <<< 238; }

out=$(run)
ok "a param with no default is asked" "$(grep -c '^id: ' <<< "$out")" 1
ok "a defaulted param is filled, not asked" "$(grep -o 'RUN.*' <<< "$out")" \
    "RUN [-g] [lab] [238] []"

out=$(run ctrl-o)
ok "ctrl-o asks for the defaulted one" "$(grep -o 'RUN.*' <<< "$out")" \
    "RUN [-g] [lab] [238] [host]"

report

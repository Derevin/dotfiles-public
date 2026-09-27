#!/usr/bin/env bash
# Pick a lab to drop. Lists what exists, resolves each through `lab-drop.sh
# --check` in the background, and by default shows only the ones that check
# passes — the labs a real drop would not refuse. ctrl-a toggles to showing
# every lab, each annotated with why it is held back.
#
# The list fills in as checks land: fzf runs with --listen, and each resolver
# pokes it to reload once its verdict is written. Coder is the one backend whose
# state lives out of reach, so a stopped one is marked held-back without a probe
# rather than woken just to answer.
#
# Prints the chosen lab name on stdout, nothing on abort. The internal
# subcommands (render/header/toggle/spawn/resolve) are how fzf and the resolvers
# call back in; they are not meant for direct use.
#
# Usage: lab-drop-pick.sh
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Pick a droppable lab (ctrl-a shows all); prints the chosen name."
    echo "Usage: lab-drop-pick.sh"
    exit 0
fi

SELF=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")

# A verdict file holds `ok`, or `no<TAB>reason`; its absence means not yet
# resolved. render and header read the same three states.
verdict_of() { [ -f "$1" ] && cut -f1 "$1" || echo pending; }

case "${1:-}" in
render)
    STATE=$2
    mode=$(cat "$STATE/mode" 2>/dev/null || echo droppable)
    while read -r name _; do
        [ -n "$name" ] || continue
        vf="$STATE/v/$name"
        verdict=$(verdict_of "$vf")
        if [ "$mode" = all ]; then
            case "$verdict" in
                ok)      note="" ;;
                pending) note="(resolving...)" ;;
                *)       note="($(cut -f2- "$vf"))" ;;
            esac
            printf '%s\t%s\n' "$name" "$note"
        elif [ "$verdict" = ok ]; then
            printf '%s\t\n' "$name"
        fi
    done < "$STATE/labs"
    ;;

header)
    STATE=$2
    mode=$(cat "$STATE/mode" 2>/dev/null || echo droppable)
    pending=0; held=0
    while read -r name _; do
        [ -n "$name" ] || continue
        vf="$STATE/v/$name"
        if [ ! -f "$vf" ]; then
            pending=$((pending + 1))
        elif [ "$(verdict_of "$vf")" = no ]; then
            held=$((held + 1))
        fi
    done < "$STATE/labs"
    if [ "$mode" = all ]; then
        printf 'ctrl-a: droppable only   |   %d unresolved\n' "$pending"
    else
        printf 'ctrl-a: show all   |   %d hidden, %d unresolved\n' "$held" "$pending"
    fi
    ;;

toggle)
    STATE=$2
    if [ "$(cat "$STATE/mode" 2>/dev/null || echo droppable)" = droppable ]; then
        echo all > "$STATE/mode"
    else
        echo droppable > "$STATE/mode"
    fi
    ;;

resolve)
    STATE=$2; lab=$3
    vf="$STATE/v/$lab"
    read -r backend state < <(awk -v n="$lab" '$1 == n { print $2, $4 }' "$STATE/labs") || true
    if [ "$backend" = coder ] && [ "$state" != running ]; then
        printf 'no\tbackend stopped, cannot verify\n' > "$vf.tmp"
    elif reason=$(timeout 20 lab-drop.sh --check "$lab" 2>/dev/null); then
        printf 'ok\n' > "$vf.tmp"
    else
        rc=$?
        [ "$rc" -eq 124 ] && reason="check timed out"
        [ -n "$reason" ] || reason="cannot verify"
        printf 'no\t%s\n' "$reason" > "$vf.tmp"
    fi
    mv "$vf.tmp" "$vf"   # atomic: a concurrent render never sees a half-written verdict
    if [ -n "${FZF_PORT:-}" ]; then
        curl -s -XPOST "localhost:$FZF_PORT" \
            -d "reload($SELF render $STATE)+transform-header($SELF header $STATE)" \
            >/dev/null 2>&1 || true
    fi
    ;;

spawn)
    STATE=$2
    while read -r name _; do
        [ -n "$name" ] || continue
        "$SELF" resolve "$STATE" "$name" &
    done < "$STATE/labs"
    wait
    ;;

"")
    STATE=$(mktemp -d "${TMPDIR:-/tmp}/lab-drop-pick.XXXXXX")
    trap 'rm -rf "$STATE"' EXIT
    mkdir -p "$STATE/v"
    echo droppable > "$STATE/mode"
    lab-list.sh --long > "$STATE/labs" 2>/dev/null || true
    if [ ! -s "$STATE/labs" ]; then
        echo "lab-drop-pick: no labs to drop" >&2
        exit 0
    fi

    # Resolvers are launched from fzf's start binding, not here: only a child of a
    # fzf action inherits $FZF_PORT, which is how they poke the reload back.
    sel=$("$SELF" render "$STATE" | fzf \
        --prompt 'drop lab> ' \
        --header-first \
        --listen \
        --bind "start:transform-header($SELF header $STATE)+execute-silent(setsid $SELF spawn $STATE >/dev/null 2>&1 &)" \
        --bind "ctrl-a:execute-silent($SELF toggle $STATE)+reload($SELF render $STATE)+transform-header($SELF header $STATE)" \
    ) || sel=""
    name=$(printf '%s' "$sel" | cut -f1)
    # Abort (empty selection) is not an error: exit 0 so the caller reads it off
    # the empty stdout, not the status.
    if [ -n "$name" ]; then printf '%s\n' "$name"; fi
    ;;

*)
    echo "lab-drop-pick: unknown subcommand '$1'" >&2
    exit 2
    ;;
esac

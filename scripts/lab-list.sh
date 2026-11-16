#!/usr/bin/env bash
# List the labs that exist, one name per line.
#
# Derived from the filesystem, docker and coder every time — existence is never
# stored, so this can never disagree with reality. Includes the legacy numbered
# fixtures (dwt1, hwt3, cwt2), which can be attached to from a launchpad but
# never claimed.
#
# Usage: lab-list.sh [--long]
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "List existing labs (and legacy fixtures), one name per line."
    echo "Usage: lab-list.sh [--long]"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-lib.sh"

LONG=0
[ "${1:-}" = "--long" ] && LONG=1

lab_conf_load

# A name this tooling knows: a lab, or one of the numbered fixtures. The lab half
# is lab-lib.sh's to define — a second copy here would silently stop listing real
# labs the day the grammar widens.
known() { lab_is_lab "$1" || [[ "$1" =~ ^[hdc]wt[0-9]+$ ]]; }

names=""
# scan <checkout> <prefix> — the labs beside a checkout and under a prefix.
scan() {
    local checkout=$1 prefix=$2 d n c w
    if [ -n "$checkout" ]; then
        for d in "$checkout"-*; do
            [ -d "$d" ] || continue
            n="${d##*/}"; n="${n#"${checkout##*/}"-}"
            known "$n" && names+="$n"$'\n'
        done
    fi
    if [ -n "$prefix" ]; then
        while read -r c; do
            n="${c#"$prefix"}"
            known "$n" && names+="$n"$'\n'
        done < <(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -F "$prefix" || true)
        while read -r w; do
            [ -n "$w" ] || continue
            n="${w#"$prefix"}"
            known "$n" && names+="$n"$'\n'
        done < <(coder list --output json 2>/dev/null | jq -r '.[].name' 2>/dev/null | grep -F "$prefix" || true)
    fi
    return 0
}

for key in $LAB_PROJECTS; do
    scan "$(lab_conf_key "$key" CHECKOUT)" "$(lab_conf_key "$key" CONTAINER_PREFIX)"
done

# An undeclared repo has host labs only, beside its main checkout, and nothing
# but a cwd inside the repo can say where that is.
if here=$(lab_project_from_cwd); then
    key=$(lab_project_key "$here")
    if [ -z "$(lab_conf_key "$key" CHECKOUT)" ] && checkout=$(lab_cwd_checkout "$key" "$here"); then
        scan "$checkout" ""
    fi
fi

names=$(printf '%s' "$names" | sort -u)
[ -n "$names" ] || exit 0

if [ "$LONG" -eq 0 ]; then
    printf '%s\n' "$names"
    exit 0
fi

# --long adds what the name alone does not say: which project owns it, and
# whether the backend is up right now. One coder round trip for the whole table,
# not one per row.
CODER_JSON=""
CODER_ASKED=0

while read -r n; do
    [ -n "$n" ] || continue
    lab_resolve "$n" >/dev/null 2>&1 || { printf '%s\t?\t?\t?\n' "$n"; continue; }
    case "$LAB_BACKEND" in
        docker)
            state=$(docker container inspect -f '{{.State.Status}}' "$LAB_CONTAINER" 2>/dev/null || echo "-") ;;
        coder)
            if [ "$CODER_ASKED" -eq 0 ]; then
                CODER_ASKED=1
                CODER_JSON=$(coder list --output json 2>/dev/null) || CODER_JSON=""
            fi
            state=$(printf '%s' "$CODER_JSON" \
                | jq -r --arg n "$LAB_CONTAINER" '.[] | select(.name == $n) | .latest_build.status' 2>/dev/null)
            state="${state:--}" ;;
        *)
            state=$([ -d "$LAB_WORKTREE" ] && echo present || echo "-") ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$n" "$LAB_BACKEND" "$LAB_PROJECT" "$state"
done <<< "$names" | column -t -s $'\t'

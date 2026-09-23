#!/usr/bin/env bash
# Update Claude ahead of the panes: host first, then every running lab, all on
# channel `latest`. The in-session autoupdater is disabled fleet-wide
# (DISABLE_AUTOUPDATER in claude/settings.json); this is what refreshes Claude
# instead, run by sync as a pre-flight so you sit down to a current build.
#
# The host is updated locally and its success touches a marker; the workspace
# opener's Claude launches block on that marker (--wait-host) so the morning
# Claude is the fresh one, without waiting for the slower lab updates.
#
# Labs are enumerated from `lab-list.sh --long` and updated through `lab-run`,
# both called by bare name (they live on PATH) so a test can shadow them. One
# update per install location: the host once; one running container per docker
# project (a project's labs share one volume); each running coder workspace.
#
# Usage: claude-update.sh [--wait-host <epoch>]
set -euo pipefail

MARKER="${XDG_RUNTIME_DIR:-/tmp}/claude-update-host.done"

if [[ "${1:-}" == "--help" ]]; then
    echo "Update Claude on the host and every running lab (channel latest)."
    echo "Usage: claude-update.sh [--wait-host <epoch>]"
    exit 0
fi

# --wait-host <epoch>: block until the host update marker is at least as fresh as
# <epoch>, then exit 0. A stale, absent, or never-touched (failed update) marker
# falls through the timeout and still exits 0 — a broken update must never wedge a
# Claude launch.
if [[ "${1:-}" == "--wait-host" ]]; then
    want="${2:-0}"
    timeout="${CLAUDE_UPDATE_WAIT_TIMEOUT:-120}"
    deadline=$(( $(date +%s) + timeout ))
    while :; do
        if [[ -f "$MARKER" ]]; then
            mtime=$(stat -c %Y "$MARKER" 2>/dev/null || echo 0)
            [[ "$mtime" -ge "$want" ]] && exit 0
        fi
        [[ "$(date +%s)" -ge "$deadline" ]] && exit 0
        sleep 1
    done
fi

failures=()

# --- host first -------------------------------------------------------------
# Done locally, not via lab-run: host labs share this same install, so updating
# the host covers them all. The marker fires here, before the labs fan out, so
# the workspace Claude unblocks early.
if claude install latest >/dev/null 2>&1; then
    touch "$MARKER"
else
    failures+=("host")
fi

# --- enumerate running labs -------------------------------------------------
# lab-list.sh --long columns: name  backend  project  state. The state column
# picks the live rows (docker/coder running, host present); every other value —
# exited, stopped, a transient, a bare '-', or a '?' unresolved row — is skipped,
# not a failure. Host rows need no lab-run (covered above). Docker dedups to one
# running container per project; each coder workspace is its own install.
targets=()
declare -A docker_seen
if command -v lab-list.sh >/dev/null 2>&1; then
    while read -r name backend project state; do
        [[ -n "$name" ]] || continue
        case "$backend" in
            docker)
                [[ "$state" == running ]] || continue
                [[ -n "${docker_seen[$project]:-}" ]] && continue
                docker_seen[$project]=1
                targets+=("$name")
                ;;
            coder)
                [[ "$state" == running ]] || continue
                targets+=("$name")
                ;;
        esac
    done < <(lab-list.sh --long 2>/dev/null)
fi

# --- fan out to the distinct install locations, in parallel -----------------
# The docker dedup guarantees no two jobs write the same volume, so this is safe
# to parallelize. A failure records the target name; the host, if it failed, is
# already in the list.
if [[ ${#targets[@]} -gt 0 ]]; then
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    for lab in "${targets[@]}"; do
        ( lab-run "$lab" -- claude install latest >/dev/null 2>&1 || printf '%s' "$lab" > "$tmpdir/fail.$lab" ) &
    done
    wait
    for f in "$tmpdir"/fail.*; do
        [[ -e "$f" ]] || continue
        failures+=("$(cat "$f")")
    done
fi

# --- report -----------------------------------------------------------------
if [[ ${#failures[@]} -eq 0 ]]; then
    echo "claude update: ✓"
    exit 0
fi
for t in "${failures[@]}"; do
    echo "claude update: $t failed"
done
exit 1

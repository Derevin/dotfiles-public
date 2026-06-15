#!/usr/bin/env bash
# Install a periodic `git fetch` + fast-forward merge as a systemd user timer.
# Useful for keeping a main clone's default branch fresh so worktrees branch
# off recent history.
set -euo pipefail

UNIT_DIR="$HOME/.config/systemd/user"

usage() {
    echo "Install a periodic git-fetch + ff-only-merge systemd user timer for a repo."
    echo "Usage:"
    echo "  install_fetcher.sh <repo-path> [--branch <name>] [--interval <spec>]"
    echo "  install_fetcher.sh --uninstall <repo-path>"
    echo "  install_fetcher.sh --list"
    echo ""
    echo "Defaults: branch = origin/HEAD target, interval = 1h."
}

slug_for() {
    basename "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-' | sed 's/-\+$//;s/^-\+//'
}

do_list() {
    shopt -s nullglob
    local found=0
    for timer in "$UNIT_DIR"/git-fetch-*.timer; do
        found=1
        local name; name=$(basename "$timer" .timer)
        local repo; repo=$(grep -oP '^WorkingDirectory=\K.*' "$UNIT_DIR/$name.service" || echo "?")
        printf '%-40s %s\n' "$name" "$repo"
    done
    [[ $found -eq 1 ]] || echo "no fetchers installed"
}

do_uninstall() {
    local repo; repo=$(realpath -- "$1")
    local slug; slug=$(slug_for "$repo")
    local unit="git-fetch-$slug"
    systemctl --user disable --now "$unit.timer" 2>/dev/null || true
    rm -f "$UNIT_DIR/$unit.service" "$UNIT_DIR/$unit.timer"
    systemctl --user daemon-reload
    echo "uninstalled $unit"
}

do_install() {
    local repo; repo=$(realpath -- "$1"); shift
    local branch=""
    local interval="1h"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --branch) branch="$2"; shift 2;;
            --interval) interval="$2"; shift 2;;
            *) echo "unknown arg: $1" >&2; exit 1;;
        esac
    done

    [[ -d "$repo/.git" || -f "$repo/.git" ]] || { echo "not a git repo: $repo" >&2; exit 1; }

    cd "$repo"
    git remote get-url origin >/dev/null 2>&1 || { echo "no 'origin' remote in $repo" >&2; exit 1; }

    if [[ -z "$branch" ]]; then
        branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)
        [[ -n "$branch" ]] || { echo "couldn't detect default branch; pass --branch <name>" >&2; exit 1; }
    fi

    local slug; slug=$(slug_for "$repo")
    local unit="git-fetch-$slug"
    local ssh_sock="${SSH_AUTH_SOCK:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/keyring/ssh}"

    mkdir -p "$UNIT_DIR"

    cat > "$UNIT_DIR/$unit.service" <<EOF
[Unit]
Description=Fast-forward $repo on $branch to origin/$branch
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$repo
Environment=SSH_AUTH_SOCK=$ssh_sock
ExecStart=-/usr/bin/git fetch origin $branch
ExecStart=/bin/bash -c 'if [ "\$(/usr/bin/git rev-parse --abbrev-ref HEAD)" = "$branch" ]; then exec /usr/bin/git merge --ff-only origin/$branch; fi'
EOF

    cat > "$UNIT_DIR/$unit.timer" <<EOF
[Unit]
Description=Periodic fast-forward of $repo on $branch

[Timer]
OnActiveSec=30s
OnUnitActiveSec=$interval
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now "$unit.timer"

    echo "installed $unit (every $interval; $repo on $branch)"
    systemctl --user list-timers "$unit.timer" --no-pager 2>/dev/null || true
}

if [[ $# -eq 0 ]]; then
    usage; exit 1
fi

case "$1" in
    --help|-h) usage; exit 0;;
    --list) do_list;;
    --uninstall)
        shift
        [[ $# -ge 1 ]] || { echo "usage: install_fetcher.sh --uninstall <repo-path>" >&2; exit 1; }
        do_uninstall "$1"
        ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 1;;
    *) do_install "$@";;
esac

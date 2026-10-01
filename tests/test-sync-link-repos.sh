#!/usr/bin/env bash
# Tests sync.sh's link_repos parser: which repos.conf entries carry a links=
# table — the set whose pull must trigger a reinstall. sync.sh runs its flow on
# load, so we can't source it; instead extract just the function and exercise it
# against fixture confs (it takes conf paths as args for exactly this).
#
# Usage: test-sync-link-repos.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Test sync.sh's link_repos parser against fixture repos.conf files."
    echo "Usage: test-sync-link-repos.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
SYNC="$SCRIPT_DIR/../scripts/sync.sh"

# Pull in just the function definition, not sync's top-level flow.
source <(sed -n '/^link_repos() {/,/^}/p' "$SYNC")

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/a.conf" <<'EOF'
# comment
tasks     core   git@example.com:me/tasks.git
skillpak  extra  git@example.com:me/skillpak.git  links=dotfiles.links
plain     extra  git@example.com:me/plain.git
EOF
cat > "$TMP/b.conf" <<'EOF'
skillpak  extra  git@example.com:me/skillpak.git  links=dotfiles.links
widgets   extra  git@example.com:me/widgets.git   links=links.conf
EOF

# Lists only links= repos, deduped across both confs; core/plain/comment skipped.
out=$(link_repos "$TMP/a.conf" "$TMP/b.conf" | sort | tr '\n' ' ')
ok "links= repos only, deduped" "$out" "skillpak widgets "

# A conf with no links= lines yields nothing.
cat > "$TMP/none.conf" <<'EOF'
tasks    core   git@example.com:me/tasks.git
plain    extra  git@example.com:me/plain.git
EOF
ok "no links= lines -> empty" "$(link_repos "$TMP/none.conf")" ""

# A missing conf is skipped, not an error.
ok "missing conf -> empty" "$(link_repos "$TMP/does-not-exist.conf")" ""

report

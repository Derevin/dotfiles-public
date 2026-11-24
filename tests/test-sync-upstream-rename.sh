#!/usr/bin/env bash
# Tests sync.sh's apply_repo following a renamed default branch: once origin
# renames master → main, a clone still on master must end up on main, tracking
# origin/main, without recreating master on origin. A branch whose upstream was
# merely deleted must be left alone.
#
# Self-contained: each case clones its own bare origin. sync.sh runs its flow on
# load, so only its functions are sourced.
# Usage: test-sync-upstream-rename.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Test sync.sh following a remote default-branch rename."
    echo "Usage: test-sync-upstream-rename.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
SYNC="$SCRIPT_DIR/../scripts/sync.sh"

source <(sed -n '/^apply_repo() {/,/^}/p; /^follow_upstream_rename() {/,/^}/p' "$SYNC")

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
git config --global push.default current
git config --global fetch.prune true
git config --global init.defaultBranch master
export GIT_AUTHOR_NAME=T GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=T GIT_COMMITTER_EMAIL=t@example.com

# setup <case> — a bare origin on master holding one commit, cloned to $CLONE.
setup() {
    local d=$TMP/$1
    ORIGIN=$d/origin.git
    CLONE=$d/clone
    git init -q --bare "$ORIGIN"
    git clone -q "$ORIGIN" "$d/seed" 2>/dev/null
    (cd "$d/seed" && echo a > a && git add a && git commit -qm A && git push -q origin master)
    git clone -q "$ORIGIN" "$CLONE"
}

# rename_origin — what GitHub's branch rename does to the remote.
rename_origin() {
    git --git-dir="$ORIGIN" branch -m master main
}

branch() { git -C "$CLONE" symbolic-ref --short HEAD; }
upstream() { git -C "$CLONE" rev-parse --abbrev-ref '@{u}' 2>/dev/null; }
origin_heads() { git --git-dir="$ORIGIN" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' '; }

# Up to date: local master follows the rename.
setup clean
rename_origin
git -C "$CLONE" fetch -q
out=$(apply_repo "$CLONE")
ok "clean: branch renamed" "$(branch)" "main"
ok "clean: tracks origin/main" "$(upstream)" "origin/main"
ok "clean: reports in sync" "${out##*$'\n'}" "clone: ✓"

# Local commit made before the rename: pushed to main, master not recreated.
setup ahead
(cd "$CLONE" && echo b > b && git add b && git commit -qm B)
rename_origin
git -C "$CLONE" fetch -q
out=$(apply_repo "$CLONE")
ok "ahead: branch renamed" "$(branch)" "main"
ok "ahead: reports pushed" "${out##*$'\n'}" "clone: pushed"
ok "ahead: origin holds main only" "$(origin_heads)" "main "
ok "ahead: commit on origin/main" \
    "$(git --git-dir="$ORIGIN" log -1 --format=%s main)" "B"

# Feature branch whose upstream was deleted (origin's default unchanged): left alone.
setup deleted
(cd "$CLONE" && git checkout -qb feat && git push -qu origin feat 2>/dev/null)
git --git-dir="$ORIGIN" branch -qD feat
git -C "$CLONE" fetch -q
out=$(apply_repo "$CLONE")
ok "deleted: branch kept" "$(branch)" "feat"
ok "deleted: reports no upstream" "$out" "clone: no upstream, skipping"

report

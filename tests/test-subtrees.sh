#!/usr/bin/env bash
# Tests the subtree round trip: sync.sh's apply_subtrees pulling a mirror and
# subtrees-push.sh publishing to it. Publishing copies local commits into the
# mirror, so a pull must take nothing it already holds, merge a commit made in
# the mirror against the last state both sides share, and leave nothing half
# merged on a real conflict; a publish after such a pull must not replay what
# the mirror already has.
#
# Self-contained: each case builds a throwaway superproject with a squash-added
# `lib/` from its own bare mirror, so nothing reaches a real remote. sync.sh runs
# its flow on load, so only its functions are sourced.
# Usage: test-subtrees.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Test the subtree pull (sync.sh) and publish (subtrees-push.sh) round trip."
    echo "Usage: test-subtrees.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
SYNC="$SCRIPT_DIR/../scripts/sync.sh"
PUSH="$SCRIPT_DIR/../scripts/subtrees-push.sh"

source <(sed -n '/^apply_subtrees() {/,/^}/p; /^subtree_ingest() {/,/^}/p' "$SYNC")

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=T GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=T GIT_COMMITTER_EMAIL=t@example.com

# setup <case> — cd into a superproject whose lib/ is subtree-added from a fresh
# mirror holding a seed commit, the way a new mirror starts.
setup() {
    local d=$TMP/$1
    MIRROR=$d/mirror.git
    git init -q --bare "$MIRROR"
    git init -q "$d/seed"
    (cd "$d/seed" && printf 'seed\n' > README.md && printf 'license\n' > LICENSE &&
        git add -A && git commit -qm "Initial commit" && git push -q "$MIRROR" HEAD:refs/heads/main)
    git init -q "$d/super"
    cd "$d/super" || exit 1
    printf 'top\n' > top.txt
    git add -A && git commit -qm "Init"
    git subtree add -q --prefix=lib "$MIRROR" main --squash >/dev/null 2>&1
    printf 'lib %s main\n' "$MIRROR" > .subtrees
    git add -A && git commit -qm "Lib: Register subtree"
}

# edit <file> <line> — a local commit appending <line> to lib/<file>.
edit() {
    printf '%s\n' "$2" >> "lib/$1"
    git add -A && git commit -qm "Lib: $1 $2"
}

# contrib <file> <line> — a commit made in the mirror itself.
contrib() {
    local c=$TMP/contrib.$RANDOM
    git clone -q --branch main "$MIRROR" "$c" 2>/dev/null
    (cd "$c" && printf '%s\n' "$2" >> "$1" && git add -A && git commit -qm "Contrib: $1 $2" &&
        git push -q origin main)
}

publish() { "$PUSH" >/dev/null 2>&1; }

# pull — one sync of the subtrees, the ref refreshed as sync's prefetch does.
# Prints apply_subtrees' line for lib.
pull() {
    git fetch -q "$MIRROR" "+main:refs/sync/lib"
    apply_subtrees "$PWD" | grep '/lib: '
}

mirror_tree() { git --git-dir="$MIRROR" rev-parse 'main^{tree}'; }
dup_subjects() { git --git-dir="$MIRROR" log --no-merges --format=%s main | sort | uniq -d | tr '\n' ' '; }
clean() { [ -z "$(git status --porcelain)" ] && ! git rev-parse -q --verify MERGE_HEAD >/dev/null && echo y; }

# --- Right after the add the mirror is only the seed: nothing to do. -----------
setup fresh
ok "fresh: in sync" "$(pull)" "super/lib: ✓"

# --- Publish, change lib locally, sync: the mirror holds nothing new. ----------
setup roundtrip
edit a.txt one
publish
ok "roundtrip: published" "$(git rev-parse HEAD:lib)" "$(mirror_tree)"
ok "roundtrip: in sync after publish" "$(pull)" "super/lib: ✓"
edit a.txt two
before=$(git rev-parse HEAD)
ok "roundtrip: local change is unpublished" "$(pull)" "super/lib: unpublished (publish via subtrees-push.sh)"
ok "roundtrip: nothing merged" "$(git rev-parse HEAD)" "$before"
ok "roundtrip: tree clean" "$(clean)" y

# --- Publish, someone commits in the mirror, sync: it is merged in. -----------
setup ingest
edit a.txt one
publish
contrib README.md contributed
ok "ingest: ingested" "$(pull)" "super/lib: ingested"
ok "ingest: mirror commit arrived" "$(tail -1 lib/README.md)" contributed
ok "ingest: tree clean" "$(clean)" y
ok "ingest: in sync after" "$(pull)" "super/lib: ✓"

# --- The same with a local change pending, then publish again. ----------------
setup mixed
edit a.txt one
publish
contrib README.md contributed
edit a.txt two
ok "mixed: ingested" "$(pull)" "super/lib: ingested"
ok "mixed: mirror commit arrived" "$(tail -1 lib/README.md)" contributed
ok "mixed: local change kept" "$(tail -1 lib/a.txt)" two
publish
ok "mixed: published after ingest" "$(git rev-parse HEAD:lib)" "$(mirror_tree)"
ok "mixed: no commit published twice" "$(dup_subjects)" ""
contrib README.md again
edit b.txt one
ok "mixed: second ingest" "$(pull)" "super/lib: ingested"
ok "mixed: second mirror commit arrived" "$(tail -1 lib/README.md)" again
publish
ok "mixed: published after second ingest" "$(git rev-parse HEAD:lib)" "$(mirror_tree)"
ok "mixed: still no commit published twice" "$(dup_subjects)" ""

# --- A real conflict is reported, and nothing is left half merged. ------------
setup conflict
edit a.txt one
publish
contrib a.txt theirs
edit a.txt ours
out=$(pull)
case "$out" in *conflict*) out=conflict ;; esac
ok "conflict: reported" "$out" conflict
ok "conflict: tree clean" "$(clean)" y
fails apply_subtrees "$PWD"

# --- A mirror whose history is copies, not the split (as one restarted from a
#     fresh root is): publish still works, and so does a pull after it. -------
setup copies
edit a.txt one
publish
root=$(git commit-tree "HEAD:lib" -m "Restart")
git push -q --force "$MIRROR" "$root:refs/heads/main"
edit c.txt one
publish
ok "copies: published onto the copy" "$(git rev-parse HEAD:lib)" "$(mirror_tree)"
contrib README.md contributed
edit d.txt one
ok "copies: ingested" "$(pull)" "super/lib: ingested"
ok "copies: mirror commit arrived" "$(tail -1 lib/README.md)" contributed
publish
ok "copies: published after ingest" "$(git rev-parse HEAD:lib)" "$(mirror_tree)"
ok "copies: no commit published twice" "$(dup_subjects)" ""

report

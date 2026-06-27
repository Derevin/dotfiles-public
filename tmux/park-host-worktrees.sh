#!/usr/bin/env bash
# Park idle host worktrees + the main checkout onto the latest base branch.
# "Parked" = clean tree with no commits beyond the base tip; those fast-forward
# to latest. Dirty or ahead worktrees are left untouched and reported. The main
# checkout is best-effort (its own state is yours) and never affects the exit
# code; a WORKTREE needing attention exits non-zero so the overview sync strip
# (remain-on-exit=failed) stays open.
set -uo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ -z "${1:-}" ]; then
    echo "Park idle host worktrees + main checkout onto the latest base branch."
    echo "Usage: park-host-worktrees.sh <repo-root> [base-branch=main]"
    exit 0
fi

ROOT="$1"
BASE="${2:-main}"

cd "$ROOT" || { echo "park: cannot cd $ROOT" >&2; exit 2; }

echo "park: fetch origin…"
git fetch --quiet origin 2>/dev/null || echo "  (fetch failed — offline? using local $BASE)"

# Main checkout — best-effort, never affects exit code (your work is yours).
mb=$(git symbolic-ref --quiet --short HEAD || echo "(detached)")
if [ -n "$(git status --porcelain)" ]; then
    echo "  main  [$mb]  dirty — left as is"
elif [ "$mb" != "$BASE" ]; then
    echo "  main  [$mb]  not on $BASE — left as is"
elif git merge --ff-only --quiet "origin/$BASE" 2>/dev/null; then
    echo "  main  [$BASE]  → $(git rev-parse --short HEAD)"
else
    echo "  main  [$BASE]  $(git rev-parse --short HEAD) (no ff from origin/$BASE)"
fi

TARGET=$(git rev-parse "$BASE" 2>/dev/null) || { echo "park: no $BASE branch" >&2; exit 2; }

# A worktree parks iff clean and not ahead of the base tip; () body = subshell so
# the cd doesn't leak across iterations.
park_one() (
    cd "$1" || { echo "  ${1##*/}  cannot enter — skipped"; exit 1; }
    name=${1##*/}
    br=$(git symbolic-ref --quiet --short HEAD || echo "(detached)")
    if [ -n "$(git status --porcelain)" ]; then
        echo "  $name  [$br]  DIRTY — skipped"; exit 1
    fi
    ahead=$(git rev-list --count "$TARGET..HEAD")
    if [ "$ahead" -gt 0 ]; then
        echo "  $name  [$br]  AHEAD $ahead — skipped"; exit 1
    fi
    if git merge --ff-only --quiet "$TARGET" 2>/dev/null; then
        echo "  $name  [$br]  → $(git rev-parse --short HEAD)"; exit 0
    fi
    echo "  $name  [$br]  DIVERGED — skipped"; exit 1
)

rc=0
while read -r wt; do
    [ "$wt" = "$ROOT" ] && continue
    park_one "$wt" || rc=1
done < <(git worktree list --porcelain | awk '/^worktree /{print $2}')

exit "$rc"

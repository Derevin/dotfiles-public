#!/usr/bin/env bash
# Push every subtree listed in .subtrees to its mirror.
# Format: <prefix> <remote> <branch> [flags], one per line. Comments with #.
# Flags steer sync's pull direction only; every listed prefix is pushed.
#
# Instead of `git subtree push` (which re-bloats remote history with
# every dotfiles commit walked by the split), this splits the subtree
# locally, finds the commit whose tree matches the current remote tip,
# and cherry-picks only the new commits onto remote tip. Result:
# fast-forward pushes, remote SHAs preserved across pushes.
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    cat <<'USAGE'
Publish every subtree listed in .subtrees to its public mirror.
Usage: subtrees-push.sh

Run from the superproject root with the work already committed and pushed: the
split walks HEAD, so nothing uncommitted reaches a mirror. Each prefix is split
locally, matched to the remote tip by tree, and the new commits cherry-picked on
top — fast-forward push, remote SHAs preserved. Exits non-zero if a prefix needs
a manual push.

Publishing is deliberate. Run the leak scan from CLAUDE.md first and confirm it
comes back empty; nothing here checks it.
USAGE
    exit 0
fi

if [[ ! -f .subtrees ]]; then
  echo "no .subtrees file, nothing to push"
  exit 0
fi

push_one() {
  local prefix=$1 remote=$2 branch=$3
  local split remote_sha remote_tip remote_tree boundary sha wt

  split=$(git subtree split --prefix="$prefix" HEAD 2>/dev/null)

  remote_sha=$(git ls-remote "$remote" "refs/heads/$branch" | awk '{print $1}')
  if [[ -z "$remote_sha" ]]; then
    echo "  remote branch missing; pushing as new branch"
    git push "$remote" "$split:refs/heads/$branch"
    echo "  pushed"
    return 0
  fi

  git fetch --quiet "$remote" "$branch"
  remote_tip=$(git rev-parse FETCH_HEAD)
  remote_tree=$(git rev-parse "$remote_tip^{tree}")

  boundary=""
  for sha in $(git rev-list "$split"); do
    if [[ "$(git rev-parse "$sha^{tree}")" == "$remote_tree" ]]; then
      boundary=$sha
      break
    fi
  done

  if [[ -z "$boundary" ]]; then
    echo "  no tree-equivalent commit on local split; push manually"
    return 1
  fi

  if [[ "$boundary" == "$split" ]]; then
    echo "  up to date"
    return 0
  fi

  wt=$(mktemp -d -u -t "subtree-push.XXXXXX")
  git worktree add --quiet --detach "$wt" "$remote_tip"
  (
    cd "$wt"
    git cherry-pick --quiet $(git rev-list --reverse "$boundary".."$split")
    git push --quiet "$remote" "HEAD:refs/heads/$branch"
  )
  git worktree remove --force "$wt"
  echo "  pushed"
}

failed=0
while read -r prefix remote branch _; do
  case "$prefix" in '#'*|'') continue ;; esac
  printf "=== subtree: %s ===\n" "$prefix"
  push_one "$prefix" "$remote" "$branch" || failed=1
done < .subtrees

exit "$failed"

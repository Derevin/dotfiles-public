#!/usr/bin/env bash
context_rebase_in_progress() {
    [[ -d "$context_git_dir/rebase-merge" || -d "$context_git_dir/rebase-apply" ]]
}

context_open() {
    if [[ ! -e "$HOME/repos/context/.git" ]]; then
        echo "context store: missing Git checkout at ~/repos/context." >&2
        return 1
    fi
    cd "$HOME/repos/context" || return 1
    context_git_dir=$(git rev-parse --absolute-git-dir) || return 1

    # Both entry points share an index and rebase state across sessions.
    context_lock_dir="$context_git_dir/context-sync.lock"
    if ! mkdir -- "$context_lock_dir"; then
        echo "context store: cannot lock; retry when the other context command finishes." >&2
        return 1
    fi
    trap 'rmdir -- "$context_lock_dir"' EXIT
    trap 'exit 1' HUP INT TERM

    local unmerged
    unmerged=$(git ls-files --unmerged) || return 1
    if context_rebase_in_progress || [[ -n "$unmerged" || -e "$context_git_dir/MERGE_HEAD" \
        || -e "$context_git_dir/CHERRY_PICK_HEAD" || -e "$context_git_dir/REVERT_HEAD" ]]; then
        echo "context store: finish the in-progress Git operation or resolve the conflicts before retrying." >&2
        return 1
    fi
}

context_sync() {
    local upstream stash_before head rebase_failed=0

    if ! git fetch; then
        echo "context-sync: cannot reach remote." >&2
        return 1
    fi
    if ! upstream=$(git rev-parse --verify '@{upstream}'); then
        echo "context-sync: no upstream branch configured." >&2
        return 1
    fi

    # Avoid autostashing other projects' edits when there is nothing to replay onto.
    if ! git merge-base --is-ancestor "$upstream" HEAD; then
        stash_before=$(git rev-parse --verify -q refs/stash || true)
        if ! git rebase --autostash "$upstream"; then
            rebase_failed=1
            if context_rebase_in_progress && ! git rebase --abort; then
                echo "context-sync: could not abort the rebase." >&2
            fi
            echo "context-sync: rebase failed." >&2
        fi
        # A failed autostash apply can leave a stash entry even when rebase exits 0.
        if [[ $(git rev-parse --verify -q refs/stash || true) != "$stash_before" ]]; then
            echo "context-sync: local edits left in stash. See git stash list." >&2
            return 1
        fi
        [[ "$rebase_failed" == 0 ]] || return 1
    fi

    head=$(git rev-parse HEAD) || return 1
    if [[ "$head" != "$upstream" ]] && ! git push; then
        echo "context-sync: push failed. Commits remain local." >&2
        return 1
    fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -euo pipefail
    if [[ ${1:-} == --help ]]; then
        echo "Fetch, rebase, and push the context store. No-op if missing."
        echo "Usage: context-sync.sh"
        exit 0
    fi

    [[ -e "$HOME/repos/context/.git" ]] || exit 0
    context_open
    context_sync
fi

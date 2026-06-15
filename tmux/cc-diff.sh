#!/bin/bash
# Git diff viewer
# Flags: s = side-by-side (default: inline)
#        w = ignore whitespace
#        b = branch diff (merge-base to HEAD) instead of working tree
#        x = exclude **/generated/** paths

side=false
ws=""
branch=false
exclude=false

for arg in "$@"; do
    case "$arg" in
        s) side=true ;;
        d) ;;
        w) ws="-w" ;;
        b) branch=true ;;
        x) exclude=true ;;
    esac
done

pathspec=()
if $exclude; then
    pathspec=(':(exclude)**/generated/**')
fi

untracked() {
    if $exclude; then
        git ls-files --others --exclude-standard -z | grep -zv '/generated/'
    else
        git ls-files --others --exclude-standard -z
    fi
}

if $branch; then
    for candidate in origin/main origin/master main master; do
        if git rev-parse --verify "$candidate" &>/dev/null; then
            base="$candidate"; break
        fi
    done
    merge_base=$(git merge-base HEAD "${base:-origin/main}")
    output=$(git diff -U7 $ws "$merge_base" -- "${pathspec[@]}"; untracked | xargs -0 -r -I{} git diff -U7 $ws --no-index -- /dev/null {} 2>/dev/null; true)
else
    output=$(git diff -U7 $ws HEAD -- "${pathspec[@]}"; untracked | xargs -0 -r -I{} git diff -U7 $ws --no-index -- /dev/null {} 2>/dev/null; true)
fi

if $side; then
    echo "$output" | delta --navigate --width="$(tput cols)" --paging=always
else
    echo "$output" | DELTA_FEATURES=inline delta --navigate --width="$(tput cols)" --paging=always
fi

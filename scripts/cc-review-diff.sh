#!/bin/bash
# Branch diff for Claude review skill.
# Outputs commit log + raw diff (merge-base to HEAD, including untracked files).

if [[ "${1:-}" == "--help" ]]; then
    echo "Branch diff for review: commits + diff merge-base..HEAD (incl. untracked)."
    echo "Usage: cc-review-diff.sh"
    exit 0
fi

for candidate in origin/main origin/master main master; do
    if git rev-parse --verify "$candidate" &>/dev/null; then
        base="$candidate"; break
    fi
done

merge_base=$(git merge-base HEAD "${base:-origin/main}")

echo "=== COMMITS ==="
git log --oneline "$merge_base"..HEAD

echo ""
echo "=== DIFF ==="
git diff -U7 -w "$merge_base" -- ':(exclude)**/generated/**'

# Include untracked files
git ls-files --others --exclude-standard -z | grep -zv '/generated/' |
    xargs -0 -r -I{} git diff -U7 -w --no-index -- /dev/null {} 2>/dev/null

true

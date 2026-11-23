#!/usr/bin/env bash
set -euo pipefail

usage() { echo 'Usage: context-commit.sh [--project NAME] "<message>"'; }

if [[ "${1:-}" == "--help" ]]; then
    echo "Commit one project's context store edits and publish pending commits."
    usage
    exit 0
fi

if [[ ${1:-} == --project ]]; then
    [[ $# == 3 ]] || { usage >&2; exit 1; }
    project=$2
    shift 2
else
    [[ $# == 1 ]] || { usage >&2; exit 1; }
    project=$(find-project.sh)
fi

case "$project" in
    ''|.|..|.[gG][iI][tT]|*/*|*\\*)
        echo "context-commit: project must name a single directory in the context store." >&2
        exit 1
        ;;
esac

source "$(dirname -- "${BASH_SOURCE[0]}")/context-sync.sh"
context_open

if [[ ! -d $project && -z $(git --literal-pathspecs ls-files -- "$project/") ]]; then
    echo "context-commit: project '$project' has no directory in the context store." >&2
    exit 1
fi

changes=$(git --literal-pathspecs status --porcelain --untracked-files=all -- "$project/")
if [[ -n "$changes" ]]; then
    git --literal-pathspecs add -A -- "$project/"
    staged=$(git --literal-pathspecs diff --cached --name-only -- "$project/")
    if [[ -n "$staged" ]]; then
        git --literal-pathspecs commit --only -m "$1" -- "$project/"
    fi
fi

if ! context_sync; then
    echo "context-commit: pending commits are local. Rerun context-commit.sh to retry." >&2
    exit 1
fi

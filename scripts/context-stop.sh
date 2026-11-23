#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help ]]; then
    echo "Track context store edits and check them when Claude stops."
    echo "Usage: context-stop.sh < hook-input.json"
    exit 0
fi

payload=$(cat)
session=$(jq -r '.session_id // empty' <<< "$payload")
[[ $session =~ ^[[:alnum:]_-]+$ ]] || exit 0

store="$HOME/repos/context"
state="${XDG_STATE_HOME:-$HOME/.local/state}/context-edits"

record_edit() {
    local path cwd relative tmp
    [[ -e "$store/.git" ]] || return 0
    path=$(jq -r 'select(.tool_name == "Edit" or .tool_name == "Write") | .tool_input.file_path // empty' <<< "$payload")
    [[ -n "$path" ]] || return 0

    if [[ $OSTYPE == msys* ]]; then
        path=$(cygpath -u -- "$path")
    fi
    if [[ $path != /* ]]; then
        cwd=$(jq -r '.cwd // empty' <<< "$payload")
        [[ -n "$cwd" ]] || return 0
        path="$cwd/$path"
    fi
    store=$(realpath -m -- "$store")
    path=$(realpath -m -- "$path")
    [[ $path == "$store/"* ]] || return 0
    relative=${path#"$store/"}
    [[ $relative == */* && $relative != .[gG][iI][tT]/* ]] || return 0

    # Each write gets its own record so Stop can prune while a fork records edits.
    umask 077
    mkdir -p -- "$state"
    tmp=$(mktemp "$state/.edit.XXXXXXXXXXXX")
    printf '%s\0' "$relative" > "$tmp"
    mv -- "$tmp" "$state/$session.edit.${tmp##*.}"
}

path_published() {
    local changes
    changes=$(GIT_OPTIONAL_LOCKS=0 git --literal-pathspecs status --porcelain --untracked-files=all -- "$1" 2>/dev/null) || return 1
    [[ -z "$changes" ]] || return 1
    changes=$(git --literal-pathspecs diff --name-only '@{u}..HEAD' -- "$1" 2>/dev/null) || return 1
    [[ -z "$changes" ]]
}

check_edits() {
    local record path project reason command git_dir settled=0
    local -A pending=() verdict=()
    shopt -s nullglob
    local records=("$state/$session".edit.*)
    [[ ${#records[@]} -gt 0 ]] || return 0

    if [[ ! -e "$store/.git" ]]; then
        rm -f -- "${records[@]}"
        return 0
    fi
    # Mid-rebase, an autostashed draft looks published; keep every record until the other command finishes.
    if cd "$store" && git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) \
        && [[ ! -e $git_dir/context-sync.lock && ! -d $git_dir/rebase-merge && ! -d $git_dir/rebase-apply ]]; then
        settled=1
    fi
    for record in "${records[@]}"; do
        IFS= read -r -d '' path < "$record" || continue
        if [[ $settled == 1 && -z ${verdict[$path]+set} ]]; then
            path_published "$path" && verdict[$path]=1 || verdict[$path]=0
        fi
        if [[ ${verdict[$path]:-0} == 1 ]]; then
            rm -f -- "$record"
        else
            pending[${path%%/*}]=1
        fi
    done
    [[ ${#pending[@]} -gt 0 ]] || return 0

    reason='Context store edits still need to be published. Run one command per project with a message describing its edits.'
    while IFS= read -r project; do
        printf -v command 'context-commit.sh --project %q "<message>"' "$project"
        reason+=$'\n'"$command"
    done < <(printf '%s\n' "${!pending[@]}" | LC_ALL=C sort)

    if [[ $(jq -r '.stop_hook_active // false' <<< "$payload") == true ]]; then
        jq -nc --arg reason "$reason" '{systemMessage: $reason}'
    else
        jq -nc --arg reason "$reason" '{decision: "block", reason: $reason}'
    fi
}

case $(jq -r '.hook_event_name // empty' <<< "$payload") in
    PostToolUse) record_edit ;;
    Stop) check_edits ;;
esac

#!/usr/bin/env bash
set -uo pipefail

if [[ ${1:-} == --help ]]; then
    echo "Test context store commits, sync, and Claude hooks against local repos."
    echo "Usage: test-context-store.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
export PATH="$SCRIPT_DIR/../scripts:$PATH"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null LC_ALL=C

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

repo_git() (
    repo=$1
    shift
    cd "$repo" || exit 1
    git "$@"
)

store_git() { repo_git "$store" "$@"; }
peer_git() { repo_git "$peer" "$@"; }

fixture() {
    local dir="$tmp/$1"
    fixture_home="$dir/home"
    store="$fixture_home/repos/context"
    remote="$dir/remote.git"
    peer="$dir/peer"
    mkdir -p "$store/alpha" "$store/beta" || exit 1
    git init -q --bare -b main "$remote" || exit 1
    store_git init -q -b main || exit 1
    store_git config user.name Tester
    store_git config user.email test@example.com
    echo base > "$store/alpha/GLOSSARY.md"
    echo base > "$store/beta/GLOSSARY.md"
    store_git add .
    store_git commit -qm Seed || exit 1
    store_git remote add origin "$remote"
    store_git push -qu origin main || exit 1
    git clone -q "$remote" "$peer" || exit 1
    peer_git config user.name Tester
    peer_git config user.email test@example.com
    echo alpha > "$peer/.find-project.conf"
}

peer_change() {
    printf '%s\n' "$2" > "$peer/$1"
    peer_git add -- "$1"
    peer_git commit -qm Remote || exit 1
    peer_git push -q || exit 1
}

invoke() {
    output=$(
        cd "$peer" || exit 1
        env HOME="$fixture_home" XDG_STATE_HOME="$fixture_home/state" "$@" 2>&1
    )
    status=$?
}

contains() { [[ "$output" == *"$1"* ]] && echo yes || echo no; }
published() { repo_git "$remote" "$@"; }

fixture commit
peer_change beta/remote.md remote
echo local > "$store/alpha/GLOSSARY.md"
echo draft > "$store/beta/GLOSSARY.md"
echo scratch > "$store/beta/untracked.md"
invoke context-commit.sh 'alpha: term — local'
ok "Commit resolves the caller project and rebases with unrelated edits" \
    "$status|$(published log -2 --format=%s)|$(published show --format= --name-only HEAD)|$(store_git status --short beta)" \
    $'0|alpha: term — local\nRemote|alpha/GLOSSARY.md| M beta/GLOSSARY.md\n?? beta/untracked.md'

fixture override
echo staged > "$store/alpha/GLOSSARY.md"
store_git add alpha
echo local > "$store/beta/GLOSSARY.md"
echo new > "$store/beta/new.md"
invoke context-commit.sh --project beta 'beta: term — local'
ok "Override excludes another project's staged changes" \
    "$status|$(published show --format= --name-only HEAD)|$(store_git diff --cached --name-only)" \
    $'0|beta/GLOSSARY.md\nbeta/new.md|alpha/GLOSSARY.md'

fixture retry
printf '#!/bin/sh\necho rejected >&2\nexit 1\n' > "$remote/hooks/pre-receive"
chmod +x "$remote/hooks/pre-receive"
echo local > "$store/alpha/GLOSSARY.md"
invoke context-commit.sh Local
before="$status|$(contains 'push failed')|$(contains 'rejected')|$(contains 'Rerun context-commit.sh')|$(published log -1 --format=%s)"
pending=$(store_git rev-parse HEAD)
rm "$remote/hooks/pre-receive"
invoke context-commit.sh Retry
ok "A rejected commit stays local and an empty rerun publishes it" \
    "$before|$status|$(published rev-parse HEAD)" "1|yes|yes|yes|Seed|0|$pending"

fixture conflict
peer_change alpha/GLOSSARY.md remote
echo local > "$store/alpha/GLOSSARY.md"
echo draft > "$store/beta/GLOSSARY.md"
invoke context-commit.sh Local
ok "An aborted rebase keeps the commit and reapplies unrelated edits" \
    "$status|$(contains 'rebase failed')|$(contains 'CONFLICT')|$(store_git log -1 --format=%s)|$(published log -1 --format=%s)|$(store_git status --short)" \
    '1|yes|yes|Local|Remote| M beta/GLOSSARY.md'

fixture sync
peer_change beta/remote.md remote
echo local > "$store/alpha/GLOSSARY.md"
store_git add alpha
store_git commit -qm Stranded
echo draft > "$store/beta/GLOSSARY.md"
invoke context-sync.sh
ok "Sync rebases and publishes stranded commits while preserving drafts" \
    "$status|$(published log -2 --format=%s)|$(store_git status --short)" \
    $'0|Stranded\nRemote| M beta/GLOSSARY.md'

fixture offline
store_git remote set-url origin "$remote/missing"
echo draft > "$store/alpha/GLOSSARY.md"
store_git add alpha
head=$(store_git rev-parse HEAD)
invoke context-sync.sh
ok "An unreachable remote leaves HEAD and the index alone" \
    "$status|$(contains 'cannot reach remote')|$(contains 'does not appear to be a git repository')|$(store_git rev-parse HEAD)|$(store_git status --short)" \
    "1|yes|yes|$head|M  alpha/GLOSSARY.md"

fixture autostash
peer_change beta/GLOSSARY.md remote
echo local > "$store/alpha/GLOSSARY.md"
store_git add alpha
store_git commit -qm Stranded
echo draft > "$store/beta/GLOSSARY.md"
invoke context-sync.sh
ok "Autostash conflicts stop the push and name the recovery command" \
    "$status|$(contains 'local edits left in stash')|$(contains 'git stash list')|$(published log -1 --format=%s)|$(store_git show stash:beta/GLOSSARY.md 2>/dev/null)" \
    '1|yes|yes|Remote|draft'

fixture busy
mkdir "$store/.git/context-sync.lock"
echo local > "$store/alpha/GLOSSARY.md"
invoke context-commit.sh Local
before="$status|$(contains 'cannot lock')|$(store_git status --short)"
invoke context-sync.sh
ok "Both entry points respect the same store lock" \
    "$before|$status|$(contains 'cannot lock')" '1|yes| M alpha/GLOSSARY.md|1|yes'

fixture missing
fixture_home="$peer"
mkdir -p "$fixture_home/repos/context/alpha"
echo draft > "$fixture_home/repos/context/alpha/GLOSSARY.md"
invoke context-commit.sh --project alpha Local
before="$status|$(contains 'missing Git checkout')|$(peer_git log -1 --format=%s)"
invoke context-sync.sh
ok "A missing store never falls back to the enclosing repo" \
    "$before|$status|$output" '1|yes|Seed|0|'

fixture reject
echo draft > "$store/alpha/GLOSSARY.md"
rejected=
for name in .. .GIT alpha/x '' gamma; do
    invoke context-commit.sh --project "$name" Local
    rejected+="$status$(contains 'context-commit: project')"
done
invoke context-commit.sh --project beta
rejected+="|$status$(contains 'Usage:')"
invoke context-commit.sh
rejected+="$status$(contains 'Usage:')"
ok "Commit rejects bad project names and argument counts" \
    "$rejected|$(published log -1 --format=%s)|$(store_git status --short)" \
    '1yes1yes1yes1yes1yes|1yes1yes|Seed| M alpha/GLOSSARY.md'

fixture midop
mkdir "$store/.git/rebase-merge"
echo local > "$store/alpha/GLOSSARY.md"
invoke context-commit.sh Local
before="$status|$(contains 'in-progress Git operation')"
invoke context-sync.sh
ok "Both entry points refuse during an in-progress operation and release the lock" \
    "$before|$status|$(contains 'in-progress Git operation')|$(contains 'cannot lock')|$(published log -1 --format=%s)" \
    '1|yes|1|yes|no|Seed'

fixture no-upstream-sync
store_git branch --unset-upstream
invoke context-sync.sh
ok "Sync without an upstream names that, not a rebase failure" \
    "$status|$(contains 'no upstream')|$(contains 'rebase failed')" '1|yes|no'

record_edit() {
    invoke context-stop.sh < <(jq -nc --arg session "$1" --arg path "$2" --arg tool "${3:-Edit}" \
        '{session_id: $session, hook_event_name: "PostToolUse", agent_id: "test-fork", tool_name: $tool, tool_input: {file_path: $path}}')
}

stop() {
    invoke context-stop.sh < <(jq -nc --arg session "$1" --argjson active "${2:-false}" \
        '{session_id: $session, hook_event_name: "Stop", stop_hook_active: $active}')
}

hook_value() { jq -r "$1 // empty" <<< "$output" 2>/dev/null; }

fixture block
echo draft > "$store/alpha/GLOSSARY.md"
echo draft > "$store/beta/new.md"
record_edit first "$store/alpha/GLOSSARY.md"
record_edit first "$store/beta/new.md" Write
record_edit first "$store/beta/new.md" Write
stop second
before="$status|$output"
stop first
prompts=$(hook_value '.reason' | sed -n '/^context-commit\.sh /p')
before="$before|$status|$(hook_value '.decision')|$prompts"
stop first true
ok "Parent blocks once for each turn and warns if the same paths are still pending" \
    "$before|$status|$(hook_value '.decision')|$(hook_value '.systemMessage' | grep -c '^context-commit\.sh --project ')" \
    $'0||0|block|context-commit.sh --project alpha "<message>"\ncontext-commit.sh --project beta "<message>"|0||2'

fixture prune
echo tracked > "$store/alpha/[term].md"
store_git add alpha
store_git commit -qm Local
record_edit current "$store/alpha/[term].md"
stop current
before="$status|$(hook_value '.decision')"
store_git push -q
echo other > "$store/alpha/t.md"
echo other > "$store/beta/GLOSSARY.md"
mkdir -p "$fixture_home/repos/context-backup/beta"
echo outside > "$fixture_home/repos/context-backup/beta/GLOSSARY.md"
record_edit current "$fixture_home/repos/context-backup/beta/GLOSSARY.md"
record_edit current "$store/beta/GLOSSARY.md" Bash
stop current
before="$before|$status|$output"
echo later > "$store/alpha/[term].md"
stop current
ok "Stop tracks unpushed paths, drops settled ones, and ignores other edits" \
    "$before|$status|$output" '0|block|0||0|'

fixture no-upstream
record_edit current "$store/alpha/GLOSSARY.md"
store_git branch --unset-upstream
stop current
ok "Stop keeps an edit record when publication cannot be verified" \
    "$status|$(hook_value '.decision')|$(contains 'context-commit.sh --project alpha')" '0|block|yes'

fixture filters
echo root > "$store/README.md"
record_edit current "$store/README.md"
record_edit current "$store/.git/description"
record_edit current "$store/alpha/../README.md"
record_edit '../x' "$store/alpha/GLOSSARY.md"
record_edit '' "$store/alpha/GLOSSARY.md"
stop current
ok "Edits outside a project directory and unsafe session ids leave no record" \
    "$status|$output|$(find "$fixture_home/state" "$fixture_home/x"* -type f 2>/dev/null | wc -l)" '0||0'

fixture busy-stop
record_edit current "$store/alpha/GLOSSARY.md"
mkdir "$store/.git/context-sync.lock"
stop current
before="$status|$(hook_value '.decision')"
rmdir "$store/.git/context-sync.lock"
echo local > "$store/alpha/GLOSSARY.md"
stop current true
ok "Stop keeps records while another context command holds the lock" \
    "$before|$status|$(contains 'context-commit.sh --project alpha')" '0|block|0|yes'

fixture gone
echo draft > "$store/alpha/GLOSSARY.md"
record_edit current "$store/alpha/GLOSSARY.md"
mv "$store/.git" "$store/.git-gone"
stop current
ok "Stop drops records once the store checkout is gone" \
    "$status|$output|$(find "$fixture_home/state" -name 'current.edit.*' | wc -l)" '0||0'

ok "Claude wires both context hooks and keeps the fork registry" \
    "$(jq -r '.hooks | [(.PostToolUse[] | .matcher, .hooks[].command), (.Stop[]?.hooks[].command)] | join("|")' \
        "$SCRIPT_DIR/../claude/settings.json")" \
    '|~/.local/bin/fork-registry.sh|^(Edit|Write)$|~/.local/bin/context-stop.sh|~/.local/bin/context-stop.sh'

report

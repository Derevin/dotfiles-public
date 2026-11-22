#!/usr/bin/env bash
# Unit tests for scripts/local-ci, against a fake `uv run prek`.
# Usage: test-local-ci.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the local-ci unit tests."
    echo "Usage: test-local-ci.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
CI="$SCRIPT_DIR/../scripts/local-ci"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export XDG_STATE_HOME="$TMP/state"
export TMPDIR="$TMP/out" && mkdir -p "$TMPDIR"
unset LOCAL_CI_CALLER

# The fake uv records its argv and prints prek's verbose report for FAKE_MODE:
# green (two hooks pass, one skips), red (the second hook fails), dead (prek
# never starts) or workspace (red, nested configs: prek heads each project and
# indents everything under it). prek names no id for a skipped hook and indents
# hook output. `prek list` records its argv apart and answers FAKE_LIST.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/uv" <<'EOF'
#!/usr/bin/env bash
if [ "$FAKE_MODE" = dead ]; then
    echo "error: Failed to spawn: \`prek\`" >&2
    exit 2
fi
if [ "$4" = list ]; then
    printf '%s\n' "$@" > "$FAKE_LIST_ARGS"
    echo "${FAKE_LIST:-[]}"
    exit 0
fi
printf '%s\n' "$@" > "$FAKE_ARGS"
if [ "$FAKE_MODE" = workspace ]; then
    cat <<'OUT'
✓ sub
  check yaml.........................................(no files to check)Skipped
  fmt....................................................................Passed
  - hook id: fmt
  - duration: 0.54s
× <workspace>
  cargo test.............................................................Failed
  - hook id: cargo-test
  - duration: 12.30s
  - exit code: 101

    boom
OUT
    exit 1
fi
cat <<'OUT'
check yaml...........................................(no files to check)Skipped
fmt......................................................................Passed
- hook id: fmt
- duration: 0.54s

  test result: ok. 3 passed.....................................Passed
OUT
if [ "$FAKE_MODE" = red ]; then
    cat <<'OUT'
cargo test...............................................................Failed
- hook id: cargo-test
- duration: 12.30s
- exit code: 101

  boom
OUT
    exit 1
fi
cat <<'OUT'
cargo test...............................................................Passed
- hook id: cargo-test
- duration: 12.30s
OUT
EOF
chmod +x "$TMP/bin/uv"
export FAKE_ARGS="$TMP/args"
export FAKE_LIST_ARGS="$TMP/list-args"
export PATH="$TMP/bin:$PATH"

git_q() { git "$@" >/dev/null 2>&1; }

# A repo with a main branch and a task branch carrying committed, uncommitted,
# untracked and deleted changes.
REPO="$TMP/proj"
mkdir -p "$REPO"
cd "$REPO" || exit 1
git_q init -b main
git_q config user.email t@t
git_q config user.name t
echo repos: [] > .pre-commit-config.yaml
echo base > untouched.txt
echo base > doomed.txt
echo base > edited.txt
git_q add -A
git_q commit -m base
git_q switch -c task
echo branch > committed.txt
git rm -q doomed.txt
git_q add -A
git_q commit -m work
echo dirty >> edited.txt
echo new > untracked.txt

LOG="$XDG_STATE_HOME/local-ci/proj.jsonl"
last() { tail -n 1 "$LOG" | jq -r "$1"; }

ok "help exits 0" "$("$CI" --help >/dev/null; echo $?)" 0

FAKE_MODE=green LOCAL_CI_CALLER=agent "$CI" > "$TMP/stdout" 2>&1
ok "green exits 0" "$?" 0
ok "runs prek through uv, lock untouched" "$(sed -n 1,4p "$FAKE_ARGS" | paste -sd' ')" "run --locked prek run"
ok "runs the manual stage" "$(grep -c -x -- manual "$FAKE_ARGS")" 1
ok "checks the branch's files, deletions out" \
    "$(sed -n '/^--files$/,$p' "$FAKE_ARGS" | tail -n +2 | paste -sd' ')" \
    "committed.txt edited.txt untracked.txt"
ok "green logs one record" "$(wc -l < "$LOG")" 1
ok "green record passes" "$(last .result)" pass
ok "caller from LOCAL_CI_CALLER" "$(last .caller)" agent
ok "branch recorded" "$(last .branch)" task
ok "commit recorded" "$(last .commit)" "$(git rev-parse HEAD)"
ok "a dirty tree is recorded" "$(last .dirty)" true
ok "each hook that ran a step, hook output not" "$(last '[.steps[].step] | join(" ")')" "fmt cargo-test"
ok "step results" "$(last '[.steps[].result] | join(" ")')" "pass pass"
ok "durations in ms" "$(last '.steps[1].ms')" 12300
ok "green prints one line" "$(wc -l < "$TMP/stdout")" 1
ok "green leaves no output file" "$(find "$TMPDIR" -type f | wc -l)" 0
ok "asks for caller-scoped hooks outside the caller's group" \
    "$(sed -n '4,$p' "$FAKE_LIST_ARGS" | paste -sd' ')" \
    "list --hook-stage manual --output-format json --group caller-scoped --no-group agent"
ok "none, none skipped" "$(grep -c -x -- --skip "$FAKE_ARGS")" 0

FAKE_MODE=green FAKE_LIST='[{"id":"slow","full_id":".:slow"},{"id":"slower","full_id":"sub:slower"}]' \
    "$CI" >/dev/null 2>&1
ok "unset caller scopes as manual" "$(tail -n 1 "$FAKE_LIST_ARGS")" manual
ok "skips another caller's hooks" "$(sed -n '/^--skip$/{n;p}' "$FAKE_ARGS" | paste -sd' ')" ".:slow sub:slower"
ok "logs them skipped" "$(last '[.steps[] | "\(.step) \(.result)"] | join(", ")')" \
    "fmt pass, cargo-test pass, slow skip, slower skip"

FAKE_MODE=red "$CI" > "$TMP/stdout" 2>&1
ok "red exits 1" "$?" 1
ok "red record fails" "$(last .result)" fail
ok "red step last" "$(last '.steps[-1] | "\(.step) \(.result)"')" "cargo-test fail"
ok "unset caller is manual" "$(last .caller)" manual
ok "red prints prek's output" "$(grep -c boom "$TMP/stdout")" 1
ok "red leaves no output file" "$(find "$TMPDIR" -type f | wc -l)" 0

FAKE_MODE=workspace "$CI" > "$TMP/stdout" 2>&1
ok "workspace red exits 1" "$?" 1
ok "workspace steps" "$(last '[.steps[] | "\(.step) \(.result) \(.ms)"] | join(", ")')" \
    "fmt pass 540, cargo-test fail 12300"
ok "workspace red prints the project heads" "$(grep -c -e '^✓ sub$' -e '^× <workspace>$' "$TMP/stdout")" 2

FAKE_MODE=dead "$CI" > "$TMP/stdout" 2>&1
ok "a runner that never starts is red" "$?" 1
ok "red prints the runner's error" "$(grep -c 'Failed to spawn' "$TMP/stdout")" 1
ok "and logs no steps" "$(last '.steps | length')" 0

# On the base branch with a clean tree nothing is changed, yet CI still runs.
git_q stash -u
git_q switch main
FAKE_MODE=green "$CI" >/dev/null 2>&1
ok "base branch, clean: runs" "$?" 0
ok "base branch, clean: no files" "$(sed -n '/^--files$/,$p' "$FAKE_ARGS" | tail -n +2 | wc -l)" 0

# No config, no CI: exit 3, and nothing logged.
NOCFG="$TMP/bare"
mkdir -p "$NOCFG"
git -C "$NOCFG" init -q
before=$(wc -l < "$LOG")
(cd "$NOCFG" && FAKE_MODE=green "$CI" >/dev/null 2>&1)
ok "no config exits 3" "$?" 3
ok "no config logs nothing" "$(wc -l < "$LOG")" "$before"

report

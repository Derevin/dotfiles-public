#!/usr/bin/env bash
# Unit tests for lab-lib.sh — the derivations every lab script shares: names,
# heads, truncation, project resolution, quadrant state, task lookup.
#
# Self-contained: temp checkouts and a temp lab.conf, no docker, coder or tmux.
# Usage: test-lab-lib.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the lab-lib.sh unit tests."
    echo "Usage: test-lab-lib.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/one" "$TMP/two"
cat > "$TMP/lab.conf" <<CONF
LAB_ONE_CHECKOUT=$TMP/one/Proj
LAB_ONE_CONTAINER_PREFIX=one-
LAB_ONE_PROVISIONER=$TMP/provision.sh
LAB_ONE_BACKEND=docker
LAB_TWO_CHECKOUT=$TMP/two/Two
LAB_TWO_CONTAINER_PREFIX=two-
CONF

export LAB_CONF="$TMP/lab.conf"
export LAB_STATE_DIR="$TMP/state"
export LAB_TASKS_ROOT="$TMP/tasks"

source "$SCRIPT_DIR/../scripts/lab-lib.sh"

# --- backends ---------------------------------------------------------------
ok "backend h" "$(lab_backend hlab-tmp1)" host
ok "backend d" "$(lab_backend dlab-238-x)" docker
ok "backend c" "$(lab_backend cwt3)" coder
ok "backend word passthrough" "$(lab_backend docker)" docker
fails lab_backend zzz
ok "letter" "$(lab_backend_letter coder)" c

# --- names ------------------------------------------------------------------
ok "head of claimed" "$(lab_head dlab-238-fix-the-nasty-bug)" dlab-238
ok "head of anonymous" "$(lab_head dlab-tmp1)" dlab-tmp1
ok "head of fixture" "$(lab_head dwt1)" dwt1
ok "task id" "$(lab_task_id clab-039-settle)" 039
ok "task id of anonymous" "$(lab_task_id clab-tmp2)" ""

lab_is_lab dlab-238-x; ok "is_lab claimed" "$?" 0
lab_is_lab hlab-tmp9; ok "is_lab anonymous" "$?" 0
lab_is_lab dwt1; ok "is_lab fixture" "$?" 1
lab_is_anonymous dlab-tmp1; ok "is_anonymous" "$?" 0
lab_is_anonymous dlab-238-x; ok "is_anonymous claimed" "$?" 1

# The whole workspace name has to fit Coder's 32-character cap, and the prefix
# and id eat into it before the slug does.
n=$(lab_claimed_name docker 238 fix-the-nasty-bug widget-)
ok "claimed name truncates" "$n" dlab-238-fix-the-nasty-bu
ok "claimed name fits the cap" "$((${#n} + 7))" 32
# A cut landing on a separator would leave a name Coder rejects.
ok "no trailing hyphen" "$(lab_claimed_name docker 238 three-word-slug-here widget-)" dlab-238-three-word-slug
ok "short slug untouched" "$(lab_claimed_name host 001 ab widget-)" hlab-001-ab
# A prefix long enough to leave no room drops the slug rather than overflowing.
ok "no budget leaves the head" "$(lab_claimed_name coder 001 anything averyveryverylongprefix-)" clab-001

ok "project key" "$(lab_project_key my-proj.x)" MY_PROJ_X
ok "strip prefix" "$(lab_strip_prefix two-clab-001-x)" clab-001-x
ok "strip prefix leaves unknown" "$(lab_strip_prefix zz-clab-001-x)" zz-clab-001-x

# --- claude -----------------------------------------------------------------
ok "claude cmd" "$(lab_claude_cmd dlab-238)" "CLAUDE_LABEL=dlab-238 claude --effort max"
ok "claude cmd no auto memory" "$(lab_claude_cmd --no-auto-memory dwt1 --continue)" \
    "CLAUDE_LABEL=dwt1 CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 claude --effort max --continue"
ok "claude cmd quotes what needs it" "$(lab_claude_cmd x '/plan-task 039')" \
    "CLAUDE_LABEL=x claude --effort max '/plan-task 039'"
ok "claude cmd skips empty args" "$(lab_claude_cmd x '')" "CLAUDE_LABEL=x claude --effort max"

# Claude keys session state on this path, which is why the claim rename carries
# it. Only separators a checkout path actually contains are pinned here; how
# Claude encodes a dot or an underscore is unverified, and a wrong guess would
# make the claim's move a no-op rather than corrupt anything.
ok "project dir encoding" "$(lab_claude_project_dir /home/u/repos/p/Proj-dlab-238-x)" \
    "$HOME/.claude/projects/-home-u-repos-p-Proj-dlab-238-x"

# --- project resolution -----------------------------------------------------
mkdir -p "$TMP/one/Proj-dlab-238-x"
lab_resolve dlab-238-x
ok "resolve picks the project owning the worktree" "$LAB_PROJECT_KEY" ONE
ok "resolve worktree" "$LAB_WORKTREE" "$TMP/one/Proj-dlab-238-x"
ok "resolve container" "$LAB_CONTAINER" "one-dlab-238-x"
ok "resolve backend" "$LAB_BACKEND" docker
ok "resolve provisioner" "$LAB_PROVISIONER" "$TMP/provision.sh"

LAB_PROJECT_OVERRIDE=two lab_resolve hlab-tmp1
ok "override wins" "$LAB_WORKTREE" "$TMP/two/Two-hlab-tmp1"

# No local evidence: the cwd decides, because a launchpad stands in its project's
# main checkout. This is also what keeps a coder lab — which has neither a
# worktree nor a container — off the network on the common path.
mkdir -p "$TMP/two/Two"
(cd "$TMP/two/Two" && git init -q .) 2>/dev/null
ok "cwd decides when nothing local says" \
    "$(cd "$TMP/two/Two" && lab_resolve clab-007-y && echo "$LAB_CONTAINER")" two-clab-007-y
# A cwd whose project is not configured is just a shell that happens to be
# elsewhere, not an answer.
fails bash -c 'cd /tmp && source "'"$SCRIPT_DIR"'/../scripts/lab-lib.sh" && lab_resolve hlab-tmp9'

# The backend a project's labs land in when nothing else says. A project that
# declares none gets none invented for it — creation asks there instead.
lab_project_paths one
ok "project default backend" "$LAB_DEFAULT_BACKEND" docker
lab_project_paths two
ok "no default backend declared" "$LAB_DEFAULT_BACKEND" ""


# --- quadrant state ---------------------------------------------------------
lab_state_put proj labs 1 dlab-238-x
lab_state_put proj labs 3 hlab-tmp1
lab_state_put proj labs2 1 clab-007-y
ok "rows of one window" "$(lab_state_rows proj labs | tr '\t' ' ' | tr '\n' ';')" \
    "1 dlab-238-x;3 hlab-tmp1;"
# Re-attaching a quadrant replaces its row rather than adding a second.
lab_state_put proj labs 1 clab-007-y
ok "put replaces" "$(lab_state_rows proj labs | wc -l)" 2
lab_state_rename proj clab-007-y clab-007-z
ok "rename carries every row" "$(grep -c 'clab-007-z' "$(lab_state_file proj)")" 2
# A launchpad is the absence of a row.
lab_state_drop proj labs 1
ok "drop leaves nothing behind" "$(lab_state_rows proj labs | wc -l)" 1
lab_state_drop_lab proj clab-007-z
ok "dropping a lab forgets every quadrant" "$(grep -c 'clab-007-z' "$(lab_state_file proj)")" 0

# --- tasks ------------------------------------------------------------------
mkdir -p "$TMP/tasks/proj"/{todo,planning,planned,active}
touch "$TMP/tasks/proj/planned/N039-settle-agent-environment-flow.md"
ok "task found by bare id" "$(lab_task_find proj 039)" \
    "$TMP/tasks/proj/planned/N039-settle-agent-environment-flow.md"
fails lab_task_find proj 111
# The letter is priority and task-reprioritize.sh rewrites it, so two files can
# share an id only by mistake — and guessing between them would bind the lab to
# the wrong task.
touch "$TMP/tasks/proj/todo/A039-other.md"
fails lab_task_find proj 039
rm "$TMP/tasks/proj/todo/A039-other.md"
ok "task found in an explicit dir" "$(lab_task_find proj 039 planned)" \
    "$TMP/tasks/proj/planned/N039-settle-agent-environment-flow.md"
fails lab_task_find proj 039 todo

# --- current lab ------------------------------------------------------------
ok "current from coder" "$(CODER_WORKSPACE_NAME=two-clab-001-x lab_current)" clab-001-x
ok "current from docker" "$(LAB_NAME=dlab-238-x lab_current)" dlab-238-x
# A host lab has no env marker: the worktree dir is the name, from anywhere inside it.
mkdir -p "$TMP/one/Proj-hlab-tmp4/modules/gui"
ok "current from a host lab subdir" \
    "$(cd "$TMP/one/Proj-hlab-tmp4/modules/gui" && lab_current)" hlab-tmp4
ok "current outside a lab" "$(cd "$TMP/one" && lab_current; echo)" ""

report

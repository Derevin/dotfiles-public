#!/usr/bin/env bash
# Tag an anonymous lab with a task: the rename that turns dlab-tmp1 into
# dlab-238-fix-the-nasty-bug.
#
# The name is the path, so the rename has to carry five things together or the
# lab loses part of its identity: the worktree, the container, Claude's
# per-project session dir, the pane's @lab, and the task's Worker: line. For a
# coder lab the session dir is a no-op carrier — state lives inside the
# workspace and travels with it.
#
# Requires an existing task and never moves queue state: creation and placement
# stay with /create-task and the task scripts.
#
# Usage: lab-claim.sh <lab> <task-id>
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Tag an anonymous lab with a task, renaming it to <b>lab-<id>-<slug>."
    echo "Usage: lab-claim.sh <lab> <task-id>"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lab-lib.sh"
source "$SCRIPT_DIR/task-lib.sh"

OLD="${1:-}"
ID="${2:-}"
if [ -z "$OLD" ] || [ -z "$ID" ]; then
    echo "usage: lab-claim.sh <lab> <task-id>" >&2; exit 2
fi
[[ "$ID" =~ ^[0-9]{3}$ ]] || { echo "lab-claim: task id must be three digits, got '$ID'" >&2; exit 2; }

# The new name on stdout is this script's whole output — lab-start.sh reads it
# back. Everything the rename says goes to stderr.
lab_is_lab "$OLD" || { echo "lab-claim: $OLD is a legacy fixture — it has no task and cannot be claimed" >&2; exit 1; }
lab_is_anonymous "$OLD" || { echo "lab-claim: $OLD is already claimed" >&2; exit 1; }

lab_resolve "$OLD"
OLD_WORKTREE="$LAB_WORKTREE"
OLD_CONTAINER="$LAB_CONTAINER"
BACKEND="$LAB_BACKEND"
PROJECT="$LAB_PROJECT"

TASK_PATH=$(lab_task_find "$PROJECT" "$ID")
TASK_FILE=$(basename "$TASK_PATH")
SLUG=$(slug_from_filename "$TASK_FILE")

NEW=$(lab_claimed_name "$BACKEND" "$ID" "$SLUG" "$LAB_PREFIX")
# Pinned: the new name has neither a worktree nor a container yet, so resolving
# it on its own evidence would fall through to the cwd and could land on a
# different project's checkout than the lab we are renaming.
LAB_PROJECT_OVERRIDE="$PROJECT" lab_resolve "$NEW"
NEW_WORKTREE="$LAB_WORKTREE"
NEW_CONTAINER="$LAB_CONTAINER"

# Keyed on the id, because the checks below compare whole names and a name
# carries the slug: a lab claimed for this task before it was retitled derives a
# different name now and would slip past every one of them. NEW itself is left to
# those checks — they can tell a collision from a claim that died partway, which
# this cannot.
EXISTING=$(lab_task_lab "$BACKEND" "$ID")
if [ -n "$EXISTING" ] && [ "$EXISTING" != "$NEW" ]; then
    echo "lab-claim: task $ID already has the $BACKEND lab $EXISTING" >&2; exit 1
fi

# One lab per (backend, task): a second would need a suffix, and then the id no
# longer identifies the lab. The new worktree standing where the old one has
# already gone is the exception — that is a claim that died partway, so pick it
# up at the backend rather than calling it a collision.
RESUME=0
if [ "$BACKEND" != coder ] && [ -d "$NEW_WORKTREE" ]; then
    if [ -d "$OLD_WORKTREE" ]; then
        echo "lab-claim: $NEW already exists at $NEW_WORKTREE" >&2; exit 1
    fi
    RESUME=1
fi
case "$BACKEND" in
    docker)
        lab_container_exists "$NEW_CONTAINER" && { echo "lab-claim: container $NEW_CONTAINER already exists" >&2; exit 1; }
        # Checked here, not at the recreate below: by then the old container is
        # gone and the worktree has moved, so a provisioner that is missing or
        # has lost its +x would leave a lab with no backend.
        [ -x "$LAB_PROVISIONER" ] || { echo "lab-claim: provisioner not executable: $LAB_PROVISIONER" >&2; exit 1; }
        ;;
    coder) lab_workspace_exists "$NEW_CONTAINER" && { echo "lab-claim: workspace $NEW_CONTAINER already exists" >&2; exit 1; } ;;
esac

# 1. The container. LAB_NAME is baked into a docker container's environment at
# create and `docker rename` cannot change it, while detect_worker prefers it
# and the provisioner derives the worktree path from it — so the container is
# destroyed and recreated against the moved worktree rather than renamed.
# Nothing is lost: home is a shared volume, code is a bind mount, ~/.claude is a
# host bind mount. Removing it first keeps a stale bind mount from outliving the
# move; if the recreate then fails, re-running the claim resumes from here.
if [ "$BACKEND" = docker ] && lab_container_exists "$OLD_CONTAINER"; then
    docker rm -f "$OLD_CONTAINER" >/dev/null
fi

# 2. The worktree — the path IS the name.
if [ "$BACKEND" != coder ] && [ "$RESUME" = 0 ]; then
    [ -d "$OLD_WORKTREE" ] || { echo "lab-claim: no worktree at $OLD_WORKTREE" >&2; exit 1; }
    git -C "$LAB_CHECKOUT" worktree move "$OLD_WORKTREE" "$NEW_WORKTREE" >&2
fi

# 3. Claude's per-project session dir, keyed on the encoded cwd. Without this
# the conversation the claim exists to preserve is stranded under the old name.
# A coder lab keeps its sessions inside the workspace, so there is nothing here
# to move.
if [ "$BACKEND" != coder ]; then
    OLD_PROJ=$(lab_claude_project_dir "$OLD_WORKTREE")
    NEW_PROJ=$(lab_claude_project_dir "$NEW_WORKTREE")
    if [ -d "$OLD_PROJ" ] && [ ! -e "$NEW_PROJ" ]; then
        mv "$OLD_PROJ" "$NEW_PROJ"
    fi
fi

# 4. Recreate the container / rename the workspace.
case "$BACKEND" in
    docker)
        "$LAB_PROVISIONER" docker "$NEW" "$NEW_WORKTREE" >&2
        ;;
    coder)
        coder rename "$OLD_CONTAINER" "$NEW_CONTAINER" -y >&2
        ;;
esac

# 5. The task's Worker: line. No-op while the task is still in todo/ — the slash
# command's own task-claim.sh stamps it from inside the lab. Run from the
# checkout: task-restamp.sh picks its tasks dir off the cwd, and the lab was
# identified by its worktree, not by where the claim was invoked.
(cd "$LAB_CHECKOUT" && task-restamp.sh "$TASK_FILE" "$(lab_head "$NEW")") >/dev/null

lab_state_rename "$PROJECT" "$OLD" "$NEW"

# 6. Any pane showing the lab. Relaunching with --continue picks the
# conversation back up out of the dir just moved, so an investigation survives
# becoming a task.
# `tmux info` needs a client and fails outside one, so it cannot stand in for
# "is there a server": with none, list-panes yields nothing and this is a no-op.
if command -v tmux >/dev/null 2>&1; then
    while read -r pane lab; do
        [ "$lab" = "$OLD" ] || continue
        lab-attach.sh --pane "$pane" "$NEW" --continue
    done < <(TMUX= tmux list-panes -a -F '#{pane_id} #{@lab}' 2>/dev/null)
fi

echo "$NEW"

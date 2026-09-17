#!/usr/bin/env bash
# End-to-end test of the host-backend lab lifecycle: create anonymous, claim it
# to a task, drop it. Host is the backend with no provisioning unknowns, so it is
# the one that can be exercised for real; the docker and coder paths differ only
# in what the provisioner does and what the claim recreates or renames.
#
# Self-contained: a throwaway project with its own origin, a throwaway tasks repo,
# a stub provisioner, stub docker and coder, and a tmux socket dir of its own.
# Touches ~/.claude/projects only under paths derived from the temp dir, and
# removes them.
#
# Usage: test-lab-lifecycle.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the end-to-end lab lifecycle test (create, claim, drop) on the host backend."
    echo "Usage: test-lab-lifecycle.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"

# The working tree, not whatever the installer last linked: the scripts call each
# other by bare name, so they have to be found through PATH either way.
export PATH="$SCRIPT_DIR/../scripts:$SCRIPT_DIR/../tmux:$PATH"

TMP=$(mktemp -d)
CLEAN_PROJ_DIRS=()
cleanup() {
    rm -rf "$TMP"
    [ "${#CLEAN_PROJ_DIRS[@]}" -gt 0 ] && rm -rf "${CLEAN_PROJ_DIRS[@]}"
}
trap cleanup EXIT

q() { git "$@" >/dev/null 2>&1; }

# The user's real tmux server is not a test fixture. lab-claim.sh's last step
# walks every pane on whatever server answers and respawns any whose @lab is the
# name being claimed — and the names here, hlab-tmp1 and friends, are exactly the
# ones lab-new.sh hands out for real. Point tmux at a socket dir of our own so no
# server answers at all.
export TMUX_TMPDIR="$TMP/tmux"
mkdir -p "$TMUX_TMPDIR"
unset TMUX

# Neither backend is under test here, and coder list is a network round trip that
# can hang with no timeout. Stub both so the run is hermetic either way.
mkdir -p "$TMP/bin"
for stub in docker coder; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/stub.log"\nexit 1\n' \
        "$stub" "$TMP" > "$TMP/bin/$stub"
    chmod +x "$TMP/bin/$stub"
done
export PATH="$TMP/bin:$PATH"

# A throwaway project with an origin to detach from.
git init -q --bare "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/Widget" 2>/dev/null
q -C "$TMP/Widget" config user.email t@t
q -C "$TMP/Widget" config user.name T
echo hi > "$TMP/Widget/README.md"
q -C "$TMP/Widget" add -A
q -C "$TMP/Widget" commit -m init
q -C "$TMP/Widget" branch -M main
q -C "$TMP/Widget" push -u origin main

# A throwaway tasks repo: the restamp commits and pushes, so it needs a remote.
git init -q --bare "$TMP/tasks-origin.git"
git clone -q "$TMP/tasks-origin.git" "$TMP/tasks" 2>/dev/null
q -C "$TMP/tasks" config user.email t@t
q -C "$TMP/tasks" config user.name T
mkdir -p "$TMP/tasks/widget"/{todo,planning,planned,active,done,canceled}
TASK="$TMP/tasks/widget/active/N238-make-the-build-faster.md"
printf '# Make the build faster\nWorker: main\n\nbody\n' > "$TASK"
q -C "$TMP/tasks" add -A
q -C "$TMP/tasks" commit -m init
q -C "$TMP/tasks" branch -M main
q -C "$TMP/tasks" push -u origin main

cat > "$TMP/lab.conf" <<CONF
LAB_WIDGET_CHECKOUT=$TMP/Widget
LAB_WIDGET_CONTAINER_PREFIX=widget-
LAB_WIDGET_PROVISIONER=$TMP/provision.sh
CONF
cat > "$TMP/provision.sh" <<'PROV'
#!/usr/bin/env bash
printf '%s %s %s\n' "$1" "$2" "$3" >> "$(dirname "$0")/provision.log"
[ -z "${PROVISION_FAIL:-}" ] || exit 1
PROV
chmod +x "$TMP/provision.sh"

export LAB_CONF="$TMP/lab.conf" LAB_STATE_DIR="$TMP/state"
export LAB_TASKS_ROOT="$TMP/tasks" TASKS_ROOT="$TMP/tasks"
cd "$TMP/Widget"

# --- create ------------------------------------------------------------------
N=$(lab-new.sh host 2>/dev/null)
# Only the name reaches stdout; lab-start.sh and the claim read it back.
ok "new prints the name alone" "$N" hlab-tmp1
ok "new creates the worktree" "$([ -d "$TMP/Widget-$N" ] && echo y)" y
# Detached at origin/<base>: no script invents a branch name.
ok "new detaches" "$(git -C "$TMP/Widget-$N" symbolic-ref -q HEAD || echo detached)" detached
ok "new lands on origin/main" "$(git -C "$TMP/Widget-$N" rev-parse HEAD)" \
    "$(git -C "$TMP/Widget" rev-parse origin/main)"
ok "new calls the provisioner" "$(cat "$TMP/provision.log")" "host $N $TMP/Widget-$N"

N2=$(lab-new.sh host 2>/dev/null)
ok "new takes the lowest free index" "$N2" hlab-tmp2

# --- claim -------------------------------------------------------------------
enc() { printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g'; }
PROJ_OLD="$HOME/.claude/projects/$(enc "$TMP/Widget-$N")"
CLEAN_PROJ_DIRS+=("$PROJ_OLD")
mkdir -p "$PROJ_OLD"
echo session > "$PROJ_OLD/x.jsonl"

NEW=$(lab-claim.sh "$N" 238 2>/dev/null)
PROJ_NEW="$HOME/.claude/projects/$(enc "$TMP/Widget-$NEW")"
CLEAN_PROJ_DIRS+=("$PROJ_NEW")

# The slug truncates so <prefix><name> fits Coder's cap, on every backend.
ok "claim renames to id and slug" "$NEW" hlab-238-make-the-build-f
ok "claimed name fits the cap" "$((${#NEW} + 7))" 32
ok "claim moves the worktree" "$([ -d "$TMP/Widget-$NEW" ] && echo y)" y
ok "claim leaves no old worktree" "$([ -d "$TMP/Widget-$N" ] && echo y)" ""
# Without this the conversation the claim exists to preserve is stranded.
ok "claim carries the claude session dir" "$([ -f "$PROJ_NEW/x.jsonl" ] && echo y)" y
# The stamp is the head, not the whole name: it lands in commit subjects too.
ok "claim restamps the task" "$(sed -n 's/^Worker: //p' "$TASK")" hlab-238
ok "restamp commits" "$(git -C "$TMP/tasks" log --oneline -1 | sed 's/^[0-9a-f]* //')" \
    "Restamp: make-the-build-faster [hlab-238]"
ok "restamp pushes" "$(git -C "$TMP/tasks" rev-parse HEAD)" \
    "$(git -C "$TMP/tasks" rev-parse origin/main)"

# Inside the lab, every identity question agrees.
ok "worker inside the lab" \
    "$(cd "$TMP/Widget-$NEW" && source "$(command -v task-lib.sh)" && detect_worker && echo "$WORKER")" \
    hlab-238
ok "project inside the lab" "$(cd "$TMP/Widget-$NEW" && find-project.sh)" widget
ok "lab-current inside the lab" "$(cd "$TMP/Widget-$NEW" && lab-current.sh)" "$NEW"

ok "list is derived from the filesystem" "$(lab-list.sh | tr '\n' ' ')" "$NEW $N2 "

# A second claim of the same task on the same backend would need a suffix, and
# then the id would no longer identify the lab.
fails lab-claim.sh "$N2" 238
fails lab-claim.sh "$NEW" 238

# --- drop guards -------------------------------------------------------------
fails lab-drop.sh "$NEW"                      # attached task is in active/
echo dirt > "$TMP/Widget-$N2/dirt"
fails lab-drop.sh "$N2"                       # dirty worktree
rm "$TMP/Widget-$N2/dirt"
q -C "$TMP/Widget-$N2" config user.email t@t
q -C "$TMP/Widget-$N2" config user.name T
echo more >> "$TMP/Widget-$N2/README.md"
q -C "$TMP/Widget-$N2" commit -am local
fails lab-drop.sh "$N2"                       # HEAD no remote ref can reach
q -C "$TMP/Widget-$N2" reset --hard origin/main
fails lab-drop.sh dwt1                        # a legacy fixture is not ours to destroy

lab-drop.sh "$N2" >/dev/null
ok "drop removes the worktree" "$([ -d "$TMP/Widget-$N2" ] && echo y)" ""

mv "$TASK" "$TMP/tasks/widget/done/"
lab-drop.sh "$NEW" >/dev/null
ok "drop allows a finished task" "$([ -d "$TMP/Widget-$NEW" ] && echo y)" ""
# Conversation history is small text and is wanted after the lab is gone.
ok "drop keeps the claude session dir" "$([ -d "$PROJ_NEW" ] && echo y)" y
ok "nothing left to list" "$(lab-list.sh)" ""

# --- claiming from outside the checkout --------------------------------------
# The lab is identified by its worktree, not by where the claim was invoked, so
# every project-keyed step has to be pinned the same way. The restamp is the one
# that reads its tasks dir off the cwd, and it runs after the worktree has
# already moved — an unpinned failure there leaves half a claim.
TASK239="$TMP/tasks/widget/active/N239-tidy-the-logs.md"
printf '# Tidy the logs\nWorker: main\n\nbody\n' > "$TASK239"
q -C "$TMP/tasks" add -A
q -C "$TMP/tasks" commit -m add-239
q -C "$TMP/tasks" push
N3=$(lab-new.sh host 2>/dev/null)
OUT=$(cd "$TMP" && lab-claim.sh "$N3" 239 2>/dev/null)
ok "claim works from outside the checkout" "$OUT" hlab-239-tidy-the-logs
ok "restamp keys on the lab's project, not the cwd's" \
    "$(sed -n 's/^Worker: //p' "$TASK239")" hlab-239

mv "$TASK239" "$TMP/tasks/widget/done/"
lab-drop.sh "$OUT" >/dev/null

# --- claiming a task that is still in todo/ ----------------------------------
# The claim may not move queue state, and a task in todo/ carries no Worker:
# line — the slash command's own task-claim.sh stamps it later, from inside the
# lab. So the restamp is a no-op here, and it must not reach the tasks repo:
# a stamped todo/ task would be pushed to a queue shared with everyone else.
TASK240="$TMP/tasks/widget/todo/N240-read-the-manual.md"
printf '# Read the manual\n\nbody\n' > "$TASK240"
q -C "$TMP/tasks" add -A
q -C "$TMP/tasks" commit -m add-240
q -C "$TMP/tasks" push
HEAD_BEFORE=$(git -C "$TMP/tasks" rev-parse HEAD)
N4=$(lab-new.sh host 2>/dev/null)
OUT4=$(lab-claim.sh "$N4" 240 2>/dev/null)
ok "claim works on a task still in todo/" "$OUT4" hlab-240-read-the-manual
ok "claim leaves a todo/ task unstamped" "$(grep -c '^Worker: ' "$TASK240")" 0
ok "an unstamped task reaches no commit" "$(git -C "$TMP/tasks" rev-parse HEAD)" "$HEAD_BEFORE"

mv "$TASK240" "$TMP/tasks/widget/done/"
lab-drop.sh "$OUT4" >/dev/null

# --- provisioning that fails rolls the whole lab back ------------------------
# Bringing the backend up is the provisioner's first step and seeding it the
# last, so a failure usually leaves one standing. Left there it holds the name
# against every retry while being unusable itself — the free-index scan reads it
# as a lab that exists.
: > "$TMP/stub.log"
PROVISION_FAIL=1 lab-new.sh docker >/dev/null 2>&1
ok "a failed provision leaves no worktree" "$([ -d "$TMP/Widget-dlab-tmp1" ] && echo y)" ""
ok "a failed provision destroys the container" \
    "$(grep -c '^docker rm -f widget-dlab-tmp1$' "$TMP/stub.log")" 1

report

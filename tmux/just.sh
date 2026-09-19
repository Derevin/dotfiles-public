#!/bin/bash
# Fuzzy recipe picker: merges project + global justfile recipes, runs selection

if [[ "${1:-}" == "--help" ]]; then
    echo "Fuzzy just-recipe picker merging project and global justfiles."
    echo "Usage: just.sh"
    exit 0
fi

# Check dependencies
if ! command -v just >/dev/null 2>&1; then
    echo "just not found — install from https://github.com/casey/just/releases"
    read -n1
    exit 1
fi
if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf not found — install from https://github.com/junegunn/fzf/releases"
    read -n1
    exit 1
fi

run_just() {
    local scope=$1; shift
    if [ "$scope" = global ]; then just -g "$@"; else just "$@"; fi
}

# `just --show` renders the header as `name p1 p2='default':`, and its params
# are what the picker has to fill.
recipe_params() {
    printf '%s\n' "$2" | grep -m1 "^${1}\b" |
        sed -n 's/^[^ ]* \(.*\):$/\1/p' | tr ' ' '\n' | grep -v '^[[:space:]]*$'
}

# The value a defaulted param is filled with when nothing asks: the chooser's
# first line, since a chooser leads with the answer it would pick, else the
# default the recipe itself names.
param_fill() {
    local scope=$1 recipe=$2 name=$3 default=$4 first
    first=$(run_just "$scope" "_${recipe}-${name}" 2>/dev/null | head -1)
    printf '%s' "${first:-$default}"
}

# `just.sh --preview <scope> <recipe>` — the pane beside the listing: the recipe
# as just renders it, then what Enter would pass for the params it defaults.
# A header reading `backend=''` says nothing about where a lab would land; the
# chooser, which is what knows, says host.
if [ "${1:-}" = --preview ]; then
    show=$(run_just "${2:-}" --show "${3:-}" 2>/dev/null) || exit 0
    printf '%s\n' "$show"
    fills=""
    while IFS= read -r param; do
        [[ "$param" == [\*+\$]* ]] && continue
        [[ "$param" == *"="* ]] || continue
        name="${param%%=*}"
        default="${param#*=}"
        # Nothing to fill it with is nothing to say: the recipe resolves the
        # empty value itself, or stops on it.
        fill=$(param_fill "$2" "$3" "$name" "${default//\'/}")
        [ -n "$fill" ] && fills+=" ${name}=${fill}"
    done < <(recipe_params "${3:-}" "$show")
    [ -n "$fills" ] && printf '\nenter passes:%s   (ctrl-o to choose)\n' "$fills"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# lab-lib.sh sits beside this script once installed; in the repo the tmux and
# script helpers are kept apart, and the private tmux scripts a level further.
for d in "$SCRIPT_DIR" "$SCRIPT_DIR/../scripts" "$SCRIPT_DIR/../public/scripts"; do
    [ -f "$d/lab-lib.sh" ] && { source "$d/lab-lib.sh"; break; }
done
# A miss is otherwise silent: every lab_* call expands to nothing and the caller
# degrades instead of stopping — a pane with no Claude, a recipe on the host.
declare -F lab_resolve >/dev/null || { echo "just.sh: cannot find lab-lib.sh" >&2; exit 1; }

# Foreground splits open minimal — 1 row — so a long-running recipe doesn't eat
# the window; zoom/resize the pane when the output matters. Dispatch panes size
# themselves, and pane-lib owns what they open at.
SPLIT_SIZE=1

# Build one POSIX-quoted command line from argv. `coder ssh -- argv...`
# space-joins the remote argv WITHOUT re-quoting and lets the workspace shell
# re-tokenize, so a bare `bash -c "pipeline"` gets mangled (bash -c grabs only
# the first word). Single-quoting each token makes the space-join idempotent:
# the workspace shell parses it straight back into the original words.
_coder_cmdline() {
    local a out=""
    for a in "$@"; do out+=" '${a//\'/\'\\\'\'}'"; done
    printf '%s' "$out"
}

# Run a command inside a lab's backend. Only the containerized ones route here:
# a host lab runs in the caller pane, on the host, against its worktree.
lab_exec() {
    case "$LAB_BACKEND" in
        docker) docker exec "$LAB_CONTAINER" "$@" ;;
        coder) coder ssh "$LAB_CONTAINER" -- "$(_coder_cmdline "$@")" ;;
        *) return 1 ;;
    esac
}

# The lab's path as seen from inside its backend. Docker bind-mounts the host
# path 1:1; coder workspaces use /workspace directly (no host-shape symlink).
lab_backend_dir() {
    case "$LAB_BACKEND" in
        coder) echo "/workspace" ;;
        *) echo "$LAB_WORKTREE" ;;
    esac
}

# Is a lab pane busy? Count in-backend processes whose LAB_PANE_ID env
# matches the pane. lab-shell sets this on the leader bash; any child command
# inherits it. count == 1 means only leader (idle); >1 means something
# running. count == 0 means no process tagged with this pane — either a
# legacy pane (pre-LAB_PANE_ID lab-shell) or a torn-down pane. Treat as
# busy in that case so we split a fresh pane rather than blindly send-keys
# into something that might be running.
lab_pane_busy() {
    local pane_id="$1" count
    # -z anchors the match on the value end so %1 doesn't also count %12/%13
    # (environ entries are NUL-separated, so the trailing $ binds to the value).
    count=$(lab_exec bash -c "grep -alz 'LAB_PANE_ID=$pane_id$' /proc/*/environ 2>/dev/null | wc -l" 2>/dev/null)
    # coder ssh returns CRLF, so $() leaves a trailing \r — strip every
    # non-digit before the integer test (a bare `[ 0$'\r' -ne 1 ]` errors).
    count=${count//[!0-9]/}
    # Indeterminate (empty / non-numeric / exec failed) → treat as BUSY so we
    # split a fresh pane rather than send-keys into something that may be live.
    [ -n "$count" ] || return 0
    [ "$count" -ne 1 ]
}

# Is a host pane busy? pane_current_command names the foreground process, and
# that name is "bash" both for an idle shell and for a bash script running in it
# (a workspace pane's task-watch.sh, say), where send-keys would be swallowed by
# the running program. The tty's foreground process group separates the two: an
# idle shell owns it, a foreground child does not. tpgid is the 6th field past
# the comm, stripped first because a comm can itself hold spaces and parens.
# Where procfs can't answer (Git Bash), report idle so the command-name check
# stands as the only signal.
pane_busy() {
    local pane_id="$1" pid tpgid
    pid=$(tmux display-message -t "$pane_id" -p '#{pane_pid}' 2>/dev/null)
    [ -n "$pid" ] || return 1
    tpgid=$(sed 's/^[^)]*) //' "/proc/$pid/stat" 2>/dev/null | awk '{print $6}')
    [ -n "$tpgid" ] || return 1
    [ "$tpgid" != "$pid" ]
}

# Hide per-repo recipes whose backing repo isn't checked out. A recipe opts in
# with a `# requires-repo <name>` body marker (the `@#` form is a silent no-op);
# we drop it from the listing when ~/repos/<name> is absent — so e.g. recipes
# for a given repo only appear where that repo exists. Fails open: any parse
# miss leaves the recipe visible.
#
# Per-recipe metadata (requires-repo marker, recipe identity for dedup) comes
# from one jq-parsed `just --dump` per scope — per-recipe `just --show` spawns
# make the listing visibly slow. Without jq, fall back to per-recipe shows.
HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1
declare -A p_req p_body g_req g_body

drop_missing_repos() {
    local scope="$1" listing="$2" line name show repo kept=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        name=${line%%[[:space:]]*}
        if [ "$HAVE_JQ" -eq 1 ]; then
            if [ "$scope" = global ]; then repo=${g_req[$name]:-}; else repo=${p_req[$name]:-}; fi
            [ "$repo" = "-" ] && repo=""
        else
            if [ "$scope" = global ]; then
                show=$(just -g --show "$name" 2>/dev/null)
            else
                show=$(just --show "$name" 2>/dev/null)
            fi
            repo=$(printf '%s\n' "$show" | sed -nE 's/^[[:space:]]*@?#[[:space:]]*requires-repo[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
        fi
        if [ -n "$repo" ] && [ ! -d "$HOME/repos/$repo" ]; then
            continue
        fi
        kept+="$line"$'\n'
    done <<< "$listing"
    printf '%s' "${kept%$'\n'}"
}

# Collect recipes: "source recipe  # description"
recipes=""

# Strip dispatch directives from the listing. just renders the recipe's doc
# comment as its description (`myrecipe  # background_takeover`); feeding that to
# fzf makes the directive searchable (typing "background" hits every bg recipe)
# and clutters the display. We re-parse the directive from `just --show` after
# selection, so dropping it here loses nothing. Real descriptions are kept.
strip_directives='s/[[:space:]]+#[[:space:]]*(background_takeover|background|host_only)$//'
project=$(just --list --list-heading '' --list-prefix '' 2>/dev/null | sed -E "$strip_directives")
global=$(just -g --list --list-heading '' --list-prefix '' 2>/dev/null | sed -E "$strip_directives")

if [ "$HAVE_JQ" -eq 1 ]; then
    # name<TAB>requires-repo(or -)<TAB>compact recipe JSON; the JSON doubles as
    # recipe identity for dedup (tojson escapes tabs/newlines, so TSV stays sane)
    dump_meta='.recipes | to_entries[] | [.key,
        ([.value.body[][]? | strings
          | capture("^\\s*@?#\\s*requires-repo\\s+(?<r>\\S+)").r] | first // "-"),
        (.value | tojson)] | @tsv'
    pdump=$(just --dump --dump-format json 2>/dev/null)
    gdump=$(just -g --dump --dump-format json 2>/dev/null)
    while IFS=$'\t' read -r n r b; do p_req[$n]=$r; p_body[$n]=$b; done \
        < <(jq -r "$dump_meta" <<<"$pdump" 2>/dev/null)
    while IFS=$'\t' read -r n r b; do g_req[$n]=$r; g_body[$n]=$b; done \
        < <(jq -r "$dump_meta" <<<"$gdump" 2>/dev/null)

    # A dir without its own justfile resolves the project scope to ~/.justfile
    # itself — drop the whole project side up front rather than discovering
    # per-recipe that everything is a duplicate.
    if [ -n "$project" ]; then
        psrc=$(jq -r '.source // empty' <<<"$pdump" 2>/dev/null)
        gsrc=$(jq -r '.source // empty' <<<"$gdump" 2>/dev/null)
        [ -n "$psrc" ] && [ "$psrc" = "$gsrc" ] && project=""
    fi
fi

# Drop recipes that require an absent ~/repos/<name> (see drop_missing_repos).
project=$(drop_missing_repos project "$project")
global=$(drop_missing_repos global "$global")

# Deduplicate: if a recipe name appears in both and the body is identical, drop from project (global wins)
if [ -n "$global" ] && [ -n "$project" ]; then
    dupes=$(comm -12 \
        <(echo "$project" | awk '{print $1}' | sort) \
        <(echo "$global"  | awk '{print $1}' | sort))
    for name in $dupes; do
        if [ "$HAVE_JQ" -eq 1 ]; then
            [ -n "${p_body[$name]:-}" ] && [ "${p_body[$name]:-}" = "${g_body[$name]:-}" ] || continue
        else
            [ "$(just --show "$name" 2>/dev/null)" = "$(just -g --show "$name" 2>/dev/null)" ] || continue
        fi
        project=$(echo "$project" | awk -v r="$name" '$1 != r')
    done
fi

if [ -n "$project" ]; then
    recipes=$(echo "$project" | sed 's/^/project  /')
fi
if [ -n "$global" ]; then
    if [ -n "$recipes" ]; then
        recipes="$recipes"$'\n'
    fi
    recipes="${recipes}$(echo "$global" | sed 's/^/global   /')"
fi

if [ -z "$recipes" ]; then
    echo "No recipes found (no justfile in current dir, no ~/.justfile)"
    read -n1
    exit 0
fi

# fzf picker with preview. tiebreak=begin ranks by match position — the default
# `length` tiebreak settles ties on total line length, which lets a doc comment
# two characters longer rank `target-mock` above `mock` for the query "mock".
selection=$(echo "$recipes" | fzf \
    --prompt "recipe> " \
    --header 'enter: run    ctrl-o: fill in optional args' \
    --expect=ctrl-o \
    --tiebreak=begin,length \
    --preview "\"$SCRIPT_DIR/just.sh\" --preview {1} {2}" \
    --preview-window=right:50%:wrap)

# --expect puts the accepting key on a line of its own above the selection,
# empty for a plain Enter.
ASK_OPTIONAL=0
[ "$(head -1 <<< "$selection")" = ctrl-o ] && ASK_OPTIONAL=1
selection=$(sed -n 2p <<< "$selection")
[ -z "$selection" ] && exit 0

source=$(echo "$selection" | awk '{print $1}')
recipe=$(echo "$selection" | awk '{print $2}')

# Get recipe parameters from `just --show`
if [ "$source" = "global" ]; then
    show=$(just -g --show "$recipe" 2>/dev/null)
else
    show=$(just --show "$recipe" 2>/dev/null)
fi

params=$(recipe_params "$recipe" "$show")

args=()
if [ -n "$params" ]; then
    for param in $params; do
        # Skip variadic params (*args, +args, $args)
        [[ "$param" == [\*+\$]* ]] && continue

        # Extract parameter name and default
        if [[ "$param" == *"="* ]]; then
            name="${param%%=*}"
            default="${param#*=}"
            default="${default//\'/}"
            has_default=1
        else
            name="$param"
            default=""
            has_default=0
        fi

        # A param the recipe gives a default is filled, not asked: the default
        # is the answer nearly every time, and a chooser for it is a popup with
        # one likely outcome. ctrl-o on the recipe is where the other answers
        # live — for an empty default, the recipe's own fallback decides.
        if [ "$has_default" -eq 1 ] && [ "$ASK_OPTIONAL" -eq 0 ]; then
            args+=("$(param_fill "$source" "$recipe" "$name" "$default")")
            continue
        fi

        # Check for chooser recipe: _recipe-param (provides fzf values). With
        # the dump maps, existence is a map lookup and the chooser's output
        # streams straight into fzf — the picker opens before slow probes
        # (docker/coder) finish. An empty-output chooser falls through to the
        # typed prompt: --exit-0 auto-closes the empty fzf, and the tee'd file
        # distinguishes "chooser produced nothing" from "user cancelled".
        chooser="_${recipe}-${name}"
        if [ "$HAVE_JQ" -eq 1 ]; then
            if [ "$source" = "global" ]; then chooser_def=${g_body[$chooser]:-}; else chooser_def=${p_body[$chooser]:-}; fi
            if [ -n "$chooser_def" ]; then
                ctmp=$(mktemp)
                if [ "$source" = "global" ]; then
                    val=$(just -g "$chooser" 2>/dev/null | tee "$ctmp" | fzf --prompt "$name> " --exit-0)
                else
                    val=$(just "$chooser" 2>/dev/null | tee "$ctmp" | fzf --prompt "$name> " --exit-0)
                fi
                if [ -s "$ctmp" ]; then
                    rm -f "$ctmp"
                    [ -z "$val" ] && echo "aborted" && exit 0
                    args+=("$val")
                    continue
                fi
                rm -f "$ctmp"
            fi
        else
            if [ "$source" = "global" ]; then
                chooser_output=$(just -g "$chooser" 2>/dev/null)
            else
                chooser_output=$(just "$chooser" 2>/dev/null)
            fi
            if [ -n "$chooser_output" ]; then
                val=$(echo "$chooser_output" | fzf --prompt "$name> ")
                [ -z "$val" ] && echo "aborted" && exit 0
                args+=("$val")
                continue
            fi
        fi

        # Prompt for value
        if [ -n "$default" ]; then
            printf "%s [%s]: " "$name" "$default"
            read -r val
            [ -z "$val" ] && val="$default"
        else
            printf "%s: " "$name"
            read -r val
            [ -z "$val" ] && echo "aborted" && exit 0
        fi
        args+=("$val")
    done
fi

# Build the command string
if [ "$source" = "global" ]; then
    cmd="just -g '$recipe'"
else
    cmd="just '$recipe'"
fi
for arg in "${args[@]}"; do
    cmd+=" '$arg'"
done

# Check dispatch directives. Recognized as a `@#` body marker (silent no-op,
# leaving the doc-comment slot free for descriptions) or a legacy doc comment
# above the recipe — the `^[[:space:]]*@?#` anchor matches both forms. `\b`
# after `background` keeps it from matching `background_takeover`.
BACKGROUND=0
BACKGROUND_TAKEOVER=0
HOST_ONLY=0
if echo "$show" | grep -qE '^[[:space:]]*@?#[[:space:]]*background_takeover\b'; then
    BACKGROUND_TAKEOVER=1
elif echo "$show" | grep -qE '^[[:space:]]*@?#[[:space:]]*background\b'; then
    BACKGROUND=1
fi
# host_only: skip lab routing even if the caller pane is bound to a lab.
# For recipes whose body only makes sense on the laptop (e.g. opening a VNC
# window, port-forwarding, anything talking to the local Coder server).
if echo "$show" | grep -qE '^[[:space:]]*@?#[[:space:]]*host_only\b'; then
    HOST_ONLY=1
fi

# Read caller pane ID stashed by the M-j binding (tmux global env).
# Clear TMUX so bare tmux commands reach the main (default) server,
# not the popup server we're running inside.
TMUX=
CALLER_PANE_ID=$(tmux show-environment -g JUST_CALLER 2>/dev/null | cut -d= -f2-)

# The direnv hook rides on PROMPT_COMMAND, which the non-interactive `$SHELL -c`
# behind a command-carrying pane never runs, so a backgrounded recipe
# would build with none of the worktree's .envrc (ccache base_dir, max_size).
# The send-keys paths need no such load: they type into an interactive pane that
# already sits in the target dir. Backend dispatch is lab-shell's own business.
DIRENV_LOAD='eval "$(direnv export bash)"; '

# Dispatch to target pane if running inside tmux popup with caller context
if [ -n "$CALLER_PANE_ID" ]; then
    # Which side a dispatch pane opens on. The foreground splits further down
    # ask for themselves, against whichever pane they end up anchored to.
    SPLIT_BEFORE=$(pane_split_before "$CALLER_PANE_ID")

    # If the caller pane is bound to a containerized lab, route dispatch through
    # lab-shell so commands run inside the right container at the right cwd.
    # Global recipes always run on the host — by definition they're not project-local.
    # Recipes with `# host_only` also stay on the host regardless of caller binding.
    #
    # The gate is the BACKEND, not @lab being set: a host lab sets @lab too, and
    # its recipes belong in the caller pane, on the host, against its worktree —
    # which is where the popup's $PWD already points.
    LAB=""
    if [ "$source" != "global" ] && [ "$HOST_ONLY" -eq 0 ]; then
        LAB=$(tmux show-options -pvt "$CALLER_PANE_ID" @lab 2>/dev/null)
    fi
    if [ -n "$LAB" ]; then
        # "cannot resolve" and "host lab" are not the same answer. Falling back
        # to the host for both would run a build on the laptop, against the
        # popup's $PWD, with nothing to say it never entered the container — the
        # case a lab dropped from another pane leaves behind.
        if ! lab_resolve "$LAB" 2>/dev/null; then
            tmux display-message -t "$CALLER_PANE_ID" "just: pane is bound to '$LAB', which does not resolve — not dispatching"
            exit 1
        fi
        [ "${LAB_BACKEND:-}" = host ] && LAB=""
    fi

    if [[ $BACKGROUND -eq 1 || $BACKGROUND_TAKEOVER -eq 1 ]] && [ -n "$LAB" ]; then
        # One arm for both markers: what separates them is takeover's willingness
        # to type into an idle caller, and a caller bound to a backend has no
        # host shell to type into.
        pane_dispatch "$CALLER_PANE_ID" "lab-shell $LAB \"$cmd\"" "" "$SPLIT_BEFORE"
    elif [[ $BACKGROUND_TAKEOVER -eq 1 ]]; then
        # Background-takeover: send to caller pane if idle bash in single-pane window; else dispatch pane
        c_win_panes=$(tmux display-message -t "$CALLER_PANE_ID" -p '#{window_panes}')
        c_pane_cmd=$(tmux display-message -t "$CALLER_PANE_ID" -p '#{pane_current_command}')
        if [[ $c_win_panes -eq 1 && "$c_pane_cmd" =~ ^(bash|zsh)$ ]] && ! pane_busy "$CALLER_PANE_ID"; then
            tmux send-keys -t "$CALLER_PANE_ID" "cd '$PWD' && $cmd" Enter
        else
            pane_dispatch "$CALLER_PANE_ID" "cd '$PWD' && $DIRENV_LOAD$cmd" "" "$SPLIT_BEFORE" "$PWD"
        fi
    elif [[ $BACKGROUND -eq 1 ]]; then
        pane_dispatch "$CALLER_PANE_ID" "cd '$PWD' && $DIRENV_LOAD$cmd" "" "$SPLIT_BEFORE" "$PWD"
    elif [ -n "$LAB" ]; then
        # Foreground in a lab backend. pane_current_command on the host
        # is always 'docker' (or 'coder'), so use tmux options + in-backend
        # env-based busy check:
        #   - Normalize caller: if caller is itself a child pane, treat its
        #     @just_caller as the "main" pane (so child→child dispatches stay
        #     anchored to the original claude pane).
        #   - Reuse an idle tagged child if one exists.
        #   - Else, if main is busy, split a new child anchored to main.
        #   - Else, send-keys directly to main's container bash.
        # Backend-shaped cwd: docker uses host paths via bind mount, coder
        # uses /workspace directly (no host-shape symlink there).
        lab_dir=$(lab_backend_dir)
        main_pane=$(tmux show-options -pvt "$CALLER_PANE_ID" @just_caller 2>/dev/null)
        main_pane="${main_pane:-$CALLER_PANE_ID}"

        caller_target=$(tmux display-message -t "$main_pane" -p '#{session_name}:#{window_index}')
        tagged_pane=""
        while read -r pid; do
            [[ "$(tmux show-options -pvt "$pid" @just_caller 2>/dev/null)" == "$main_pane" ]] || continue
            lab_pane_busy "$pid" && continue
            tagged_pane="$pid"; break
        done < <(tmux list-panes -t "$caller_target" -F '#{pane_id}')

        if [ -n "$tagged_pane" ]; then
            tmux send-keys -t "$tagged_pane" "cd '$lab_dir' && $cmd" Enter
        elif lab_pane_busy "$main_pane"; then
            pane_split -v -d -l "$SPLIT_SIZE" --caller "$main_pane" \
                --lab "$LAB" --backend "$LAB_BACKEND" \
                "$main_pane" "lab-shell --interactive-after $LAB \"$cmd\"" >/dev/null
        else
            tmux send-keys -t "$main_pane" "cd '$lab_dir' && $cmd" Enter
        fi
    else
        # Foreground (default): interactive dispatch to caller's pane
        caller_info=$(tmux display-message -t "$CALLER_PANE_ID" \
            -p '#{session_name}|#{window_index}|#{pane_index}|#{pane_current_command}')
        IFS='|' read -r c_sess c_win_idx c_pane_idx c_pane_cmd <<< "$caller_info"
        caller_target="$c_sess:$c_win_idx"

        # Check for a tagged idle pane from a previous recipe run
        tagged_pane=$(tmux list-panes -t "$caller_target" \
            -F '#{pane_id} #{pane_current_command}' \
            | while read -r pid pcmd; do
                if [[ "$(tmux show-options -pvt "$pid" @just_caller 2>/dev/null)" == "$CALLER_PANE_ID" ]] \
                    && [[ "$pcmd" =~ ^(bash|zsh)$ ]] && ! pane_busy "$pid"; then
                    echo "$pid"; break
                fi
            done)
        if [ -n "$tagged_pane" ]; then
            tmux send-keys -t "$tagged_pane" "cd '$PWD' && $cmd" Enter
        elif [[ "$c_pane_cmd" =~ ^(bash|zsh)$ ]] && ! pane_busy "$CALLER_PANE_ID"; then
            tmux send-keys -t "$CALLER_PANE_ID" "cd '$PWD' && $cmd" Enter
        else
            target=$(pane_split -v -d -l "$SPLIT_SIZE" -c "$PWD" \
                --caller "$CALLER_PANE_ID" "$CALLER_PANE_ID")
            tmux send-keys -t "$target" "cd '$PWD' && $cmd" Enter
        fi
    fi
else
    # No caller context (manual run): execute inline
    echo "--- just $recipe ${args[*]} ---"
    if [ "$source" = "global" ]; then
        just -g "$recipe" "${args[@]}"
    else
        just "$recipe" "${args[@]}"
    fi
    echo ""
    echo "[press any key to close]"
    read -n1
fi

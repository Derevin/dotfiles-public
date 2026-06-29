#!/bin/bash
# Fuzzy recipe picker: merges project + global justfile recipes, runs selection

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

# Worktree backend config (private; absent on public installs → empty defaults).
WT_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/worktree.conf"
[ -f "$WT_CONF" ] && . "$WT_CONF"
WT_CONTAINER_PREFIX="${WT_CONTAINER_PREFIX:-}"
WT_DOCKER_WORKDIR_PREFIX="${WT_DOCKER_WORKDIR_PREFIX:-}"

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

# Run a command inside a worktree backend. Backend derived from slot prefix:
# d → docker, c → coder.
wt_exec() {
    local wt="$1"; shift
    case "${wt:0:1}" in
        d) docker exec "${WT_CONTAINER_PREFIX}$wt" "$@" ;;
        c) coder ssh "${WT_CONTAINER_PREFIX}$wt" -- "$(_coder_cmdline "$@")" ;;
        *) return 1 ;;
    esac
}

# Worktree path inside the backend — backend-shaped. Docker bind-mounts the
# host path 1:1; coder workspaces use /workspace directly (no host-shape symlink).
wt_worktree() {
    local wt="$1"
    case "${wt:0:1}" in
        c) echo "/workspace" ;;
        *) echo "${WT_DOCKER_WORKDIR_PREFIX}$wt" ;;
    esac
}

# Is a worktree pane busy? Count in-backend processes whose WT_PANE_ID env
# matches the pane. wt-shell sets this on the leader bash; any child command
# inherits it. count == 1 means only leader (idle); >1 means something
# running. count == 0 means no process tagged with this pane — either a
# legacy pane (pre-WT_PANE_ID wt-shell) or a torn-down pane. Treat as
# busy in that case so we split a fresh pane rather than blindly send-keys
# into something that might be running.
wt_pane_busy() {
    local pane_id="$1" wt="$2" count
    # -z anchors the match on the value end so %1 doesn't also count %12/%13
    # (environ entries are NUL-separated, so the trailing $ binds to the value).
    count=$(wt_exec "$wt" bash -c "grep -alz 'WT_PANE_ID=$pane_id$' /proc/*/environ 2>/dev/null | wc -l" 2>/dev/null)
    # coder ssh returns CRLF, so $() leaves a trailing \r — strip every
    # non-digit before the integer test (a bare `[ 0$'\r' -ne 1 ]` errors).
    count=${count//[!0-9]/}
    # Indeterminate (empty / non-numeric / exec failed) → treat as BUSY so we
    # split a fresh pane rather than send-keys into something that may be live.
    [ -n "$count" ] || return 0
    [ "$count" -ne 1 ]
}

# Send command to first idle pane (>= min index) in a window, or split if all busy
# Prefers panes in the spatial direction matching SPLIT_BEFORE
send_to_idle_or_split() {
    local t="$1" min="$2" target="" sort_flag="-rn"
    [ -n "$SPLIT_BEFORE" ] && sort_flag="-n"
    target=$(tmux list-panes -t "$t" -F '#{pane_top} #{pane_index} #{pane_current_command}' \
        | sort $sort_flag \
        | awk -v m="$min" '$2 >= m && $3 ~ /^(bash|zsh)$/ {print $2; exit}')
    if [ -n "$target" ]; then
        target="$t.$target"
    else
        target=$(tmux split-window -t "$t" -v $SPLIT_BEFORE -l 25% -d -P -F '#{pane_id}' -c "$PWD")
    fi
    tmux send-keys -t "$target" "cd '$PWD' && $cmd" Enter
}

# Hide per-repo recipes whose backing repo isn't checked out. A recipe opts in
# with a `# requires-repo <name>` body marker (the `@#` form is a silent no-op),
# which `just --show` surfaces; we drop it from the listing when ~/repos/<name>
# is absent — so e.g. recipes for a given repo only appear where that repo
# exists. Fails open: any --show/parse miss leaves the recipe visible.
drop_missing_repos() {
    local scope="$1" listing="$2" line name show repo kept=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        name=${line%%[[:space:]]*}
        if [ "$scope" = global ]; then
            show=$(just -g --show "$name" 2>/dev/null)
        else
            show=$(just --show "$name" 2>/dev/null)
        fi
        repo=$(printf '%s\n' "$show" | sed -nE 's/^[[:space:]]*@?#[[:space:]]*requires-repo[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
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

# Drop recipes that require an absent ~/repos/<name> (see drop_missing_repos).
project=$(drop_missing_repos project "$project")
global=$(drop_missing_repos global "$global")

# Deduplicate: if a recipe name appears in both and the body is identical, drop from project (global wins)
if [ -n "$global" ] && [ -n "$project" ]; then
    dupes=$(comm -12 \
        <(echo "$project" | awk '{print $1}' | sort) \
        <(echo "$global"  | awk '{print $1}' | sort))
    for name in $dupes; do
        if [ "$(just --show "$name" 2>/dev/null)" = "$(just -g --show "$name" 2>/dev/null)" ]; then
            project=$(echo "$project" | awk -v r="$name" '$1 != r')
        fi
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

# fzf picker with preview
selection=$(echo "$recipes" | fzf \
    --prompt "recipe> " \
    --preview 'src={1}; recipe={2}; if [ "$src" = "global" ]; then just -g --show "$recipe" 2>/dev/null; else just --show "$recipe" 2>/dev/null; fi' \
    --preview-window=right:50%:wrap)

[ -z "$selection" ] && exit 0

source=$(echo "$selection" | awk '{print $1}')
recipe=$(echo "$selection" | awk '{print $2}')

# Get recipe parameters from `just --show`
if [ "$source" = "global" ]; then
    show=$(just -g --show "$recipe" 2>/dev/null)
else
    show=$(just --show "$recipe" 2>/dev/null)
fi

# Extract parameter names from the recipe header (grep for it — head -1 may hit a comment)
header=$(echo "$show" | grep -m1 "^${recipe}\\b")
params=$(echo "$header" | sed -n 's/^[^ ]* \(.*\):$/\1/p' | tr ' ' '\n' | grep -v '^\s*$')

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
        else
            name="$param"
            default=""
        fi

        # Check for chooser recipe: _recipe-param (provides fzf values)
        chooser="_${recipe}-${name}"
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
# host_only: skip wt-shell routing even if caller pane is bound to a workspace.
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

# Dispatch to target pane if running inside tmux popup with caller context
if [ -n "$CALLER_PANE_ID" ]; then
    # Determine split direction: explicit @split-dir tag wins, else position heuristic
    split_dir=$(tmux show-options -pvt "$CALLER_PANE_ID" @split-dir 2>/dev/null)
    SPLIT_BEFORE=""
    if [[ "$split_dir" == "up" ]]; then
        SPLIT_BEFORE="-b"
    elif [[ "$split_dir" != "down" ]]; then
        # Fallback: split upward if caller is small and in the upper half
        pane_pos=$(tmux display-message -t "$CALLER_PANE_ID" -p '#{pane_top} #{pane_height} #{window_height}')
        read -r ptop pheight wheight <<< "$pane_pos"
        if (( ptop < wheight / 2 && pheight <= wheight / 2 )); then
            SPLIT_BEFORE="-b"
        fi
    fi

    # If the caller pane is bound to a containerized worktree, route dispatch through
    # wt-shell so commands run inside the right container at the right cwd.
    # Global recipes always run on the host — by definition they're not project-local.
    # Recipes with `# host_only` also stay on the host regardless of caller binding.
    WT=""
    if [ "$source" != "global" ] && [ "$HOST_ONLY" -eq 0 ]; then
        WT=$(tmux show-options -pvt "$CALLER_PANE_ID" @wt 2>/dev/null)
    fi

    if [[ $BACKGROUND_TAKEOVER -eq 1 ]]; then
        if [ -n "$WT" ]; then
            tmux split-window -d -v $SPLIT_BEFORE -l 25% -t "$CALLER_PANE_ID" "wt-shell $WT \"$cmd\""
        else
            # Background-takeover: send to caller pane if idle bash in single-pane window; else ephemeral split
            c_win_panes=$(tmux display-message -t "$CALLER_PANE_ID" -p '#{window_panes}')
            c_pane_cmd=$(tmux display-message -t "$CALLER_PANE_ID" -p '#{pane_current_command}')
            if [[ $c_win_panes -eq 1 && "$c_pane_cmd" =~ ^(bash|zsh)$ ]]; then
                tmux send-keys -t "$CALLER_PANE_ID" "cd '$PWD' && $cmd" Enter
            else
                tmux split-window -d -v $SPLIT_BEFORE -l 25% -t "$CALLER_PANE_ID" -c "$PWD" "cd '$PWD' && $cmd"
            fi
        fi
    elif [[ $BACKGROUND -eq 1 ]]; then
        if [ -n "$WT" ]; then
            tmux split-window -d -v $SPLIT_BEFORE -l 25% -t "$CALLER_PANE_ID" "wt-shell $WT \"$cmd\""
        else
            # Background: ephemeral split that auto-closes when command finishes
            tmux split-window -d -v $SPLIT_BEFORE -l 25% -t "$CALLER_PANE_ID" -c "$PWD" "cd '$PWD' && $cmd"
        fi
    elif [ -n "$WT" ]; then
        # Foreground in a worktree backend. pane_current_command on the host
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
        wt_dir=$(wt_worktree "$WT")
        main_pane=$(tmux show-options -pvt "$CALLER_PANE_ID" @just_caller 2>/dev/null)
        main_pane="${main_pane:-$CALLER_PANE_ID}"

        caller_target=$(tmux display-message -t "$main_pane" -p '#{session_name}:#{window_index}')
        tagged_pane=""
        while read -r pid; do
            [[ "$(tmux show-options -pvt "$pid" @just_caller 2>/dev/null)" == "$main_pane" ]] || continue
            wt_pane_busy "$pid" "$WT" && continue
            tagged_pane="$pid"; break
        done < <(tmux list-panes -t "$caller_target" -F '#{pane_id}')

        if [ -n "$tagged_pane" ]; then
            tmux send-keys -t "$tagged_pane" "cd '$wt_dir' && $cmd" Enter
        elif wt_pane_busy "$main_pane" "$WT"; then
            target=$(tmux split-window -t "$main_pane" -v $SPLIT_BEFORE -l 25% -d -P -F '#{pane_id}' \
                "wt-shell --interactive-after $WT \"$cmd\"")
            tmux set-option -pt "$target" @wt "$WT"
            tmux set-option -pt "$target" @just_caller "$main_pane"
        else
            tmux send-keys -t "$main_pane" "cd '$wt_dir' && $cmd" Enter
        fi
    else
        # Foreground (default): interactive dispatch to caller's pane
        caller_info=$(tmux display-message -t "$CALLER_PANE_ID" \
            -p '#{session_name}|#{window_index}|#{window_name}|#{pane_index}|#{pane_current_command}')
        IFS='|' read -r c_sess c_win_idx c_win_name c_pane_idx c_pane_cmd <<< "$caller_info"
        caller_target="$c_sess:$c_win_idx"

        if [[ "$c_win_name" =~ ^i[0-9]*[1-9]$ ]]; then
            # Inspect window: send to first idle console pane (3+)
            send_to_idle_or_split "$caller_target" 3
        else
            # Check for a tagged idle pane from a previous recipe run
            tagged_pane=$(tmux list-panes -t "$caller_target" \
                -F '#{pane_id} #{pane_current_command}' \
                | while read -r pid pcmd; do
                    if [[ "$(tmux show-options -pvt "$pid" @just_caller 2>/dev/null)" == "$CALLER_PANE_ID" ]] \
                        && [[ "$pcmd" =~ ^(bash|zsh)$ ]]; then
                        echo "$pid"; break
                    fi
                done)
            if [ -n "$tagged_pane" ]; then
                tmux send-keys -t "$tagged_pane" "cd '$PWD' && $cmd" Enter
            elif [[ "$c_pane_cmd" =~ ^(bash|zsh)$ ]]; then
                tmux send-keys -t "$CALLER_PANE_ID" "cd '$PWD' && $cmd" Enter
            else
                target=$(tmux split-window -t "$CALLER_PANE_ID" -v $SPLIT_BEFORE -l 25% -d -P -F '#{pane_id}' -c "$PWD")
                tmux set-option -pt "$target" @just_caller "$CALLER_PANE_ID"
                tmux send-keys -t "$target" "cd '$PWD' && $cmd" Enter
            fi
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

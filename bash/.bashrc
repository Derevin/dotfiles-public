# Machine-specific env (loaded before interactive check so tools like
# VSCode CMake extension see these variables in non-interactive shells)
[[ -f ~/.bashrc.local ]] && . ~/.bashrc.local

# Local scripts
[[ -d ~/.local/bin ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && PATH="$HOME/.local/bin:$PATH"

# Rust (rustup)
[[ -f ~/.cargo/env ]] && . ~/.cargo/env

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# History
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000

# Check window size after each command
shopt -s checkwinsize

# Make less more friendly for non-text input files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Enable color support of ls and add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls -A --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias python='python3'

# Enable programmable completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Auto-start tmux (just for panes/windows, no session persistence).
# Skipped inside coder workspaces — the outer laptop tmux is already the multiplexer there.
if [[ $- == *i* ]] && command -v tmux &>/dev/null && [[ -z "$TMUX" ]] && [[ -z "$NO_TMUX" ]] && [[ -z "$VSCODE_RESOLVING_ENVIRONMENT" ]] && [[ -z "$CODER_AGENT_TOKEN" ]]; then
    _tmux_cleanup() {
        trap '' EXIT HUP TERM
        tmux kill-session -t "$$" 2>/dev/null
        tmux -L popup kill-server 2>/dev/null
    }
    trap _tmux_cleanup EXIT HUP

    # MSYS2: find and kill orphaned ConPTY processes (conhost.exe --headless,
    # cygwin-console-helper) whose parent no longer exists — leftover from tmux
    # pane teardown. PowerShell avoids wmic/taskkill parsing issues in MSYS2 bash.
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "mingw"* ]]; then
        _kill_conpty_orphans() {
            local _s=/tmp/_conpty_cleanup_$$.ps1
            cat > "$_s" << 'PS'
$d = { -not (Get-Process -Id $_.ParentProcessId -ErrorAction SilentlyContinue) }
Get-CimInstance Win32_Process -Filter "Name='conhost.exe' AND CommandLine LIKE '%--headless%'" |
    Where-Object $d | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name='cygwin-console-helper.exe'" |
    Where-Object $d | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
PS
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$_s")" 2>/dev/null
            rm -f "$_s"
        }
        # Startup: clean orphans from previous crashed sessions (background)
        _kill_conpty_orphans &
    fi

    tmux new-session -d -s "$$" 2>/dev/null
    # base-index race: a tab racing the server's config load lands its first
    # window at 0 (slow MSYS config eval makes this Windows-only). Bump 0->1.
    tmux move-window -d -s "$$:0" -t "$$:1" 2>/dev/null
    tmux attach-session -t "$$" 2>/dev/null
    while tmux has-session -t "$$" 2>/dev/null; do
        sleep 0.3
        tmux attach-session -t "$$" 2>/dev/null
    done

    # Post-loop: outer shell healthy here — reliable cleanup point
    [[ "$OSTYPE" == "msys" || "$OSTYPE" == "mingw"* ]] && _kill_conpty_orphans
    tmux -L popup kill-server 2>/dev/null
    exit 0
fi

shopt -s no_empty_cmd_completion

PROMPT_KEEP=1  # full dirs to keep before basename

__fish_pwd() {
	local p="${PWD/#$HOME/\~}"
	if [[ "$p" == "~" || "$p" == "/" ]]; then
		printf '%s' "$p"
		return
	fi
	local IFS='/'
	local -a parts
	read -ra parts <<< "$p"
	local n=${#parts[@]} keep=$((PROMPT_KEEP + 1))
	if (( n <= keep )); then
		printf '%s' "$p"
		return
	fi
	local r="${parts[0]}"
	for (( i=1; i < n-keep; i++ )); do
		r+="/${parts[i]:0:2}"
	done
	for (( i=n-keep; i < n; i++ )); do
		r+="/${parts[i]}"
	done
	printf '%s' "$r"
}

PS1='\[\033[6 q\]'             # steady-bar cursor; TUIs/tmux otherwise leave a block
PS1="$PS1"'\[\033]0;$TITLEPREFIX:$PWD\007\]' # set window title
PS1="$PS1"'\[\033[33m\]'       # change to brownish yellow
PS1="$PS1"'$(__fish_pwd)'      # fish-style abbreviated path

# Git prompt integration (platform-specific paths)
if test -z "$WINELOADERNOEXEC"; then
	if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "mingw"* ]]; then
		# Git for Windows
		GIT_EXEC_PATH="$(git --exec-path 2>/dev/null)"
		COMPLETION_PATH="${GIT_EXEC_PATH%/libexec/git-core}"
		COMPLETION_PATH="${COMPLETION_PATH%/lib/git-core}"
		COMPLETION_PATH="$COMPLETION_PATH/share/git/completion"
	else
		# Linux
		COMPLETION_PATH="/usr/share/git-core/contrib/completion"
		[ -d "$COMPLETION_PATH" ] || COMPLETION_PATH="/usr/share/bash-completion/completions"
	fi

	if test -f "$COMPLETION_PATH/git-completion.bash"; then
		. "$COMPLETION_PATH/git-completion.bash" 2>/dev/null
	fi
	__git_branch() {
		local b
		b="$(git symbolic-ref --short HEAD 2>/dev/null)" \
			|| b="$(git rev-parse --short HEAD 2>/dev/null)" \
			|| return
		printf ' (%s)' "$b"
	}
	PS1="$PS1"'\[\033[36m\]'  # change color to cyan
	PS1="$PS1"'$(__git_branch)'
fi

PS1="$PS1"'\[\033[0m\]'        # change color
PS1="$PS1"'$ '                 # prompt: always $

export PS1

# direnv: load per-directory .envrc (e.g. a per-worktree ccache env). Last in
# the file so its PROMPT_COMMAND hook installs after the prompt is built. The
# interactive pane shell loads .envrc before launching claude, so claude's
# (non-interactive) shells inherit the env too.
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"


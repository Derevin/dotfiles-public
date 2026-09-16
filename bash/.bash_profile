test -f ~/.profile && . ~/.profile

# Start in home dir (some terminals default to install dir).
# Skip when:
# - already in tmux (tmux controls the starting dir)
# - inside a coder workspace (lab-shell already cd'd to the worktree dir before invoking bash -l)
# - inside a container (same: lab-shell's `docker exec -w` set the cwd)
[[ -z "$TMUX" ]] && [[ -z "$CODER_AGENT_TOKEN" ]] && [[ -z "$IN_CONTAINER" ]] && cd ~

test -f ~/.bashrc && . ~/.bashrc

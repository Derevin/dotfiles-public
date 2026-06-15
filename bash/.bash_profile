test -f ~/.profile && . ~/.profile

# Start in home dir (some terminals default to install dir).
# Skip when:
# - already in tmux (tmux controls the starting dir)
# - inside a coder workspace (wt-shell already cd'd to the worktree dir before invoking bash -l)
[[ -z "$TMUX" ]] && [[ -z "$CODER_AGENT_TOKEN" ]] && cd ~

test -f ~/.bashrc && . ~/.bashrc

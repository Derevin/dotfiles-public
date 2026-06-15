# dotfiles

Cross-platform (Linux · WSL · Windows) personal dotfiles. This is the **public subset** of a larger
private setup, so a few things ship as templates rather than as my actual config.

## Install

Clone to `~/repos/dotfiles` (the installer expects that path), then run it:

```sh
git clone https://github.com/Derevin/dotfiles-public.git ~/repos/dotfiles
cd ~/repos/dotfiles
./dotfiles_install.py --dry-run   # preview
./dotfiles_install.py             # symlink everything into place
```

It symlinks each config to its home location and applies GNOME keybindings
where applicable (a no-op elsewhere). It's idempotent — re-run any time.

The CLI tools the configs expect (`nvim`, `fzf`, `ripgrep`, `just`, `delta`,
`tmux`, `micro`) aren't bundled — install them with your package manager.

## What's inside

- `bash/` — shell config, prompt, a direnv hook
- `nvim/` — Neovim config (lazy.nvim)
- `tmux/` — tmux config and an Alt-driven pane/window workflow (`cc-*`, worktree dispatch)
- `alacritty/`, `windows-terminal/` — terminal config per platform
- `micro/` — the micro editor
- `claude/` — global Claude Code config: `CLAUDE.md`, skills, commands
- `scripts/` — workflow tooling (sync, project resolution, a task queue, a context store)
- `just/justfile` — global `just` recipes

## Task queue & context store

Some shipped scripts and skills (`task-*.sh`, `context-*.sh`, `/list-tasks`,
`/pick-task`) drive two personal, file-based systems kept in **separate** repos
(not included here):

- **Tasks** — a markdown task queue under `~/repos/tasks/<project>/`.
- **Context** — per-project glossaries and decision records under `~/repos/context/<project>/`.

Point them at your own repos in `repos.conf`. Without those repos the tooling
simply has nothing to act on.

## Config templates

`repos.conf` and `projects.conf` ship as commented templates — add your own
sibling repos and project-name mappings.

# Windows, WSL and Git Bash gotchas

Applies only when the active platform is Windows Terminal, WSL, or MSYS2/Git Bash.
Inert on native Linux.

**Windows reads a separate clone.** Native Windows apps (Windows Terminal) read
symlinks created by a second clone under `/mnt/c/Users/<user>/repos/dotfiles`, not
the WSL one. Editing `windows-terminal/settings.json` in the WSL repo does not
reach WT: commit and push from WSL, `git pull` in the Windows clone, then restart
WT — a write over the `/mnt/c` 9P mount may not trip its file watcher.

**WSL `vmIdleTimeout`.** `wsl/.wslconfig` shuts the VM down 5 minutes after the
last distro exits. Repos live inside WSL (`~/repos/`) for native I/O speed.

**MSYS2 git + pipe groups.** `{ git ...; git ...; } | pager` corrupts the terminal
for `less`. Capture into a variable first, then pipe. The same applies to
`function | fzf`, where fzf's TUI breaks entirely.

**Windows Terminal Ctrl+Backspace.** [microsoft/terminal#16889](https://github.com/microsoft/terminal/issues/16889)
mangles ESC+DEL in `sendInput`.

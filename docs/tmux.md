# tmux gotchas

Hard-won behaviour of tmux itself. Worth a read before editing `tmux/.tmux*.conf`
or a script that drives tmux (`tmux/cc-*.sh`, anything spawning popups or hooks).

**Terminal type.** `.tmux-base.conf` prefers `tmux-256color` (it has `Sync`,
synchronized output, which fixes irregular redraw and cursor flicker in fzf and
micro, plus `Ss`/`Se` cursor styling) and falls back via `if-shell` to
`screen-256color`, because `tmux-256color` terminfo is missing on Git Bash.
`default-terminal` only applies to new panes — restart the server to pick it up.

**Pane targeting.** Use fully qualified `session:window.pane` in scripts (`cc:1.1`).

**Popup close keys can't be rebound** (3.4+). Popups pass all input to the command
and consult no key table. Use `-E` so the command's own quit key closes the popup.

**Popup server isolation.** Popups run on a separate server (`-L popup`). A script
inside a popup must use `TMUX= tmux ...` to reach the main server — bare `tmux`
inherits `$TMUX` from the popup server.

**Hook `$var` expansion.** tmux expands `$var` in hook commands, even
single-quoted, silently emptying shell loop variables. Inline the commands instead
of looping. Diagnose with `tmux show-hooks -g`, which shows the stored
post-expansion form.

**`run-shell` leaks in hooks.** The shell command text leaks into the active pane,
both with `-b` and in the foreground; no redirect prevents it. Chain native tmux
commands with `;` in an `if-shell` action instead — no shell subprocess, nothing
leaks.

**Format expansion.** `run-shell` expands `#{...}` in its shell-command;
`display-popup` does not. The double-expansion trap is
`display-message -p "#{pane_id}"` — escape with `##` to defer expansion.

**Removing a binding.** Just delete the line. Don't add an explicit `unbind -n`; a
stale binding until the next server restart is fine.

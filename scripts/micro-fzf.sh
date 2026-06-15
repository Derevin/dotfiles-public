#!/usr/bin/env bash
# Telescope-style fuzzy finders for micro, driven from init.lua.
#   files : pick a file   (rg --files | fzf)            -> prints "path"
#   grep  : live grep     (rg reloaded on each keystroke) -> prints "path:line:col:text"
# init.lua binds Ctrl-P -> files, Ctrl-G -> grep and opens the selection.
# Usage: micro-fzf.sh files|grep

set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Telescope-style file finder / live grep for micro; prints the selection."
    echo "Usage: micro-fzf.sh files|grep"
    exit 0
fi

# Default layout = prompt at the bottom, results above it (classic fzf look).
fzf_opts=(--preview-window 'right,55%')

case "${1:-files}" in
    files)
        # rg --files respects .gitignore and skips hidden/.git, like Telescope's default.
        rg --files 2>/dev/null \
            | fzf "${fzf_opts[@]}" --prompt 'files> ' --preview 'cat -- {} 2>/dev/null'
        ;;
    grep)
        rg_cmd='rg --column --line-number --no-heading --color=always --smart-case --'
        # Empty until you type, then reload rg per keystroke — true live grep.
        : | fzf "${fzf_opts[@]}" --ansi --disabled --prompt 'grep> ' --delimiter ':' \
                --bind "change:reload:$rg_cmd {q} || true" \
                --preview 'cat -- {1} 2>/dev/null' --preview-window 'right,55%,+{2}'
        ;;
    *)
        echo "micro-fzf.sh: unknown mode '${1:-}' (use files|grep)" >&2
        exit 2
        ;;
esac

# fzf exits non-zero on Escape / no match — that's expected: output is empty and
# micro just does nothing. Never propagate it as an error to the caller.
exit 0

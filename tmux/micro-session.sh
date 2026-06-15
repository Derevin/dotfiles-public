#!/usr/bin/env bash
# Launch micro, reopening the tabs last open in this directory (per-dir store).
# Usage: micro-session.sh [file...]

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Launch micro, reopening the tabs last open in this dir when none is given."
    echo "Usage: micro-session.sh [file...]"
    exit 0
fi

# The popup runs us directly — no interactive shell, so the bash prompt's
# steady-bar cursor escape never fires and micro inherits the previous program's
# block. Assert it ourselves before handing off.
[ -t 1 ] && printf '\033[6 q'

# Explicit files always win.
if [[ $# -gt 0 ]]; then
    exec micro "$@"
fi

# Reopen the tabs last open in this directory (skipping any since deleted).
targets=()
while IFS= read -r f; do
    [[ -n "$f" && -f "$f" ]] && targets+=("$f")
done < <(micro-lastfile.sh get "$PWD")

if [[ ${#targets[@]} -gt 0 ]]; then
    exec micro "${targets[@]}"
fi

exec micro

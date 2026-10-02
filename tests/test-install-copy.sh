#!/usr/bin/env bash
# Tests the installer's copy table: files that must be materialized as real files
# instead of symlinked. WSL refuses to read .wslconfig through a reparse point, so
# it is copied, not linked. Covers symlink replacement, refresh-on-change, dry-run.
#
# Hermetic: a throwaway HOME with a fake source file; no touching the user's tree.
#
# Usage: test-install-copy.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Test the installer's copy table (copy-not-symlink) in dotfiles_install.py."
    echo "Usage: test-install-copy.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
PUBLIC_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# cd off the repo root so PYTHONPATH (not cwd) resolves the public module — the
# root holds a same-named private composer that would otherwise shadow it.
cd "$TMP"

HOME="$TMP" PYTHONPATH="$PUBLIC_DIR" python3 - "$TMP" > "$TMP/out.sh" 2>"$TMP/err" <<'PY'
import sys
from pathlib import Path
import dotfiles_install as d

tmp = Path(sys.argv[1])
src = tmp / "repo/.wslconfig"
src.parent.mkdir(parents=True, exist_ok=True)
src.write_text("[wsl2]\nmemory=11GB\n")
dst = tmp / ".wslconfig"

# The old install left a symlink here; copy_file must replace it with a real file.
dst.symlink_to(src)
d.copy_file(src, dst, dry_run=False)
print("after_is_symlink=%d" % int(dst.is_symlink()))
print("content_ok=%d" % int(dst.read_text() == src.read_text()))

# A changed source refreshes the copy.
src.write_text("[wsl2]\nmemory=12GB\n")
d.copy_file(src, dst, dry_run=False)
print("refreshed=%d" % int(dst.read_text() == src.read_text()))

# dry-run touches nothing.
src.write_text("[wsl2]\nmemory=13GB\n")
d.copy_file(src, dst, dry_run=True)
print("dryrun_noop=%d" % int(dst.read_text() != src.read_text()))

# .wslconfig is in the copy table, not the symlink table.
print("in_copy=%d" % int(".wslconfig" in [dst for _, dst in d.WINDOWS_COPY]))
print("not_linked=%d" % int(".wslconfig" not in [dst for _, dst in d.WINDOWS_ONLY]))
PY
source "$TMP/out.sh" 2>/dev/null || true

ok "symlink replaced by real file" "${after_is_symlink:-}" "0"
ok "copied content matches source" "${content_ok:-}"      "1"
ok "changed source refreshes copy" "${refreshed:-}"       "1"
ok "dry-run makes no change"        "${dryrun_noop:-}"      "1"
ok ".wslconfig is in copy table"    "${in_copy:-}"          "1"
ok ".wslconfig not in link table"   "${not_linked:-}"       "1"

report

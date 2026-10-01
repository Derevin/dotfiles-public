#!/usr/bin/env bash
# Tests the installer's external-repo link tables: the repos.conf `links=<file>`
# marker, the two-column table parser, and that a present repo's declared symlinks
# are created through the normal link pipeline. A missing table warns; a repo that
# isn't on disk contributes nothing.
#
# Hermetic: a throwaway HOME with a fake extra repo under it; no network, no real
# repos.conf, no touching the user's tree.
#
# Usage: test-install-links.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Test external-repo link tables in dotfiles_install.py (links= marker, table parse, linking)."
    echo "Usage: test-install-links.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
PUBLIC_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A fake extra repo: a skill to link, and a two-column table naming it.
mkdir -p "$TMP/repos/skillpak/.claude/skills/myskill"
echo "stub skill" > "$TMP/repos/skillpak/.claude/skills/myskill/SKILL.md"
cat > "$TMP/repos/skillpak/dotfiles.links" <<'EOF'
# src (rel to repo)              dst (rel to $HOME)
.claude/skills/myskill           .claude/skills/myskill
EOF

# A repos.conf: one repo marked with links=, one without.
mkdir -p "$TMP/layer"
cat > "$TMP/layer/repos.conf" <<'EOF'
skillpak  extra  git@example.com:me/skillpak.git  links=dotfiles.links
plain     extra  git@example.com:me/plain.git
EOF

# Run python from the temp dir, not the repo root: the root dir holds the private
# composer (also dotfiles_install.py), and cwd leads sys.path — from here only
# PYTHONPATH resolves the import, so it lands on the public module under test.
cd "$TMP"

HOME="$TMP" PYTHONPATH="$PUBLIC_DIR" python3 - "$TMP" > "$TMP/out.sh" 2>"$TMP/err" <<'PY'
import sys
from pathlib import Path
import dotfiles_install as d

tmp = Path(sys.argv[1])

core, extra, links = d.load_repos([d.Layer(tmp / "layer")])
print("links_skillpak=%s" % links.get("skillpak"))
print("links_plain=%s" % links.get("plain"))
print("extra_both=%d" % int("skillpak" in extra and "plain" in extra))

pairs = d.parse_link_table(tmp / "repos/skillpak/dotfiles.links")
print("npairs=%d" % len(pairs))
print("pair0_src=%s" % pairs[0][0])
print("pair0_dst=%s" % pairs[0][1])

layers = d.repo_link_layers(links)
print("nlayers=%d" % len(layers))
print("root_ok=%d" % int(layers[0].root == tmp / "repos/skillpak"))

for root, src, dst in d.merge_mappings(layers):
    d.link(root / src, d.HOME / dst, dry_run=False)
link = tmp / ".claude/skills/myskill"
print("is_symlink=%d" % int(link.is_symlink()))
print("resolves_ok=%d" % int(link.resolve() == (tmp / "repos/skillpak/.claude/skills/myskill").resolve()))
PY
source "$TMP/out.sh" 2>/dev/null || true

ok "links= parsed"                 "${links_skillpak:-}" "dotfiles.links"
ok "unmarked repo absent from map" "${links_plain:-}"    "None"
ok "both repos are extra"          "${extra_both:-}"     "1"
ok "table parsed one pair"         "${npairs:-}"         "1"
ok "pair src"                      "${pair0_src:-}"      ".claude/skills/myskill"
ok "pair dst"                      "${pair0_dst:-}"      ".claude/skills/myskill"
ok "one layer built"              "${nlayers:-}"        "1"
ok "layer rooted at repo"          "${root_ok:-}"        "1"
ok "skill symlinked"               "${is_symlink:-}"     "1"
ok "symlink resolves to repo"      "${resolves_ok:-}"    "1"

# A one-column line is malformed: the parser must exit non-zero, not guess.
printf 'only_one_column\n' > "$TMP/bad.links"
fails env HOME="$TMP" PYTHONPATH="$PUBLIC_DIR" python3 -c \
  "import pathlib, dotfiles_install as d; d.parse_link_table(pathlib.Path('$TMP/bad.links'))"

# A repo marked with links= but not on disk contributes no layer (and no error).
absent=$(HOME="$TMP" PYTHONPATH="$PUBLIC_DIR" python3 -c \
  "import dotfiles_install as d; print(len(d.repo_link_layers({'ghost': 'dotfiles.links'})))" 2>/dev/null)
ok "absent repo contributes nothing" "${absent:-}" "0"

report

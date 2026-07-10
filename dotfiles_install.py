#!/usr/bin/env python3
"""Dotfiles installer. Creates symlinks from repo files to their home locations."""

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

DOTFILES = Path(__file__).resolve().parent
HOME = Path.home()
IS_WINDOWS = sys.platform == "win32"

# (source relative to DOTFILES, target relative to HOME)
COMMON = [
    ("bash/.bashrc", ".bashrc"),
    ("bash/.bash_profile", ".bash_profile"),
    ("bash/.inputrc", ".inputrc"),
    ("git/.gitconfig", ".gitconfig"),
    ("git/ignore", ".config/git/ignore"),
    # cargo config needs sccache on PATH — a public clone installs it itself.
    ("config/cargo/config.toml", ".cargo/config.toml"),
    ("claude/CLAUDE.md", ".claude/CLAUDE.md"),
    ("claude/keybindings.json", ".claude/keybindings.json"),
    ("claude/settings.json", ".claude/settings.json"),
    ("claude/statusline.sh", ".claude/statusline.sh"),
    ("claude/git-push-gate.sh", ".claude/git-push-gate.sh"),
    ("claude/skills/remember", ".claude/skills/remember"),
    ("claude/skills/promote-memory", ".claude/skills/promote-memory"),
    ("claude/skills/zoom-out", ".claude/skills/zoom-out"),
    ("claude/skills/design-an-interface", ".claude/skills/design-an-interface"),
    ("claude/skills/grill-me-with-docs", ".claude/skills/grill-me-with-docs"),
    ("claude/skills/improve-codebase-architecture", ".claude/skills/improve-codebase-architecture"),
    ("claude/skills/write-a-skill", ".claude/skills/write-a-skill"),
    ("claude/skills/defend-pr", ".claude/skills/defend-pr"),
    ("claude/commands", ".claude/commands"),
    ("tmux/.tmux.conf", ".tmux.conf"),
    ("tmux/.tmux-base.conf", ".tmux-base.conf"),
    ("tmux/.tmux-popup.conf", ".tmux-popup.conf"),
    ("tmux/overview.sh", ".local/bin/overview.sh"),
    ("tmux/cc-inspect.sh", ".local/bin/cc-inspect.sh"),
    ("tmux/cc-close-window.sh", ".local/bin/cc-close-window.sh"),
    ("tmux/cc-nav.sh", ".local/bin/cc-nav.sh"),
    ("tmux/cc-diff.sh", ".local/bin/cc-diff.sh"),
    ("tmux/cc-just.sh", ".local/bin/cc-just.sh"),
    ("tmux/cc-scratch.sh", ".local/bin/cc-scratch.sh"),
    ("tmux/cc-close-pane.sh", ".local/bin/cc-close-pane.sh"),
    ("tmux/cc-save-editor.sh", ".local/bin/cc-save-editor.sh"),
    ("tmux/cc-wt-cleanup.sh", ".local/bin/cc-wt-cleanup.sh"),
    ("tmux/cc-select-pane.sh", ".local/bin/cc-select-pane.sh"),
    ("tmux/wt-split.sh", ".local/bin/wt-split.sh"),
    ("just/justfile", ".justfile"),
    ("scripts/find-project.sh", ".local/bin/find-project.sh"),
    ("scripts/task-lib.sh", ".local/bin/task-lib.sh"),
    ("scripts/task-list.sh", ".local/bin/task-list.sh"),
    ("scripts/task-claim.sh", ".local/bin/task-claim.sh"),
    ("scripts/task-done.sh", ".local/bin/task-done.sh"),
    ("scripts/task-cancel.sh", ".local/bin/task-cancel.sh"),
    ("scripts/task-unclaim.sh", ".local/bin/task-unclaim.sh"),
    ("scripts/task-next-id.sh", ".local/bin/task-next-id.sh"),
    ("scripts/task-planned.sh", ".local/bin/task-planned.sh"),
    ("scripts/task-commit.sh", ".local/bin/task-commit.sh"),
    ("scripts/context-commit.sh", ".local/bin/context-commit.sh"),
    ("scripts/context-sync.sh", ".local/bin/context-sync.sh"),
    ("scripts/task-cleanup-branch.sh", ".local/bin/task-cleanup-branch.sh"),
    ("scripts/sync.sh", ".local/bin/sync.sh"),
    ("scripts/subtrees-push.sh", ".local/bin/subtrees-push.sh"),
    ("scripts/cc-review-diff.sh", ".local/bin/cc-review-diff.sh"),
    ("scripts/install_fetcher.sh", ".local/bin/install_fetcher.sh"),
    ("tmux/workspace-dotfiles.sh", ".local/bin/workspace-dotfiles.sh"),
    ("tmux/workspace-solo.sh", ".local/bin/workspace-solo.sh"),
    ("tmux/workspace-dual.sh", ".local/bin/workspace-dual.sh"),
]

WINDOWS_ONLY = [
    ("windows/.minttyrc", ".minttyrc"),
    ("alacritty/alacritty.toml", "AppData/Roaming/alacritty/alacritty.toml"),
    ("alacritty/platform-windows.toml", "AppData/Roaming/alacritty/platform.toml"),
    ("windows-terminal/settings.json", "AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"),
    ("wsl/.wslconfig", ".wslconfig"),
]

# Tarballs extracted before symlinking (none in the public layer — add your own,
# e.g. a pinned tool build). The extracted tree should be gitignored; the tarball
# is the tracked artifact. (tarball relative to DOTFILES, extract dir, strip count)
LINUX_TARBALLS = []

# Like LINUX_TARBALLS, but the archive is downloaded at install instead of tracked
# in git — for tools too big to vendor (>50MB). Extracted tree should be gitignored.
# Supports .zip and .tar.* archives. (url, extract dir, strip count, sha256)
LINUX_URL_ARTIFACTS = []

LINUX_ONLY = [
    ("alacritty/alacritty.toml", ".config/alacritty/alacritty.toml"),
    ("alacritty/platform-linux.toml", ".config/alacritty/platform.toml"),
    ("micro/settings.json", ".config/micro/settings.json"),
    ("micro/bindings.json", ".config/micro/bindings.json"),
    ("micro/init.lua", ".config/micro/init.lua"),
    ("micro/colorschemes/solarized-vp.micro", ".config/micro/colorschemes/solarized-vp.micro"),
    ("diffview/config", ".config/diffview/config"),
    ("tmux/micro-session.sh", ".local/bin/micro-session.sh"),
    ("scripts/micro-fzf.sh", ".local/bin/micro-fzf.sh"),
    ("scripts/micro-yazi.sh", ".local/bin/micro-yazi.sh"),
    ("scripts/micro-lastfile.sh", ".local/bin/micro-lastfile.sh"),
    ("tmux/wt-shell", ".local/bin/wt-shell"),
    ("tmux/wt-run", ".local/bin/wt-run"),
    ("tmux/wt-popup", ".local/bin/wt-popup"),
    ("tmux/park-host-worktrees.sh", ".local/bin/park-host-worktrees.sh"),
    ("scripts/apply-gnome-keybindings.sh", ".local/bin/apply-gnome-keybindings.sh"),
]

# Sibling repos under ~/repos are declared in each layer's repos.conf (shared
# with sync.sh).


class Layer:
    """One source root contributing mappings, tarballs, and a repos.conf. The
    installer composes an ordered list of layers and links each in turn, so a
    later layer wins on a dst collision. A standalone install is one layer (this
    file's own dir); the private superproject adds its own via main(extra_layers)."""

    def __init__(self, root, common=(), windows_only=(), linux_only=(), tarballs=(), url_artifacts=()):
        self.root = Path(root)
        self.common = list(common)
        self.windows_only = list(windows_only)
        self.linux_only = list(linux_only)
        self.tarballs = list(tarballs)
        self.url_artifacts = list(url_artifacts)

    def mappings(self):
        return self.common + (self.windows_only if IS_WINDOWS else self.linux_only)

    @property
    def repos_conf(self):
        return self.root / "repos.conf"


def own_layer():
    """The layer rooted at this installer's own directory."""
    return Layer(DOTFILES, COMMON, WINDOWS_ONLY, LINUX_ONLY, LINUX_TARBALLS, LINUX_URL_ARTIFACTS)


def merge_mappings(layers):
    """Flatten the layers' mappings into (root, src_rel, dst_rel), collapsing dst
    collisions so a later layer wins (e.g. the private layer repoints ~/.justfile
    from the public justfile to the private one). Without this both mappings link
    in turn and the second relinks the first's dst on every run — never idempotent.
    A reassigned dst keeps its original position, so any ordering dependencies
    between nested mappings still hold."""
    merged = {}  # dst_rel -> (root, src_rel), insertion-ordered
    for layer in layers:
        for src_rel, dst_rel in layer.mappings():
            merged[dst_rel] = (layer.root, src_rel)
    return [(root, src_rel, dst_rel) for dst_rel, (root, src_rel) in merged.items()]


def _is_native_symlink(path: Path) -> bool:
    """Check if a symlink is a native Windows symlink (vs MSYS-style)."""
    try:
        subprocess.run(
            ["cmd", "/c", f"if exist {str(path)} (exit 0) else (exit 1)"],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return True
    except subprocess.CalledProcessError:
        return False


_actions_taken = 0


def action(msg: str):
    global _actions_taken
    _actions_taken += 1
    print(msg)


def verify_dotfiles_location(install_root):
    if IS_WINDOWS:
        return
    expected = HOME / "repos" / "dotfiles"
    if expected.resolve() == install_root.resolve():
        return
    print(f"error: dotfiles must be at {expected}, found at {install_root}", file=sys.stderr)
    sys.exit(1)


def load_repos(layers):
    """Parse every layer's repos.conf into (core, extra) dicts mapping
    name -> remote. core repos are always cloned; extra repos are opt-in via
    --extra. sync.sh reads the same files. Later layers override earlier ones on
    a name collision."""
    core, extra = {}, {}
    for layer in layers:
        manifest = layer.repos_conf
        if not manifest.exists():
            continue
        for line in manifest.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            name, tier, remote = line.split()
            if tier == "core":
                core[name] = remote
            elif tier == "extra":
                extra[name] = remote
            else:
                sys.exit(f"repos.conf: bad tier {tier!r} for {name!r} (want core|extra)")
    return core, extra


def clone_repo(name: str, remote: str, dry_run: bool, verbose: bool = False):
    if IS_WINDOWS:
        return
    dest = HOME / "repos" / name
    if dest.exists():
        if verbose:
            print(f"  skip ({name} already cloned) {dest}")
        return
    action(f"  clone {remote} -> {dest}")
    if not dry_run:
        dest.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", remote, str(dest)], check=True)


def extract_tarball(tarball: Path, extract_dir: Path, strip: int, dry_run: bool, verbose: bool = False):
    marker = extract_dir / ".installed-from-mtime"
    tarball_mtime = str(int(tarball.stat().st_mtime))
    if marker.exists() and marker.read_text().strip() == tarball_mtime:
        if verbose:
            print(f"  skip (already extracted) {extract_dir}")
        return

    action(f"  extract {tarball} -> {extract_dir}")
    if dry_run:
        return

    if extract_dir.exists():
        shutil.rmtree(extract_dir)
    extract_dir.mkdir(parents=True)
    with tarfile.open(tarball, "r:*") as tf:
        members = []
        for m in tf.getmembers():
            parts = Path(m.name).parts
            if len(parts) <= strip:
                continue
            m.name = str(Path(*parts[strip:]))
            members.append(m)
        tf.extractall(extract_dir, members=members)
    marker.write_text(tarball_mtime)


def _extract_stripped(archive: Path, extract_dir: Path, strip: int):
    """Extract a .zip or .tar.* archive into extract_dir, dropping `strip` leading
    path components. Preserves unix permissions, including zip exec bits (taken
    from external_attr, which tarfile carries natively but zipfile does not)."""
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as zf:
            for info in zf.infolist():
                parts = Path(info.filename).parts
                if len(parts) <= strip:
                    continue
                target = extract_dir / Path(*parts[strip:])
                if info.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(info) as src, open(target, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                mode = (info.external_attr >> 16) & 0o7777
                if mode:
                    target.chmod(mode)
    else:
        with tarfile.open(archive, "r:*") as tf:
            members = []
            for m in tf.getmembers():
                parts = Path(m.name).parts
                if len(parts) <= strip:
                    continue
                m.name = str(Path(*parts[strip:]))
                members.append(m)
            tf.extractall(extract_dir, members=members)


def fetch_url_artifact(url, extract_dir: Path, strip: int, sha256: str, dry_run: bool, verbose: bool = False):
    """Download an archive from URL and extract it into extract_dir — for tools too
    big to vendor in git (>50MB). Idempotent via a marker recording (url, sha256):
    re-runs skip when unchanged, so the download only happens on first install or a
    version bump. sha256 ('' to skip) is verified before extraction; on a network
    error or hash mismatch we warn and leave any prior install intact, rather than
    aborting the whole installer."""
    marker = extract_dir / ".installed-from-url"
    want = f"{url}\n{sha256}"
    if marker.exists() and marker.read_text() == want:
        if verbose:
            print(f"  skip (already fetched) {extract_dir}")
        return

    action(f"  fetch {url} -> {extract_dir}")
    if dry_run:
        return

    fd, tmp_name = tempfile.mkstemp(prefix="dotfiles-artifact-")
    os.close(fd)
    tmp_path = Path(tmp_name)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "dotfiles-installer"})
        with urllib.request.urlopen(req) as resp, open(tmp_path, "wb") as out:
            shutil.copyfileobj(resp, out)
        if sha256:
            h = hashlib.sha256()
            with open(tmp_path, "rb") as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
            if h.hexdigest() != sha256:
                action(f"  warn: sha256 mismatch for {url} — skipping (got {h.hexdigest()})")
                return
        if extract_dir.exists():
            shutil.rmtree(extract_dir)
        extract_dir.mkdir(parents=True)
        _extract_stripped(tmp_path, extract_dir, strip)
        marker.write_text(want)
    except (urllib.error.URLError, OSError) as e:
        action(f"  warn: failed to fetch {url}: {e}")
    finally:
        tmp_path.unlink(missing_ok=True)


def link(src: Path, dst: Path, dry_run: bool, verbose: bool = False):
    if dst.is_symlink():
        is_correct_target = dst.resolve() == src.resolve()
        needs_native = IS_WINDOWS and not _is_native_symlink(dst)
        if is_correct_target and not needs_native:
            if verbose:
                print(f"  skip (already linked) {dst}")
            return
        if needs_native:
            action(f"  replacing MSYS symlink with native: {dst}")
        if not dry_run:
            try:
                dst.unlink()
            except OSError as e:
                action(f"  skip (cannot replace: {e.strerror}) {dst}")
                return

    if dst.exists():
        backup = dst.with_suffix(dst.suffix + ".bak")
        if dry_run:
            action(f"  backup {dst} -> {backup}")
        else:
            try:
                dst.rename(backup)
            except OSError as e:
                # Read-only bind-mounted file (e.g. ~/.gitconfig in a container) —
                # renaming a mountpoint fails with EBUSY. os.path.ismount can't predict
                # it when the bind source shares the parent's device, so catch the
                # failure instead. Leave it; the mount is the intended content.
                action(f"  skip (cannot replace: {e.strerror}) {dst}")
                return
            action(f"  backup {dst} -> {backup}")

    action(f"  link {dst} -> {src}")
    if not dry_run:
        if IS_WINDOWS:
            subprocess.run(
                ["cmd", "/c", "mkdir", str(dst.parent)],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        else:
            dst.parent.mkdir(parents=True, exist_ok=True)
        if IS_WINDOWS:
            # Use mklink for native Windows symlinks — Python's symlink_to
            # under Git Bash creates MSYS-style symlinks invisible to native apps
            args = ["cmd", "/c", "mklink"]
            if src.is_dir():
                args.append("/D")
            args += [str(dst), str(src)]
            subprocess.run(args, check=True, stdout=subprocess.DEVNULL)
        else:
            dst.symlink_to(src)


def apply_gnome_keybindings(dry_run: bool, verbose: bool = False):
    """Apply GNOME keybinding policy via gsettings. GNOME settings live in a
    binary dconf DB and can't be symlinked, so the repo declares them in an
    idempotent script run here. The script no-ops without GNOME (WSL, Windows)."""
    if IS_WINDOWS:
        return
    script = DOTFILES / "scripts" / "apply-gnome-keybindings.sh"
    if not script.exists():
        return
    if dry_run:
        action(f"  apply gnome keybindings ({script})")
        return
    if verbose:
        print(f"  apply gnome keybindings ({script})")
    if subprocess.run([str(script)]).returncode != 0:
        action(f"  warn: gnome keybindings apply failed ({script})")


def main(extra_layers=(), install_root=None, provision=None):
    layers = [own_layer(), *extra_layers]
    if install_root is None:
        install_root = DOTFILES
    core_repos, extra_repos = load_repos(layers)

    parser = argparse.ArgumentParser(description="Install dotfiles symlinks")
    parser.add_argument("--dry-run", action="store_true", help="Preview without making changes")
    parser.add_argument("-v", "--verbose", action="store_true", help="Show already-linked skips")
    parser.add_argument("--no-provision", action="store_true",
                        help="Skip the provision() prerequisites step (apt, runtimes)")
    parser.add_argument(
        "--extra", nargs="+", choices=sorted(extra_repos), default=[], metavar="REPO",
        help="Also clone optional repos into ~/repos (choices: %(choices)s)",
    )
    args = parser.parse_args()

    if args.dry_run:
        print("DRY RUN — no changes will be made\n")

    if args.verbose:
        platform = "Windows"
        if not IS_WINDOWS:
            platform = "Linux"
            try:
                with open("/proc/version") as f:
                    if "microsoft" in f.read().lower():
                        platform = "Linux (WSL)"
            except FileNotFoundError:
                pass
        print(f"Platform: {platform}")
        print(f"Dotfiles: {install_root}")
        print(f"Home:     {HOME}\n")

    verify_dotfiles_location(install_root)

    # A layer may provision system-level prerequisites that can't be symlinked
    # (apt packages, runtimes). The mechanism is generic and dormant for a public
    # clone (which passes no provision); the private composer supplies the
    # Debian/Ubuntu logic. --no-provision skips it for environments that supply
    # their own prerequisites (e.g. a container reusing only the symlinks).
    if provision is not None and not args.no_provision:
        provision(args.dry_run, args.verbose)

    for name, remote in core_repos.items():
        clone_repo(name, remote, args.dry_run, args.verbose)
    for name in args.extra:
        clone_repo(name, extra_repos[name], args.dry_run, args.verbose)

    if not IS_WINDOWS:
        for layer in layers:
            for tar_rel, dir_rel, strip in layer.tarballs:
                tarball = layer.root / tar_rel
                if not tarball.exists():
                    action(f"  warn: tarball not found {tarball}")
                    continue
                extract_tarball(tarball, layer.root / dir_rel, strip, args.dry_run, args.verbose)

        for layer in layers:
            for url, dir_rel, strip, sha in layer.url_artifacts:
                fetch_url_artifact(url, layer.root / dir_rel, strip, sha, args.dry_run, args.verbose)

    for root, src_rel, dst_rel in merge_mappings(layers):
        src = root / src_rel
        dst = HOME / dst_rel
        if not src.exists():
            action(f"  warn: source not found {src}")
            continue
        link(src, dst, args.dry_run, args.verbose)

    apply_gnome_keybindings(args.dry_run, args.verbose)

    if _actions_taken == 0:
        print("install: ✓")


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
# Sync dotfiles first, run install, then sync remaining repos and subtrees.
# If the dotfiles pull brings in new code, re-exec so the new script wins.
#
# Speed: nearly all the wall-clock is `git fetch` SSH handshakes (~1.5s each).
# Two things attack that:
#   - One shared SSH connection (ControlMaster), so repeated fetches — notably
#     the re-exec's second pass — skip the handshake.
#   - A single parallel PREFETCH burst up front. It is read-only (only
#     remote-tracking refs move), so it sits ahead of the re-exec/install gates
#     without touching them: nothing is *applied* until dotfiles has merged,
#     re-exec'd, and install has run. Apply then fast-forwards from the
#     already-fetched refs and hits the network only for an actual push.
#
# Ordering still holds: dotfiles applies and re-execs first (so new code wins),
# then install clones any newly-declared siblings (a fresh clone is already
# current, so it needs no prefetch), then siblings apply in parallel.
set -euo pipefail
SYNC_ISSUES=0

if [[ "${1:-}" == "--help" ]]; then
    echo "Sync dotfiles, run install, sync remaining repos, ingest subtrees."
    echo "Exits non-zero if anything is dirty, diverged, or fails to sync."
    echo "Usage: sync.sh"
    exit 0
fi

# Route every git network op over one reused SSH connection. ControlMaster=auto
# opens a master on first use and shares it after; ControlPersist keeps it alive
# across the re-exec (the master is a separate process and the exported env —
# hence this socket path — survives `exec`). A private ControlPath isolates this
# from the user's own ssh, and ControlMaster=auto degrades to a normal
# connection if the socket can't be created, so it is safe everywhere.
SYNC_SSH_SOCK=/tmp/dotfiles-sync-%C
# Compose onto whatever SSH command the environment already mandates rather than
# hardcoding `ssh`: a Coder workspace presets GIT_SSH_COMMAND to a `coder gitssh`
# wrapper that injects its managed git key, and replacing it with bare `ssh`
# loses the key (every fetch → "Permission denied (publickey)"). The wrapper
# forwards our -o options straight through to ssh, so multiplexing still applies.
# Stash the original base in an exported var so the re-exec recomposes from it
# instead of doubling the options onto an already-composed command.
: "${SYNC_SSH_BASE:=${GIT_SSH_COMMAND:-ssh}}"
export SYNC_SSH_BASE
# LogLevel=QUIET hushes the "ControlSocket already exists, disabling
# multiplexing" notice that a cold parallel burst emits as the fetches race to
# open the master; git still prints transport errors, so failures stay visible.
export GIT_SSH_COMMAND="$SYNC_SSH_BASE -o ControlMaster=auto -o ControlPath=$SYNC_SSH_SOCK -o ControlPersist=30 -o LogLevel=QUIET"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"; $SYNC_SSH_BASE -O exit -o ControlPath="$SYNC_SSH_SOCK" git@github.com 2>/dev/null || true' EXIT

# Functions report trouble by returning non-zero, not by setting a shared
# variable: the parallel jobs run in background subshells, where a variable
# write would never reach the parent. Each caller folds the return into
# SYNC_ISSUES. Note that calling a function in a `|| ...` context disables
# `set -e` for its whole body, so the git commands below guard their own
# failures explicitly rather than leaning on `set -e`.

# --- Prefetch (read-only): refresh remote-tracking refs in parallel ----------
# Dirty repos are skipped just as apply skips them, so we never spend a fetch on
# a repo whose result we would throw away.
prefetch_repo() {
  local repo=$1
  [[ -d "$repo/.git" ]] || return 0
  cd "$repo" || return 1
  if ! git diff --quiet || ! git diff --cached --quiet; then
    return 0
  fi
  git remote | grep -q . || return 0
  git fetch --quiet || return 1
  return 0
}

# Fetch each subtree's remote tip into a private ref (refs/sync/<prefix>) so the
# apply pass can compare trees without a fetch. Best-effort: on failure the ref
# is simply absent and apply falls back to `git subtree pull`, which fetches. A
# dedicated ref (not FETCH_HEAD) makes this safe to run concurrently with the
# repo's own prefetch in the same working copy.
prefetch_subtrees() {
  local repo=$1
  local subtrees_file="$repo/.subtrees"
  [[ -f "$subtrees_file" ]] || return 0
  cd "$repo" || return 0
  if ! git diff --quiet || ! git diff --cached --quiet; then
    return 0
  fi
  local prefix remote branch _
  while read -r prefix remote branch _; do
    case "$prefix" in '#'*|'') continue ;; esac
    git fetch --quiet "$remote" "+$branch:refs/sync/${prefix//\//-}" 2>/dev/null || true
  done < "$subtrees_file"
  return 0
}

# One prefetch job per repo. The repo's own fetch and its subtree fetches share
# a working copy, so run them in sequence — concurrent fetches in one repo race
# on FETCH_HEAD and can leave the subtree ref unwritten. Across repos the jobs
# still run in parallel. Only the repo fetch's result is recorded (apply depends
# on it); subtree prefetch is best-effort and apply re-fetches if it is missing.
prefetch_one() {
  local repo=$1 rc=0
  prefetch_repo "$repo" || rc=$?
  prefetch_subtrees "$repo" || true
  printf '%s\n' "$rc" >"$tmpdir/pf.$(basename "$repo").rc"
}

# --- Apply (mutating): fast-forward / push from the already-fetched refs ------
apply_repo() {
  local repo=$1
  local name
  name=$(basename "$repo")

  if [[ ! -d "$repo/.git" ]]; then
    echo "$name: skipped (not a git repo)"
    return 1
  fi
  cd "$repo" || { echo "$name: cd failed"; return 1; }

  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "$name: dirty, skipping"
    return 1
  fi

  local local_ref remote_ref base
  local_ref=$(git rev-parse HEAD)
  remote_ref=$(git rev-parse @{u} 2>/dev/null || echo "")
  base=$(git merge-base HEAD @{u} 2>/dev/null || echo "")

  if [[ -z "$remote_ref" ]]; then
    echo "$name: no upstream, skipping"
    return 0
  fi

  if [[ "$local_ref" != "$remote_ref" && "$local_ref" == "$base" ]]; then
    # Fast-forward to the prefetched upstream — no network (cf. `pull --ff-only`,
    # which re-fetches). The base check guarantees this is a clean ff.
    if git merge --ff-only --quiet @{u}; then
      echo "$name: pulled"
    else
      echo "$name: pull failed"
      return 1
    fi
  elif [[ "$local_ref" != "$remote_ref" && "$remote_ref" == "$base" ]]; then
    if ! git push --quiet; then
      echo "$name: push failed"
      return 1
    fi
    # Push may go to a different branch than @{u} (push.default=current vs
    # upstream tracking a different branch) — in that case @{u} doesn't move
    # and we'd loop forever reporting "pushed". Verify @{u} actually advanced.
    if [[ "$(git rev-parse @{u})" == "$local_ref" ]]; then
      echo "$name: pushed"
    else
      echo "$name: push did not update @{u} — check upstream vs push.default"
      return 1
    fi
  elif [[ "$local_ref" != "$remote_ref" ]]; then
    echo "$name: diverged, skipping (resolve manually)"
    return 1
  else
    echo "$name: ✓"
  fi
}

apply_subtrees() {
  local repo=$1
  local subtrees_file="$repo/.subtrees"
  local name rc=0
  name=$(basename "$repo")

  [[ -f "$subtrees_file" ]] || return 0
  cd "$repo" || { echo "$name subtrees: cd failed"; return 1; }
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "$name subtrees: dirty, skipping"
    return 1
  fi

  local prefix remote branch _ ref tip_tree before after
  while read -r prefix remote branch _; do
    case "$prefix" in '#'*|'') continue ;; esac
    ref="refs/sync/${prefix//\//-}"

    # Compare the local prefix tree against the remote tip's tree. Prefer the
    # prefetched ref; if it is absent (prefetch raced or failed), fetch it now —
    # we must have a reliable tree to compare, because `git subtree pull
    # --squash` keys off a stored split SHA that goes stale on every push and
    # will spuriously create an empty merge unless gated on a real tree change.
    if ! tip_tree=$(git rev-parse --verify --quiet "$ref^{tree}"); then
      if git fetch --quiet "$remote" "+$branch:$ref" 2>/dev/null; then
        tip_tree=$(git rev-parse "$ref^{tree}")
      else
        echo "$name/$prefix: fetch failed"
        rc=1
        continue
      fi
    fi

    if [[ "$tip_tree" == "$(git rev-parse "HEAD:$prefix")" ]]; then
      echo "$name/$prefix: ✓"
      continue
    fi

    before=$(git rev-parse HEAD)
    if git subtree pull --prefix="$prefix" "$remote" "$branch" --squash --quiet; then
      after=$(git rev-parse HEAD)
      if [[ "$before" != "$after" ]]; then
        echo "$name/$prefix: ingested"
      else
        echo "$name/$prefix: ✓"
      fi
    else
      echo "$name/$prefix: failed"
      rc=1
    fi
  done < "$subtrees_file"
  return $rc
}

# Record a repo's prefetch result so apply can tell "fetched, up to date" from
# "fetch failed" instead of trusting a stale ref (which would falsely report ✓
# when the remote was unreachable).
prefetch_rc() {
  local f="$tmpdir/pf.$(basename "$1").rc" rc=0
  [[ -f "$f" ]] && read -r rc <"$f"
  printf '%s' "$rc"
}

# A repo and its subtrees touch the same working tree, so apply them in order;
# different repos don't, so the jobs that call this run concurrently.
apply_repo_and_subtrees() {
  local repo=$1 rc=0
  if [[ "$(prefetch_rc "$repo")" != 0 ]]; then
    echo "$(basename "$repo"): fetch failed"
    return 1
  fi
  apply_repo "$repo" || rc=1
  apply_subtrees "$repo" || rc=1
  return $rc
}

# Declared sibling repo names across all installer layers' repos.conf (root
# actual + public template), deduped — mirrors dotfiles_install.py's load_repos
# so sync and install agree on the repo set. The public conf is absent in a
# public-only clone (its content is the root conf there); skipped when missing.
declared_repos() {
  local -A seen
  local conf name _
  for conf in ~/repos/dotfiles/repos.conf ~/repos/dotfiles/public/repos.conf; do
    [[ -f "$conf" ]] || continue
    while read -r name _; do
      case "$name" in '#'*|'') continue ;; esac
      [[ -n "${seen[$name]:-}" ]] && continue
      seen[$name]=1
      printf '%s\n' "$name"
    done < "$conf"
  done
}

# --- 1. Prefetch every existing repo + subtree, in parallel (read-only) -------
# New siblings (declared by a not-yet-pulled dotfiles change) aren't on disk
# yet; install clones them after the gate, and a fresh clone needs no sync.
all_repos=(~/repos/dotfiles)
while read -r rname; do
  [[ -d ~/repos/$rname ]] && all_repos+=(~/repos/$rname)
done < <(declared_repos)

for repo in "${all_repos[@]}"; do
  ( rc=0; prefetch_repo "$repo" || rc=$?; printf '%s\n' "$rc" >"$tmpdir/pf.$(basename "$repo").rc" ) &
  prefetch_subtrees "$repo" &
done
wait

# --- 2. Dotfiles apply (gate). Re-exec on pull so the rest runs under the new
#        script. SYNC_RERAN guards against infinite re-exec — one level only. ---
cd ~/repos/dotfiles
before=$(git rev-parse HEAD)
if [[ "$(prefetch_rc ~/repos/dotfiles)" != 0 ]]; then
  echo "dotfiles: fetch failed"
  SYNC_ISSUES=1
else
  apply_repo ~/repos/dotfiles || SYNC_ISSUES=1
fi
after=$(git rev-parse HEAD)
if [[ "$before" != "$after" ]]; then
  if [[ -n "${SYNC_RERAN:-}" ]]; then
    echo "dotfiles changed again after rerun — bailing to avoid loop" >&2
    exit 1
  fi
  echo "dotfiles updated — re-running sync"
  rm -rf "$tmpdir"            # exec won't fire the EXIT trap; clean up now, but keep the ssh master warm for the rerun
  SYNC_RERAN=1 exec "$0" "$@"
fi

# --- 3. Install — links new files, clones any newly-required sibling repos. ----
# The installer is Python and can't install Python (chicken-and-egg). It's the one
# prerequisite sync can't provide for itself, so error out with a hint rather than
# guess a package manager; everything else the installer provisions.
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 not found — required to run the installer." >&2
  echo "Install it with your package manager (e.g. sudo apt-get install -y python3), then re-run." >&2
  exit 1
fi
~/repos/dotfiles/dotfiles_install.py

# Re-collect siblings: install may have just cloned new ones (already current).
other_repos=()
while read -r rname; do
  [[ -d ~/repos/$rname ]] && other_repos+=(~/repos/$rname)
done < <(declared_repos)

# --- 4. Apply siblings (ff/push + subtrees) and dotfiles' own subtrees in
#        parallel. Each job buffers output (concurrent writes to one stream
#        would interleave) and records its exit code; we replay in submission
#        order and fold the codes into SYNC_ISSUES. ---
outs=()
n=0

run_job() {
  local out=$1; shift
  local rc=0
  "$@" >"$out" 2>&1 || rc=$?
  printf '%s\n' "$rc" >"$out.rc"
}

submit() {
  local out="$tmpdir/job$n"
  outs+=("$out")
  n=$((n + 1))
  run_job "$out" "$@" &
}

for repo in "${other_repos[@]}"; do
  submit apply_repo_and_subtrees "$repo"
done
submit apply_subtrees ~/repos/dotfiles
wait

for out in "${outs[@]}"; do
  cat "$out"
  job_rc=0
  read -r job_rc <"$out.rc" || true
  [[ "$job_rc" == 0 ]] || SYNC_ISSUES=1
done

exit $SYNC_ISSUES

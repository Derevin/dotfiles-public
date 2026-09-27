#!/usr/bin/env bash
# Unit test for the cargo wrapper: heavy subcommands get a low-priority systemd
# scope, light ones fall straight through, the real cargo is found on PATH rather
# than assumed at ~/.cargo/bin, and the scope tuning comes from the environment.
#
# Usage: test-cargo.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the cargo wrapper unit test (routing, real-cargo resolution, scope args)."
    echo "Usage: test-cargo.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
WRAPPER="$SCRIPT_DIR/../scripts/cargo"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A home of our own so a real ~/.cargo on the test box can't stand in for the
# fake real cargo below — the point is that PATH resolves it, not $HOME.
export HOME="$TMP/home"; mkdir -p "$HOME"

export REALLOG="$TMP/real.log" SDLOG="$TMP/sd.log"
: > "$REALLOG"; : > "$SDLOG"

# Fake real cargo: records its argv and whether the scope marked it scoped.
mkdir -p "$TMP/realbin"
cat > "$TMP/realbin/cargo" <<'EOF'
#!/usr/bin/env bash
printf 'args=%s scoped=%s\n' "$*" "${CARGO_SCOPED-}" >> "$REALLOG"
EOF

# Fake systemd-run: records its argv, then execs the command after '--' so the
# real cargo still runs — proving the scope wraps it rather than replaces it.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/systemd-run" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SDLOG"
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done
shift
exec "$@"
EOF

# The wrapper reached as bare `cargo`, ahead of the fake real cargo on PATH.
mkdir -p "$TMP/wrapbin"
ln -s "$WRAPPER" "$TMP/wrapbin/cargo"
chmod +x "$TMP/realbin/cargo" "$TMP/bin/systemd-run"
export PATH="$TMP/wrapbin:$TMP/realbin:$TMP/bin:$PATH"
hash -r

# A live systemd user manager is one gate for scoping. bind() leaves a socket
# file behind after the process exits, which is all the wrapper's -S test wants.
export XDG_RUNTIME_DIR="$TMP/run"; mkdir -p "$TMP/run/systemd"
have_socket=0
if python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' \
    "$TMP/run/systemd/private" 2>/dev/null; then
    have_socket=1
fi

run() { : > "$REALLOG"; : > "$SDLOG"; cargo "$@"; }

# --- real cargo resolution + light passthrough --------------------------------
run --version
ok "light command runs the PATH-resolved real cargo" "$(grep -c 'args=--version' "$REALLOG")" 1
ok "light command is not scoped" "$(cat "$SDLOG")" ""

run +nightly --version
ok "a +toolchain light command stays unscoped" "$(cat "$SDLOG")" ""

# --- gates that skip scoping even for a heavy subcommand -----------------------
( export CARGO_SCOPED=1; run build )
ok "CARGO_SCOPED prevents a nested re-scope" "$(cat "$SDLOG")" ""
ok "CARGO_SCOPED still runs real cargo" "$(grep -c 'args=build' "$REALLOG")" 1

( export IN_CONTAINER=1; run build )
ok "IN_CONTAINER skips scoping" "$(cat "$SDLOG")" ""

# --- the scope itself (needs a socket to mint) --------------------------------
if [ "$have_socket" = 1 ]; then
    run build --release
    ok "a heavy command runs real cargo" "$(grep -c 'args=build --release' "$REALLOG")" 1
    ok "a heavy command is scoped" "$(grep -c 'scoped=1' "$REALLOG")" 1
    ok "the scope sets CPUWeight" "$(grep -c 'CPUWeight=20' "$SDLOG")" 1
    ok "MemoryHigh defaults to a RAM percentage" "$(grep -c 'MemoryHigh=75%' "$SDLOG")" 1

    run +nightly build
    ok "a +toolchain heavy command still scopes" "$(grep -c 'scoped=1' "$REALLOG")" 1

    ( export CARGO_SCOPE_MEMORY_HIGH=3G CARGO_SCOPE_CPU_WEIGHT=50; run build )
    ok "MemoryHigh honors its env override" "$(grep -c 'MemoryHigh=3G' "$SDLOG")" 1
    ok "CPUWeight honors its env override" "$(grep -c 'CPUWeight=50' "$SDLOG")" 1

    ( export CARGO_SCOPE_MEMORY_HIGH=; run build )
    ok "an empty MemoryHigh drops the memory bound" "$(grep -c 'MemoryHigh' "$SDLOG")" 0
else
    echo "no python3 AF_UNIX socket — skipping scope-args assertions"
fi

report

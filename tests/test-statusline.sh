#!/usr/bin/env bash
# Unit tests for claude/statusline.sh: the model segment.
# Usage: test-statusline.sh
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run the statusline.sh unit tests."
    echo "Usage: test-statusline.sh"
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-lib.sh"
SL="$SCRIPT_DIR/../claude/statusline.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A fresh rate cache keeps the script from fetching; a non-repo cwd and no label
# leave the model as the only segment.
export HOME="$TMP"
mkdir -p "$HOME/.cache"
echo 23 > "$HOME/.cache/claude-statusline-usd-czk"
unset CLAUDE_LABEL
cd "$TMP" || exit 1

model() { printf '{"model":{"display_name":"%s"}}' "$1" | "$SL"; }

ok "keeps the version" "$(model 'Opus 4.8')" "Opus 4.8"
ok "drops the context suffix" "$(model 'Opus 5.5 (1M context)')" "Opus 5.5"
ok "keeps a long name whole" "$(model 'Sonnet 5')" "Sonnet 5"

report

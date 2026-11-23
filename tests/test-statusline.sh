#!/usr/bin/env bash
# Unit tests for claude/statusline.sh.
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

# A non-repo cwd and no label leave the model as the only segment.
export HOME="$TMP"
unset CLAUDE_LABEL
cd "$TMP" || exit 1

model() { printf '{"model":{"display_name":"%s"}}' "$1" | "$SL"; }

ok "abbreviates the family" "$(model 'Opus 4.8')" "O4.8"
ok "drops the context suffix" "$(model 'Opus 5.5 (1M context)')" "O5.5"
ok "keeps a versionless name whole" "$(model 'Opus')" "Opus"

effort() { printf '{"model":{"display_name":"Opus 5.5"},"effort":{"level":"%s"}}' "$1" | "$SL"; }
fills=""
for level in low medium high xhigh max; do fills+="$(effort "$level") "; done
ok "fills a circle per effort level" "$fills" "O5.5󰝦 O5.5󰪟 O5.5󰪡 O5.5󰪣 O5.5󰪥 "
ok "skips an unknown effort level" "$(effort turbo)" "O5.5"
ok "shows cost in whole USD" "$(echo '{"cost":{"total_cost_usd":1.234}}' | "$SL")" '$1'
ok "leads with context, then model and cost" \
    "$(echo '{"model":{"display_name":"Opus 5.5"},"context_window":{"used_percentage":23.4},"cost":{"total_cost_usd":3.21}}' | "$SL")" \
    '23% O5.5 $3'
# Account-wide, so shown once in the tmux status bar instead (ai-usage.sh).
ok "leaves rate limits out" \
    "$(echo '{"model":{"display_name":"Opus 5.5"},"rate_limits":{"five_hour":{"used_percentage":20},"seven_day":{"used_percentage":40}}}' | "$SL")" \
    'O5.5'

report

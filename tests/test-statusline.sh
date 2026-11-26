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

ok "keeps the full name" "$(model 'Opus 4.8')" "Opus 4.8"
ok "drops the context suffix" "$(model 'Opus 5.5 (1M context)')" "Opus 5.5"

effort() { printf '{"model":{"display_name":"Opus 5.5"},"effort":{"level":"%s"}}' "$1" | "$SL"; }
fills=""
for level in low medium high xhigh max; do fills+="$(effort "$level") "; done
ok "fills a circle per effort level" "$fills" "Opus 5.5 󰝦 Opus 5.5 󰪟 Opus 5.5 󰪡 Opus 5.5 󰪣 Opus 5.5 󰪥 "
ok "skips an unknown effort level" "$(effort turbo)" "Opus 5.5"
# Claude Code's session cost leaves out its forks, so it misleads.
ok "leads with context, leaves cost out" \
    "$(echo '{"model":{"display_name":"Opus 5.5"},"context_window":{"used_percentage":23.4},"cost":{"total_cost_usd":3.21}}' | "$SL")" \
    '23% Opus 5.5'
# Account-wide, so shown once in the tmux status bar instead (ai-usage.sh).
ok "leaves rate limits out" \
    "$(echo '{"model":{"display_name":"Opus 5.5"},"rate_limits":{"five_hour":{"used_percentage":20},"seven_day":{"used_percentage":40}}}' | "$SL")" \
    'Opus 5.5'

# --- effort record -----------------------------------------------------------
# The live effort goes beside the transcript, where a lab relaunch reads it back.
PD="$TMP/.claude/projects/-p"
mkdir -p "$PD" && touch "$PD/s.jsonl"
render() {
    printf '{"model":{"display_name":"Opus 5.5"},"effort":{"level":"%s"},"transcript_path":"%s"}' "$1" "$2" | "$SL"
}
record() { cat "$PD/.effort" 2>/dev/null; }

ok "renders while recording" "$(render medium "$PD/s.jsonl")" "Opus 5.5 󰪟"
ok "records the effort beside the transcript" "$(record)" medium
render high "$PD/s.jsonl" >/dev/null
ok "records an /effort change" "$(record)" high
# The write goes through a rename, so an unchanged inode means no rewrite.
ino=$(stat -c %i "$PD/.effort")
render high "$PD/s.jsonl" >/dev/null
ok "an unchanged level is not rewritten" "$(stat -c %i "$PD/.effort")" "$ino"
ok "no temp file left beside the record" "$(ls -A "$PD" | tr '\n' ' ')" ".effort s.jsonl "
render turbo "$PD/s.jsonl" >/dev/null
ok "an unknown level keeps the record" "$(record)" high

# Before the first turn there is no transcript to resume, so nothing to record.
PN="$TMP/.claude/projects/-new"
mkdir -p "$PN"
render low "$PN/s.jsonl" >/dev/null
ok "no transcript file, no record" "$(ls -A "$PN")" ""
ok "no transcript path still renders" "$(render low '')" "Opus 5.5 󰝦"
# A relative path would resolve against the cwd ($TMP), so it must not count.
mkdir rel && touch rel/s.jsonl
render low rel/s.jsonl >/dev/null
ok "a relative transcript path leaves no stray file" "$(ls -A rel)" s.jsonl

report

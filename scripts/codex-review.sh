#!/usr/bin/env bash
# Review the branch diff with Codex: a second vendor's read beside the Claude
# reviewers. Codex gets the same review-diff.sh output they do, on stdin, in a
# read-only sandbox, and its final message becomes the report.
#
# Never fails the review it serves: a missing, failing or silent codex still exits
# 0 and leaves a report saying why, which the synthesizer reads as "no findings".
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Review the branch diff with Codex (gpt-6.2-sol) and write its findings to a report."
    echo "Usage: codex-review.sh <report-path>"
    exit 0
fi

REPORT="${1:?usage: codex-review.sh <report-path>}"
MODEL=gpt-6.2-sol
# Under the Bash tool's 10-minute ceiling, so the caller sees the report, not a kill.
TIMEOUT=540

mkdir -p "$(dirname "$REPORT")"

unavailable() {
    printf 'Codex review unavailable: %s\n' "$1" > "$REPORT"
    exit 0
}

command -v codex >/dev/null || unavailable "codex not installed"

read -r -d '' PROMPT <<'EOF'
You are one reviewer in a multi-reviewer branch review. Others cover readability,
architecture, performance, tests, security and comments. Yours is correctness: does
the change do what it sets out to do?

The diff (merge base to the working tree, untracked files included) is in the
<stdin> block. You are in the repository with read-only access: read the
surrounding code and callers as far as you need to judge a hunk.

Look for wrong behaviour, edge cases the change breaks, regressions in callers,
races, error paths that lose or corrupt state, and contracts the diff breaks.

Report only noteworthy findings: no praise, no style nits, nothing about pre-existing
code the diff does not change. For each: `file:line`, what goes wrong and on what
input, and the fix. If the change is correct, say so in one line.
EOF

stderr=$(mktemp)
trap 'rm -f "$stderr"' EXIT
rm -f "$REPORT"

review-diff.sh | timeout "$TIMEOUT" codex exec -s read-only -m "$MODEL" --color never \
    -o "$REPORT" "$PROMPT" >/dev/null 2>"$stderr"
rc=${PIPESTATUS[1]}

[ "$rc" -eq 124 ] && unavailable "timed out after ${TIMEOUT}s"
[ "$rc" -ne 0 ] && unavailable "codex exited $rc
$(tail -n 20 "$stderr")"
[ -s "$REPORT" ] || unavailable "codex returned no final message"
exit 0

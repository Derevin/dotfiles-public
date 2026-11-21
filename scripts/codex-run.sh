#!/usr/bin/env bash
# Run Codex non-interactively on the prompt from stdin, registered in the fork
# registry like a Claude fork: ~/.claude/forks/<run-id>/meta.json is open while
# Codex runs and closed on every exit, its transcript the Codex rollout file, so
# fork-recover.sh lists and pings it. The run's prompt, event log and (without -o)
# final message live in that entry's scratch directory.
#
# Stdout carries the run id alone, printed before Codex starts. Failure is a
# non-zero exit with the reason on stderr.
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Run Codex (gpt-6.2-sol) on the prompt from stdin, registered in the fork registry."
    echo "Usage: codex-run.sh [-l LABEL] [-e EFFORT] [-s SANDBOX|bypass] [-C DIR] [-o FILE] [--resume ID | --resume-latest] < prompt"
    echo
    echo "  -l LABEL         what the run is for (implement, cold-read, review), kept in meta.json"
    echo "  -e EFFORT        reasoning effort; unset leaves Codex's default"
    echo "  -s SANDBOX       read-only | workspace-write | danger-full-access | bypass"
    echo "  -C DIR           working root (default: current directory)"
    echo "  -o FILE          final message (default: the entry's scratch/final.md)"
    echo "  --resume ID      continue Codex session ID with the prompt as the next turn"
    echo "  --resume-latest  continue the newest closed run with this label and DIR;"
    echo "                   exit 3 when there is none, before any side effect"
    echo
    echo "Exits 75 before any side effect when Codex is near its usage limit"
    echo "(5-hour window >= 93% or week >= 98%), for the caller to fall back to Claude."
    exit 0
fi

MODEL=gpt-6.2-sol
MAX_5H=93
MAX_WEEK=98
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="${FORK_REGISTRY_ROOT:-$HOME/.claude/forks}"
SESSIONS="${CODEX_HOME:-$HOME/.codex}/sessions"

die() { echo "codex-run.sh: $1" >&2; exit "${2:-1}"; }

LABEL="" EFFORT="" SANDBOX="" DIR="$PWD" OUTPUT="" RESUME="" LATEST=0
while [ $# -gt 0 ]; do
    case "$1" in
    -l|-e|-s|-C|-o|--resume)
        [ $# -ge 2 ] || die "$1 needs a value" 2
        case "$1" in
        -l) LABEL=$2 ;; -e) EFFORT=$2 ;; -s) SANDBOX=$2 ;;
        -C) DIR=$2 ;; -o) OUTPUT=$2 ;; --resume) RESUME=$2 ;;
        esac
        shift ;;
    --resume-latest) LATEST=1 ;;
    *) die "unknown argument: $1" 2 ;;
    esac
    shift
done
[ -n "$RESUME" ] && [ "$LATEST" = 1 ] && die "--resume and --resume-latest are exclusive" 2

# -s: a symlinked -o is replaced, not its target deleted by the rm below.
[ -z "$OUTPUT" ] || OUTPUT=$(realpath -ms -- "$OUTPUT")
cd "$DIR" 2>/dev/null || die "no such directory: $DIR" 2
DIR=$PWD

# A lab worktree serves one task, so its newest closed run under a label is that
# task's run. Closed only: an open entry is still going, or died mid-turn.
if [ "$LATEST" = 1 ]; then
    # Parsable codex entries only: one broken file would fail a slurp of all, and
    # read as nothing to resume.
    runs=()
    mapfile -t codex < <(grep -l '"agent_type": *"codex"' "$ROOT"/*/meta.json 2>/dev/null)
    for f in "${codex[@]}"; do
        jq -e . "$f" >/dev/null 2>&1 && runs+=("$f")
    done
    [ "${#runs[@]}" -gt 0 ] && RESUME=$(jq -rs --arg l "$LABEL" --arg c "$DIR" '
        [ .[] | select(.agent_type == "codex" and .status == "closed"
                       and (.label // "") == $l and .cwd == $c
                       and (.codex_session_id // "") != "") ]
        | sort_by(.started // "") | last | .codex_session_id // empty' \
        "${runs[@]}" 2>/dev/null)
    [ -n "$RESUME" ] || die "no closed '$LABEL' run to resume in $DIR" 3
fi

command -v codex >/dev/null || die "codex not found" 127

# No snapshot reads as headroom: a fresh install has logged none yet.
if read -r used5 usedweek < <("$SCRIPT_DIR/codex-usage.sh" 2>/dev/null) \
    && { [ "$used5" -ge "$MAX_5H" ] || [ "$usedweek" -ge "$MAX_WEEK" ]; }; then
    die "codex near its usage limit (5h $used5%, week $usedweek%)" 75
fi

ID="codex-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
ENTRY="$ROOT/$ID"
SCRATCH="$ENTRY/scratch"
META="$ENTRY/meta.json"
mkdir -p "$SCRATCH" || die "cannot create $ENTRY"
[ -n "$OUTPUT" ] || OUTPUT="$SCRATCH/final.md"
mkdir -p "$(dirname "$OUTPUT")" || die "cannot create $(dirname "$OUTPUT")"
rm -f "$OUTPUT"

# Through a tmp file: a failed jq would otherwise leave a truncated meta.json,
# which lists as neither open nor closed.
meta_set() {
    jq "$@" "$META" >"$META.tmp" 2>/dev/null && mv "$META.tmp" "$META"
}

transcript=""
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    for t in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$CLAUDE_CODE_SESSION_ID".jsonl; do
        [ -f "$t" ] && { transcript=$t; break; }
    done
fi

# pid is this wrapper's, not the Claude session's: fork-recover.sh reads a dead pid
# under an open entry as DEAD, which for a Codex run is exactly a killed wrapper.
jq -n --arg id "$ID" --arg label "$LABEL" --arg sess "${CLAUDE_CODE_SESSION_ID:-}" \
    --arg cwd "$DIR" --arg st "$transcript" --arg out "$OUTPUT" --arg pid "$$" \
    --arg started "$(date -Iseconds)" \
    '{agent_id: $id, agent_type: "codex", label: $label, session_id: $sess, cwd: $cwd,
      session_transcript: $st, fork_transcript: "", codex_session_id: "",
      output: $out, pid: $pid, started: $started, status: "open"}' >"$META" \
    || die "cannot write $META"

cpid=""
rc=1
close() {
    # Codex leads its own process group, so the commands it started go with it.
    [ -n "$cpid" ] && { kill -- "-$cpid" 2>/dev/null; wait "$cpid" 2>/dev/null; }
    meta_set --arg ended "$(date -Iseconds)" --argjson rc "$rc" \
        '. + {status: "closed", ended: $ended, exit: $rc}'
}
trap close EXIT
trap 'rc=143; exit 143' TERM
trap 'rc=130; exit 130' INT
trap 'rc=129; exit 129' HUP

echo "$ID"
cat >"$SCRATCH/prompt.md"

args=(-m "$MODEL" --json -o "$OUTPUT")
[ -n "$EFFORT" ] && args+=(-c "model_reasoning_effort=\"$EFFORT\"")
if [ "$SANDBOX" = bypass ]; then
    args+=(--dangerously-bypass-approvals-and-sandbox)
elif [ -n "$SANDBOX" ]; then
    # Resume takes no -s; the config key reaches both.
    if [ -n "$RESUME" ]; then args+=(-c "sandbox_mode=\"$SANDBOX\""); else args+=(-s "$SANDBOX"); fi
fi
if [ -n "$RESUME" ]; then
    # Resume takes no -C either: it runs where the process is, which is $DIR.
    cmd=(codex exec resume "${args[@]}" "$RESUME" -)
else
    cmd=(codex exec "${args[@]}" -C "$DIR" -)
fi

sid="" rollout=""
[ -n "$RESUME" ] && { sid=$RESUME; meta_set --arg s "$sid" '.codex_session_id = $s'; }
# The first event names the session; the rollout file named after it appears
# once Codex writes its first turn.
discover() {
    if [ -z "$sid" ]; then
        sid=$(grep -m1 -o '"thread_id": *"[^"]*"' "$SCRATCH/events.jsonl" 2>/dev/null | cut -d'"' -f4)
        [ -n "$sid" ] && meta_set --arg s "$sid" '.codex_session_id = $s'
    fi
    if [ -n "$sid" ] && [ -z "$rollout" ]; then
        rollout=$(find "$SESSIONS" -name "rollout-*-$sid.jsonl" -print -quit 2>/dev/null)
        [ -n "$rollout" ] && meta_set --arg r "$rollout" '.fork_transcript = $r'
    fi
}

setsid "${cmd[@]}" <"$SCRATCH/prompt.md" >"$SCRATCH/events.jsonl" 2>"$SCRATCH/stderr.log" &
cpid=$!
# Bounded: each try walks the whole sessions tree, and a rollout that never
# appears would otherwise be searched for all run long.
tries=0
while [ -z "$rollout" ] && [ "$tries" -lt 300 ] && kill -0 "$cpid" 2>/dev/null; do
    sleep 1
    tries=$((tries + 1))
    discover
done
wait "$cpid"
rc=$?
cpid=""
discover

if [ "$rc" -ne 0 ]; then
    echo "codex-run.sh: codex exited $rc" >&2
    tail -n 20 "$SCRATCH/stderr.log" >&2
    exit "$rc"
fi
if [ ! -s "$OUTPUT" ]; then
    rc=1
    die "codex returned no final message"
fi
exit 0

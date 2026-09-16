#!/usr/bin/env bash
# Assertions shared by the test scripts. Source, don't execute.
# A test file counts and reports; `[ "$FAILS" -eq 0 ]` is its exit status.

TESTS=0
FAILS=0

# ok <name> <actual> <expected>
ok() {
    TESTS=$((TESTS + 1))
    if [ "$2" = "$3" ]; then return 0; fi
    FAILS=$((FAILS + 1))
    printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$3" "$2" >&2
}

# fails <cmd...> — the command must exit non-zero.
fails() {
    TESTS=$((TESTS + 1))
    if ! "$@" >/dev/null 2>&1; then return 0; fi
    FAILS=$((FAILS + 1))
    printf 'FAIL %s: expected non-zero exit\n' "$*" >&2
}

report() {
    printf '%d tests, %d failures\n' "$TESTS" "$FAILS"
    [ "$FAILS" -eq 0 ]
}

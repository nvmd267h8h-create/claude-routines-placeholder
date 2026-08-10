#!/bin/sh
# Runs the built reedit CLI over every fixture and checks outputs against
# committed goldens. Used by CI (both platforms) and locally.
#
# usage: verify-fixtures.sh <path-to-reedit-binary> [out-dir]
set -u

BIN="$1"
OUT="${2:-out}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/Tests/Fixtures"
GOLDENS="$ROOT/Tests/GoldenFiles"

mkdir -p "$OUT"
failures=0

fail() {
    echo "FAIL: $1" >&2
    failures=$((failures + 1))
}

check_valid_fixture() {
    input="$1"
    name="$2"

    echo "== $name"

    "$BIN" inspect "$input" > "$OUT/$name.inspect.txt"
    if [ $? -ne 0 ]; then
        fail "$name: inspect exited non-zero"
    elif [ -f "$GOLDENS/$name.inspect.golden.txt" ]; then
        if ! diff -u "$GOLDENS/$name.inspect.golden.txt" "$OUT/$name.inspect.txt"; then
            fail "$name: inspect output differs from golden"
        fi
    fi

    "$BIN" validate "$input" > "$OUT/$name.validate.txt"
    if [ $? -ne 0 ]; then
        fail "$name: validate reported errors"
        cat "$OUT/$name.validate.txt" >&2
    fi

    "$BIN" roundtrip "$input" --output "$OUT/$name.roundtrip.fcpxml" > "$OUT/$name.roundtrip.txt"
    if [ $? -ne 0 ]; then
        fail "$name: roundtrip exited non-zero"
        cat "$OUT/$name.roundtrip.txt" >&2
    elif [ -f "$GOLDENS/$name.roundtrip.golden.fcpxml" ]; then
        if ! cmp -s "$GOLDENS/$name.roundtrip.golden.fcpxml" "$OUT/$name.roundtrip.fcpxml"; then
            fail "$name: roundtrip bytes differ from golden"
        fi
    fi

    "$BIN" graph "$input" --json "$OUT/$name.graph.json" > "$OUT/$name.graph.txt"
    if [ $? -ne 0 ]; then
        fail "$name: graph exited non-zero"
    elif [ ! -s "$OUT/$name.graph.json" ]; then
        fail "$name: graph JSON is empty"
    fi
    # Graph JSON golden equality is asserted structurally in swift test;
    # byte formats differ between Foundation implementations.
}

expect_exit() {
    description="$1"
    expected="$2"
    shift 2
    "$@" > /dev/null 2>&1
    actual=$?
    if [ "$actual" -ne "$expected" ]; then
        fail "$description: expected exit $expected, got $actual"
    else
        echo "== $description: exit $actual as expected"
    fi
}

for input in "$FIXTURES"/valid/*.fcpxml; do
    [ -e "$input" ] || continue
    check_valid_fixture "$input" "$(basename "$input" .fcpxml)"
done
for input in "$FIXTURES"/valid/*.fcpxmld; do
    [ -d "$input" ] || continue
    check_valid_fixture "$input" "$(basename "$input" .fcpxmld)"
done

# Invalid fixtures must fail with their documented exit codes
# (1 findings, 2 usage, 3 load error — docs/phase0-conventions.md).
expect_exit "e01 malformed rejects load" 3 "$BIN" inspect "$FIXTURES/invalid/e01-malformed.fcpxml"
expect_exit "e02 missing version rejects load" 3 "$BIN" inspect "$FIXTURES/invalid/e02-missing-version.fcpxml"
expect_exit "e03 bad times fail validation" 1 "$BIN" validate "$FIXTURES/invalid/e03-bad-time.fcpxml"
expect_exit "e04 dangling ref fails validation" 1 "$BIN" validate "$FIXTURES/invalid/e04-dangling-ref.fcpxml"
expect_exit "e05 empty bundle rejects load" 3 "$BIN" inspect "$FIXTURES/invalid/e05-empty-bundle.fcpxmld"
expect_exit "usage error on unknown command" 2 "$BIN" frobnicate
expect_exit "roundtrip refuses to overwrite source" 3 "$BIN" roundtrip \
    "$FIXTURES/valid/f01-simple-25fps.fcpxml" --output "$FIXTURES/valid/f01-simple-25fps.fcpxml"
expect_exit "graph refuses to overwrite source" 3 "$BIN" graph \
    "$FIXTURES/valid/f01-simple-25fps.fcpxml" --json "$FIXTURES/valid/f01-simple-25fps.fcpxml"
expect_exit "graph refuses to write inside a bundle input" 3 "$BIN" graph \
    "$FIXTURES/valid/f06-bundle.fcpxmld" --json "$FIXTURES/valid/f06-bundle.fcpxmld/graph.json"
expect_exit "roundtrip refuses .fcpxmld output paths" 3 "$BIN" roundtrip \
    "$FIXTURES/valid/f01-simple-25fps.fcpxml" --output "$OUT/refused.fcpxmld"

if [ "$failures" -gt 0 ]; then
    echo "verify-fixtures: $failures failure(s)" >&2
    exit 1
fi
echo "verify-fixtures: all checks passed"

#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
ROOT=$(dirname "$SCRIPT_DIR")
CLI=$ROOT/bin/generex
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/generex-cli-test.XXXXXX")
OUT=$TEMP_DIR/out
ERR=$TEMP_DIR/err
ASSERTIONS=0

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf 'generex_cli_test: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    ASSERTIONS=$((ASSERTIONS + 1))
    [ "$1" = "$2" ] || fail "$3: expected [$2], got [$1]"
}

assert_empty_file() {
    ASSERTIONS=$((ASSERTIONS + 1))
    [ ! -s "$1" ] || fail "$2: expected empty file"
}

assert_contains() {
    ASSERTIONS=$((ASSERTIONS + 1))
    grep -F "$2" "$1" >/dev/null 2>&1 || fail "$3: missing [$2]"
}

run_generex() {
    set +e
    "$CLI" "$@" >"$OUT" 2>"$ERR"
    RC=$?
    set -e
}

run_generex --help
assert_eq "$RC" 0 'help status'
assert_contains "$OUT" 'generex enumerate [OPTIONS] PATTERN' 'help usage'
assert_empty_file "$ERR" 'help stderr'

run_generex --version
assert_eq "$RC" 0 'version status'
assert_eq "$(cat "$OUT")" 'generex 0.0.0 (Generex 1.0.2)' 'version output'
assert_empty_file "$ERR" 'version stderr'

run_generex enumerate --limit 8 '[ab]{1,2}'
assert_eq "$RC" 0 'enumerate status'
assert_eq "$(cat "$OUT")" '{"value":"a"}
{"value":"aa"}
{"value":"ab"}
{"value":"b"}
{"value":"ba"}
{"value":"bb"}' 'enumerate output'
assert_empty_file "$ERR" 'enumerate stderr'

run_generex enumerate --limit 0 '[ab]'
assert_eq "$RC" 0 'zero limit status'
assert_empty_file "$OUT" 'zero limit output'

run_generex count '[ab]{2}'
assert_eq "$(cat "$OUT")" 4 'finite count'
run_generex count 'a*'
assert_eq "$(cat "$OUT")" infinite 'infinite count'
run_generex first '[ba]{2}'
assert_eq "$(cat "$OUT")" '{"value":"aa"}' 'first output'
run_generex nth '[ab]{2}' 2
assert_eq "$(cat "$OUT")" '{"value":"ab"}' 'nth output'

run_generex random --seed 42 --count 3 --min-length 2 --max-length 4 'a+'
assert_eq "$RC" 0 'random status'
assert_eq "$(cat "$OUT")" '{"value":"aaaa"}
{"value":"aa"}
{"value":"aa"}' 'seeded random output'

printf '[ab]{2}' >"$TEMP_DIR/pattern"
run_generex count --input "$TEMP_DIR/pattern"
assert_eq "$RC" 0 'file input status'
assert_eq "$(cat "$OUT")" 4 'file input output'

printf '[ab]{2}' | "$CLI" count --input - >"$OUT" 2>"$ERR"
assert_eq "$(cat "$OUT")" 4 'stdin input output'
assert_empty_file "$ERR" 'stdin input stderr'

run_generex enumerate -- '-x'
assert_eq "$(cat "$OUT")" '{"value":"-x"}' 'leading hyphen pattern'

run_generex enumerate ''
assert_eq "$(cat "$OUT")" '{"value":""}' 'empty pattern value'

TAB=$(printf '\t')
run_generex enumerate "$TAB"
assert_eq "$(cat "$OUT")" '{"value":"\t"}' 'JSON control escaping'

run_generex enumerate '(café|茶)'
assert_eq "$(cat "$OUT")" '{"value":"茶"}
{"value":"café"}' 'Unicode enumeration'

run_generex enumerate '('
assert_eq "$RC" 1 'invalid regex status'
assert_empty_file "$OUT" 'invalid regex stdout'
assert_contains "$ERR" 'generex: cannot build generator:' 'invalid regex diagnostic'

printf '\377' >"$TEMP_DIR/invalid-utf8"
run_generex count --input "$TEMP_DIR/invalid-utf8"
assert_eq "$RC" 1 'invalid UTF-8 status'
assert_empty_file "$OUT" 'invalid UTF-8 stdout'
assert_contains "$ERR" 'pattern input is not valid UTF-8' 'invalid UTF-8 diagnostic'

run_generex wat
assert_eq "$RC" 2 'unknown command status'
assert_contains "$ERR" 'generex: unknown command wat' 'unknown command diagnostic'
assert_contains "$ERR" "Try 'generex --help' for usage." 'usage hint'

run_generex nth '[ab]' 0
assert_eq "$RC" 2 'invalid index status'
assert_contains "$ERR" 'INDEX must be an integer from 1' 'invalid index diagnostic'

run_generex count '[ab]' --input "$TEMP_DIR/pattern"
assert_eq "$RC" 2 'conflicting source status'
assert_contains "$ERR" 'PATTERN and --input are mutually exclusive' 'conflicting source diagnostic'

(cd "$TEMP_DIR" && "$CLI" count '[ab]' >"$OUT" 2>"$ERR")
assert_eq "$(cat "$OUT")" 2 'outside checkout output'
assert_empty_file "$ERR" 'outside checkout stderr'

mkdir -p "$TEMP_DIR/fixture/bin"
cp "$CLI" "$TEMP_DIR/fixture/bin/generex"
set +e
"$TEMP_DIR/fixture/bin/generex" --help >"$OUT" 2>"$ERR"
RC=$?
set -e
assert_eq "$RC" 1 'missing bootstrap status'
assert_contains "$ERR" 'project-local Clojure CLI is missing' 'missing bootstrap diagnostic'

printf 'generex CLI tests passed: %s assertions\n' "$ASSERTIONS"

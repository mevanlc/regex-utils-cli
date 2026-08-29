#!/bin/sh

set -eu

PROGRAM=regextrie-c-cli-test
BINARY=$1
ROOT=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/regextrie-c-cli.XXXXXX")
OUT=$TEMP_DIR/stdout
ERR=$TEMP_DIR/stderr
EXPECTED=$TEMP_DIR/expected
STATUS=0
ASSERTIONS=0

cleanup() {
    chmod 600 "$TEMP_DIR/unreadable" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf '%s: %s\n' "$PROGRAM" "$1" >&2
    exit 1
}

pass() {
    ASSERTIONS=$((ASSERTIONS + 1))
}

run() {
    : >"$OUT"
    : >"$ERR"
    set +e
    "$BINARY" "$@" >"$OUT" 2>"$ERR"
    STATUS=$?
    set -e
}

assert_status() {
    [ "$STATUS" -eq "$1" ] || fail "$2: expected status $1, got $STATUS"
    pass
}

assert_empty() {
    [ ! -s "$1" ] || fail "$2: expected empty output"
    pass
}

assert_contains() {
    grep -F -- "$1" "$2" >/dev/null 2>&1 || fail "$3: missing '$1'"
    pass
}

assert_output() {
    printf '%s' "$1" >"$EXPECTED"
    cmp -s "$EXPECTED" "$OUT" || fail "$2: unexpected stdout"
    pass
}

[ -x "$BINARY" ] || fail "built executable is missing"

run --version
assert_status 0 "version"
assert_output 'regextrie-c 0.0.0 (RegexTrie c35e88931f64)
' "version"
assert_empty "$ERR" "version"
run --help
assert_status 0 "help"
assert_contains 'Usage:' "$OUT" "help"
assert_contains '--insert-mode' "$OUT" "help"
assert_contains '--query-input' "$OUT" "help"
assert_empty "$ERR" "help"

run -q foo -q '?oo' -q '???' -q qux -- foo bar
assert_status 0 "regex mode"
assert_output '{"query":"foo","found":true,"insert_mode":"regex"}
{"query":"?oo","found":true,"insert_mode":"regex"}
{"query":"???","found":true,"insert_mode":"regex"}
{"query":"qux","found":false,"insert_mode":"regex"}
' "regex mode"
assert_empty "$ERR" "regex mode"

run --insert-mode word -q foo -q FOO -q '&//' -q '?oo' -- foo
assert_status 0 "word aliases"
assert_output '{"query":"foo","found":true,"insert_mode":"word"}
{"query":"FOO","found":true,"insert_mode":"word"}
{"query":"&//","found":true,"insert_mode":"word"}
{"query":"?oo","found":false,"insert_mode":"word"}
' "word aliases"

run -m word -q 'a@b' -q ab -q 'a@@b' -- 'a@b'
assert_status 0 "at collision"
assert_contains '{"query":"a@b","found":true' "$OUT" "at collision"
assert_contains '{"query":"ab","found":true' "$OUT" "at collision"
assert_contains '{"query":"a@@b","found":true' "$OUT" "at collision"
run -m word -q 'a@b' -- ab
assert_contains '{"query":"a@b","found":false' "$OUT" "at asymmetric collision"

printf 'foo\r\nbar\r\n' >"$TEMP_DIR/words"
printf '?oo\nba?\nother\n' >"$TEMP_DIR/queries"
run --input "$TEMP_DIR/words" --query-input "$TEMP_DIR/queries"
assert_status 0 "file records"
assert_output '{"query":"?oo","found":true,"insert_mode":"regex"}
{"query":"ba?","found":true,"insert_mode":"regex"}
{"query":"other","found":false,"insert_mode":"regex"}
' "file records"

printf '?oo\r\nba?\n' | "$BINARY" --input "$TEMP_DIR/words" --query-input - >"$OUT" 2>"$ERR"
assert_output '{"query":"?oo","found":true,"insert_mode":"regex"}
{"query":"ba?","found":true,"insert_mode":"regex"}
' "query stdin"
assert_empty "$ERR" "query stdin"

printf 'foo\n\nbar\n' >"$TEMP_DIR/interior-empty"
run --input "$TEMP_DIR/interior-empty" -q '' -q foo
assert_status 0 "interior empty"
assert_contains '{"query":"","found":true' "$OUT" "interior empty"
assert_contains '{"query":"foo","found":true' "$OUT" "interior empty"
printf '\n' >"$TEMP_DIR/one-empty"
run --input "$TEMP_DIR/one-empty" -q ''
assert_contains '{"query":"","found":true' "$OUT" "one empty dictionary"
: >"$TEMP_DIR/empty"
run --input "$TEMP_DIR/empty" -q ''
assert_contains '{"query":"","found":false' "$OUT" "zero dictionary"

run -m word -q 'line
break' -q 'tea 茶' -q 'quote"slash\tab	' -- 'line
break' 'tea 茶' 'quote"slash\tab	'
assert_status 0 "argv controls and Unicode"
assert_contains '"query":"line\nbreak"' "$OUT" "JSON newline"
assert_contains '"query":"tea 茶"' "$OUT" "raw Unicode"
assert_contains '"query":"quote\"slash\\tab\t"' "$OUT" "JSON escaping"

run -m regex -q _oo -q '?oo' -q FOO -- foo foo
assert_status 0 "duplicates and wildcard aliases"
assert_contains '{"query":"_oo","found":true' "$OUT" "underscore alias"
assert_contains '{"query":"?oo","found":true' "$OUT" "question wildcard"
assert_contains '{"query":"FOO","found":true' "$OUT" "case alias"

run -m word -q foo -q missing -q foo -- foo
assert_output '{"query":"foo","found":true,"insert_mode":"word"}
{"query":"missing","found":false,"insert_mode":"word"}
{"query":"foo","found":true,"insert_mode":"word"}
' "query order and duplicates"

run -q '??' -q '?' -- 'é'
assert_status 0 "bytewise UTF-8 wildcarding"
assert_contains '{"query":"??","found":true' "$OUT" "two-byte Unicode wildcard"
assert_contains '{"query":"?","found":false' "$OUT" "Unicode byte length"

run --bogus
assert_status 2 "unknown option"
run -hV
assert_status 2 "combined short options"
run --input=words
assert_status 2 "equals-form option"
run -m invalid
assert_status 2 "invalid mode"
run -i
assert_status 2 "missing input value"
run -q
assert_status 2 "missing query value"

run --input one --input two -q x
assert_status 2 "repeated input"
run -m word -m regex -q x -- x
assert_status 2 "repeated mode"
run -Q one -Q two -- x
assert_status 2 "repeated query input"
run --input one -q x -- x
assert_status 2 "mixed dictionary source"
run -q x -Q queries -- x
assert_status 2 "mixed query source"
run -- x
assert_status 2 "missing query source"
run -q x
assert_status 2 "missing dictionary source"
run --input - --query-input -
assert_status 2 "two stdin sources"
run -q x -word
assert_status 2 "option-like dictionary"

run --input "$TEMP_DIR/missing" -q x
assert_status 1 "missing input"
assert_empty "$OUT" "missing input"
printf 'foo\n' >"$TEMP_DIR/unreadable"
chmod 000 "$TEMP_DIR/unreadable"
run --input "$TEMP_DIR/unreadable" -q foo
chmod 600 "$TEMP_DIR/unreadable"
assert_status 1 "unreadable input"
printf '\377\n' >"$TEMP_DIR/invalid-utf8"
run --input "$TEMP_DIR/invalid-utf8" -q x
assert_status 1 "invalid UTF-8"
printf 'foo\000bar\n' >"$TEMP_DIR/nul"
run --input "$TEMP_DIR/nul" -q foo
assert_status 1 "dictionary NUL"
printf 'foo\000bar\n' >"$TEMP_DIR/query-nul"
run --query-input "$TEMP_DIR/query-nul" -- foo
assert_status 1 "query NUL"
: >"$TEMP_DIR/empty-queries"
run --query-input "$TEMP_DIR/empty-queries" -- foo
assert_status 1 "zero queries"

dd if=/dev/zero bs=1025 count=1 2>/dev/null | tr '\000' a >"$TEMP_DIR/long-record"
run --input "$TEMP_DIR/long-record" -q x -m word
assert_status 1 "record limit"
dd if=/dev/zero bs=1048576 count=17 2>/dev/null >"$TEMP_DIR/large-source"
run --input "$TEMP_DIR/large-source" -q x -m word
assert_status 1 "source limit"
run -q x -- 12345678901234567
assert_status 1 "regex record limit"
run -q abcdefghijklmnop -- abcdefghijklmnop abcdefghijklmnop
assert_status 1 "regex expansion limit"

run -q abcdefghijklmnop -- abcdefghijklmnop
assert_status 0 "regex expansion boundary"
assert_contains '{"query":"abcdefghijklmnop","found":true' "$OUT" "expansion boundary"

STATUS=0
REGEX_UTILS_CLI_TEST_FAIL_ALLOC_AFTER=0 "$BINARY" -q foo -- foo >"$OUT" 2>"$ERR" || STATUS=$?
assert_status 1 "allocation failure"
assert_empty "$OUT" "allocation failure"
assert_contains 'regextrie-c:' "$ERR" "allocation failure"
STATUS=0
REGEX_UTILS_CLI_TEST_FAIL_ALLOC_AFTER=4 "$BINARY" -q foo -- foo >"$OUT" 2>"$ERR" || STATUS=$?
assert_status 1 "output allocation failure"
assert_empty "$OUT" "output allocation failure"
assert_contains 'cannot allocate output buffer' "$ERR" "output allocation failure"

FIFO=$TEMP_DIR/closed-pipe
QUERY_FILE=$TEMP_DIR/many-queries
mkfifo "$FIFO"
i=0
while [ "$i" -lt 10000 ]; do
    printf 'foo\n'
    i=$((i + 1))
done >"$QUERY_FILE"
dd if="$FIFO" of=/dev/null bs=1 count=0 2>/dev/null &
READER_PID=$!
set +e
"$BINARY" -m word --query-input "$QUERY_FILE" -- foo >"$FIFO" 2>"$ERR"
STATUS=$?
set -e
wait "$READER_PID"
assert_status 0 "closed pipe"
assert_empty "$ERR" "closed pipe"

EXTERNAL=$TEMP_DIR/external
mkdir -p "$EXTERNAL"
printf 'foo\n' >"$EXTERNAL/relative-words"
(
    cd "$EXTERNAL"
    "$ROOT/bin/regextrie-c" --input relative-words -q foo >"$OUT" 2>"$ERR"
)
assert_output '{"query":"foo","found":true,"insert_mode":"regex"}
' "launcher external cwd"
assert_empty "$ERR" "launcher external cwd"

FIXTURE=$TEMP_DIR/launcher-fixture
mkdir -p "$FIXTURE/bin"
cp "$ROOT/bin/regextrie-c" "$FIXTURE/bin/regextrie-c"
set +e
"$FIXTURE/bin/regextrie-c" --version >"$OUT" 2>"$ERR"
STATUS=$?
set -e
assert_status 1 "missing launcher target"
assert_empty "$OUT" "missing launcher target"
assert_output '' "missing launcher target"
assert_contains 'build/native/bin/regextrie-c is missing; run cmake -S . -B build/native -DCMAKE_BUILD_TYPE=Debug, then cmake --build build/native' "$ERR" "missing launcher target"

printf '%s: passed %s assertions\n' "$PROGRAM" "$ASSERTIONS"

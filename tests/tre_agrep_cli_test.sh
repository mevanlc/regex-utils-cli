#!/bin/sh

set -eu

PROGRAM=tre_agrep_cli_test
AGREP=${1-}
ASSERTIONS=0
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tre-agrep-cli-test.XXXXXX")
OUT=$TEMP_DIR/stdout
ERR=$TEMP_DIR/stderr
EXPECTED=$TEMP_DIR/expected
INPUT=$TEMP_DIR/input
STATUS=0

cleanup() {
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

assert_status() {
    [ "$STATUS" -eq "$1" ] || fail "$2: expected status $1, got $STATUS"
    pass
}

assert_stdout() {
    cmp -s "$EXPECTED" "$OUT" || fail "$1: unexpected stdout"
    pass
}

assert_empty() {
    [ ! -s "$1" ] || fail "$2: expected an empty file"
    pass
}

assert_contains() {
    grep -F -- "$1" "$2" >/dev/null 2>&1 || fail "$3: missing '$1'"
    pass
}

run_agrep() {
    : >"$OUT"
    : >"$ERR"
    set +e
    LC_ALL=C "$AGREP" "$@" >"$OUT" 2>"$ERR"
    STATUS=$?
    set -e
}

run_stdin() {
    : >"$OUT"
    : >"$ERR"
    set +e
    LC_ALL=C "$AGREP" "$@" <"$INPUT" >"$OUT" 2>"$ERR"
    STATUS=$?
    set -e
}

run_in_dir() {
    directory=$1
    shift
    : >"$OUT"
    : >"$ERR"
    set +e
    (cd "$directory" && LC_ALL=C "$AGREP" "$@") >"$OUT" 2>"$ERR"
    STATUS=$?
    set -e
}

[ "$#" -eq 1 ] || fail "usage: $PROGRAM /absolute/path/to/agrep"
case $AGREP in
    /*/tre-install/bin/agrep) ;;
    *) fail "agrep must be the absolute project-local tre-install path" ;;
esac
[ -x "$AGREP" ] || fail "agrep is not executable: $AGREP"

run_agrep --help
assert_status 0 "help"
assert_empty "$ERR" "help stderr"
assert_contains 'Usage: agrep [OPTION]... PATTERN [FILE]...' "$OUT" "help"
assert_contains 'Approximate matching settings:' "$OUT" "help"
assert_contains '--show-position' "$OUT" "help"

run_agrep --version
assert_status 0 "version"
assert_empty "$ERR" "version stderr"
assert_contains 'agrep (TRE agrep) 0.9.0' "$OUT" "version"

printf 'optimize\noptimise\noptmise\nopitmize\nother\n' >"$INPUT"
run_stdin -2 -n -s --show-position optimize
assert_status 0 "representative fuzzy search"
printf '1:0:0-8:optimize\n2:1:0-8:optimise\n3:2:0-7:optmise\n4:2:0-8:opitmize\n' >"$EXPECTED"
assert_stdout "representative fuzzy search"
assert_empty "$ERR" "representative fuzzy search stderr"

printf 'optimize\noptimise\n' >"$INPUT"
run_stdin optimize
assert_status 0 "exact default"
printf 'optimize\n' >"$EXPECTED"
assert_stdout "exact default"

run_stdin -E 1 optimise
assert_status 0 "max-errors option"
printf 'optimize\noptimise\n' >"$EXPECTED"
assert_stdout "max-errors option"

printf 'abc\naxc\nabbc\nac\n' >"$INPUT"
run_stdin -E 2 -I 2 -D 3 -S 4 -s abc
assert_status 0 "nonuniform edit costs"
printf '0:abc\n2:abbc\n' >"$EXPECTED"
assert_stdout "nonuniform edit costs"

printf 'ac\n' >"$INPUT"
run_stdin -E 2 -D 2 -I 4 -S 4 -s abc
assert_status 0 "deletion cost"
printf '2:ac\n' >"$EXPECTED"
assert_stdout "deletion cost"

printf 'abbc\n' >"$INPUT"
run_stdin -E 2 -D 4 -I 2 -S 4 -s abc
assert_status 0 "insertion cost"
printf '2:abbc\n' >"$EXPECTED"
assert_stdout "insertion cost"

printf 'axc\n' >"$INPUT"
run_stdin -E 2 -D 4 -I 4 -S 2 -s abc
assert_status 0 "substitution cost"
printf '2:axc\n' >"$EXPECTED"
assert_stdout "substitution cost"

printf 'abc\naxc\nabbc\nac\nzzz\n' >"$INPUT"
run_stdin -s '(abc){~1}'
assert_status 0 "embedded approximate constraint"
printf '0:abc\n1:axc\n1:abbc\n1:ac\n' >"$EXPECTED"
assert_stdout "embedded approximate constraint"

BEST_FILE=$TEMP_DIR/best.txt
printf 'optimise\noptmise\nother\n' >"$BEST_FILE"
run_agrep -B -2 -s optimize "$BEST_FILE"
assert_status 0 "best named-file match"
printf '1:optimise\n' >"$EXPECTED"
assert_stdout "best named-file match"

printf 'a.b\naxb\n' >"$INPUT"
run_stdin -k 'a.b'
assert_status 0 "literal pattern"
printf 'a.b\n' >"$EXPECTED"
assert_stdout "literal pattern"

printf 'cat\nscatter\ncat!\n' >"$INPUT"
run_stdin -w cat
assert_status 0 "whole-word pattern"
printf 'cat\ncat!\n' >"$EXPECTED"
assert_stdout "whole-word pattern"

printf 'Foo\nfoo\nbar\n' >"$INPUT"
run_stdin -i foo
assert_status 0 "case-insensitive pattern"
printf 'Foo\nfoo\n' >"$EXPECTED"
assert_stdout "case-insensitive pattern"

printf 'x\ny\n' >"$INPUT"
run_stdin -v x
assert_status 0 "inverted selection"
printf 'y\n' >"$EXPECTED"
assert_stdout "inverted selection"

printf 'hit\nmiss\n' >"$INPUT"
run_stdin hit
assert_status 0 "implicit stdin"
printf 'hit\n' >"$EXPECTED"
assert_stdout "implicit stdin"
run_stdin hit -
assert_status 0 "explicit stdin"
assert_stdout "explicit stdin"

FILE_A=$TEMP_DIR/a.txt
FILE_B=$TEMP_DIR/b.txt
printf 'first hit\nmiss\n' >"$FILE_A"
printf 'miss\nhit second\n' >"$FILE_B"
run_agrep -h hit "$FILE_A" "$FILE_B"
assert_status 0 "multiple file order"
printf 'first hit\nhit second\n' >"$EXPECTED"
assert_stdout "multiple file order"

run_agrep -H hit "$FILE_A"
assert_status 0 "forced filename"
printf '%s:first hit\n' "$FILE_A" >"$EXPECTED"
assert_stdout "forced filename"

EXTERNAL_DIR=$TEMP_DIR/external
mkdir "$EXTERNAL_DIR"
run_in_dir "$EXTERNAL_DIR" hit ../a.txt
assert_status 0 "external cwd relative file"
printf 'first hit\n' >"$EXPECTED"
assert_stdout "external cwd relative file"

: >"$INPUT"
run_stdin hit
assert_status 1 "zero-byte input"
assert_empty "$OUT" "zero-byte input stdout"
assert_empty "$ERR" "zero-byte input stderr"

printf 'hit' >"$INPUT"
run_stdin hit
assert_status 0 "record without final delimiter"
printf 'hit' >"$EXPECTED"
assert_stdout "record without final delimiter"

printf 'hit\n' >"$INPUT"
run_stdin hit
assert_status 0 "record with final delimiter"
printf 'hit\n' >"$EXPECTED"
assert_stdout "record with final delimiter"

printf 'a\n\nb\n' >"$INPUT"
run_stdin '^$'
assert_status 0 "interior empty record"
printf '\n' >"$EXPECTED"
assert_stdout "interior empty record"

printf 'catXdogXXeelX' >"$INPUT"
run_stdin -d 'X+' 'cat|dog|eel'
assert_status 0 "custom record delimiter"
printf 'catXdogXXeel' >"$EXPECTED"
assert_stdout "custom record delimiter"
run_stdin -M -d 'X+' 'cat|dog|eel'
assert_status 0 "delimiter-after"
printf 'catXdogXXeelX' >"$EXPECTED"
assert_stdout "delimiter-after"

LONG_FILE=$TEMP_DIR/long.txt
awk 'BEGIN { for (i = 0; i < 20000; i++) printf "a"; print "needle" }' >"$LONG_FILE"
run_agrep needle "$LONG_FILE"
assert_status 0 "long record"
cp "$LONG_FILE" "$EXPECTED"
assert_stdout "long record"

run_agrep -c hit "$FILE_A" "$FILE_B"
assert_status 0 "count output"
printf '%s:1\n%s:1\n' "$FILE_A" "$FILE_B" >"$EXPECTED"
assert_stdout "count output"

run_agrep -l hit "$FILE_A" "$FILE_B"
assert_status 0 "files-with-matches output"
printf '%s\n%s\n' "$FILE_A" "$FILE_B" >"$EXPECTED"
assert_stdout "files-with-matches output"

printf 'beta\nalpha\n' >"$INPUT"
run_stdin -n -s --show-position 'a'
assert_status 0 "record number cost and position"
printf '1:0:3-4:beta\n2:0:0-1:alpha\n' >"$EXPECTED"
assert_stdout "record number cost and position"

printf 'hit one\nhit two\n' >"$INPUT"
run_stdin -m 1 hit
assert_status 0 "maximum count"
printf 'hit one\n' >"$EXPECTED"
assert_stdout "maximum count"
run_stdin -q hit
assert_status 0 "quiet output"
assert_empty "$OUT" "quiet stdout"

printf 'beta\n' >"$INPUT"
run_stdin --color beta
assert_status 0 "default color"
printf '\033[01;31mbeta\033[00m\n' >"$EXPECTED"
assert_stdout "default color"

: >"$OUT"
: >"$ERR"
set +e
GREP_COLOR=35 LC_ALL=C "$AGREP" --colour beta <"$INPUT" >"$OUT" 2>"$ERR"
STATUS=$?
set -e
assert_status 0 "custom color"
printf '\033[35mbeta\033[00m\n' >"$EXPECTED"
assert_stdout "custom color"

UTF8_LOCALE=
for locale_name in C.UTF-8 C.utf8 en_US.UTF-8 UTF-8; do
    if LC_ALL=$locale_name locale charmap >/dev/null 2>&1; then
        UTF8_LOCALE=$locale_name
        break
    fi
done
if [ -n "$UTF8_LOCALE" ]; then
    printf 'CAFÉ\ncafe\n茶\n' >"$INPUT"
    : >"$OUT"
    : >"$ERR"
    set +e
    LC_ALL=$UTF8_LOCALE "$AGREP" -i 'café' <"$INPUT" >"$OUT" 2>"$ERR"
    STATUS=$?
    set -e
    assert_status 0 "UTF-8 case folding"
    printf 'CAFÉ\n' >"$EXPECTED"
    assert_stdout "UTF-8 case folding"

    printf 'é\n1\n茶\n' >"$INPUT"
    set +e
    LC_ALL=$UTF8_LOCALE "$AGREP" '^[[:alpha:]]+$' <"$INPUT" >"$OUT" 2>"$ERR"
    STATUS=$?
    set -e
    assert_status 0 "UTF-8 character class"
    printf 'é\n茶\n' >"$EXPECTED"
    assert_stdout "UTF-8 character class"

    printf 'café\n' >"$INPUT"
    set +e
    LC_ALL=$UTF8_LOCALE "$AGREP" --show-position 'fé' <"$INPUT" >"$OUT" 2>"$ERR"
    STATUS=$?
    set -e
    assert_status 0 "UTF-8 byte position"
    printf '2-5:café\n' >"$EXPECTED"
    assert_stdout "UTF-8 byte position"

    printf '\377\nvalid\n' >"$INPUT"
    set +e
    LC_ALL=$UTF8_LOCALE "$AGREP" '.' <"$INPUT" >"$OUT" 2>"$ERR"
    STATUS=$?
    set -e
    assert_status 1 "invalid UTF-8 input"
    assert_empty "$OUT" "invalid UTF-8 stdout"
    assert_empty "$ERR" "invalid UTF-8 stderr"
fi

printf 'a\000b\n' >"$INPUT"
run_stdin -c '\x00'
assert_status 0 "NUL count"
printf '1\n' >"$EXPECTED"
assert_stdout "NUL count"
run_stdin '\x00'
assert_status 0 "NUL record output"
printf 'a' >"$EXPECTED"
assert_stdout "NUL record truncation"

run_agrep
assert_status 2 "missing pattern"
assert_empty "$OUT" "missing pattern stdout"
assert_contains 'Usage: agrep [OPTION]... PATTERN [FILE]...' "$ERR" "missing pattern"

run_agrep --bogus x
assert_status 1 "unknown option"
assert_empty "$OUT" "unknown option stdout"
assert_contains "unrecognized option \`--bogus'" "$ERR" "unknown option"

run_agrep '['
assert_status 2 "malformed pattern"
assert_contains 'Error in search pattern:' "$ERR" "malformed pattern"

run_agrep -d '[' x
assert_status 2 "malformed delimiter"
assert_contains 'Error in record delimiter pattern:' "$ERR" "malformed delimiter"

run_agrep -d 'a*' x
assert_status 2 "empty-matching delimiter"
assert_contains 'Record delimiter pattern must not match an empty string' "$ERR" "empty-matching delimiter"

printf 'no match\n' >"$INPUT"
run_stdin x
assert_status 1 "no match"
assert_empty "$OUT" "no match stdout"
assert_empty "$ERR" "no match stderr"

MISSING=$TEMP_DIR/missing.txt
run_agrep hit "$MISSING"
assert_status 1 "missing file"
assert_empty "$OUT" "missing file stdout"
assert_contains "$MISSING: No such file or directory" "$ERR" "missing file"

MATCH_FILE=$TEMP_DIR/match.txt
printf 'hit\n' >"$MATCH_FILE"
run_agrep hit "$MISSING" "$MATCH_FILE"
assert_status 0 "missing file masked before match"
printf '%s:hit\n' "$MATCH_FILE" >"$EXPECTED"
assert_stdout "missing file masked before match"
assert_contains "$MISSING: No such file or directory" "$ERR" "missing file masked before match"

run_agrep hit "$MATCH_FILE" "$MISSING"
assert_status 0 "missing file masked after match"
printf '%s:hit\n' "$MATCH_FILE" >"$EXPECTED"
assert_stdout "missing file masked after match"
assert_contains "$MISSING: No such file or directory" "$ERR" "missing file masked after match"

run_agrep x "$TEMP_DIR"
assert_status 1 "read failure"
assert_contains 'Error reading from' "$ERR" "read failure"

printf 'hit\n' >"$INPUT"
run_stdin -B hit
assert_status 1 "best match on stdin"
assert_empty "$OUT" "best match on stdin stdout"
assert_contains 'Cannot use -B when reading from standard input.' "$ERR" "best match on stdin"

printf 'abc\naxc\n' >"$INPUT"
run_stdin -E nope abc
assert_status 0 "nonnumeric max-errors"
printf 'abc\n' >"$EXPECTED"
assert_stdout "nonnumeric max-errors"
run_stdin -E 1junk abc
assert_status 0 "trailing-junk max-errors"
printf 'abc\naxc\n' >"$EXPECTED"
assert_stdout "trailing-junk max-errors"
run_stdin --max-errors=-1 abc
assert_status 0 "negative max-errors"
printf 'abc\n' >"$EXPECTED"
assert_stdout "negative max-errors"

printf 'ac\n' >"$INPUT"
run_stdin -E 1 -D nope -I 4 -S 4 -s abc
assert_status 0 "nonnumeric deletion cost"
printf '0:ac\n' >"$EXPECTED"
assert_stdout "nonnumeric deletion cost"
printf 'abbc\n' >"$INPUT"
run_stdin -E 1 -D 4 -I nope -S 4 -s abc
assert_status 0 "nonnumeric insertion cost"
printf '0:abbc\n' >"$EXPECTED"
assert_stdout "nonnumeric insertion cost"
printf 'axc\n' >"$INPUT"
run_stdin -E 1 -D 4 -I 4 -S nope -s abc
assert_status 0 "nonnumeric substitution cost"
printf '0:axc\n' >"$EXPECTED"
assert_stdout "nonnumeric substitution cost"

printf 'abc\nabc\n' >"$INPUT"
run_stdin -m 1junk abc
assert_status 0 "trailing-junk maximum count"
printf 'abc\n' >"$EXPECTED"
assert_stdout "trailing-junk maximum count"
run_stdin -m nope abc
assert_status 1 "nonnumeric maximum count"
assert_empty "$OUT" "nonnumeric maximum count stdout"
run_stdin -m 0 abc
assert_status 1 "zero maximum count"
assert_empty "$OUT" "zero maximum count stdout"

if [ "${REGEX_UTILS_TRE_SKIP_REGEX_LIMIT_TESTS-0}" != 1 ]; then
    PATTERN_65536=$(awk 'BEGIN { for (i = 0; i < 65536; i++) printf "a" }')
    PATTERN_65537=${PATTERN_65536}a
    printf 'a\n' >"$INPUT"
    run_stdin "$PATTERN_65536"
    assert_status 1 "maximum-length pattern"
    assert_empty "$ERR" "maximum-length pattern stderr"
    run_stdin "$PATTERN_65537"
    assert_status 2 "over-limit pattern"
    assert_contains 'Error in search pattern:' "$ERR" "over-limit pattern"
fi

PIPE_INPUT=$TEMP_DIR/pipe-input.txt
PIPE=$TEMP_DIR/output-pipe
awk 'BEGIN { for (i = 0; i < 100000; i++) print "hit" }' >"$PIPE_INPUT"
mkfifo "$PIPE"
: >"$ERR"
set +e
LC_ALL=C "$AGREP" hit "$PIPE_INPUT" >"$PIPE" 2>"$ERR" &
producer_pid=$!
dd if="$PIPE" of=/dev/null bs=1 count=1 2>/dev/null
DD_STATUS=$?
wait "$producer_pid"
STATUS=$?
set -e
[ "$DD_STATUS" -eq 0 ] || fail "broken pipe reader failed with status $DD_STATUS"
pass
[ "$STATUS" -ge 128 ] || fail "broken pipe: expected signal status, got $STATUS"
pass
assert_empty "$ERR" "broken pipe stderr"

printf '%s: TRE agrep CLI tests passed: %s assertions\n' "$PROGRAM" "$ASSERTIONS"

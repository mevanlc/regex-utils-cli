#!/bin/sh

set -u

if [ "$#" -ne 2 ]; then
  echo 'usage: hyperscan_cli_test.sh BINARY LAUNCHER' >&2
  exit 2
fi

binary=$1
launcher=$2
tmp=${TMPDIR:-/tmp}/regex-utils-hyperscan-test.$$
mkdir "$tmp" || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

assertions=0
status=0

fail() {
  echo "hyperscan_cli_test: $*" >&2
  exit 1
}

run_command() {
  "$@" >"$tmp/stdout" 2>"$tmp/stderr"
  status=$?
}

run_stdin() {
  input=$1
  shift
  printf '%s' "$input" | "$@" >"$tmp/stdout" 2>"$tmp/stderr"
  status=$?
}

assert_status() {
  status_expected=$1
  assertions=$((assertions + 1))
  [ "$status" -eq "$status_expected" ] ||
    fail "expected status $status_expected, got $status; stderr: $(lat "$tmp/stderr")"
}

assert_stdout_empty() {
  assertions=$((assertions + 1))
  [ ! -s "$tmp/stdout" ] || fail 'expected empty stdout'
}

assert_stderr_empty() {
  assertions=$((assertions + 1))
  [ ! -s "$tmp/stderr" ] ||
    fail "expected empty stderr: $(lat "$tmp/stderr")"
}

assert_stdout_lines() {
  stdout_expected=$1
  printf '%s\n' "$stdout_expected" >"$tmp/expected"
  assertions=$((assertions + 1))
  cmp -s "$tmp/expected" "$tmp/stdout" || {
    lat "$tmp/expected" "$tmp/stdout" >&2
    fail 'stdout mismatch'
  }
}

assert_stderr_contains() {
  stderr_expected=$1
  assertions=$((assertions + 1))
  grep -F "$stderr_expected" "$tmp/stderr" >/dev/null || {
    lat "$tmp/stderr" >&2
    fail "stderr does not contain: $stderr_expected"
  }
}

assert_success_lines() {
  success_expected=$1
  shift
  run_command "$@"
  assert_status 0
  assert_stdout_lines "$success_expected"
  assert_stderr_empty
}

assert_success_empty() {
  run_command "$@"
  assert_status 0
  assert_stdout_empty
  assert_stderr_empty
}

assert_error() {
  error_expected_status=$1
  error_expected_message=$2
  shift 2
  run_command "$@"
  assert_status "$error_expected_status"
  assert_stdout_empty
  assert_stderr_contains "hyperscan: $error_expected_message"
}

[ -x "$binary" ] || fail "binary is not executable: $binary"
[ -x "$launcher" ] || fail "launcher is not executable: $launcher"
binary=$(cd "$(dirname "$binary")" && pwd)/$(basename "$binary")
launcher=$(cd "$(dirname "$launcher")" && pwd)/$(basename "$launcher")

version='hyperscan v5.4.2.1 (Hyperscan 5.4.2 2026-08-26)'
assert_success_lines "$version" "$binary" --version

run_command "$binary" --help
assert_status 0
assert_stderr_empty
cat >"$tmp/expected-help" <<'EOF'
Usage:
  hyperscan scan [PATTERN_OPTIONS] [SCAN_OPTIONS]
  hyperscan info [PATTERN_OPTIONS]
  hyperscan --help
  hyperscan --version

Pattern source (choose one):
  -e, --expression PATTERN       Add one pattern; repeatable
  -f, --expression-file FILE     Read LF-delimited patterns from FILE

Compilation:
      --literal                  Compile byte literals instead of regexes
      --mode MODE                block, stream, or vectored [default: block]
  -i, --caseless                 Case-insensitive matching
  -s, --dotall                   Make dot match newlines
  -m, --multiline                Enable multiline anchors
      --single-match             Report at most one match per pattern
      --allow-empty              Permit regexes that match empty input
      --utf8                     Enable strict UTF-8 mode
      --ucp                      Enable Unicode properties; requires --utf8
      --prefilter                Permit false-positive prefilter matches
      --som-leftmost             Report leftmost start offsets
      --som-horizon HORIZON      small, medium, or large for stream SOM
      --min-offset N             Minimum match end offset
      --max-offset N             Maximum match end offset
      --min-length N             Minimum match length
      --edit-distance N          Experimental edit distance
      --hamming-distance N       Experimental Hamming distance

Scan input:
      --input FILE               Read binary subject; - is stdin [default]
      --text TEXT                Use exact argument bytes as the subject
      --chunk-size N             Stream/vector chunk bytes [default: 4096]
      --max-matches N            Event limit [default: 100000]
EOF
cmp -s "$tmp/expected-help" "$tmp/stdout" || fail 'help output mismatch'
assertions=$((assertions + 1))

(cd "$tmp" && "$launcher" --help >launcher-help 2>launcher-help.err) ||
  fail 'launcher help failed from an external cwd'
cmp -s "$tmp/stdout" "$tmp/launcher-help" || fail 'launcher changed help output'
[ ! -s "$tmp/launcher-help.err" ] || fail 'launcher wrote help diagnostics'
assertions=$((assertions + 2))
assert_success_lines "$version" "$launcher" --version

mkdir -p "$tmp/fake-path"
cat >"$tmp/fake-path/hyperscan" <<'EOF'
#!/bin/sh
echo fake-hyperscan
exit 77
EOF
chmod +x "$tmp/fake-path/hyperscan"
run_command env PATH="$tmp/fake-path:$PATH" "$launcher" --version
assert_status 0
assert_stdout_lines "$version"
assert_stderr_empty

mkdir -p "$tmp/missing-launcher/bin"
cp "$launcher" "$tmp/missing-launcher/bin/hyperscan"
run_command "$tmp/missing-launcher/bin/hyperscan" --version
assert_status 1
assert_stdout_empty
assert_stderr_contains 'hyperscan: build/hyperscan/bin/hyperscan is missing or not executable'
assert_stderr_contains 'hyperscan: run the Conan and CMake commands in README.md under "Hyperscan setup"'

basic='{"id":1,"start":null,"end":5,"start_status":"disabled"}
{"id":2,"start":null,"end":8,"start_status":"disabled"}
{"id":2,"start":null,"end":12,"start_status":"disabled"}'
assert_success_lines "$basic" "$binary" scan -e foo -e 'ba[rz]' --text 'xxfoobar baz'
assert_success_empty "$binary" scan -e nomatch --text subject

overlap='{"id":1,"start":null,"end":1,"start_status":"disabled"}
{"id":1,"start":null,"end":2,"start_status":"disabled"}
{"id":1,"start":null,"end":3,"start_status":"disabled"}'
assert_success_lines "$overlap" "$binary" scan -e a --text aaa

duplicates='{"id":1,"start":null,"end":3,"start_status":"disabled"}
{"id":2,"start":null,"end":3,"start_status":"disabled"}'
assert_success_lines "$duplicates" "$binary" scan -e foo -e foo --text foo
assert_success_lines \
  '{"id":1,"start":null,"end":3,"start_status":"disabled"}' \
  "$binary" scan -e FOO --caseless --text foo
assert_success_lines \
  '{"id":1,"start":null,"end":3,"start_status":"disabled"}' \
  "$binary" scan -e 'a.b' --dotall --text 'a
b'
assert_success_lines \
  '{"id":1,"start":null,"end":5,"start_status":"disabled"}' \
  "$binary" scan -e '^foo' --multiline --text 'x
foo'

allow_empty='{"id":1,"start":null,"end":0,"start_status":"disabled"}
{"id":1,"start":null,"end":1,"start_status":"disabled"}'
assert_success_lines "$allow_empty" "$binary" scan -e 'a*' --allow-empty --text a
assert_success_lines \
  '{"id":1,"start":null,"end":1,"start_status":"disabled"}' \
  "$binary" scan -e a --single-match --text aaa
assert_success_lines \
  '{"id":1,"start":null,"end":3,"start_status":"disabled"}
{"id":1,"start":null,"end":4,"start_status":"disabled"}
{"id":1,"start":null,"end":5,"start_status":"disabled"}
{"id":1,"start":null,"end":6,"start_status":"disabled"}' \
  "$binary" scan -e '(foo)\1' --prefilter --text foofoo

som='{"id":1,"start":2,"end":8,"start_status":"available"}'
assert_success_lines "$som" "$binary" scan -e 'foo.*bar' --som-leftmost --text xxfoobar
assert_success_lines "$som" "$binary" scan -e 'foo.*bar' --som-leftmost \
  --mode stream --chunk-size 3 --text xxfoobar
assert_success_lines "$som" "$binary" scan -e 'foo.*bar' --som-leftmost \
  --mode vectored --chunk-size 2 --text xxfoobar

end_match='{"id":1,"start":null,"end":5,"start_status":"disabled"}'
assert_success_lines "$end_match" "$binary" scan -e 'foo$' --mode stream \
  --chunk-size 1 --text xxfoo

perl -e 'print q{a}, q{x} x 70000, q{z}' >"$tmp/horizon-subject"
assert_success_lines \
  '{"id":1,"start":null,"end":70002,"start_status":"past_horizon"}' \
  "$binary" scan -e 'a.*z' --som-leftmost --som-horizon small --mode stream \
  --chunk-size 4096 --input "$tmp/horizon-subject"

for size in 1 2 3 8 64; do
  assert_success_lines \
    '{"id":1,"start":null,"end":8,"start_status":"disabled"}' \
    "$binary" scan -e foobar --mode stream --chunk-size "$size" --text xxfoobar
  assert_success_lines \
    '{"id":1,"start":null,"end":8,"start_status":"disabled"}' \
    "$binary" scan -e foobar --mode vectored --chunk-size "$size" --text xxfoobar
done

assert_success_lines \
  '{"id":1,"start":null,"end":5,"start_status":"disabled"}' \
  "$binary" scan --literal -e 'a.b' --text xxa.byy
printf 'a\0b\nxyz\n' >"$tmp/literals"
printf 'xxa\0byyxyz' >"$tmp/binary-subject"
literal_binary='{"id":1,"start":null,"end":5,"start_status":"disabled"}
{"id":2,"start":null,"end":10,"start_status":"disabled"}'
assert_success_lines "$literal_binary" "$binary" scan --literal \
  --expression-file "$tmp/literals" --mode vectored --chunk-size 2 \
  --input "$tmp/binary-subject"
assert_success_lines "$literal_binary" "$binary" scan --literal \
  --expression-file "$tmp/literals" --mode stream --chunk-size 2 \
  --input "$tmp/binary-subject"

perl -e 'print q{a} x 8192' >"$tmp/literal-8192"
run_command "$binary" info --literal --expression-file "$tmp/literal-8192"
assert_status 0
assert_stderr_empty
grep -E '^\{"source_tag":"v5\.4\.2\.1","library_version":"5\.4\.2 2026-08-26","compile_kind":"literal","mode":"block","patterns":1,"database_bytes":[1-9][0-9]*,"scratch_bytes":[1-9][0-9]*,"stream_bytes":null\}$' "$tmp/stdout" >/dev/null ||
  fail 'literal info JSON has the wrong schema'
assertions=$((assertions + 1))

assert_success_lines \
  '{"id":1,"start":null,"end":5,"start_status":"disabled"}' \
  "$binary" scan -e colour --edit-distance 1 --text color
assert_success_lines \
  '{"id":1,"start":null,"end":6,"start_status":"disabled"}' \
  "$binary" scan -e colour --hamming-distance 1 --text coloux
assert_success_lines \
  '{"id":1,"start":null,"end":6,"start_status":"disabled"}' \
  "$binary" scan -e foo --min-offset 4 --text foofoo
assert_success_lines \
  '{"id":1,"start":null,"end":3,"start_status":"disabled"}' \
  "$binary" scan -e foo --max-offset 4 --min-length 3 --text foofoo

printf 'foo\r\nbar\n' >"$tmp/expressions-crlf"
assert_success_lines \
  '{"id":2,"start":null,"end":3,"start_status":"disabled"}' \
  "$binary" scan --expression-file "$tmp/expressions-crlf" --text bar
printf ' leading\ntrailing \n\ttab\n' >"$tmp/expressions-space"
assert_success_lines \
  '{"id":2,"start":null,"end":9,"start_status":"disabled"}' \
  "$binary" scan --expression-file "$tmp/expressions-space" --text 'trailing '

assert_success_lines \
  '{"id":1,"start":null,"end":2,"start_status":"disabled"}' \
  "$binary" scan -e '\p{Greek}+' --utf8 --ucp --text 'Ω'
printf '\300\257' >"$tmp/invalid-utf8"
assert_success_empty "$binary" scan -e x --input "$tmp/invalid-utf8"
assert_error 2 'subject is not valid UTF-8' "$binary" scan -e x --utf8 \
  --input "$tmp/invalid-utf8"
for bytes in '\355\240\200' '\364\220\200\200' '\342\202'; do
  printf '%b' "$bytes" >"$tmp/invalid-utf8"
  assert_error 2 'subject is not valid UTF-8' "$binary" scan -e x --utf8 \
    --input "$tmp/invalid-utf8"
done

printf foo >"$tmp/subject"
assert_success_lines \
  '{"id":1,"start":null,"end":3,"start_status":"disabled"}' \
  "$binary" scan -e foo --input "$tmp/subject"
run_stdin foo "$binary" scan -e foo
assert_status 0
assert_stdout_lines '{"id":1,"start":null,"end":3,"start_status":"disabled"}'
assert_stderr_empty
run_stdin foo "$binary" scan -e foo --input -
assert_status 0
assert_stdout_lines '{"id":1,"start":null,"end":3,"start_status":"disabled"}'
assert_stderr_empty
assert_success_empty "$binary" scan -e foo --text ''
printf '' >"$tmp/empty-subject"
assert_success_empty "$binary" scan -e foo --input "$tmp/empty-subject"

run_command "$binary" info -e foo -e 'ba[rz]' --mode stream
assert_status 0
assert_stderr_empty
grep -E '^\{"source_tag":"v5\.4\.2\.1","library_version":"5\.4\.2 2026-08-26","compile_kind":"regex","mode":"stream","patterns":2,"database_bytes":[1-9][0-9]*,"scratch_bytes":[1-9][0-9]*,"stream_bytes":[1-9][0-9]*\}$' "$tmp/stdout" >/dev/null ||
  fail 'stream info JSON has the wrong schema'
assertions=$((assertions + 1))

two_matches='{"id":1,"start":null,"end":1,"start_status":"disabled"}
{"id":1,"start":null,"end":2,"start_status":"disabled"}'
assert_success_lines "$two_matches" "$binary" scan -e a --max-matches 2 --text aa
assert_error 1 'match limit exceeded' "$binary" scan -e a --max-matches 2 --text aaa
assert_error 1 'match limit exceeded' "$binary" scan -e 'a$' --mode stream \
  --chunk-size 1 --max-matches 1 -e a --text aa

assert_error 1 'Could not allocate memory for bytecode.' env \
  REGEX_UTILS_HYPERSCAN_TEST_FAIL_ALLOCATOR=database \
  "$binary" info -e foo
assert_error 1 'cannot allocate scratch space' env \
  REGEX_UTILS_HYPERSCAN_TEST_FAIL_ALLOCATOR=scratch \
  "$binary" info -e foo
assert_error 1 'stream open failed' env \
  REGEX_UTILS_HYPERSCAN_TEST_FAIL_ALLOCATOR=stream \
  "$binary" scan -e foo --mode stream --text foo

assert_error 2 'a scan or info command is required' "$binary"
assert_error 2 'a scan or info command is required' "$binary" unknown
assert_error 2 'unknown option or argument: --unknown' "$binary" scan -e foo --unknown
assert_error 2 'unknown option or argument: -is' "$binary" scan -e foo -is
assert_error 2 'unknown option or argument: --mode=stream' "$binary" scan -e foo --mode=stream
assert_error 2 'missing value for --expression' "$binary" scan --expression
assert_error 2 'exactly one pattern source is required' "$binary" scan --text foo
assert_error 2 '--expression and --expression-file cannot be mixed' "$binary" scan \
  -e foo -f "$tmp/expressions-crlf" --text foo
assert_error 2 '--expression-file may not be -' "$binary" scan -f - --text foo
assert_error 2 '--input and --text cannot be combined' "$binary" scan -e foo \
  --input - --text foo
assert_error 2 'scan input options are not valid for info' "$binary" info -e foo --text foo
assert_error 2 '--chunk-size requires stream or vectored mode' "$binary" scan -e foo \
  --chunk-size 2 --text foo
assert_error 2 'option repeated: --mode' "$binary" scan -e foo --mode stream \
  --mode vectored --text foo
assert_error 2 'option repeated: --caseless' "$binary" scan -e foo -i --caseless --text foo

assert_error 2 '--ucp requires --utf8' "$binary" scan -e foo --ucp --text foo
assert_error 2 '--som-leftmost cannot be combined with --single-match' "$binary" scan \
  -e foo --som-leftmost --single-match --text foo
assert_error 2 '--som-leftmost cannot be combined with --prefilter' "$binary" scan \
  -e foo --som-leftmost --prefilter --text foo
assert_error 2 '--som-horizon requires --mode stream and --som-leftmost' "$binary" scan \
  -e foo --som-horizon small --text foo
assert_error 2 '--edit-distance and --hamming-distance are mutually exclusive' "$binary" scan \
  -e foo --edit-distance 1 --hamming-distance 1 --text foo
assert_error 2 '--min-offset may not exceed --max-offset' "$binary" scan -e foo \
  --min-offset 3 --max-offset 2 --text foo
assert_error 2 '--min-length may not exceed --max-offset' "$binary" scan -e foo \
  --min-length 3 --max-offset 2 --text foo
assert_error 2 'an option is not supported in literal mode' "$binary" scan --literal \
  -e foo --utf8 --text foo
assert_error 2 'an option is not supported in literal mode' "$binary" scan --literal \
  -e foo --edit-distance 1 --text foo

for value in -1 +1 1x 0x; do
  assert_error 2 'invalid decimal value' "$binary" scan -e foo --min-offset "$value" --text foo
done
assert_error 2 'decimal value out of range for --min-offset' "$binary" scan -e foo \
  --min-offset 18446744073709551616 --text foo
assert_error 2 '--chunk-size must be positive' "$binary" scan -e foo --mode stream \
  --chunk-size 0 --text foo
assert_error 2 '--max-matches must be positive' "$binary" scan -e foo --max-matches 0 --text foo
assert_error 2 'decimal value out of range for --max-matches' "$binary" scan -e foo \
  --max-matches 1000001 --text foo
assert_error 2 'decimal value out of range for --edit-distance' "$binary" scan -e foo \
  --edit-distance 4294967296 --text foo

assert_error 2 'pattern 1:' "$binary" scan -e '(' --text foo
assert_error 2 'pattern 1:' "$binary" scan -e '(foo)\1' --text foofoo
assert_error 2 'pattern 1:' "$binary" scan -e '' --text foo
assert_error 2 'literal pattern may not be empty' "$binary" scan --literal -e '' --text foo
printf 'a\0b\n' >"$tmp/regex-nul"
assert_error 2 'regex pattern contains an embedded NUL byte' "$binary" scan \
  -f "$tmp/regex-nul" --text foo
printf '\300\257\n' >"$tmp/invalid-pattern"
assert_error 2 'pattern is not valid UTF-8' "$binary" scan --utf8 \
  -f "$tmp/invalid-pattern" --text foo

printf '' >"$tmp/empty-expressions"
assert_error 2 'expression file is empty' "$binary" scan -f "$tmp/empty-expressions" --text foo
perl -e 'print q{a} x 8193' >"$tmp/pattern-8193"
assert_error 2 'pattern exceeds 8192 bytes' "$binary" info -f "$tmp/pattern-8193"
perl -e 'print qq{x\n} x 10001' >"$tmp/patterns-10001"
assert_error 2 'pattern source contains more than 10000 expressions' "$binary" info \
  -f "$tmp/patterns-10001"
perl -e 'for (1..1025) { print((q{a} x 8192), qq{\n}) }' >"$tmp/patterns-over-aggregate"
assert_error 2 'cumulative expression bytes exceed 8 MiB' "$binary" info \
  -f "$tmp/patterns-over-aggregate"
assert_error 1 'cannot open expression file:' "$binary" info -f "$tmp/missing-patterns"
assert_error 1 'cannot open input file:' "$binary" scan -e foo --input "$tmp/missing-subject"
assert_error 1 'failed to read input file' "$binary" scan -e foo --input "$tmp"

if [ "${REGEX_UTILS_HYPERSCAN_SKIP_RESOURCE_TESTS:-0}" != 1 ]; then
  dd if=/dev/zero of="$tmp/subject-at-limit" bs=1 count=0 seek=268435456 2>/dev/null ||
    fail 'could not create exact-limit sparse input fixture'
  assert_success_empty "$binary" scan -e x --max-matches 1 \
    --input "$tmp/subject-at-limit"
  dd if=/dev/zero of="$tmp/subject-over-limit" bs=1 count=0 seek=268435457 2>/dev/null ||
    fail 'could not create oversized sparse input fixture'
  assert_error 1 'input file exceeds its size limit' "$binary" scan -e foo \
    --input "$tmp/subject-over-limit"
fi

fifo=$tmp/closed-pipe
mkfifo "$fifo" || fail 'could not create EPIPE fixture'
"$binary" scan -e a --max-matches 100000 --text \
  "$(perl -e 'print q{a} x 100000')" >"$fifo" 2>"$tmp/epipe-stderr" &
epipe_pid=$!
dd if="$fifo" of=/dev/null bs=1 count=1 2>/dev/null
wait "$epipe_pid"
status=$?
assert_status 0
[ ! -s "$tmp/epipe-stderr" ] || fail 'EPIPE produced a diagnostic'
assertions=$((assertions + 1))

echo "hyperscan_cli_test: $assertions assertions"

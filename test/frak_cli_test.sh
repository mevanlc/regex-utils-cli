#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
ROOT=$(dirname "$SCRIPT_DIR")
CLOJURE=$ROOT/.deps/clojure/bin/clojure
CONFIG=$ROOT/.deps/clj-config
CACHE=$ROOT/.deps/clj-cache
ASSERTIONS=0
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/frak-cli-test.XXXXXX")
OUT=$TEMP_DIR/stdout
ERR=$TEMP_DIR/stderr
EXPECTED=$TEMP_DIR/expected
STATUS=0

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf 'frak_cli_test: %s\n' "$1" >&2
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
    printf '%s\n' "$1" >"$EXPECTED"
    cmp -s "$EXPECTED" "$OUT" || fail "$2: unexpected stdout"
    pass
}

assert_stderr() {
    printf '%s\n' "$1" >"$EXPECTED"
    cmp -s "$EXPECTED" "$ERR" || fail "$2: unexpected stderr"
    pass
}

assert_empty() {
    [ ! -s "$1" ] || fail "$2: expected an empty file"
    pass
}

assert_contains() {
    grep -F "$1" "$2" >/dev/null 2>&1 || fail "$3: missing '$1'"
    pass
}

run_frak() {
    : >"$OUT"
    : >"$ERR"
    set +e
    CLJ_CONFIG=$CONFIG CLJ_CACHE=$CACHE \
        "$CLOJURE" -Srepro -M:frak "$@" >"$OUT" 2>"$ERR"
    STATUS=$?
    set -e
}

generate() {
    CLJ_CONFIG=$CONFIG CLJ_CACHE=$CACHE \
        "$CLOJURE" -Srepro -M:frak "$@"
}

assert_match() {
    ACTUAL=$(TEST_PATTERN=$1 TEST_TEXT=$2 CLJ_CONFIG=$CONFIG CLJ_CACHE=$CACHE \
        "$CLOJURE" -Srepro -M -e \
        '(print (boolean (re-matches (re-pattern (System/getenv "TEST_PATTERN")) (System/getenv "TEST_TEXT"))))' \
        2>"$ERR") || fail "$4: pattern compilation or matching failed"
    [ "$ACTUAL" = "$3" ] || fail "$4: expected match result $3, got $ACTUAL"
    pass
}

[ -x "$CLOJURE" ] || fail "missing project-local Clojure CLI; run tools/bootstrap-clojure"

"$ROOT/tools/verify-jvm-deps" >"$OUT" 2>"$ERR" || fail "runtime artifact verification failed"
assert_empty "$ERR" "runtime artifact verification"
JAR_COUNT=$(find "$ROOT/.deps/m2" -type f -name '*.jar' | wc -l | tr -d ' ')
[ "$JAR_COUNT" -eq 7 ] || fail "expected exactly seven runtime JARs, got $JAR_COUNT"
pass

CLJ_CONFIG=$CONFIG CLJ_CACHE=$CACHE "$CLOJURE" -Srepro -Stree >"$OUT" 2>"$ERR"
assert_empty "$ERR" "dependency tree"
for coordinate in \
    'org.clojure/clojure 1.12.5' \
    'org.clojure/spec.alpha 0.5.238' \
    'org.clojure/core.specs.alpha 0.4.74' \
    'org.clojure/tools.cli 0.3.1' \
    'com.github.mifmif/generex 1.0.2' \
    'dk.brics.automaton/automaton 1.11-8' \
    'frak/frak 0.1.9'; do
    assert_contains "$coordinate" "$OUT" "dependency tree"
done
if grep -F 'clojurescript' "$OUT" >/dev/null 2>&1; then
    fail "dependency tree unexpectedly contains ClojureScript"
fi
pass

CLJ_CONFIG=$CONFIG CLJ_CACHE=$CACHE "$CLOJURE" -Srepro -Sdescribe >"$OUT" 2>"$ERR"
assert_contains ':version "1.12.5.1664"' "$OUT" "Clojure CLI version"
assert_contains ':config-user ""' "$OUT" "reproducible configuration"
assert_contains ':repro true' "$OUT" "reproducible configuration"
assert_empty "$ERR" "Clojure CLI description"

HELP='Usage: frak <flags*> <strings+>

Flags:
  -e, --exact                      Generated pattern requires an exact match
  -c, --capture                    Generated pattern captures
  -E, --escape-chars :KEY|'"'"'CHARS'"'"'  Set of characters to escape in generated pattern
  -h, --help                       Display this help message'

run_frak
assert_status 0 "no-argument help"
assert_stdout "$HELP" "no-argument help"
assert_empty "$ERR" "no-argument help"
for help_option in -h --help; do
    run_frak "$help_option"
    assert_status 0 "$help_option"
    assert_stdout "$HELP" "$help_option"
    assert_empty "$ERR" "$help_option"
done
run_frak foo --help bar
assert_status 0 "help with words"
assert_stdout "$HELP" "help with words"
assert_empty "$ERR" "help with words"

run_frak -e foo foot
assert_status 0 "short exact"
assert_stdout '^foot?$' "short exact"
assert_empty "$ERR" "short exact"
run_frak --exact foo foot
assert_status 0 "long exact"
assert_stdout '^foot?$' "long exact"
run_frak -e -e foo foot
assert_status 0 "duplicate exact"
assert_stdout '^foot?$' "duplicate exact"

PATTERN=$(generate foo bar baz quux)
for positive in foo bar baz quux; do
    assert_match "$PATTERN" "$positive" true "branching positive $positive"
done
for negative in ba quu unrelated; do
    assert_match "$PATTERN" "$negative" false "branching negative $negative"
done
PERMUTED=$(generate quux baz foo bar foo)
for positive in foo bar baz quux; do
    assert_match "$PERMUTED" "$positive" true "permuted positive $positive"
done
assert_match "$PERMUTED" ba false "permuted negative"

CAPTURED=$(generate --capture foo bar baz)
CAPTURE_SUMMARY=$(TEST_PATTERN=$CAPTURED TEST_TEXT=bar CLJ_CONFIG=$CONFIG CLJ_CACHE=$CACHE \
    "$CLOJURE" -Srepro -M -e \
    '(let [m (.matcher (re-pattern (System/getenv "TEST_PATTERN")) (System/getenv "TEST_TEXT"))] (print (str (.matches m) ":" (.groupCount m) ":" (some? (.group m 1)))))')
[ "$CAPTURE_SUMMARY" = 'true:2:true' ] || fail "capture mode did not expose generated groups"
pass
run_frak -c -c foo
assert_status 0 "duplicate capture"
assert_stdout 'foo' "capture without a generated group"

run_frak 'a.b'
assert_status 0 "default escaping"
assert_stdout 'a\.b' "default escaping"
PATTERN=$(generate 'a.b')
assert_match "$PATTERN" 'a.b' true "default escaping literal"
assert_match "$PATTERN" 'axb' false "default escaping negative"
run_frak -E :default 'a*b'
assert_status 0 "default keyword escaping"
assert_stdout 'a\*b' "default keyword escaping"
run_frak --escape-chars :vim 'a-b'
assert_status 0 "Vim keyword escaping"
assert_stdout 'a\-b' "Vim keyword escaping"
run_frak -E '.' 'a.b'
assert_stdout 'a\.b' "literal escape set"
run_frak -E '' 'a.b'
assert_stdout 'a.b' "empty escape set"
PATTERN=$(generate -E '' 'a.b')
assert_match "$PATTERN" axb true "empty escape set broadens source"
run_frak -E :unknown 'a.b'
assert_status 0 "unknown escape keyword"
assert_stdout 'a.b' "unknown escape keyword"

run_frak -E '' '['
assert_status 0 "under-escaped invalid source generation"
assert_stdout '[' "under-escaped invalid source generation"
set +e
TEST_PATTERN='[' CLJ_CONFIG=$CONFIG CLJ_CACHE=$CACHE \
    "$CLOJURE" -Srepro -M -e '(re-pattern (System/getenv "TEST_PATTERN"))' \
    >"$OUT" 2>"$ERR"
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "independent compiler unexpectedly accepted '['"
pass

run_frak ''
assert_status 0 "lone empty string"
assert_stdout '' "lone empty string"
run_frak -e ''
assert_stdout '^$' "exact lone empty string"
run_frak foo '' foot
assert_stdout 'foot?' "empty string ignored beside words"
run_frak foo foo
assert_stdout 'foo' "duplicate input collapse"
run_frak 'hello world'
assert_stdout 'hello world' "space preservation"
run_frak 'line
break'
assert_stdout 'line
break' "embedded LF preservation"
run_frak café 茶
assert_status 0 "Unicode input"
PATTERN=$(generate café 茶)
assert_match "$PATTERN" café true "Unicode café"
assert_match "$PATTERN" 茶 true "Unicode CJK"
run_frak -- -e foo
assert_status 0 "option-looking strings"
PATTERN=$(generate -- -e foo)
assert_match "$PATTERN" -e true "option-looking -e"
assert_match "$PATTERN" foo true "option-looking foo"

: >"$ERR"
printf 'ignored stdin\n' | CLJ_CONFIG=$CONFIG CLJ_CACHE=$CACHE \
    "$CLOJURE" -Srepro -M:frak foo >"$OUT" 2>"$ERR"
assert_stdout 'foo' "stdin is ignored"
assert_empty "$ERR" "stdin is ignored"

run_frak --bogus
assert_status 1 "unknown option"
assert_empty "$OUT" "unknown option"
assert_stderr 'Unknown option: "--bogus"' "unknown option"
run_frak -E
assert_status 1 "missing escape value"
assert_empty "$OUT" "missing escape value"
assert_stderr 'Missing required argument for "-E :KEY|'"'"'CHARS'"'"'"' "missing escape value"

set +e
CLJ_CONFIG=$CONFIG CLJ_CACHE=$CACHE "$CLOJURE" -Srepro -M:frak foo | \
    dd of=/dev/null bs=1 count=0 2>/dev/null
STATUS=$?
set -e
pass

FAKE_BIN=$TEMP_DIR/fake-bin
mkdir -p "$FAKE_BIN"
printf '#!/bin/sh\nexit 97\n' >"$FAKE_BIN/curl"
chmod 755 "$FAKE_BIN/curl"
PATH=$FAKE_BIN:$PATH "$ROOT/tools/bootstrap-clojure" >"$OUT" 2>"$ERR"
assert_empty "$OUT" "cached bootstrap"
assert_empty "$ERR" "cached bootstrap"

MISMATCH=$TEMP_DIR/mismatch
mkdir -p "$MISMATCH/tools" "$MISMATCH/.deps/clojure"
cp "$ROOT/tools/bootstrap-clojure" "$MISMATCH/tools/bootstrap-clojure"
set +e
PATH=$FAKE_BIN:$PATH "$MISMATCH/tools/bootstrap-clojure" >"$OUT" 2>"$ERR"
STATUS=$?
set -e
assert_status 1 "mismatched installation"
assert_contains "remove that exact directory and rerun" "$ERR" "mismatched installation"

OLD_JAVA=$TEMP_DIR/old-java-bin
mkdir -p "$OLD_JAVA"
cat >"$OLD_JAVA/java" <<'EOF'
#!/bin/sh
printf 'java version "1.8.0_999"\n' >&2
EOF
cat >"$OLD_JAVA/curl" <<EOF
#!/bin/sh
touch "$TEMP_DIR/curl-was-called"
exit 97
EOF
chmod 755 "$OLD_JAVA/java" "$OLD_JAVA/curl"
OLD_FIXTURE=$TEMP_DIR/old-java-fixture
mkdir -p "$OLD_FIXTURE/tools"
cp "$ROOT/tools/bootstrap-clojure" "$OLD_FIXTURE/tools/bootstrap-clojure"
set +e
PATH=$OLD_JAVA:$PATH "$OLD_FIXTURE/tools/bootstrap-clojure" >"$OUT" 2>"$ERR"
STATUS=$?
set -e
assert_status 1 "old Java"
assert_contains "Java 17 or newer is required" "$ERR" "old Java"
[ ! -e "$TEMP_DIR/curl-was-called" ] || fail "old-Java check downloaded before failing"
pass

NO_JAVA_BIN=$TEMP_DIR/no-java-bin
mkdir -p "$NO_JAVA_BIN"
for command in dirname curl tar sed mktemp mkdir rm mv chmod shasum; do
    ln -s "$(command -v "$command")" "$NO_JAVA_BIN/$command"
done
NO_JAVA_FIXTURE=$TEMP_DIR/no-java-fixture
mkdir -p "$NO_JAVA_FIXTURE/tools"
cp "$ROOT/tools/bootstrap-clojure" "$NO_JAVA_FIXTURE/tools/bootstrap-clojure"
set +e
PATH=$NO_JAVA_BIN "$NO_JAVA_FIXTURE/tools/bootstrap-clojure" >"$OUT" 2>"$ERR"
STATUS=$?
set -e
assert_status 1 "missing Java"
assert_contains "required command not found on PATH: java" "$ERR" "missing Java"

UNWRITABLE_FIXTURE=$TEMP_DIR/unwritable-fixture
mkdir -p "$UNWRITABLE_FIXTURE/tools" "$UNWRITABLE_FIXTURE/.deps"
cp "$ROOT/tools/bootstrap-clojure" "$UNWRITABLE_FIXTURE/tools/bootstrap-clojure"
chmod 555 "$UNWRITABLE_FIXTURE/.deps"
set +e
"$UNWRITABLE_FIXTURE/tools/bootstrap-clojure" >"$OUT" 2>"$ERR"
STATUS=$?
set -e
chmod 755 "$UNWRITABLE_FIXTURE/.deps"
assert_status 1 "unwritable target"
assert_contains "cannot create bootstrap directory beneath" "$ERR" "unwritable target"

CORRUPT_BIN=$TEMP_DIR/corrupt-bin
mkdir -p "$CORRUPT_BIN"
cat >"$CORRUPT_BIN/curl" <<'EOF'
#!/bin/sh
output=
while [ "$#" -gt 0 ]; do
    if [ "$1" = --output ]; then
        shift
        output=$1
    fi
    shift
done
printf corrupt >"$output"
EOF
chmod 755 "$CORRUPT_BIN/curl"
CORRUPT_FIXTURE=$TEMP_DIR/corrupt-fixture
mkdir -p "$CORRUPT_FIXTURE/tools"
cp "$ROOT/tools/bootstrap-clojure" "$CORRUPT_FIXTURE/tools/bootstrap-clojure"
set +e
PATH=$CORRUPT_BIN:$PATH "$CORRUPT_FIXTURE/tools/bootstrap-clojure" >"$OUT" 2>"$ERR"
STATUS=$?
set -e
assert_status 1 "corrupt archive"
assert_contains "archive SHA-256 mismatch" "$ERR" "corrupt archive"
[ ! -e "$CORRUPT_FIXTURE/.deps/clojure" ] || fail "corrupt archive created an installation"
pass

NO_HASH_BIN=$TEMP_DIR/no-hash-bin
mkdir -p "$NO_HASH_BIN"
for command in dirname java curl tar sed mktemp mkdir rm mv chmod; do
    ln -s "$(command -v "$command")" "$NO_HASH_BIN/$command"
done
NO_HASH_FIXTURE=$TEMP_DIR/no-hash-fixture
mkdir -p "$NO_HASH_FIXTURE/tools"
cp "$ROOT/tools/bootstrap-clojure" "$NO_HASH_FIXTURE/tools/bootstrap-clojure"
set +e
PATH=$NO_HASH_BIN "$NO_HASH_FIXTURE/tools/bootstrap-clojure" >"$OUT" 2>"$ERR"
STATUS=$?
set -e
assert_status 1 "missing hash utility"
assert_contains "SHA-256 utility not found" "$ERR" "missing hash utility"

VERIFY_FIXTURE=$TEMP_DIR/verify-fixture
mkdir -p "$VERIFY_FIXTURE/tools" "$VERIFY_FIXTURE/.deps"
cp -R "$ROOT/.deps/m2" "$VERIFY_FIXTURE/.deps/m2"
cp "$ROOT/jvm-deps.sha256" "$VERIFY_FIXTURE/jvm-deps.sha256"
cp "$ROOT/tools/verify-jvm-deps" "$VERIFY_FIXTURE/tools/verify-jvm-deps"
FIXTURE_FRAK=$VERIFY_FIXTURE/.deps/m2/frak/frak/0.1.9/frak-0.1.9.jar
rm "$FIXTURE_FRAK"
set +e
"$VERIFY_FIXTURE/tools/verify-jvm-deps" >"$OUT" 2>"$ERR"
STATUS=$?
set -e
assert_status 1 "missing runtime JAR"
cp "$ROOT/.deps/m2/frak/frak/0.1.9/frak-0.1.9.jar" "$FIXTURE_FRAK"
printf corrupt >>"$FIXTURE_FRAK"
set +e
"$VERIFY_FIXTURE/tools/verify-jvm-deps" >"$OUT" 2>"$ERR"
STATUS=$?
set -e
assert_status 1 "corrupt runtime JAR"
cp "$ROOT/.deps/m2/frak/frak/0.1.9/frak-0.1.9.jar" "$FIXTURE_FRAK"
cp "$FIXTURE_FRAK" "$VERIFY_FIXTURE/.deps/m2/frak/frak/0.1.9/unlisted.jar"
set +e
"$VERIFY_FIXTURE/tools/verify-jvm-deps" >"$OUT" 2>"$ERR"
STATUS=$?
set -e
assert_status 1 "unlisted runtime JAR"
assert_contains "unlisted runtime JAR" "$ERR" "unlisted runtime JAR"

OFFLINE_FIXTURE=$TEMP_DIR/offline-fixture
mkdir -p "$OFFLINE_FIXTURE/.deps"
cp -R "$ROOT/.deps/m2" "$OFFLINE_FIXTURE/.deps/m2"
sed \
    -e 's#https://repo.maven.apache.org/maven2/#https://127.0.0.1:9/#' \
    -e 's#https://repo.clojars.org/#https://127.0.0.1:9/#' \
    "$ROOT/deps.edn" >"$OFFLINE_FIXTURE/deps.edn"
(
    cd "$OFFLINE_FIXTURE"
    CLJ_CONFIG=$OFFLINE_FIXTURE/.deps/clj-config CLJ_CACHE=$OFFLINE_FIXTURE/.deps/clj-cache \
        "$CLOJURE" -Srepro -M:frak -e foo foot >"$OUT" 2>"$ERR"
)
assert_stdout '^foot?$' "prepared offline invocation"
assert_empty "$ERR" "prepared offline invocation"

printf 'frak CLI tests passed: %s assertions\n' "$ASSERTIONS"

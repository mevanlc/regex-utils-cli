# Plan: RegexTrie C CLI Exercise

## Summary

Add `bin/regextrie-c`, a project-local launcher for a custom C CLI that exercises
[`ikeofilic1/RegexTrie`](https://github.com/ikeofilic1/RegexTrie). Fetch the immutable
upstream source archive with CMake, compile `trie.c` as a private static library, and
map the CLI directly to `new_trie()`, `add_word()` or `add_regex()`, `find_word()`, and
`free_trie()`.

CMake alone is sufficient. Upstream consists of one header, one implementation file,
and an interactive example, with no third-party dependency or package metadata. Do
not add Conan, a custom Conan recipe, or another native package manager. The wrapper
must accurately expose that this is a byte-class trie with precomputed `?` paths—not a
general regex parser, compiler, matcher, or regex-inference library.

## Verified Upstream Facts

- The authoritative source is
  [`ikeofilic1/RegexTrie`](https://github.com/ikeofilic1/RegexTrie), a small C
  repository whose default branch is `master`.
- Upstream has no tags, GitHub releases, package-registry entry, vendored dependency,
  CMake file, Makefile, install metadata, or declared version. Pin immutable commit
  [`c35e88931f646a24ed9a1f09d0b13fb204a773b1`](https://github.com/ikeofilic1/RegexTrie/commit/c35e88931f646a24ed9a1f09d0b13fb204a773b1),
  the current head from January 5, 2024, instead of resolving `master` at build time.
- Use the GitHub commit archive
  `https://github.com/ikeofilic1/RegexTrie/archive/c35e88931f646a24ed9a1f09d0b13fb204a773b1.tar.gz`
  with SHA-256
  `ed0e39fb3359927ff74f0a552a85e96371898ada82ca483fb68a115a73e7133c`.
  The archive contains only the README, three C files, and two word lists.
- No license file, SPDX header, licensing statement, or GitHub-detected license is
  present at the pinned commit or in earlier repository history. Treat the source as
  unlicensed/all-rights-reserved: use it only for this local exercise, do not vendor
  it, and do not redistribute source or linked binaries without permission from the
  copyright holder.
- `trie.h` exposes `new_trie`, `add_word`, `add_regex`, `find_word`, `free_trie`, and
  `print_trie_dfs`. It also exposes the complete `Trie` layout rather than an opaque
  type. The CLI must use only the functions needed for insert/query/free and must not
  depend on struct internals.
- `add_word(root, word)` inserts one NUL-terminated byte string. `find_word(root,
  query)` follows the same indexed path and returns integer 1 only if its final node
  carries the terminal marker; it returns 0 for a missing path or null root.
- `add_regex(root, word)` first inserts the original word, then recursively inserts
  every same-length combination in which any subset of byte positions is replaced by
  `?`. For a collision-free word of byte length `n`, this represents `2^n` pattern
  strings and creates a full two-way trie with up to `2^(n+1)-1` nodes.
- The name `add_regex` is misleading in conventional regex terms. It does not parse
  regex syntax, interpret quantifiers/classes/anchors/alternation, or compile a
  pattern. A query `?oo` succeeds after `add_regex("foo")` because that literal path
  was precomputed during insertion.
- The README explicitly describes `?` as an ASCII wildcard and acknowledges
  `O(2^length)` setup per word versus `O(length)` lookup. It does not define Unicode,
  locale, normalization, encoding, or malformed-byte behavior.
- Every byte is reduced through `IDX(x) = ((x + 128) % 32)`. Only 32 equivalence
  classes exist, so the library does not preserve byte identity. ASCII upper/lowercase
  letters collide, but many unrelated bytes collide too: direct probes confirmed
  `add_word("foo")` makes `foo`, `FOO`, and `&//` all report found.
- `?` and `_` both index to class 31. After `add_regex("foo")`, both `?oo` and `_oo`
  report found. The result describes the library's indexed equivalence classes, not
  normal wildcard or exact-string semantics.
- `@` indexes to class 0, which is also used as the terminal slot. Insertion and lookup
  skip descent for that class. A probe confirmed `add_word("a@b")` makes `a@b`, `ab`,
  and `a@@b` report found, while `a@b` need not match when only `ab` was inserted.
  Preserve and characterize this upstream behavior rather than special-casing `@`.
- Matching is byte-length-sensitive apart from the special class-0 behavior. A UTF-8
  scalar is multiple positions, and `add_regex` creates wildcard combinations per
  encoded byte rather than per Unicode scalar or grapheme.
- Empty strings are valid C strings. `add_word("")` and `add_regex("")` mark the root
  terminal, after which `find_word("")` returns 1. Duplicate insertions are accepted
  and do not produce distinct query results.
- The allocator uses `assert` for some allocation failures, does not fully check the
  initial child-array allocation, and performs recursive insertion and destruction.
  With `NDEBUG`, allocation assertions disappear. Build the exercise in Debug mode,
  preflight all resource limits, and do not claim graceful out-of-memory recovery.
- `find_word`, `add_word`, and `add_regex` call `strlen` and therefore cannot represent
  embedded NUL. The CLI must reject NUL before calling upstream rather than silently
  truncating a record.
- `print_trie_dfs` prints directly to stdout and reconstructs each edge as `'?' +
  index`; it cannot recover original bytes from the 32-way equivalence classes. It is
  a lossy debug traversal, not a dictionary/pattern serialization format, and is not
  included in the focused CLI.
- Upstream `src/trietests.c` is an interactive example rather than an automated suite.
  It inserts file lines with `add_word` only, prints prompts, stops on a blank query,
  continues after unreadable files, and exits 0 even if every requested file failed.
  It has no `--help`, version output, machine-readable mode, or `add_regex` exercise.
- The pinned header declares `Trie *new_trie()` rather than `new_trie(void)`, producing
  a strict-prototype warning under current Clang. Several size conversions also warn
  under aggressive conversion flags. Compile upstream with warnings visible but not
  promoted to errors; compile all project-owned C with warnings denied.
- The library performs dictionary insertion and membership lookup over its byte-class
  paths. It does not infer regex source, optimize an existing regex, generate matching
  text, search within a larger subject, return match spans/captures, or enumerate the
  original inserted values.

Local validation compiled the pinned source as C11 with Apple Clang 21, built and ran
the interactive example, and used an independent ASan/UBSan probe for both insertion
modes, empty input, aliases, `?`, `_`, `@`, length mismatch, cleanup, and exponential
growth. Supported probe paths produced no address/undefined-behavior report (LeakSanitizer
is unavailable on this macOS runtime). A ten-byte collision-free `add_regex` input
created 2,047 nodes, matching the full-tree bound. A temporary CMake 4.4 project also
fetched the exact archive by URL/hash and built it successfully without Conan.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Supported: insert byte strings into the 32-class trie and query whole stored paths. |
| Wildcard-pattern precomputation | Supported through `add_regex`; every subset of byte positions is replaced with literal `?` paths before lookup. |
| Plain insertion | Supported through `add_word`, while preserving all upstream byte-class collisions. |
| Regex parsing or matching | Unsupported; the library does not accept conventional regex syntax or search subject text. |
| Regex inference from samples | Unsupported; `add_regex` stores wildcard variants but emits no regex source. |
| Existing-regex optimization | Unsupported; there is no regex input or output. |
| Matching-text generation | Unsupported; do not confuse stored path expansion with sample generation. |
| Original-value enumeration | Unsupported; `print_trie_dfs` is lossy and intentionally omitted. |

## Files and Dependency Setup

### Pinned CMake source acquisition

Create the root `CMakeLists.txt` as the shared native build entry point. Future TRE and
Hyperscan plans must extend this file rather than create unrelated nested builds. Start
with this source declaration:

```cmake
cmake_minimum_required(VERSION 3.24)
project(regex_utils_cli LANGUAGES C)

include(CTest)
include(FetchContent)

option(REGEX_UTILS_ENABLE_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

FetchContent_Declare(
  regextrie_upstream
  URL
    "https://github.com/ikeofilic1/RegexTrie/archive/c35e88931f646a24ed9a1f09d0b13fb204a773b1.tar.gz"
  URL_HASH
    "SHA256=ed0e39fb3359927ff74f0a552a85e96371898ada82ca483fb68a115a73e7133c"
  DOWNLOAD_EXTRACT_TIMESTAMP FALSE
)
FetchContent_MakeAvailable(regextrie_upstream)

add_library(regextrie_c_upstream STATIC
  "${regextrie_upstream_SOURCE_DIR}/src/trie.c"
)
target_include_directories(regextrie_c_upstream SYSTEM PUBLIC
  "${regextrie_upstream_SOURCE_DIR}/src"
)
target_compile_features(regextrie_c_upstream PUBLIC c_std_11)
set_target_properties(regextrie_c_upstream PROPERTIES C_EXTENSIONS OFF)
```

`FetchContent_MakeAvailable` is sufficient even though the populated source has no
`CMakeLists.txt`; the root project defines the library target itself. The pinned
archive is downloaded and extracted only under `build/native/_deps/`, already covered
by the root `/build/` ignore rule. Do not copy upstream headers, source, word lists, or
archive into the repository.

Add the custom executable and tests:

```cmake
add_executable(regextrie-c native/regextrie_c_cli.c)
target_link_libraries(regextrie-c PRIVATE regextrie_c_upstream)
target_compile_features(regextrie-c PRIVATE c_std_11)
set_target_properties(regextrie-c PROPERTIES
  C_EXTENSIONS OFF
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

add_executable(regextrie-c-library-tests tests/regextrie_c_library_test.c)
target_link_libraries(regextrie-c-library-tests PRIVATE regextrie_c_upstream)
add_test(NAME regextrie-c-library COMMAND regextrie-c-library-tests)
add_test(
  NAME regextrie-c-cli
  COMMAND sh "${CMAKE_SOURCE_DIR}/tests/regextrie_c_cli_test.sh"
             "$<TARGET_FILE:regextrie-c>"
)
```

Set every configuration-specific runtime output property to the same
`${CMAKE_BINARY_DIR}/bin` path so single- and multi-config generators agree. For
Clang/GCC, compile the upstream target with `-Wall -Wextra -Wpedantic` but without
`-Werror`; compile project-owned CLI/test targets with those flags plus `-Werror`.
Use `/W4 /WX` for project-owned targets under MSVC while retaining upstream warnings.

When `REGEX_UTILS_ENABLE_SANITIZERS=ON`, require Clang or GCC and add
`-fsanitize=address,undefined -fno-omit-frame-pointer` to compile and link options for
the upstream library, CLI, and C test. Fail configuration clearly for unsupported
compilers instead of pretending sanitizers are active.

Configure, build, and test from a clean checkout with:

```sh
cmake -S . -B build/native \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DREGEX_UTILS_ENABLE_SANITIZERS=OFF
cmake --build build/native --parallel
ctest --test-dir build/native --output-on-failure
```

Debug is the supported exercise build because upstream relies on allocation asserts.
The first configuration requires HTTPS access for the verified archive; subsequent
builds and tests reuse `build/native/_deps` without global installation. CMake 3.24 or
newer and a C11 compiler are host prerequisites, not project dependencies.

To update upstream later, select a reviewed immutable commit, inspect its complete
diff and licensing status, download that commit archive, calculate its SHA-256, and
change the URL/hash together. Never add an unpinned branch URL or bypass `URL_HASH`.

### Implementation and launcher files

- `native/regextrie_c_cli.c`: project-owned argument parser, record reader, safety
  preflight, upstream API calls, JSON Lines serializer, and process-status handling.
- `bin/regextrie-c`: executable POSIX launcher that resolves the repository root and
  `exec`s `build/native/bin/regextrie-c` without changing the caller cwd.
- `tests/regextrie_c_library_test.c`: direct API characterization tests, including
  upstream collisions and sanitizer-covered cleanup.
- `tests/regextrie_c_cli_test.sh`: byte-precise end-to-end CLI tests using temporary
  files and the target path supplied by CTest.
- `CMakeLists.txt`: shared native build, pinned archive, targets, warnings, sanitizers,
  and CTest registration.
- `README.md`: native prerequisites, configure/build/test commands, CLI contract,
  examples, byte-class/wildcard limitations, expansion limits, and license caveat.

The launcher must not configure or compile implicitly. If the fixed target is absent,
write this diagnostic to stderr and exit 1:

```text
regextrie-c: build/native/bin/regextrie-c is missing; run cmake -S . -B build/native -DCMAKE_BUILD_TYPE=Debug, then cmake --build build/native
```

Do not search `PATH`, use a globally installed similarly named executable, or add
`build/native/bin` to the user's environment. Help/version are provided by the built
native CLI, so they require the same explicit build as every other operation.

## CLI Contract

```text
Usage:
  regextrie-c [OPTIONS] [WORD...]

Dictionary input:
  WORD...                         Dictionary records as separate arguments
  -i, --input FILE                Read LF/CRLF-delimited dictionary records;
                                  use - for stdin
  -m, --insert-mode word|regex    Call add_word or add_regex [default: regex]

Queries:
  -q, --query QUERY               Query with find_word; repeatable
  -Q, --query-input FILE          Read LF/CRLF-delimited queries; use - for stdin

Other:
  -h, --help                      Show help
  -V, --version                   Show wrapper and pinned source versions
```

Version output is exactly:

```text
regextrie-c 0.0.0 (RegexTrie c35e88931f64)
```

Implement option parsing in project-owned C; add no CLI dependency. Accept each short
or long spelling above with a separate value, reject `--option=value`, combined short
flags, unknown options, missing values, repeated `--input`/`--insert-mode`/
`--query-input`, and stray option-like words. `--` ends option parsing and permits
dictionary words beginning with `-`.

Exactly one dictionary source is required: one or more positional `WORD` operands, or
one `--input FILE`, never both. Exactly one query source is required: one or more
`--query` occurrences, or one `--query-input FILE`, never both. At most one selected
source may be stdin, and stdin is never inferred merely because it is non-terminal.

### Record and encoding rules

- Each argv operand or `--query` value is one record. A file or stdin source uses LF
  and CRLF delimiters, treats a final delimiter as optional, preserves interior empty
  records, and preserves a lone CR and all other bytes.
- A zero-byte dictionary file is a valid empty trie. A zero-byte query source contains
  no work and is a data failure. One LF is one empty record for either source.
- Require well-formed UTF-8 and reject embedded NUL before any upstream call. UTF-8 is
  accepted only as a lossless transport/JSON encoding: RegexTrie still indexes its
  individual encoded bytes, not Unicode characters.
- Bound each dictionary/query record to 1,024 bytes and each file/stdin source to 16
  MiB. Diagnose a limit before constructing the trie; do not silently truncate.
- In `regex` mode, additionally reject dictionary records longer than 16 bytes and
  require the sum of `2^byte_length` across all dictionary records—including
  duplicates—to be at most 65,536. Compute with overflow checks before calling
  `new_trie()`. These fixed limits prevent the documented exponential insertion from
  exhausting ordinary local runs; there is no override flag.
- Empty dictionary records consume one unit of the expansion budget and map to the
  root terminal. Empty queries are passed to `find_word` normally.

### API mapping and result semantics

After every argument, source, encoding, length, and expansion check succeeds:

1. Call `new_trie()` once.
2. For each dictionary record in source order, call `add_word()` once in `word` mode
   or `add_regex()` once in `regex` mode. Preserve duplicates.
3. Call `find_word()` exactly once for each query in source order and convert only
   return value 0 to JSON `false`; any nonzero value becomes `true`.
4. Call `free_trie()` exactly once before every normal return after construction.

Do not pre-normalize case, replace `?`, interpret regex syntax, deduplicate records,
post-filter collisions, run another matcher, or reconstruct private trie state. A
`found` result means only that pinned RegexTrie returned nonzero for that byte-class
path under the chosen insertion function.

Write one compact UTF-8 JSON object per query with this exact field order:

```json
{"query":"?oo","found":true,"insert_mode":"regex"}
```

Preserve query order and duplicates. Emit non-ASCII UTF-8 directly and escape JSON
quotes, backslashes, and control characters. Each object receives one LF. Never emit
the dictionary, expansion count, internal key classes, timing, prompts, or prose to
stdout.

### Diagnostics and exit statuses

- Exit 0 after all queries, regardless of whether any `found` value is false. Help and
  version also exit 0 and write to stdout only.
- Exit 2 for option syntax, unknown modes/options, conflicting or missing sources,
  repeated scalar options, or a zero-query argv list.
- Exit 1 for unreadable files, invalid UTF-8, NUL, record/source limits, a zero-record
  query file, expansion-budget failure, allocation detected in project-owned code,
  or non-EPIPE output failure.
- Prefix every project diagnostic with `regextrie-c:`, write it to stderr, and leave
  stdout empty. Read and preflight all records before constructing the trie or writing
  results so input failures cannot produce partial output.
- Upstream allocations may still assert or abort under genuine exhaustion. Document
  that residual limitation; do not install signal handlers or attempt recovery from
  upstream undefined state.
- Buffer complete JSON records and use checked writes. Treat stdout EPIPE as success
  without an additional diagnostic; other write/flush errors exit 1.

## Representative Invocations

Precomputed wildcard paths, the default mode:

```console
$ ./bin/regextrie-c -q foo -q '?oo' -q '???' -q qux -- foo bar
{"query":"foo","found":true,"insert_mode":"regex"}
{"query":"?oo","found":true,"insert_mode":"regex"}
{"query":"???","found":true,"insert_mode":"regex"}
{"query":"qux","found":false,"insert_mode":"regex"}
```

Plain insertion still preserves low-five-bit aliases:

```console
$ ./bin/regextrie-c --insert-mode word -q foo -q FOO -q '&//' -q '?oo' -- foo
{"query":"foo","found":true,"insert_mode":"word"}
{"query":"FOO","found":true,"insert_mode":"word"}
{"query":"&//","found":true,"insert_mode":"word"}
{"query":"?oo","found":false,"insert_mode":"word"}
```

Dictionary file plus query stdin:

```console
$ printf 'foo\r\nbar\r\n' > words.txt
$ printf '?oo\nba?\nother\n' | \
    ./bin/regextrie-c --input words.txt --query-input -
{"query":"?oo","found":true,"insert_mode":"regex"}
{"query":"ba?","found":true,"insert_mode":"regex"}
{"query":"other","found":false,"insert_mode":"regex"}
```

The launcher preserves the external cwd, so relative input paths resolve where the
user invoked it rather than beside `bin/` or the build tree.

## Implementation Milestones

1. Add the root CMake project and pinned FetchContent URL/hash; build the upstream
   static target in Debug with no Conan and reproduce the known strict-prototype
   warning without treating it as a project failure.
2. Add the project-owned C CLI skeleton, launcher, help/version, strict source
   arbitration, UTF-8/record reader, byte/source limits, diagnostics, and EPIPE logic.
3. Implement complete preflight and direct `word` mode mapping; test empty strings,
   duplicates, aliases, `@`, length behavior, and cleanup under sanitizers.
4. Implement `regex` mode with the 16-byte and 65,536-expansion gates, then verify
   wildcard combinations, `_` collision, bytewise UTF-8 behavior, and rejection before
   exponential work.
5. Add JSON Lines output, C/library and shell/CLI CTest coverage, README documentation,
   clean-fetch/offline builds, and the local-only unlicensed-source warning.

## Test Plan

### Dependency and build gates

```sh
cmake -S . -B build/native \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DREGEX_UTILS_ENABLE_SANITIZERS=OFF
cmake --build build/native --parallel
ctest --test-dir build/native --output-on-failure
./bin/regextrie-c --version
```

Assert configure downloads only the pinned commit archive, verifies its exact SHA-256,
populates source under `build/native/_deps`, and creates no Conan files/cache. Inspect
the compiler command database to confirm C11 without extensions, warnings-as-errors on
project code, assertions enabled, and no unreviewed source patch. Reconfigure and
rebuild with network unavailable while the populated build tree remains present.

Run a separate sanitizer tree:

```sh
cmake -S . -B build/native-sanitize \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DREGEX_UTILS_ENABLE_SANITIZERS=ON
cmake --build build/native-sanitize --parallel
ASAN_OPTIONS=detect_leaks=0 \
  ctest --test-dir build/native-sanitize --output-on-failure
```

Use `detect_leaks=0` only on macOS where LeakSanitizer is unavailable; enable leak
detection on supported hosts. Require no ASan/UBSan finding for accepted test inputs.

For source-grounded comparison, compile pinned upstream without modifying it:

```sh
cc -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Wpedantic \
  src/trie.c src/trietests.c -o trietests
```

Expect current Clang to emit only the known strict-prototype warnings under this flag
set. Confirm the example's no-argument usage/status 1, interactive prompts, `add_word`
case aliasing, and status 0 after an unreadable file; do not use it as the project CLI.

### Library and successful CLI behavior

- Directly test `new_trie`/`free_trie`, a zero-insertion trie, empty strings,
  duplicates, multiple words, missing paths, prefixes, suffixes, and length mismatch.
- Characterize `add_word("foo")` against `foo`, `FOO`, `&//`, `?oo`, and nearby
  negatives. Characterize `@` both when its class-0 slot exists and when it does not.
- Characterize `add_regex("foo")` against the original, all eight exact/`?`
  combinations, `_` aliases, same-length negatives, and shorter/longer queries.
- Verify a collision-free ten-byte regex insertion creates 2,047 nodes in a test that
  may inspect the public struct solely for this complexity assertion; production CLI
  code must not inspect it.
- Exercise argv and LF/CRLF file sources, optional terminal delimiters, interior and
  single empty records, duplicates, reordered records, spaces, tabs, embedded argv LF,
  metacharacters, valid multibyte UTF-8, and relative paths from an external cwd.
- Test zero-byte dictionary files in both modes and one-empty-record dictionaries.
  Preserve the distinction between empty dictionary and dictionary containing empty.
- Assert query JSON field order, raw Unicode plus JSON escaping, query order and
  duplicates, true/false mapping, one LF per object, empty success stderr, and quiet
  EPIPE. Compare NUL/control cases at the byte level.
- Prove the launcher resolves only the fixed project build, forwards argv/status
  unchanged, preserves cwd, and reports the exact build remedy when missing.

### Failure and safety behavior

- Reject unknown/combined/equals-form options, missing values, invalid modes, repeated
  scalar options, mixed dictionary sources, mixed query sources, absent sources,
  multiple stdin consumers, and option-like words without `--`; assert status 2.
- Reject missing/unreadable files, invalid UTF-8, NUL, records over 1,024 bytes,
  sources over 16 MiB, and zero-record query files with status 1 and no stdout.
- In regex mode, reject one 17-byte word, a cumulative expansion count above 65,536,
  and arithmetic-overflow attempts before `new_trie` or any recursive insertion.
  Count duplicates toward the limit and assert boundary 65,536 is accepted.
- Inject project-owned allocator failures in record/JSON handling and require cleanup,
  status 1, and no partial stdout. Do not simulate recovery inside upstream allocation
  assertions.
- Configure with a compiler unsupported by the sanitizer option and require an early
  clear error. Corrupt the archive/cache in a disposable build and require CMake's
  URL-hash failure rather than compiling unverified source.

## Acceptance Criteria

- The project fetches exactly commit `c35e88931f64` by verified archive hash and builds
  it locally as C11 through the shared root CMake project.
- CMake is the only added build/dependency mechanism; no Conan manifest, recipe,
  profile, lockfile, package cache, or global RegexTrie installation is introduced.
- `bin/regextrie-c` launches only the custom project-built executable and exercises
  `add_word`, `add_regex`, `find_word`, and `free_trie` without replacing their logic.
- The CLI contract is deterministic for argv/file/stdin records, JSON Lines, exit
  statuses, diagnostics, encoding, resource limits, and broken pipes.
- Tests preserve and explain low-five-bit aliases, bytewise wildcard expansion, `?`/
  `_` collision, `@`/terminal collision, empty strings, duplicates, and exponential
  growth rather than claiming conventional regex semantics.
- All project-owned C is warning-clean and passes CTest plus ASan/UBSan; known upstream
  warnings remain visible and isolated from warnings-as-errors.
- Regex parsing, regex inference/output, matching-text generation, subject search,
  spans/captures, and lossless enumeration remain explicitly unsupported.
- The implementation and README identify the absent upstream license and keep fetched
  source/build artifacts local and ignored; redistribution requires upstream permission.

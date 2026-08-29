# Plan: TRE Native CLI Exercise

## Summary

Exercise [`laurikari/tre`](https://github.com/laurikari/tre) through its maintained
native `agrep` command. Extend the shared root CMake build so it fetches an immutable
TRE source archive, runs upstream's Autotools build entirely under `build/native/`, and
installs the resulting command at `build/native/tre-install/bin/agrep`. Invoke that
project-local executable directly; do not create `bin/tre`, rename `agrep`, copy the
binary, or add an argument/output adapter.

The native command exposes TRE's defining operations: exact POSIX ERE search and
approximate search with configurable insertion, deletion, substitution, and total
cost limits. It also exposes record splitting, best-cost selection, match cost, and
match positions. Preserve its native grep-like output, diagnostics, statuses, locale
behavior, and known edge cases rather than designing a second CLI.

CMake is the project entry point, while the pinned upstream source retains its own
Autotools build. Conan does not improve this setup: the
[Conan Center recipe](https://github.com/conan-io/conan-center-index/tree/master/recipes/tre)
currently offers only `tre/cci.20230717`, a Conan Center Index pseudo-version whose
date-like suffix reflects its July 17, 2023 source snapshot. Its non-Windows build still
requires Autotools, gettext, and libtool. Do not add Conan for TRE.

## Verified Upstream Facts

- The authoritative source is [`laurikari/tre`](https://github.com/laurikari/tre), a
  C regex library and command-line tool under a two-clause BSD-style license.
- GitHub release [`v0.9.0`](https://github.com/laurikari/tre/releases/tag/v0.9.0),
  published September 20, 2024, is the latest tagged release. Development has continued
  since that release. Pin immutable current commit
  [`71bfcaf0af3994384987c6c2679ed7d078ffe189`](https://github.com/laurikari/tre/commit/71bfcaf0af3994384987c6c2679ed7d078ffe189)
  from May 23, 2026 rather than mutable `master` or the older release archive.
- The post-0.9.0 commits include input-size guards, a 65,536-byte regex limit, bounded
  internal stack growth, allocation fixes, backtracking and BRE-parenthesis fixes,
  header-layout cleanup, and new limit regression tests. Those unreleased safety fixes
  are material to a CLI accepting arbitrary local input.
- Fetch the GitHub commit archive
  `https://github.com/laurikari/tre/archive/71bfcaf0af3994384987c6c2679ed7d078ffe189.tar.gz`
  with SHA-256
  `8f630500dcd10ad5c086e3e8e851888107ecca93c384793f856384c6a5c19664`.
  The archive is a source snapshot and intentionally lacks generated `configure` and
  `Makefile.in` files, so `utils/autogen.sh` must run before out-of-tree configure.
- Upstream still declares version `0.9.0` in `configure.ac`; consequently the pinned
  post-release `agrep --version` reports `0.9.0`. The project documentation and tests
  must identify both the reported version and pinned commit so this is not mistaken
  for the tagged source.
- TRE implements POSIX Basic and Extended Regular Expressions plus extensions such as
  non-greedy repetition, inline option groups, word-boundary and shorthand classes,
  `\Q...\E`, hexadecimal escapes, backreferences in EREs, and approximate-match
  constraints embedded in subexpressions.
- The library targets strict POSIX match/submatch behavior. Its ordinary matcher has
  worst-case time linear in subject length and quadratic in regex length, except that
  backreferences can require exponential time. Match workspace is prepared during
  compilation or taken from stack/temporary storage rather than growing with ordinary
  subject length.
- Approximate matching uses edit distance. Insertions, deletions, and substitutions
  have independently configurable costs and count limits; the result reports total
  cost and individual operation counts. Setting maximum cost to zero requests an exact
  match.
- The public prefixed API includes `tre_regcomp`, `tre_regexec`, length-aware and raw
  byte variants, wide-character variants, `tre_regaexec`/`tre_reganexec`,
  `tre_regaparams_default`, `tre_regfree`, configuration queries, and callback-backed
  `tre_reguexec`. New code should include `<tre/tre.h>`; `<tre/regex.h>` is a legacy
  source-compatibility header that maps unprefixed names.
- Length-aware `tre_regncomp`/`tre_regnexec` and raw-byte variants can represent
  embedded NUL. In multibyte locales, ordinary string APIs interpret the active
  encoding and report submatch offsets in bytes. Raw-byte APIs bypass multibyte
  decoding.
- TRE does not implement multi-character collating elements or equivalence classes.
  Approximate matching does not support minimal/non-greedy repetitions. Backreferences
  materially weaken the otherwise predictable runtime guarantee.
- Upstream's `agrep` is a maintained, purpose-built exercise CLI. It compiles the
  pattern as a TRE extended regex, compiles a record-delimiter regex, reads files or
  stdin as byte records, then calls `tre_reganexec` for each record. It is suitable for
  this project and makes a custom wrapper redundant.
- With neither `-E` nor a numeric shorthand, `agrep` sets maximum cost to zero and
  performs exact search. `-E N` or `-0` through `-9` selects a maximum cost; `-D`,
  `-I`, and `-S` alter deletion, insertion, and substitution costs. `-B` performs a
  two-pass best-cost search and therefore rejects stdin.
- `-s` prints each selected record's total match cost. `--show-position` prints the
  first match's start/end byte offsets. The CLI does not expose the API's separate
  insertion/deletion/substitution counts or capture array.
- The default record delimiter is newline. `-d PATTERN` replaces it with a TRE regex,
  and `-M` moves delimiters after rather than before selected records. An empty-matching
  delimiter is rejected. A trailing delimiter does not invent a final empty record.
- The process calls `setlocale(LC_ALL, "")`. Character classes, multibyte decoding,
  case folding, and what constitutes a character therefore depend on the caller's
  locale. Position output remains byte-based.
- `agrep` can match NUL in input records because it uses the length-aware approximate
  API and a pattern can contain `\x00`. Ordinary selected-record output is not binary
  safe: its `%.*s` write stops at NUL. A local probe matching `a\0b` emitted only byte
  `a`. Document binary search as usable only with non-record output such as `--count`,
  `--quiet`, or file-name selection.
- Native numeric option parsing uses `atoi` without full validation. For example,
  `-E nope` becomes maximum cost zero and succeeds as exact search; trailing junk and
  negative values are not diagnosed consistently. Documentation should use only
  nonnegative decimal integers and tests must preserve the native parser behavior.
- Successful selection exits 0; no selected record exits 1. Help/version and handled
  pattern/option failures behave as documented, but some I/O/control failures do not:
  an unreadable sole file and `-B` on stdin print diagnostics and exit 1 because the
  caller ignores the handler's error result. A missing file can be masked by a later
  successful file. Do not normalize these upstream statuses.
- On the verified macOS build, a downstream pipe closing early terminates `agrep` with
  SIGPIPE/status 141. The direct invocation must retain that behavior.
- `agrep` performs matching/search only. TRE does not infer regexes from samples,
  optimize or rewrite existing regex source, or generate matching text.

Local validation built commit `71bfcaf0af39` on macOS arm64 with Apple Clang 21 after
running the upstream bootstrap, using static linking, approximate matching, `agrep`,
wide-character support, and multibyte support. The upstream `agrep` suite and all four
library test programs passed; the large-input limit test took roughly three minutes.
Direct probes covered exact and approximate search, nonuniform costs, embedded
approximate syntax, positions, version/help, invalid patterns, missing files, invalid
numeric values, stdin best-match rejection, embedded NUL, and broken pipes. A separate
temporary project using the planned CMake `ExternalProject` declaration fetched and
verified the archive, bootstrapped and built TRE, and installed `agrep`, `libtre.a`, and
the generated/public headers at the exact planned prefix.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core matching/search | Supported directly by upstream `agrep`: search TRE EREs over file or stdin records. |
| Approximate/fuzzy matching | Supported with maximum cost, per-operation costs, best-match mode, embedded approximate constraints, cost display, and positions. |
| Exact matching | Supported as native default/max-cost zero behavior. |
| Regex optimization | Unsupported; TRE compiles but does not emit a rewritten regex. |
| Regex inference from samples | Unsupported; input records are subjects, not positive/negative examples. |
| Matching-text generation | Unsupported. |
| Binary matching | Partially exposed: matching is length-aware, but ordinary record output truncates at NUL. |
| Captures and detailed edit counts | Available in the C API but not emitted by `agrep`; intentionally omitted rather than adding a wrapper. |

## Files and Dependency Setup

### Pinned CMake/Autotools build

Extend the root `CMakeLists.txt` introduced by the RegexTrie C plan. Keep one native
build tree; do not create a nested project-owned `CMakeLists.txt` or a Conan graph.
Include CMake's `ExternalProject` module and add a `tre_upstream` target with:

```cmake
include(ExternalProject)

set(TRE_COMMIT 71bfcaf0af3994384987c6c2679ed7d078ffe189)
set(TRE_INSTALL_DIR "${CMAKE_BINARY_DIR}/tre-install")

find_program(TRE_MAKE_PROGRAM NAMES gmake make REQUIRED)
foreach(tool IN ITEMS autoconf autoheader automake aclocal autopoint)
  string(TOUPPER "${tool}" tool_upper)
  find_program("TRE_${tool_upper}" "${tool}" REQUIRED)
endforeach()
find_program(TRE_LIBTOOLIZE NAMES glibtoolize libtoolize REQUIRED)

ExternalProject_Add(
  tre_upstream
  URL
    "https://github.com/laurikari/tre/archive/${TRE_COMMIT}.tar.gz"
  URL_HASH
    "SHA256=8f630500dcd10ad5c086e3e8e851888107ecca93c384793f856384c6a5c19664"
  DOWNLOAD_EXTRACT_TIMESTAMP FALSE
  PREFIX "${CMAKE_BINARY_DIR}/tre"
  INSTALL_DIR "${TRE_INSTALL_DIR}"
  UPDATE_DISCONNECTED TRUE
  PATCH_COMMAND
    "${CMAKE_COMMAND}" -E chdir <SOURCE_DIR> /bin/sh ./utils/autogen.sh
  CONFIGURE_COMMAND
    "${CMAKE_COMMAND}" -E env
      "CC=${CMAKE_C_COMPILER}"
      "CFLAGS=${TRE_CFLAGS}"
      "LDFLAGS=${TRE_LDFLAGS}"
      <SOURCE_DIR>/configure
        --prefix=<INSTALL_DIR>
        --disable-shared
        --enable-static
        --disable-nls
        --disable-system-abi
        --disable-debug
        --enable-warnings
        --enable-approx
        --enable-agrep
        --enable-wchar
        --enable-multibyte
  BUILD_COMMAND "${TRE_MAKE_PROGRAM}"
  INSTALL_COMMAND "${TRE_MAKE_PROGRAM}" install
)
```

Form `TRE_CFLAGS` as one space-delimited string, not a CMake semicolon list. For the
supported Debug build use `-O0 -g3 -Wall -Wextra -Wpedantic`; leave `TRE_LDFLAGS`
empty normally. When `REGEX_UTILS_ENABLE_SANITIZERS=ON`, require Clang or GCC and
append `-fsanitize=address,undefined -fno-omit-frame-pointer` to both compile and link
flags. Do not pass upstream `--enable-debug`: that option enables internal trace output
on stdout and would corrupt the native CLI stream; debug symbols and sanitizers do not
require it.

The root configure must support macOS and Linux/POSIX hosts and reject native Windows
before downloading with a clear message. TRE itself has Visual Studio projects, but
its Windows solution does not build the `agrep` CLI selected by this plan. Require a C
compiler, `/bin/sh`, CMake 3.24+, `make`, autoconf, automake, gettext's `autopoint`, and
GNU libtool (`glibtoolize` on macOS). `utils/autogen.sh` must find the same tools on
`PATH`; CMake's checks are an early diagnostic, not a tool bootstrap.

Disable NLS so the locally installed CLI has deterministic English diagnostics and no
runtime `libintl` dependency. `autopoint` remains a source-bootstrap prerequisite
because upstream invokes it before configure knows NLS is disabled. Keep approximate,
wide-character, and multibyte features explicitly enabled and system-regex ABI
compatibility explicitly disabled so the built headers and binary use TRE's own types
and prefixed implementation.

After installation, the only supported user-facing path is:

```text
build/native/tre-install/bin/agrep
```

Do not search `PATH`, call a system `agrep`, install under `/usr/local`, or copy/symlink
the executable into `bin/`. The fixed build-tree path distinguishes this implementation
from unrelated commands also named `agrep`.

Add a `tre-upstream-check` CMake target which depends on `tre_upstream`, obtains the
ExternalProject binary directory, and runs `${TRE_MAKE_PROGRAM} check` there. Keep it
out of the default build because the current exhaustive limit test is intentionally
slow. The normal project CLI test remains a CTest test and receives the absolute
installed `agrep` path as its sole harness argument.

Configure and build from a clean checkout with:

```sh
cmake -S . -B build/native \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DREGEX_UTILS_ENABLE_SANITIZERS=OFF
cmake --build build/native --parallel
ctest --test-dir build/native --output-on-failure
cmake --build build/native --target tre-upstream-check
build/native/tre-install/bin/agrep --version
```

The first configure/build needs HTTPS access and the listed source-bootstrap tools.
The archive, generated Autotools files, objects, static library, headers, and installed
binary remain under `/build/`, already ignored by the root `.gitignore`. A populated
build tree must rebuild without network access. Do not vendor the archive or generated
Autotools files.

### Why Conan is not selected

Conan Center currently exposes only `tre/cci.20230717`. `cci.YYYYMMDD` is its
pseudo-version convention here, and the recipe confirms that it fetches upstream commit
`07e66d07b44ae95a7a89f79c7ce1090f0f4d64db`, committed July 17, 2023. That snapshot
predates release 0.9.0 by fourteen months and the selected head by nearly three years.
On non-Windows systems its recipe still runs Autotools and adds gettext/libtool as tool
requirements, so it neither provides the selected source nor removes the upstream build
stack. Do not write a local Conan recipe merely to wrap the same ExternalProject.
Re-evaluate only if Conan Center publishes the selected or a newer reviewed release and
materially simplifies the complete native dependency graph.

### Implementation and documentation files

- `CMakeLists.txt`: extend the shared native build with the pinned TRE ExternalProject,
  tool/platform preflight, installed path, sanitizer propagation, CTest registration,
  and opt-in upstream-check target.
- `tests/tre_agrep_cli_test.sh`: byte-aware direct-process tests; accept the installed
  binary path from CTest and never resolve `agrep` from `PATH`.
- `README.md`: add prerequisites, build/test commands, the full direct invocation,
  native option/output behavior, locale and binary caveats, pinned commit, and license.
- `.gitignore`: no change is expected because every generated TRE path is beneath
  `/build/`; add no Conan ignore entries solely for this plan.

## Native CLI Contract

The project defines no new interface. Document and test the pinned upstream command:

```text
Usage: build/native/tre-install/bin/agrep [OPTION]... PATTERN [FILE]...

Pattern:
  -e, --regexp=PATTERN          Supply PATTERN as a TRE ERE
  -i, --ignore-case             Locale-sensitive case-insensitive matching
  -k, --literal                 Treat PATTERN as a literal string
  -w, --word-regexp             Require a whole-word match

Approximate matching:
  -E, --max-errors=NUM          Maximum total match cost
  -0 ... -9                     Shorthand maximum cost
  -D, --delete-cost=NUM         Cost of a character missing from the subject
  -I, --insert-cost=NUM         Cost of an extra subject character
  -S, --substitute-cost=NUM     Cost of a substituted character
  -B, --best-match              Select only records with the lowest cost

Records and selection:
  -d, --delimiter=PATTERN       TRE regex separating input records
  -M, --delimiter-after         Print custom delimiters after selected records
  -v, --invert-match            Select nonmatching records
  -m, --max-count=NUM           Stop after NUM selected records per input

Output:
  -c, --count                   Print selected-record counts
  -l, --files-with-matches      Print only names of files with selections
  -n, --record-number           Prefix record numbers
  -s, --show-cost               Prefix match costs
      --show-position           Prefix first-match byte start/end offsets
      --color, --colour         Highlight the first match with ANSI escapes
  -h, --no-filename             Suppress file-name prefixes
  -H, --with-filename           Always print file-name prefixes
  -q, --quiet, --silent         Suppress normal output

Other:
      --help                    Show native help
  -V, --version                 Show native reported version
  -y, --nothing                 Compatibility no-op
```

This synopsis records the public native surface; do not reimplement it. Long options
use GNU `getopt_long` behavior on the supported builds and commonly accept both
`--name=value` and `--name value`. `--` ends option parsing. Prefer `-e PATTERN` when a
pattern begins with `-` or when separating it clearly from files.

### Input, regex, and matching rules

- `PATTERN` is one argv string and therefore cannot contain an embedded NUL. Quote it
  for the shell. TRE escapes such as `\x00` can still express a NUL character.
- With no `FILE`, or with `-`, records come from stdin. Multiple file operands are
  searched in order. Relative paths resolve from the caller's cwd.
- Default newline records exclude the delimiter. Custom delimiters are TRE EREs and
  may span bytes; `-M` controls whether the delimiter is emitted after rather than
  before a selected record. Preserve upstream's exact delimiter rules.
- With no cost option, matching is exact. `-E N`/`-N` changes only the global maximum
  cost. Pattern-level `{...}` approximate constraints remain part of TRE syntax and
  can constrain individual subexpressions.
- Costs and positions describe the best match TRE returns within each record. Position
  units are bytes even in multibyte locales. `-s` exposes total cost, not individual
  edit counts.
- `-B` reads each named file twice to discover and then emit the globally best cost.
  It is invalid for stdin. Do not use it for FIFOs, changing files, or other inputs
  that cannot be replayed identically.
- Use nonnegative base-10 integer arguments. Native `atoi` acceptance of malformed or
  negative values is an implementation quirk, not a recommended input format.
- Set `LC_ALL=C` for deterministic byte-oriented ASCII tests. Document that ordinary
  user invocations inherit their locale and can intentionally use UTF-8/multibyte
  behavior.

### Native output and statuses

- Selected records are written in input order with native delimiter placement.
  Filename, record number, cost, and position prefixes appear in that order when all
  are enabled. `--color` inserts `GREP_COLOR` or default `01;31` ANSI sequences even
  when stdout is redirected.
- `--count`, `--files-with-matches`, `--quiet`, and `--invert-match` retain their native
  grep-like interactions. Tests should cover combinations but must not impose a new
  project-level precedence or structured format.
- Match success exits 0. No selected record exits 1 with normally empty stderr. Help
  and version write to stdout and exit 0. Invalid options, patterns, and delimiters
  write native diagnostics to stderr and normally exit 2.
- Preserve verified deviations: a missing sole file and `-B` on stdin exit 1;
  malformed numeric values can be accepted; one missing file can be masked by a match
  in another; output after NUL truncates; EPIPE can terminate by SIGPIPE/status 141.
- Do not add JSON, prefix or translate diagnostics, buffer or rewrite records, validate
  native numeric options, repair binary output, suppress ANSI automatically, or map
  statuses. These would describe a project wrapper rather than TRE's CLI.

## Representative Invocations

Approximate search with cost, record number, and position:

```console
$ printf 'optimize\noptimise\noptmise\nopitmize\nother\n' | \
    build/native/tre-install/bin/agrep -2 -n -s --show-position optimize
1:0:0-8:optimize
2:1:0-8:optimise
3:2:0-7:optmise
4:2:0-8:opitmize
```

Exact search is the default:

```console
$ printf 'optimize\noptimise\n' | \
    build/native/tre-install/bin/agrep optimize
optimize
```

Nonuniform edit costs with maximum cost two:

```console
$ printf 'abc\naxc\nabbc\nac\n' | \
    build/native/tre-install/bin/agrep -E 2 -I 2 -D 3 -S 4 -s abc
0:abc
2:abbc
```

Approximate constraints embedded in a subexpression:

```console
$ printf 'abc\naxc\nabbc\nac\nzzz\n' | \
    build/native/tre-install/bin/agrep -s '(abc){~1}'
0:abc
1:axc
1:abbc
1:ac
```

These examples are byte-for-byte expectations under `LC_ALL=C` for the pinned commit.
When demonstrating UTF-8 character classes or case folding, show the selected locale
explicitly and assert semantic matches rather than assuming every host has the same
locale database.

## Implementation Milestones

1. Extend the shared root CMake project with host-tool checks, exact archive/hash,
   ExternalProject bootstrap/configure/build/install, and the fixed local output path.
   Prove a clean build reports TRE 0.9.0 while recording commit `71bfcaf0af39`.
2. Add the opt-in upstream-check target and run the complete upstream suite with
   approximate, wide-character, multibyte, and static-library support enabled.
3. Add direct CLI tests for exact search, fuzzy costs, best match, embedded approximate
   syntax, record delimiters, positions, locale, output modes, and native statuses.
4. Add byte-level edge tests for NUL truncation, malformed numeric acceptance, missing
   file masking, stdin best-match rejection, ANSI, and broken pipes without wrapping
   or correcting upstream behavior.
5. Add README prerequisites, build commands, direct invocation, examples, capability
   boundaries, commit/version distinction, license, and CMake-without-Conan rationale;
   validate clean-fetch and cached/offline builds.

## Test Plan

### Dependency and build gates

```sh
cmake -S . -B build/native \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DREGEX_UTILS_ENABLE_SANITIZERS=OFF
cmake --build build/native --parallel
ctest --test-dir build/native --output-on-failure
cmake --build build/native --target tre-upstream-check
build/native/tre-install/bin/agrep --version
```

Assert the source directory resolves to exact commit archive/hash, all TRE generated
files and install artifacts remain below `build/native`, the install contains static
`libtre`, `<tre/tre.h>`, generated `<tre/tre-config.h>`, and `bin/agrep`, and no Conan
manifest/cache or global install is created. Confirm the configured feature summary has
system ABI and NLS disabled while approximate, `agrep`, wchar, and multibyte are enabled.

Re-run the normal build and focused tests with network unavailable while retaining the
populated build tree. In a disposable tree, corrupt the downloaded archive and require
CMake's URL-hash failure. Remove one required bootstrap tool from `PATH` and require a
configure-time diagnostic before download.

Run a separate sanitizer tree:

```sh
cmake -S . -B build/native-sanitize \
  -DCMAKE_BUILD_TYPE=Debug \
  -DREGEX_UTILS_ENABLE_SANITIZERS=ON
cmake --build build/native-sanitize --parallel
ctest --test-dir build/native-sanitize --output-on-failure
```

On macOS set `ASAN_OPTIONS=detect_leaks=0` only where the local runtime lacks
LeakSanitizer; keep leak detection on supported Linux hosts. Require no ASan/UBSan
finding from the sanitizer-built `agrep` exercised by the project CTest suite. Run the
complete upstream suite in the normal tree: its `test-limits` intentionally allocates
and scans through very large sizes and is not a sanitizer gate. Give that normal test a
generous timeout and do not mistake it for a hang while it is consuming CPU.

### Successful native behavior

- Assert `--help` and `--version` use stdout, exit 0, and expose/report the expected
  native interface and `0.9.0`; separately verify the source commit/hash.
- Exercise exact default, `-E` and numeric shorthand bounds, each nonuniform cost,
  best-match named-file mode, literal, word, ignore-case, inverted, and pattern-level
  approximate constraints.
- Exercise stdin, `-`, one and multiple named files, empty input, records with and
  without final delimiters, empty/interior records, custom regex delimiters, `-M`, long
  records, relative paths from an external cwd, and ordering across files.
- Exercise count, files-with-matches, record number, cost, position, filename override,
  maximum count, quiet, color with default and `GREP_COLOR`, and meaningful option
  combinations. Compare ANSI and delimiters at the byte level.
- Under `LC_ALL=C`, assert the four representative examples exactly. Under one detected
  UTF-8 locale, test multibyte literals, character classes, case folding, invalid
  sequences, and that positions are byte offsets.
- Use `\x00` against NUL-containing records to prove matching succeeds. Use `--count`
  for a reliable binary-safe result, then separately assert ordinary record output
  truncates at the first NUL as pinned native behavior.

### Failure and native-edge behavior

- Assert no-match status 1 with empty stderr; invalid/unknown options, absent pattern,
  malformed regex, malformed delimiter, and empty-matching delimiter normally use
  status 2 and native stderr.
- Characterize missing/unreadable file behavior alone, before/after a matching file,
  stdin `-B`, zero `--max-count`, and read failures. Preserve the actual 0/1/2 results
  even when they differ from the help summary.
- Characterize zero, positive, negative, nonnumeric, and in-range trailing-junk values
  for `-E`, `-D`, `-I`, `-S`, and `-m`; documentation uses only valid decimal inputs,
  but tests prevent accidental normalization. Do not pass values outside C `int` range
  because upstream `atoi` makes that conversion undefined.
- Close a downstream pipe after one record and assert native SIGPIPE behavior on the
  supported host. Do not require the same numeric shell status on platforms that encode
  signals differently; require nonzero signal termination and no project diagnostic.
- Test the selected head's regex-length boundary and nearby over-limit failure without
  allocating unbounded project data. Leave the exhaustive multi-gigabyte coverage to
  upstream `test-limits`.
- Prove no `bin/tre`, `bin/agrep`, copied binary, shell adapter, JSON serializer, or
  globally resolved command is used by documentation or tests.

## Acceptance Criteria

- CMake fetches only archive `71bfcaf0af39` with the recorded SHA-256, bootstraps and
  builds it using upstream Autotools, and installs it only below `build/native`.
- TRE is built static with approximate, `agrep`, wide-character, and multibyte support;
  NLS, system ABI compatibility, and internal stdout tracing are disabled.
- Conan is not added; the plan records why the current Conan Center recipe is stale and
  does not simplify the selected POSIX build.
- Users invoke only `build/native/tre-install/bin/agrep`, and the project preserves the
  complete native argument, output, diagnostic, locale, and exit behavior.
- Tests cover exact and fuzzy search, costs, best match, positions, record delimiters,
  pattern extensions, output controls, UTF-8 locale behavior, NUL limitations, native
  parser quirks, I/O failures, and broken pipes.
- The complete pinned upstream test suite and project CTest suite pass in the normal
  build; the sanitizer-built `agrep` passes the project CTest suite under ASan/UBSan on
  supported hosts without making the multi-gigabyte upstream limit test a sanitizer
  gate.
- Regex optimization, regex inference, matching-text generation, detailed edit counts,
  capture output, and binary-safe record output remain explicitly unsupported by the
  selected CLI rather than being emulated.
- README documentation distinguishes reported version 0.9.0 from the pinned post-release
  commit, identifies the BSD-style license, lists required host bootstrap tools, and
  explains the performance/backreference, locale, and binary-output caveats.

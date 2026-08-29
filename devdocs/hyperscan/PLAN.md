# Plan: Intel Hyperscan CLI Exercise

## Summary

Exercise [`intel/hyperscan`](https://github.com/intel/hyperscan) through a focused
project-owned C++ CLI at `bin/hyperscan`. The command will compile multiple regex or
literal expressions into an optimized Hyperscan database, scan one binary subject in
block, streaming, or vectored mode, and emit match events as JSON Lines. A separate
`info` command will expose the compiled database, scratch, and stream-state sizes.

Use a checked-in Conan 2 recipe for immutable upstream tag `v5.4.2.1`, not Conan
Center's older prebuilt `hyperscan/5.4.2` package. Conan is useful here because the
selected security tag requires OpenSSL for database integrity and upstream already
needs Boost headers and Ragel at build time. Keep the Conan home below the checkout,
pin Conan itself through `uvx`, lock the complete graph, and let the shared root CMake
project consume the locally built package.

The planned target is x86_64 Linux or macOS with SSSE3. On Apple Silicon, build an
x86_64 binary with Apple Clang and run it explicitly through Rosetta 2. Reject native
Arm, 32-bit targets, Windows, and Linux cross-builds from non-x86 hosts before fetching
or compiling. This plan is specifically for Intel Hyperscan; do not silently substitute
the Arm-capable Vectorscan fork.

## Verified Upstream Facts

- The authoritative source is [`intel/hyperscan`](https://github.com/intel/hyperscan),
  a BSD-3-Clause C/C++ library for matching many expressions simultaneously.
- Pin annotated tag
  [`v5.4.2.1`](https://github.com/intel/hyperscan/tree/v5.4.2.1), which resolves
  to commit
  [`809f09b611e8da52b377481c14db575bf2625fad`](https://github.com/intel/hyperscan/commit/809f09b611e8da52b377481c14db575bf2625fad).
  The tag was created August 26, 2026 after a sequence of 2026 security fixes. Do not
  track mutable `master`.
- Fetch
  `https://github.com/intel/hyperscan/archive/refs/tags/v5.4.2.1.tar.gz` with SHA-256
  `7119ef2db45c98abd816ba789aae82fdfd1a0b240bb40a88bac2d90933a346df`.
- The security-tag changes add defensive pattern, database, engine, NFA, DFA, scratch,
  stream, and serialization checks; several out-of-bounds and overflow regression
  tests; and HMAC-SHA256 protection for compiled databases. The HMAC implementation
  adds a required OpenSSL Crypto dependency to both `hs` and `hs_runtime`.
- Upstream did not bump its internal version constants: `CMakeLists.txt`, `hs.h`, and
  `hs_version()` still report `5.4.2`. Set `SOURCE_DATE_EPOCH=1787718881`, the tagger
  timestamp, so `hs_version()` reproducibly reports `5.4.2 2026-08-26`. Project help,
  version output, and documentation must also name source tag `v5.4.2.1` so the build
  is not mistaken for the older tag.
- Hyperscan compiles PCRE-like expressions into immutable databases and reports matches
  synchronously through callbacks. It supports block, streaming, and vectored databases;
  a database compiled for one mode cannot be scanned with another mode's API.
- Block mode scans one contiguous buffer with `hs_scan`. Vectored mode scans an array of
  non-contiguous blocks with `hs_scan_vector` as one logical subject. Streaming mode
  retains state across `hs_scan_stream` calls and may report end-of-data matches only
  from `hs_close_stream`.
- The defining operation is simultaneous multi-pattern matching. Each expression can
  have an integer ID and compile flags; every callback identifies the expression and
  reports an end offset. Hyperscan does not guarantee global callback ordering and may
  report several end positions for one expression.
- Start offsets are disabled by default and the callback's `from` argument is then zero,
  not a meaningful start. `HS_FLAG_SOM_LEFTMOST` enables the leftmost start for each end
  offset, with performance and pattern-support costs. Streaming SOM additionally needs
  exactly one small, medium, or large horizon; small and medium horizons may return
  `HS_OFFSET_PAST_HORIZON` instead of a start.
- Compile flags include case-insensitive, dot-all, multiline, single-match, allow-empty,
  UTF-8, Unicode properties, prefilter, SOM-leftmost, logical-combination, and quiet
  modes. UCP only has meaning with UTF-8. Single-match and prefilter are each incompatible
  with SOM.
- Prefilter mode may broaden unsupported constructs and deliberately returns a superset
  of true matches. It requires a separate confirmation engine for exact results. This
  exercise exposes the upstream event stream but does not invent such a confirmer.
- `hs_compile_ext_multi` supports per-expression minimum end offset, maximum end offset,
  minimum match length, edit distance, or Hamming distance. Edit and Hamming distance are
  mutually exclusive. Approximate matching is documented as experimental and can have a
  large performance cost.
- `hs_compile_lit_multi` treats every byte literally, accepts explicit lengths and
  embedded NUL, and supports only caseless, single-match, and SOM flags. The selected
  tag rejects zero-length literals and lengths above 8,192 bytes.
- The selected tag centrally caps an individual pattern or literal at 8,192 bytes and a
  compiled database at 4 GiB, with smaller engine-specific limits. The CLI adds lower
  aggregate input/output bounds before calling the library.
- Hyperscan's default regex semantics differ materially from PCRE: captures and
  backreferences are unavailable, arbitrary zero-width assertions, recursion,
  conditionals, callouts, atomic groups, and possessive quantifiers are unsupported,
  match callbacks are not ordered, all possible end positions may be reported, and only
  end offsets are available unless SOM is requested.
- In UTF-8 mode, scanning malformed UTF-8 has undefined behavior. The CLI must strictly
  validate both regex source and subject bytes before calling Hyperscan when `--utf8` is
  active. Without that flag, subject scanning is binary-safe and offsets are byte offsets.
- `hs_alloc_scratch` allocates fixed scan workspace for a compiled database; a scratch
  block cannot be used concurrently. `hs_database_size`, `hs_scratch_size`, and, for
  streaming databases, `hs_stream_size` expose useful compiled resource sizes.
- `hs_valid_platform` checks the minimum SSSE3 runtime requirement. Upstream supports
  x86 and x86_64, but this plan intentionally narrows the project package to x86_64.
- Upstream ships example and specialist tools (`simplegrep`, `hscheck`, `hsbench`,
  `hscollider`, and `hsdump`), but no maintained single CLI provides this plan's focused
  multi-pattern, three-mode scan contract and machine-readable event output. `simplegrep`
  is a one-pattern block-mode example; the other tools target compilation checks,
  benchmarking, differential correctness, or debug dumping. A custom CLI is warranted.
- [Conan Center's current recipe](https://github.com/conan-io/conan-center-index/tree/master/recipes/hyperscan)
  exposes only `5.4.2` and `5.4.0`. It cannot select `v5.4.2.1`, does not model the new
  OpenSSL dependency, and pins Boost 1.83.0 plus Ragel 6.10 around the older source.
  Consuming its binary package would omit the selected security changes.

Local validation on macOS arm64 used Conan 2.31.2 through `uvx`, Conan Center Boost
1.83.0 headers, OpenSSL 3.5.8, Ragel 6.10, CMake 4.4.2, and Apple Clang 21. A temporary
local recipe cross-built `v5.4.2.1` as x86_64/C++11 with `-march=core2`, linked a static
x86_64 copy of upstream `simplegrep`, and ran it successfully under Rosetta 2. The probe
also verified that OpenSSL can be built static with applications, FIPS, and zlib disabled
for this HMAC-only dependency. Upstream emits numerous warnings on current Clang, so its
warnings must remain visible but separate from warnings-as-errors on project-owned code.
The complete upstream unit suite was not run during plan authoring.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core multi-regex matching | Supported: compile ordered expressions with IDs and scan one subject in block, stream, or vector mode. |
| Literal matching | Supported with the length-aware multi-literal API, including NUL from expression files. |
| Approximate matching | Supported through one global edit-distance or Hamming-distance extended parameter; documented as experimental. |
| Compile-time constraints | Supported through global minimum/maximum end offsets and minimum match length. |
| Prefilter matching | Supported with an explicit false-positive warning; no exact confirmation is added. |
| Compiled-resource inspection | Supported through database, scratch, and stream-state size APIs. |
| Regex optimization | Partially applicable: Hyperscan builds an optimized binary database but does not emit rewritten regex source. |
| Regex inference from samples | Unsupported. Patterns are supplied by the caller. |
| Matching-text generation | Unsupported. Hyperscan scans caller-provided bytes. |
| Captures and matched-text extraction | Unsupported by Hyperscan's callback model; only IDs and byte offsets are emitted. |
| Logical combinations | Supported by the library but omitted because this focused CLI assigns sequential IDs and one shared flag set. |
| Database serialization | Supported by the library but omitted; this CLI compiles and exercises a database in one process. |

## Files and Dependency Setup

### Project-local Conan 2 graph

Add these dependency files:

- `conanfile.py`: root consumer recipe requiring exactly `hyperscan/5.4.2.1`, generating
  `CMakeDeps` and `CMakeToolchain`, and placing generated files in
  `build/hyperscan/conan/`.
- `conan.lock`: checked-in lockfile covering the local Hyperscan recipe and every Conan
  Center recipe revision selected for its dependency graph.
- `conan/profiles/hyperscan-x86_64`: host profile which `include(default)`, overrides
  `arch=x86_64`, `build_type=Release`, and `compiler.cppstd=11`, and otherwise retains the
  locally detected compiler, standard library, and OS settings.
- `conan/recipes/hyperscan/conanfile.py`: checked-in package recipe for the immutable
  source archive.
- `conan/recipes/hyperscan/test_package/CMakeLists.txt`, `conanfile.py`, and
  `test_package.cpp`: package linkage/runtime smoke test.

Pin the Conan executable itself as `conan==2.31.2` and invoke it only through:

```sh
CONAN_HOME="$PWD/.conan2" uvx --from conan==2.31.2 conan ...
```

Do not install Conan globally. Add `/.conan2/` and `/CMakeUserPresets.json` to
`.gitignore`; the CMake build already remains below ignored `/build/`. `uvx` supplies the
Python interpreter used by both Conan and upstream's build-time Python scripts. The
checked-in lockfile, not an existing user cache, determines dependency recipe revisions.

The local recipe must make these decisions explicit:

- Package name/version: `hyperscan/5.4.2.1`; `package_type = "static-library"`.
- Settings: OS, architecture, compiler, and build type. Support only `Macos` and `Linux`
  host settings with `arch=x86_64` and exact `compiler.cppstd=11`; reject other standard
  settings rather than relying on Conan Center's broad `make_unique` compatibility patch.
- Options: `fPIC` and project option `sanitizers`. Build only static `libhs`; do not
  package `hs_runtime`, Chimera, tools, examples, docs, or unit binaries.
- Requirements: `boost/1.83.0` with `boost/*:header_only=True`, and `openssl/3.5.8`
  static with `no_apps=True`, `no_fips=True`, and `no_zlib=True`.
- Tool requirement: `ragel/6.10`, resolved in the build context so Apple Silicon uses a
  native arm64 generator while producing x86_64 Hyperscan objects.
- Source: the exact tag archive and SHA-256 recorded above, extracted with `strip_root`.
- CMake cache compatibility: set `CMAKE_POLICY_VERSION_MINIMUM=3.5` as a cache variable
  before upstream's old `cmake_minimum_required(VERSION 2.8.11)` is evaluated by CMake 4.
- CMake options: static only, `BUILD_EXAMPLES=OFF`, `BUILD_CHIMERA=OFF`,
  `BUILD_AVX512=OFF`, `BUILD_AVX512VBMI=OFF`, `FAT_RUNTIME=OFF`, and
  `DUMP_SUPPORT=OFF`. Leave `VALIDATE_PATTERN_INPUT=OFF`; its optional content heuristic
  rejects some otherwise valid NUL-heavy literals, while the selected tag's unconditional
  API bounds and the CLI's exact length checks remain active.
- Baseline code generation: put `-march=core2 -mtune=generic` in both upstream C and C++
  flags. This explicitly suppresses upstream's `-march=native`, includes SSSE3, works
  under Rosetta, and prevents build-host AVX features from leaking into the artifact.
- Normal package: `OPTIMISE=ON`, `DISABLE_ASSERTS=ON`, and Release mode. Sanitizer
  package: `OPTIMISE=OFF`, `DISABLE_ASSERTS=OFF`, and append
  `-fsanitize=address,undefined -fno-omit-frame-pointer` to C, C++, and consumer link
  flags while retaining Release mode to avoid upstream's Debug-only `-Werror` policy.
- Reproducibility: apply `SOURCE_DATE_EPOCH=1787718881` around CMake configure/build.
- Build only target `hs`; do not run the default all-target build, which would compile
  unrelated upstream tools and tests discovered during configure.
- Package exactly `LICENSE`, `lib/libhs.a`, and public headers `hs.h`, `hs_common.h`,
  `hs_compile.h`, and `hs_runtime.h`. Do not copy private headers or source.
- Publish CMake file name `hyperscan` and target `hyperscan::hs`; make OpenSSL Crypto a
  transitive link requirement and mark Boost as an intentional build-only requirement.

Do not apply Conan Center's large 5.4.2 patch set or modify upstream source. The verified
C++11, target-only build succeeds without its `make_unique` rewrite. Keep upstream
warnings visible and do not promote them to errors; project-owned C++ remains warning
clean with warnings denied.

The recipe's `test_package` must link `hyperscan::hs`, call `hs_valid_platform`, compile
two expressions with `hs_compile_multi`, allocate scratch, scan a NUL-containing block,
assert the expected IDs/end offsets, and free every object. On Apple Silicon, Conan runs
the resulting x86_64 test under Rosetta. The test must also assert that `HS_MAJOR`,
`HS_MINOR`, and `HS_PATCH` are 5, 4, and 2 while the package reference remains 5.4.2.1.

### Bootstrap, lock, and update workflow

From a clean checkout:

```sh
CONAN_HOME="$PWD/.conan2" \
  uvx --from conan==2.31.2 conan profile detect --force

CONAN_HOME="$PWD/.conan2" \
  uvx --from conan==2.31.2 conan create conan/recipes/hyperscan \
    --profile:host=conan/profiles/hyperscan-x86_64 \
    --profile:build=default \
    --build=missing

CONAN_HOME="$PWD/.conan2" \
  uvx --from conan==2.31.2 conan lock create . \
    --profile:host=conan/profiles/hyperscan-x86_64 \
    --profile:build=default \
    --lockfile-out=conan.lock

CONAN_HOME="$PWD/.conan2" \
  uvx --from conan==2.31.2 conan install . \
    --profile:host=conan/profiles/hyperscan-x86_64 \
    --profile:build=default \
    --lockfile=conan.lock \
    --build=missing
```

The first command creates only checkout-local `.conan2/` state. The host profile inherits
the detected compiler version instead of hard-coding one machine's Xcode or GCC version.
The build profile remains the detected native machine, which is essential for the Ragel
tool on Apple Silicon. On native x86_64 Linux/macOS the host and build architectures
match; on macOS arm64 only the host side is overridden to x86_64.

For an intentional dependency update, change source/dependency pins and checksums in the
local recipe, rerun `conan create`, regenerate `conan.lock` with an explicit update, and
review the recipe revisions and package graph before committing. Never regenerate the
lockfile implicitly during an ordinary build.

For the sanitizer graph, use the same locked recipe revisions but add
`-o:h 'hyperscan/*:sanitizers=True'` to both `conan create` and `conan install`, and place
consumer generators under `build/hyperscan-sanitize/conan/`. Do not reuse normal and
sanitized package binaries.

### Shared CMake integration

Extend the root `CMakeLists.txt` introduced by the RegexTrie C plan and already extended
by TRE. Retain CMake 3.24 and the root project's unconditional C language. Add a gated
Hyperscan target so ordinary RegexTrie/TRE builds do not require Conan, OpenSSL, a C++
compiler, or an x86_64 host package:

```cmake
option(REGEX_UTILS_BUILD_HYPERSCAN "Build the Intel Hyperscan exercise" OFF)

if(REGEX_UTILS_BUILD_HYPERSCAN)
  enable_language(CXX)
  find_package(hyperscan CONFIG REQUIRED)

  add_executable(hyperscan native/hyperscan_cli.cpp)
  target_link_libraries(hyperscan PRIVATE hyperscan::hs)
  target_compile_features(hyperscan PRIVATE cxx_std_11)
  set_target_properties(hyperscan PROPERTIES
    CXX_EXTENSIONS OFF
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  )
  target_compile_definitions(hyperscan PRIVATE
    REGEX_UTILS_HYPERSCAN_SOURCE_TAG="v5.4.2.1"
  )

  add_test(
    NAME hyperscan-cli
    COMMAND sh "${CMAKE_SOURCE_DIR}/tests/hyperscan_cli_test.sh"
               "$<TARGET_FILE:hyperscan>"
  )
endif()
```

Add compiler-specific warning flags to the project target: `/W4 /WX` for MSVC in theory,
or `-Wall -Wextra -Wpedantic -Werror` for Clang/GCC. This plan rejects Windows before
dependency setup, so the MSVC branch merely keeps the shared project structurally sound.
When `REGEX_UTILS_ENABLE_SANITIZERS=ON`, add matching ASan/UBSan compile and link flags to
the project target and require the sanitizer-built Conan package.

Configure the normal consumer after `conan install` with:

```sh
cmake -S . -B build/hyperscan \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=build/hyperscan/conan/conan_toolchain.cmake \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DREGEX_UTILS_ENABLE_SANITIZERS=OFF \
  -DREGEX_UTILS_BUILD_REGEXTRIE_C=OFF \
  -DREGEX_UTILS_BUILD_TRE=OFF \
  -DREGEX_UTILS_BUILD_HYPERSCAN=ON
cmake --build build/hyperscan --parallel
ctest --test-dir build/hyperscan --output-on-failure
```

The root consumer recipe's layout must make the toolchain path above exact. Conan manages
only Hyperscan and its transitive dependencies. The dedicated build tree disables the
RegexTrie and TRE blocks before their source or tool preflights, while still reusing the
one root CMake project. Their established `build/native` Debug build remains independent
of Conan and continues to exercise both earlier native plans. Do not convert those
dependency-light plans to Conan merely because a root consumer now exists.

### Platform gate and launcher

Add `bin/hyperscan` as a small POSIX launcher. It must resolve its own repository root,
preserve the caller's working directory, and use only `build/hyperscan/bin/hyperscan`. It
must not search `PATH`, invoke a system Hyperscan tool, or rebuild automatically.

- On `x86_64` Linux or macOS, `exec` the built command directly.
- On macOS `arm64`, first run `arch -x86_64 /usr/bin/true`; if that fails, print
  `hyperscan: Rosetta 2 is required to run the x86_64 build` to stderr and exit 1.
  Otherwise execute `arch -x86_64 <fixed-binary> ...`.
- On every other OS/architecture, print a concise unsupported-platform diagnostic and
  exit 1 before attempting the binary.
- If the fixed binary is absent or not executable, print the exact Conan/CMake bootstrap
  remedy and exit 1.

The C++ command must call `hs_valid_platform()` before compiling expressions. If it does
not return `HS_SUCCESS`, report the numeric Hyperscan status and exit 1 without reading
the subject or producing stdout.

### Implementation and documentation files

- `.gitignore`: add checkout-local Conan and generated user-preset paths.
- `conanfile.py`, `conan.lock`, and `conan/profiles/hyperscan-x86_64`: locked consumer
  graph and host profile.
- `conan/recipes/hyperscan/`: immutable local package recipe and test package.
- `CMakeLists.txt`: extend the shared native project with C++, Conan package lookup,
  executable, warnings, sanitizer handling, and CTest registration.
- `native/hyperscan_cli.cpp`: argument parsing, bounded binary input, strict UTF-8
  validation, direct API mapping, event buffering, JSON output, and cleanup.
- `bin/hyperscan`: fixed-path native/Rosetta launcher.
- `tests/hyperscan_cli_test.sh`: byte-aware end-to-end contract tests.
- `README.md`: bootstrap, platform support, command reference, examples, and semantic
  caveats shared with the other implemented tools.

## CLI Contract

### Commands

```text
bin/hyperscan scan [PATTERN_OPTIONS] [SCAN_OPTIONS]
bin/hyperscan info [PATTERN_OPTIONS]
bin/hyperscan --help
bin/hyperscan --version
```

`scan` is the primary command. `info` compiles the same database and reports its resource
sizes without reading subject input. Require the command name; do not add an implicit
default subcommand.

### Pattern sources and IDs

Exactly one pattern source is required:

- `-e, --expression PATTERN`: repeat one or more times. Each occurrence is one complete
  pattern and preserves its argument bytes.
- `-f, --expression-file PATH`: read LF-delimited byte records from one named file.
  Remove one terminal LF and its immediately preceding CR per record; preserve every
  other byte, including spaces, tabs, empty records, and NUL. `PATH` may not be `-`
  because stdin belongs to the subject.

Reject mixing `-e` and `-f`, a zero-byte expression file, more than 10,000 expressions,
any expression over 8,192 bytes, or cumulative expression bytes over 8 MiB before calling
Hyperscan. A file containing a single delimiter represents one empty expression, not zero
expressions. Preserve duplicates and source order. Assign stable unsigned IDs 1 through
N in that order; IDs are never inferred from pattern contents.

In regex mode, reject embedded NUL because `hs_compile_ext_multi` takes NUL-terminated
expressions. In literal mode, preserve NUL and pass exact `std::string::size()` values to
`hs_compile_lit_multi`. Do not echo raw pattern bytes in diagnostics.

### Pattern and compile options

- `--literal`: compile every pattern with `hs_compile_lit_multi`; default is regex mode
  with `hs_compile_ext_multi`.
- `--mode block|stream|vectored`: database/scan mode; default `block`.
- `-i, --caseless`: add `HS_FLAG_CASELESS`.
- `-s, --dotall`: add `HS_FLAG_DOTALL`.
- `-m, --multiline`: add `HS_FLAG_MULTILINE`.
- `--single-match`: add `HS_FLAG_SINGLEMATCH`.
- `--allow-empty`: add `HS_FLAG_ALLOWEMPTY`.
- `--utf8`: add `HS_FLAG_UTF8` and enable strict project-side UTF-8 validation.
- `--ucp`: add `HS_FLAG_UCP`; require `--utf8`.
- `--prefilter`: add `HS_FLAG_PREFILTER`.
- `--som-leftmost`: add `HS_FLAG_SOM_LEFTMOST`.
- `--som-horizon small|medium|large`: streaming SOM precision; valid only with
  `--mode stream --som-leftmost`. Default `large` in that combination.
- `--min-offset N`, `--max-offset N`, and `--min-length N`: set the corresponding
  unsigned 64-bit `hs_expr_ext_t` field for every regex.
- `--edit-distance N` or `--hamming-distance N`: set one unsigned 32-bit approximate
  distance for every regex; the two options are mutually exclusive.

Parse every numeric value as a complete base-10 string with overflow checking. Reject a
minimum offset above a maximum offset and a minimum length above a supplied maximum
offset before compilation, matching upstream's constraints. Scalar options may appear
only once; boolean repetition is also an error rather than silently idempotent.

Literal mode accepts only `--caseless`, `--single-match`, `--som-leftmost`, mode, and SOM
horizon. Reject dotall, multiline, allow-empty, UTF-8/UCP, prefilter, and every extended
parameter before calling the literal API. Reject single-match plus SOM and prefilter plus
SOM. Leave other pattern-support decisions to Hyperscan and report its indexed compile
error exactly once.

The shared flag/extended-parameter set deliberately omits per-pattern flags, logical
combination/quiet IDs, platform tuning, and grey-box compiler controls. Do not parse the
upstream tools' `ID:/regex/flags{ext}` format or link their internal expression parser.

### Subject and chunking options

`scan` accepts exactly one subject source:

- `--input PATH`: named binary file; `--input -` means stdin and is the default.
- `--text TEXT`: exact argument bytes, including an empty argument.

Reject both together. Read the complete subject before scanning, cap it at 256 MiB, and
preserve every byte including NUL, CR, LF, and invalid UTF-8 when UTF-8 mode is off. This
bounded pre-read lets all modes receive identical bytes and prevents late input errors
from causing partial stdout.

- `--chunk-size N`: positive decimal bytes, default 4096, accepted only in stream and
  vectored modes. Cap it at `UINT_MAX` and the 256 MiB subject limit.
- `--max-matches N`: positive decimal event limit, default 100,000 and maximum
  1,000,000. Buffer events in memory. On event N+1, return nonzero from the callback to
  terminate scanning, discard the buffer, print a limit diagnostic, and exit 1 with no
  stdout.

Block mode calls `hs_scan` once. Vectored mode divides the pre-read subject into
`--chunk-size` blocks and calls `hs_scan_vector` once; chunk boundaries do not reset
matching or offsets. Streaming mode opens one stream, calls `hs_scan_stream` for the same
chunks, and always calls `hs_close_stream` with the callback so end-of-data matches are
retained. For an empty subject, block mode scans a non-null zero-length buffer, vectored
mode supplies one zero-length vector, and streaming mode opens then closes without a scan
chunk.

### API mapping and cleanup

For both commands:

1. Complete option, platform, pattern-source, size, NUL, combination, and UTF-8 preflight.
2. Form expression pointers, IDs 1..N, shared flags, and optional extended structures.
3. Call `hs_compile_ext_multi` for regexes or `hs_compile_lit_multi` for literals with a
   null platform pointer and the exact selected mode.
4. On compile failure, use `hs_compile_error_t.expression` to report one-based pattern ID
   when available, free the error, and emit no stdout.
5. Allocate one scratch block with `hs_alloc_scratch` and use it only synchronously.
6. Run the selected scan API or size-query API.
7. Free scratch and database on every path; close an opened stream even after callback
   termination. Do not invoke a Hyperscan API from inside the callback.

Do not sort, deduplicate, coalesce, confirm, or re-match events. Buffering is solely for
all-or-nothing output and the match cap; final output preserves callback order exactly.

### `scan` output

Write one compact UTF-8 JSON object per callback, with this exact field order:

```json
{"id":1,"start":null,"end":5,"start_status":"disabled"}
```

- `id` is the assigned positive expression ID.
- `start` is a byte offset when SOM returned one, otherwise JSON `null`.
- `end` is the exclusive byte offset supplied by Hyperscan.
- `start_status` is `"available"`, `"disabled"`, or `"past_horizon"`.

Without SOM, ignore callback `from=0` and emit disabled/null. With SOM, emit the numeric
start unless it equals `HS_OFFSET_PAST_HORIZON`, in which case emit past-horizon/null.
Each object ends with one LF. Do not emit matched bytes, pattern source, a count, timing,
database statistics, callback flags, chunk boundaries, or prose. A valid scan with no
events exits 0 with empty stdout and stderr.

### `info` output

Compile and allocate scratch exactly as `scan`, then call `hs_database_size`,
`hs_scratch_size`, and, only in stream mode, `hs_stream_size`. Emit one compact JSON
object with exact field order:

```json
{"source_tag":"v5.4.2.1","library_version":"5.4.2 2026-08-26","compile_kind":"regex","mode":"stream","patterns":2,"database_bytes":1234,"scratch_bytes":2048,"stream_bytes":512}
```

Use JSON `null` for `stream_bytes` in block and vectored modes. Size values above are
illustrative and must not be asserted exactly across compilers or platforms. `info`
rejects all scan-only subject, chunk, and match-limit options.

### Diagnostics and statuses

- `--help` and `--version` write stdout only and exit 0. Version output is exactly
  `hyperscan v5.4.2.1 (Hyperscan 5.4.2 2026-08-26)`.
- Exit 0 after any valid `scan` or `info`, including no-match scans.
- Exit 2 for option syntax, source arbitration, invalid numeric values/combinations,
  local pattern bounds, invalid regex/literal compilation, or invalid UTF-8 required by
  `--utf8`.
- Exit 1 for unsupported CPU/platform, missing Rosetta or executable, unreadable files,
  subject/aggregate resource limits, allocation failure, match-limit termination,
  unexpected Hyperscan runtime errors, or non-EPIPE output failure.
- Prefix every diagnostic with `hyperscan:`, write it to stderr, and leave stdout empty.
  Compile errors identify `pattern N` and include upstream's message without raw pattern
  bytes.
- Buffer complete JSON records and use checked writes. Treat stdout EPIPE as success with
  no diagnostic; all other write/flush failures exit 1.

## Representative Invocations

Two simultaneous block-mode expressions:

```console
$ ./bin/hyperscan scan -e foo -e 'ba[rz]' --text 'xxfoobar baz'
{"id":1,"start":null,"end":5,"start_status":"disabled"}
{"id":2,"start":null,"end":8,"start_status":"disabled"}
{"id":2,"start":null,"end":12,"start_status":"disabled"}
```

The order shown is representative callback order, not a cross-pattern ordering contract.
Tests compare event multisets where upstream marks matches unordered.

Leftmost starts across stream chunks:

```console
$ printf 'xxfoobar' | ./bin/hyperscan scan -e 'foo.*bar' \
    --mode stream --chunk-size 3 --som-leftmost
{"id":1,"start":2,"end":8,"start_status":"available"}
```

Vectored binary subject and pure literals from a file:

```console
$ printf 'a\0b\nxyz\n' > literals.bin
$ printf 'xxa\0byyxyz' | ./bin/hyperscan scan --literal \
    --expression-file literals.bin --mode vectored --chunk-size 2
{"id":1,"start":null,"end":5,"start_status":"disabled"}
{"id":2,"start":null,"end":10,"start_status":"disabled"}
```

Approximate regex matching:

```console
$ ./bin/hyperscan scan -e colour --edit-distance 1 --text color
{"id":1,"start":null,"end":5,"start_status":"disabled"}
```

Resource inspection:

```console
$ ./bin/hyperscan info -e foo -e 'ba[rz]' --mode block
{"source_tag":"v5.4.2.1","library_version":"5.4.2 2026-08-26","compile_kind":"regex","mode":"block","patterns":2,"database_bytes":...,"scratch_bytes":...,"stream_bytes":null}
```

The ellipses describe platform-dependent JSON numbers and are not literal command output.

## Implementation Milestones

1. Add the pinned Conan tool invocation, local recipe, x86_64 host profile, checkout-local
   home ignore rules, and package test. Create and lock the normal package on native
   x86_64 or macOS arm64/Rosetta and verify source/hash, dependency versions, C++11,
   Core2 code generation, deterministic version date, and static linkage.
2. Extend the shared root CMake project with C++, `hyperscan::hs`, the project executable,
   warnings, CTest, and fixed launcher. Implement help/version, platform checks, strict
   common option parsing, cleanup, and the `info` command.
3. Implement bounded expression and subject sources, regex/literal compilation, strict
   UTF-8 validation, block scan, callback buffering, JSON Lines, diagnostics, statuses,
   and EPIPE handling.
4. Add stream and vectored scans, chunking, SOM status/horizons, compile flags, extended
   bounds, edit/Hamming distance, prefilter behavior, NUL literals, and match-limit
   termination.
5. Add package/CLI tests, the separately built sanitizer graph, README documentation,
   clean-checkout/offline validation, and cross-plan native-build regression coverage.

## Test Plan

### Dependency, package, and build gates

Run the exact clean-checkout bootstrap and normal CMake commands above. Assert:

- all Conan state is under `.conan2/`, all generated CMake files are under
  `build/hyperscan/conan/`, and no global Conan package or system Hyperscan is used;
- the lockfile resolves the exact local recipe revision plus Boost 1.83.0, OpenSSL 3.5.8,
  and Ragel 6.10 recipe revisions; ordinary install refuses silent lock changes;
- the downloaded Hyperscan archive passes the recorded SHA-256 and its Git tree matches
  tag commit `809f09b611e8`;
- the package contains only the license, four public headers, and static `libhs.a`, with
  OpenSSL Crypto as its transitive target dependency;
- compile commands show x86_64/Core2, C++11 for upstream, no AVX2/AVX-512/fat runtime,
  static linking, and no unreviewed source patch;
- project code is warning-clean with warnings denied while upstream warnings remain
  visible but nonfatal;
- `file build/hyperscan/bin/hyperscan` reports x86_64 on both Intel and Apple Silicon Macs,
  and `otool -L`/`ldd` shows no system Hyperscan or unexpected shared OpenSSL dependency;
- the recipe test package and project CTest pass, and `hs_version()` contains the fixed
  date rather than the build date.

Retain the populated `.conan2/` and build tree, disable network access, repeat `conan
install`, build, and focused tests, and require success from cached locked inputs. In a
disposable local home, corrupt the source archive and require checksum failure. Delete
one required package from another disposable home and require offline installation to
fail clearly rather than falling back to system headers/libraries.

Build the sanitizer variant in `build/hyperscan-sanitize/` with the local recipe option and
root CMake option both enabled. Run CTest with leak detection where supported; use
`ASAN_OPTIONS=detect_leaks=0` only on macOS runtimes without LeakSanitizer. Require no
ASan/UBSan finding for package smoke tests or accepted CLI inputs.

### CLI success behavior

- Assert exact help/version streams and statuses through both the built binary and
  launcher; prove the launcher preserves cwd and forwards argv/status unchanged.
- Exercise one and many regexes, duplicate patterns, stable IDs, no matches, overlapping
  matches, multiple end positions, alternation, anchors, dotall, multiline, caseless,
  single-match, allow-empty, prefilter, and documented unsupported constructs.
- Exercise block, stream, and vectored modes over identical bytes. Use chunk sizes 1,
  boundary-minus-one, boundary, boundary-plus-one, and larger than the subject; assert
  cross-chunk matches and byte offsets agree as event multisets where ordering is not a
  contract.
- Exercise SOM in all modes and small/medium/large streaming horizons. Include a stream
  longer than the small horizon to assert `past_horizon` without requiring a huge file.
- Exercise end-anchored and word-boundary patterns that produce callbacks only when a
  stream closes.
- Exercise edit and Hamming distance separately plus min/max offsets and minimum length;
  assert semantic event sets rather than compiled database sizes.
- Exercise literal metacharacters, duplicates, empty-literal rejection, 8,192-byte
  boundary, embedded NUL from a file, and a literal split across stream/vector chunks.
- Exercise argv expressions and LF/CRLF expression files, empty records, leading/trailing
  spaces, tabs, non-ASCII bytes, regex metacharacters, optional final delimiters, and
  relative file paths from an external cwd.
- Exercise stdin, `--input -`, named binary files, `--text ''`, an empty file, NUL and all
  byte classes, exactly 256 MiB in a sparse/generated fixture where practical, and one
  byte over the limit without committing large fixtures.
- Under `--utf8`, exercise ASCII and multibyte code points, UCP classes, matches split at
  UTF-8 byte boundaries, and byte-based offsets. Without `--utf8`, prove arbitrary bytes
  pass through unchanged.
- Assert JSON field order, numeric/null types, one LF per event, callback order
  preservation, no prose, empty success stderr, all-or-nothing buffered writes, and quiet
  EPIPE. Compare NUL/control cases at the byte level.
- For `info`, assert exact metadata fields and nullability, positive sizes, stream size
  only in stream mode, consistent pattern count/mode/kind, and non-exact size assertions.

### Failure and safety behavior

- Reject unknown/combined/equals-form options unless explicitly supported, missing
  values, no subcommand, no pattern source, mixed sources, `-f -`, zero patterns, too many
  patterns, per-pattern/aggregate limits, repeated scalars/booleans, and scan-only options
  on `info`; require status 2 and no stdout.
- Reject malformed, signed, negative, trailing-junk, zero where positive is required, and
  overflowing numeric values. Test every exact numeric boundary.
- Reject UCP without UTF-8, SOM with single-match/prefilter, horizon outside streaming
  SOM, edit plus Hamming distance, invalid extended bounds, and every forbidden literal
  option before compilation.
- Assert malformed/unsupported regexes and zero-length/invalid literals report status 2,
  one-based pattern ID, upstream reason, no raw pattern bytes, and no stdout.
- With `--utf8`, reject malformed pattern-file and subject sequences before compilation
  or scanning. Include overlong encodings, surrogates, truncation, and code points above
  U+10FFFF. Without the flag, feed the same subject bytes successfully.
- Reject missing/unreadable files, directories, short reads, subject over 256 MiB,
  allocation injection, and read failures with status 1 and no stdout.
- Generate exactly the match limit and then one event beyond it. The boundary succeeds;
  overflow terminates through the callback, still closes a stream if applicable, frees
  all objects, discards buffered events, and exits 1 with no stdout.
- Inject each Hyperscan allocation/runtime error reachable through project test seams and
  require complete cleanup. Do not fabricate library results or catch process-level
  corruption as normal errors.
- On Apple Silicon, test missing Rosetta and successful explicit x86 execution. On native
  x86 without SSSE3 (or a controlled platform-test seam), require `hs_valid_platform`
  failure before subject read. Reject Arm Linux, Windows, and unsupported architectures
  before dependency download.
- Corrupt locked recipe/source/package state in disposable local homes and require Conan
  or the source hash to fail closed. Prove the launcher never resolves a fake `hyperscan`
  earlier on `PATH`.

## Acceptance Criteria

- The project builds immutable Intel Hyperscan tag `v5.4.2.1`/commit `809f09b611e8` from
  the verified archive while clearly distinguishing its upstream-reported version 5.4.2.
- Conan 2.31.2 is run through `uvx`, its home is checkout-local, the complete recipe graph
  is locked, and the local recipe pins Boost headers, static OpenSSL Crypto, and Ragel.
- Conan is used because this library has a material native dependency graph; the plan
  does not consume Conan Center's older Hyperscan binary or convert unrelated native
  libraries to Conan.
- The gated, dedicated Hyperscan build leaves the default `build/native` RegexTrie/TRE
  Debug workflow usable without Conan, C++, OpenSSL, or Hyperscan's x86-only package.
- The package and CLI target only x86_64/Core2+SSSE3 Linux/macOS, with explicit Rosetta 2
  execution on Apple Silicon and early rejection elsewhere.
- `bin/hyperscan` invokes only the fixed project build and exposes exact `scan` and `info`
  contracts for regex/literal compilation, block/stream/vector modes, compile flags,
  SOM, extended bounds, approximate matching, and resource sizes.
- Match output is binary-safe JSON Lines containing IDs and honest byte-offset state,
  preserving callback order and representing disabled/past-horizon starts without
  inventing offsets or matched text.
- Input arbitration, byte preservation, UTF-8 validation, size/event bounds, statuses,
  diagnostics, cleanup, and EPIPE behavior are deterministic and tested.
- The normal locked build, package smoke test, project CTest suite, offline rebuild, and
  separately instrumented ASan/UBSan build pass on supported hosts.
- Documentation warns about PCRE syntax/semantic differences, unordered/all-end matches,
  SOM cost, experimental approximate matching, prefilter false positives, byte offsets,
  x86/SSSE3 requirements, and the 5.4.2-versus-5.4.2.1 version distinction.
- Regex-source rewriting, regex inference, matching-text generation, captures, logical
  combinations, exact prefilter confirmation, and database serialization remain
  explicitly unsupported rather than being emulated outside Hyperscan.

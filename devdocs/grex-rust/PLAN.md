# Plan: grex Rust CLI Exercise

## Summary

Exercise [`pemistahl/grex`](https://github.com/pemistahl/grex) through its maintained
native `grex` command. Install exact crates.io release 1.4.6 into the shared
project-local Cargo home and invoke `./.cargo-home/bin/grex` directly. Do not create
`bin/grex-rust`, copy the installed executable, or write an argument/output adapter.

The upstream CLI already exposes grex's defining operation and all material builder
settings: it infers one regex from positive literal examples, with optional character
generalization, repetition factoring, escaping, anchoring, grouping, and display
controls. Preserve its native input parsing, output, diagnostics, exit statuses, and
known panic paths rather than presenting a cleaner project-defined interface.

## Verified Upstream Facts

- The authoritative source is
  [`pemistahl/grex`](https://github.com/pemistahl/grex), an Apache-2.0 Rust 2021
  library and CLI. Development continues beyond the latest release, so pin the
  release rather than mutable `main`.
- [crates.io](https://crates.io/crates/grex) publishes `grex 1.4.6` as the current
  non-yanked release. The crate archive SHA-256 is
  `4ada730ccbcaf2eaaf9d254661960b0211e042e031e307ba8fd39821307f46dd`.
- Tag `v1.4.6` resolves through its annotated tag to immutable commit
  [`db9275ace11ad455700656c6186e0d69f6107870`](https://github.com/pemistahl/grex/commit/db9275ace11ad455700656c6186e0d69f6107870),
  dated November 14, 2025. The published crate's `.cargo_vcs_info.json` records the
  same commit.
- The crate archive includes `Cargo.lock`, and its default `cli` feature enables the
  Clap-backed `grex` binary. Use exact `--version '=1.4.6'` plus `--locked` so both
  the direct package and the release's transitive graph are fixed.
- The package does not declare `rust-version`. Its README says the CLI requires Rust
  1.70 or newer, but this project must use the already selected exact Rust 1.87.0
  toolchain, on which the locked release was directly verified.
- The command's only inference input is a nonempty collection of literal positive
  examples. Samples are not regex fragments, and no negative-example API is exposed.
  Grex sorts the samples internally before constructing and minimizing a DFA.
- Default output is an anchored, case-sensitive expression intended to match exactly
  the supplied language. Duplicate samples do not add language members, input order
  does not control output order, and one empty sample is valid and renders `^$`.
- Grex finds common prefixes and suffixes, forms character classes and alternations,
  makes suffixes optional, and can convert repeated non-overlapping substrings to
  quantifiers. These are construction-time inference optimizations; the tool cannot
  accept and optimize an existing regex.
- `--digits`, `--spaces`, `--words`, and their negated variants generalize Unicode
  characters to `\d`, `\s`, `\w`, `\D`, `\S`, and `\W`. Generalization can make the
  result match strings that were not supplied, and combinations follow the precedence
  documented in native help.
- `--repetitions` enables quantifier conversion. `--min-repetitions` and
  `--min-substring-length` accept positive `u32` values and default to 1. The minimum
  options are accepted without `--repetitions` but then have no visible effect.
- `--escape` renders non-ASCII characters as Rust-style Unicode escapes.
  `--with-surrogates` requires `--escape` and emits UTF-16 surrogate code units for
  astral characters; that mode is for JavaScript compatibility and is not valid
  Unicode-scalar syntax for Rust's regex parser.
- Matching is case-sensitive, uses noncapturing groups, and includes both anchors by
  default. `--ignore-case`, `--capture-groups`, `--no-start-anchor`,
  `--no-end-anchor`, and `--no-anchors` change those settings. The anchor-removal
  options can be combined redundantly without error.
- `--verbose` emits a multiline expression beginning with `(?x)`. `--colorize`
  inserts ANSI styling even when stdout is redirected, so machine consumers and
  golden tests must omit that flag.
- Release 1.4.6 advertises Unicode 16.0 support and correct treatment of extended
  grapheme clusters. Ordinary output is compatible with the Rust `regex` crate used
  by the release; consumers of another engine must still verify its dialect.
- The native parser accepts argv examples, `--file FILE`, a sole positional `-` for
  piped examples, and `--file -` for a filename read from stdin. The last form does
  not read examples from stdin: it trims the entire stream and treats it as a path.
- File and piped-example modes split LF or CRLF records, preserve interior empty
  records, and do not invent an empty record after a final delimiter. A zero-byte
  source produces zero samples and reaches the builder's nonempty-input panic; a
  source containing one LF produces one empty sample and succeeds with `^$`.
- File input reports missing, permission, and invalid-UTF-8 failures as native exit 1
  diagnostics. Piped input calls `unwrap()` on each decoded line, so invalid UTF-8
  panics instead of taking the file-error path. NUL can enter through a file or pipe
  and may be written literally in the generated regex; argv cannot contain NUL.
- The positional argument is greedy and permits hyphen values. Options must therefore
  precede the first positional example. After the first example, option-looking tokens
  such as `--file` are literal samples; an unrecognized leading token such as
  `--bogus` is also accepted as a sample instead of rejected as an unknown option.
- With piped stdin, a sole positional `-` selects stdin; with a terminal it is a
  literal sample. When `-` appears alongside another positional sample, it is literal.
- Success writes the generated expression and one final LF to stdout and nothing to
  stderr. Help and version also use stdout and exit 0. Clap usage failures exit 2,
  handled file failures exit 1, and builder/input or broken-pipe panics use Rust's
  native panic diagnostic and normally exit 101. Do not normalize any of these.
- The library and CLI infer regex source. They do not generate matching text, execute
  a matching/search operation, optimize an existing regex, or expose DFA/state data.

A local feasibility check installed the exact registry release with
`cargo +1.87.0 install --locked` into a temporary Cargo home and ran the resulting
native binary on macOS arm64. Direct probes covered argv, file and stdin input,
LF/CRLF records, empty records and empty sources, duplicates, Unicode, NUL,
representative generation options, ANSI output, option-position behavior, and native
failure statuses; the upstream suite covers every option family.
At tag `v1.4.6`, `cargo check`, the CLI build, rustfmt, and CLI-target clippy with
warnings denied passed on Rust 1.87. All 682 nextest tests and all 11 doctests passed.
Upstream's all-target clippy is not clean because its pinned tests trigger current
Clippy lints and a deprecated `assert_cmd` API; that is not a project acceptance gate.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Supported directly by the native CLI: infer one regex from nonempty positive literal examples. |
| Regex inference from samples | Supported for positive samples, including one empty string; negative examples are unsupported. |
| Construction-time optimization | Supported through DFA minimization, factoring, character classes, optionality, and optional repetition conversion. |
| Existing-regex optimization | Unsupported; the CLI never accepts regex source as input. |
| Character generalization | Supported through the six Unicode shorthand-class flags. |
| Matching/search | Unsupported by the CLI and public builder; tests may compile ordinary output only to validate inference semantics. |
| Matching-text generation | Unsupported; do not emulate it. |
| Internal automaton inspection | Unsupported; DFA states and transformations are not CLI output. |

## Files and Dependency Setup

### Shared Rust infrastructure

Reuse the root `rust-toolchain.toml`, `Cargo.toml`, `Cargo.lock`, `.cargo-home/`, and
`/target/` ignore rules established by `devdocs/regextrie-rust/PLAN.md`. Keep toolchain
`1.87.0`; the grex CLI was verified on it and does not justify a second toolchain.

Do not add `grex` to root `[dependencies]`: Cargo does not expose dependency binary
targets, so that declaration would not make the native command runnable. The direct
tool installation has its own exact registry version and uses the published crate's
lock. Extend the root package only with the engine used by integration tests:

```toml
[dev-dependencies]
regex = "=1.12.2"
```

Commit the updated root `Cargo.lock`. This test dependency is the same regex version
locked by grex 1.4.6 and is used only to assert that ordinary generated expressions
match positive examples and reject selected negatives. It must not generate or alter
the CLI's output. Do not use it for `--with-surrogates` or colorized output.

The earlier Rust plan adds this ignored path if it is absent:

```gitignore
/.cargo-home/
```

Setting `CARGO_HOME` to that directory keeps the registry index, crate archives,
sources, install metadata, and `bin/grex` inside the checkout. The rustup-managed
compiler itself may remain in the user's normal rustup home, matching the shared Rust
toolchain decision.

### Project-local installer

Add `tools/install-grex-rust`, an executable POSIX shell setup helper. It installs the
native tool but never proxies grex arguments. The helper must:

1. Resolve the repository root from its own location, change to it, and use absolute
   paths thereafter so it can be called from any working directory.
2. Require `rustup` and `cargo`, verify that toolchain `1.87.0` is installed, and fail
   with the exact
   `rustup toolchain install 1.87.0 --profile minimal --component rustfmt --component clippy`
   remedy before mutating `.cargo-home/` when it is unavailable.
3. Set `CARGO_HOME="$repo_root/.cargo-home"` for every Cargo operation. Do not inspect,
   install to, or fall through to the user's normal Cargo home or a global `grex`.
4. Treat an existing installation as valid only when Cargo install metadata lists
   `grex v1.4.6` with executable `grex` and `bin/grex --version` prints exactly
   `grex 1.4.6`. A valid cached install exits successfully without network access.
5. Otherwise run exactly:

   ```sh
   CARGO_HOME="$repo_root/.cargo-home" \
     cargo +1.87.0 install --locked --version '=1.4.6' grex
   ```

   Do not use `--force`, a Git checkout, a moving version requirement, prebuilt
   release assets, Homebrew, or another system package manager.
6. Verify the install metadata and version again after Cargo succeeds. On failure,
   return Cargo's nonzero status and never claim the command is ready.

Cargo validates the registry archive against its index checksum and uses the lockfile
inside that archive for transitive versions. Record the archive checksum in project
documentation and verify the cached archive independently in acceptance tests; the
installer does not reimplement Cargo's registry downloader.

The direct exercise command is always:

```sh
./tools/install-grex-rust
./.cargo-home/bin/grex [UPSTREAM OPTIONS]
```

Do not add `.cargo-home/bin` to `PATH`. Using the explicit path proves that the
project-local release is exercised and avoids accidentally selecting a global tool.
Paths passed to grex remain relative to the caller's current working directory.

### Tests and documentation

- `tools/install-grex-rust`: exact, idempotent project-local Cargo installer.
- `tests/grex_rust_cli.rs`: end-to-end subprocess tests of the installed upstream CLI;
  use only `std` plus the exact `regex` dev dependency.
- `Cargo.toml` and `Cargo.lock`: add and lock only the semantic-test dependency.
- `.gitignore`: reuse or add `/.cargo-home/`; do not ignore another grex-specific
  installation tree.
- `README.md`: document Rust setup, installer, direct command path, all native options,
  record behavior, output dialect, native quirks, examples, and unsupported operations.

Tests must locate the executable as
`$CARGO_MANIFEST_DIR/.cargo-home/bin/grex`. If it is absent or has the wrong version,
fail with `run ./tools/install-grex-rust`; never search `PATH` or install during a test.

## Native CLI Contract

This project defines no new grex interface. Document and test release 1.4.6 under its
full project-local path:

```text
Usage:
  ./.cargo-home/bin/grex [OPTIONS] {INPUT...|--file FILE}

Input:
  INPUT...                       One or more literal positive examples
  -f, --file FILE                Read LF/CRLF-delimited examples from FILE

Character generalization:
  -d, --digits                   Convert Unicode decimal digits to \d
  -D, --non-digits               Convert Unicode non-digits to \D
  -s, --spaces                   Convert Unicode whitespace to \s
  -S, --non-spaces               Convert Unicode non-whitespace to \S
  -w, --words                    Convert Unicode word characters to \w
  -W, --non-words                Convert Unicode non-word characters to \W

Escaping and repetition:
  -e, --escape                   Escape non-ASCII characters
      --with-surrogates          Use surrogate pairs; requires --escape
  -r, --repetitions              Convert repeated substrings to quantifiers
      --min-repetitions N        Positive u32; default 1
      --min-substring-length N   Positive u32; default 1

Anchors and display:
      --no-start-anchor          Omit ^
      --no-end-anchor            Omit $
      --no-anchors               Omit both anchors
  -x, --verbose                  Emit multiline (?x) output
  -c, --colorize                 Add ANSI syntax highlighting

Other:
  -i, --ignore-case              Emit case-insensitive output
  -g, --capture-groups           Use capturing groups where groups are needed
  -h, --help                     Print native help
  -v, --version                  Print native version
```

Clap accepts combined short flags where their options take no values. All recognized
options must appear before the first positional sample. Use `--` before a sample that
spells a known option when needed; do not treat acceptance of unknown option-looking
samples as option validation.

### Input records

- Each positional operand is one complete literal sample. Shell quoting preserves
  spaces, tabs, LF, empty strings, Unicode, and regex metacharacters; the operating
  system forbids NUL in argv.
- `-f FILE` is mutually exclusive with parsed positional input. A relative `FILE` is
  resolved from grex's caller cwd, not the repository or installer location.
- A sole positional `-` reads example records from non-terminal stdin. Feed it LF or
  CRLF records; an optional final delimiter does not add another sample.
- `--file -` reads a path from non-terminal stdin after trimming leading and trailing
  whitespace, then reads examples from that file. Reserve it for characterizing the
  upstream feature; use positional `-` for ordinary piped examples.
- Zero records are not valid even though Clap has already accepted `-` or a file.
  One explicitly empty record is valid. Preserve duplicate records and let grex's
  internal sorting/DFA construction collapse their semantic effect.
- Inputs are literal text. Regex metacharacters such as `.`, `*`, `[`, and `\` must
  be escaped by grex in its result rather than interpreted as sample syntax.

### Generation options

- Apply generalization only when deliberately broadening the inferred language.
  Combined shorthand flags use grex's documented precedence; tests must assert the
  language produced by representative combinations rather than assuming each flag
  transforms an independent pass.
- `--min-repetitions` and `--min-substring-length` affect output only with
  `--repetitions`. Values 0, negative spellings, non-integers, and values above `u32`
  are native Clap failures.
- `--with-surrogates` without `--escape` is a usage failure. Surrogate output is
  returned verbatim and must not be passed to the Rust semantic-test engine.
- `--ignore-case` emits `(?i)`. `--verbose` emits `(?x)` and expands the source over
  multiple lines. `--capture-groups` changes only groups the inferred structure needs.
- Avoid `--colorize` whenever the output will be stored, compared, piped into a regex
  engine, or parsed. The ANSI bytes are presentation, not regex syntax.

### Output, diagnostics, and statuses

- Successful inference writes only regex source plus one terminating LF to stdout.
  Default, generalized, repetition, escaped, and anchor-modified output is usually a
  single line; verbose output is multiline. A literal NUL sample can produce NUL in
  stdout, so byte-sensitive tests must not assume C-string output.
- Native help and version go to stdout and exit 0. Help wrapping may depend on terminal
  width, so assert stable headings and option spellings instead of its entire layout.
- Native Clap diagnostics go to stderr and exit 2. Handled file I/O diagnostics go to
  stderr and exit 1. Both leave stdout empty.
- Empty file/pipe input and invalid UTF-8 from piped lines can panic, emitting Rust's
  native panic text to stderr and normally exiting 101. Do not assert source paths or
  backtrace formatting.
- The CLI uses `println!` without special broken-pipe handling. Preserve its native
  nonzero panic behavior if a downstream reader closes early; do not add a wrapper
  solely to convert EPIPE to success.
- There is no JSON mode, diagnostic prefix, quiet mode, match mode, output file, or
  stable project-defined error schema.

## Representative Invocations

Default positive-sample inference:

```console
$ ./.cargo-home/bin/grex a aa aaa
^a(?:aa?)?$
```

Unicode digit generalization from stdin; options precede positional `-`:

```console
$ printf '123\n٤٥٦\n' | ./.cargo-home/bin/grex --digits -
^\d\d\d$
```

Repetition factoring from a file:

```console
$ printf 'aa\nbcbc\ndefdefdef\n' > cases.txt
$ ./.cargo-home/bin/grex --repetitions --file cases.txt
^(?:a{2}|(?:bc){2}|(?:def){3})$
```

Non-ASCII escaping with JavaScript surrogate output:

```console
$ ./.cargo-home/bin/grex --escape --with-surrogates '💩'
^\u{d83d}\u{dca9}$
```

Anchor removal for embedding:

```console
$ ./.cargo-home/bin/grex --no-anchors a aa aaa
a(?:aa?)?
```

These exact examples characterize pinned 1.4.6. Broader inference tests should compile
ordinary output and assert positive/negative language semantics rather than depend on
incidental alternation spelling.

## Implementation Milestones

1. Reconcile the shared Rust setup: retain toolchain 1.87.0 and `.cargo-home/`, add
   exact `regex 1.12.2` as a dev dependency, update the root lock, and prove the root
   package still checks under the existing regextrie plan.
2. Add `tools/install-grex-rust`; perform a clean project-local exact locked install,
   verify registry checksum/version metadata, and prove an offline cached rerun.
3. Document the complete native interface and add direct subprocess tests for argv,
   file, stdin, generation settings, raw/ANSI output, and native status behavior.
4. Add semantic tests that compile non-surrogate, non-colorized output with the exact
   Rust regex dev dependency and validate positive and selected negative examples.
5. Add shared README usage and run the full root Cargo gates plus the pinned upstream
   release checks without modifying or vendoring upstream source.

## Test Plan

### Dependency and project gates

From a clean checkout with Rust 1.87.0 already installed:

```sh
./tools/install-grex-rust
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 install --list
./.cargo-home/bin/grex --version
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 check --locked --all-targets
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 build --locked
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 nextest run --locked
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 fmt --check
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 clippy --locked --all-targets -- -D warnings
```

Assert install metadata lists only `grex v1.4.6` for this tool, version output is exact,
the cached `grex-1.4.6.crate` SHA-256 matches the recorded digest, and all registry
cache/install paths are beneath `.cargo-home`. The root lock must remain unchanged
during locked gates. Run the installer again with network unavailable and require a
quiet cached success before invoking the binary from a cwd outside the repository by
its absolute project-local path.

In a separate checkout of upstream commit `db9275ace11...`, run:

```sh
cargo +1.87.0 check --locked
cargo +1.87.0 build --locked --bin grex
cargo +1.87.0 nextest run --locked
cargo +1.87.0 test --locked --doc
cargo +1.87.0 fmt --check
cargo +1.87.0 clippy --locked --bin grex -- -D warnings
```

Expect 682 passing nextest cases and 11 passing doctests. Do not make upstream
`clippy --all-targets -D warnings` a gate for this release: its test sources have
known current-lint failures while the CLI target is clean.

### Successful native behavior

- Assert `-h`/`--help` and `-v`/`--version` use stdout, exit 0, and expose every
  documented native spelling. Verify representative combined short flags.
- Run inference through multiple argv operands, `--file` with LF/CRLF and optional
  final delimiters, positional `-` with piped records, and `--file -` with a piped
  filename. Run file tests from an external cwd to prove path resolution.
- Distinguish zero records from one empty record. Cover interior empty records,
  duplicates, reordered examples, leading-hyphen literals, spaces, tabs, embedded LF
  in argv, Unicode grapheme clusters, regex metacharacters, and NUL through stdin.
- Semantically validate default output against every supplied positive and selected
  nearby negative samples with `regex 1.12.2`. Confirm duplicates and reordered inputs
  do not change the accepted language.
- Exercise each shorthand family and representative precedence combinations. Assert
  positive examples still match and intentional generalization adds selected matches.
- Exercise repetition conversion and both positive thresholds, including that the
  thresholds have no effect without `--repetitions`.
- Exercise case-insensitive, capture-group, three anchor-removal, verbose, escape, and
  surrogate modes. Compile only dialect-compatible output; compare surrogate spelling
  directly and assert verbose semantics as well as layout markers.
- Assert `--colorize` emits ANSI bytes even with captured stdout, ordinary success has
  empty stderr, output has exactly one final LF, and NUL behavior is byte-exact.
- Characterize option parsing: recognized options work before the first sample;
  option-looking tokens after it and unknown leading hyphen tokens become literals.

### Failure and native-limitation behavior

- Assert no arguments, missing `--file` value, `--with-surrogates` without `--escape`,
  zero/noninteger/out-of-range repetition values, and parsed file/input conflicts use
  native Clap stderr and status 2 with empty stdout.
- Assert nonexistent, unreadable, and invalid-UTF-8 files use native stderr and status
  1. Do not require a project prefix not emitted by upstream.
- Assert zero-byte file and stdin sources panic nonzero, while one LF succeeds as one
  empty sample. Characterize invalid UTF-8 stdin as a panic without golden-testing a
  backtrace or registry source path.
- Close a pipe before a sufficiently large result is written and assert only native
  nonzero broken-pipe behavior; do not demand a quiet diagnostic or exact panic text.
- Hide, corrupt, or replace the local installed binary in a disposable checkout and
  confirm tests fail with the installer remedy rather than selecting `grex` from
  `PATH`. Verify missing Rust 1.87 fails installer preflight before Cargo-home changes.

## Acceptance Criteria

- `tools/install-grex-rust` reproducibly installs crates.io `grex 1.4.6` with its
  published lock into `.cargo-home/bin/grex` using Rust 1.87.0.
- The archive checksum, source commit, native version, install metadata, and offline
  cached behavior are verified.
- No grex wrapper, copied binary, vendored source, global package, nested Cargo
  workspace, or redundant root `grex` dependency is added.
- The direct upstream CLI is documented and tested for every native option family,
  argv/file/stdin input, output modes, and native exit behavior.
- Tests preserve and explain greedy hyphen parsing, filename-from-stdin behavior,
  empty-source panics, unconditional ANSI output, and other verified 1.4.6 quirks.
- Ordinary generated regexes are checked semantically against positive and negative
  examples without rewriting output or adding a matching operation to the CLI.
- Unsupported existing-regex optimization, negative-example inference, matching-text
  generation, matching/search, and automaton inspection remain explicitly absent.
- The full shared Rust package remains locked, formatted, clippy-clean, and passing
  under `cargo nextest run` after the grex exercise tests are added.

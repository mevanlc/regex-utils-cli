# Plan: regextrie Rust CLI Exercise

## Summary

Add `bin/regextrie-rust`, a project-local launcher for a custom Rust CLI that
exercises [`axelberardino/regextrie`](https://github.com/axelberardino/regextrie).
Pin published crate `regextrie 0.1.0` in the shared root Cargo package and expose two
subcommands: `matches` calls `RegexTrie::find_matches()` for every candidate, while
`best` calls `RegexTrie::find_best_match()` with the library default or one of three
fixed custom scoring functions.

Upstream publishes a binary named `regextrie`, but it is a hard-coded demonstration:
it parses no arguments and always runs embedded examples. Do not install or reuse it
as the project CLI. The custom command must stay at the public library boundary and
preserve the crate's returned-span full-match check, prefix-indexing limitations,
duplicate behavior, and nondeterministic best-match ties.

## Verified Upstream Facts

- The authoritative source is
  [`axelberardino/regextrie`](https://github.com/axelberardino/regextrie), an
  MIT-licensed Rust 2024 project. Its latest release and source commit at planning
  time are from July 2025.
- [crates.io](https://crates.io/crates/regextrie) publishes one non-yanked release,
  `regextrie 0.1.0`, with crate SHA-256
  `0280b7b3765e575c11dc8b100e9fd896b8d733e77d85c8fce85acf0be9c79b34`.
  Pin it as an exact registry dependency and let the root `Cargo.lock` pin its full
  transitive graph.
- Tag `v0.1.0` resolves to immutable commit
  [`faa49d60f074e5e7e5ea11129554bbbbebaf362f`](https://github.com/axelberardino/regextrie/commit/faa49d60f074e5e7e5ea11129554bbbbebaf362f).
  The published crate's `.cargo_vcs_info.json` records the same commit.
- Upstream declares Rust edition 2024 and pins toolchain 1.87 with rustfmt and
  clippy. Use exact toolchain `1.87.0` for the shared Rust package so the wrapper is
  tested at upstream's floor rather than only on a newer local compiler.
- The crate depends on Rayon, `regex-automata`, `regex-syntax`, and `thiserror`.
  `insert_many()` compiles regex-classified patterns in parallel as dense DFA
  regexes; plain patterns are stored only in the trie.
- `RegexTrie::from(&[String])` creates a default trie and calls `insert_many()`.
  `from_with_scorer()` accepts a boxed `Fn(&str, bool) -> usize`; the lowest score
  wins. Both return `RegexTrieError` if batch regex compilation fails.
- `find_matches(input)` returns the original strings for every matching pattern.
  Regex matches are accepted only when the DFA's first returned match starts at byte
  0 and ends at `input.len()`.
- That returned-span check is not equivalent to compiling an anchored expression.
  Alternation remains leftmost-first: `(a|aaa)` is rejected for candidate `aaa`
  because the first result spans only `0..1`, while `(aaa|a)` is accepted because its
  first result spans `0..3`. Preserve this behavior rather than anchoring or retrying.
- `find_best_match(input)` applies the configured scorer to the same candidate set.
  The default gives every exact plain-string match score 0 and each regex its UTF-8
  byte length, so a plain match outranks regexes and otherwise a shorter regex wins.
- Regex candidate indices are collected in a `HashSet`. `find_matches()` therefore
  has no stable regex-result order, and `find_best_match()` retains the first
  encountered result on equal scores. The wrapper may sort `matches` output for
  deterministic serialization, but must not add a tie-breaker to `best`.
- Plain strings use a terminal boolean rather than stored pattern entries. Duplicate
  plain strings collapse to one result. Duplicate regex strings compile into
  separate indexed entries and appear more than once in `find_matches()`.
- An empty pattern is a plain terminal at the root and exactly matches an empty
  candidate. A zero-pattern trie succeeds and matches nothing.
- Prefix extraction stops at the first unescaped character in the hard-coded set
  `.?*+()[]{}`. Characters before that point form the trie index; patterns beginning
  with recognized syntax, such as `.*`, remain root candidates.
- That classifier is intentionally incomplete relative to Rust regex syntax. It does
  not recognize `^`, `$`, or `|`, so patterns containing only those operators are
  treated as literal strings and never compiled. For example, `^foo$` matches the
  literal candidate `^foo$`, not `foo`, and `foo|bar` matches only literal `foo|bar`.
- Backslash handling only treats a backslash as escaping the classifier's hard-coded
  special characters. Regex escapes such as `\b`, `\d`, `\s`, and `\w` can become
  literal trie-prefix characters, preventing otherwise valid regexes from becoming
  candidates for normal input. A direct probe confirmed `\bword\b` did not match
  `word` and `word\s+tail` did not match `word tail`.
- Escaped classifier characters do support literal matching. A pattern `\[` is
  stored on the literal `[` path and returned as `\[` when the candidate is `[`.
- Regex compilation uses `regex-automata` syntax and DFA constraints. Unsupported
  constructs such as look-around or backreferences fail; there is no PCRE engine.
  The public error transparently displays the DFA build failure, commonly beginning
  `error building NFA`.
- `insert_many()` mutates trie/index state and installs placeholder regexes before
  parallel compilation completes. A failure can leave a caller-owned existing trie
  partially mutated. Constructing through `RegexTrie::from()` discards that partial
  value on error; the CLI must use the constructors rather than incremental insert.
- The crate does not expose the selected literal prefix, compiled DFA, match spans,
  scorer value, or trie statistics. Do not derive or reconstruct them from private
  fields.
- The repository's `cmd/main.rs` binary takes no input, prints prose, catches and
  continues after individual insertion errors, and runs several fixed sample sets.
  It is a demo rather than a reusable upstream CLI.
- The crate matches an input against supplied regexes. It does not infer a regex from
  samples, optimize an existing regex, combine patterns into regex source, or
  generate matching text.

Local validation built the tagged checkout with upstream's Rust 1.87 lockfile and
passed all 16 tests under `cargo nextest`; `cargo check`, `cargo build`, rustfmt
checking, and clippy with warnings denied also succeeded (rustfmt emitted upstream
warnings for nightly-only formatting settings). A second probe built the exact
registry crate with current compatible transitive versions and confirmed returned-span
checking and alternation behavior, default scoring, empty patterns, Unicode,
duplicates, invalid compilation, escaped metacharacters, and the
prefix-classification defects above. The planned CLI support crates also compile on
Rust 1.87.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Supported: build a prefix-indexed set of plain/regex patterns and query matches whose first returned span covers the candidate. |
| All matching patterns | Supported directly through `find_matches()`, with deterministic sorting only at serialization. |
| Best matching pattern | Supported directly through `find_best_match()` and the default/custom scorer constructors. |
| Regex optimization | Unsupported; candidate indexing is an internal search optimization, not output regex rewriting. |
| Regex inference from samples | Unsupported; inputs are patterns, not positive/negative examples. |
| Matching-text generation | Unsupported; do not emulate it. |
| Match spans/captures | Unsupported by the public API; do not run a second regex engine to invent them. |

## Files and Dependency Setup

### Shared Rust package

Create the root Cargo package shared by this and the later native grex plan:

```toml
[package]
name = "regex-utils-cli"
version = "0.0.0"
edition = "2024"
rust-version = "1.87"
publish = false

[[bin]]
name = "regextrie-rust"
path = "src/bin/regextrie_rust.rs"

[dependencies]
clap = { version = "=4.6.6", features = ["derive"] }
regextrie = "=0.1.0"
serde = { version = "=1.0.229", features = ["derive"] }
serde_json = "=1.0.151"
```

Use exact direct versions and commit the generated root `Cargo.lock`; registry
checksums in the lock are the dependency integrity record. Later Rust plans must
extend this package and lock rather than create a nested workspace or replace these
versions without a combined compatibility review.

Add root `rust-toolchain.toml`:

```toml
[toolchain]
channel = "1.87.0"
profile = "minimal"
components = ["rustfmt", "clippy"]
```

The implementation requires a rustup-managed Cargo installation so `+1.87.0`
selects the exact toolchain. Cargo itself may be installed outside the project, but
crate registry/index/source data must remain project-local. Add this to `.gitignore`
beside the existing `/target/` entry:

```gitignore
/.cargo-home/
```

Generate and prepare the package from the repository root:

```sh
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 generate-lockfile
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 fetch --locked
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 check --locked --bin regextrie-rust
```

Confirm `Cargo.lock` resolves `regextrie 0.1.0` with the crates.io checksum above.
Do not add the upstream Git repository, path dependency, demo binary, benchmark
dependencies, or upstream development dependencies to the root package.

To update later, choose a reviewed non-yanked registry version, revise the exact
manifest requirement and toolchain only if its MSRV demands it, then run:

```sh
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 update -p regextrie --precise VERSION
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 check --locked --bin regextrie-rust
```

Review the crate source diff, behavior probes, and lockfile diff together. Do not run
an unconstrained full-lock update.

### Implementation and documentation files

- `Cargo.toml`, `Cargo.lock`, and `rust-toolchain.toml`: shared root Rust package,
  exact dependency graph, and toolchain.
- `src/bin/regextrie_rust.rs`: custom Rust CLI and unit-testable parsing/execution
  helpers; keep I/O and `RegexTrie` calls separated.
- `bin/regextrie-rust`: executable POSIX launcher for the Cargo binary.
- `tests/regextrie_rust_cli.rs`: subprocess tests of the compiled binary and launcher.
- `.gitignore`: add only the project-local Cargo home; retain `/target/`.
- `README.md`: add bootstrap, command syntax, record rules, output schemas, scoring,
  registry provenance, and upstream limitations.

The launcher must resolve the repository root from its own location, require `cargo`
on `PATH`, set `CARGO_HOME` to `<root>/.cargo-home`, set `CARGO_TARGET_DIR` to
`<root>/target`, and execute:

```sh
cargo +1.87.0 run --quiet --locked --manifest-path <root>/Cargo.toml \
  --bin regextrie-rust -- "$@"
```

Do not change the caller's working directory, so relative `--input` and
`--candidate-input` paths keep normal CLI semantics. Preserve Cargo/build failures
on stderr and return Cargo's status. The launcher adds no application options,
output, retry, dependency update, or fallback toolchain.

## CLI Contract

```text
Usage:
  regextrie-rust matches [OPTIONS] [PATTERN...]
  regextrie-rust best [OPTIONS] [PATTERN...]

Pattern input:
  PATTERN...                         Regex/plain patterns as separate arguments
  -i, --input FILE                  Read LF/CRLF-delimited patterns; use - for stdin

Candidate input:
  -c, --candidate TEXT              Candidate string; repeatable
  -C, --candidate-input FILE        Read LF/CRLF-delimited candidates; use - for stdin

Best-match scoring:
  -s, --scorer MODE                 library-default, shortest, longest, or input-order
                                     (default: library-default)

General options:
  -h, --help                        Print help and exit
  -V, --version                     Print CLI and dependency versions
```

Require exactly one subcommand. `--scorer` is valid only on `best`; reject it on
`matches`. Reject unknown modes/options, repeated singleton options, candidate
options without a subcommand, and all mixed sources. A positional pattern beginning
with `-` must follow `--`; use `--candidate=-value` for an option value beginning
with `-`.

`--version` is top-level and accepts no subcommand or operands. It prints:

```text
regextrie-rust 0.0.0 (regextrie 0.1.0)
```

### Pattern and candidate records

- Accept exactly one pattern source: one or more positional `PATTERN` arguments, one
  `--input FILE`, or implicit stdin when neither is present. Reject positionals mixed
  with `--input` and repeated `--input`.
- If implicit pattern stdin is attached to a terminal, report a usage error rather
  than waiting. Explicit `--input -` may wait on a terminal.
- A zero-byte pattern source supplies an empty pattern list and is successful. An
  empty record supplies one empty pattern; these cases have different matching
  behavior and must not be conflated.
- Positional patterns are complete strings. Preserve order, duplicates, empty
  values, whitespace, embedded LF, Unicode, metacharacters, and escapes. NUL cannot
  occur in argv but is permitted in file/stdin records. Do not trim, normalize,
  classify, precompile, anchor, escape, sort, or deduplicate patterns.
- Read file/stdin bytes completely and decode strict UTF-8. Split on LF; treat CR
  immediately before LF as part of the delimiter while preserving every other CR.
  One final LF/CRLF terminates the last record without adding a phantom value:
  `a\n` is `['a']`, `a\n\n` is `['a', '']`, and `\n` is `['']`.
- Both subcommands require exactly one candidate source: repeated `--candidate`
  values or one `--candidate-input FILE`. Reject mixing and repetition. Decode files
  with the same record rules and preserve candidate order and duplicates.
- A zero-byte candidate source exits 1 with
  `regextrie-rust: candidate input contains no records`. Omitting a candidate source
  is a usage error; do not infer a second stdin read.
- At most one source may select stdin. Pattern stdin must be paired with candidate
  arguments or a non-stdin file; candidate stdin requires argv or file patterns.

### Trie construction and scoring

Construct exactly one trie per invocation before processing any candidate:

- `matches` and `best --scorer library-default` call
  `RegexTrie::from(&patterns)` once.
- `best --scorer shortest` calls `RegexTrie::from_with_scorer()` with
  `Box::new(|pattern, _| pattern.len())`. Length is UTF-8 bytes, matching Rust `str`.
- `best --scorer longest` uses `usize::MAX - pattern.len()`, making a longer pattern
  receive a lower score. Do not negate through a signed conversion.
- `best --scorer input-order` builds a lookup from each distinct pattern to its first
  zero-based input position, moves it into the scorer, and returns that position;
  an impossible missing key receives `usize::MAX`. Duplicate strings share their
  first position.

Do not call `insert()` or `insert_many()` directly, compile patterns separately,
inspect private fields, or rerun construction per candidate. Custom scorers affect
only best selection; they do not change candidate matching.

Distinct equal-score regexes remain nondeterministic in library-default, shortest,
and longest modes because upstream iterates a `HashSet` and replaces the best only
for a strictly lower score. Do not sort candidates or call `find_matches()` to add a
tie-break. `input-order` is the explicit deterministic option for distinct patterns.

### `matches`

Call `find_matches(candidate)` exactly once per candidate. Sort the returned vector
lexicographically only for deterministic output; retain duplicate strings. Emit one
compact JSON object per candidate, in candidate order:

```json
{"candidate":"a123bbb","matched":true,"matches":["a.*","a123bbb","a[0-9]+b.*"]}
{"candidate":"other","matched":false,"matches":[]}
```

`matched` is `!matches.is_empty()` after sorting. JSON field order is `candidate`,
`matched`, `matches`; serialize through `serde_json` with raw Unicode and escaped
control characters. Do not emit match spans, capture groups, scores, or trie data.

### `best`

Call `find_best_match(candidate)` exactly once per candidate and emit:

```json
{"candidate":"a123bbb","matched":true,"best":"a123bbb","scorer":"library-default"}
{"candidate":"other","matched":false,"best":null,"scorer":"library-default"}
```

`matched` is whether `best` is `Some`; do not call `find_matches()` as a second
check. JSON field order is `candidate`, `matched`, `best`, `scorer`. Return the exact
upstream string and selected mode name, but not a wrapper-computed numeric score.

### Errors, diagnostics, and process behavior

- Exit 0 for successful output, help, and version; 2 for command-line usage errors;
  and 1 for unreadable input, invalid UTF-8, trie construction/regex compilation,
  JSON serialization, stdout failure, and other processing errors.
- Prefix application diagnostics with `regextrie-rust:`, write them only to stderr,
  and do not expose Rust panic/debug output. Preserve a concise nonempty upstream
  error after `failed to build trie:` without trying to identify the failed pattern.
- Build the trie and buffer all JSON Lines before the first stdout write. If any
  pattern fails compilation, emit no candidate output. Multiple parallel failures
  need not select a deterministic underlying error.
- Do not report invalid-looking patterns that upstream classified as plain strings
  as errors. In particular, preserve verified literal behavior for `^foo$` and
  `foo|bar`, and preserve candidate-index misses for `\b`/`\s` examples.
- Write stdout with `write_all`; treat `BrokenPipe` as quiet success. Other write
  failures exit 1 if possible. Cargo/launcher errors retain their native status and
  stderr before the application starts.
- The command is not a CPU, memory, DFA-size, or input-size sandbox. Rayon may use
  multiple threads during construction. Document resource risks for untrusted or
  very large pattern sets.

## Representative Invocations

```console
$ ./bin/regextrie-rust matches 'a.*' 'a[0-9]+b.*' a123bbb \
    --candidate a123bbb --candidate xa123bbb
{"candidate":"a123bbb","matched":true,"matches":["a.*","a123bbb","a[0-9]+b.*"]}
{"candidate":"xa123bbb","matched":false,"matches":[]}
```

```console
$ ./bin/regextrie-rust best 'a.*' 'a[0-9]+b.*' a123bbb --candidate a123bbb
{"candidate":"a123bbb","matched":true,"best":"a123bbb","scorer":"library-default"}
```

```console
$ printf 'a.*\na[0-9]+b.*\n' > patterns.txt
$ printf 'a123bbb\nother\n' | \
    ./bin/regextrie-rust best --input patterns.txt --candidate-input - --scorer shortest
{"candidate":"a123bbb","matched":true,"best":"a.*","scorer":"shortest"}
{"candidate":"other","matched":false,"best":null,"scorer":"shortest"}
```

The first launcher run may populate `.cargo-home/` and compile into `target/`; Cargo
progress remains quiet, while dependency/build failures remain on stderr.

## Implementation Milestones

1. Add the shared Cargo manifest, exact toolchain, lockfile, and project-local Cargo
   cache rule. Fetch and verify crate 0.1.0 and its checksum under Rust 1.87.
2. Add the Rust binary skeleton with Clap help/version, strict source arbitration,
   record decoding, common diagnostics, buffered output, and EPIPE handling.
3. Implement one-constructor trie setup and `matches`; verify full-match semantics,
   deterministic result sorting, duplicates, empty patterns, and prefix defects.
4. Implement `best` with library-default, shortest, longest, and input-order scorer
   construction; verify custom scoring and nondeterministic-tie preservation.
5. Add the `bin/regextrie-rust` Cargo launcher, unit/integration tests, and README,
   then run clean-cache, locked, formatting, lint, and dual-toolchain smoke gates.

## Test Plan

### Dependency and static gates

```sh
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 fetch --locked
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 check --locked --all-targets
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 build --locked --bin regextrie-rust
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 nextest run --locked
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 fmt --check
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 clippy --locked --all-targets -- -D warnings
./bin/regextrie-rust --version
```

Assert Cargo uses 1.87.0, the lock remains unchanged, regextrie resolves to exact
registry version/checksum, registry data lives beneath `.cargo-home`, and the binary
runs from a caller cwd outside the checkout. Repeat a smoke command with network
disabled after `fetch` to prove the locked cache is sufficient.

In a separate checkout of upstream commit `faa49d60...`, run its checked-in lock
under toolchain 1.87.0:

```sh
cargo +1.87.0 check --locked
cargo +1.87.0 build --locked
cargo +1.87.0 nextest run --locked
cargo +1.87.0 fmt --check
cargo +1.87.0 clippy --locked --all-targets -- -D warnings
```

Expect 16 passing tests. Record but do not repair upstream rustfmt warnings about
nightly-only configuration; all commands must still exit successfully.

### Successful CLI behavior

- Top-level and subcommand help are stdout-only with exit 0. Version has the exact
  documented spelling. Verify short/long option equivalence and launcher forwarding.
- Feed pattern and candidate records through argv, LF/CRLF files, explicit stdin,
  and implicit pattern stdin. Cover zero-byte versus one-empty-record sources,
  whitespace, embedded CR/LF, NUL where permitted, Unicode, duplicates, and terminal
  delimiters without normalization.
- Confirm the returned-span full-match rule: `a.*` matches `abc` but not `xabc`.
  Assert `(a|aaa)` does not match `aaa` while `(aaa|a)` does, preserving upstream's
  leftmost-first alternation result without anchoring or retrying. Cover root regexes,
  literal prefixes, character classes, disjunctions in groups, quantifiers, escaped
  classifier metacharacters, and multiple/no matches.
- Assert `matches` sorts only its returned strings, retains duplicate regex results,
  collapses duplicate plain results according to upstream, and preserves candidate
  record order and duplicates.
- Assert the default scorer prioritizes an exact plain pattern over matching regexes
  and otherwise prefers a shorter regex. Test shortest, longest, and input-order
  custom scorers against the same candidate, including multibyte pattern lengths.
- For equal-score distinct regexes, accept any upstream winner in the documented set
  and repeatedly confirm the wrapper does not impose a lexical/input-order tie-break
  except when `--scorer input-order` is selected.
- Characterize classifier defects exactly: `^foo$`, `foo$`, and `foo|bar` are plain;
  `\bword\b` and `word\s+tail` fail to become candidates for normal matching text;
  `\[` works as an escaped literal. Do not compare against another engine's ideal.
- Verify compact raw-Unicode JSON Lines, exact field order, `null`, escaping of control
  characters, one LF per object, no stderr on success, and quiet EPIPE.

### Failure and safety behavior

- Reject missing/unknown subcommands, `--scorer` on `matches`, unknown scorer values,
  mixed/repeated sources, absent candidates, zero candidate records, and multiple
  stdin consumers with usage status 2 or the documented data failure status.
- Reject unreadable paths and invalid UTF-8 with concise stderr, exit 1, and no
  stdout. Test paths relative to an external caller cwd through the launcher.
- Supply one and multiple patterns that the upstream classifier recognizes as regex
  but `regex-automata` rejects, including an unclosed class and unsupported look-around.
  Assert atomic failure without attempting to name the parallel failing record.
- Verify invalid-looking patterns classified as plain remain successful. This is a
  regression gate against wrapper-side syntax validation.
- Simulate missing Cargo, unavailable 1.87.0 toolchain, a lock mismatch, offline
  cache miss, compilation failure, and non-EPIPE stdout failure. Launcher failures
  retain Cargo status/output; application failures retain the CLI contract.
- Exercise large/deep pattern sets only at bounded test sizes; no acceptance test may
  depend on benchmark timing or consume unbounded memory/threads.

## Acceptance Criteria

- The shared Rust package pins toolchain 1.87.0, exact direct dependencies, and a
  committed Cargo lock resolving verified `regextrie 0.1.0`; registry/cache/build
  artifacts remain ignored and project-local where planned.
- `bin/regextrie-rust` launches the locked custom binary from any cwd without
  changing relative path semantics or adding behavior of its own.
- `matches` and `best` map directly to one constructor and one public query per
  candidate, with only documented serialization sorting and fixed scorers added.
- Input records, JSON schemas, statuses, diagnostics, atomic output, EPIPE handling,
  duplicate/order behavior, full-match semantics, scorer ties, and upstream prefix
  defects match this plan exactly.
- Cargo check/build/nextest/fmt/clippy, all 16 upstream tests, clean-cache/offline
  smoke checks, representative invocations, and the full CLI failure matrix pass.

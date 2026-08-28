# Plan: triegex Python CLI Exercise

## Summary

Add `bin/triegex`, a project-local Python CLI for exercising
[`ZhukovAlexander/triegex`](https://github.com/ZhukovAlexander/triegex). Pin the
unpublished 0.0.4 release commit through uv and expose three focused subcommands:
`build` renders the compact trie-structured regex, `contains` checks exact trie
membership, and `match` runs the generated expression against candidate text as
shown in upstream's documentation.

The library has no CLI and has not been updated for modern Python imports. The
wrapper must provide one narrow, temporary `collections.MutableSet` compatibility
alias while importing it on Python 3.10 or newer. It must otherwise preserve
0.0.4 behavior, including sorted output, unconditional trailing word boundaries,
unescaped regex metacharacters, the match-nothing branch, and known MutableSet
iteration/discard defects.

## Verified Upstream Facts

- The authoritative source is
  [`ZhukovAlexander/triegex`](https://github.com/ZhukovAlexander/triegex). Upstream
  identifies tag `0.0.4` as its latest release and recommends installing that tag
  from Git. Pin the tag's immutable commit
  [`85a25240b8821c2da257e6f6b784023e56a5b680`](https://github.com/ZhukovAlexander/triegex/commit/85a25240b8821c2da257e6f6b784023e56a5b680),
  dated May 2019; do not depend on the moving `master` branch or tag name.
- [PyPI's latest triegex release is 0.0.3](https://pypi.org/project/triegex/),
  published in January 2018 as a source distribution. It predates 0.0.4's
  iterative renderer and deterministic child sorting. Use the documented Git
  release rather than silently substituting the older registry artifact.
- The legacy `setup.py` uses `setuptools_scm` to derive version `0.0.4`, packages
  one pure-Python `triegex` module, declares no runtime dependencies, and provides
  no console entry point or Python-version floor. It classifies itself as alpha,
  OS-independent Python 3 software under MIT.
- Version 0.0.4 imports `collections` and defines `Triegex` as a subclass of
  `collections.MutableSet`. That alias was removed from current Python, so an
  unmodified import raises `AttributeError` on both project test versions. The
  actual base class remains available as `collections.abc.MutableSet`.
- `Triegex(*words)` creates an empty root and calls `add()` for every supplied
  word. `add()` walks Python string characters, shares prefixes, and marks the last
  node as terminal. A zero-word trie is valid, but an empty word raises
  `IndexError` because `add()` reads `word[-1]`.
- `to_regex()` performs iterative breadth-first collection followed by bottom-up
  rendering, so it does not recurse once per character. It sorts child nodes by
  Python string/code-point order and produces deterministic source independent of
  insertion order.
- Every terminal word receives `\b`. The result is therefore case-sensitive and
  unanchored at the start, but requires Python `re`'s Unicode word boundary after
  the word. `foo` matches inside `xxfoo!` but not at the start of `food`.
- A word that ends in a non-word character often cannot match itself: the generated
  `foo!\b` needs a word/non-word transition after `!`, so it does not match `foo!`
  at end of string. A one-character symbol or emoji has the same limitation.
- The renderer appends `~^(?#match nothing)` at the root. An empty trie returns
  that source exactly. A populated trie includes it as the final alternative, for
  example `(?:bar\b|foo\b|~^(?#match nothing))`.
- Words are inserted directly as regex characters; `re.escape()` is never called.
  Inputs such as `a.b` and `a*b` retain `.` and `*` operators, while `(` or `[` can
  make the generated source syntactically invalid. `build` must expose that source
  unchanged; `match` may consequently match unsupplied text or fail compilation.
- Exact membership is independent of regex semantics. `word in trie` walks the
  trie and requires a terminal node, so `foo` is contained while `food` is not.
- Adding the same multi-character word repeatedly leaves one terminal path.
  However, the MutableSet iterator's traversal visits the root twice, so terminal
  one-character root children are yielded twice and counted twice by `len()`.
  Its path bookkeeping is also keyed only by character, not node identity, and is
  not a reliable export API for arbitrary tries: iterating
  `Triegex('aba', 'cba')` yields `cba` and the erroneous `cbaba`.
- `discard()` removes a terminal leaf, but returns after its first pruning step.
  It does not clear the terminal marker when the discarded word is a prefix of a
  longer word; discarding `foo` from `{'foo', 'foobar'}` leaves `foo` contained.
  The CLI must not claim full MutableSet mutation support.
- The package has no regex optimizer for an existing pattern, matching-text
  generator, flags/configuration API, escaping mode, anchoring mode, or sample
  weights. Trie prefix factoring is construction behavior, not a general-purpose
  regex optimization pass.
- Upstream demonstrates matching by passing `to_regex()` to Python `re.findall`.
  There is no package-owned regex engine. The planned `match` command follows that
  documented composition with Python `re`, while `contains` remains the direct
  package-owned membership operation.

A local feasibility check used uv 0.12.5 to build the exact Git commit as
`triegex 0.0.4`. Its `direct_url.json` recorded both the requested and resolved
full SHA. With the temporary MutableSet alias, all nine upstream tests passed on
CPython 3.10.20 and 3.14.6. Direct probes verified deterministic rendering, empty
tries, prefix sharing, Unicode, membership, word-boundary behavior, unescaped
metacharacters, duplicate one-character iteration, broken prefix discard, and the
match-nothing sentinel.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Supported: build a sorted prefix trie from words and emit `Triegex.to_regex()` source. |
| Regex inference from samples | Supported as trie construction from supplied words, with the critical limitation that samples are embedded as regex syntax rather than escaped literals. |
| Exact trie membership | Supported directly with `candidate in trie`. |
| Matching/search | Supported through upstream's documented composition of `to_regex()` with Python `re`; it is unanchored, case-sensitive search with forced trailing word boundaries. |
| Regex optimization | Unsupported for existing regex input; prefix factoring occurs only while constructing the trie. |
| Matching-text generation | Unsupported; do not emulate it. |
| MutableSet iteration/removal | Public but defective for important cases; characterize it without exposing misleading CLI operations. |

## Files and Dependency Setup

### Shared Python infrastructure

Extend the root uv application project established by the regexfinder plan. After
this plan, the relevant manifest content is:

```toml
[project]
name = "regex-utils-cli"
version = "0.0.0"
requires-python = ">=3.10"
dependencies = [
  "regexfinder",
  "triegex",
]

[tool.uv]
package = false

[tool.uv.sources]
regexfinder = { git = "https://github.com/mevanlc/regexfinder.git", rev = "88b50c683f77c68ff232f75e111ea6650940c4b5" }
triegex = { git = "https://github.com/ZhukovAlexander/triegex.git", rev = "85a25240b8821c2da257e6f6b784023e56a5b680" }

[tool.uv.extra-build-dependencies]
triegex = [
  "setuptools==84.0.0",
  "setuptools-scm==10.2.1",
  "packaging==26.3",
  "vcs-versioning==2.3.1",
  "tomli==2.4.1; python_version < '3.11'",
  "typing-extensions==4.16.0; python_version < '3.11'",
]
```

Keep `package = false`, the Python `>=3.10` floor, and the regexfinder pin intact.
Later Python plans must extend the same manifest and `uv.lock` rather than create
another project or environment.

Add the Git dependency with:

```sh
uv add 'triegex @ git+https://github.com/ZhukovAlexander/triegex.git@85a25240b8821c2da257e6f6b784023e56a5b680'
uv lock
```

Add the exact `extra-build-dependencies` table before the final lock/sync. The
legacy source has no `pyproject.toml` and discovers `setuptools_scm` dynamically
through `setup_requires`; explicitly augmenting its isolated build environment
prevents build-tool releases from drifting. The build-only packages need not be
installed into the runtime environment. Commit the updated `pyproject.toml` and
`uv.lock`; confirm the lock records triegex 0.0.4 at the exact Git commit.

The shared clean-checkout bootstrap remains:

```sh
uv sync --frozen
```

Run the executable through uv:

```sh
uv run --frozen -- ./bin/triegex --help
```

To update later, review a specific upstream commit, revise its full `rev`, review
whether its build requirements still need augmentation, and run:

```sh
uv lock --upgrade-package triegex
uv sync --frozen
```

Do not install PyPI 0.0.3, resolve `master`, rely on tag mutability, disable build
isolation, add build tools to runtime dependencies, vendor the module, or require a
global package. The package is pure Python and has no OS/architecture restriction;
Git/network availability is required only when uv first resolves the pinned source.

### Implementation and documentation files

- `bin/triegex`: extensionless executable Python script with a Python 3 shebang;
  invoke it through `uv run --frozen`.
- `test/triegex_test.py`: end-to-end tests using `unittest`, subprocesses, and
  temporary files from the standard library.
- `pyproject.toml` and `uv.lock`: extend the shared Python files as shown.
- `README.md`: add bootstrap, command syntax, record rules, output schemas,
  examples, source pin, compatibility shim, and behavioral limitations.

Use only the standard library for argument parsing, file input, UTF-8 decoding,
JSON, package-provenance inspection, compatibility loading, and diagnostics. Do
not add a CLI framework or an alternate trie/escaping implementation.

### Dependency loading and compatibility shim

Parse help before checking the environment. Before processing or `--version`, use
`importlib.metadata` to require distribution version `0.0.4`, the expected Git URL,
and commit `85a25240b8821c2da257e6f6b784023e56a5b680` from `direct_url.json`.

Import the package with this narrowly scoped sequence:

1. Import `collections` and `MutableSet` from `collections.abc`.
2. Record whether `collections.MutableSet` already exists and its prior value.
3. Only when absent, assign the `collections.abc.MutableSet` object to that name.
4. Import `triegex`, then restore the prior state in a `finally` block: delete the
   temporary name if it was absent or restore its original value if it existed.
5. Verify callable `triegex.Triegex` and create a zero-word smoke-test instance.

Do not patch the installed file, leave the alias globally installed, catch failures
outside the import boundary, or modify any other `collections` name. On provenance,
import, or API failure, write this to stderr and exit 1:

```text
triegex: pinned triegex 0.0.4 is unavailable; run uv sync --frozen
```

`--version` performs the same check and prints:

```text
triegex 0.0.4 (ZhukovAlexander/triegex 85a25240b8821c2da257e6f6b784023e56a5b680)
```

Never fall through to a globally installed module or the PyPI 0.0.3 artifact.

## CLI Contract

```text
Usage:
  triegex build [OPTIONS] [WORD...]
  triegex contains [OPTIONS] [WORD...]
  triegex match [OPTIONS] [WORD...]

Word input:
  WORD...                          Words as separate arguments
  -i, --input FILE                Read LF/CRLF-delimited words; use - for stdin

Candidate input for contains/match:
  -c, --candidate TEXT            Candidate text; repeatable
  -C, --candidate-input FILE      Read LF/CRLF-delimited candidates; use - for stdin

Match output:
  -b, --boolean                   Report only whether each candidate has a match

General options:
  -h, --help                      Print help and exit
  -V, --version                   Print dependency version and pinned commit
```

Require exactly one subcommand. Top-level help lists all forms; subcommand help
lists only valid inputs and its output. `--version` is top-level and accepts no
subcommand or operands. Reject candidate options and `--boolean` on `build`, and
reject `--boolean` on `contains`. Reject unknown options and repeated
non-repeatable options. A positional word beginning with `-` must follow `--`; an
option value beginning with `-` must use `--candidate=-value`.

### Word input

- Accept exactly one word source: one or more positional `WORD` arguments, one
  `--input FILE`, or implicit stdin when neither is present. Reject positionals
  mixed with `--input` and reject repeated `--input`.
- If implicit stdin is attached to a terminal, exit with a usage error rather than
  waiting. `--input -` explicitly selects stdin and may wait on a terminal.
- Positional words are complete strings. Preserve their order, empty values,
  whitespace, embedded newlines, metacharacters, and duplicates. NUL cannot occur
  in argv but can occur in file/stdin records.
- Read file/stdin bytes completely and decode strict UTF-8. Split on LF; treat CR
  immediately before LF as part of the delimiter while preserving every other CR
  and character. One final LF/CRLF terminates the last record without adding a
  phantom word: `foo\n` is `['foo']`, `foo\n\n` is `['foo', '']`, and `\n` is
  `['']`. A zero-byte source is an empty word list.
- Pass the complete ordered list once as `Triegex(*words)`. Do not trim, sort,
  deduplicate, escape, validate as regex, or filter empty words in wrapper code.
  This keeps upstream sorting, duplicate handling, and empty-word failure visible.

### Candidate input

- `contains` and `match` require exactly one candidate source: one or more
  `--candidate TEXT` occurrences or one `--candidate-input FILE`. Reject mixing
  them and reject repeated `--candidate-input`.
- Decode and split candidate files with the word-record rules above. Preserve
  empty candidates, whitespace, duplicates, order, NUL, and metacharacters.
- A zero-byte candidate source exits 1 with
  `triegex: candidate input contains no records`. Omitting a candidate source is a
  usage error; never infer a second stdin read.
- At most one source may select stdin. Positional/file words may be paired with
  candidate stdin; implicit/explicit word stdin may be paired only with candidate
  arguments or a non-stdin candidate file.

### API mapping and output

Construct exactly one `Triegex(*words)` per invocation. Do not inspect `_root`,
instantiate `TriegexNode`, iterate the trie, call `len()`, call `discard()`, or
mutate it after construction.

#### `build`

Call `trie.to_regex()` exactly once and write the returned source unchanged plus
one LF. Do not compile it, remove the sentinel, add anchors/flags, escape inputs,
or rewrite groups or boundaries. For `foo`, `bar`, and `baz`, stdout is:

```text
(?:ba(?:r\b|z\b)|foo\b|~^(?#match nothing))
```

A zero-word trie is successful and writes:

```text
~^(?#match nothing)
```

If a word contains LF, the raw source contains that LF before the command's final
terminator. Document that `build` emits the exact returned pattern source as UTF-8
text, not JSON Lines.

#### `contains`

Do not call `to_regex()`. Evaluate `candidate in trie` once per candidate and
buffer one compact JSON object per input record, in order:

```json
{"candidate":"foo","contains":true}
{"candidate":"food","contains":false}
```

Serialize with `ensure_ascii=False`, compact separators, and one LF per object.
This reports exact terminal membership even when the corresponding generated
regex would be invalid or would not match the candidate because of `\b`.

#### `match`

Call `trie.to_regex()` exactly once and compile that exact source with
`re.compile()` and no flags. Use the compiled expression's `finditer()` once per
candidate. Without `--boolean`, emit one compact JSON object per candidate:

```json
{"candidate":"food foo bar!","matched":true,"matches":[{"text":"foo","start":5,"end":8,"groups":[],"groupdict":{}},{"text":"bar","start":9,"end":12,"groups":[],"groupdict":{}}]}
```

For each match, record `group(0)`, `start()`, `end()`, `groups()` as a JSON array
preserving `None`, and `groupdict()` as an object. Input metacharacters can create
capturing groups; report them without modification.

With `--boolean`, still call `finditer()` and stop after its first yielded match,
then emit only:

```json
{"candidate":"food foo bar!","matched":true}
```

Do not switch to `search()`, `findall()`, full matching, an escaped copy, or an
alternate engine. A regex compilation error is a processing failure even though
`build` and `contains` can succeed for the same words.

### Errors, diagnostics, and process behavior

- Exit 0 for successful output, help, and version; 2 for command-line usage
  errors; and 1 for dependency/provenance failure, unreadable input, invalid UTF-8,
  empty-word `IndexError`, generated-regex compilation failure, serialization
  failure, and other processing errors.
- Prefix diagnostics with `triegex:`, write them only to stderr, and do not expose
  tracebacks, partial JSON, or partial pattern output. Buffer all primary output
  before the first stdout write.
- Preserve safe, nonempty upstream/Python exception text after a concise operation
  label. Do not relabel metacharacter failures as invalid words: the library accepts
  those words and the generated regex is what failed to compile.
- Treat EPIPE as quiet success. Other stdout failures exit 1 if no primary bytes
  were written; never append diagnostics to stdout.
- The wrapper is not a CPU, memory, or regex-backtracking sandbox. Words and
  candidate text from untrusted sources can produce pathological regex behavior.

## Representative Invocations

Build sorted compact source:

```console
$ uv run --frozen -- ./bin/triegex build foo bar baz
(?:ba(?:r\b|z\b)|foo\b|~^(?#match nothing))
```

Exercise exact membership:

```console
$ uv run --frozen -- ./bin/triegex contains foo bar --candidate foo --candidate food
{"candidate":"foo","contains":true}
{"candidate":"food","contains":false}
```

Exercise matching with candidate stdin:

```console
$ printf 'food foo bar!\nnone\n' | \
    uv run --frozen -- ./bin/triegex match foo bar --candidate-input - --boolean
{"candidate":"food foo bar!","matched":true}
{"candidate":"none","matched":false}
```

## Implementation Milestones

1. **Extend and lock the uv project.** Add the exact Git source and pinned isolated
   build additions, regenerate the shared lockfile, and prove version/provenance
   plus shimmed import on Python 3.10 and the current Python release without
   disturbing regexfinder.
2. **Build common CLI plumbing.** Add subcommand dispatch, strict option parsing,
   record-preserving input, dependency loading/restoration, compact JSON, buffered
   output, help/version, and status-separated diagnostics.
3. **Implement build and membership.** Construct one trie, return exact
   `to_regex()` source for `build`, and implement ordered `candidate in trie`
   results for `contains` without iteration or wrapper-side trie logic.
4. **Implement matching.** Compile the one generated source with default Python
   `re`, expose detailed and boolean `finditer` results, and normalize compilation
   and matching failures without changing pattern semantics.
5. **Test and document.** Cover both Python endpoints, all input sources and
   subcommands, the compatibility alias lifecycle, package defects, output bytes,
   diagnostics, and a frozen clean-checkout bootstrap; update the root README.

## Test Plan

Use standard-library `unittest`, `subprocess`, `json`, and temporary-path helpers.
Spawn the absolute `bin/triegex` path inside the uv environment so tests exercise
the checkout script without shell reconstruction.

### Dependency and static checks

```sh
uv lock --check
uv sync --python 3.10 --frozen
uv run --python 3.10 --frozen -- python -m unittest test/triegex_test.py
uv sync --python 3.14 --frozen
uv run --python 3.14 --frozen -- python -m unittest test/triegex_test.py
uv run --frozen -- ./bin/triegex --version
uv tree
```

Assert the lock is unchanged, triegex resolves to version 0.0.4 at the full Git
SHA, the build uses the exact augmented tool versions, triegex adds no transitive
runtime packages, and regexfinder retains its existing source pin. If 3.14 is no
longer current when implemented, replace it with the then-current stable Python
while retaining the 3.10 floor.

Run the nine upstream tests in an isolated source checkout at the pinned commit on
both Python endpoints after installing the temporary alias in the test process.
They are a dependency characterization gate, not a substitute for CLI tests.

### Successful behavior

- Top-level and subcommand help write only stdout and exit 0 before dependency
  installation. Version checks the import/provenance and is silent on stderr.
- After every successful or failed dependency-load attempt, assert that the wrapper
  restored the original `collections.MutableSet` state. Direct import without the
  shim must still demonstrate the expected `AttributeError` on supported Python.
- `build foo bar baz` produces the exact documented source. Permute input order and
  assert identical output; test common prefixes, one word, repeated words, and a
  zero-word file whose exact result is the match-nothing sentinel.
- Feed argv, file, explicit stdin, and implicit redirected stdin word sources.
  Verify strict record preservation for spaces, CR, LF, NUL, duplicates, and
  Unicode. Compare raw output bytes, including the command's one final LF.
- `contains` preserves candidate order and duplicates and distinguishes exact
  members, prefixes, extensions, empty strings, Unicode, metacharacters, and words
  whose forced boundary prevents regex matching. Confirm it never calls or
  validates `to_regex()`.
- `match` emits correct spans, text, groups, and group dictionaries for no match,
  one match, multiple matches, and generated captures. Confirm `--boolean` changes
  only the schema and first-match consumption.
- Characterize unanchored, case-sensitive, Unicode-word-boundary behavior: `foo`
  matches `xxfoo!` but not `food`; `café` and `茶` match before spaces; `foo!` and a
  lone emoji are contained but do not match themselves at end of string.
- Characterize unescaped syntax: `a.b` also matches `axb`, `a*b` can match only its
  trailing `b`, and `build '('` succeeds with raw invalid source while `match '('
  ...` exits 1 during compilation.
- In a direct API characterization test, prove one-character terminals are yielded
  and counted twice and discarding a prefix word leaves it contained. Confirm no
  CLI implementation relies on iteration, length, or discard.
- Run every README example and parse every contains/match line as UTF-8 JSON.
  Successful normal operation must leave stderr empty.

### Failure and safety behavior

- Missing/unknown subcommands, unknown or misplaced options, mixed word/candidate
  sources, repeated non-repeatable options, unexpected operands, omitted candidates
  on a terminal, and two stdin selections exit 2 with empty stdout.
- Empty word records, unreadable files, invalid UTF-8, zero-record candidate input,
  invalid generated patterns, JSON failures, and non-EPIPE output failures exit 1
  with empty stdout and no traceback.
- In a clean copied checkout before `uv sync`, help succeeds while version and
  processing give the exact bootstrap diagnostic. Install PyPI 0.0.3 in an
  isolated probe and confirm its metadata/direct URL cannot satisfy provenance.
- Alter the source URL, resolved commit, version, `Triegex` export, or import shim
  target in isolated tests and confirm the loader fails closed and restores
  `collections` state.
- Run from outside the project directory and confirm dependency discovery and file
  paths remain correct. Inputs resembling Python code stay inert, though regex
  metacharacters intentionally retain their regex meaning.
- Bound a large word list, a very long word, and a pathological generated pattern
  with test timeouts. Assert deterministic success or a normalized upstream/Python
  failure without claiming resource isolation.
- Close stdout early and verify quiet success; simulate other write failures and
  verify status 1 without duplicated or cross-stream output.

## Acceptance Criteria

- The shared uv manifest and lock retain regexfinder and add triegex 0.0.4 at
  commit `85a25240b8821c2da257e6f6b784023e56a5b680`, with exact isolated build-tool
  augmentation and no global/runtime build-tool installation.
- `build`, `contains`, and `match` map directly to `Triegex(*words)`, `to_regex()`,
  membership, and the documented Python `re` composition; no wrapper-side trie,
  escaping, anchoring, sorting, deduplication, or optimization is introduced.
- The compatibility alias exists only during import and is restored on every path.
  Help remains available before bootstrap, while version verifies exact provenance.
- Word/candidate sources preserve records and ordering; pattern output, JSON Lines,
  stdout/stderr separation, exit statuses, and EPIPE behavior match this contract
  on Python 3.10 and the current stable Python release.
- Tests expose deterministic trie factoring and exact membership while
  characterizing empty-word failure, raw metacharacters, forced boundaries,
  match-nothing output, iterator duplication, and prefix-discard failure.
- Existing-regex optimization, safe-literal inference, matching-text generation,
  MutableSet listing/removal, alternate regex dialects, flags, and resource
  isolation remain explicitly out of scope.

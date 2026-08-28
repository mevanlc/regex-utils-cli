# Plan: retrie Python CLI Exercise

## Summary

Add `bin/retrie`, a project-local Python CLI for exercising
[`ddelange/retrie`](https://github.com/ddelange/retrie). Install the published
`retrie 0.3.1` wheel through the shared uv project and expose five focused
subcommands: `build` renders a trie-factored regex, `check` reports blacklist or
whitelist membership, `filter` exercises the corresponding sequence filter,
`cleanse` applies the library's text-cleansing operation, and `replace` performs
single-pass mapping-based substitution.

The package has no upstream command-line program. The wrapper must call its public
`Trie`, `Blacklist`, `Whitelist`, and `Replacer` APIs directly and preserve their
Python `re` semantics. In particular, keys are escaped literals, rendering is
deterministic, matching is case-insensitive with word boundaries by default, and
whitelist cleansing concatenates matched substrings without preserving separators.

## Verified Upstream Facts

- The authoritative source is
  [`ddelange/retrie`](https://github.com/ddelange/retrie), an MIT-licensed,
  pure-Python project whose default branch is `master`.
- The current upstream and
  [PyPI release](https://pypi.org/project/retrie/) is `0.3.1`, published in
  February 2024 from tag `0.3.1`. The tag resolves to immutable commit
  [`25441108266ffcb1bd08e8f64e74af09161be0d4`](https://github.com/ddelange/retrie/commit/25441108266ffcb1bd08e8f64e74af09161be0d4).
  Later `master` commits only update repository automation; its package source,
  tests, metadata, and README remain identical to that tag at planning time.
- PyPI provides a universal `py2.py3-none-any` wheel with SHA-256
  `cb67a394f93e66d3ee35592c0c65192f8c1d7f36e6a98e73306e439e97bf8d9d`
  and a source distribution. Pin the registry release as `retrie==0.3.1` and let
  `uv.lock` record artifact hashes; a Git dependency is unnecessary.
- The legacy `setup.py` declares only `cached-property` below Python 3.8 and
  `typing` below Python 3.5. Neither marker applies at this project's Python 3.10
  floor, so retrie adds no transitive runtime package on supported interpreters.
- Upstream declares support as far back as Python 2.7 and through Python 3.12. The
  project retains its shared Python `>=3.10` floor and verifies the unmodified
  wheel at both that floor and the current stable Python endpoint.
- The distribution exports version `0.3.1` but no console-script entry point. Its
  useful objects live in `retrie.trie` and `retrie.retrie`; a custom wrapper is
  required.
- `Trie(*words)` and chained `Trie.add(*words)` add literal Python strings one
  character at a time. Duplicate strings share the same terminal path. `Trie` can
  also merge trees, but merging does not add a distinct CLI capability.
- `Trie.pattern()` recursively renders a noncapturing Python-regex union. It sorts
  dictionary keys and alternatives, shares prefixes, converts sibling leaves to a
  character class, and makes suffixes optional when a word is a prefix of another.
  `Trie('abc', 'foo', 'abs').pattern()` is `(?:ab[cs]|foo)` independent of input
  order.
- Every input character passes through `re.escape()`. Metacharacters such as `.`,
  `*`, and `[` are literals in the generated regex, unlike triegex's raw-regex
  insertion behavior. The CLI must not escape a second time.
- A zero-word trie and `Trie('')` both render the empty string. Combining an empty
  key with `foo` renders `(?:foo)?`, correctly exposing the empty alternative.
  Empty keys must not be silently removed.
- Rendering recursively descends once per trie level. A sufficiently long shared
  path can raise Python `RecursionError`; a 2,000-character single key does so with
  normal CPython recursion limits. The wrapper must report the upstream failure,
  not raise recursion limits or substitute another renderer.
- `Retrie.compile()` surrounds the raw trie pattern with its configured boundary
  and calls Python `re.compile`. The default boundary is `\b`; an empty boundary
  enables substring matching. A non-`\b` custom boundary becomes fixed-width
  lookbehind and lookahead, but the planned CLI deliberately exposes only the
  documented whole-word and substring modes.
- The default flags are `re.IGNORECASE | re.UNICODE`. Passing `re_flags=None`
  produces case-sensitive behavior. Python 3 always has Unicode regex semantics;
  no separate Unicode option is needed.
- `Blacklist.is_blacklisted()` and `Whitelist.is_whitelisted()` both call the
  inherited `is_listed()`, which returns `bool(compiled.search(term))`. A candidate
  is therefore listed if any occurrence matches; this is search, not full-string
  matching.
- `Blacklist.filter(sequence)` lazily retains values for which no match is found,
  while `Whitelist.filter(sequence)` retains values for which a match is found.
  Preserve duplicates and input order when consuming either iterator.
- `Blacklist.cleanse_text(text)` calls `compiled.sub('', text)`, removing all
  matches. `Whitelist.cleanse_text(text)` calls `compiled.findall(text)` and joins
  the matches with an empty separator. For example, whole-word whitelisting of
  `abc`, `foo`, and `abs` cleanses `good ABC foobar` to `ABC`, while substring mode
  produces `ABCfoo`.
- `Replacer(mapping)` builds its trie from mapping keys and calls `compiled.sub()`
  with a lookup callback. `replace(text, count=0)` replaces all nonoverlapping
  matches in one pass; a positive count limits replacements according to Python
  `re.sub` semantics.
- In default case-insensitive mode, `Replacer` lowercases mapping keys and matched
  text before lookup. If distinct keys collide after `str.lower()`, construction
  raises `ValueError` with an ambiguous-mapping diagnostic. Case-sensitive mode
  preserves mapping keys exactly.
- Empty checklist keys expose upstream behavior rather than a conventional empty
  set: the default compiled pattern is `\b\b`, which matches word boundaries.
  Thus `Blacklist([]).is_blacklisted('abc')` is true, while it is false for `!!!`.
  An empty replacement mapping can fail with `KeyError` when the zero-width pattern
  matches; require at least one replacement pair but retain zero-key checklist tests.
- Trie construction is sample-to-regex inference for literal positive strings and
  prefix factoring is its optimization. The package does not optimize an existing
  regex, generate matching text, accept negative examples, or implement its own
  regex engine.

A local feasibility probe installed the exact PyPI wheel through uv and confirmed
distribution and runtime version `0.3.1`, no console scripts, deterministic escaped
patterns, both checklist modes, cleansing, replacement counts, Unicode, empty keys,
and the recursive-rendering limit. All six upstream tests passed against the wheel
on CPython 3.10.20 and 3.14.6.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core trie operation | Supported: construct `Trie` from literal keys and emit its deterministic factored `pattern()`. |
| Regex inference from samples | Supported for positive literal strings through trie construction; no negative samples or generalization beyond shared prefixes. |
| Regex optimization | Supported only as construction-time prefix factoring; existing regex input cannot be optimized. |
| Matching/search | Supported through `Blacklist` and `Whitelist` search-based checks and filters using their compiled Python regex. |
| Text cleansing | Supported directly through both checklist classes, preserving their different remove-versus-concatenate semantics. |
| Mapping replacement | Supported directly through `Replacer.replace()`, including substring, case, and count controls. |
| Matching-text generation | Unsupported; do not emulate it. |

## Files and Dependency Setup

### Shared Python infrastructure

Extend the root uv application project established by the earlier Python plans.
After this plan, the relevant manifest content is:

```toml
[project]
name = "regex-utils-cli"
version = "0.0.0"
requires-python = ">=3.10"
dependencies = [
  "regexfinder",
  "retrie==0.3.1",
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

Keep the existing Git pins, triegex build augmentation, `package = false`, and
Python floor intact. Add the registry dependency with:

```sh
uv add 'retrie==0.3.1'
uv lock
```

Commit the updated `pyproject.toml` and `uv.lock`. Confirm the lock chooses the
universal 0.3.1 wheel and records its registry hashes. On supported Python, the two
historical conditional requirements must not appear in the installed environment.

The shared clean-checkout bootstrap remains:

```sh
uv sync --frozen
```

Run the executable through the locked environment:

```sh
uv run --frozen -- ./bin/retrie --help
```

To update later, review a specific PyPI release and its corresponding source tag,
change the exact version, and run:

```sh
uv lock --upgrade-package retrie
uv sync --frozen
```

Review behavior and lockfile changes together. Do not install from moving `master`,
add a second uv project, vendor source, use a global package, or introduce a CLI
framework. The universal wheel is OS- and architecture-independent.

### Implementation and documentation files

- `bin/retrie`: extensionless executable Python script with a Python 3 shebang;
  invoke it through `uv run --frozen`.
- `test/retrie_test.py`: end-to-end tests using `unittest`, subprocesses, and
  temporary files from the standard library.
- `pyproject.toml` and `uv.lock`: extend the shared Python files exactly as above.
- `README.md`: document bootstrap, subcommands, record formats, output contracts,
  PyPI pin, Python floor, empty-trie behavior, and upstream limitations.

Use only the standard library for argument parsing, UTF-8 I/O, JSON, package
metadata inspection, and diagnostics. Parse help before importing the dependency.
Before processing or `--version`, use `importlib.metadata` to require distribution
version `0.3.1`, import `retrie.trie.Trie` plus `Blacklist`, `Whitelist`, and
`Replacer` from `retrie.retrie`, and verify all four are callable. On any version,
import, or API failure, write this to stderr and exit 1:

```text
retrie: pinned retrie 0.3.1 is unavailable; run uv sync --frozen
```

`--version` performs the same check and prints:

```text
retrie 0.3.1
```

## CLI Contract

```text
Usage:
  retrie build [OPTIONS] [KEY...]
  retrie check MODE [OPTIONS] [KEY...]
  retrie filter MODE [OPTIONS] [KEY...]
  retrie cleanse MODE [OPTIONS] [KEY...]
  retrie replace [OPTIONS]

Modes for check/filter/cleanse:
  blacklist                         Use Blacklist behavior
  whitelist                         Use Whitelist behavior

Key input for build/check/filter/cleanse:
  KEY...                            Keys as separate arguments
  -i, --input FILE                 Read LF/CRLF-delimited keys; use - for stdin

Candidate input for check/filter:
  -c, --candidate TEXT             Candidate text; repeatable
  -C, --candidate-input FILE       Read LF/CRLF-delimited candidates; use - for stdin

Whole-text input for cleanse/replace:
  -t, --text TEXT                  Use one complete text argument
  -T, --text-input FILE            Read one complete text; use - for stdin

Replacement input for replace:
  -r, --replacement OLD NEW        Add one replacement pair; repeatable
  -R, --replacement-input FILE     Read JSON Lines pairs; use - for stdin
  -n, --count NUMBER               Maximum replacements; 0 means all; default 0

Matching options for check/filter/cleanse/replace:
  -s, --substring                  Match inside words instead of at word boundaries
  -S, --case-sensitive             Disable the default case-insensitive matching

General options:
  -h, --help                       Print help and exit
  -V, --version                    Print dependency version
```

Require exactly one subcommand and, where shown, exactly one mode. Options are
subcommand-specific. Reject matching controls on `build`, key/candidate options on
`replace`, text/replacement/count options outside their commands, unknown modes,
unknown options, and repeated non-repeatable options. `--version` is top-level and
accepts no subcommand or operands. Put `--` before a positional key beginning with
`-`; use `--candidate=-value` or `--text=-value` for option values beginning with
`-`, and use JSON Lines for replacement pairs whose option spelling is ambiguous.

### Key and candidate records

- Accept exactly one key source: positional `KEY` arguments, one `--input FILE`, or
  implicit stdin when neither is present. Reject mixing positionals with `--input`.
  A zero-byte source is a valid zero-key trie.
- If implicit stdin is attached to a terminal, report a usage error rather than
  waiting. Explicit `--input -` may wait on a terminal.
- Positional keys are complete strings. Preserve empty values, whitespace, embedded
  newlines, NUL where the source permits it, Unicode, metacharacters, duplicates,
  and order. Do not trim, sort, deduplicate, pre-escape, or reject empty keys.
- Read file/stdin bytes completely and decode strict UTF-8. Split records on LF;
  treat CR immediately before LF as part of the delimiter while preserving every
  other CR. One final delimiter terminates the last record without adding a phantom
  value: `foo\n` is `['foo']`, `foo\n\n` is `['foo', '']`, and `\n` is `['']`.
- `check` and `filter` require exactly one candidate source: repeated
  `--candidate` values or one `--candidate-input`. Decode candidate records with
  the same rules, preserving order and duplicates. A zero-byte candidate source
  exits 1 with `retrie: candidate input contains no records`.
- At most one source may use stdin. Keys from stdin require candidates/text from
  arguments or a non-stdin file; candidate/text stdin requires keys from arguments
  or a non-stdin file.

### Whole-text and replacement input

- `cleanse` and `replace` accept exactly one whole-text source: one `--text`, one
  `--text-input`, or implicit stdin when neither is supplied. Reject mixing or
  repetition. Read a text file/stdin completely as strict UTF-8 without splitting,
  trimming, or normalizing it. A zero-byte text is a valid empty string.
- `replace` requires exactly one mapping source: one or more `--replacement OLD NEW`
  pairs or one `--replacement-input FILE`. Reject mixing and repeated files.
- A replacement file is strict UTF-8 JSON Lines. Each record must be an object with
  exactly two string fields, `old` and `new`; reject arrays, extra/missing keys,
  non-string values, blank records, and trailing non-JSON content. JSON escaping
  allows either string to contain LF, CR, NUL, and other characters. Split physical
  records with the same LF/CRLF terminal-delimiter rules as key input.
- Reject zero replacement records with
  `retrie: replacement input contains no records`. Reject an exact duplicate `old`
  before constructing a dictionary; let `Replacer` itself diagnose distinct keys
  that collide only after lowercasing in default mode.
- Parse `--count` as a base-10 non-negative integer and pass it unchanged. Reject
  signs other than an optional leading `+`, whitespace, nondecimal forms, and
  negative values as usage errors.
- At most one of key, candidate, text, and replacement sources may select stdin.
  Never infer a second read from an already consumed stream.

### API mapping and output

For case-sensitive operation pass `re_flags=None`; otherwise omit `re_flags` so the
class uses `DEFAULT_FLAGS`. Pass `match_substrings=True` only with `--substring`.
Do not access trie internals, call Python `re` in wrapper code, add anchors, change
boundaries, normalize case, or recreate any matching/replacement algorithm.

#### `build`

Construct `Trie(*keys)`, call `pattern()` exactly once, and write its returned
string followed by one LF. For `abc`, `foo`, and `abs`, stdout is:

```text
(?:ab[cs]|foo)
```

A zero-key or single-empty-key trie writes only the terminating LF. Metacharacters
remain escaped exactly as upstream returns them. Buffer the complete pattern before
writing so recursive-rendering failures produce no partial stdout.

#### `check`

Construct one `Blacklist` or `Whitelist`. For each candidate, call the mode-specific
`is_blacklisted()` or `is_whitelisted()` exactly once and emit one compact JSON
object in input order:

```json
{"candidate":"foobar","blacklisted":false}
{"candidate":"a foo bar","blacklisted":true}
```

Whitelist output uses the key `whitelisted`. Serialize with `ensure_ascii=False`,
compact separators, and one LF per object. Do not replace these calls with direct
access to `is_listed` or `compiled.search`.

#### `filter`

Construct the selected checklist and pass the entire ordered candidate list once to
its `filter()` method. Consume that iterator once and emit one compact JSON object
for every retained record:

```json
{"candidate":"good"}
{"candidate":"foobar"}
```

Blacklist retains unlisted candidates; whitelist retains listed candidates. Do not
implement inverse conditions in wrapper code. An empty result is successful and
writes zero bytes.

#### `cleanse`

Construct the selected checklist and call `cleanse_text(text)` exactly once. Write
the returned string as UTF-8 with no added newline. Blacklist mode removes matches;
whitelist mode concatenates `findall()` results exactly as upstream does. For keys
`abc`, `foo`, and `abs`, whole-word cleansing of `good ABC foobar` yields `good  foobar`
in blacklist mode and `ABC` in whitelist mode.

#### `replace`

Construct one insertion-ordered dictionary from the validated replacement records,
then one `Replacer` with the matching options. Call `replace(text, count=count)`
exactly once and write the returned text with no added newline. With whole-word,
default-case matching, mappings `abc -> new1`, `foo -> new2`, and `abs -> new3`
transform `ABS ...foo... foobar` into `new3 ...new2... foobar`.

Do not repeatedly call `str.replace`, apply mappings in input order, restore source
capitalization, or catch ambiguous lowercase keys as a wrapper-level conflict.

### Errors, diagnostics, and process behavior

- Exit 0 for successful output, help, and version; 2 for command-line usage errors;
  and 1 for dependency failure, unreadable input, invalid UTF-8 or JSON, empty or
  duplicate replacement input, recursive rendering, regex compilation, ambiguous
  case-insensitive mappings, replacement lookup, serialization, and other processing
  failures.
- Prefix diagnostics with `retrie:`, write them only to stderr, and do not expose
  tracebacks or partial output. Buffer JSON, patterns, and transformed text before
  the first stdout write.
- Preserve safe nonempty upstream exception text after a concise operation label.
  Do not relabel `ValueError` from case-folded mapping collisions as duplicate raw
  input, and do not hide empty-trie behavior in checklist modes.
- Treat EPIPE as quiet success. Other output failures exit 1 if no primary bytes
  were written; never append diagnostics to stdout.
- The wrapper is not a CPU, memory, recursion, or regex-backtracking sandbox.
  Document that untrusted or very large input can consume excessive resources.

## Representative Invocations

```console
$ uv run --frozen -- ./bin/retrie build abc foo abs
(?:ab[cs]|foo)
```

```console
$ uv run --frozen -- ./bin/retrie check blacklist foo --candidate foobar --candidate 'a foo bar'
{"candidate":"foobar","blacklisted":false}
{"candidate":"a foo bar","blacklisted":true}
```

```console
$ printf 'good\nABC\nfoobar\n' | uv run --frozen -- ./bin/retrie filter whitelist abc foo abs --candidate-input -
{"candidate":"ABC"}
```

```console
$ uv run --frozen -- ./bin/retrie cleanse blacklist abc foo abs --text 'good ABC foobar'
good  foobar
```

The displayed shell prompt follows the raw cleanse output; the command itself adds
no newline.

```console
$ uv run --frozen -- ./bin/retrie replace \
    --replacement abc new1 --replacement foo new2 --replacement abs new3 \
    --text 'ABS ...foo... foobar'
new3 ...new2... foobar
```

## Implementation Milestones

1. Extend the shared uv manifest with `retrie==0.3.1`, update the lock, sync with
   `--frozen`, and verify version, artifact resolution, imports, APIs, and absence of
   an upstream CLI on Python 3.10 and the current stable endpoint.
2. Add `bin/retrie` with top-level/subcommand help, lazy dependency validation,
   version output, common diagnostics, EPIPE handling, and exact source arbitration.
3. Implement shared strict UTF-8 record loading and `build`; verify deterministic,
   escaped, duplicate, empty, Unicode, and recursive-failure behavior.
4. Implement checklist construction plus `check`, `filter`, and `cleanse`; verify
   both modes, matching controls, direct-method mapping, JSON Lines, and raw text.
5. Implement replacement-pair parsing and `replace`; verify JSON Lines mappings,
   case collisions, substring mode, count, arbitrary replacement text, and atomic
   output.
6. Add subprocess tests and README usage, then perform the clean-checkout and
   dual-Python acceptance sequence without changing the lockfile.

## Test Plan

Use standard-library `unittest` for project tests and spawn the absolute
`bin/retrie` path inside uv's environment. Tests must set the working directory to
a temporary directory so the executable cannot rely on the checkout as cwd.

### Dependency and upstream gates

```sh
uv lock --check
uv sync --python 3.10 --frozen
uv run --python 3.10 --frozen -- python -m unittest test/retrie_test.py
uv sync --python 3.14 --frozen
uv run --python 3.14 --frozen -- python -m unittest test/retrie_test.py
uv run --frozen -- ./bin/retrie --version
uv tree
```

Assert the lock remains unchanged, resolves retrie exactly to PyPI 0.3.1 with the
expected wheel hash, and retains both earlier Git pins and triegex's exact build
augmentation. Assert retrie adds no active transitive dependency on either endpoint.
If Python 3.14 is no longer current at implementation time, replace it with the
then-current stable Python while retaining 3.10 as the floor.

In an isolated checkout of tag `0.3.1`, run the published artifact against the six
upstream tests at both endpoints:

```sh
uv run --no-project --python 3.10 --with 'retrie==0.3.1' --with pytest -- pytest -q -o addopts= tests
uv run --no-project --python 3.14 --with 'retrie==0.3.1' --with pytest -- pytest -q -o addopts= tests
```

These characterize the dependency; project subprocess tests remain authoritative
for the CLI contract.

### Successful behavior

- Help for every command writes only stdout and exits 0 without importing retrie.
  Version validates the installed distribution/APIs and writes exact version output.
- `build abc foo abs` produces `(?:ab[cs]|foo)` plus LF. Permute inputs and verify
  identical output; cover shared prefixes, metacharacters, Unicode, duplicates,
  zero keys, one empty key, and empty-plus-nonempty optional rendering.
- Exercise key records through argv, LF and CRLF files, explicit stdin, and implicit
  redirected stdin. Verify preservation of whitespace, embedded CR, NUL, Unicode,
  empty records, duplicates, and terminal-delimiter rules.
- For both checklist modes, test whole-word versus substring and default versus
  case-sensitive matching. `check` must emit the correct mode-specific boolean for
  every ordered candidate and `filter` must preserve exactly the upstream iterator's
  retained records, including duplicates.
- Characterize zero-key checklists exactly: default `\b\b` lists `abc` but not
  `!!!`; do not assert conventional empty-set semantics.
- Verify blacklist cleansing removes matches while retaining other bytes, and
  whitelist cleansing concatenates only matches. Cover multiple matches, no match,
  empty text, Unicode case matching, substring mode, NUL, and output containing LF.
- Verify replacement from repeated argv pairs and JSON Lines files. Cover default
  ignore-case lookup, case-sensitive mode, substring mode, count zero/one/many,
  replacements containing metacharacters/newlines/NUL, an empty key, and no match.
- Assert `build` appends exactly one LF, JSON commands use compact Unicode JSON
  Lines, and cleanse/replace add no bytes to the returned upstream string.

### Failure and safety behavior

- Reject missing/unknown subcommands or modes, misplaced options, mixed sources,
  repeated singleton options, absent candidates, zero candidate records, missing
  replacements, duplicate raw mapping keys, invalid counts, and multiple stdin
  consumers with exit 2 for syntax or 1 for malformed input data as classified.
- Reject unreadable files, invalid UTF-8, malformed JSON Lines, wrong mapping keys
  or value types, blank mapping records, and stdout failures with concise stderr and
  no traceback or partial stdout.
- Verify default case-insensitive `x -> one` plus `X -> two` reaches upstream
  `Replacer` and reports its ambiguous-mapping `ValueError`; the case-sensitive
  form succeeds with both mappings.
- Feed a key long enough to trigger upstream recursive rendering and assert exit 1,
  a concise operation-specific diagnostic, and empty stdout. Do not hard-code an
  exact recursion threshold.
- Run with retrie absent and with a deliberately wrong installed version; processing
  and version fail with the documented sync diagnostic while help still succeeds.
- Close the reader side of a pipe and confirm EPIPE exits quietly without traceback;
  simulate another write failure and confirm it remains a processing failure.

## Acceptance Criteria

- The shared uv manifest and lock add exactly `retrie==0.3.1` from PyPI without
  disturbing regexfinder or triegex pins, and clean frozen sync works on the Python
  floor and current stable endpoint.
- `bin/retrie` exposes only the documented commands/options, validates the installed
  dependency lazily, and runs independently of caller cwd through `uv run --frozen`.
- Every operation maps directly to one public upstream class/method and preserves
  escaped deterministic patterns, matching flags, word/substrings, filter direction,
  cleansing, replacement, empty-key quirks, and upstream failures.
- Inputs, output encodings, JSON schemas, raw-text newline behavior, diagnostics,
  exit statuses, atomic writes, and EPIPE behavior match this plan exactly.
- Dual-Python project tests, the six upstream tests, representative invocations,
  semantic edge cases, and clean-checkout validation all pass with no lock drift or
  global installation.

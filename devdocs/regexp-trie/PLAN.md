# Plan: Regexp::Trie CLI Exercise

## Summary

Add `bin/regexp-trie`, a project-local Perl command that inserts literal samples
into `Regexp::Trie` and prints the Perl regex body compiled by the trie. The
command will expose the library's focused `new`, `add`, and `regexp` flow without
adding wrapper-side sorting, suffix reduction, matching, or optimization.

Inputs are always literal strings, not regex patterns. The upstream module quotes
each character before building the regex, so a sample such as `a+b` matches the
plus sign rather than acting as a quantifier.

## Verified Upstream Facts

- Use [Regexp::Trie 0.02](https://metacpan.org/release/DANKOGAI/Regexp-Trie-0.02),
  the latest CPAN release. It was released in 2006 and requires Perl 5.8.1 or
  newer; pin this release because no newer behavior should be assumed.
- The complete public workflow is `Regexp::Trie->new`, one `add` call per literal,
  and `regexp`. The distribution exports nothing and provides no upstream CLI.
- `add` splits a Perl string into characters and stores them in a prefix trie.
  `regexp` recursively quotes characters, sorts sibling keys, folds terminal
  siblings into character classes, makes shared tails optional where applicable,
  and returns a compiled `Regexp` object.
- Because only prefixes are shared, `foobar` and `xxbar` remain
  `(?:foobar|xxbar)`; the common suffix is not factored. The module documents
  itself as faster but less configurable than `Regexp::Assemble` and
  `Regexp::Optimizer`.
- Duplicate samples share the same terminal node and do not duplicate output.
  Sibling keys are sorted at every trie node, so version 0.02's output is
  deterministic for the same decoded sample set but does not preserve insertion
  order.
- `regexp` returns a compiled regex rather than a bare pattern string. On current
  Perl, direct stringification adds an implementation wrapper such as `(?^:...)`;
  use `re::regexp_pattern` to recover the body produced by the trie.
- Empty strings are representable as trie terminals. Mixed with `foo`, an empty
  sample produces `(?:foo)?`. When every added sample is empty, version 0.02 still
  returns an empty compiled regex but emits an uninitialized-value warning from
  its `regexp` method. The CLI must contain only that verified warning case rather
  than leaking it on an otherwise successful invocation.
- The result is unanchored and has no user-selectable modifiers. Unicode input is
  handled as decoded Perl characters; the compiled object may carry Perl's `u`
  modifier, while the extracted body contains the literal Unicode characters.
- The MakeMaker distribution declares no non-core runtime dependencies. Its
  optional dictionary test requires an external word list and generated fixture,
  neither of which is included in the release.

A local feasibility check installed version 0.02 with project-local `cpanm` under
Homebrew Perl 5.44.0. The packaged test suite passed its load test and skipped its
optional dictionary test as designed. Direct API checks reproduced upstream's
`foo(?:bar|xar|zap?)` example, `a(?:\*b|\+b|\.b)` for literal metacharacters,
`caf[èé]` for decoded Unicode, `foo(?:bar)?` for a terminal with a longer branch,
and the documented empty-sample behavior above.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Build a prefix trie of literals through `add` and compile it through `regexp`. |
| Regex optimization | Prefix sharing, character classes, and optional tails are intrinsic; arbitrary regex optimization is unsupported. |
| Matching-text generation | Unsupported; do not emulate it. |
| Regex inference from samples | Supported for literal samples through trie construction. |
| Matching/search | Unsupported as a library operation; match output only in semantic tests. |

## Files and Dependency Setup

### Shared Perl infrastructure

Reuse the root `cpanfile` and project-local `local/` tree established by the other
Perl plans. Add the exact Trie pin so the completed Perl manifest is:

```perl
requires 'Regexp::Optimizer', '== 0.23';
requires 'Regexp::Assemble',  '== 0.38';
requires 'Regex::PreSuf',     '== 1.17';
requires 'Regexp::Trie',      '== 0.02';
```

If the shared manifest has not yet been implemented, create it with all four
pins. Otherwise add only the missing declaration. Keep using the root `/local/`
ignore rule and install or refresh the one shared dependency tree with:

```sh
cpanm --local-lib-contained local --installdeps .
```

Do not install globally, vendor the CPAN release, or create a separate local tree
for this command.

### Implementation files

- `bin/regexp-trie`: executable Perl CLI.
- `t/regexp-trie.t`: end-to-end subprocess tests.
- `README.md`: add setup, command usage, input rules, examples, and the library's
  prefix-only and empty-sample caveats to the shared project documentation.

Use `FindBin` to add the root `local/lib/perl5` relative to the executable so the
command works from any current directory. Use only Perl core support such as
`Getopt::Long`, `Encode`, and `re`; do not add a CLI framework.

Require exactly version 0.02. If it is absent or another version is loaded, exit 1
and write this actionable diagnostic to stderr:

```text
regexp-trie: Regexp::Trie 0.02 is not installed; run cpanm --local-lib-contained local --installdeps .
```

## CLI Contract

```text
Usage: regexp-trie [OPTIONS] [SAMPLE ...]

Build a Perl regex from literal samples using Regexp::Trie.

Input:
  SAMPLE ...                  Each positional argument is one literal sample
  -i, --input FILE            Read one sample per line; repeatable; use - for stdin

Options:
  -h, --help                  Print help and exit
  -V, --version               Print the command and module version and exit
```

No subcommand or algorithm option is needed because the module exposes one
operation and no configuration setters. In particular, do not add regex mode,
suffix factoring, anchors, modifiers, matching, case folding, or custom ordering.

### Sample collection

- Select exactly one source family: one or more positional `SAMPLE` arguments,
  one or more repeatable `--input FILE` options, or stdin when neither is given.
  Reject positional samples combined with `--input`.
- Process repeated files in option order and permit `--input -` at most once. If
  stdin is selected implicitly while attached to a terminal, report a usage error
  instead of waiting for input. Use `--` before a positional sample beginning
  with a hyphen.
- Positional arguments are individual samples and are not split on embedded
  newlines.
- For files and stdin, decode strict UTF-8 and read LF-delimited records. Remove
  each record's LF and one immediately preceding CR. A final record without LF is
  valid, and a terminating LF does not create an additional empty record.
- Preserve every other character, including leading and trailing spaces. Empty
  records are valid literal samples: one LF supplies one empty sample, whereas a
  zero-byte source supplies no samples.
- Decode positional samples as strict UTF-8 too. Invalid UTF-8 from any source is
  an input failure; keep file path arguments in their original form while opening
  them.
- Combine records from all files and require at least one sample overall. An empty
  file may participate when another source provides a sample, but an invocation
  with zero records fails instead of calling `regexp` on an unpopulated trie.
- Preserve sample order while invoking `add` once per record. Permit duplicates
  and do not sort or deduplicate before the library receives them; the trie itself
  determines the canonical rendering.

### Trie and rendering flow

After parsing and input validation:

1. Create exactly one object with `Regexp::Trie->new`.
2. Call `add` exactly once for each decoded sample, in source order. Pass the
   original string without pre-quoting or other transformation.
3. Call `regexp` exactly once. It performs both trie rendering and Perl regex
   compilation, so do not compile or optimize the samples independently.
4. Capture warnings only around that `regexp` call. Suppress a warning only when
   all samples are empty, the returned pattern body is empty, and the captured
   message starts with version 0.02's known
   `Use of uninitialized value $str in regexp compilation` text. Any additional
   or different warning is a processing failure.
5. Verify the result is a compiled `Regexp`, then call `re::regexp_pattern` and
   print only its pattern component. Do not stringify the object, because that
   adds Perl's outer modifier wrapper.

Discard the modifier component returned by `re::regexp_pattern`. The CLI emits a
decoded UTF-8 regex body made entirely from quoted literals and trie grouping; it
does not offer flags. Consumers must decode the UTF-8 output before compiling it,
as the command's own semantic tests do.

The narrow warning exception preserves the library call and its valid empty regex
while keeping successful stderr clean. Do not bypass `regexp`, reconstruct the
trie from its internal hash, or suppress warnings for nonempty input.

### Output and exit behavior

- Write only the inferred UTF-8 Perl regex body to stdout followed by one newline.
  An empty body therefore produces exactly one newline. Embedded sample newlines
  may make the body itself span physical output lines.
- `--help` writes help to stdout and exits 0 without requiring the CPAN dependency.
- `--version` writes `regexp-trie (Regexp::Trie 0.02)` to stdout and exits 0.
- Successful trie construction exits 0 and leaves stderr empty.
- Unknown options, conflicting source families, repeated stdin, implicit terminal
  input, or an overall zero-sample input exit 2, keep stdout empty, and write a
  concise `regexp-trie:` diagnostic to stderr.
- A missing or wrong dependency, unreadable input, invalid UTF-8, an exception or
  unexpected warning from the module, an invalid return value, or output I/O
  failure exits 1, keeps stdout empty, and writes a concise diagnostic to stderr.
- Buffer the result until processing succeeds so failures cannot leave a partial
  regex on stdout. Do not emit labels, delimiters, colors, timings, statistics, or
  progress text.

### Examples

Upstream's documented trie:

```console
$ printf '%s\n' foobar fooxar foozap fooza | bin/regexp-trie
foo(?:bar|xar|zap?)
```

Literal metacharacters:

```console
$ bin/regexp-trie 'a+b' 'a.b' 'a*b'
a(?:\*b|\+b|\.b)
```

Input order does not affect sibling order:

```console
$ bin/regexp-trie cat car
ca[rt]
```

## Implementation Milestones

1. **Complete the Perl foundation.** Add the exact 0.02 declaration to the shared
   `cpanfile`, install into `local/`, and prove the version loads from that tree.
2. **Build the CLI shell.** Add help/version handling, source-family selection,
   strict UTF-8 decoding, line delimiting, diagnostics, and exact exit statuses.
3. **Exercise the trie API.** Add each untouched sample, call `regexp` once,
   narrowly handle the all-empty warning, extract the pattern body, and buffer
   output.
4. **Cover semantics and failures.** Add end-to-end tests for all source paths,
   trie structures, literals, Unicode, duplicates, empty samples, deterministic
   ordering, safety, and failure boundaries.
5. **Document and validate.** Update the shared README and run clean-checkout
   dependency installation, syntax checks, the focused test, and the full Perl
   exercise suite.

## Test Plan

Use `Test::More` and core subprocess/file helpers. Invoke the executable so tests
cover project-relative dependency discovery, byte streams, output separation, and
exit statuses.

### Dependency and static checks

```sh
cpanm --local-lib-contained local --installdeps .
PERL5LIB=local/lib/perl5 perl -MRegexp::Trie -e \
  'die unless $Regexp::Trie::VERSION eq q{0.02}'
perl -c bin/regexp-trie
prove -v t/regexp-trie.t
prove -v t
```

### Trie behavior

- Help and version write only to stdout, leave stderr empty, and exit 0; help also
  works in a clean checkout before dependencies are installed.
- Assert all three documented examples exactly. These renderings follow version
  0.02's explicit sibling sort and are independent of sample insertion order.
- Positional, single-file, repeated-file, implicit-stdin, and explicit
  `--input -` sources produce identical bodies for the same sample set.
- Verify CRLF handling, a final record without LF, a terminating LF, and blank
  records. Zero bytes yield a zero-sample error; one LF yields one empty regex
  line with no warning; empty plus `foo` yields `(?:foo)?`.
- `foo` plus `foobar` produces `foo(?:bar)?`; `foobar` plus `xxbar` produces
  `(?:foobar|xxbar)` and demonstrates that the library does not factor suffixes.
- Duplicate samples have the same output as one copy. Reversing sample order has
  byte-identical output for ASCII and decoded Unicode cases.
- `café` plus `cafè` produces `caf[èé]`. Decode the emitted UTF-8 before compiling
  it and verify full-string matches for both positives and suitable negatives.
- Cover spaces, tabs, an embedded positional newline, NUL, regex metacharacters,
  backslashes, and non-ASCII characters. Compile each output as
  `\A(?:OUTPUT)\z`; every input must match literally and negatives must fail.
- Confirm the extracted body has no outer `(?^:...)` or `(?^u:...)` wrapper and
  that normal success leaves stderr empty.

### Failure and safety behavior

- Unknown options, missing `--input` arguments, positional plus file input,
  repeated stdin, interactive missing input, and overall zero samples exit 2 with
  empty stdout.
- Missing or unreadable files, invalid UTF-8 from argv/file/stdin, a hidden or
  wrong-version module, a mocked unexpected module warning, a mocked exception or
  non-Regexp return, and simulated output failure exit 1 with empty stdout.
- Run from outside the checkout to prove dependency lookup is executable-relative.
  Run a clean checkout before bootstrap to assert the exact missing-dependency
  guidance.
- Samples containing `(?{...})`, `(??{...})`, delimiters, and backreferences are
  matched literally. Use a sentinel side effect to prove neither trie compilation
  nor semantic validation executes sample text.
- Exercise one empty sample and repeated empty samples to prove only the verified
  upstream warning is contained. Inject any different warning and prove it fails
  rather than being silently discarded.

## Acceptance Criteria

- A clean checkout installs exactly Regexp::Trie 0.02 into the shared project-local
  Perl tree without a global installation.
- `bin/regexp-trie` maps each literal sample directly to one `add` call, invokes
  `regexp` once, and prints the body recovered from that compiled result.
- The wrapper adds no suffix factoring, matching, regex mode, modifiers, sorting,
  deduplication, or optimization of its own.
- Tests prove exact stable trie structures and full-string literal semantics for
  argv, files, stdin, Unicode, whitespace, metacharacters, duplicates, ordering,
  and empty samples.
- The sole-empty-string warning is handled only under its verified preconditions;
  other warnings and failures remain visible as clean diagnostics with no partial
  stdout.
- README documents literal-only input, prefix-only factoring, deterministic sorted
  output, UTF-8 handling, unanchored output, and the empty-sample caveat.

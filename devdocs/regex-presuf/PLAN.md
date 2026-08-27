# Plan: Regex::PreSuf CLI Exercise

## Summary

Add `bin/regex-presuf`, a project-local Perl command that passes literal samples
to `Regex::PreSuf::presuf` and prints the compact Perl regex produced by the
library. Expose its three prefix/suffix strategies and its optional dot-as-any-
character behavior without adding a separate trie, optimizer, matcher, or regex
rewriter.

The library always quotes its inputs internally. This command therefore accepts
literal samples, not regex patterns; strings such as `a.b` and `a*b` remain
literal by default. The one exception is `--anychar`, under which a dot in an
input sample deliberately represents any one character.

## Verified Upstream Facts

- Use [Regex::PreSuf 1.17](https://metacpan.org/release/JHI/Regex-PreSuf-1.17),
  the latest CPAN release. Pin the release rather than tracking an unversioned
  source snapshot.
- The distribution exports one defining function, `presuf`. It accepts an
  optional leading options hash followed by a list of strings and returns a Perl
  regex body that factors common prefixes and, when requested, suffixes.
- `presuf` applies `quotemeta` to every input. Regex metacharacters are therefore
  literal input data. With `anychar` enabled, it changes quoted input dots back to
  wildcard dots before assembly.
- Prefix factoring is enabled and suffix factoring is disabled by default.
  `suffixes => 1` enables both directions, while `prefixes => 0` selects suffix
  factoring without prefix factoring.
- The result has no anchors or modifiers. Callers that require a full-string
  match must anchor it themselves, and emitted whitespace is literal Perl regex
  whitespace that must not be interpreted under the `x` modifier.
- Duplicate samples collapse into one expression. Rendering order is an upstream
  implementation detail and is not required to preserve input order.
- An empty string is valid sample data: one empty sample returns an empty regex,
  while `presuf('', 'foo')` returns `(?:foo)?`. Calling `presuf` with no samples
  also returns an empty string, so the CLI must distinguish those cases before
  invoking the library.
- The distribution has no upstream CLI and declares no non-core runtime
  dependency. Its old MakeMaker source layout is intended to be built or
  installed before tests load `Regex/PreSuf.pm`.

A local feasibility check installed version 1.17 with project-local `cpanm` under
Homebrew Perl 5.44.0. All 57 upstream tests passed against that installed module,
including its 21,417-word corpus test. Verified renderings include
`foo(?:bar|xar|zap)` in default prefix mode, `foo(?:zap|[bx]ar)` with suffixes
enabled, `caf[èé]` for Unicode samples, and `foo.bar` for `foo.bar` plus
`fooxbar` when `anychar` is enabled.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Factor literal samples into one Perl regex through `presuf`. |
| Regex optimization | Structural compaction is intrinsic to inference; arbitrary regex input is unsupported. |
| Matching-text generation | Unsupported; do not emulate it. |
| Regex inference from samples | This is the library's defining operation. |
| Matching/search | Unsupported as a library operation; compile and match output only in tests. |

## Files and Dependency Setup

### Shared Perl infrastructure

Reuse the root `cpanfile` and project-local `local/` tree established by the
earlier Perl plans. Add the exact PreSuf pin so the combined manifest is:

```perl
requires 'Regexp::Optimizer', '== 0.23';
requires 'Regexp::Assemble',  '== 0.38';
requires 'Regex::PreSuf',     '== 1.17';
```

If the shared manifest has not yet been implemented, create it with all three
pins. Otherwise add only the missing declaration. Keep using the root `/local/`
ignore rule and install or refresh that one dependency tree with:

```sh
cpanm --local-lib-contained local --installdeps .
```

Do not install the module globally, vendor the CPAN distribution, or add a second
Perl dependency tree.

### Implementation files

- `bin/regex-presuf`: executable Perl CLI.
- `t/regex-presuf.t`: end-to-end subprocess tests.
- `README.md`: add the command reference, examples, input rules, and the
  literal-versus-`--anychar` distinction to the shared project documentation.

Use `FindBin` to add the root `local/lib/perl5` relative to the executable so it
works outside the repository directory. Use only core support modules such as
`Getopt::Long` and `Encode`; do not add a CLI framework.

Load exactly version 1.17. If it is unavailable, exit 1 and write this actionable
diagnostic to stderr:

```text
regex-presuf: Regex::PreSuf 1.17 is not installed; run cpanm --local-lib-contained local --installdeps .
```

## CLI Contract

```text
Usage: regex-presuf [OPTIONS] [SAMPLE ...]

Infer a compact Perl regex from literal samples.

Input:
  SAMPLE ...                  Each positional argument is one literal sample
  -i, --input FILE            Read one sample per line; repeatable; use - for stdin

Options:
  -s, --strategy TYPE         prefix, both, or suffix; default prefix
  -a, --anychar               Treat dots in samples as one-character wildcards
  -h, --help                  Print help and exit
  -V, --version               Print the command and module version and exit
```

No subcommand is needed because `presuf` exposes one operation. Do not add
anchoring, regex modifiers, matching, arbitrary regex input, debug output, or a
second optimization pass.

### Sample collection

- Select exactly one source family: one or more positional `SAMPLE` arguments,
  one or more repeatable `--input FILE` options, or stdin when neither is given.
  Reject positional samples combined with `--input`.
- Process repeated files in option order and permit `--input -` at most once. If
  stdin is selected implicitly while attached to a terminal, report a usage
  error rather than waiting for input.
- Positional arguments are individual samples and are not split on embedded
  newlines.
- For files and stdin, decode strict UTF-8 and read LF-delimited records. Remove
  each record's LF and one immediately preceding CR. A final record without LF is
  valid, and a terminating LF does not create an additional empty record.
- Preserve every other character, including leading and trailing spaces. Empty
  records are valid samples: an input containing only one LF supplies one empty
  sample. A zero-byte source supplies no samples.
- Decode positional samples as strict UTF-8 too. Invalid UTF-8 from any source is
  an input failure; keep file path arguments in their original form when opening
  them.
- Combine records from all files, then require at least one sample. Empty files
  may participate when another source supplies a sample, but an overall zero-
  sample invocation fails instead of confusing it with one empty sample.
- Permit duplicates and preserve source order when passing the list to `presuf`,
  while making no promise that alternations in the returned regex retain that
  order.

### Option mapping and processing flow

Map `--strategy` directly to the options understood by `presuf`:

| CLI strategy | `presuf` configuration |
| --- | --- |
| `prefix` | Leave the default prefix-only behavior unchanged. |
| `both` | Pass `suffixes => 1`. |
| `suffix` | Pass `prefixes => 0`. |

When `--anychar` is present, also pass `anychar => 1`. This is not an output
formatting option: each dot in an input sample becomes an intentional wildcard
and may subsume samples that have another character in the same position.

After input validation:

1. Build the minimal options hash for the selected strategy and `--anychar`.
2. Call `presuf` exactly once with that hash and the complete decoded sample list.
   Do not pre-quote, sort, deduplicate, or otherwise transform the samples.
3. Compile the returned regex body with a block `eval` around `qr/.../` as a final
   integrity check. Interpolate it as regex data; never construct a string `eval`
   or enable `re 'eval'`.
4. Print the original string returned by `presuf`, not a stringified compiled
   `Regexp`, so the CLI exposes the library's rendering without an outer wrapper.

The compile check is defensive processing validation, not a new matching
capability. User inputs cannot introduce Perl regex code because the library
quotes them; `--anychar` only restores wildcard dots.

### Output and exit behavior

- Write only the inferred UTF-8 Perl regex body to stdout followed by one newline.
  An empty regex therefore produces exactly one newline.
- `--help` writes help to stdout and exits 0.
- `--version` writes `regex-presuf (Regex::PreSuf 1.17)` to stdout and exits 0.
- Successful inference exits 0 and leaves stderr empty.
- Unknown options, an invalid strategy, conflicting source families, repeated
  stdin, implicit terminal input, or an overall zero-sample input are usage/input
  errors: exit 2, keep stdout empty, and write a concise `regex-presuf:`
  diagnostic to stderr.
- A missing/wrong dependency, unreadable input, invalid UTF-8, an exception from
  `presuf`, a generated-regex compilation failure, or output I/O failure exits 1,
  keeps stdout empty, and writes a concise diagnostic to stderr.
- Buffer and validate the result before writing it so failures never leave a
  partial regex on stdout. Do not emit labels, delimiters, colors, statistics, or
  progress messages.

### Examples

Default prefix factoring:

```console
$ printf '%s\n' foobar fooxar foozap | bin/regex-presuf
foo(?:bar|xar|zap)
```

Prefix and suffix factoring:

```console
$ bin/regex-presuf --strategy both foobar fooxar foozap
foo(?:zap|[bx]ar)
```

Dot-as-wildcard inference:

```console
$ bin/regex-presuf --anychar foo.bar fooxbar
foo.bar
```

Without `--anychar`, the dot remains literal and the same inputs produce an
expression equivalent to `foo[\.x]bar`.

## Implementation Milestones

1. **Extend the Perl foundation.** Add the exact 1.17 declaration to the shared
   `cpanfile`, install into `local/`, and prove the module and exported function
   load from that tree.
2. **Build the CLI shell.** Add option parsing, source-family selection, strict
   UTF-8 decoding, line delimiting, help/version text, diagnostics, and the exact
   exit-status policy.
3. **Implement inference.** Map the three strategies and `--anychar`, call
   `presuf` once, compile-check its result, and emit the unmodified returned body.
4. **Cover source and semantic boundaries.** Add subprocess tests for argv, files,
   stdin, empty samples, Unicode, metacharacters, duplicates, strategies, and
   failures.
5. **Document and validate.** Update the shared README and run the clean-checkout
   dependency, syntax, focused-test, and full-Perl-suite checks.

## Test Plan

Use `Test::More` and core subprocess/file helpers. Invoke the executable in tests
so they cover relative dependency discovery, byte streams, stdout/stderr, and
exit statuses.

### Dependency and static checks

```sh
cpanm --local-lib-contained local --installdeps .
PERL5LIB=local/lib/perl5 perl -MRegex::PreSuf -e \
  'die unless $Regex::PreSuf::VERSION eq q{1.17}'
perl -c bin/regex-presuf
prove -v t/regex-presuf.t
prove -v t
```

### Inference behavior

- Help and version write only to stdout, leave stderr empty, and exit 0.
- Assert the three documented examples exactly; version 1.17's own tests treat
  these simple renderings as stable.
- Positional, single-file, repeated-file, implicit-stdin, and explicit
  `--input -` sources have equivalent semantics for identical sample lists.
- Verify CRLF handling, a final record without LF, a terminating LF, and empty
  records. Zero bytes yield a zero-sample error, one LF yields a successful empty
  regex line, and `''` plus `foo` yields `(?:foo)?`.
- Default mode treats `.`, `*`, `+`, `?`, brackets, parentheses, anchors, slashes,
  backslashes, and other regex punctuation literally. Recompile the output and
  anchor it as `\A(?:OUTPUT)\z` in the test before checking every positive sample
  and suitable negative controls.
- `--anychar` makes only input dots wildcards. Confirm that `foo.bar` plus
  `fooxbar` produces `foo.bar`, matches both inputs and another one-character
  substitution, and does not match zero or two characters at that position.
- Unicode input such as `café` and `cafè` produces `caf[èé]` and matches by decoded
  characters. Include leading/trailing spaces and an embedded newline or tab in
  positional samples; validate them without the `x` modifier.
- Duplicate samples do not create duplicate alternatives. Test semantics rather
  than general alternation order because upstream does not promise input-order
  rendering.
- For representative data, compare `prefix`, `both`, and `suffix`: all results
  must match the same supplied samples even though their structures differ.

### Failure and safety behavior

- Unknown options, missing option arguments, invalid strategy names, positional
  plus file input, repeated stdin, interactive missing input, and overall zero
  samples exit 2 with empty stdout.
- Missing and unreadable files, invalid UTF-8 from argv/file/stdin, a hidden or
  wrong-version local module, and simulated write failure exit 1 with empty
  stdout and an attributable diagnostic.
- Run from outside the checkout to prove dependency lookup is relative to the
  executable. Run from a clean checkout before bootstrap to assert the exact
  missing-dependency guidance.
- Samples containing `(?{...})` and `(??{...})` are matched literally in default
  mode. A sentinel side-effect check must prove that neither sample collection nor
  output validation executes them.
- Compile every successful output as a Perl regex. A forced/mock upstream
  exception or invalid return proves that processing failures are buffered and do
  not leak partial stdout.

## Acceptance Criteria

- A clean checkout installs exactly Regex::PreSuf 1.17 into the shared project-
  local Perl tree without a global module installation.
- `bin/regex-presuf` accepts literal samples from exactly the documented source
  families and maps every strategy and `--anychar` directly to `presuf`.
- The command calls the library once, emits its returned regex body unchanged,
  and never adds anchors, modifiers, matching, or wrapper-side optimization.
- Tests prove the emitted expressions' full-string semantics across normal,
  empty, Unicode, whitespace, metacharacter, duplicate, and wildcard samples.
- Diagnostics, output streams, and statuses follow the contract, and no input can
  execute Perl regex code.
- README documents that inputs are literal, dots change meaning under
  `--anychar`, output is unanchored, rendering order is unspecified, and literal
  whitespace must not be used with the `x` modifier.

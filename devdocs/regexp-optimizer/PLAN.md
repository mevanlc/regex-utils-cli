# Plan: Regexp::Optimizer CLI Exercise

## Summary

Add a project-local Perl command, `bin/regexp-optimizer`, that compiles a Perl
regular-expression body, optimizes it with `Regexp::Optimizer`, and prints the
optimized Perl pattern for piping or inspection.

This is an exercise interface for the upstream library, not a new optimizer. The
command must pass the user's pattern directly through Perl's regex compiler and
`Regexp::Optimizer`; it must not add its own rewrite rules or claim that the
result is smaller, faster, idempotent, or semantically correct for every Perl
regex feature.

## Verified Upstream Facts

- Use [Regexp::Optimizer 0.23](https://metacpan.org/pod/Regexp%3A%3AOptimizer),
  the latest CPAN release. It was released in 2013 and declares Perl 5.8.1 as its
  minimum version.
- Pin its direct dependency,
  [Regexp::Assemble 0.38](https://metacpan.org/pod/Regexp%3A%3AAssemble), rather
  than allowing `cpanm` to resolve an arbitrary future release.
- The public surface needed here is `new`, `optimize`, and `as_string`.
  `optimize` calls `as_string` and returns a compiled `Regexp`; `as_string`
  returns the rewritten pattern representation.
- The optimizer acts on Perl regex alternations. It recursively processes groups
  and delegates alternation assembly to `Regexp::Assemble`.
- The implementation uses Perl's experimental `??{ CODE }` facility internally.
  The CLI must not enable `use re 'eval'` for user patterns.
- Upstream documents optimization as non-idempotent: a second pass can add nested
  noncapturing groups even when matching semantics remain unchanged.
- Version 0.23 mishandles an escaped literal pipe in an alternation. Optimizing
  `foo\|bar|baz` produces `(?^:(?:ba[rz]|foo))`, losing the literal-pipe branch and
  broadening the language. Preserve and document that upstream result rather than
  adding a wrapper-side repair.
- An `x`-mode pattern ending in a comment compiles when the scoped wrapper is closed
  after an ignored LF, but version 0.23 reconstructs an invalid expression internally.
  Report that optimizer exception cleanly rather than rewriting the pattern.
- The package has no upstream CLI.

A local feasibility check with Homebrew Perl 5.44.0 confirmed that
`cpanm --local-lib` installs Regexp::Optimizer 0.23 and Regexp::Assemble 0.38,
all 10 upstream optimizer tests pass, and the documented example optimizes to
`(?^:foo(?:[bx]ar|zap))` when the compiled result is rendered with
`re::regexp_pattern`.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Compile and optimize one Perl regex body. |
| Regex optimization | Supported directly through `Regexp::Optimizer->optimize`. |
| Matching-text generation | Unsupported by the library; do not emulate it. |
| Regex inference from samples | Unsupported by this library; `Regexp::Assemble` will receive its own plan. |
| Matching/search | Not a library operation; use matching only inside semantic tests. |

## Files and Dependency Setup

### Shared Perl dependency layout

Create the root `cpanfile` as the shared manifest for all Perl exercise tools:

```perl
requires 'Regexp::Optimizer', '== 0.23';
requires 'Regexp::Assemble',  '== 0.38';
```

Future Perl plans must add to this manifest and reuse the same installation tree.
Do not create a manifest or local library directory per command.

Install into the ignored root `local/` directory:

```sh
cpanm --local-lib-contained local --installdeps .
```

Add `/local/` to the root `.gitignore`. Do not check installed CPAN files into the
repository and do not require a global module installation.

### Implementation files

- `bin/regexp-optimizer`: executable Perl CLI.
- `t/regexp-optimizer.t`: end-to-end tests that invoke the executable.
- `README.md`: initial project setup and usage documentation, including the local
  `cpanm` bootstrap and the examples below.
- `cpanfile` and `.gitignore`: shared Perl dependency infrastructure described
  above.

The command must locate `local/lib/perl5` relative to its own path using
`FindBin`, not the caller's current working directory. Use Perl core modules
`Getopt::Long`, `Encode`, and `re`; do not add another CLI framework dependency.

If the pinned module is unavailable, exit with status 1 and write this actionable
diagnostic to stderr:

```text
regexp-optimizer: Regexp::Optimizer 0.23 is not installed; run cpanm --local-lib-contained local --installdeps .
```

## CLI Contract

```text
Usage: regexp-optimizer [OPTIONS] [PATTERN]

Optimize one Perl regular-expression body.

Input:
  PATTERN                    Regex body supplied as one argument
  -i, --input FILE           Read the complete regex body from FILE; use - for stdin

Options:
  -f, --flags FLAGS          Perl modifiers drawn from i, m, s, and x
  -h, --help                 Print help and exit
  -V, --version              Print the command and module version and exit
```

### Input rules

- Accept exactly one input source: one positional `PATTERN`, one `--input FILE`,
  or stdin when neither is supplied.
- Reject multiple positional patterns and reject a positional pattern combined
  with `--input` as usage errors.
- If no pattern or `--input` is supplied and stdin is a terminal, report a usage
  error instead of waiting for input. A redirected empty stdin is a valid empty
  regex.
- `--input -` selects stdin explicitly.
- Treat PATTERN as a regex body, not a slash-delimited Perl literal. For example,
  pass `foo|bar`, not `/foo|bar/i`; use `--flags i` for modifiers. Literal leading
  hyphens require the standard `--` option terminator.
- Read file and stdin contents in full without stripping a trailing newline or
  other whitespace. This preserves regex bytes that can be meaningful without
  the `x` modifier.
- Decode the regex body as strict UTF-8 regardless of whether it came from argv,
  a file, or stdin. Invalid UTF-8 is an input failure. Keep the filesystem path
  itself in its original argv representation when opening a file.
- `FLAGS` defaults to empty. Accept each of `i`, `m`, `s`, and `x` at most once;
  reject other or duplicate characters with status 2. Canonicalize accepted
  flags to `imsx` order before compiling.

### Compilation and optimization flow

1. Decode and validate the selected input and flags.
2. If flags are present, construct a scoped inline modifier group
   `(?FLAGS:PATTERN)`; otherwise compile PATTERN directly. When `x` is active, append
   one ignored LF inside the group so an end-of-input comment cannot consume the
   wrapper's closing parenthesis.
3. Compile with a block `eval` around `qr/.../`. Interpolate the already decoded
   pattern as regex data; do not construct and execute a string `eval`.
4. Do not enable `re 'eval'`. Reject user patterns containing executable Perl
   regex code when Perl's compiler rejects them.
5. Create one `Regexp::Optimizer` instance and call `optimize` once. Do not run a
   fixed point loop because the operation is not textually idempotent.
6. Call `re::regexp_pattern` on the returned compiled regex and print the pattern
   component. Do not stringify the `Regexp` object directly, because that adds an
   extra outer wrapper such as `(?^:(?^:...))`.

Calling `optimize` exercises both public transformation paths because upstream's
`optimize` delegates to `as_string` before compiling the result.

### Output and exit behavior

- Write the optimized pattern to UTF-8 stdout exactly as returned by
  `re::regexp_pattern`, followed by one newline. Do not add labels, delimiters,
  color, or explanatory text.
- `--help` writes help to stdout and exits 0.
- `--version` writes `regexp-optimizer (Regexp::Optimizer 0.23)` to stdout and
  exits 0.
- Exit 0 after successful processing, including an empty input pattern.
- Exit 2 for option/operand mistakes, invalid or duplicate flags, or a missing
  input source on an interactive terminal. Print a concise diagnostic and usage
  hint to stderr.
- Exit 1 for a missing dependency, unreadable input file, invalid UTF-8, Perl regex
  compilation failure, or an exception from the optimizer. Prefix the underlying
  diagnostic with `regexp-optimizer:` and keep stdout empty.
- Let normal broken-pipe handling terminate output without replacing the primary
  result with a diagnostic.

### Examples

```console
$ bin/regexp-optimizer 'foobar|fooxar|foozap'
(?^:foo(?:[bx]ar|zap))
```

```console
$ printf %s 'foo|bar' | bin/regexp-optimizer --flags i
(?^:(?i:(?:bar|foo)))
```

Because stdin is preserved verbatim, use `printf` rather than `echo` when a
trailing newline is not intended to be part of the regex.

## Implementation Milestones

1. **Bootstrap shared Perl dependencies.** Add `cpanfile`, ignore `local/`, install
   the exact releases with project-local `cpanm`, and prove both pinned module
   versions load from `local/lib/perl5`.
2. **Build the executable shell.** Add the relative local-library lookup,
   dependency diagnostic, strict UTF-8 streams, option parsing, help/version
   output, source exclusivity checks, and documented exit statuses.
3. **Implement optimization.** Compile the body safely with optional scoped
   modifiers, call `optimize` once, extract the result through
   `re::regexp_pattern`, and keep stdout machine-friendly.
4. **Add end-to-end coverage.** Exercise argv, file, and stdin inputs; validate
   exact stable examples and semantic equivalence for cases whose rendering is
   not contractual.
5. **Document and recheck from clean state.** Add README setup and examples, remove
   `local/`, reinstall from `cpanfile`, and run all checks again.

## Test Plan

Use `Test::More` and core process/file facilities. Invoke the executable as a
subprocess so tests cover its relative module lookup, byte streams, stderr, and
exit status rather than only calling Perl functions in-process.

### Dependency and static checks

```sh
cpanm --local-lib-contained local --installdeps .
PERL5LIB=local/lib/perl5 perl -MRegexp::Optimizer -MRegexp::Assemble -e \
  'die unless $Regexp::Optimizer::VERSION eq q{0.23} && $Regexp::Assemble::VERSION eq q{0.38}'
perl -c bin/regexp-optimizer
prove -v t/regexp-optimizer.t
```

### Successful behavior

- `--help` and `--version` write only to stdout and exit 0.
- The documented alternation example produces exactly
  `(?^:foo(?:[bx]ar|zap))` plus a newline.
- `foo|bar` with `--flags i` produces exactly
  `(?^:(?i:(?:bar|foo)))` plus a newline.
- The same pattern supplied through argv, a file, stdin, and `--input -` produces
  identical output when the bytes are identical.
- A non-alternating pattern succeeds without claiming that a rewrite occurred.
- An empty redirected input succeeds and emits one empty output line.
- Nested groups, escaped metacharacters, and ordinary `x`-mode whitespace exercise the
  upstream cases represented in its test suite.
- Characterize the escaped-literal-pipe defect exactly: `foo\|bar|baz` renders
  `(?^:(?:ba[rz]|foo))`, ceases to full-match `foo|bar`, and starts full-matching
  `foo`. This pinned failure is not included in semantic-equivalence assertions.
- Confirm an end-of-input `x` comment passes wrapper compilation but fails during
  upstream optimization with status 1, a prefixed diagnostic, and empty stdout.
- A UTF-8 pattern with non-ASCII literals recompiles successfully and matches the
  same positive and negative samples before and after optimization.
- Recompile CLI output as a Perl regex and compare matching results for a table of
  positive and negative samples. Do not depend on alternation ordering where
  `Regexp::Assemble` does not promise a textual order.
- Run optimized output through the command a second time to document the upstream
  non-idempotence caveat; assert semantic equivalence, not textual equality.

### Failure behavior

- Unknown options, duplicate flags, unsupported flags, multiple positional
  patterns, and conflicting positional/`--input` sources exit 2 with empty stdout.
- No input on a terminal exits 2 without blocking.
- A nonexistent or unreadable file, invalid UTF-8, an unclosed group, and another
  invalid Perl pattern exit 1 with empty stdout and a prefixed stderr diagnostic.
- A pattern containing a Perl code assertion such as `(?{ ... })` is rejected;
  no code from the pattern executes.
- Temporarily hiding `local/lib/perl5` produces the exact dependency guidance and
  status 1.

## Acceptance Criteria

- A clean checkout can install the two exact CPAN releases into `local/` with the
  documented `cpanm` command and without a global module install.
- `bin/regexp-optimizer` works from outside the repository root because its local
  library lookup is based on the executable path.
- The public CLI, examples, stdout/stderr separation, and exit statuses match this
  document exactly.
- The command calls upstream optimization once, renders through
  `re::regexp_pattern`, and does not execute regex-supplied Perl code.
- Tests demonstrate both the stable documented rendering and semantic behavior on
  representative positive and negative samples.
- README records the old-release/non-idempotence caveats and describes this as an
  exploratory wrapper rather than a guarantee of optimal regex output.

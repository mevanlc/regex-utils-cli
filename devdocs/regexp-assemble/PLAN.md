# Plan: Regexp::Assemble CLI Exercise

## Summary

Add `bin/regexp-assemble`, a project-local Perl command for assembling multiple
Perl regex patterns into one regex and testing the assembled regex against one
candidate string. The command will also support literal-sample mode, where each
input is quoted before assembly so the library infers a compact regex matching
the supplied samples literally.

The CLI must remain a transparent exercise surface for `Regexp::Assemble`. It may
decode and delimit inputs, quote literal samples, validate patterns, and render
the result, but it must not implement its own trie, optimizer, or matching logic.

## Verified Upstream Facts

- Use [Regexp::Assemble 0.38](https://metacpan.org/pod/Regexp%3A%3AAssemble),
  the latest CPAN release. It was released in 2017 under the Perl 5 license.
- The module accepts regex strings through `add`, tokenizes them, reduces common
  prefixes and suffixes, and produces either a pattern string through `as_string`
  or a compiled regex through `re`.
- `add` chomps records by default. This CLI will delimit records itself and create
  the object with `chomp => 0` so meaningful input whitespace is not discarded a
  second time.
- `as_string` and `re` drain the object's internal path unless deprecated mutable
  mode is enabled. Each CLI invocation therefore creates one object and performs
  one terminal assembly operation.
- Reduction is enabled by default. Lookahead generation and plus-unrolling are
  opt-in. Meta-pair folding is enabled by default even though upstream warns that
  it is incorrect for some `s`-modifier cases.
- The default lexer can mishandle nested parenthetical expressions, and complex
  inputs can produce an invalid or semantically incorrect assembled pattern.
  Disabling reduction is an upstream-recommended diagnostic workaround for some
  edge cases, not a general correctness guarantee.
- The module can track which source pattern matched, but tracked output inserts
  `(?{ ... })` code and `_build_re` enables `re 'eval'`. Exposing that mode for
  user-controlled patterns would permit regex-supplied Perl code to run, so this
  CLI must not expose `track`, `matched`, or tracked matching.
- The package has no upstream CLI.

A local feasibility check with Homebrew Perl 5.44.0 confirmed that all 2,948
upstream tests pass when run from the distribution root. The three-pattern
example `foobar`, `fooxar`, and `foozap` assembles to
`foo(?:[bx]ar|zap)`, and untracked `match` returns `fooxar` as the matched
substring in `xxfooxaryy`.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Assemble multiple regex patterns with `add` and `re`. |
| Regex optimization | Common-prefix/suffix assembly and optional reduction are intrinsic to the library. |
| Matching-text generation | Unsupported; do not emulate it. |
| Regex inference from samples | `--literal` quotes samples and lets the library assemble them. |
| Matching/search | `match` uses the library's untracked `match` and `mvar(0)` APIs. |

## Files and Dependency Setup

### Shared Perl infrastructure

Reuse the root `cpanfile` and project-local `local/` tree established by the
Regexp::Optimizer plan. The combined Perl manifest remains:

```perl
requires 'Regexp::Optimizer', '== 0.23';
requires 'Regexp::Assemble',  '== 0.38';
```

If the shared manifest has not yet been implemented, create it with both exact
pins. Otherwise verify the declarations rather than adding a duplicate. The root
`.gitignore` already ignores `/local/`.

Install or refresh the shared local dependency tree with:

```sh
cpanm --local-lib-contained local --installdeps .
```

Do not install globally, vendor CPAN source, or create a second Perl dependency
tree for this command.

### Implementation files

- `bin/regexp-assemble`: executable Perl CLI.
- `t/regexp-assemble.t`: end-to-end subprocess tests.
- `README.md`: add setup, command reference, examples, and safety/lexer caveats to
  the project documentation created by the first implemented CLI plan.

Use `FindBin` to add the root `local/lib/perl5` relative to the executable, so the
command works from any current directory. Use only Perl core support modules such
as `Getopt::Long`, `Encode`, and `re`; no additional CLI framework is needed.

If the pinned dependency cannot be loaded, write this to stderr and exit 2:

```text
regexp-assemble: Regexp::Assemble 0.38 is not installed; run cpanm --local-lib-contained local --installdeps .
```

## CLI Contract

```text
Usage:
  regexp-assemble assemble [OPTIONS] [PATTERN ...]
  regexp-assemble match [OPTIONS] (--text TEXT | --text-file FILE) [PATTERN ...]

Pattern input:
  PATTERN ...                 Each positional argument is one pattern or sample
  -i, --input FILE            Read one pattern or sample per line; repeatable;
                              use - for stdin

Assembly options:
  -l, --literal               Treat inputs as literal samples with quotemeta
  -f, --flags FLAGS           Perl modifiers drawn from i, m, s, and x
  -a, --anchor TYPE           none, word, line, string, or string-absolute
      --[no-]reduce           Enable or disable tail reduction; default enabled
      --lookahead             Enable lookahead generation
      --unroll-plus           Enable plus-quantifier unrolling
      --[no-]fold-meta-pairs  Fold complementary meta pairs; default enabled
      --indent SPACES         Pretty-print with this positive indentation width

Match input:
  -t, --text TEXT             Candidate text supplied as one argument
      --text-file FILE        Read the complete candidate text from FILE

General options:
  -h, --help                  Print command or subcommand help and exit
  -V, --version               Print the command and module version and exit
```

Require an explicit `assemble` or `match` subcommand. Top-level help must show both
forms; subcommand help must show only the options valid for that operation.

### Pattern collection input

- Select exactly one pattern-source family:
  - one or more positional `PATTERN` arguments;
  - one or more repeatable `--input FILE` options; or
  - stdin when neither positional patterns nor `--input` are supplied.
- Reject positional patterns combined with `--input`. Process repeated input files
  in option order. Permit `--input -` at most once.
- If stdin is implicitly selected while attached to a terminal, report a usage
  error rather than waiting for input.
- Positional arguments are already individual records and are not split on
  newlines.
- For files and stdin, decode strict UTF-8 and read records separated by LF.
  Remove the record's LF and one immediately preceding CR. A final record without
  LF is valid. A trailing LF does not create another empty record.
- Decode positional patterns as strict UTF-8. Invalid UTF-8 from any source is an
  input error.
- Require at least one record and reject empty records with a source filename and
  line number, or a positional index. `Regexp::Assemble` renders an empty assembly
  as an always-fail pattern containing NUL, which is not useful CLI output.
- Preserve every other character, including leading/trailing spaces and embedded
  newlines in positional patterns. Construct `Regexp::Assemble` with `chomp => 0`.
- In regex mode, each record is a Perl regex body, not `/.../flags` syntax. In
  literal mode, apply Perl's `quotemeta` once before validation and `add`.
- Duplicate inputs are permitted and follow upstream behavior: they are counted
  internally but do not add duplicate branches to the assembled regex.

### Candidate text input

- `match` requires exactly one of `--text TEXT` or `--text-file FILE`.
- Decode candidate text as strict UTF-8. `--text-file` reads the complete file
  without removing line endings or other whitespace.
- Do not accept `-` for `--text-file`; stdin is reserved for pattern records when
  selected. Use `--text` for a candidate that must accompany stdin patterns.
- Reject `--text` and `--text-file` for `assemble`.

### Option validation and API mapping

- `FLAGS` defaults to empty. Accept each of `i`, `m`, `s`, and `x` at most once,
  reject other or duplicate characters, and canonicalize accepted flags to `imsx`
  order before passing them to `flags`.
- `--anchor` defaults to `none` and maps as follows:

  | CLI value | API call |
  | --- | --- |
  | `none` | no anchor method |
  | `word` | `anchor_word(1)` |
  | `line` | `anchor_line(1)` |
  | `string` | `anchor_string(1)` using `\A...\Z` |
  | `string-absolute` | `anchor_string_absolute(1)` using `\A...\z` |

- Map `--no-reduce` to `reduce(0)`, `--lookahead` to `lookahead(1)`,
  `--unroll-plus` to `unroll_plus(1)`, and `--no-fold-meta-pairs` to
  `fold_meta_pairs(0)`. Preserve upstream defaults when these switches are absent.
- `--indent` requires an integer greater than zero and requires `x` in `--flags`;
  otherwise pretty-print whitespace would change matching semantics. Reject
  `--indent` combined with `--lookahead` because upstream gives indentation
  precedence and would silently ignore lookahead generation.
- Keep `--lookahead` opt-in and document upstream's warning about incorrect
  patterns in obscure lookahead cases.
- Do not expose callbacks, a custom lexer, `insert`, debugging, mutable mode,
  tracking, capture attribution, or internal dumps in this focused CLI.

### Assembly and matching flow

1. Parse and validate the subcommand, inputs, and option combinations before
   constructing the upstream object.
2. Create `Regexp::Assemble->new(chomp => 0, flags => FLAGS)` and apply the selected
   anchor, reduction, lookahead, unroll, fold, and indentation methods.
3. Transform inputs with `quotemeta` only in literal mode.
4. Validate each transformed record with a block `eval` around `qr/.../`, using a
   scoped inline modifier group when flags are present. Never use string `eval` or
   enable `re 'eval'`. Report the offending source/index if compilation fails.
5. Call `add` once per validated record so source-specific failures remain
   attributable.
6. For `assemble`, call `re`, extract the pattern component with
   `re::regexp_pattern`, and print it. This preserves selected modifiers as an
   inline group and avoids the outer `(?^:...)` added by direct stringification.
7. For `match`, call the untracked `match` method with the candidate. On success,
   retrieve and print the matched substring through `mvar(0)`. Do not enable
   tracking merely to identify the contributing source pattern.

Calling `re` rather than only `as_string` ensures the final assembled expression
actually compiles. A successful compile still does not prove semantic equivalence
for every complex input, so the documentation and tests must retain the upstream
lexer caveat.

### Output and exit behavior

- `assemble` writes only the assembled Perl regex body to UTF-8 stdout, followed
  by one newline.
- A successful `match` writes the exact matched substring followed by one newline.
  A zero-width match therefore writes one empty line.
- A non-match writes nothing and exits 1.
- `--version` writes `regexp-assemble (Regexp::Assemble 0.38)` and exits 0.
- Help and successful assembly/match operations exit 0.
- All usage, input, dependency, regex compilation, assembly, and I/O failures exit
  2, write a concise `regexp-assemble:` diagnostic to stderr, and keep stdout
  empty. This reserves status 1 exclusively for a valid match operation that did
  not match, following grep-style matching semantics.
- Do not emit upstream statistics, labels, colors, or progress text. Let normal
  broken-pipe handling terminate output.

### Examples

```console
$ printf '%s\n' foobar fooxar foozap | bin/regexp-assemble assemble
foo(?:[bx]ar|zap)
```

```console
$ bin/regexp-assemble assemble --literal 'a.b' 'a-b'
a[-.]b
```

```console
$ bin/regexp-assemble match --text xxfooxaryy foobar fooxar foozap
fooxar
```

## Implementation Milestones

1. **Reuse the Perl foundation.** Merge the exact Assemble pin into the shared
   `cpanfile` if needed, install into `local/`, and prove version 0.38 loads from
   that tree.
2. **Build common CLI parsing.** Add subcommand dispatch, source-family handling,
   strict UTF-8 decoding, record attribution, help/version output, option conflict
   checks, and grep-style exit statuses.
3. **Implement assembly.** Configure the object, validate and add each pattern,
   call `re`, and render through `re::regexp_pattern`.
4. **Implement literal inference and matching.** Add transparent `quotemeta`
   handling and untracked `match`/`mvar(0)` behavior without `re 'eval'`.
5. **Test and document.** Add semantic and exact-output tests, document the shared
   bootstrap and both subcommands, then validate from a clean local dependency
   tree.

## Test Plan

Use `Test::More` and core subprocess/file helpers. Tests must invoke the executable
so they cover relative dependency discovery, byte streams, output separation, and
exit statuses.

### Dependency and static checks

```sh
cpanm --local-lib-contained local --installdeps .
PERL5LIB=local/lib/perl5 perl -MRegexp::Assemble -e \
  'die unless $Regexp::Assemble::VERSION eq q{0.38}'
perl -c bin/regexp-assemble
prove -v t/regexp-assemble.t
```

### Assembly behavior

- Top-level and subcommand help, plus `--version`, write only to stdout and exit 0.
- The documented regex and literal examples produce their exact shown output.
- Positional, single-file, repeated-file, implicit-stdin, and `--input -` sources
  produce equivalent assembly when their records are identical.
- CRLF and a final record without LF are delimited as specified; a trailing LF
  does not create an empty pattern.
- Duplicate records do not duplicate the assembled branch.
- Flags are preserved in the rendered regex, and every anchor mode produces the
  documented Perl anchor pair.
- Default reduction and `--no-reduce` are both exercised. Recompile their outputs
  and compare positive and negative samples instead of requiring identical text.
- Exercise lookahead, plus-unrolling, meta-pair folding on and off, and indented
  `x` output with inputs for which each setting changes rendering or behavior.
- Literal mode covers regex metacharacters, spaces, and non-ASCII UTF-8 samples;
  the output must match every literal sample and appropriate negative controls.
- Regex mode covers character classes, quantifiers, escaped metacharacters, and a
  nested-group case supported by the default lexer.

### Matching behavior

- `match` returns the first matched substring through `mvar(0)`, exits 0, and keeps
  stderr empty for both regex and literal modes.
- A valid non-match exits 1 with both output streams empty.
- A zero-width match emits exactly one newline and exits 0.
- `--text-file` preserves candidate newlines, and matching remains Unicode-aware
  after strict UTF-8 decoding.
- Anchor and modifier options affect matching in the same way they affect emitted
  assembly output.

### Failure and safety behavior

- Missing/unknown subcommands, unknown options, invalid flags or anchors, bad
  indentation, conflicting input families, repeated stdin, and invalid text
  source combinations exit 2 with empty stdout.
- Interactive missing pattern input fails without blocking. Zero records and blank
  records fail with their precise source/index.
- Missing/unreadable files, invalid UTF-8 patterns or candidate text, and invalid
  Perl patterns exit 2 with attributed diagnostics.
- Inputs with executable assertions such as `(?{ ... })` and `(??{ ... })` are
  rejected, and sentinel side effects prove that no user code ran.
- An input that exposes the upstream nested-parenthesis lexer limitation must fail
  cleanly if the assembled result cannot compile; it must not produce partial
  stdout.
- Running from outside the repository finds the same project-local dependency.
  Hiding `local/lib/perl5` produces the exact bootstrap guidance and status 2.

## Acceptance Criteria

- A clean checkout installs the exact shared Perl dependencies into `local/`
  without a global package installation.
- The CLI implements the two documented subcommands and maps every supported
  option directly to the named upstream method.
- Regex assembly, literal-sample inference, and untracked matching work from argv,
  files, and stdin as applicable, with stable stdout and grep-style match status.
- Final output is compiled before printing and is extracted with
  `re::regexp_pattern` rather than direct object stringification.
- No code path enables `re 'eval'`, tracking, or user-supplied Perl execution.
- Tests cover exact stable examples, semantic positive/negative cases, input/error
  boundaries, safety, and execution outside the repository root.
- README clearly documents input record rules, regex-versus-literal mode, option
  mappings, unsupported tracking, and upstream lexer/lookahead limitations.

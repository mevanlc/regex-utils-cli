# regex-utils-cli

Project-local command-line exercises for regex-related libraries across several
language ecosystems. Each command stays close to its upstream library's public API;
the implementation plans and verified limitations are under [`devdocs/`](devdocs/).

## Perl setup

The Perl commands share one exact, project-local dependency manifest. Requirements:

- Perl
- `cpanm`

Install into the ignored `local/` tree:

```sh
cpanm --local-lib-contained local --installdeps .
```

No global Perl modules are required. Each executable finds `local/lib/perl5`
relative to its own path, so it can be invoked from another working directory.

## Regexp::Optimizer

`bin/regexp-optimizer` compiles one Perl regex body, passes it through
`Regexp::Optimizer` once, and prints the optimized pattern for piping or inspection.

### Usage

```text
Usage: regexp-optimizer [OPTIONS] [PATTERN]

Input:
  PATTERN                    Regex body supplied as one argument
  -i, --input FILE           Read the complete regex body from FILE; use - for stdin

Options:
  -f, --flags FLAGS          Perl modifiers drawn from i, m, s, and x
  -h, --help                 Print help and exit
  -V, --version              Print the command and module version and exit
```

Supply exactly one input source. With no positional pattern or `--input`, redirected
stdin is read in full. File and stdin input preserve every byte, including a trailing
newline, then are decoded as strict UTF-8. Patterns are regex bodies rather than
slash-delimited literals; use `--flags` for modifiers.

```console
$ bin/regexp-optimizer 'foobar|fooxar|foozap'
(?^:foo(?:[bx]ar|zap))

$ printf %s 'foo|bar' | bin/regexp-optimizer --flags i
(?^:(?i:(?:bar|foo)))
```

Successful output is the pattern returned by `re::regexp_pattern`, followed by one
newline. Usage errors exit 2. Dependency, input, compilation, and optimization failures
exit 1 and write only a prefixed diagnostic to stderr.

### Scope and caveats

This is an exploratory wrapper around Regexp::Optimizer 0.23, an old CPAN release. It
does not add rewrite rules or promise that output is smaller, faster, canonical, or
correct for every Perl regex feature. Upstream optimization is not textually idempotent,
so the command performs exactly one pass.

Version 0.23 also mishandles an escaped literal pipe inside an alternation. For example,
optimizing `foo\|bar|baz` produces `(?^:(?:ba[rz]|foo))`, which does not preserve the
original language. The wrapper deliberately reports that upstream result rather than
repairing it with a second regex implementation.

An `x`-mode pattern ending in a comment can compile successfully but fail inside the
upstream optimizer when it reconstructs the expression. That failure is reported on
stderr with status 1 and no partial output.

The wrapper does not enable `re 'eval'`. User patterns containing executable regex code
are rejected by Perl rather than executed. Matching-text generation, sample-to-regex
inference, and a matching/search command are outside this library's interface.

## Regexp::Assemble

`bin/regexp-assemble` exercises Regexp::Assemble 0.38 through two operations:
assembling multiple Perl regex bodies and searching candidate text with the resulting
untracked regex.

```text
Usage:
  regexp-assemble assemble [OPTIONS] [PATTERN ...]
  regexp-assemble match [OPTIONS] (--text TEXT | --text-file FILE) [PATTERN ...]

Pattern input:
  PATTERN ...                 Each argument is one pattern or literal sample
  -i, --input FILE            Read one record per line; repeatable; use - for stdin

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
```

Choose positional records, repeatable input files, or stdin—not a mixture. Files and
stdin contain LF-delimited strict UTF-8 records; a preceding CR is removed, a final
record need not end in LF, and blank patterns are rejected. Positional arguments are
already individual records and may contain newlines. Regex mode accepts Perl regex
bodies rather than `/.../flags` syntax. `--literal` instead quotes each record once,
making the command a literal-sample inference surface.

```console
$ printf '%s\n' foobar fooxar foozap | bin/regexp-assemble assemble
foo(?:[bx]ar|zap)

$ bin/regexp-assemble assemble --literal 'a.b' 'a-b'
a[-.]b

$ bin/regexp-assemble match --text xxfooxaryy foobar fooxar foozap
fooxar
```

The anchor choices map directly to the library's word, line, string (`\A...\Z`),
and absolute-string (`\A...\z`) methods. Indentation requires `--flags x` and cannot
be combined with lookahead. A non-match exits 1 with no output; successful matches
print the exact matched substring. All usage, input, dependency, regex, and assembly
failures exit 2.

The command deliberately does not expose tracking because Regexp::Assemble implements
tracked patterns with embedded Perl code and `re 'eval'`. The default lexer can
mishandle nested parentheses, and upstream warns that meta-pair folding under `s` and
some lookahead expressions can be incorrect. Disabling reduction is a diagnostic aid,
not a general correctness guarantee. Every emitted assembly is nevertheless compiled
by the library before it is printed.

## Regex::PreSuf

`bin/regex-presuf` passes literal samples to Regex::PreSuf 1.17 exactly once and
prints the compact Perl regex body returned by the library.

```text
Usage: regex-presuf [OPTIONS] [SAMPLE ...]

Input:
  SAMPLE ...                  Each positional argument is one literal sample
  -i, --input FILE            Read one sample per line; repeatable; use - for stdin

Options:
  -s, --strategy TYPE         prefix, both, or suffix; default prefix
  -a, --anychar               Treat dots in samples as one-character wildcards
  -h, --help                  Print help and exit
  -V, --version               Print the command and module version and exit
```

Choose positional samples, repeatable input files, or stdin. File and stdin records
use strict UTF-8 and LF delimiters; a preceding CR is removed, a final LF does not add
another sample, and one blank line represents one empty sample. Zero records are an
error. Empty positional arguments and all other whitespace are preserved.

```console
$ printf '%s\n' foobar fooxar foozap | bin/regex-presuf
foo(?:bar|xar|zap)

$ bin/regex-presuf --strategy both foobar fooxar foozap
foo(?:zap|[bx]ar)

$ bin/regex-presuf --anychar foo.bar fooxbar
foo.bar
```

Inputs are literal, not regex bodies: Regex::PreSuf quotes regex punctuation itself.
Only `--anychar` changes that rule by deliberately restoring input dots as one-character
wildcards. `prefix` uses the library default, `both` enables suffix factoring, and
`suffix` disables prefix factoring. Output is unanchored, has no modifiers, and may not
retain input order. Duplicate samples collapse upstream. The command compile-checks
the returned body but does not add matching, anchors, sorting, deduplication, or another
optimization pass.

## Regexp::Trie

`bin/regexp-trie` inserts literal samples into Regexp::Trie 0.02, invokes the
library's `regexp` method once, and prints the compiled regex body without Perl's
outer modifier wrapper.

```text
Usage: regexp-trie [OPTIONS] [SAMPLE ...]

Input:
  SAMPLE ...                  Each positional argument is one literal sample
  -i, --input FILE            Read one sample per line; repeatable; use - for stdin

Options:
  -h, --help                  Print help and exit
  -V, --version               Print the command and module version and exit
```

Its source rules match `regex-presuf`: choose positional samples, repeatable files,
or stdin; file records are LF-delimited strict UTF-8 with an optional preceding CR;
empty records are samples; and zero records are an error. Each sample is passed
unchanged to one `add` call.

```console
$ printf '%s\n' foobar fooxar foozap fooza | bin/regexp-trie
foo(?:bar|xar|zap?)

$ bin/regexp-trie 'a+b' 'a.b' 'a*b'
a(?:\*b|\+b|\.b)

$ bin/regexp-trie cat car
ca[rt]
```

Inputs are always literal. The library shares prefixes, forms character classes,
and makes tails optional, but it does not factor arbitrary suffixes: `foobar` and
`xxbar` remain `(?:foobar|xxbar)`. Sibling keys are sorted by the library, so output
is deterministic for a decoded sample set rather than insertion ordered. Duplicate
samples collapse in the trie. Output is UTF-8, unanchored, and has no selectable
modifiers.

An empty sample is supported; empty plus `foo` produces `(?:foo)?`. Version 0.02
emits a known uninitialized-value warning when every sample is empty even though it
returns a valid empty regex. The wrapper suppresses only that exact case. Any other
module warning is a failure, and no wrapper-side sorting, suffix factoring, matching,
or optimization is added.

## Tests

```sh
PERL5LIB=local/lib/perl5 perl -MRegexp::Optimizer -MRegexp::Assemble -MRegex::PreSuf -MRegexp::Trie -e \
  'die unless $Regexp::Optimizer::VERSION eq q{0.23} && $Regexp::Assemble::VERSION eq q{0.38} && $Regex::PreSuf::VERSION eq q{1.17} && $Regexp::Trie::VERSION eq q{0.02}'
perl -c bin/regexp-optimizer
perl -c bin/regexp-assemble
perl -c bin/regex-presuf
perl -c bin/regexp-trie
prove -v t
```

## Node setup

The Node commands share one root manifest and lockfile. Install the exact
project-local dependency graph with Node and npm:

```sh
npm ci
```

No global npm packages are used. Invoke commands through their npm scripts so
resolution stays inside this checkout.

## regexp-tree

The project directly exposes the official `regexp-tree-cli` 0.0.21 command; it
does not add a wrapper. That CLI pins and exercises `regexp-tree` 0.1.27.

```text
npm run --silent regexp-tree -- [UPSTREAM OPTIONS]

Upstream options:
  -e, --expression REGEXP     Slash-delimited regex literal; required
  -l, --loc                   Capture AST node locations while parsing
  -o, --optimize              Optimize and regenerate the expression
  -c, --compat                Transpile newer/extended features for compatibility
  -t, --table TYPE            Print nfa, dfa, or all transition tables
  -h, --help                  Show native help
  -v, --version               Show the CLI package version
```

Expressions must be one quoted `/Body/OptionalFlags` argument. The command has
no file or stdin input mode. With no operation flag it prints a two-space-indented
ECMAScript-style AST; `--loc`, optimization, compatibility transpilation, and
educational NFA/DFA tables retain their native output and status behavior.

```console
$ FORCE_COLOR=0 npm run --silent regexp-tree -- -e '/a|b/i'
{
  "type": "RegExp",
  "body": {
    "type": "Disjunction",
    "left": {
      "type": "Char",
      "value": "a",
      "kind": "simple",
      "symbol": "a",
      "codePoint": 97
    },
    "right": {
      "type": "Char",
      "value": "b",
      "kind": "simple",
      "symbol": "b",
      "codePoint": 98
    }
  },
  "flags": "i"
}

$ FORCE_COLOR=0 npm run --silent regexp-tree -- \
    -e '/[a-zA-Z_0-9][A-Z_\da-z]*e{1,}/' --optimize

 Optimized: /\w+e+/

```

Native precedence is `optimize`, then `compat`, then `table`, then parse; these
options are alternatives rather than a pipeline. `--loc` affects only parse mode.
Unknown options and extra operands are silently ignored upstream, and not every
parsed construct is supported by automaton conversion. Output may include ANSI
styling even when redirected; use `FORCE_COLOR=0` for deterministic output. This
CLI does not expose matching, sample inference, or matching-text generation.

## oniguruma-parser

`bin/oniguruma-parser` exercises oniguruma-parser 0.12.2 through parsing,
canonical regeneration, read-only traversal, and optimization.

```text
Usage:
  oniguruma-parser parse [OPTIONS] [PATTERN]
  oniguruma-parser roundtrip [OPTIONS] [PATTERN]
  oniguruma-parser traverse [OPTIONS] [PATTERN]
  oniguruma-parser optimize [OPTIONS] [PATTERN]

Pattern input:
  PATTERN                         Oniguruma pattern body as one argument
  -i, --input FILE                Read the complete pattern from FILE; use - for stdin

Oniguruma options:
  -f, --flags FLAGS               Top-level Oniguruma flags; default empty
      --capture-group             Enable the captureGroup compile-time rule
      --singleline                Enable the singleline compile-time rule

Optimizer-only options:
      --allow-orphan-backrefs     Skip orphan-backreference validation
      --disable-optimization NAME Disable one optional transform; repeatable
```

Patterns are bodies, not slash-delimited literals. Choose one positional pattern,
one complete file, or stdin. File and stdin bytes are decoded as strict UTF-8 and
are not trimmed or split; empty patterns, NUL, whitespace, and final newlines are
preserved. Top-level flags are separate and passed unchanged. Supported atoms are
`i`, `m`, `x`, `D`, `P`, `S`, `W`, `y{g}`, and `y{w}`; Oniguruma `m` means dotAll,
not multiline anchors. `--singleline` separately changes `^` and `$` assertions.

All successful output is two-space-indented JSON. Unbounded quantifier maxima use
the string `"Infinity"` so JSON does not lose them as `null`.

```console
$ npm run --silent oniguruma-parser -- roundtrip 'a{1,}'
{
  "pattern": "a+",
  "flags": ""
}

$ printf %s '^.*' | npm run --silent oniguruma-parser -- traverse
{
  "total": 6,
  "byType": {
    "Alternative": 1,
    "Assertion": 1,
    "CharacterSet": 1,
    "Flags": 1,
    "Quantifier": 1,
    "Regex": 1
  }
}

$ npm run --silent oniguruma-parser -- optimize \
    '(?x) (?:\!{1,}) (\b(?:ark|arm|art)\b) [[^0-9A-Fa-f]\P{^Nd}\p{ Letter }]'
{
  "pattern": "!+\\b(ar[kmt])\\b[\\H\\d\\p{L}]",
  "flags": ""
}
```

Optimization names are validated against the installed package before individual
transforms can be disabled. The parser models Oniguruma 6.9.10 and Unicode 16.0.0;
it intentionally rejects conditionals, non-built-in callouts, and other rare syntax.
It parses and transforms syntax only: it does not execute Oniguruma regexes, convert
them to JavaScript, infer patterns, generate matches, expose arbitrary visitors, or
accept mutable AST JSON.

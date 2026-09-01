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

The Node commands share one root manifest and lockfile. With Node 20 or newer,
install the exact project-local dependency graph with npm:

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

## grex-js

`bin/grex-js` passes literal positive examples to the WebAssembly-backed
`@pemistahl/grex` 1.0.2 `RegExpBuilder` and prints its inferred regex source.

```text
Usage: grex-js [OPTIONS] [TEST_CASE...]

Input:
  TEST_CASE...                    Literal positive examples as separate arguments
  -i, --input FILE                Read LF/CRLF-delimited examples; use - for stdin

Character generalization:
      --digits / --non-digits
      --whitespace / --non-whitespace
      --words / --non-words

Repetitions:
      --repetitions
      --min-repetitions N         Range 1 through 4294967295
      --min-substring-length N    Range 1 through 4294967295

Rendering and matching semantics:
      --ignore-case
      --capture-groups
      --escape-non-ascii MODE     code-point or surrogate-pair
      --verbose
      --no-start-anchor
      --no-end-anchor
      --no-anchors
```

Choose positional examples, one input file, or stdin. File and stdin records are
strict UTF-8 and LF-delimited, with CR removed only when it precedes LF. Interior
empty records are preserved, a final delimiter adds no phantom example, and a
zero-byte source remains an empty list (which upstream rejects). One empty example
is distinct and successfully produces `^$`. The wrapper does not sort, deduplicate,
trim, or parse the literal examples.

```console
$ npm run --silent grex-js -- hello world
^(?:hello|world)$

$ printf '%s\n' a aa 123 | npm run --silent grex-js -- --digits --words
^(?:\d\d\d|\w(?:\w)?)$

$ npm run --silent grex-js -- --repetitions \
    --min-substring-length 2 aa bcbc defdefdef
^(?:aa|(?:bc){2}|(?:def){3})$

$ npm run --silent grex-js -- \
    --escape-non-ascii surrogate-pair 'You smell like 💩.'
^You smell like \u{d83d}\u{dca9}\.$
```

The six character conversions deliberately generalize beyond the supplied examples;
their overlap precedence is defined by upstream. Repetition thresholds are valid
only with `--repetitions`. The result is anchored by default, while the three anchor
switches exercise the corresponding builder methods.

Output is PCRE-oriented Unicode 15.0 source and is only mostly compatible with
JavaScript `RegExp`: case-insensitive and verbose modes emit leading `(?i)` and
`(?x)`, and Unicode escape support depends on the consumer's dialect. The command
does not accept negative examples or existing regexes, execute matches, optimize an
input regex, generate matching text, or rewrite the source returned by upstream.

## regex-trie-js

`bin/regex-trie-js` exercises the literal prefix trie in regex-trie 1.0.4. It can
print the generated JavaScript regex body, check exact trie membership, or test
candidate text with the generated regex.

```text
Usage:
  regex-trie-js build [OPTIONS] [PHRASE...]
  regex-trie-js contains [OPTIONS] [PHRASE...]
  regex-trie-js match [OPTIONS] [PHRASE...]

Phrase input:
  PHRASE...                        Literal phrases as separate arguments
  -i, --input FILE                Read LF/CRLF-delimited phrases; use - for stdin

Candidate input for contains/match:
  -c, --candidate TEXT            Candidate text; repeatable
  -C, --candidate-input FILE      Read LF/CRLF-delimited candidates; use - for stdin
```

Choose positional phrases, one phrase file, or stdin. `contains` and `match` also
require either repeatable candidate arguments or one candidate file. At most one
source can consume stdin. File and stdin records use strict UTF-8; LF and CRLF are
delimiters, an unterminated final record is retained, and interior blank records are
preserved. Empty phrases and duplicate phrases are passed to the library unchanged;
upstream ignores empty phrases and suppresses duplicates. Input is never sorted.

```console
$ npm run --silent regex-trie-js -- build foo bar baz
(?:foo|ba[rz])

$ printf '%s\n' f fo fox | npm run --silent regex-trie-js -- build
f(?:ox?)?

$ npm run --silent regex-trie-js -- contains \
    --candidate foo --candidate food foo bar baz
{"candidate":"foo","contains":true}
{"candidate":"food","contains":false}

$ npm run --silent regex-trie-js -- match \
    --candidate foo --candidate food --candidate bat foo bar baz
{"candidate":"foo","matches":true}
{"candidate":"food","matches":true}
{"candidate":"bat","matches":false}
```

`contains` is exact membership, while `match` uses `toRegExp()` and therefore
performs case-sensitive, unanchored substring matching with no flags. The `build`
output is the constructor-ready pattern body from `toString()`, not a slash-delimited
regex literal. All inputs are literal phrases; the command does not accept or optimize
existing regexes, add anchors, generate matching text, or promise globally minimal
output.

Rendering is observably order-sensitive: `a b` produces `[ab]` and `b a` produces
`[ba]`, while integer-like trie keys follow JavaScript enumeration rules (`9 1`
produces `[19]`). The old jsesc dependency renders non-ASCII text as escapes such as
`caf\xE9`, `\uD83D\uDCA9`, and `\u6F22\u5B57`.

Two upstream control-character defects are intentionally preserved. Backspace is
rendered as `\b`, which JavaScript interprets as a word boundary, and NUL followed by
digits 1 through 7 can become a legacy octal escape such as `\01`; generated matching
can therefore fail for those original phrases. The recursive upstream renderer can
also exhaust the JavaScript stack on a sufficiently long phrase. This exploratory CLI
normalizes that error, but it is not a CPU, memory, or recursion-isolation boundary.

## Python setup

The Python commands share one uv project, require Python 3.10 or newer, and keep the
interpreter environment in the ignored `.venv/` directory. Install only the exact
versions and Git commits recorded by `uv.lock`:

```sh
uv sync --frozen
```

Run the commands through uv so the locked project environment is selected even when
the current working directory is outside this checkout.

## regexfinder

`bin/regexfinder` exercises the graph and matching APIs from the modernized
`mevanlc/regexfinder` fork, pinned to commit
`88b50c683f77c68ff232f75e111ea6650940c4b5`. That fork packages the original
clockworkmicro algorithms for Python 3.10+ without replacing them.

```text
Usage:
  regexfinder analyze [OPTIONS] PATTERN
  regexfinder optimize [OPTIONS] PATTERN
  regexfinder search [OPTIONS] PATTERN [TEXT...]

Graph options for analyze/optimize:
  -a, --alpha NUMBER               Non-negative finite objective weight; default 1

Search input:
  TEXT...                          Candidate strings as separate arguments
  -i, --input FILE                 Read LF/CRLF-delimited candidates; use - for stdin
  -b, --boolean                    Report only whether each candidate has a match

Optimization diagnostics:
  -v, --verbose                    Replay captured upstream diagnostics on stderr
```

Patterns are Python regex bodies, not slash-delimited literals. Search candidates
come from positional arguments, one strict-UTF-8 record file, or stdin. LF and CRLF
delimit records; interior empty records, duplicates, order, whitespace, controls, and
an unterminated final record are preserved.

```console
$ uv run --frozen -- ./bin/regexfinder analyze '[ab]'
{"input_regex":"[ab]","alpha":1.0,"graph":{"out_regex":"[ab]","cardinality":2,"log2_cardinality":2.0,"entropy":1.0,"complexity":4,"phi":6.0}}

$ uv run --frozen -- ./bin/regexfinder optimize 'a(b|c)d'
{"input_regex":"a(b|c)d","alpha":1.0,"before":{"out_regex":"a(b|c)d","cardinality":2,"log2_cardinality":1.0,"entropy":1.0,"complexity":7,"phi":8.0},"after":{"out_regex":"a[bc]d","cardinality":2,"log2_cardinality":1.0,"entropy":1.0,"complexity":6,"phi":7.0},"changed":true}

$ printf 'car\ndog\n' | uv run --frozen -- ./bin/regexfinder search --boolean 'ca[rt]'
{"text":"car","matched":true}
{"text":"dog","matched":false}
```

`analyze` reports the library's direct properties, including its known leaf-graph
bug: `[ab]` reports `log2_cardinality` as 2.0 rather than 1.0. `optimize` calls
`reducePhi()` once. Phi reduction may broaden the accepted language; it is not an
equivalence-preserving canonicalizer. Unsolicited upstream debug output is suppressed
unless `--verbose` replays it on stderr.

`search` calls `NODE.match()` and exposes Python search spans; it does not use the
graph renderer. Graph analysis supports only a hand-written ASCII-oriented subset of
Python regex syntax and cannot assign finite cardinality to `*` or `+`. The advertised
random-string property is defective, the only visualization API writes a PDF and
launches a viewer, and the unfinished word collector is not stable sample inference,
so none is exposed. This wrapper does not repair those behaviors or isolate CPU,
memory, or regex-backtracking risks.

## triegex

`bin/triegex` exercises ZhukovAlexander/triegex 0.0.4 at immutable commit
`85a25240b8821c2da257e6f6b784023e56a5b680`. The unpublished Git release needs a
temporary `collections.MutableSet` compatibility alias on modern Python; the command
installs that alias only while importing the package and restores the previous state.

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
```

Word and candidate files use the same strict-UTF-8 record rules as `regexfinder`.
`build` writes the exact `to_regex()` result; `contains` checks exact terminal
membership without generating a regex; and `match` compiles the generated source with
Python `re` and reports either detailed spans or booleans.

```console
$ uv run --frozen -- ./bin/triegex build foo bar baz
(?:ba(?:r\b|z\b)|foo\b|~^(?#match nothing))

$ uv run --frozen -- ./bin/triegex contains foo bar --candidate foo --candidate food
{"candidate":"foo","contains":true}
{"candidate":"food","contains":false}

$ printf 'food foo bar!\nnone\n' | \
    uv run --frozen -- ./bin/triegex match foo bar --candidate-input - --boolean
{"candidate":"food foo bar!","matched":true}
{"candidate":"none","matched":false}
```

Rendering is deterministic and sorted, and always includes the
`~^(?#match nothing)` branch. Every terminal word receives `\b`, so matching is
case-sensitive and unanchored but requires a trailing Unicode word boundary. A word
ending in punctuation or emoji can therefore be contained without matching itself.

Inputs are inserted as raw regex syntax, not escaped literals: `a.b` can match `axb`,
`a*b` can match `b`, and unmatched `(` or `[` can make `match` fail even though
`build` and `contains` succeed. The command deliberately does not expose the package's
defective iterator or `discard()` behavior. It also does not optimize existing regexes,
generate matching text, add flags, provide safe-literal inference, or isolate resource
use and regex backtracking.

## retrie

`bin/retrie` exercises the public APIs in the published retrie 0.3.1 wheel. Unlike
triegex, retrie treats keys as literals and escapes regex syntax before producing a
deterministic, sorted Python regex.

```text
Usage:
  retrie build [OPTIONS] [KEY...]
  retrie check MODE [OPTIONS] [KEY...]
  retrie filter MODE [OPTIONS] [KEY...]
  retrie cleanse MODE [OPTIONS] [KEY...]
  retrie replace [OPTIONS]

Modes for check/filter/cleanse:
  blacklist | whitelist

Key and candidate input:
  -i, --input FILE                 Read LF/CRLF-delimited keys; use - for stdin
  -c, --candidate TEXT             Candidate text; repeatable
  -C, --candidate-input FILE       Read LF/CRLF-delimited candidates; use - for stdin

Whole-text and replacement input:
  -t, --text TEXT                  Use one complete text argument
  -T, --text-input FILE            Read one complete text; use - for stdin
  -r, --replacement OLD NEW        Add one replacement pair; repeatable
  -R, --replacement-input FILE     Read JSON Lines pairs; use - for stdin
  -n, --count NUMBER               Maximum replacements; 0 means all; default 0

Matching options:
  -s, --substring                  Match inside words instead of at word boundaries
  -S, --case-sensitive             Disable default case-insensitive matching
```

Key and candidate files use strict-UTF-8 record input. `cleanse` and `replace` instead
read one complete text without trimming or newline normalization. Replacement files
are JSON Lines objects containing exactly two string properties, `old` and `new`, so
mapping strings can contain newlines, NUL, and other controls. At most one source can
consume stdin.

```console
$ uv run --frozen -- ./bin/retrie build abc foo abs
(?:ab[cs]|foo)

$ uv run --frozen -- ./bin/retrie check blacklist foo \
    --candidate foobar --candidate 'a foo bar'
{"candidate":"foobar","blacklisted":false}
{"candidate":"a foo bar","blacklisted":true}

$ printf 'good\nABC\nfoobar\n' | \
    uv run --frozen -- ./bin/retrie filter whitelist abc foo abs --candidate-input -
{"candidate":"ABC"}

$ uv run --frozen -- ./bin/retrie cleanse blacklist abc foo abs \
    --text 'good ABC foobar'
good  foobar

$ uv run --frozen -- ./bin/retrie replace \
    --replacement abc new1 --replacement foo new2 --replacement abs new3 \
    --text 'ABS ...foo... foobar'
new3 ...new2... foobar
```

`build` calls `Trie.pattern()` and appends one newline. A zero-key or single-empty-key
trie renders an empty pattern; empty plus `foo` renders `(?:foo)?`. `check` calls the
mode-specific membership method, and `filter` consumes the corresponding upstream
iterator. Blacklists retain unlisted candidates, while whitelists retain listed ones.

Matching is case-insensitive Unicode search at word boundaries by default. `--substring`
removes the boundaries and `--case-sensitive` passes no regex flags. Blacklist cleansing
removes matches; whitelist cleansing concatenates only matches, discarding separators.
These raw text operations add no final newline.

Replacement uses one `Replacer` and one `replace()` call, so mappings are applied as a
single regex substitution rather than sequential `str.replace` calls. Distinct default-
mode keys that collide after lowercasing retain upstream's ambiguous-mapping error.
Empty checklists also retain upstream's `\b\b` behavior and can list word-containing
text. Deep keys can exhaust Python recursion. The wrapper does not optimize existing
regexes, accept negative examples, generate matching text, or isolate recursion,
backtracking, CPU, or memory use.

## JVM setup

The Frak exercise requires JDK 17 or newer plus `curl`, `tar`, `sed`, `mktemp`, and
either `sha256sum` or `shasum`. Bootstrap the pinned official Clojure CLI and prepare
the runtime from the repository root:

```sh
./tools/bootstrap-clojure
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Srepro -P -M:frak
./tools/verify-jvm-deps
```

The bootstrap installs Clojure CLI 1.12.5.1664 beneath ignored `.deps/clojure` and
validates the downloaded archive before installing it. `deps.edn` resolves exactly
five runtime JARs beneath `.deps/m2`: Clojure 1.12.5, spec.alpha 0.5.238,
core.specs.alpha 0.4.74, tools.cli 0.3.1, and Frak 0.1.9. Frak's obsolete Clojure
and unused ClojureScript dependencies are excluded. `tools/verify-jvm-deps` checks
every JAR against `jvm-deps.sha256` and rejects unlisted JARs.

`-Srepro` excludes user Clojure configuration. Project configuration and dependency
artifacts stay under `.deps`, while Clojure's ignored classpath cache stays in
`.cpcache`. Once the tooling and five JARs are prepared, both the cached bootstrap
and normal Frak invocation work without network access. No global Clojure or
Leiningen installation is required.

## Frak

This project invokes the published Frak 0.1.9 CLI directly; there is no `bin/frak`
wrapper or argument/output adapter.

```text
Usage: frak <flags*> <strings+>

Flags:
  -e, --exact                      Generated pattern requires an exact match
  -c, --capture                    Generated pattern captures
  -E, --escape-chars :KEY|'CHARS'  Set of characters to escape in generated pattern
  -h, --help                       Display this help message
```

Use the full invocation from the repository root so Clojure finds `deps.edn` and its
relative local repository:

```console
$ CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
    ./.deps/clojure/bin/clojure -Srepro -M:frak -e foo foot
^foot?$

$ CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
    ./.deps/clojure/bin/clojure -Srepro -M:frak foo bar baz quux
(?:quux|foo|ba[zr])

$ CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
    ./.deps/clojure/bin/clojure -Srepro -M:frak -E :vim 'a-b'
a\-b
```

Each positional argument is one positive literal sample. Shell quoting can preserve
empty strings, spaces, embedded newlines, Unicode, and metacharacters, but Java argv
cannot carry NUL and is subject to the operating system's argument-size limit. Frak
does not read stdin or files. Use Frak's `--` to end option parsing when a sample such
as `-e` begins with a hyphen.

`--exact` anchors the complete generated source with `^` and `$`. `--capture` makes
only groups required by upstream factoring capturing. `--escape-chars` replaces the
default escape set: `:default` restores it, `:vim` selects the Vim very-magic set,
and a literal value supplies the complete replacement set. An empty value or unknown
keyword disables escaping, which can produce broader or invalid regex source while
still exiting successfully because the CLI does not compile its output.

The rendered regex is language-oriented, not canonically spelled. Alternative and
character-class order can vary between runtimes, so compare branching results by
matching semantics rather than exact text. Duplicate inputs collapse; empty inputs
are ignored beside nonempty ones, while a lone empty input emits an empty pattern
(`^$` with `--exact`). Successful output is raw regex source plus one newline.

Frak infers regexes only from positive literal examples. Its CLI has no version or
whole-word flag, negative samples, matching/search operation, matching-text generator,
or existing-regex optimizer. The library has a whole-word option, but the published
CLI does not expose it.

Run the direct-process, bootstrap, dependency-integrity, and prepared-offline checks
with:

```sh
./test/frak_cli_test.sh
```

## Rust setup

The Rust exercises use the exact rustup toolchain declared in `rust-toolchain.toml`.
Install it once, then prepare the locked dependency graph inside this checkout:

```sh
rustup toolchain install 1.87.0 --profile minimal --component rustfmt --component clippy
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 fetch --locked
```

Cargo registry data stays beneath ignored `.cargo-home/`, and builds stay beneath
ignored `target/`. The rustup-managed compiler itself may use the normal rustup home.

## regextrie (Rust)

`bin/regextrie-rust` exercises regextrie 0.1.0 through one trie construction and one
public query per candidate. The project uses a custom CLI because upstream's binary is
only a hard-coded demonstration.

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

Choose positional patterns, one pattern file, or implicit pattern stdin. Both commands
also require repeated candidate arguments or one candidate file. At most one source may
use stdin. File and stdin sources are strict UTF-8 LF/CRLF records: delimiters are
removed without otherwise trimming data, a final delimiter adds no phantom record, and
NUL is preserved. A zero-byte pattern source is a valid empty pattern list, while one
blank record is one empty pattern. A zero-byte candidate source is an error.

```console
$ ./bin/regextrie-rust matches 'a.*' 'a[0-9]+b.*' a123bbb \
    --candidate a123bbb --candidate xa123bbb
{"candidate":"a123bbb","matched":true,"matches":["a.*","a123bbb","a[0-9]+b.*"]}
{"candidate":"xa123bbb","matched":false,"matches":[]}

$ ./bin/regextrie-rust best 'a.*' 'a[0-9]+b.*' a123bbb --candidate a123bbb
{"candidate":"a123bbb","matched":true,"best":"a123bbb","scorer":"library-default"}
```

`matches` calls `find_matches()` and sorts only its returned strings for deterministic
JSON Lines; duplicate regex results remain duplicated. `best` calls
`find_best_match()`. Its default scorer prioritizes a matching plain string and then a
shorter regex. The custom modes score the shortest, longest, or first input pattern.
Equal-score best matches remain upstream-order-dependent except in `input-order` mode.

The crate's regex classifier and full-match check have important limitations. It
accepts a regex only when the first leftmost match spans the complete candidate, so
`(a|aaa)` does not match `aaa`, while `(aaa|a)` does. Operators `^`, `$`, and `|` are
not classifier metacharacters, making `^foo$` and `foo|bar` plain strings. Regex escapes
such as `\b` and `\s` can be indexed as literal prefix characters and miss otherwise
matching candidates. These behaviors are preserved rather than corrected by another
regex engine.

The command does not infer, combine, or optimize regexes, generate matching text, or
expose spans and captures. Trie construction may use Rayon threads and is not a CPU,
memory, DFA-size, or input-size sandbox.

Validate the custom command with:

```sh
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 check --locked --all-targets
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 nextest run --locked
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 fmt --check
CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 clippy --locked --all-targets -- -D warnings
```

## grex (Rust)

The maintained native grex CLI already exposes the library's inference features, so
this project installs and invokes it directly without a wrapper:

```sh
./tools/install-grex-rust
./.cargo-home/bin/grex --version
```

The installer uses Rust 1.87.0 and the published package lock to install exact crates.io
release 1.4.6 beneath `.cargo-home`. It validates Cargo's install metadata and the
native version, and a valid cached installation succeeds quietly without network
access. The `grex-1.4.6.crate` archive has SHA-256
`4ada730ccbcaf2eaaf9d254661960b0211e042e031e307ba8fd39821307f46dd`
and records upstream commit `db9275ace11ad455700656c6186e0d69f6107870`.

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

```console
$ ./.cargo-home/bin/grex a aa aaa
^a(?:aa?)?$

$ printf '123\n٤٥٦\n' | ./.cargo-home/bin/grex --digits -
^\d\d\d$

$ ./.cargo-home/bin/grex --repetitions aa bcbc defdefdef
^(?:a{2}|(?:bc){2}|(?:def){3})$

$ ./.cargo-home/bin/grex --escape --with-surrogates '💩'
^\u{d83d}\u{dca9}$
```

Inputs are positive literal examples, not regex source. Grex sorts them internally,
builds and minimizes a DFA, and emits one anchored Rust-dialect regex plus a final
newline. Duplicates and input order do not change the accepted language. Empty records
beside nonempty examples are ignored by release 1.4.6; a source containing one empty
record alone is valid and emits `^$`, while a zero-byte file or pipe reaches the native
nonempty-input panic.

Options must precede the first positional example because the positional operand is
greedy. After that point, known option spellings are literal samples; an unknown leading
hyphen token is also accepted as a sample. A sole `-` reads example records from
non-terminal stdin but is a literal sample on a terminal. `--file -` instead trims stdin
and treats it as a filename. Relative file paths use the caller's working directory.
Files and pipes accept LF/CRLF records and can carry NUL; invalid UTF-8 through a file is
a handled error, while invalid piped UTF-8 follows the native panic path.

The six shorthand flags deliberately generalize beyond supplied examples. Repetition
thresholds take effect only with `--repetitions`. Output is anchored, case-sensitive,
and noncapturing by default; the case, group, anchor, verbose, escape, surrogate, and
color controls retain their native behavior. `--colorize` emits ANSI even to captured
stdout, and surrogate output is not valid Rust Unicode-scalar regex syntax.

Native help/version exit 0, Clap usage errors exit 2, handled file failures exit 1, and
builder/input or broken-pipe panics normally exit 101. There is no project diagnostic
prefix or JSON mode. Grex does not accept negative examples, optimize an existing regex,
generate matching text, search candidate text, or expose its automaton.

## Native C/C++ setup

The native exercises use the shared root CMake project. They require CMake 3.24 or
newer and a C compiler. TRE additionally requires a POSIX host with `/bin/sh`, `make`,
Autoconf, Automake, gettext's `autopoint`, and GNU libtool (`glibtoolize` on macOS).
The default RegexTrie and TRE graph does not use Conan; opt-in Hyperscan has a separate
C++/Conan setup below. Configure, build, and test the default Debug targets with:

```sh
cmake -S . -B build/native \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DREGEX_UTILS_ENABLE_SANITIZERS=OFF
cmake --build build/native --parallel
ctest --test-dir build/native --output-on-failure
cmake --build build/native --target tre-upstream-check
```

The first build downloads immutable RegexTrie and TRE commit archives into the ignored
build tree. CMake verifies their respective SHA-256 values
`ed0e39fb3359927ff74f0a552a85e96371898ada82ca483fb68a115a73e7133c` and
`8f630500dcd10ad5c086e3e8e851888107ecca93c384793f856384c6a5c19664`.
Subsequent builds reuse those sources without a global library installation. Set
`REGEX_UTILS_BUILD_REGEXTRIE_C=OFF` or `REGEX_UTILS_BUILD_TRE=OFF` to omit that
library's fetch, host-tool checks, targets, and tests. The complete upstream TRE suite is
behind the non-default `tre-upstream-check` target because its limit test is slow.

For an ASan/UBSan build on Clang or GCC:

```sh
cmake -S . -B build/native-sanitize \
  -DCMAKE_BUILD_TYPE=Debug \
  -DREGEX_UTILS_ENABLE_SANITIZERS=ON
cmake --build build/native-sanitize --parallel
ASAN_OPTIONS=detect_leaks=0 \
  ctest --test-dir build/native-sanitize --output-on-failure
```

Use `detect_leaks=0` only on macOS, where this sanitizer runtime lacks LeakSanitizer.

## Hyperscan setup

The Hyperscan exercise is deliberately separate from `build/native`. It supports only
x86_64 macOS or Linux with SSSE3. On Apple Silicon, Apple Clang cross-builds x86_64 and
the launcher runs it explicitly through Rosetta 2. Windows, 32-bit targets, Arm Linux,
and Linux cross-builds from non-x86 hosts are rejected. This is Intel Hyperscan, not the
Arm-capable Vectorscan fork.

The package recipe builds immutable source tag `v5.4.2.1` (commit
`809f09b611e8da52b377481c14db575bf2625fad`) from an archive with SHA-256
`7119ef2db45c98abd816ba789aae82fdfd1a0b240bb40a88bac2d90933a346df`. Upstream's
internal constants remain 5.4.2; `SOURCE_DATE_EPOCH` makes its runtime version
reproducibly report `5.4.2 2026-08-26`. The checked lock also fixes Boost 1.83.0
headers, static OpenSSL Crypto 3.5.8, and build-time Ragel 6.10 recipe revisions.

Conan 2.31.2 runs only through `uvx`, stores its cache in ignored `.conan2/`, and
generates consumer files under `build/hyperscan/conan/`. From a clean checkout:

```sh
CONAN_HOME="$PWD/.conan2" \
  uvx --from conan==2.31.2 conan profile detect --force

CONAN_HOME="$PWD/.conan2" \
  uvx --from conan==2.31.2 conan create conan/recipes/hyperscan \
    --profile:host=conan/profiles/hyperscan-x86_64 \
    --profile:build=default \
    --lockfile=conan.lock \
    --build=missing

CONAN_HOME="$PWD/.conan2" \
  uvx --from conan==2.31.2 conan install . \
    --profile:host=conan/profiles/hyperscan-x86_64 \
    --profile:build=default \
    --lockfile=conan.lock \
    --build=missing

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

The local recipe produces static `libhs.a`, four public headers, and the BSD license.
It uses C++11 and the Core2/SSSE3 baseline with generic tuning, disables fat runtime,
AVX2/AVX-512 variants, Chimera, tools, examples, dumps, and unrelated tests, and links
static OpenSSL Crypto transitively. Upstream warnings remain visible but nonfatal;
project-owned C++ is built with warnings denied. The fixed normal launcher never
rebuilds or searches `PATH`:

```console
$ ./bin/hyperscan --version
hyperscan v5.4.2.1 (Hyperscan 5.4.2 2026-08-26)
```

For the separate ASan/UBSan package and consumer graph:

```sh
CONAN_HOME="$PWD/.conan2" \
  uvx --from conan==2.31.2 conan create conan/recipes/hyperscan \
    --profile:host=conan/profiles/hyperscan-x86_64 \
    --profile:build=default \
    --lockfile=conan.lock \
    -o:h 'hyperscan/*:sanitizers=True' \
    --build=missing

CONAN_HOME="$PWD/.conan2" \
  uvx --from conan==2.31.2 conan install . \
    --profile:host=conan/profiles/hyperscan-x86_64 \
    --profile:build=default \
    --lockfile=conan.lock \
    -o:h '&:sanitizers=True' \
    -o:h 'hyperscan/*:sanitizers=True' \
    --build=missing

cmake -S . -B build/hyperscan-sanitize \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=build/hyperscan-sanitize/conan/conan_toolchain.cmake \
  -DREGEX_UTILS_ENABLE_SANITIZERS=ON \
  -DREGEX_UTILS_BUILD_REGEXTRIE_C=OFF \
  -DREGEX_UTILS_BUILD_TRE=OFF \
  -DREGEX_UTILS_BUILD_HYPERSCAN=ON
cmake --build build/hyperscan-sanitize --parallel
ASAN_OPTIONS=detect_leaks=0 \
REGEX_UTILS_HYPERSCAN_SKIP_RESOURCE_TESTS=1 \
  ctest --test-dir build/hyperscan-sanitize --output-on-failure
```

Use `detect_leaks=0` only for the macOS sanitizer runtime. Populated locked caches can
be verified offline by adding `--no-remote` to `conan create` and `conan install`.

## Intel Hyperscan

`bin/hyperscan` compiles ordered regexes or byte literals into one database and either
scans a binary subject or reports compiled resource sizes. Pattern IDs are stable,
one-based source positions.

```text
Usage:
  hyperscan scan [PATTERN_OPTIONS] [SCAN_OPTIONS]
  hyperscan info [PATTERN_OPTIONS]
  hyperscan --help
  hyperscan --version

Pattern source (choose one):
  -e, --expression PATTERN       Add one pattern; repeatable
  -f, --expression-file FILE     Read LF-delimited patterns from FILE

Compilation:
      --literal                  Compile byte literals instead of regexes
      --mode MODE                block, stream, or vectored [default: block]
  -i, --caseless                 Case-insensitive matching
  -s, --dotall                   Make dot match newlines
  -m, --multiline                Enable multiline anchors
      --single-match             Report at most one match per pattern
      --allow-empty              Permit regexes that match empty input
      --utf8                     Enable strict UTF-8 mode
      --ucp                      Enable Unicode properties; requires --utf8
      --prefilter                Permit false-positive prefilter matches
      --som-leftmost             Report leftmost start offsets
      --som-horizon HORIZON      small, medium, or large for stream SOM
      --min-offset N             Minimum match end offset
      --max-offset N             Maximum match end offset
      --min-length N             Minimum match length
      --edit-distance N          Experimental edit distance
      --hamming-distance N       Experimental Hamming distance

Scan input:
      --input FILE               Read binary subject; - is stdin [default]
      --text TEXT                Use exact argument bytes as the subject
      --chunk-size N             Stream/vector chunk bytes [default: 4096]
      --max-matches N            Event limit [default: 100000]
```

Expression files are binary LF records. One CR immediately before an LF is removed;
all other bytes, whitespace, empty records, and NUL are preserved. A zero-byte file is
an error. Regex mode rejects NUL because its upstream API takes C strings. Literal mode
passes explicit lengths, supports NUL, and accepts only caseless, single-match, SOM, and
mode options. Duplicates are preserved. Limits are 10,000 patterns, 8,192 bytes per
pattern, and 8 MiB cumulatively.

`scan` pre-reads one exact subject from `--text`, a named binary file, or stdin. It
preserves NUL and invalid byte sequences unless `--utf8` requests strict validation,
and caps the subject at 256 MiB. Block mode scans once. Vectored mode passes chunks as
one logical subject, and stream mode retains state across chunks and closes the stream
with callbacks enabled for end-of-data matches. Chunk size is positive and valid only
for stream/vector modes.

```console
$ ./bin/hyperscan scan -e foo -e 'ba[rz]' --text 'xxfoobar baz'
{"id":1,"start":null,"end":5,"start_status":"disabled"}
{"id":2,"start":null,"end":8,"start_status":"disabled"}
{"id":2,"start":null,"end":12,"start_status":"disabled"}

$ printf 'xxfoobar' | ./bin/hyperscan scan -e 'foo.*bar' \
    --mode stream --chunk-size 3 --som-leftmost
{"id":1,"start":2,"end":8,"start_status":"available"}

$ ./bin/hyperscan scan -e colour --edit-distance 1 --text color
{"id":1,"start":null,"end":5,"start_status":"disabled"}

$ ./bin/hyperscan info -e foo -e 'ba[rz]' --mode stream
{"source_tag":"v5.4.2.1","library_version":"5.4.2 2026-08-26","compile_kind":"regex","mode":"stream","patterns":2,"database_bytes":4992,"scratch_bytes":2317,"stream_bytes":20}
```

Resource sizes vary by compiler and platform. Match output is compact JSON Lines in
Hyperscan callback order. `end` is an exclusive byte offset. Without SOM, `start` is
honestly `null`/`disabled`; with SOM it is a byte offset or `null`/`past_horizon` for a
small or medium streaming horizon. Output does not invent matched text or captures.
The command buffers all events, stops at `--max-matches` plus one, and emits no partial
stdout on failure. EPIPE is quiet.

Hyperscan syntax is PCRE-like, not PCRE-equivalent. It has no captures in callbacks,
backreferences, recursion, arbitrary assertions, atomic groups, or possessive
quantifiers. It can report multiple end positions, does not promise global callback
ordering, and SOM costs memory and performance. Prefilter deliberately produces a
superset and this CLI does not add an exact confirmer. Edit and Hamming distance are
mutually exclusive, experimental, and potentially expensive. UCP requires UTF-8;
malformed UTF-8 patterns and subjects are rejected before the library is called.

Help/version and valid scans (including no matches) exit 0. Usage, local bounds,
invalid UTF-8, and compile errors exit 2. Platform, file, allocation, runtime, output,
and match-limit failures exit 1. Diagnostics are prefixed `hyperscan:` and never echo
raw pattern bytes.

The CLI does not rewrite regex source, infer regexes from samples, generate matching
text, expose captures, implement logical combinations, confirm prefilter results, or
serialize databases.

## RegexTrie (C)

`bin/regextrie-c` launches only `build/native/bin/regextrie-c`; it never configures or
builds implicitly. The custom CLI maps directly to pinned upstream calls for trie
creation, `add_word()` or `add_regex()`, `find_word()`, and cleanup.

```text
Usage:
  regextrie-c [OPTIONS] [WORD...]

Dictionary input:
  WORD...                         Dictionary records as separate arguments
  -i, --input FILE                Read LF/CRLF-delimited dictionary records;
                                  use - for stdin
  -m, --insert-mode word|regex    Call add_word or add_regex [default: regex]

Queries:
  -q, --query QUERY               Query with find_word; repeatable
  -Q, --query-input FILE          Read LF/CRLF-delimited queries; use - for stdin

Other:
  -h, --help                      Show help
  -V, --version                   Show wrapper and pinned source versions
```

Choose exactly one dictionary source and one query source; at most one may be stdin.
Files use strict UTF-8 LF/CRLF records without trimming other bytes. A final delimiter
adds no phantom record, interior empty records are preserved, and a zero-byte dictionary
creates an empty trie. A zero-record query source is an error. Embedded NUL is rejected
because upstream uses C strings.

```console
$ ./bin/regextrie-c -q foo -q '?oo' -q '???' -q qux -- foo bar
{"query":"foo","found":true,"insert_mode":"regex"}
{"query":"?oo","found":true,"insert_mode":"regex"}
{"query":"???","found":true,"insert_mode":"regex"}
{"query":"qux","found":false,"insert_mode":"regex"}

$ ./bin/regextrie-c --insert-mode word -q foo -q FOO -q '&//' -q '?oo' -- foo
{"query":"foo","found":true,"insert_mode":"word"}
{"query":"FOO","found":true,"insert_mode":"word"}
{"query":"&//","found":true,"insert_mode":"word"}
{"query":"?oo","found":false,"insert_mode":"word"}
```

This library is not a conventional regex engine. It reduces every byte to one of 32
classes. Consequently ASCII case collides, `foo`, `FOO`, and `&//` share a path, `?`
collides with `_`, and `@` collides with the terminal slot. UTF-8 is transported
losslessly but indexed byte by byte rather than by Unicode scalar or grapheme.

Default `regex` mode inserts the original word and every same-length combination made
by replacing byte positions with literal `?` paths. Its setup grows exponentially; the
CLI therefore limits regex-mode records to 16 bytes and cumulative expansion to 65,536
paths. All records are limited to 1,024 bytes and each file/stdin source to 16 MiB. The
entire input and JSON Lines output are preflighted and buffered before upstream work or
the first stdout write.

The command reports each whole-path query as `found`, even when that result comes from
an upstream byte-class collision. It does not parse or emit regex syntax, infer or
optimize regexes, search within subjects, generate matching text, return spans/captures,
or enumerate inserted values. Upstream allocation assertions and recursive cleanup can
still abort under genuine resource exhaustion.

The pinned upstream source has no license declaration. It is fetched only for this
local exercise and must not be redistributed, including in linked binary form, without
permission from its copyright holder.

## TRE `agrep`

TRE is exercised through the upstream CLI installed at exactly:

```text
build/native/tre-install/bin/agrep
```

There is no `bin/` wrapper and the project never searches `PATH` for another command
named `agrep`. The build pins post-release commit
`71bfcaf0af3994384987c6c2679ed7d078ffe189`, while the upstream program still reports
version `0.9.0`:

```console
$ build/native/tre-install/bin/agrep --version
agrep (TRE agrep) 0.9.0
```

The selected command searches TRE extended regular expressions over newline-delimited
records from files or stdin. Exact matching is the default. `-E N` and `-0` through
`-9` enable approximate matching, while `-D`, `-I`, and `-S` set deletion, insertion,
and substitution costs. `-B` rereads named files to emit only their lowest-cost records
and therefore cannot operate on stdin.

```text
Usage: build/native/tre-install/bin/agrep [OPTION]... PATTERN [FILE]...

Pattern:
  -e, --regexp=PATTERN          Supply PATTERN as a TRE ERE
  -i, --ignore-case             Use locale-sensitive case folding
  -k, --literal                 Treat PATTERN as a literal string
  -w, --word-regexp             Require a whole-word match

Approximate matching:
  -E, --max-errors=NUM          Set the maximum total match cost
  -0 ... -9                     Set the maximum cost with one digit
  -D, --delete-cost=NUM         Set the missing-character cost
  -I, --insert-cost=NUM         Set the extra-character cost
  -S, --substitute-cost=NUM     Set the wrong-character cost
  -B, --best-match              Emit only records with the lowest cost

Records and output:
  -d, --delimiter=PATTERN       Use a TRE regex as the record delimiter
  -M, --delimiter-after         Print custom delimiters after records
  -v, --invert-match            Select nonmatching records
  -m, --max-count=NUM           Stop after NUM selected records per input
  -c, --count                   Print selected-record counts
  -l, --files-with-matches      Print only matching file names
  -n, --record-number           Prefix record numbers
  -s, --show-cost               Prefix total match costs
      --show-position           Prefix first-match byte offsets
      --color, --colour         Highlight the first match with ANSI escapes
  -h, --no-filename             Suppress file-name prefixes
  -H, --with-filename           Always print file-name prefixes
  -q, --quiet, --silent         Suppress normal output
```

Approximate search can report record number, total cost, and byte positions together:

```console
$ printf 'optimize\noptimise\noptmise\nopitmize\nother\n' | \
    build/native/tre-install/bin/agrep -2 -n -s --show-position optimize
1:0:0-8:optimize
2:1:0-8:optimise
3:2:0-7:optmise
4:2:0-8:opitmize
```

Costs can differ by edit operation:

```console
$ printf 'abc\naxc\nabbc\nac\n' | \
    build/native/tre-install/bin/agrep -E 2 -I 2 -D 3 -S 4 -s abc
0:abc
2:abbc
```

Patterns may also contain TRE's approximate constraints:

```console
$ printf 'abc\naxc\nabbc\nac\nzzz\n' | \
    build/native/tre-install/bin/agrep -s '(abc){~1}'
0:abc
1:axc
1:abbc
1:ac
```

Input files are searched in operand order, and relative paths belong to the caller's
working directory. The default newline delimiter is excluded from records; `-d` accepts
a TRE regex for custom delimiters and `-M` changes their output placement. A trailing
delimiter creates no phantom empty record. Prefix order is filename, record number,
cost, then position. Positions are byte offsets even in a multibyte locale.

`agrep` calls `setlocale(LC_ALL, "")`, so character classes, case folding, and invalid
multibyte input follow the inherited locale. Set `LC_ALL=C` for deterministic bytewise
ASCII behavior. Matching itself is length-aware and `\x00` can match NUL, but ordinary
record output uses a C-string write and truncates at the first NUL. Use modes such as
`--count`, `--quiet`, or file-name selection when searching binary data.

Native behavior is preserved without validation or status translation. Valid numeric
arguments should be nonnegative base-10 integers, although upstream's `atoi` parsing
accepts values such as `-E nope` as zero and `-E 1junk` as one. A match exits 0 and no
match exits 1. Help/version exit 0; malformed patterns normally exit 2, while an unknown
option, an unreadable sole file, and `-B` on stdin currently exit 1. A missing file can
be masked by a later match, and a closed output pipe terminates through SIGPIPE.

TRE performs exact and approximate search. This CLI does not rewrite or optimize regex
source, infer regexes from samples, generate matching text, emit captures or separate
edit counts, or provide binary-safe record output. Ordinary matching has predictable
subject-length behavior, but regex work grows with pattern size and backreferences can
require exponential time. The selected source rejects patterns longer than 65,536
bytes. A degenerate literal exactly at that maximum compiles in the normal build but
exhausts the instrumented call stack under AddressSanitizer on the validated macOS
build, so the normal CLI suite covers the exact boundary while the sanitizer suite
exercises the practical CLI cases.

The pinned source uses a two-clause BSD-style license. It is built directly with its
Autotools system and installed only beneath `build/native/`. Conan Center's
`tre/cci.20230717` snapshot predates both TRE 0.9.0 and the selected safety fixes while
still requiring the same Autotools stack, so Conan would not improve this setup.

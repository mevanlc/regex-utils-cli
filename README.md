# regex-utils-cli

Project-local command-line exercises for regex-related libraries across several
language ecosystems. Each command stays close to its upstream library's public API;
the implementation plans and verified limitations are under [`devdocs/`](devdocs/).

## Regexp::Optimizer

`bin/regexp-optimizer` compiles one Perl regex body, passes it through
`Regexp::Optimizer` once, and prints the optimized pattern for piping or inspection.

### Setup

Requirements:

- Perl
- `cpanm`

Install the exact dependencies into the ignored project-local `local/` tree:

```sh
cpanm --local-lib-contained local --installdeps .
```

No global Perl modules are required. The executable finds `local/lib/perl5` relative
to its own path, so it can be invoked from another working directory.

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

### Tests

```sh
PERL5LIB=local/lib/perl5 perl -MRegexp::Optimizer -MRegexp::Assemble -e \
  'die unless $Regexp::Optimizer::VERSION eq q{0.23} && $Regexp::Assemble::VERSION eq q{0.38}'
perl -c bin/regexp-optimizer
prove -v t/regexp-optimizer.t
```

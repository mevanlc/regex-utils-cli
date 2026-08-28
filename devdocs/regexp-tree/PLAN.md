# Plan: regexp-tree CLI Exercise

## Summary

Install the official `regexp-tree-cli` npm package project-locally and invoke its
native `regexp-tree-cli` command through an npm script. Do not create a redundant
`bin/` wrapper: the upstream command already exposes parsing, location capture,
optimization, compatibility transpilation, and finite-automaton tables.

The upstream packaging is split. The `regexp-tree` library package now ships a
`regexp-tree` binary that only directs users to the separate CLI package. Pin
`regexp-tree-cli`, which in turn pins the actual `regexp-tree` library version it
exercises.

## Verified Upstream Facts

- Use [regexp-tree-cli 0.0.21](https://www.npmjs.com/package/regexp-tree-cli),
  the current npm release of the
  [official CLI](https://github.com/DmitrySoshnikov/regexp-tree-cli). It declares
  an exact dependency on
  [regexp-tree 0.1.27](https://www.npmjs.com/package/regexp-tree), the current
  library release.
- `regexp-tree@0.1.27` exposes a `regexp-tree` executable, but that executable only
  prints a relocation notice telling users to install and run
  `regexp-tree-cli`. It is not the exercise command.
- The CLI accepts one required `--expression`/`-e` value in slash-delimited form:
  `/Body/OptionalFlags`. A bare body such as `a|b` is rejected.
- Without an operation option it parses the expression and prints a two-space-
  indented JSON AST. `--loc`/`-l` adds source locations to the parsed nodes.
- `--optimize`/`-o` calls the library optimizer and prints its generated regex.
  `--compat`/`-c` calls the compatibility transpiler, including transformations
  for features such as dotAll and named captures.
- `--table`/`-t` accepts `nfa`, `dfa`, or `all`. It converts supported expressions
  to finite automata, prints transition tables, and minimizes the DFA before
  printing the final table.
- The grammar is based on ECMAScript regular expressions and also supports some
  documented extensions, including the `x` extended-mode flag. This is not a
  general PCRE, Perl, Python, Java, or Oniguruma parser.
- Native option precedence is `optimize`, then `compat`, then `table`, then normal
  parsing. The CLI permits those flags together and silently selects the first
  applicable operation; `--loc` affects only normal parsing.
- Repeated `--expression` options are accepted and the last value wins. The CLI
  has no file or stdin input mode and does not expose the library's programmatic
  matching APIs.
- The yargs parser is not configured in strict mode. Unknown options and extra
  positional operands are silently ignored rather than rejected.
- Parser and transformation failures are not normalized: yargs option errors and
  uncaught library exceptions write native diagnostics to stderr and exit 1.
- The CLI's `colors` dependency emits ANSI styling even when stdout is redirected.
  `FORCE_COLOR=0` disables it for deterministic examples and automated tests;
  `NO_COLOR` is not honored by the installed version.
- Neither top-level package declares a Node `engines` range. Do not claim a broad
  compatibility matrix without testing it.

A local feasibility check installed the exact packages with npm 12.0.2 and ran
them on Node 24.16.0. Parsing, Unicode locations, optimization, compatibility
transpilation, all table modes, help, version, and failure paths worked. The
resulting production dependency tree passed `npm audit --omit=dev` with no known
vulnerabilities at the time of planning.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Parse ECMAScript-style regex literals into an AST, optionally with locations. |
| Regex optimization | Supported directly by `regexp-tree-cli --optimize`. |
| Matching-text generation | Unsupported; AST-to-regex generation is not generation of matching text. |
| Regex inference from samples | Unsupported; do not emulate it. |
| Matching/search | Available in the library API but absent from the native CLI; do not add a wrapper solely to expose it. |
| Additional native operation | Exercise compatibility transpilation and NFA/DFA table generation. |

## Files and Dependency Setup

### Shared Node infrastructure

As the first Node plan, create the root `package.json` as the shared manifest for
all Node exercise tools:

```json
{
  "name": "regex-utils-cli",
  "private": true,
  "scripts": {
    "regexp-tree": "node ./node_modules/regexp-tree-cli/bin/regexp-tree-cli",
    "test": "node --test",
    "test:regexp-tree": "node --test test/regexp-tree-cli.test.js"
  },
  "dependencies": {
    "regexp-tree-cli": "0.0.21"
  }
}
```

Do not add `regexp-tree` as a second direct dependency. Version 0.0.21 of the CLI
already requires exactly `regexp-tree` 0.1.27, and the checked-in lockfile records
that relationship and every transitive package.

Create `package-lock.json` with the current npm lockfile format by running:

```sh
npm install --save-exact regexp-tree-cli@0.0.21
```

Commit both manifest files. Add `/node_modules/` to the root `.gitignore`; do not
commit installed packages or require a global npm install. Later Node plans must
add their dependencies and test scripts to these same root files rather than
creating per-library npm projects.

From a clean checkout, reproduce the locked dependency tree with:

```sh
npm ci
```

Use `npm install --save-exact PACKAGE@VERSION` only when intentionally adding or
changing a dependency and regenerating the lock. Do not use `npm update` as a
bootstrap command.

### Implementation and documentation files

- `package.json`: shared scripts and exact direct dependency shown above.
- `package-lock.json`: checked-in lock of the complete Node dependency graph.
- `test/regexp-tree-cli.test.js`: end-to-end tests of the installed upstream
  executable using Node's built-in test runner.
- `.gitignore`: add `/node_modules/`.
- `README.md`: add Node setup, direct CLI usage, examples, output caveats, and
  supported operations to the shared project documentation.

Do not create `bin/regexp-tree`, `bin/regexp-tree-cli`, a JavaScript adapter, or a
post-install copy. The `regexp-tree` npm script directly runs the installed
upstream entry point by project-relative path, so a missing local install cannot
silently fall through to a globally installed command.

## Native CLI Contract

Run the project-local command as:

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

The first `--` ends npm's options; all following arguments go unchanged to the
upstream executable. Use `--silent` to suppress npm's script banner. Prefix
machine-consumed or golden-output invocations with `FORCE_COLOR=0`.

### Expression and operation rules

- Supply exactly one shell argument containing `/Body/OptionalFlags`. Quote it so
  the shell does not interpret metacharacters, backslashes, spaces, `$`, or `!`.
- The CLI itself requires `-e` for every processing operation. It does not read an
  expression from stdin or a file and ignores piped input.
- `//` is a valid empty expression; parsing it yields a `RegExp` node whose `body`
  is `null`. An omitted or empty `-e` value is an option or parse failure.
- Standard ECMAScript flags and the extensions supported by the pinned parser
  belong inside the closing slash. There is no separate CLI flag argument.
- Prefer one `-e`. If repeated, version 0.0.21 keeps only the last expression.
- Avoid unknown options and extra positional operands. Version 0.0.21 silently
  ignores them, so a misspelled operation flag can unexpectedly fall through to
  ordinary parse mode while still exiting successfully.
- Prefer exactly one of `--optimize`, `--compat`, and `--table`. If combined, do
  not imply that operations form a pipeline: the native implementation applies
  `optimize` over `compat`, `compat` over `table`, and `table` over parsing.
- `--loc` only changes parse output. It has no effect when an earlier operation
  wins through the precedence above.
- Use `--table` only with expressions accepted by the library's educational
  finite-automaton implementation. Parser support for a construct does not imply
  NFA/DFA conversion support for it.

### Native output and exit behavior

- Parse mode writes one valid, two-space-indented JSON document followed by a
  newline. With `FORCE_COLOR=0`, stderr is empty on success.
- `--loc` retains that JSON format and adds `loc` objects containing source,
  start, end, line, column, and offset data where applicable.
- Optimize mode writes a blank line, a leading space, `Optimized: REGEXP`, a
  trailing space, and two newline characters. With color enabled, the label is
  bold ANSI text.
- Compat mode has the same native spacing and styling, with the label `Compat:`.
- Table mode writes a legend and Unicode box-drawing tables. `dfa` prints both the
  original and minimized DFA; `all` prints the NFA followed by both DFA tables.
- Help writes native yargs help to stdout and exits 0. Version writes `0.0.21` and
  exits 0; it reports the CLI package version, not the library version.
- Successful parsing, optimization, transpilation, and table generation exit 0.
- Missing expressions, missing option values, invalid table choices, malformed
  regexes, and unsupported processing paths exit 1. Yargs diagnostics or uncaught
  Node stack traces go to stderr. Failures before an operation writes output keep
  stdout empty, but a table-conversion failure retains the legend already written to
  stdout before the finite automaton is built.
- Do not wrap, relabel, trim, recolor, catch, or translate upstream output and
  statuses. Tests may parse JSON, disable color, and compare semantic substrings,
  but the user-facing npm script must remain a direct upstream invocation.

### Examples

Parse an expression:

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
```

Optimize an expression; the actual native stdout includes the surrounding blank
line and spaces described above:

```console
$ FORCE_COLOR=0 npm run --silent regexp-tree -- -e '/[a-zA-Z_0-9][A-Z_\da-z]*e{1,}/' -o

 Optimized: /\w+e+/

```

Compatibility-transpile dotAll and a named backreference:

```console
$ FORCE_COLOR=0 npm run --silent regexp-tree -- -e '/(?<all>.)\k<all>/s' -c

 Compat: /([\0-\uFFFF])\1/

```

Inspect both automata:

```console
$ FORCE_COLOR=0 npm run --silent regexp-tree -- -e '/a|b|c/' --table all
> - starting
✓ - accepting

NFA transition table:
...
DFA: Original transition table:
...
DFA: Minimized transition table:
...
```

## Implementation Milestones

1. **Establish the Node foundation.** Create the root manifest, exact CLI
   dependency, shared scripts, lockfile, and `/node_modules/` ignore rule; prove a
   clean `npm ci` installs both pinned upstream packages.
2. **Verify direct invocation.** Run help, version, parse, location, optimizer,
   compatibility, and each table mode through the npm alias without adding a
   wrapper.
3. **Add native CLI tests.** Spawn the project-local binary with `FORCE_COLOR=0`
   and assert structured output, transformations, precedence, streams, and exit
   statuses.
4. **Document the command.** Explain slash-delimited expressions, shell quoting,
   operation precedence, no stdin/file mode, native ANSI/spacing, and the package
   split in README.
5. **Validate from clean state.** Recreate `node_modules` with `npm ci`, run the
   focused and aggregate Node tests, inspect the locked dependency versions, and
   run the representative direct CLI commands.

## Test Plan

Use `node:test`, `node:assert/strict`, and `node:child_process`; add no test
framework dependency. Resolve
`regexp-tree-cli/bin/regexp-tree-cli` from the checkout and spawn it with
`process.execPath`, a UTF-8 encoding, and `FORCE_COLOR=0`. This ensures tests
exercise the project-local package even if a global command happens to exist.

### Dependency and static checks

```sh
npm ci
npm ls regexp-tree-cli regexp-tree
npm run --silent regexp-tree -- --version
npm run test:regexp-tree
npm test
npm audit --omit=dev
```

Assert that `npm ls` reports `regexp-tree-cli@0.0.21` and its exact
`regexp-tree@0.1.27` dependency, the version command prints `0.0.21`, the lockfile
is unchanged after `npm ci`, and no globally installed package is needed. Treat a
future audit advisory as a dependency-review trigger rather than applying an
unreviewed force upgrade that breaks the pins.

### Successful behavior

- Help and version exit 0, write only stdout, and contain the native options and
  exact CLI version.
- Parse `/a|b/i`, decode stdout with `JSON.parse`, and assert the `RegExp`,
  `Disjunction`, `Char`, code-point, and `flags` fields rather than relying only on
  a textual snapshot.
- Parse `//` and assert `body: null`. Parse Unicode such as `/é/u` and assert the
  decoded value, code point, flag, and location offsets with and without `--loc`.
- Verify escaped metacharacters, character classes, quantifiers, assertions,
  named captures, backreferences, Unicode properties, and the documented `x`
  extension using examples accepted by version 0.1.27.
- Optimize the documented expression and assert exact color-free stdout
  as the JavaScript string `\n Optimized: /\\w+e+/ \n\n`, with empty stderr and
  status 0.
- Compat-transpile `/(?<all>.)\k<all>/s` and assert exact color-free stdout
  as the JavaScript string `\n Compat: /([\\0-\\uFFFF])\\1/ \n\n`.
- Exercise `nfa`, `dfa`, and `all` with a simple alternation. Assert the legend,
  expected headings, accepting states, transitions, and that the minimized DFA
  has the expected smaller state set; do not assert terminal-width-sensitive
  padding beyond the pinned test environment.
- Repeat `-e` and prove the final expression is parsed. Combine operation flags
  and prove `optimize > compat > table > parse`; verify `--loc` affects only parse
  mode.
- Pass an unknown option and an extra positional operand and prove the native CLI
  ignores both. Record this as an upstream validation limitation, not desired
  wrapper behavior.
- Run the documented examples through the npm script as smoke tests in addition
  to spawning the resolved entry point directly in automated assertions.

### Failure and boundary behavior

- Missing `-e`, missing option arguments, an invalid table choice, and malformed
  slash-delimited expressions in parse/optimize/compat mode exit 1 with empty
  stdout and nonempty stderr.
- A bare regex body is rejected, while the empty literal `//` succeeds. Piped
  input without `-e` still produces the native missing-expression error.
- Pass an expression containing spaces, shell metacharacters, Unicode, and escaped
  slashes as one argv element to prove no shell reconstruction occurs in tests.
- Exercise `/a(?=b)/`, which parses but is unsupported by automaton conversion.
  Assert status 1, a stack trace on stderr, and the already-emitted legend on
  stdout; do not claim every parsed construct can produce a table.
- Confirm `FORCE_COLOR=0` removes ANSI escape bytes. Separately run one native
  operation without it and assert styling may be present rather than normalizing
  user-facing output.
- Temporarily test from a clean copied checkout before `npm ci`: the npm script
  must not silently fetch or substitute a global CLI. After `npm ci`, run it from
  outside the repository using
  `npm --prefix /absolute/repo/path run --silent regexp-tree -- ...` and confirm
  the same project-local version executes.

## Acceptance Criteria

- A clean checkout installs the exact CLI and library versions from the checked-in
  lockfile with `npm ci`; `/node_modules/` remains untracked.
- `npm run --silent regexp-tree -- ...` invokes the official
  `regexp-tree-cli` binary directly, with no project `bin/` wrapper or adapter.
- Parsing, locations, optimization, compatibility transpilation, and NFA/DFA table
  generation are all exercised with their native arguments, output, and statuses.
- Tests cover JSON semantics, exact stable transform output, Unicode, the empty
  regex, regex syntax, operation precedence, unsupported table input, native
  failures, ANSI control, and project-local resolution.
- Unsupported matching-text generation, inference, and CLI matching are not
  simulated with unrelated wrapper logic.
- README clearly identifies the two-package split, slash-literal input format,
  lack of stdin/file support, operation precedence, table limitations, native
  output formatting, and `FORCE_COLOR=0` for reproducible output.

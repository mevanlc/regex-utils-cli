# Plan: grex-js CLI Exercise

## Summary

Add `bin/grex-js`, a project-local Node CLI that passes literal test cases to
`@pemistahl/grex` and prints the regular expression inferred by its WebAssembly-
backed `RegExpBuilder`. The command exposes the builder settings that materially
change inference while keeping sample parsing and regex construction inside the
upstream library.

The npm package does not ship a CLI. Its defining operation is regex inference
from positive examples; it does not accept an existing regex for optimization,
generate matching text, execute the generated expression, or learn from negative
examples. Do not invent those operations in the wrapper.

## Verified Upstream Facts

- Use [@pemistahl/grex 1.0.2](https://www.npmjs.com/package/@pemistahl/grex),
  the current npm release from the
  [official grex-js repository](https://github.com/pemistahl/grex-js). Pin that
  exact version in the shared root npm manifest and lockfile.
- The npm release, the repository's `main` branch, and tag `v1.0.2` resolve to
  source commit `f3ed8d4dd6454c4c26ed35084b388d9736d4187a`. The published
  artifact corresponds to version 1.4.2 of the separate Rust implementation.
  The current [Rust grex 1.4.6](https://github.com/pemistahl/grex/releases/tag/v1.4.6)
  is not a substitute for exercising this older JavaScript package.
- The package contains generated JavaScript bindings plus a roughly 3 MB package
  payload dominated by WebAssembly. It has no runtime npm dependencies, `bin`
  entry, native addon, operating-system restriction, architecture restriction,
  or declared Node engine range.
- Conditional exports send `require('@pemistahl/grex')` to the synchronous Node
  build and ESM `import` to the browser build. The Node build reads its adjacent
  `grex_bg.wasm` relative to its own module directory.
- Because this project's shared Node manifest uses ESM, the CLI must use
  `createRequire(import.meta.url)` and then require `@pemistahl/grex`. Do not
  import the browser export or copy the WASM file into the project.
- `RegExpBuilder.from(testCases)` accepts an array of strings, sorts test cases
  internally, and throws when the array is empty. A list containing one empty
  string is valid and builds `^$`; duplicate strings collapse semantically.
- Test cases are literal strings, not regex fragments. Metacharacters are escaped
  or incorporated into safe classes by the library; for example, `a.b` and `a*b`
  infer `^a[*.]b$`.
- Default inference produces an anchored, case-sensitive expression using non-
  capturing groups. It seeks a specific expression that matches only the supplied
  positive cases, although manual review can still find a simpler domain regex.
- The library builds a DFA from the examples, minimizes it, and converts it to a
  regex. Input ordering does not control alternation order.
- Six methods generalize Unicode characters to `\d`, `\D`, `\s`, `\S`, `\w`, or
  `\W`. Enabling these can make the result match strings that were not supplied.
  Upstream defines precedence when overlapping generalizers are combined.
- Repetition conversion detects repeated non-overlapping substrings and uses
  quantifiers. Its minimum repetition count and minimum substring length default
  to 1 and are represented by unsigned 32-bit integers in the WASM API.
- Other builder methods enable case-insensitive matching, capturing groups,
  verbose mode, Unicode escaping with code points or surrogate pairs, and removal
  of either or both anchors.
- Output is PCRE-oriented and only mostly compatible with JavaScript `RegExp`.
  In particular, case-insensitive and verbose modes emit leading `(?i)` and `(?x)`
  modifiers, and code-point escapes require dialect-aware handling. The CLI must
  return the source without claiming native JavaScript executability.
- Version 1.0.2 documents Unicode 15.0 support. Do not attribute Unicode 16.0 or
  features from the newer Rust release to this npm artifact.
- The public builder can throw JavaScript strings rather than `Error` objects. The
  wrapper must normalize both forms without emitting `undefined`, object dumps, or
  stack traces.

A local feasibility check installed 1.0.2 with npm 12.0.2 and exercised it under
Node 24.16.0. The CommonJS Node export loaded its bundled WASM, all public builder
settings returned patterns, `free()` succeeded after `build()`, empty-list errors
were catchable, and the production dependency tree passed `npm audit --omit=dev`
with no known vulnerabilities at the time of planning. Acceptance still includes
a smoke test on the project's declared Node 20 minimum because upstream declares
no engine compatibility range.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Infer one PCRE-style regex from literal positive test cases. |
| Regex inference from samples | Supported directly by `RegExpBuilder.from(...).build()`. |
| Regex optimization | Unsupported; the DFA is minimized during inference, but no existing regex is accepted. |
| Matching-text generation | Unsupported; input examples are not generated output. |
| Matching/search | Unsupported; the package returns regex source and does not execute it. |
| Negative examples | Unsupported; do not emulate them by post-processing the result. |

## Files and Dependency Setup

### Shared Node infrastructure

Extend the root Node project established by the preceding Node plans. The combined
manifest after this plan is:

```json
{
  "name": "regex-utils-cli",
  "private": true,
  "type": "module",
  "engines": {
    "node": ">=20"
  },
  "scripts": {
    "grex-js": "node ./bin/grex-js",
    "oniguruma-parser": "node ./bin/oniguruma-parser",
    "regexp-tree": "node ./node_modules/regexp-tree-cli/bin/regexp-tree-cli",
    "test": "node --test",
    "test:grex-js": "node --test test/grex-js.test.js",
    "test:oniguruma-parser": "node --test test/oniguruma-parser.test.js",
    "test:regexp-tree": "node --test test/regexp-tree-cli.test.js"
  },
  "dependencies": {
    "@pemistahl/grex": "1.0.2",
    "oniguruma-parser": "0.12.2",
    "regexp-tree-cli": "0.0.21"
  }
}
```

Add and lock the package with:

```sh
npm install --save-exact @pemistahl/grex@1.0.2
```

Commit the updated `package.json` and `package-lock.json`. Reuse `/node_modules/`
in `.gitignore` and the shared clean-checkout bootstrap:

```sh
npm ci
```

Do not install the separate Rust `grex` executable, add a second Node project,
vendor the WASM artifact, depend on a browser bundler, or use a global npm package.

### Implementation and documentation files

- `bin/grex-js`: extensionless executable ESM CLI with a Node shebang.
- `test/grex-js.test.js`: end-to-end tests using Node's built-in test runner.
- `package.json` and `package-lock.json`: the shared Node files above.
- `README.md`: add setup, input-record rules, options, examples, output dialect,
  inference limitations, and the Node/CommonJS-WASM loading rationale.

Use only Node core modules for argument parsing, input, strict UTF-8 decoding,
dependency resolution, and diagnostics. Use `node:util`'s `parseArgs` with tokens
enabled so duplicate options can be rejected; do not add a CLI framework.

Resolve the CommonJS entry relative to the executable with `createRequire`, walk
from that resolved file to the installed package metadata, and verify version
1.0.2 before a version or inference request. Both requests must require the Node
export so a missing or corrupt WASM does not produce a misleading successful
version check. If the dependency is missing, has the wrong version, cannot load
its WASM, or lacks `RegExpBuilder`, write this to stderr and exit 1:

```text
grex-js: @pemistahl/grex 1.0.2 is not installed; run npm ci
```

Parse and display help before resolving the dependency so help works in a clean
checkout. Do not fall through to a package installed globally or relative to the
caller's current working directory.

## CLI Contract

```text
Usage:
  grex-js [OPTIONS] [TEST_CASE...]

Input:
  TEST_CASE...                    Literal positive examples as separate arguments
  -i, --input FILE                Read LF/CRLF-delimited examples; use - for stdin

Character generalization:
      --digits                    Convert Unicode decimal digits to \d
      --non-digits                Convert Unicode non-digits to \D
      --whitespace                Convert Unicode whitespace to \s
      --non-whitespace            Convert Unicode non-whitespace to \S
      --words                     Convert Unicode word characters to \w
      --non-words                 Convert Unicode non-word characters to \W

Repetitions:
      --repetitions               Convert repeated substrings to quantifiers
      --min-repetitions N         Minimum repeated occurrences beyond the first; default 1
      --min-substring-length N    Minimum repeated substring length; default 1

Rendering and matching semantics:
      --ignore-case               Emit a case-insensitive expression
      --capture-groups            Use capturing instead of non-capturing groups
      --escape-non-ascii MODE     MODE is code-point or surrogate-pair
      --verbose                   Emit a multiline expression with (?x)
      --no-start-anchor           Omit ^
      --no-end-anchor             Omit $
      --no-anchors                Omit both ^ and $

General options:
  -h, --help                      Print help and exit
  -V, --version                   Print command and package version and exit
```

There is one inference operation and therefore no redundant subcommand. Reject
unknown options, repeated options, and unexpected option values. A test case that
starts with `-` must follow `--`.

### Test-case input

- Accept exactly one source: one or more positional `TEST_CASE` arguments, one
  `--input FILE`, or stdin when neither is present. Reject positional cases mixed
  with `--input` and reject a repeated `--input`.
- If stdin would be selected implicitly while attached to a terminal, exit with a
  usage error instead of waiting. `--input -` explicitly selects stdin and may
  wait even when attached to a terminal.
- Positional arguments are complete literal cases. Preserve their order, empty
  strings, spaces, tabs, newlines supplied within an argument, and metacharacters.
  The operating system cannot carry NUL in an argv element; file/stdin input can.
- Read a file or stdin completely and decode it with a fatal UTF-8 `TextDecoder`.
  Split on LF. Treat a CR immediately before LF as part of the record delimiter,
  but preserve every other CR and all other characters.
- A single final LF or CRLF terminates the last record and does not create an
  additional empty case. Interior blank records remain empty cases. Thus `a\n`
  is `['a']`, `a\n\n` is `['a', '']`, and `\n` is `['']`.
- A zero-byte file or redirected zero-byte stdin supplies an empty array. Pass it
  to `RegExpBuilder.from` so its upstream empty-list failure is observable; do not
  silently reinterpret it as one empty case.
- Do not trim, sort, deduplicate, parse escapes, interpret regex syntax, or combine
  sources in wrapper code. Upstream is responsible for sorting and any duplicate
  collapse.

### Builder-option mapping

Start with `RegExpBuilder.from(testCases)`, reassign the builder returned by every
enabled method, call `build()` exactly once, and call `free()` exactly once on the
final builder in a `finally` block.

| CLI option | Upstream call |
| --- | --- |
| `--digits` | `withConversionOfDigits()` |
| `--non-digits` | `withConversionOfNonDigits()` |
| `--whitespace` | `withConversionOfWhitespace()` |
| `--non-whitespace` | `withConversionOfNonWhitespace()` |
| `--words` | `withConversionOfWords()` |
| `--non-words` | `withConversionOfNonWords()` |
| `--repetitions` | `withConversionOfRepetitions()` |
| `--min-repetitions N` | `withMinimumRepetitions(N)` |
| `--min-substring-length N` | `withMinimumSubstringLength(N)` |
| `--ignore-case` | `withCaseInsensitiveMatching()` |
| `--capture-groups` | `withCapturingGroups()` |
| `--escape-non-ascii code-point` | `withEscapingOfNonAsciiChars(false)` |
| `--escape-non-ascii surrogate-pair` | `withEscapingOfNonAsciiChars(true)` |
| `--verbose` | `withVerboseMode()` |
| `--no-start-anchor` | `withoutStartAnchor()` |
| `--no-end-anchor` | `withoutEndAnchor()` |
| `--no-anchors` | `withoutAnchors()` |

Apply methods in table order for deterministic wrapper behavior. The six class
generalizers may be combined; preserve upstream's documented precedence rather
than rejecting or reordering combinations based on wrapper guesses. In particular:

- digits take precedence over words and whitespace;
- whitespace takes precedence over non-digits and non-words;
- words take precedence over non-digits and non-whitespace;
- non-digits take precedence over non-words and non-whitespace; and
- non-words take precedence over non-whitespace.

Require `--min-repetitions` and `--min-substring-length` to accompany
`--repetitions`. Parse each value as an ASCII decimal integer from 1 through
4,294,967,295; reject signs, fractions, exponent notation, zero, and overflow as
usage errors before the number crosses the WASM boundary.

Reject `--no-anchors` combined with either individual anchor option. Allow
`--no-start-anchor` and `--no-end-anchor` together and map them to the two
individual methods, which intentionally exercises a different API path with the
same expected source as `--no-anchors`.

Do not add syntax highlighting, an output-dialect switch, negative samples,
regex validation, matching, or a pass that rewrites the inferred expression.

### Output, exits, and diagnostics

- Write the exact string returned by `build()` to stdout followed by one LF. Do
  not JSON-encode it, interpret backslashes, remove internal or trailing pattern
  characters, or add labels. Verbose output remains multiline.
- Help exits 0 and writes only stdout. `--version` writes `grex-js 1.0.2` plus LF
  to stdout and exits 0.
- Successful inference exits 0 with empty stderr, including one empty test case,
  duplicate cases, literal NUL from file/stdin, and multiline verbose output.
- Unknown/repeated options, invalid option values, conflicting sources, invalid
  numeric ranges, numeric options without `--repetitions`, conflicting anchor
  options, extra help/version operands, or implicit terminal input exit 2 with
  empty stdout.
- Missing/wrong dependencies, WASM load failures, unreadable input, invalid UTF-8,
  an upstream empty-list rejection, and other builder failures exit 1 with empty
  stdout.
- Prefix concise diagnostics with `grex-js:`. If upstream throws an `Error`, use
  its `message`; if it throws a string, use the string. Do not print stack traces,
  object coercion noise, internal paths, or a partial pattern.
- Buffer the pattern before one stdout write. Treat `EPIPE` as a quiet successful
  termination with status 0; report other output failures and exit 1.

### Examples

Infer an exact anchored expression from positional cases:

```console
$ npm run --silent grex-js -- hello world
^(?:hello|world)$
```

Generalize digits and words from line-delimited stdin:

```console
$ printf '%s\n' a aa 123 | npm run --silent grex-js -- --digits --words
^(?:\d\d\d|\w(?:\w)?)$
```

Detect repeated substrings with explicit thresholds:

```console
$ npm run --silent grex-js -- --repetitions \
    --min-substring-length 2 aa bcbc defdefdef
^(?:aa|(?:bc){2}|(?:def){3})$
```

Escape astral characters as surrogate pairs:

```console
$ npm run --silent grex-js -- \
    --escape-non-ascii surrogate-pair 'You smell like 💩.'
^You smell like \u{d83d}\u{dca9}\.$
```

An empty string is a valid test case:

```console
$ npm run --silent grex-js -- ''
^$
```

## Implementation Milestones

1. **Extend the Node foundation.** Add the exact npm dependency and scripts,
   regenerate the shared lockfile, and load the CommonJS Node/WASM entry under the
   existing ESM project mode.
2. **Build strict CLI plumbing.** Add help/version, token-aware argument validation,
   mutually exclusive source selection, lossless record decoding, dependency
   checks, buffered output, and status-separated diagnostics.
3. **Implement core inference.** Pass literal cases to `RegExpBuilder.from`, build
   once, return raw source, and release the final WASM builder.
4. **Expose meaningful builder settings.** Map all class, repetition, capture,
   escaping, verbose, case, and anchor controls with the documented constraints.
5. **Test and document.** Cover every source and API path, package/dialect limits,
   clean installation, Node 20 smoke behavior, and the aggregate Node suite.

## Test Plan

Use ESM imports from `node:test`, `node:assert/strict`, `node:child_process`, and
temporary-file helpers. Spawn the CLI with `process.execPath` and the absolute
`bin/grex-js` path so tests do not depend on a shell or caller working directory.
Compare NUL and newline-sensitive cases as bytes.

### Dependency and static checks

```sh
npm ci
npm ls @pemistahl/grex oniguruma-parser regexp-tree-cli regexp-tree
npm run --silent grex-js -- --version
npm run test:grex-js
npm test
npm audit --omit=dev
```

Assert the exact 1.0.2 dependency and bundled WASM, an unchanged lockfile after
`npm ci`, correct version output, absence of a global dependency, and continued
success of the preceding Node CLI tests. Run a load-and-build smoke test on Node
20 as the minimum-engine gate. Treat future audit findings as review triggers
rather than applying an unreviewed forced upgrade.

### Successful behavior

- Top-level help and version write only stdout and exit 0. Help works without
  `node_modules`; version gives the exact bootstrap diagnostic when absent.
- Positional, file, explicit stdin, and implicit redirected-stdin sources produce
  the same source for equivalent records. Verify LF, CRLF, a final delimiter,
  interior empty records, whitespace-only records, literal CR, Unicode grapheme
  clusters, metacharacters, and NUL with no unintended trimming or decoding.
- Assert exact upstream examples: `['a', 'aa', 'aaa']` becomes `^a(?:aa?)?$`,
  `['hello', 'world']` becomes `^(?:hello|world)$`, and `['']` becomes `^$`.
- Reverse input order and add duplicates; assert the same result, demonstrating
  upstream sorting and duplicate collapse rather than wrapper reordering.
- For compatible default outputs, compile with JavaScript `RegExp` and assert all
  supplied examples match while nearby negative examples do not. Keep this as a
  test oracle only; do not expose matching in the CLI.
- Exercise each of the six class conversions independently and assert `^\d$`,
  `^\D$`, `^\s$`, `^\S$`, `^\w$`, and `^\W$` for representative one-character
  inputs. Exercise documented precedence combinations without assuming a total
  ordering beyond upstream's pairwise rules.
- Exercise repetition conversion with default and custom thresholds. Assert the
  three documented outputs for `aa`, `bcbc`, and `defdefdef`.
- Assert code-point and surrogate-pair escaping, case-insensitive `(?i)` output,
  capture-group replacement, verbose `(?x)` multiline output, and each of the
  three anchor-removal methods.
- Confirm both individual anchor switches together equal `--no-anchors`, while
  each switch alone removes only its named anchor.
- Run every README example through the npm script in addition to direct spawning.
  Confirm every success has empty stderr and exactly one wrapper-added LF after
  the returned pattern.

### Failure and safety behavior

- Unknown or repeated options, unexpected operands for help/version, conflicting
  sources, bad escape modes, invalid numeric spellings/ranges, threshold options
  without repetition conversion, anchor conflicts, and implicit terminal input
  exit 2 with empty stdout.
- Zero-byte file/stdin reaches `RegExpBuilder.from([])` and exits 1 with
  `grex-js: No test cases have been provided for regular expression generation`.
  Distinguish this from a one-record empty input, which succeeds with `^$`.
- Missing/unreadable files, invalid UTF-8, missing/wrong package versions, a
  missing/corrupt WASM file, and injected upstream string/`Error` failures exit 1
  with no pattern fragment, stack, or internal path.
- Run outside the repository and prove the executable resolves the checkout-local
  dependency and WASM. In a clean copied checkout before `npm ci`, help works and
  inference prints only the actionable bootstrap diagnostic.
- Use metacharacters, replacement-like text, JavaScript source, shell syntax, and
  sentinel paths as samples. Assert they remain inert literal data and cannot be
  evaluated or treated as regex fragments.
- Feed a large case set under a test timeout and assert successful completion or a
  normalized upstream failure. Document that the CLI does not provide CPU or
  memory isolation around the DFA/WASM computation.
- Simulate stdout failures to verify buffered output, status 1 for non-EPIPE
  errors, and quiet status 0 for `EPIPE`.

## Acceptance Criteria

- A clean checkout installs exactly `@pemistahl/grex` 1.0.2 and its bundled WASM
  through the shared npm lockfile, with no global package, Rust CLI, or browser
  bundler.
- The ESM executable deliberately loads the package's CommonJS Node export and
  works from any current working directory without copying package artifacts.
- Input records preserve literal data, empty-case and empty-list semantics remain
  distinct, and the wrapper neither sorts nor deduplicates before the upstream API.
- Every CLI setting maps to its named `RegExpBuilder` method, `build()` is called
  once, `free()` releases the final builder, and no wrapper regex algorithm alters
  the result.
- Tests cover all sources and methods, Unicode, duplicates, metacharacters,
  thresholds, precedence, output bytes, diagnostics, exit statuses, dependency and
  WASM failures, Node 20 compatibility, and the shared Node regression suite.
- README identifies the output as PCRE-style Unicode 15.0 regex source, explains
  where generalization broadens matches, and does not promise JavaScript `RegExp`
  compatibility, regex optimization, negative examples, matching, or matching-text
  generation.

# Plan: regex-trie JavaScript CLI Exercise

## Summary

Add `bin/regex-trie-js`, a project-local Node CLI for building and exercising an
`alexeld/regex-trie` trie from literal phrases. Expose three focused subcommands:
`build` prints the compact regex source returned by `toString()`, `contains`
checks exact trie membership with `contains()`, and `match` tests candidate text
with the unanchored JavaScript `RegExp` returned by `toRegExp()`.

The npm package has no CLI or configuration API. The wrapper must preserve its
literal-only, case-sensitive, unanchored behavior and its input-order-sensitive
rendering rather than adding anchors, flags, sorting, optimization passes, or
regex parsing of its own.

## Verified Upstream Facts

- Use [regex-trie 1.0.4](https://www.npmjs.com/package/regex-trie), the current
  npm release from the
  [official alexeld/regex-trie repository](https://github.com/alexeld/regex-trie).
  Pin the exact registry release and its transitive dependency in the shared npm
  lockfile.
- Version 1.0.4 was published in 2014. The repository's current `master` is commit
  `579e0c2af2c902c37cd53925c012e5addb390215` from 2017; its runtime source is
  byte-equivalent to the npm release apart from line endings. Subsequent source
  changes only updated package metadata and a documentation link.
- The repository's `v1.0.4` tag points to an earlier version-bump state rather
  than the exact published manifest. Use the npm artifact and lockfile, not the
  Git tag, as the implementation source of truth.
- The CommonJS package exports one `RegexTrie` constructor, has no `bin`, export
  map, type declarations, native code, operating-system restriction, architecture
  restriction, or Node engine declaration.
- Its sole production dependency is `jsesc ^0.5.0`, which currently locks to
  `jsesc 0.5.0`. Do not install the obsolete upstream development toolchain in
  this project.
- `add(value)` is chainable. It accepts a string, number, or array, coerces every
  number except `NaN` to a string, silently ignores other values and empty strings,
  and uses `contains()` to avoid adding a duplicate phrase.
- All CLI sources in this plan provide strings. Do not add numeric coercion syntax
  merely to exercise a path that command-line arguments already represent as text.
- `contains(phrase)` reports exact trie membership. It is not regex matching: with
  phrase `foo`, candidate `food` is not contained.
- `toString()` returns a JavaScript regex pattern body as a primitive string, or
  `undefined` when no non-empty phrase was added. It factors common prefixes,
  collapses one-character alternatives into classes, and represents phrase-prefix
  relationships with optional non-capturing groups.
- `toRegExp()` calls `new RegExp(toString())` with no flags and returns `undefined`
  for an empty trie. The result is case-sensitive, non-capturing, and unanchored,
  so phrase `foo` matches `food` and `afoo` as substrings.
- The library does not offer anchoring, flags, capture controls, deletion, or an
  optimizer for an existing regex. Its source explicitly calls the generated
  expression “non-optimised”; trie factoring is part of construction, not a
  general regex optimization capability.
- Phrases are interpreted literally. Regex metacharacters are escaped before
  source generation; `^(foo|bar]` and `car[a-z]zoo`, for example, produce
  `(?:\^\(foo\|bar\]|car\[a\-z\]zoo)`.
- Source order is observable. Most alternatives follow insertion order, so
  `['a', 'b']` produces `[ab]` while `['b', 'a']` produces `[ba]`. Integer-like
  object keys follow JavaScript enumeration rules instead: `['9', '1']` produces
  `[19]`. The wrapper must neither promise lexicographic order nor sort inputs.
- The implementation walks JavaScript UTF-16 code units and uses the old `jsesc`
  defaults. It renders `café` as `caf\xE9`, astral characters as surrogate-pair
  escapes such as `\uD83D\uDCA9`, and CJK code units as `\uXXXX`.
- Two escaping defects are material. U+0008 becomes `\b`, which `RegExp` treats as
  a word-boundary assertion, and a NUL followed by digits 1 through 7 can become a
  legacy octal escape such as `\01`. Generated regexes can therefore fail to match
  those original phrases. Characterize and document the defects; do not silently
  rewrite upstream output.
- The generated string is a `RegExp` constructor pattern body, not `/.../flags`
  notation. A literal slash is valid unescaped source for the constructor but
  would need escaping if a caller later embeds it in a JavaScript regex literal.
- The recursive renderer can exhaust the JavaScript stack for sufficiently long
  phrases. The CLI is an exercise tool, not a resource-isolation boundary.

A local feasibility check installed regex-trie 1.0.4 and jsesc 0.5.0 with npm
12.0.2 and exercised them under Node 24.16.0. Source construction, exact
membership, unanchored matching, prefix factoring, insertion order, duplicates,
empty strings, controls, metacharacters, BMP Unicode, and astral characters were
verified directly. The production tree passed `npm audit --omit=dev` with no known
vulnerabilities at planning time.

The historical upstream suite is not a project acceptance gate. Under its pinned
Mocha 1.17.1, 54 tests passed and four stale `_quotemeta` tests failed because they
still call the removed `regex()` method instead of `toRegExp()`. Installing the
full historical development tree also reported 49 vulnerabilities at planning
time. Use new project-local end-to-end tests against the published API instead.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Build a prefix trie of literal phrases and render compact JavaScript regex source. |
| Regex inference from samples | Supported for factoring non-empty literal phrases; generated matching remains unanchored. |
| Regex optimization | Unsupported for regex input; prefix factoring is only construction behavior. |
| Matching-text generation | Unsupported; do not emulate it. |
| Matching/search | Supported as case-sensitive, unanchored substring search through `toRegExp()`. |
| Exact trie membership | Supported separately through `contains()`. |

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
    "regex-trie-js": "node ./bin/regex-trie-js",
    "regexp-tree": "node ./node_modules/regexp-tree-cli/bin/regexp-tree-cli",
    "test": "node --test",
    "test:grex-js": "node --test test/grex-js.test.js",
    "test:oniguruma-parser": "node --test test/oniguruma-parser.test.js",
    "test:regex-trie-js": "node --test test/regex-trie-js.test.js",
    "test:regexp-tree": "node --test test/regexp-tree-cli.test.js"
  },
  "dependencies": {
    "@pemistahl/grex": "1.0.2",
    "oniguruma-parser": "0.12.2",
    "regex-trie": "1.0.4",
    "regexp-tree-cli": "0.0.21"
  }
}
```

Add and lock the package with:

```sh
npm install --save-exact regex-trie@1.0.4
```

Commit the updated `package.json` and `package-lock.json`. Confirm the lockfile
resolves `jsesc` to 0.5.0, reuse `/node_modules/` in `.gitignore`, and retain the
shared clean-checkout bootstrap:

```sh
npm ci
```

Do not install from the misleading Git tag, copy source out of `node_modules`,
vendor `jsesc`, create another Node project, or require a global package.

### Implementation and documentation files

- `bin/regex-trie-js`: extensionless executable ESM CLI with a Node shebang.
- `test/regex-trie-js.test.js`: end-to-end tests using Node's built-in test runner.
- `package.json` and `package-lock.json`: shared Node infrastructure above.
- `README.md`: add subcommands, record parsing, JSON Lines output, order and
  anchoring behavior, Unicode/control limitations, and examples.

Use only Node core modules for parsing arguments, strict UTF-8 input, JSON Lines,
dependency resolution, and diagnostics. Use `node:util`'s `parseArgs` with tokens
enabled; do not add a CLI framework or the upstream development dependencies.

Because the project is ESM and regex-trie is CommonJS, use
`createRequire(import.meta.url)` to resolve and require `regex-trie` relative to
the executable. Resolve its package metadata through the same project-local
require, verify version 1.0.4, and validate that the export is a constructor with
`add`, `contains`, `toString`, and `toRegExp` methods before version or processing
requests. On failure, write this to stderr and exit 1:

```text
regex-trie-js: regex-trie 1.0.4 is not installed; run npm ci
```

Display help before loading the dependency so help remains available before
`npm ci`. Never resolve relative to the caller's working directory or fall through
to a globally installed package.

## CLI Contract

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

General options:
  -h, --help                      Print help and exit
  -V, --version                   Print command and package version and exit
```

Require exactly one subcommand. Top-level help lists all forms; subcommand help
shows only valid inputs and its output schema. `--version` is top-level and accepts
no subcommand or operands. Reject candidate options on `build`, unknown options,
and repeated non-repeatable options. `--candidate` is intentionally repeatable.
A phrase or candidate option value beginning with `-` must follow `--` when it is
positional, or be attached with `--candidate=-value` when it is an option value.

### Phrase input

- Accept exactly one phrase source: one or more positional `PHRASE` arguments,
  one `--input FILE`, or stdin when neither is present. Reject positionals mixed
  with `--input` and reject repeated `--input`.
- If stdin would be selected implicitly while attached to a terminal, exit with a
  usage error rather than waiting. `--input -` explicitly selects stdin.
- Positional phrases are complete literal strings. Preserve their order, empty
  values, whitespace, newlines within an argument, and metacharacters. NUL cannot
  occur in argv but can occur in file/stdin records.
- Read file/stdin bytes completely and decode them with a fatal UTF-8
  `TextDecoder`. Split on LF; treat CR immediately before LF as part of the record
  delimiter while preserving every other CR and character.
- One final LF or CRLF terminates the last record without adding a phantom empty
  phrase. Preserve interior blank records: `foo\n` is `['foo']`, `foo\n\n` is
  `['foo', '']`, and `\n` is `['']`. A zero-byte stream is an empty array.
- Pass the complete array to `trie.add(phrases)` exactly once. Do not filter empty
  strings, sort, deduplicate, parse numbers, or interpret regex syntax. This keeps
  the library's silent empty-string rejection and duplicate handling observable.

### Candidate input

- `contains` and `match` require exactly one candidate source: one or more
  `--candidate TEXT` occurrences or one `--candidate-input FILE`. Reject mixing
  them and reject a repeated `--candidate-input`.
- Parse candidate files with the same strict UTF-8 and LF/CRLF record rules as
  phrases. Preserve empty candidates, duplicates, order, NUL, and metacharacters.
- A zero-byte candidate file supplies no candidates and exits 1 with
  `regex-trie-js: candidate input contains no records`. Omitting a candidate
  source entirely is a usage error with status 2.
- At most one input source may select stdin. Reject explicit or implicit phrase
  stdin combined with `--candidate-input -`. Positional/file phrases may be used
  with candidate stdin, and phrase stdin may be used with candidate arguments or
  a non-stdin candidate file.

### API mapping and output

Create one trie per invocation with `new RegexTrie()` and call `add(phrases)` once.
Do not inspect or mutate `_trie`, `_num_phrases_in_trie`, or other private fields.

#### `build`

1. Call `trie.toString()` exactly once after `add`.
2. If it returns a string, write that exact pattern body plus one LF.
3. If it returns `undefined`, exit 1 with
   `regex-trie-js: no non-empty phrases were added`.

Do not wrap the result in anchors or delimiters, reorder alternatives, compile it,
or add flags. For `foo`, `bar`, and `baz`, stdout is:

```text
(?:foo|ba[rz])
```

#### `contains`

Call `trie.contains(candidate)` once per candidate after `add`. Buffer and print
one compact JSON object per input candidate, in candidate order:

```json
{"candidate":"foo","contains":true}
{"candidate":"food","contains":false}
```

An empty trie is valid for this operation and reports `false` for every candidate,
directly exposing `contains()` behavior. Do not infer membership from generated
source or from wrapper-side sets.

#### `match`

1. Call `trie.toRegExp()` exactly once after `add`.
2. If it returns `undefined`, use the same no-non-empty-phrases error as `build`.
3. Call the returned regex's `test(candidate)` once per candidate and emit:

```json
{"candidate":"foo","matches":true}
{"candidate":"food","matches":true}
{"candidate":"bat","matches":false}
```

The regex has no stateful flags, so candidate order does not affect results. Do
not add anchors, reset `lastIndex`, use a different regex engine, or change
substring matching into full-string matching.

For `contains` and `match`, serialize each object with `JSON.stringify`, join the
complete buffered records with LF, and append one final LF. JSON escaping preserves
candidate newlines, controls, NUL, and unpaired UTF-16 code units without breaking
record framing.

### Exit and diagnostic behavior

- Help exits 0 and writes only stdout. `--version` writes
  `regex-trie-js 1.0.4` plus LF to stdout and exits 0.
- Successful operations exit 0 with empty stderr. `contains` succeeds even when
  every phrase was ignored as empty.
- Missing/unknown subcommands, unknown or invalid options, repeated non-repeatable
  options, conflicting phrase/candidate sources, missing candidates, candidate
  options on `build`, multiple stdin consumers, extra version operands, and
  implicit terminal phrase input exit 2 with empty stdout.
- Missing/wrong dependencies, unreadable files, invalid UTF-8, zero candidate
  records, empty effective tries for `build`/`match`, recursion errors, `RegExp`
  construction errors, and other library exceptions exit 1 with empty stdout.
- Prefix concise diagnostics with `regex-trie-js:`. Report an exception's message
  without its stack or internal paths and never emit partial source or JSON Lines.
- Buffer all output before a single stdout write. Treat `EPIPE` as quiet success
  with status 0; report every other stdout failure and exit 1.

### Examples

Build source from positional phrases:

```console
$ npm run --silent regex-trie-js -- build foo bar baz
(?:foo|ba[rz])
```

Build from line-delimited stdin:

```console
$ printf '%s\n' f fo fox | npm run --silent regex-trie-js -- build
f(?:ox?)?
```

Compare exact membership with generated-regex matching:

```console
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

Observe the pinned release's Unicode escaping:

```console
$ npm run --silent regex-trie-js -- build café 💩 漢字
(?:caf\xE9|\uD83D\uDCA9|\u6F22\u5B57)
```

## Implementation Milestones

1. **Complete the shared Node manifest.** Add regex-trie 1.0.4, lock jsesc 0.5.0,
   add command/test scripts, and prove the CommonJS constructor loads under the
   existing ESM project.
2. **Build strict shared plumbing.** Add dispatch, token-aware option validation,
   lossless record readers, stdin-conflict detection, deferred dependency checks,
   buffered output, help/version, and status-separated diagnostics.
3. **Implement source and membership.** Add phrases once, map `build` directly to
   `toString`, and map `contains` directly to per-candidate membership calls.
4. **Implement matching.** Compile once through `toRegExp`, preserve unanchored
   case-sensitive semantics, and emit deterministic JSON Lines booleans.
5. **Test and document.** Cover all sources and APIs, historical limitations,
   clean installation, Node 20 smoke behavior, and the complete shared Node suite.

## Test Plan

Use ESM imports from `node:test`, `node:assert/strict`, `node:child_process`, and
temporary-file helpers. Spawn `bin/regex-trie-js` with `process.execPath` and an
absolute path so tests exercise the checkout-local implementation without a shell
or caller-working-directory dependency. Compare control-sensitive output as bytes.

### Dependency and static checks

```sh
npm ci
npm ls regex-trie jsesc @pemistahl/grex oniguruma-parser regexp-tree-cli regexp-tree
npm run --silent regex-trie-js -- --version
npm run test:regex-trie-js
npm test
npm audit --omit=dev
```

Assert exact regex-trie 1.0.4 and jsesc 0.5.0 resolution, an unchanged lockfile
after `npm ci`, correct version output, no global dependency, and continued success
of all earlier Node command tests. Smoke-test construction on Node 20 because the
package declares no engine range. Treat future audit findings as review triggers;
do not install or audit-fix the obsolete upstream development tree into the project.

### Successful behavior

- Top-level and subcommand help plus version write only stdout and exit 0. Help
  works before installation; version reports the exact bootstrap diagnostic when
  the dependency is absent.
- Positional, file, explicit stdin, and implicit redirected-stdin phrase sources
  produce identical results for equivalent records. Verify LF/CRLF, final and
  interior blank records, whitespace, literal CR, NUL, regex metacharacters, BMP
  Unicode, astral characters, duplicates, and order without wrapper normalization.
- Build the documented sets and assert `(?:foo|ba[rz])`, `f(?:ox?)?`,
  `foo(?:ds?)?`, escaped metacharacters, and the shown Unicode source exactly.
- Reverse phrases and assert input-order differences such as `[ab]` versus `[ba]`.
  Assert that `['9', '1']` yields `[19]`, documenting integer-key enumeration.
- Add duplicates and empty phrases around `foo`; assert source remains `foo`,
  exact membership is true only for `foo`, and empty membership is false.
- Exercise candidate arguments, candidate files, and candidate stdin. Confirm
  compact valid JSON Lines, stable property order, preserved candidate order and
  duplicates, correct escaping, empty stderr, and one final LF.
- Prove the semantic distinction between exact `contains` and unanchored `match`:
  `foo` is both contained and matched, while `food` and `afoo` are not contained
  but are matched; `FOO`, `bat`, and empty text are neither.
- Use generated matching for every ordinary source example and assert every
  non-empty original phrase matches. Use nearby negative strings chosen with the
  unanchored semantics in mind.
- Pass an empty trie to `contains` and assert false results with status 0. Confirm
  empty effective tries produce the exact status-1 diagnostic for build and match.
- Run every README example through the npm script as well as direct CLI spawning.

### Failure and limitation behavior

- Missing/unknown subcommands, unknown/repeated options, invalid option placement,
  conflicting sources, missing candidates, two stdin consumers, and implicit
  terminal phrase input exit 2 with empty stdout.
- Missing/unreadable phrase or candidate files, invalid UTF-8, zero candidate
  records, missing/wrong package versions, and injected library/output failures
  exit 1 without partial output, stacks, or internal paths.
- Characterize rather than hide the upstream escape defects: build U+0008 and
  assert source `\b`; show that `match` does not match the original backspace.
  Build NUL followed by `1` and assert source `\01` plus the corresponding false
  result for the original phrase. Keep these pinned-regression tests clearly marked
  as documented upstream limitations.
- Confirm literal slash output is constructor-ready but not slash-delimited syntax.
  Confirm all regex metacharacters remain inert data and cannot inject captures,
  flags, alternations, or executable JavaScript.
- Run from outside the repository and prove checkout-local dependency resolution.
  In a copied checkout before `npm ci`, help works while version and processing
  requests return only the bootstrap diagnostic.
- Feed a deeply nested long phrase under a timeout and normalize any upstream
  `RangeError`; document that the command does not isolate recursion, CPU, or
  memory use.
- Simulate stdout failures to assert status 1 for non-EPIPE errors and quiet status
  0 for `EPIPE`.

## Acceptance Criteria

- A clean checkout installs exactly regex-trie 1.0.4 and jsesc 0.5.0 through the
  shared npm lockfile without global packages, Git-tag source, or upstream dev
  dependencies.
- The ESM executable loads the CommonJS constructor relative to itself and works
  from any current working directory on the declared Node runtime range.
- `build`, `contains`, and `match` map directly to `toString`, `contains`, and
  `toRegExp`; phrases are added once and wrapper code does not implement trie or
  regex algorithms.
- Phrase and candidate records preserve meaningful bytes and order. Empty phrases,
  duplicate phrases, empty tries, and zero-record candidates have the documented
  distinct behaviors.
- Output preserves upstream spelling and unanchored matching semantics, including
  insertion-order differences, UTF-16 escaping, and the characterized backspace
  and NUL/octal defects.
- Tests cover all input channels and APIs, Unicode and controls, metacharacters,
  exact-versus-substring results, dependency failures, diagnostics, exit statuses,
  EPIPE, Node 20 compatibility, and the aggregate Node regression suite.
- README explicitly states that the library does not accept regex input, optimize
  arbitrary regexes, generate matching text, support empty phrases, anchor output,
  add flags, or guarantee that every control-character phrase roundtrips.

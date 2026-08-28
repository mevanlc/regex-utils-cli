# Plan: oniguruma-parser CLI Exercise

## Summary

Add `bin/oniguruma-parser`, a project-local Node CLI for parsing, regenerating,
traversing, and optimizing Oniguruma pattern bodies with `oniguruma-parser`.
Expose four focused subcommands that map directly to the library's public root,
generator, traverser, and optimizer modules.

This library parses and transforms regex syntax; it is not an Oniguruma matching
engine. The CLI must not execute patterns, infer patterns from samples, generate
matching text, or silently translate them to JavaScript regexes.

## Verified Upstream Facts

- Use [oniguruma-parser 0.12.2](https://www.npmjs.com/package/oniguruma-parser),
  the current npm release from the
  [official repository](https://github.com/slevithan/oniguruma-parser). Pin the
  exact release in the shared npm manifest and lockfile.
- Version 0.12.2 is ESM-only, declares no runtime dependencies, exposes no native
  CLI, and publishes separate entry points for the root wrapper, parser,
  generator, traverser, optimizer, and Unicode data.
- The published package is portable JavaScript with no native build or declared
  operating-system/architecture restriction. This project sets Node 20 as its
  supported runtime floor and fails through npm's engine check on older runtimes.
- `toOnigurumaAst(pattern, options)` validates an Oniguruma pattern body and
  returns an AST. It automatically provides the package's Unicode property data,
  so it is the appropriate parse entry point for this CLI.
- `generate(ast)` returns an object with `pattern` and `flags`. Generation can
  canonicalize syntax even without the optimizer; for example, `a{1,}` regenerates
  as `a+`.
- `traverse(ast, visitor)` visits or transforms nodes in place using node-type
  visitors. A read-only `'*'` visitor can exercise traversal without inventing a
  regex transformation.
- `optimize(pattern, options)` parses, repeatedly applies enabled transformations
  until no further progress is made, and returns canonical `pattern` and `flags`
  strings. Upstream claims preservation of both matched strings and subpattern
  matches.
- Top-level flags are supplied separately from the pattern. Version 0.12.2 accepts
  `i`, `m`, `x`, `D`, `P`, `S`, `W`, `y{g}`, and `y{w}`. In Oniguruma, `m` means
  dotAll; it is not JavaScript or Perl multiline-anchor mode.
- The `captureGroup` rule enables unnamed captures and numbered calls when named
  captures are present. The `singleline` compile-time rule changes `^` and `$` to
  string-oriented assertions; it is distinct from flag `m`.
- The optimizer additionally supports `allowOrphanBackrefs` and named per-
  optimization overrides. Optional transformations are enabled by default.
- Empty pattern bodies are valid. AST quantifiers use JavaScript `Infinity` for an
  unbounded maximum, which vanilla `JSON.stringify` would incorrectly serialize
  as `null`; the CLI needs an explicit JSON representation for that value.
- The parser models Oniguruma 6.9.10 and Unicode 16.0.0. It intentionally rejects
  some rare syntax, including conditionals, non-built-in callouts, code-point
  sequences, and several unusual backreference and flag forms. Its documented
  behavior also differs from Oniguruma in a handful of edge cases.
- Parsing does not run a regex or execute callouts. Built-in callout syntax is AST
  data, while unsupported callouts fail during parsing.

A local feasibility check installed version 0.12.2 under Node 24.16.0 and npm
12.0.2. Direct ESM calls verified empty and Unicode patterns, AST generation,
read-only traversal, generator normalization, all top-level flags, compile-time
rules, optimizer overrides, orphan-backreference handling, and documented error
paths. The package's dependency tree passed `npm audit --omit=dev` with no known
vulnerabilities at the time of planning.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Parse and validate an Oniguruma pattern body into an AST. |
| AST generation | Parse then regenerate a canonical pattern and flags in memory. |
| Traversal | Count node types with a read-only wildcard visitor. |
| Regex optimization | Supported directly through `optimize`, including named disables. |
| Matching-text generation | Unsupported; do not emulate it. |
| Regex inference from samples | Unsupported; do not emulate it. |
| Matching/search | Unsupported; this package does not execute Oniguruma regexes. |

## Files and Dependency Setup

### Shared Node infrastructure

Extend the root Node project defined by the regexp-tree plan. The combined
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
    "oniguruma-parser": "node ./bin/oniguruma-parser",
    "regexp-tree": "node ./node_modules/regexp-tree-cli/bin/regexp-tree-cli",
    "test": "node --test",
    "test:oniguruma-parser": "node --test test/oniguruma-parser.test.js",
    "test:regexp-tree": "node --test test/regexp-tree-cli.test.js"
  },
  "dependencies": {
    "oniguruma-parser": "0.12.2",
    "regexp-tree-cli": "0.0.21"
  }
}
```

`"type": "module"` is required because the dependency exports ESM only and the
extensionless executable should use static ESM syntax. If the regexp-tree test was
already implemented with CommonJS syntax, migrate it to ESM imports or rename it
to `.cjs` when adding this field; do not leave the aggregate `npm test` broken.

Add and lock the dependency with:

```sh
npm install --save-exact oniguruma-parser@0.12.2
```

Commit the updated `package.json` and `package-lock.json`. Reuse the existing
`/node_modules/` ignore rule and clean-checkout bootstrap:

```sh
npm ci
```

Do not install globally, use the third-party CommonJS wrapper, create a second npm
project, or vendor the published distribution.

### Implementation and documentation files

- `bin/oniguruma-parser`: extensionless executable ESM CLI with a Node shebang.
- `test/oniguruma-parser.test.js`: end-to-end tests using Node's built-in test
  runner.
- `package.json` and `package-lock.json`: shared Node infrastructure above.
- `README.md`: add setup, subcommands, pattern/flag rules, examples, output schema,
  supported optimizer controls, and upstream limitations.

Use only Node core modules for argument parsing, input, UTF-8 decoding, JSON, and
errors. In particular, use `node:util`'s `parseArgs`; do not add a CLI framework.

Resolve the installed package relative to the executable and verify its metadata
version is exactly 0.12.2 before a version or processing request. If the package
is absent or wrong, write this to stderr and exit 1:

```text
oniguruma-parser: oniguruma-parser 0.12.2 is not installed; run npm ci
```

Parse and display top-level help before loading the dependency so `--help` remains
available in a clean checkout. Load only the needed ESM entry points after input
and option validation.

## CLI Contract

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

General options:
  -h, --help                      Print help and exit
  -V, --version                   Print command and package version and exit
```

Require exactly one of the four subcommands. Top-level help shows all forms;
subcommand help shows only options valid for that operation. Reject optimizer-
only options on the other three subcommands.

### Pattern input

- Accept exactly one source: one positional `PATTERN`, one `--input FILE`, or
  stdin when neither is present. Reject multiple positional patterns and a
  positional pattern combined with `--input`.
- If stdin would be selected implicitly while attached to a terminal, fail with a
  usage error rather than waiting. `--input -` selects stdin explicitly.
- Treat input as an Oniguruma pattern body, not `/pattern/flags` notation. Supply
  top-level flags with `--flags`. A leading-hyphen pattern requires `--`.
- Read a file or stdin completely without trimming, line splitting, or removing a
  trailing newline. Whitespace is pattern data unless flag `x` makes it
  insignificant.
- Decode file and stdin bytes as strict UTF-8 with a fatal `TextDecoder`. Positional
  input is already a JavaScript string supplied by Node. Preserve NUL and all
  other decoded characters.
- An empty positional argument, zero-byte file, or redirected zero-byte stdin is
  a valid empty pattern. Distinguish it from the absence of a source on an
  interactive terminal.

### Flags and compile-time rules

- Pass `--flags` unchanged to the selected upstream API. Let version 0.12.2
  validate flag syntax; invalid flags are processing errors, not wrapper-defined
  interpretations.
- Supported top-level flag atoms are `i`, `m`, `x`, `D`, `P`, `S`, `W`, `y{g}`,
  and `y{w}`. Repeated flags are accepted by upstream and collapse when generator
  or optimizer output is produced.
- Map `--capture-group` to `rules.captureGroup: true` and `--singleline` to
  `rules.singleline: true`. Omit false-valued rule properties so library defaults
  remain authoritative.
- Map `--allow-orphan-backrefs` only for `optimize`, as
  `rules.allowOrphanBackrefs: true`.
- Convert repeated `--disable-optimization NAME` values into
  `override: {NAME: false}`. Reject duplicates and names not returned by
  `getOptionalOptimizations()` as usage errors.

Version 0.12.2 reports these valid optimization names:

```text
alternationToClass  exposeAnchors         extractPrefix
extractPrefix2      extractSuffix         mergeRanges
optionalize         preventReDoS          removeEmptyGroups
removeUselessFlags  simplifyCallouts      unnestUselessClasses
unwrapNegationWrappers  unwrapUselessClasses  unwrapUselessGroups
useShorthands       useUnicodeAliases     useUnicodeProps
```

Do not expose the low-level parser validation-skip options, arbitrary JavaScript
visitor modules, AST mutation, or a hand-authored AST input format in this focused
CLI.

### API mapping and output

All successful output is UTF-8 JSON formatted with two-space indentation and one
final newline. Use a JSON replacer that emits positive numeric infinity as the
string `"Infinity"`; do not let `JSON.stringify` turn unbounded quantifier maxima
into `null`.

#### `parse`

1. Call `toOnigurumaAst(pattern, {flags, rules})` exactly once.
2. Print the returned AST directly through the documented JSON serializer.

Apart from the explicit `"Infinity"` JSON sentinel, retain upstream property names
and values. Do not add source locations, wrapper metadata, or a JavaScript-regex
interpretation.

#### `roundtrip`

1. Call `toOnigurumaAst` with the same common options.
2. Pass that AST directly to `generate` exactly once.
3. Print the returned `{pattern, flags}` object.

This exercises the generator in memory and intentionally exposes its canonical
rendering. Do not accept arbitrary AST JSON: the upstream AST contains non-JSON
values such as `Infinity`, and a wrapper-defined mutable AST interchange format
would obscure whether failures came from the library.

#### `traverse`

1. Parse once with `toOnigurumaAst`.
2. Call `traverse` once with a read-only `'*'` visitor.
3. Count each visited `node.type`, sort type names lexically, and print:

```json
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
```

The shown result is for `^.*`. Counting is CLI presentation logic only; never
modify, remove, replace, or annotate AST nodes in the visitor.

#### `optimize`

1. Obtain valid override names from `getOptionalOptimizations()`.
2. Call `optimize(pattern, {flags, rules, override})` exactly once.
3. Print the returned `{pattern, flags}` object.

Do not add fixed-point logic; the upstream optimizer already iterates internally.
Do not claim an output is shorter or faster for every input, even though specific
transforms target those properties.

### Exit and diagnostic behavior

- Help exits 0 and writes only stdout. `--version` writes
  `oniguruma-parser 0.12.2` to stdout and exits 0.
- Successful subcommands exit 0 and leave stderr empty, including empty patterns.
- Missing or unknown subcommands, unknown options, invalid operand counts,
  conflicting sources, optimizer-only option misuse, duplicate/unknown
  optimization names, or implicit terminal input exit 2 with empty stdout.
- Missing/wrong dependencies, unreadable files, invalid UTF-8, invalid Oniguruma
  patterns or flags, unsupported syntax, and upstream API exceptions exit 1 with
  empty stdout.
- Prefix concise diagnostics with `oniguruma-parser:` and write them to stderr.
  Report upstream `Error.message` without a stack trace; do not expose internal
  paths or partially serialized JSON.
- Buffer serialization before the single stdout write. Treat `EPIPE` as a quiet
  success with status 0; report every other stdout error and exit 1.

### Examples

Parse an unbounded quantifier; note the lossless JSON sentinel:

```console
$ npm run --silent oniguruma-parser -- parse 'a{1,}'
{
  "type": "Regex",
  "body": [
    {
      "type": "Alternative",
      "body": [
        {
          "type": "Quantifier",
          "kind": "greedy",
          "min": 1,
          "max": "Infinity",
          "body": {
            "type": "Character",
            "value": 97
          }
        }
      ]
    }
  ],
  "flags": {
    "type": "Flags",
    "ignoreCase": false,
    "dotAll": false,
    "extended": false,
    "digitIsAscii": false,
    "posixIsAscii": false,
    "spaceIsAscii": false,
    "wordIsAscii": false,
    "textSegmentMode": null
  }
}
```

Regenerate the same pattern canonically:

```console
$ npm run --silent oniguruma-parser -- roundtrip 'a{1,}'
{
  "pattern": "a+",
  "flags": ""
}
```

Optimize upstream's documented example:

```console
$ npm run --silent oniguruma-parser -- optimize \
  '(?x) (?:\!{1,}) (\b(?:ark|arm|art)\b) [[^0-9A-Fa-f]\P{^Nd}\p{ Letter }]'
{
  "pattern": "!+\\b(ar[kmt])\\b[\\H\\d\\p{L}]",
  "flags": ""
}
```

Exercise traversal:

```console
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
```

## Implementation Milestones

1. **Extend the Node foundation.** Add ESM project mode, the Node engine floor,
   the exact dependency and scripts, regenerate the shared lockfile, and prove
   both Node CLI test files still run.
2. **Build common CLI plumbing.** Add subcommand dispatch, strict core argument
   parsing, source selection, fatal UTF-8 decoding, deferred dependency checks,
   JSON serialization, help/version, and status-separated diagnostics.
3. **Implement parse and roundtrip.** Map flags/rules to `toOnigurumaAst`, preserve
   Infinity in JSON, and exercise `generate` without an external AST schema.
4. **Implement traversal and optimization.** Add read-only node counts, runtime-
   validated named disables, orphan-backreference control, and direct optimizer
   output.
5. **Test and document.** Cover every source, subcommand, option, edge case, and
   failure; update README; then validate the locked install and aggregate Node
   suite from a clean checkout.

## Test Plan

Use ESM imports from `node:test`, `node:assert/strict`, `node:child_process`, and
temporary-file helpers. Spawn the CLI with `process.execPath` and the absolute
`bin/oniguruma-parser` path so tests exercise the checkout implementation without
shell reconstruction.

### Dependency and static checks

```sh
npm ci
npm ls oniguruma-parser regexp-tree-cli regexp-tree
npm run --silent oniguruma-parser -- --version
npm run test:oniguruma-parser
npm test
npm audit --omit=dev
```

Assert the exact 0.12.2 dependency, unchanged lockfile after `npm ci`, correct
version output, absence of a global dependency, and continued regexp-tree test
success under root ESM mode. Treat future audit findings as review triggers rather
than applying unreviewed forced upgrades.

### Successful behavior

- Top-level and subcommand help plus version write only stdout and exit 0. Help
  works before dependencies are installed; version gives the actionable missing-
  dependency error when they are absent.
- Positional, file, explicit stdin, and implicit redirected-stdin sources produce
  identical outputs for identical patterns. File/stdin preserve trailing newlines,
  spaces, and NUL; an empty source successfully parses as an empty pattern.
- Parse ordinary constructs, Unicode characters/properties, named captures,
  subroutines, lookarounds, character-class intersections, possessive quantifiers,
  built-in callouts, and compile-time rules. Assert AST node semantics rather than
  only process success.
- Parse `a{1,}` and assert that `max` is the string `"Infinity"`, never `null`.
  Confirm all successful stdout parses as JSON and ends with one newline.
- Roundtrip empty, Unicode, flags, escaped, and advanced patterns. Assert
  `a{1,}` becomes `{pattern: "a+", flags: ""}` and repeated flags canonicalize.
- Traverse `^.*` and assert the exact shown count object. Use other patterns to
  prove `Flags`, nested alternatives, captures, backreferences, and Unicode
  characters are each visited without AST mutation.
- Optimize the documented example to
  `!+\b(ar[kmt])\b[\H\d\p{L}]`. Exercise prefix/suffix extraction, class merging,
  optionalization, shorthand use, and ReDoS prevention with representative exact
  or structural outputs.
- Disable `alternationToClass` and prove `a|b` remains `a|b`; compare with the
  default `[ab]`. Cover repeated distinct disables and all runtime-reported names.
- Verify `--capture-group` allows `(a)(?<b>b)\1`, `--singleline` changes the `^$`
  assertion kinds, and `--allow-orphan-backrefs` lets optimizer output `\1`.
- Run every README example through the npm script in addition to direct CLI test
  spawning.

### Failure and safety behavior

- Missing/unknown subcommands, unknown options, extra operands, conflicting input
  sources, optimizer-only options on other commands, and invalid/duplicate
  optimization names exit 2 with empty stdout.
- Missing/unreadable files, invalid UTF-8, invalid flags such as `g`, unmatched
  syntax, unsupported conditionals such as `(?(1)a|b)`, non-built-in callouts,
  default-disallowed orphan backreferences, and named/numbered capture rule errors
  exit 1 with no JSON fragment or stack trace.
- Run outside the repository and confirm the executable finds its project-local
  dependency. In a clean copied checkout before `npm ci`, help works and processing
  gives the exact bootstrap diagnostic without falling through to a global module.
- Pattern text resembling JavaScript, callouts, or replacement directives remains
  inert data. Sentinel files and globals prove parsing, traversal, generation, and
  optimization never evaluate input as code.
- Feed a deeply nested or very large pattern under a test timeout and assert the
  process either succeeds or reports an upstream failure; document that the CLI
  is not a resource-isolation sandbox.
- Simulate serialization and stdout failures to verify buffered output and status
  1 behavior; verify that `EPIPE` is quiet and exits 0.

## Acceptance Criteria

- A clean checkout installs exactly oniguruma-parser 0.12.2 through the shared
  npm lockfile and runs without global packages or a CommonJS compatibility shim.
- All four subcommands map to the named upstream APIs and pass pattern, flags,
  compile-time rules, and optimizer controls without implementing regex logic.
- Parse output preserves unbounded maxima, roundtrip exposes generator
  canonicalization, traversal is read-only, and optimization is called only once.
- Tests cover all sources, empty and Unicode patterns, flags/rules, representative
  Oniguruma syntax, optional optimization controls, package limitations, safety,
  output schemas, diagnostics, and exit statuses.
- Matching, sample inference, matching-text generation, JavaScript transpilation,
  arbitrary visitors, and arbitrary AST mutation remain explicitly out of scope.
- README documents Oniguruma 6.9.10/Unicode 16 semantics, the separate pattern and
  flag inputs, `m` versus `singleline`, the `"Infinity"` JSON sentinel, unsupported
  syntax, and the fact that this parser does not execute regexes.

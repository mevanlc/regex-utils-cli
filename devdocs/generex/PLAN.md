# Plan: Generex JVM CLI Exercise

## Summary

Add `bin/generex`, a project-local JVM CLI for
[`mifmif/Generex`](https://github.com/mifmif/Generex). Pin the latest published
Maven Central artifact, `com.github.mifmif/generex 1.0.2`, in the shared
`deps.edn` graph and call its public generation APIs from a small Clojure
namespace. Expose bounded enumeration, seeded random generation, first and
indexed values, and finite/infinite cardinality without reimplementing the
automaton traversal.

String results use JSON Lines so empty strings, whitespace, newlines, and other
controls remain unambiguous. Counts remain one plain integer or `infinite`.

## Verified Upstream Facts

- The authoritative source is
  [`mifmif/Generex`](https://github.com/mifmif/Generex), licensed Apache-2.0.
- Maven Central reports `1.0.2` as the latest published version. Tag `1.0.2`
  resolves to commit `e910243ffb174b0d71f3207d2d288485999878d2`; later source
  changes are not a published release and must not be substituted implicitly.
- The Generex JAR SHA-256 is
  `8f8ce233c335e08e113a3f9579de1046fb19927e82468b1bbebcd6cba8760b81`.
  Its sole runtime dependency is `dk.brics.automaton/automaton 1.11-8`, whose
  JAR SHA-256 is
  `a24475f6ccfe1cc7a4fe9e34e05ce687b0ce0c6e8cb781e0eced3b186482c61e`.
- The package has no maintained CLI. Its defining public methods are
  `iterator()`, `random()`, `random(min)`, `random(min,max)`, `setSeed(long)`,
  `getFirstMatch()`, `getMatchedString(int)`, `matchedStringsSize()`, and
  `isInfinite()`.
- Generex compiles through `dk.brics.automaton.RegExp`, not `java.util.regex`.
  It expands `\d`, `\D`, `\s`, `\S`, `\w`, and `\W` to its own predefined
  character sets. Java lookarounds and backreferences are not part of this
  regular-language dialect.
- Enumeration follows the upstream automaton iterator. It can be infinite and
  callers must bound consumption. The project wrapper defaults to 20 values.
- `matchedStringsSize()` and indexed lookup construct an internal transaction
  tree. They are appropriate for finite, reasonably sized languages, but can
  overflow counters or exhaust stack/memory for large automata. The wrapper
  checks `isInfinite()` before counting.
- `getMatchedString()` is one-based. The wrapper rejects zero and negative
  indices rather than retaining the upstream zero-means-one special case.
- Seeded random generation delegates to Generex's `java.util.Random`. Length
  constraints use Java `String.length()`, so they count UTF-16 code units.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Matching-text generation | Core operation: enumerate or randomly sample strings accepted by the upstream automaton. |
| Cardinality and indexed access | Expose finite/infinite detection, first value, and one-based indexed lookup. |
| Regex inference | Unsupported. |
| Regex optimization | Unsupported beyond automaton compilation internal to Generex. |
| Matching/search | Unsupported as a CLI operation; do not add another regex engine. |

## Dependency and Files

- Add `com.github.mifmif/generex {:mvn/version "1.0.2"}` to the root
  `deps.edn`. Retain the shared project-local Maven repository and Clojure CLI.
- Add the two new runtime JARs and exact digests to `jvm-deps.sha256`; the
  existing verifier must continue rejecting any unlisted JAR.
- Add `:paths ["src"]` and a `:generex` alias whose main namespace is
  `generex-cli`.
- Add `src/generex_cli.clj`, `bin/generex`, and
  `test/generex_cli_test.sh`.
- Extend the README and the seven-recipe Just interface. Generex and Frak share
  `.deps/` and `.cpcache/`, so their dependency and build cleanup recipes have
  shared scope.

Bootstrap and verify with:

```sh
./tools/bootstrap-clojure
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Srepro -P
./tools/verify-jvm-deps
```

## CLI Contract

```text
Usage:
  generex enumerate [OPTIONS] PATTERN
  generex random [OPTIONS] PATTERN
  generex first [OPTIONS] PATTERN
  generex nth [OPTIONS] PATTERN INDEX
  generex count [OPTIONS] PATTERN

Pattern input:
  PATTERN                    dk.brics automaton regex as one argument
  -i, --input FILE           Read the complete regex; use - for stdin

Generation options:
  -n, --limit NUMBER         enumerate: maximum values; default 20
  -n, --count NUMBER         random: number of values; default 1
      --seed LONG            Seed java.util.Random reproducibly
      --min-length NUMBER    Minimum random value length
      --max-length NUMBER    Maximum random value length
```

All string-producing commands write one compact JSON object per result:

```json
{"value":"ab"}
```

`enumerate` calls the upstream iterator and stops after `--limit` values or
iterator exhaustion. `random` reuses one Generex object, optionally calls
`setSeed()`, and calls the matching random overload once per requested value.
`first`, `nth`, and `count` map directly to the methods listed above.

The pattern comes from exactly one positional argument or one complete strict-
UTF-8 file/stream. File content is not trimmed. Use `--` before a positional
pattern beginning with `-`. Success is 0, CLI misuse is 2, and regex, input, or
processing failure is 1. Diagnostics use the `generex:` prefix on stderr.

## Implementation Milestones

1. Extend and resolve the exact JVM graph, then update the runtime digest list.
2. Add the Clojure namespace and executable-relative launcher.
3. Implement strict pattern input and the five direct API operations.
4. Add JSON escaping, deterministic seed handling, help/version, and stable
   process errors.
5. Add subprocess tests, README usage, and all Just lifecycle recipes.

## Acceptance

- `./tools/verify-jvm-deps` accepts exactly the seven pinned runtime JARs.
- Help and version work, including from a working directory outside the repo.
- `[ab]{1,2}` enumerates the upstream order and respects zero/nonzero limits.
- Seed 42 produces repeatable constrained random values.
- Finite and infinite count paths, first value, and one-based indexed lookup
  exercise their distinct upstream methods.
- Complete file/stdin patterns, Unicode, empty/control values, leading-hyphen
  patterns, invalid UTF-8, bad regexes, source conflicts, and missing local
  tooling have asserted stdout, stderr, and exit statuses.
- `just generex-clean-build`, `generex-clean-deps`, and `generex-clean` honor the
  documented shared JVM scopes and can be followed by a clean rebuild.


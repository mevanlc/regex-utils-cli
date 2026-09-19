# Plan: Frak JVM CLI Exercise

## Summary

Exercise [`noprompt/frak`](https://github.com/noprompt/frak) through its existing
`frak.cli` JVM entry point. Add a fully pinned root `deps.edn`, a project-local
official Clojure CLI bootstrap, and runtime artifact checks, then invoke the
upstream command directly with `clojure -M:frak`. Do not add `bin/frak` or another
argument/output adapter.

The published CLI performs Frak's defining operation: it turns positional strings
into a trie-factored regex and exposes exact anchoring, capturing groups, and the
escape-character policy. Its limitations remain part of the interface: it has no
stdin/file input, version flag, whole-word flag, matching command, or stable branch
ordering. Document and test those facts rather than extending the command in this
project.

## Verified Upstream Facts

- The authoritative source is
  [`noprompt/frak`](https://github.com/noprompt/frak). It is an Eclipse Public
  License 1.0 Clojure/ClojureScript library whose latest source commit and release
  are from April 2019.
- [Clojars](https://clojars.org/frak) reports `frak/frak 0.1.9` as the latest
  published artifact. Tag `v0.1.9` and its POM identify immutable commit
  [`355bf7a39b0cd3fa8714dc602d70b230c189b39c`](https://github.com/noprompt/frak/commit/355bf7a39b0cd3fa8714dc602d70b230c189b39c).
  Pin the registry artifact; do not resolve the dormant `master` branch.
- The 0.1.9 JAR SHA-256 is
  `4b0da44baf0be21c484bdf17789142f4cfb2d2638db4ae271a4002bdb126f422`.
  The JAR contains AOT-compiled `frak`, `frak.cli`, and `frak.platform` classes, so
  its published CLI can be called without checking out or compiling upstream.
- The legacy POM declares Clojure 1.8.0, ClojureScript 0.0-2156, and
  `org.clojure/tools.cli 0.3.1`. The JVM CLI does not load ClojureScript; explicitly
  exclude that obsolete, large dependency instead of resolving it.
- Use current Clojure runtime `org.clojure/clojure 1.12.5`, with
  `spec.alpha 0.5.238` and `core.specs.alpha 0.4.74`, while retaining the CLI's
  `tools.cli 0.3.1`. All are explicit root coordinates so the runtime graph is
  independent of Frak's old Clojure pin.
- Frak's public `string-pattern` constructs a trie from input strings and renders
  regex source. `pattern` calls the same operation and compiles it with the host
  Clojure/JVM regex engine, but the CLI deliberately calls `string-pattern` and
  prints source without compiling it.
- Trie nodes store children in Clojure sets. The renderer shares prefixes, creates
  character classes for compatible leaves, makes suffixes optional, escapes
  configured characters, and performs two post-render grouping rewrites.
- The result is language-oriented but not canonically spelled. Hash-set and grouped
  map iteration can change alternative and character-class order. On the verified
  runtime, `foo bar baz quux` rendered `(?:quux|foo|ba[zr])`, while upstream's older
  README shows `(?:ba[rz]|foo|quux)`. Both represent the same input language.
- Duplicate inputs collapse in the trie. Empty strings are ignored during trie
  insertion: `foo`, an empty argument, and `foot` render the same `foot?` as the two
  nonempty strings. A lone empty string renders an empty pattern, or `^$` with
  `--exact`.
- By default Frak escapes `\ ^ $ * + ? . | ( ) { } [ ]`. The CLI's
  `--escape-chars CHARS` replaces that set with the characters in `CHARS`; it does
  not add to the defaults.
- `--escape-chars :default` selects the default set and `:vim` selects the exported
  Vim very-magic set. An unknown keyword resolves to no set and therefore disables
  escaping rather than producing a usage error. An empty literal value also disables
  escaping. Because the CLI does not compile output, insufficient escaping can emit
  invalid or semantically broader regex source and still exit successfully.
- `--exact` wraps the complete rendered pattern in `^` and `$`. It changes only the
  generated source; the CLI performs no match.
- `--capture` changes groups the renderer needs from `(?:...)` to `(...)`. It does
  not force a group when factoring needs none, so some successful capture-mode
  outputs contain no capture group.
- The library supports `:whole-words?`, but `frak.cli/main-flags` does not expose it.
  Reusing the existing CLI means whole-word generation remains unavailable from this
  project's command. Do not add a wrapper solely to surface that option.
- The CLI accepts only argv strings. It has no file or stdin record reader, so input
  is subject to the operating system's argument-size limit and cannot contain NUL.
  Shell quoting can still supply empty strings, spaces, LF, Unicode, and regex
  metacharacters as single arguments.
- `-h`/`--help`, or invoking the command with no positional strings, prints the same
  usage text to stdout and exits 0. Help wins even when words are present.
- Unknown options and a missing `--escape-chars` value print the `tools.cli` message
  to stderr and exit 1, with no usage text. Duplicate boolean options are accepted.
  `--` ends option parsing and permits words such as `-e` or `--help`.
- Successful generation writes the pattern and one LF to stdout, nothing to stderr,
  then calls `System/exit(0)`. The CLI offers no `--version`, structured output,
  diagnostic prefix, or configurable exit-status scheme.
- Regex inference from positive literal examples and its construction-time factoring
  are Frak's supported capability. It does not accept negative samples, optimize an
  existing regex, generate matching strings, or provide a matching/search CLI.

A local feasibility probe installed the official
[Clojure CLI 1.12.5.1664](https://github.com/clojure/brew-install/releases/tag/1.12.5.1664)
under a temporary project prefix and resolved only the five planned runtime JARs
into a project-local Maven repository. The published Frak CLI ran successfully with
JDK 21.0.11 and Clojure 1.12.5. All three upstream tests (20 assertions) passed
against tag `v0.1.9` on that runtime. Direct probes confirmed help/errors, exact and
capture modes, escape policies, empty strings, leading-hyphen words, duplicate
options, metacharacters, Unicode, and noncanonical branch order.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Supported directly by upstream CLI: infer and render a trie-factored regex from positive literal argv strings. |
| Regex inference from samples | Supported for positive literals; empty inputs are ignored and there are no negative examples or weights. |
| Regex optimization | Supported only as construction-time prefix factoring and grouping rewrites; existing regex input is unsupported. |
| Exact/capture/escaping controls | Supported directly by upstream CLI and included in the plan. |
| Whole-word rendering | Supported by the library but absent from the upstream CLI; intentionally unavailable without a wrapper. |
| Matching/search | Not a Frak CLI operation; consumers may compile the emitted regex separately, but this plan does not add that composition. |
| Matching-text generation | Unsupported; do not emulate it. |

## Files and Dependency Setup

### Project-local Clojure tools

Add `tools/bootstrap-clojure`, an executable POSIX shell bootstrapper for official
Clojure CLI version `1.12.5.1664`. Pin this archive and digest:

```text
https://github.com/clojure/brew-install/releases/download/1.12.5.1664/clojure-tools-1.12.5.1664.tar.gz
77dd6868948074adcc93e83a796f8e8f15a1a92bcb1b9002d715fd2210e476f3
```

The script must:

1. Resolve the repository root from its own location and require `java`, `curl`,
   `tar`, `sed`, and either `sha256sum` or `shasum` on `PATH`.
2. Require Java 17 or newer before downloading anything; print the detected runtime
   in verbose/error diagnostics but not during a successful cached bootstrap.
3. Download into a `mktemp` directory beneath the repository's `.deps/`, follow the
   official HTTPS redirects, verify the exact archive SHA-256 before extraction, and
   reject content that fails the digest.
4. Install the distribution beneath `.deps/clojure/`: data and JARs under
   `lib/clojure`, launchers under `bin`, and man pages under `share/man/man1`. Replace
   only the archive's documented `PREFIX` and `BINDIR` placeholders and preserve
   executable modes.
5. Build the installation in a sibling temporary directory and rename it into place
   only after `bin/clojure -Sdescribe` reports version `1.12.5.1664`. Clean only its
   exact temporary paths on failure; never recursively target the repository root,
   `$HOME`, or an unresolved variable.
6. Treat an already valid installation as success without network access. If
   `.deps/clojure/` exists but is incomplete or has another version, fail with an
   instruction to remove that exact directory and rerun; do not overwrite it.

This bootstrapper installs runtime tooling only; it must not proxy Frak arguments.
No global Clojure CLI or Leiningen installation is required.

### Pinned JVM dependency graph

Add this root `deps.edn`:

```clojure
{:mvn/local-repo ".deps/m2"
 :mvn/repos {"central" {:url "https://repo.maven.apache.org/maven2/"}
             "clojars" {:url "https://repo.clojars.org/"}}
 :deps {org.clojure/clojure {:mvn/version "1.12.5"}
        org.clojure/spec.alpha {:mvn/version "0.5.238"}
        org.clojure/core.specs.alpha {:mvn/version "0.4.74"}
        org.clojure/tools.cli {:mvn/version "0.3.1"}
        frak/frak {:mvn/version "0.1.9"
                   :exclusions [org.clojure/clojure
                                org.clojure/clojurescript
                                org.clojure/tools.cli]}}
 :aliases {:frak {:main-opts ["-m" "frak.cli"]}}}
```

The explicit exclusions remove Frak's obsolete language runtime and unused
ClojureScript dependency. The root coordinates supply every runtime JAR at an exact
version. Do not add upstream source paths, Leiningen plugins, JavaScript compilation,
or a mutable Git coordinate.

Add `jvm-deps.sha256` with these exact runtime artifact checks:

```text
4b0da44baf0be21c484bdf17789142f4cfb2d2638db4ae271a4002bdb126f422  .deps/m2/frak/frak/0.1.9/frak-0.1.9.jar
dfdee131460216a84fef22e537bb0d0579965f8f70338d748323dff26f8e5a8b  .deps/m2/org/clojure/clojure/1.12.5/clojure-1.12.5.jar
eb73ac08cf49ba840c88ba67beef11336ca554333d9408808d78946e0feb9ddb  .deps/m2/org/clojure/core.specs.alpha/0.4.74/core.specs.alpha-0.4.74.jar
94cd99b6ea639641f37af4860a643b6ed399ee5a8be5d717cff0b663c8d75077  .deps/m2/org/clojure/spec.alpha/0.5.238/spec.alpha-0.5.238.jar
0e5f720bfd0f55029caf9c40ffc8b1478e8cc9be026eedda421a83456595de68  .deps/m2/org/clojure/tools.cli/0.3.1/tools.cli-0.3.1.jar
```

Add `tools/verify-jvm-deps`, an executable POSIX shell verifier that resolves the
root from its own path, changes to it, selects `sha256sum -c` or `shasum -a 256 -c`,
and checks `jvm-deps.sha256`. It must also enumerate JARs under `.deps/m2` and fail
if any are absent from the manifest. Compare `clojure -Stree` against Frak's exact
five-node closure within the checked-in shared JVM graph as a separate acceptance
gate so a changed POM cannot introduce an unlisted runtime artifact.

Append these project-local generated paths to `.gitignore`:

```gitignore
# JVM and Clojure
/.deps/
/.cpcache/
```

### Bootstrap and invocation

From the repository root, bootstrap and prepare dependencies with:

```sh
./tools/bootstrap-clojure
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Srepro -P -M:frak
./tools/verify-jvm-deps
```

`CLJ_CONFIG` and `CLJ_CACHE` keep even user configuration/tool caches inside the
checkout. `-Srepro` excludes `~/.clojure/deps.edn`; the root `:mvn/local-repo` keeps
all Maven artifacts beneath `.deps/m2`. The bootstrap requires network access only
on the first installation/resolution. With every exact artifact prepared, normal
Frak invocation succeeds while network access is unavailable.

The normal direct invocation is:

```sh
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Srepro -M:frak -e foo foot
```

Run from the repository root so Clojure finds the checked-in `deps.edn` and its
relative local repository. Do not add a `bin/frak` wrapper, shell alias, globally
installed command, copied upstream source, or precompiled project JAR.

### Implementation and documentation files

- `deps.edn`: exact JVM graph and direct `:frak` main alias.
- `jvm-deps.sha256`: checked-in runtime JAR integrity manifest.
- `tools/bootstrap-clojure`: pinned project-local Clojure CLI installer.
- `tools/verify-jvm-deps`: runtime artifact verifier.
- `.gitignore`: generated Clojure tooling, Maven repository, and classpath cache.
- `test/frak_cli_test.sh`: subprocess tests of the direct upstream CLI.
- `README.md`: JDK/tool prerequisites, bootstrap, exact invocation, upstream flags,
  examples, output instability, and limitations. Create the root README if the
  implementation sequence has not already done so.

## Direct CLI Contract

The project does not define a new interface. It documents and tests the published
one under the full project-local command prefix:

```text
Usage: frak <flags*> <strings+>

Flags:
  -e, --exact                      Generated pattern requires an exact match
  -c, --capture                    Generated pattern captures
  -E, --escape-chars :KEY|'CHARS'  Set of characters to escape in generated pattern
  -h, --help                       Display this help message
```

The effective shell form is:

```text
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Srepro -M:frak [FLAG...] STRING...
```

Do not place an extra `--` between `-M:frak` and ordinary Frak options: doing so
ends Frak's own option parsing and makes `-e`, `-c`, or `-E` input strings. Use `--`
there intentionally when the first remaining string begins with `-`.

### Inputs and options

- Each positional is one complete input string as delivered by the Java launcher;
  Frak receives Java/Clojure strings. Shell quoting is responsible for spaces, tabs,
  LF, empty strings, glob characters, and leading hyphens. NUL and values beyond the
  OS argv limit are unavailable.
- There is no stdin or file option. Redirected stdin is ignored; it must not be
  described as an input path. Use shell argument construction only within safe OS
  limits, and do not add `xargs` as part of the supported contract because batching
  changes the inferred regex.
- Options may precede or be interspersed with positional strings until `--`.
  Repeating boolean options is accepted and remains idempotent.
- `--exact` passes `:exact? true` and adds `^`/`$` around the complete result.
- `--capture` passes `:capture? true`; only groups selected by upstream factoring
  become capturing.
- `--escape-chars` consumes exactly one value. A leading colon selects a keyword;
  only `:default` and `:vim` are defined. A value without a leading colon is treated
  as the complete literal set of characters to escape, with duplicates collapsing
  in a set. It replaces, rather than augments, the default.
- `--help` takes no value. With or without positional strings it prints help and
  discards generation. No version flag exists.

### Output and failures

- A successful generation calls `frak/string-pattern` exactly once and writes its
  returned source plus one LF to stdout. The command never compiles or tests it.
- Treat branch and character-class order as unspecified. Exact-string assertions
  are permitted only for shapes with one deterministic spelling; otherwise compile
  the emitted pattern with the JVM regex engine and assert positive/negative
  language semantics.
- No arguments and explicit help write the exact upstream usage block to stdout,
  nothing to stderr, and exit 0.
- Unknown/malformed options write the unprefixed `tools.cli 0.3.1` message to stderr,
  no stdout, and exit 1. Dependency resolution and JVM failures retain their native
  stderr and nonzero status. There is no upstream exit status 2.
- Because this is direct invocation, do not intercept exceptions, normalize
  diagnostics, buffer output, translate broken-pipe behavior, or add JSON. Tests
  should characterize the pinned upstream/JVM process rather than demand wrapper
  semantics.

## Representative Invocations

Use the full direct invocation in documentation; do not introduce a `CLJ` helper or
project command:

```sh
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Srepro -M:frak -e foo foot
```

```text
^foot?$
```

The common-prefix case has a deterministic spelling and shows exact anchoring.

```sh
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Srepro -M:frak foo bar baz quux
```

One valid result on the pinned runtime is:

```text
(?:quux|foo|ba[zr])
```

Tests must also accept semantically equivalent alternative/class orderings.

```sh
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Srepro -M:frak -E :vim 'a-b'
```

```text
a\-b
```

To infer from strings that resemble options:

```sh
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Srepro -M:frak -- -e foo
```

One valid output is `(?:-e|foo)` plus LF.

## Implementation Milestones

1. Add `deps.edn` with Frak's exact five-JAR closure, exclusions, repositories,
   local Maven path, and `:frak` main alias. Verify the published entry point is
   present. Keep later additions to the shared JVM graph explicit and independently
   integrity-checked.
2. Add the pinned Clojure CLI bootstrap and ignore rules; prove a clean JDK-only
   checkout installs tooling entirely under `.deps/` and honors cached/offline use.
3. Add the artifact hash manifest and verifier; prepare dependencies, verify every
   hash, assert the exact dependency tree, and reject contamination from user config.
4. Run the upstream CLI directly and characterize help, errors, generation, every
   flag, argv edge cases, output ordering, and unsupported surfaces.
5. Add the direct-process shell tests and README documentation. Re-run them on the
   minimum supported JDK and current LTS JDK from a clean project-local cache.

## Test Plan

### Tooling and dependency gates

From a clean checkout with only a JDK and the documented POSIX utilities available:

```sh
./tools/bootstrap-clojure
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Sdescribe
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Srepro -P -M:frak
./tools/verify-jvm-deps
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Srepro -Stree
```

Assert tool version `1.12.5.1664`, project/local config and cache paths, Frak's exact
five-node closure within the checked-in shared JVM tree, all recorded hashes, no
ClojureScript, and no artifacts outside `.deps/`. Run the bootstrap and a known Frak
command again with network disabled; assert neither requires a download or changes
the installation.

Test with Java 17 and the current LTS JDK. Fail before download with a concise
bootstrap diagnostic for missing/old Java, missing hash utility, corrupt archive,
unwritable target, and an existing mismatched installation.

### Upstream source characterization

Clone upstream and detach at the recorded `v0.1.9` commit beneath ignored
`.deps/upstream/frak/`. From the project root, add its `src/cljc` and `test` paths
with `-Sdeps`, require `frak-test`, and run `clojure.test/run-tests`:

```sh
git clone https://github.com/noprompt/frak.git .deps/upstream/frak
git -C .deps/upstream/frak checkout --detach 355bf7a39b0cd3fa8714dc602d70b230c189b39c
test "$(git -C .deps/upstream/frak rev-parse HEAD)" = 355bf7a39b0cd3fa8714dc602d70b230c189b39c
CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" \
  ./.deps/clojure/bin/clojure -Srepro \
  -Sdeps '{:paths [".deps/upstream/frak/src/cljc" ".deps/upstream/frak/test"]}' \
  -M -e '(require (quote frak-test)) (let [{:keys [fail error]} (clojure.test/run-tests (quote frak-test))] (System/exit (if (zero? (+ fail error)) 0 1)))'
```

Assert the summary is exactly three tests, 20 assertions, zero failures, and zero
errors on both JDK endpoints. This gate tests source against the pinned modern
runtime; it does not become a runtime source dependency.

### Direct CLI behavior

Run the direct-process harness:

```sh
./test/frak_cli_test.sh
```

It must use the full project-local command prefix and:

- Compare no-argument, `-h`, and `--help` output to the exact four-flag upstream
  usage block; assert stdout-only and exit 0, including help mixed with words.
- Verify the deterministic `-e foo foot` output is `^foot?$` plus LF. Exercise long
  and short forms of exact, capture, and escape characters.
- For branching inputs, compile emitted source with Java/Clojure regex and assert
  every supplied nonempty string matches while representative prefixes and unrelated
  strings do not. Permute and duplicate inputs without requiring identical spelling.
- Verify default escaping and `:default`, `:vim`, a literal replacement set, an empty
  set, and an unknown keyword. Confirm under-escaped output can succeed even when a
  later independent compile rejects or broadens it.
- Verify one empty argument, empty-plus-nonempty inputs, whitespace, embedded LF,
  Unicode, metacharacters, duplicate inputs, option-looking strings after `--`, and
  the OS inability to supply NUL. Assert stdin content is ignored.
- Verify `--capture` changes only groups Frak actually emits. Compile the output and
  assert capture-group behavior rather than assuming a fixed number for all tries.
- Assert unknown options and missing `-E` values write only the current upstream
  diagnostic to stderr and exit 1. Characterize duplicate flags as successful.
- Copy the prepared Maven repository into a temporary-checkout fixture, remove or
  corrupt a runtime JAR there, and assert native Clojure/JVM or integrity-verifier
  failure. Do not mutate the developer's prepared `.deps/m2` during failure tests.
- Characterize closed-pipe behavior without requiring a wrapper-specific EPIPE
  diagnostic or exit code.

## Acceptance Criteria

- A clean POSIX checkout with JDK 17+ bootstraps the pinned official Clojure CLI and
  the complete checked-in shared JVM graph entirely beneath ignored project-local
  paths, with archive and JAR integrity checks passing.
- `deps.edn` excludes unused ClojureScript and old language coordinates, resolves
  only the documented graph, ignores user Clojure configuration under `-Srepro`, and
  supports prepared offline invocation.
- Frak is invoked directly through `-M:frak`; no `bin/frak`, behavior adapter,
  vendored source, global package, Leiningen project, or Node build is introduced.
- Help, options, argv-only input, raw regex output, noncanonical ordering, empty
  strings, diagnostics, and exit statuses match upstream 0.1.9 exactly.
- The 20 upstream assertions, direct CLI test matrix, both JDK endpoint runs,
  clean-cache bootstrap, repeated cached bootstrap, integrity verification, and
  offline smoke test all pass.

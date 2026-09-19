# Plan: Create Per-Library CLI Exercise Plans

## Goal

Create one implementation-ready plan for each library in the inventory below. Each
child plan will describe how to add the dependency to this project and expose its
useful capabilities through a command-line exercise tool.

This meta-plan creates planning documents only. Creating dependency manifests,
installing packages, writing CLI code, and running the resulting tools belong to
the child plans and their later implementation.

## Decisions

- Put each child plan at `devdocs/<library-slug>/PLAN.md`.
- Put new project-local executables in `bin/<library-slug>`.
- Reuse an upstream CLI without a redundant `bin/` wrapper when the dependency
  already provides a suitable command. The child plan must still document the
  project-local dependency, exact invocation, inputs, outputs, and validation.
- Cover each library's core capabilities. Also cover optimization, generation of
  text samples that match a regex, inference of a regex from samples, and
  matching/search when the library supports them. Explicitly mark inapplicable
  capability categories instead of inventing substitute behavior.
- Use a plain Unix CLI style: options and positional arguments, newline-delimited
  stdin where natural, primary results on stdout, diagnostics on stderr, useful
  exit statuses, and `--help`.
- Keep all dependencies project-local and reproducibly pinned or locked.
- Treat `ddelange/retrie` as one Python library; do not create a Node plan for it.
- Choose the smallest useful native dependency setup. Use CMake alone when pinned
  source and the platform toolchain are sufficient; add Conan 2 only when its package
  or transitive-dependency management materially helps. Evaluate Intel Hyperscan's
  Conan Center package under that rule rather than assuming it is required.

## Child Plan Inventory

Complete every checkbox by creating the named `PLAN.md` from current upstream
documentation, package metadata, and source. Do not copy interface assumptions
from one implementation to another merely because the libraries have similar
names.

### Perl: project-local `cpanm` libraries

- [x] `devdocs/regexp-optimizer/PLAN.md` —
  [Regexp::Optimizer](https://metacpan.org/pod/Regexp%3A%3AOptimizer)
- [x] `devdocs/regexp-assemble/PLAN.md` —
  [Regexp::Assemble](https://metacpan.org/pod/Regexp%3A%3AAssemble)
- [x] `devdocs/regex-presuf/PLAN.md` —
  [Regex::PreSuf](https://metacpan.org/release/JHI/Regex-PreSuf-1.17)
- [x] `devdocs/regexp-trie/PLAN.md` —
  [Regexp::Trie](https://metacpan.org/pod/Regexp%3A%3ATrie)

### npm/Node

- [x] `devdocs/regexp-tree/PLAN.md` —
  [regexp-tree](https://github.com/DmitrySoshnikov/regexp-tree#usage-as-a-cli).
  It already exposes `regexp-tree-cli`; plan only the project-local npm
  dependency, invocation, and validation rather than another wrapper.
- [x] `devdocs/oniguruma-parser/PLAN.md` —
  [oniguruma-parser](https://github.com/slevithan/oniguruma-parser)
- [x] `devdocs/grex-js/PLAN.md` —
  [grex-js](https://github.com/pemistahl/grex-js)
- [x] `devdocs/regex-trie-js/PLAN.md` —
  [regex-trie](https://github.com/alexeld/regex-trie)

### Python: project-local uv environment

- [x] `devdocs/regexfinder/PLAN.md` —
  [regexfinder](https://github.com/clockworkmicro/regexfinder)
- [x] `devdocs/triegex/PLAN.md` —
  [triegex](https://github.com/ZhukovAlexander/triegex)
- [x] `devdocs/retrie/PLAN.md` —
  [retrie](https://github.com/ddelange/retrie)
- [x] `devdocs/exrex/PLAN.md` —
  [exrex](https://github.com/asciimoo/exrex), reusing its published CLI for
  exhaustive/random matching-string generation, counting, and simplification.

### JVM/JDK

- [x] `devdocs/frak/PLAN.md` — [frak](https://github.com/noprompt/frak).
  Frak already has a command-line interface; plan a reproducible project-local
  JVM/Clojure dependency and direct invocation rather than another wrapper.
- [x] `devdocs/generex/PLAN.md` —
  [Generex](https://github.com/mifmif/Generex), with a custom wrapper for its
  library-only automaton enumeration, random generation, indexing, and counts.

### Rust

- [x] `devdocs/regextrie-rust/PLAN.md` —
  [regextrie](https://github.com/axelberardino/regextrie)
- [x] `devdocs/grex-rust/PLAN.md` —
  [grex](https://github.com/pemistahl/grex), distinct from the npm/Node
  `grex-js` port listed above.
- [x] `devdocs/rand-regex/PLAN.md` —
  [rand_regex](https://github.com/kennytm/rand_regex), selected as the mature,
  current Rust matching-string generator; newer enumeration crates were not yet
  established enough to add.

### C and C++ native builds

- [x] `devdocs/regextrie-c/PLAN.md` —
  [RegexTrie](https://github.com/ikeofilic1/RegexTrie)
- [x] `devdocs/tre/PLAN.md` —
  [TRE](https://github.com/laurikari/tre)
- [x] `devdocs/hyperscan/PLAN.md` —
  [Intel Hyperscan](https://github.com/intel/hyperscan), considering the
  [Conan Center recipe](https://conan.io/center/recipes/hyperscan) if it improves the
  current target's setup.

## Required Child Plan Structure

Every child `PLAN.md` must be decision-complete: an implementer should be able to
follow it without choosing package sources, file locations, CLI syntax, supported
operations, or test expectations.

### 1. Purpose and verified upstream facts

- Link the authoritative source and package registry entry.
- Record the version or source commit to use and why that source is appropriate.
- Summarize the library's actual defining operations, regex dialect, runtime or
  compiler requirements, and material limitations.
- Verify whether a maintained upstream CLI exists and whether it exercises the
  required capabilities. Reuse it when suitable; otherwise plan a custom CLI.
- Classify each requested capability as supported, unsupported, or irrelevant:
  core operation, optimization, matching-text generation, regex inference from
  samples, and matching/search.

### 2. Reproducible dependency setup

- Name every manifest, lockfile, build file, or local package recipe to add or
  update, including its exact dependency declaration.
- Keep installation inside the checkout; do not require global language packages.
- State the clean-checkout bootstrap and update commands.
- Pin registry releases. For unregistered dependencies, pin an immutable upstream
  commit and describe the smallest project-local recipe, source-fetch, or build
  integration required.
- Identify platform or architecture restrictions and fail early with a clear
  diagnostic when they cannot be satisfied.

Use these ecosystem defaults unless verified library constraints require a
different choice:

- Perl: one project-local `cpanm` installation tree and a checked-in dependency
  declaration shared by the Perl tools.
- Node: the root npm manifest and lockfile, with locally installed binaries run
  through npm rather than a global install.
- Python: the root uv project and lockfile; run scripts through `uv run` so the
  project interpreter and dependencies are selected automatically.
- JVM: a checked-in Clojure/JVM dependency declaration and project-local command
  that works with the JDK, without publishing or globally installing Frak.
- Rust: a Cargo package or workspace member with its dependency locked.
- C/C++: a checked-in CMake build with immutable source or package inputs. Add Conan
  2 only where it usefully resolves a package or dependency graph; source-only
  libraries with no external dependencies should use CMake directly.

### 3. CLI interface and data flow

- Name the executable and every subcommand, option, positional operand, default,
  and mutually exclusive combination.
- Define how lists, regexes, candidate text, mappings, and configuration enter via
  arguments, files, or stdin. When list input is natural, accept newline-delimited
  stdin without silently trimming meaningful characters.
- Define stdout exactly enough for piping and comparison. Keep explanatory text
  and dependency/runtime diagnostics on stderr.
- Define success, usage-error, invalid-regex, dependency/build, and processing
  failure behavior, including exit statuses.
- Map every CLI operation directly to the upstream API or native command it
  exercises. Do not add algorithmic behavior that could obscure which results
  came from the library.
- Include representative invocations and expected output shape for every planned
  operation.

The planned capability set should be focused rather than exhaustive. Include the
important knobs that materially change a defining operation, but do not mirror
every setter or internal diagnostic solely because it is public.

### 4. Implementation milestones

Order the work so each milestone leaves a verifiable state:

1. Add and lock the dependency, then prove the selected API or native CLI loads.
2. Add the minimal executable/build target and its help and error handling.
3. Implement the core operation and its stdin/file/argument paths.
4. Add the supported optimizer, matching-text generation, inference, or matching
   operations and their meaningful options.
5. Add automated tests, usage documentation, and clean-checkout validation.

Call out shared manifests or build files explicitly so plans within the same
ecosystem remain additive and do not propose incompatible project layouts.

### 5. Test and acceptance plan

Each child plan must provide exact commands and expected assertions for:

- clean project-local dependency installation or resolution;
- `--help` and at least one successful core-capability example;
- both argv and stdin input where both are planned;
- Unicode, empty input, duplicates, regex metacharacters, and ordering when those
  cases are meaningful to the library;
- invalid options, invalid patterns or samples, unreadable files, and dependency
  or platform failures;
- stdout/stderr separation and exit statuses;
- output semantics, not merely process success;
- the upstream CLI's direct invocation when no wrapper is being created.

For inferred or optimized regexes, prefer semantic assertions against positive
and negative samples when output spelling or alternation order is not guaranteed.
Use exact-string assertions only where the upstream contract makes the rendering
stable.

## Authoring Order and Completion Gate

1. Establish the shared child-plan template and ecosystem manifest ownership in
   the first plans authored.
2. Author plans by ecosystem so dependency and build decisions can be reconciled
   together: Perl, Node, Python, JVM, Rust, then C/C++.
3. Re-read all 20 plans as one implementation sequence. Resolve executable-name,
   manifest, lockfile, build-directory, and bootstrap-command conflicts.
4. Confirm every inventory checkbox has a child plan and every child plan contains
   verified sources, dependency setup, an exact CLI contract, milestones, and
   executable acceptance tests.
5. Confirm the combined plans require no global package installations and can be
   implemented incrementally from a clean checkout.

## Reconciled Implementation Sequence

The cross-plan reconciliation pass completed on August 29, 2026 and was extended with
the matching-string generators on September 18, 2026. It established this
dependency-safe order:

1. Perl: Regexp::Optimizer creates `cpanfile`, `local/`, `bin/`, `t/`, and README;
   Regexp::Assemble, Regex::PreSuf, and Regexp::Trie extend those shared files.
2. Node: regexp-tree creates `package.json`, `package-lock.json`, and `test/`; the three
   custom Node CLIs extend the same ESM project and lock.
3. Python: regexfinder creates `pyproject.toml` and `uv.lock`; triegex, retrie, and
   exrex extend that one uv environment and retain both immutable Git pins. Exrex
   reuses its installed console script.
4. JVM: Frak owns `deps.edn`, the project-local `.deps/` tree, and its two tooling
   scripts; Generex extends the exact artifact graph and adds a Clojure wrapper.
5. Rust: regextrie-rust creates the root Cargo package; rand_regex adds another binary
   target, while native grex reuses the toolchain and Cargo home as a separately
   installed upstream command.
6. Native: RegexTrie creates the root CMake project, TRE extends its default Debug build,
   and Hyperscan adds an opt-in C++ target in a separate Conan-backed build tree.

Executable names are unique. Ecosystem manifests and lockfiles have one owner and are
extended additively. Perl uses `t/`, Node/Python/JVM use type-distinct files in `test/`,
and Rust/native CMake use type-distinct files in `tests/`, so their aggregate runners do
not consume another ecosystem's tests.

The native targets are gated by `REGEX_UTILS_BUILD_REGEXTRIE_C`,
`REGEX_UTILS_BUILD_TRE`, and `REGEX_UTILS_BUILD_HYPERSCAN`. The first two default on in
`build/native`; Hyperscan defaults off and uses `build/hyperscan` with the earlier targets
off. This preserves the direct Debug CMake workflow and TRE's Autotools prerequisites
without making either depend on Conan, while the x86-only Hyperscan graph remains isolated.

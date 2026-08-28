# Plan: regexfinder Python CLI Exercise

## Summary

Add `bin/regexfinder`, a project-local Python CLI for exercising the graph and
matching APIs in `clockworkmicro/regexfinder`. Use the modernized
[`mevanlc/regexfinder`](https://github.com/mevanlc/regexfinder) fork as a normal
uv Git dependency pinned to commit
`88b50c683f77c68ff232f75e111ea6650940c4b5`. Expose three focused subcommands:
`analyze` reports the graph's rendered regex and objective metrics, `optimize`
runs the graph's phi-reduction pass and reports before/after metrics, and `search`
exposes `NODE.match()` over ordered candidate strings.

The pinned fork commit supplies the missing package metadata, `src/` layout,
relative import, dependency declarations, uv lockfile, and deterministic pytest
conversion while retaining the upstream API and algorithms. It publishes no CLI.
Do not implement this plan against the unrelated package named `regexfinder` on
PyPI or vendor loose upstream source files into this project.

## Verified Source Facts

- The authoritative upstream is
  [`clockworkmicro/regexfinder`](https://github.com/clockworkmicro/regexfinder).
  Its `main` branch resolved to commit
  `8ba5ff0f5a4b7852fb1945b08331a225e9339b60` at planning time. Upstream has no
  tags or releases; that last commit is from December 2023.
- Use fork commit
  [`88b50c683f77c68ff232f75e111ea6650940c4b5`](https://github.com/mevanlc/regexfinder/commit/88b50c683f77c68ff232f75e111ea6650940c4b5),
  whose distribution name and version are `regexfinder 0.0.0`. Pin the full SHA
  in uv's Git source table; do not depend on the moving `main` branch.
- [PyPI `regexfinder` 0.0.3](https://pypi.org/project/regexfinder/) is a different
  project by a different author. It finds regular expressions in text and does
  not contain the graph optimizer described by this plan. Never declare a bare
  registry dependency on `regexfinder`.
- Upstream contains two loose modules, notebooks, and ad hoc unittest files, but
  no project metadata, package directory, or console entry point. Its historical
  `requirements.txt` is a macOS Intel conda environment export from Python 3.7,
  not usable project metadata. The fork replaces that layout with a setuptools
  PEP 517 project under `src/regexfinder/` and imports `.utils` relatively.
- `regexfinder.core` eagerly imports NumPy, pandas, more-itertools, and the Python
  `graphviz` package. The fork declares minimums `numpy>=1.21.5`, `pandas>=1.3.5`,
  `more-itertools>=8.12`, and `graphviz>=0.19.1` as runtime dependencies.
- Although the old environment says Python 3.7, source annotations such as
  `dict[str, NODE]` require at least Python 3.9. The fork declares and tests
  `requires-python = ">=3.10"`; this project will use the same floor.
- The defining `GRAPH` flow is `GRAPH(regex=..., alpha=...)`, `partition()`, then
  optional `reducePhi()`. The public `outRegex`, `cardinality`,
  `log2Cardinality`, `entropy`, `K`, and `phi` properties expose the graph's
  rendering and size/complexity objective. `reducePhi()` mutates the graph and
  returns `None`.
- The objective is `phi = log2Cardinality + alpha * K`. Optimization may broaden
  the accepted language to reduce expression length; it is not an equivalence-
  preserving canonicalizer. For example, the documented large expression can
  gain cardinality while lowering phi.
- Parsing is a hand-written subset layered over Python `re.compile`. It handles
  ordinary grouping, alternation, ASCII literals, ASCII classes, `\d`, `\D`,
  `\w`, `\W`, `?`, and finite brace quantifiers. It does not faithfully model
  the whole Python regex dialect: escapes and parentheses are scanned textually,
  vectors are fixed at 128 ASCII code points, and unbounded `*`/`+` quantifiers
  cannot be assigned finite cardinality.
- `GRAPH.log2Cardinality` incorrectly returns raw cardinality for a leaf graph.
  Consequently leaf `phi` can disagree with `entropy + alpha * K`; for `[ab]`,
  the direct APIs report cardinality 2, log2-cardinality 2, entropy 1, K 4, and
  phi 6 at alpha 1. Preserve and document those upstream values.
- `reducePhi()` prints debug lines such as `Nodes 4 VSG 4` to stdout. The wrapper
  must capture them so primary stdout remains machine-readable. An explicit
  `--verbose` option may replay them on stderr.
- `NODE.match(text, boolean=False)` delegates matching to Python `re.finditer`.
  With `boolean=True` it consumes the iterator and returns a boolean; otherwise
  it returns the iterator of Python match objects. This is search, not graph
  optimization, and it can accept some patterns that graph analysis cannot.
- Matching-text generation is advertised, but `GRAPH.random` currently falls
  off its leaf branch without returning `NODE.random`; simple and parallel
  graphs therefore return `None`, while sequential graphs can fail when joining
  those values. Do not reproduce the intended recursion in wrapper code.
- `createVisual()` creates a `graphviz.Digraph`, calls `dot.render(view=True)`
  with no output-path control, writes files, and launches a viewer. It is
  unsuitable for this noninteractive Unix CLI. Not exposing it also means the
  Graphviz `dot` executable is not a runtime prerequisite for the wrapper.
- The word-collection path is unfinished and is not the sample-to-regex operation
  documented by a stable upstream interface. Do not expose it as inference.
- No upstream CLI exists. A custom wrapper is required, but it must stay at the
  API boundary above rather than repairing parser or optimizer behavior.

A local feasibility probe installed the exact fork commit through uv on CPython
3.14.0. It resolved `numpy 2.5.2`, `pandas 3.0.5`, `more-itertools 11.1.0`, and
`graphviz 0.21`; the installed `direct_url.json` recorded the requested full SHA,
and the package exported callable `GRAPH` and `NODE` objects outside the source
checkout. The fork's locked suite passed all 76 tests on CPython 3.10.20 and
3.14.0. Direct probes confirmed that optimization still changes `a(b|c)d` to
`a[bc]d` and lowers phi from 8 to 7, while the leaf-phi defect, unsolicited debug
output, and broken graph random generation remain. Project tests below are the
acceptance authority for the wrapper.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Core operation | Supported: partition a regex graph and report direct rendering, cardinality, entropy, complexity, and phi APIs. |
| Regex optimization | Supported, with upstream limitations: call `reducePhi()` once and report its mutations without claiming language equivalence. |
| Matching/search | Supported separately through `NODE.match()` and Python `re` match objects. |
| Matching-text generation | Advertised but unusable at the pinned commit because `GRAPH.random` is defective; do not emulate it. Reconsider only after an upstream/fork fix with tests. |
| Regex inference from samples | Unsupported; the unfinished word-collection code is not a stable inference API. |
| Graph visualization | Available only through a forced write-and-view API; intentionally omitted from this noninteractive CLI. |

## Verified Modernized Fork Pin

Commit `88b50c683f77c68ff232f75e111ea6650940c4b5` satisfies the packaging gate:

1. Its PEP 517 `pyproject.toml` uses setuptools, distribution name `regexfinder`,
   version `0.0.0`, MIT licensing, and `requires-python = ">=3.10"`.
2. It declares all four eagerly imported runtime dependencies and locks its own
   development environment with uv.
3. Its `src/regexfinder/` package uses a relative `.utils` import and re-exports
   the public API from `regexfinder.__init__`.
4. Its pytest conversion replaces the process-global node-ID assertion with an
   assertion on graph-node regexes. All 76 tests pass on Python 3.10 and 3.14.
5. A fresh uv Git installation builds the wheel, imports outside either checkout,
   and exposes the expected APIs with verifiable direct-URL provenance.

Use that exact commit. Do not use `main`, a moving tag, a local path dependency,
or the unrelated PyPI artifact. Future fork revisions must be reviewed, tested on
the same Python endpoints, and pinned by a new full SHA; update verified behavior
in this plan if they alter any cataloged algorithmic limitation.

## Files and Dependency Setup

### Shared Python infrastructure

Create the root uv application project used by this and later Python plans. The
initial manifest shape is:

```toml
[project]
name = "regex-utils-cli"
version = "0.0.0"
requires-python = ">=3.10"
dependencies = [
  "regexfinder",
]

[tool.uv]
package = false

[tool.uv.sources]
regexfinder = { git = "https://github.com/mevanlc/regexfinder.git", rev = "88b50c683f77c68ff232f75e111ea6650940c4b5" }
```

Use `package = false` because this repository's deliverables are executable
scripts in `bin/`, not an installable aggregate Python distribution. Later Python
plans must extend this one manifest and lockfile rather than create nested uv
projects or replace this Python floor.

Create and lock the project with:

```sh
uv init --bare --python 3.10
uv add 'regexfinder @ git+https://github.com/mevanlc/regexfinder.git@88b50c683f77c68ff232f75e111ea6650940c4b5'
uv lock
```

Commit `pyproject.toml` and `uv.lock`. The direct Git requirement prevents the
PyPI name collision; `uv.lock` must record the same exact fork commit plus exact
registry artifacts for all transitive dependencies. Reuse `/.venv/` and Python
cache entries already in `.gitignore`.

The clean-checkout bootstrap is:

```sh
uv sync --frozen
```

Run the command through uv so it always receives the selected interpreter and
locked environment:

```sh
uv run --frozen -- ./bin/regexfinder --help
```

To update later, choose a reviewed fork commit that passes the same checks, change
the exact `rev` in `pyproject.toml`, and run:

```sh
uv lock --upgrade-package regexfinder
uv sync --frozen
```

Review the fork diff and lockfile diff together. Do not run an unconstrained
upgrade, publish this aggregate project, install globally, add a `.deps` source
clone, or make the wrapper depend on its caller's working directory.

The wrapper itself has no OS or architecture restriction. NumPy and pandas may
constrain the Python/platform combinations for which uv can resolve wheels; a
resolution failure must remain an early `uv sync` failure. System Graphviz is not
required because visualization is out of scope.

### Implementation and documentation files

- `bin/regexfinder`: extensionless executable Python script with a Python 3
  shebang; invoke it through `uv run --frozen`.
- `test/regexfinder_test.py`: end-to-end tests using `unittest`, subprocesses, and
  temporary files from the standard library.
- `pyproject.toml` and `uv.lock`: the shared root Python environment above.
- `README.md`: add bootstrap, subcommands, input rules, JSON schemas, examples,
  fork provenance, Python floor, and upstream limitations.

Use only the Python standard library for argument parsing, UTF-8 input, JSON,
dependency provenance checks, stdout capture, and diagnostics. Do not add a CLI
framework.

Before processing or `--version`, use `importlib.metadata` to inspect the installed
`regexfinder` distribution's `direct_url.json`. Require the expected fork URL and
the exact pinned commit ID, then import `regexfinder` and verify callable `GRAPH`
and `NODE` exports. This prevents a globally installed or same-named PyPI package
from satisfying the check accidentally. On any provenance, import, or API failure,
write this to stderr and exit 1:

```text
regexfinder: pinned mevanlc/regexfinder dependency is unavailable; run uv sync --frozen
```

Parse and display help before loading the dependency so help works before
bootstrap. `--version` must perform the dependency check and print:

```text
regexfinder <distribution-version> (mevanlc/regexfinder <full-commit-id>)
```

Import the package normally. The modernization commit converted the baseline's
invalid escape-sequence literals to raw strings, so the wrapper must not suppress
`SyntaxWarning` or any other warning class.

## CLI Contract

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

General options:
  -h, --help                       Print help and exit
  -V, --version                    Print dependency version and pinned commit
```

Require exactly one subcommand and one `PATTERN`. The pattern is always a complete
positional operand; use `--` before a pattern beginning with `-`. Preserve its
characters exactly and do not parse `/pattern/flags` notation, unescape shell
text, add anchors, or translate dialects. An empty argv pattern reaches the API
and reports the upstream unsupported-input failure rather than being rewritten.

Options are subcommand-specific. Reject `--input`/`--boolean` outside `search`,
`--verbose` outside `optimize`, and `--alpha` outside the graph commands. Reject
unknown options, duplicate non-repeatable options, nondecimal alpha values,
negative alpha, infinity, and NaN. Normalize a valid alpha to a Python `float`
before passing it to `GRAPH`.

### Candidate input for `search`

- Accept exactly one candidate source: one or more positional `TEXT` operands,
  one `--input FILE`, or implicit stdin when no text operands are present. Reject
  positionals mixed with `--input` and repeated `--input`.
- If implicit stdin is attached to a terminal, exit with a usage error rather than
  waiting. `--input -` explicitly selects stdin and may wait on a terminal.
- Positional operands are complete strings. Preserve empty values, whitespace,
  embedded newlines, metacharacters, duplicates, and input order. NUL cannot occur
  in argv but can occur in file/stdin records.
- Read file/stdin bytes completely, decode strict UTF-8, and split on LF. Treat a
  CR immediately before LF as part of the delimiter while preserving every other
  CR and character. One final LF or CRLF terminates the last record without adding
  a phantom record: `a\n` is `['a']`, `a\n\n` is `['a', '']`, and `\n` is `['']`.
- A zero-byte stream supplies no candidates and exits 1 with
  `regexfinder: candidate input contains no records`. Do not trim, sort,
  deduplicate, or interpret escapes in wrapper code.

### Common graph snapshot

For `analyze` and `optimize`, construct `GRAPH(regex=pattern, alpha=alpha)` and
call `partition()` once before reading properties. Read and convert NumPy scalar
values to ordinary JSON integers/floats. A snapshot has this stable key set:

```json
{
  "out_regex": "a(b|c)d",
  "cardinality": 2,
  "log2_cardinality": 1.0,
  "entropy": 1.0,
  "complexity": 7,
  "phi": 8.0
}
```

Every value must come from the correspondingly named upstream property; do not
recompute log2-cardinality, entropy, complexity, or phi in the wrapper even when
the values expose a defect. Serialize with `ensure_ascii=False`, compact separators,
`allow_nan=False`, and one final LF.

### `analyze`

Emit one compact JSON object with the exact input and one direct snapshot:

```json
{"input_regex":"[ab]","alpha":1.0,"graph":{"out_regex":"[ab]","cardinality":2,"log2_cardinality":2.0,"entropy":1.0,"complexity":4,"phi":6.0}}
```

The leaf values deliberately show the verified `log2Cardinality`/`phi` defect.
`analyze` does not call `reduce()`, `reducePhi()`, `NODE.match()`, or Graphviz.

### `optimize`

1. Construct and partition one graph.
2. Take a `before` snapshot.
3. Call `graph.reducePhi()` exactly once.
4. Take an `after` snapshot and compare only `out_regex` to set `changed`.
5. Emit one compact JSON object containing the input, alpha, both snapshots, and
   the boolean.

For the representative expression, the output shape is:

```json
{"input_regex":"a(b|c)d","alpha":1.0,"before":{"out_regex":"a(b|c)d","cardinality":2,"log2_cardinality":1.0,"entropy":1.0,"complexity":7,"phi":8.0},"after":{"out_regex":"a[bc]d","cardinality":2,"log2_cardinality":1.0,"entropy":1.0,"complexity":6,"phi":7.0},"changed":true}
```

Wrap graph construction, partitioning, reduction, and snapshots in
`contextlib.redirect_stdout` so upstream prints cannot corrupt JSON. By default
discard the captured diagnostics. With `--verbose`, replay each captured line to
stderr prefixed with `regexfinder: upstream: ` after processing succeeds; never
copy diagnostics to stdout. Do not call `GRAPH.reduce()` as an extra optimization
pass or choose merges in wrapper code.

### `search`

Construct one `NODE(regex=pattern)` and call its `match()` once for each candidate.
With `--boolean`, pass `boolean=True` and emit:

```json
{"text":"xxcat!","matched":true}
```

Without `--boolean`, leave the argument at its default, consume the returned
iterator once, and emit one ordered JSON object per candidate:

```json
{"text":"xxcat!","matched":true,"matches":[{"text":"cat","start":2,"end":5,"groups":[],"groupdict":{}}]}
```

For every Python match object, record `group(0)`, `start()`, `end()`, `groups()` as
a JSON array preserving `None`, and `groupdict()` as an object. Do not call Python
`re` directly, change overlap behavior, force full matches, add flags, or use
graph-rendered output as the search pattern.

### Errors, diagnostics, and process behavior

- Exit 0 for successful output, help, and version; 2 for command-line usage
  errors; and 1 for missing/wrong dependencies, unreadable input, invalid UTF-8,
  invalid or unsupported regexes, upstream failures, non-finite metrics, JSON
  serialization failures, and other processing errors.
- Prefix diagnostics with `regexfinder:`, write them only to stderr, and do not
  expose tracebacks, NumPy representations, partially serialized JSON, or captured
  upstream stdout. Buffer all primary output before the first stdout write.
- Preserve concise upstream exception text when it is safe and nonempty, but
  classify it as `analyze failed`, `optimize failed`, or `search failed`. The
  generic `GRAPH` invalid-regex exception need not be reverse-engineered into a
  more specific parser diagnosis.
- Treat a closed stdout pipe as quiet success. Other stdout failures exit 1 if no
  primary bytes were written; never append a diagnostic to stdout.
- The wrapper is not a CPU, memory, or regex-backtracking sandbox. Document this
  for untrusted or very large input.

## Representative Invocations

Inspect a graph and preserve its direct metrics:

```console
$ uv run --frozen -- ./bin/regexfinder analyze '[ab]'
{"input_regex":"[ab]","alpha":1.0,"graph":{"out_regex":"[ab]","cardinality":2,"log2_cardinality":2.0,"entropy":1.0,"complexity":4,"phi":6.0}}
```

Run phi reduction:

```console
$ uv run --frozen -- ./bin/regexfinder optimize 'a(b|c)d'
{"input_regex":"a(b|c)d","alpha":1.0,"before":{"out_regex":"a(b|c)d","cardinality":2,"log2_cardinality":1.0,"entropy":1.0,"complexity":7,"phi":8.0},"after":{"out_regex":"a[bc]d","cardinality":2,"log2_cardinality":1.0,"entropy":1.0,"complexity":6,"phi":7.0},"changed":true}
```

Search newline-delimited candidates through the upstream node API:

```console
$ printf 'car\ndog\n' | uv run --frozen -- ./bin/regexfinder search --boolean 'ca[rt]'
{"text":"car","matched":true}
{"text":"dog","matched":false}
```

## Implementation Milestones

1. **Add and pin the fork.** Add the root uv application manifest, lock fork commit
   `88b50c683f77c68ff232f75e111ea6650940c4b5` and its transitives, and prove
   installed provenance and imports from outside both repositories on Python 3.10
   and the current Python release.
2. **Build common CLI plumbing.** Add subcommand dispatch, strict option parsing,
   deferred dependency checks, candidate-source handling, strict UTF-8 decoding,
   compact JSON, buffered output, help/version, and status-separated errors.
3. **Implement graph analysis.** Map alpha, graph construction, partitioning, and
   every snapshot field directly to the verified public API; normalize only scalar
   representation and capture upstream stdout.
4. **Implement optimization and search.** Add the single `reducePhi()` call,
   verbose diagnostic replay, detailed and boolean `NODE.match()` modes, and exact
   input-order preservation. Do not add generation, inference, or visualization.
5. **Test and document.** Cover the fork pin, both Python endpoints, every input
   source, subcommand, output schema, known defect, and failure class; update the
   root README and validate a frozen clean-checkout bootstrap.

## Test Plan

Use standard-library `unittest`, `subprocess`, `json`, and temporary-path helpers.
Spawn the absolute `bin/regexfinder` path with the uv-selected interpreter so the
tests exercise the checkout script without shell quoting or a global package.

### Dependency and static checks

```sh
uv lock --check
uv sync --python 3.10 --frozen
uv run --python 3.10 --frozen -- python -c 'import regexfinder; print(regexfinder.__file__)'
uv run --python 3.10 --frozen -- python -m unittest test/regexfinder_test.py
uv sync --python 3.14 --frozen
uv run --python 3.14 --frozen -- python -m unittest test/regexfinder_test.py
uv run --frozen -- ./bin/regexfinder --version
uv tree
```

Assert the lock is unchanged, the installed distribution's `direct_url.json`
names `mevanlc/regexfinder` and the exact pinned SHA, transitive packages
come only from the lock, and imports work outside the repository. If 3.14 is no
longer the current Python when implemented, replace that probe with the then-
current stable release while retaining the 3.10 floor.

### Successful behavior

- Top-level and subcommand help write only stdout and exit 0 before `uv sync`.
  Version verifies dependency provenance, prints the exact locked fork commit,
  and is silent on stderr.
- `analyze '[ab]'` produces the exact shown leaf metrics, including the upstream
  defect. Analyze sequential, parallel, finite quantified, and documented complex
  ASCII expressions; assert parsed values and types, not just process success.
- `--alpha 0`, `--alpha 0.5`, and the default reach `GRAPH` and change direct phi
  values as expected. Confirm JSON never contains NumPy scalar syntax, NaN, or
  Infinity.
- `optimize 'a(b|c)d'` produces the shown before/after semantics and no default
  stderr. `--verbose` keeps identical stdout while moving upstream `Nodes ... VSG
  ...` lines to prefixed stderr. Test a no-change expression and a broadening
  expression without asserting language equivalence.
- Search through positional, file, explicit stdin, and implicit redirected stdin.
  Verify boolean output, every detailed match span/text/group field, multiple
  matches, no matches, empty candidates, duplicates, and candidate order.
- Exercise whitespace, regex metacharacters, NUL from a file, and Unicode through
  a non-simple search pattern such as `café|x`. Separately characterize that a
  simple non-ASCII node and non-ASCII graph analysis fail because of the upstream
  128-element vector.
- Run every README example. Parse all successful output as UTF-8 JSON/JSON Lines,
  require exactly one LF per record, and verify no primary result is written to
  stderr.

### Failure and safety behavior

- Missing/unknown subcommands, unknown or misplaced options, missing/extra pattern
  operands, mixed candidate sources, duplicate non-repeatable options, and invalid
  alpha values exit 2 with empty stdout.
- Invalid Python regex syntax, empty graph patterns, unbounded quantifiers, syntax
  outside the hand-written graph subset, unreadable files, invalid UTF-8, and
  zero-record candidate input exit 1 with empty stdout and no traceback.
- In a clean copied checkout before `uv sync`, help succeeds while version and
  processing give the exact bootstrap diagnostic. Install the unrelated PyPI
  package in an isolated probe and confirm its metadata cannot satisfy provenance.
- Alter the direct URL or commit metadata in an isolated environment and confirm
  the wrapper fails closed rather than importing an unpinned or global package.
- Run from outside the project directory and confirm dependency discovery and
  file input remain correct. Input resembling Python code remains inert data.
- Force an upstream debug print followed by an exception and confirm neither the
  debug line nor partial JSON reaches stdout. Simulate JSON and stdout failures;
  confirm EPIPE is quiet success and other failures use status 1.
- Bound representative pathological patterns with test timeouts and document that
  exhaustion or catastrophic backtracking is an upstream/runtime risk, not a
  security boundary supplied by this exercise CLI.

The fork's 76-test suite is a dependency-update gate, but its internal assertions
and debug prints are not copied into this project's acceptance suite. Project
tests should make independent API and end-to-end assertions against the exact
locked commit.

## Acceptance Criteria

- The root uv source pins fork commit
  `88b50c683f77c68ff232f75e111ea6650940c4b5` exactly.
- A clean checkout creates only a project-local uv environment, installs the exact
  Git dependency and locked transitives, and never resolves the unrelated PyPI
  project or a global module.
- `analyze`, `optimize`, and `search` map to `GRAPH.partition()`, `GRAPH.reducePhi()`,
  and `NODE.match()` respectively, with no wrapper-side regex algorithms.
- JSON/JSON Lines schemas, candidate record preservation, upstream stdout capture,
  verbose stderr, errors, and exit statuses match this contract on Python 3.10 and
  the current stable Python release.
- Tests characterize the leaf metric bug, parser/ASCII limits, optimization
  broadening, graph generation defect, and forced-GUI visualization API without
  hiding or repairing them in this repository.
- Matching-text generation, sample inference, visualization, arbitrary graph
  mutation, pattern translation, and resource isolation remain explicitly out of
  scope until a future reviewed dependency revision supports them cleanly.

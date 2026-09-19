# Plan: exrex Python CLI Exercise

## Summary

Add [`asciimoo/exrex`](https://github.com/asciimoo/exrex) to the shared uv
environment and invoke its existing `exrex` console script directly. Do not add
a redundant `bin/exrex` adapter. The upstream command already exposes exhaustive
and random matching-string generation, cardinality, regex simplification,
bounded repeat expansion, custom delimiters, and output files.

## Verified Upstream Facts

- The authoritative source is
  [`asciimoo/exrex`](https://github.com/asciimoo/exrex), licensed AGPL-3.0-or-later.
- PyPI release `0.12.0`, published November 13, 2024, is the latest release and
  corresponds to commit `b91c075e6afa48bbaf1dd4df29e3eefb5c6b9dc4`.
  Pin `exrex==0.12.0`; `uv.lock` records the wheel and source hashes.
- The universal wheel SHA-256 is
  `1228f2e3afb008cacf6adc3ec20b098f1303886f4382b57cdf3b7259fb7c0ad3`;
  the source archive SHA-256 is
  `3f582add0700d4141e279625252e7a0655f9ad81feab3b8ab9077966668a2c99`.
  The package is one pure-Python module with no runtime dependencies and exports
  `exrex=exrex:__main__`.
- The library uses Python's internal `re._parser` representation. Its accepted
  dialect follows the running Python version, but generation implements only
  the token kinds handled by exrex.
- `generate()` is lazy. `--limit` bounds the expansion of unbounded repeat
  operators; it does not cap total output. `--max-number` caps emitted values.
- `--random` calls `getone()`, but the native CLI offers no seed option and only
  emits one random value.
- `--count` uses the same finite expansion model and `--limit`; it is not an
  unbounded-language cardinality proof. `--simplify` round-trips through the
  internal parser and may change spelling.
- Character categories and negated classes are drawn from upstream's explicit
  tables, many of which cover code points 0 through 255 rather than all Unicode.
- Default output separates values with LF and adds a final LF. A custom
  delimiter is written only between values. Generated values containing the
  delimiter are therefore not unambiguous records.
- Invalid regexes normally exit 1 with `[!] Error:`. Argparse misuse exits 2.
  Release 0.12.0's native enumeration of the empty regex raises an uncaught
  `TypeError`; retain and characterize that upstream failure rather than wrap it.

## Capability Coverage

| Capability | Plan |
| --- | --- |
| Matching-text generation | Supported exhaustively and randomly by the upstream CLI. |
| Cardinality | Supported under exrex's repeat-limit model. |
| Regex simplification | Supported by the upstream parser/renderer; not an equivalence proof outside its handled subset. |
| Regex inference | Unsupported. |
| Matching/search | Unsupported by the CLI; tests may use Python `re` only to validate generated samples. |

## Dependency and Files

- Add `exrex==0.12.0` to root `pyproject.toml` and regenerate `uv.lock`.
- Add `test/exrex_cli_test.py`; invoke the environment's installed console
  script, not a copied module or project wrapper.
- Extend README, `devdocs/PLAN-PLANS.md`, and the seven Just recipes.
- Reuse `.venv/` and the Python bytecode cleanup helper shared by the existing
  Python exercises.

Prepare and verify with:

```sh
uv sync --frozen
uv run --frozen -- python -c \
  'import importlib.metadata; assert importlib.metadata.version("exrex") == "0.12.0"'
```

## Direct CLI Contract

```text
usage: exrex [-h] [-o FILE] [-l N] [-c] [-m N] [-r] [-s]
             [-d DELIMITER] [-v] REGEX

  -o, --output FILE
  -l, --limit N
  -c, --count
  -m, --max-number N
  -r, --random
  -s, --simplify
  -d, --delimiter DELIMITER
  -v, --verbose
```

The project-local invocation is:

```sh
uv run --frozen -- exrex '[ab]{1,2}'
```

No project flag translation, status normalization, extra version option, stdin
pattern source, or output framing is added. `-v` prints the parsed token data
before the selected operation; it is not a version flag. Native option
precedence remains count, random, simplify, then exhaustive generation.

## Implementation Milestones

1. Add and lock the exact PyPI release.
2. Prove the installed console entry point and module load on the project Python
   floor and current interpreter.
3. Characterize enumeration, repeat limits, random output, count,
   simplification, backreferences, delimiter, and output-file behavior.
4. Characterize syntax/usage failures and the empty-pattern defect.
5. Add README and Just lifecycle coverage without a redundant wrapper.

## Acceptance

- A frozen uv sync installs exactly exrex 0.12.0.
- Native help is reachable through `uv run --frozen -- exrex`.
- Exhaustive output order, `--max-number`, unbounded-repeat `--limit`, custom
  delimiters, count, simplification, group references, random validity, and
  output-file routing are asserted.
- Invalid regex, unknown option, and empty-regex failure behavior retain native
  statuses and diagnostics.
- The installed script works outside the checkout when launched by absolute
  path from the prepared environment.
- All three cleanup recipes can be followed by `exrex-deps`, `exrex-build`, and
  `exrex-test` successfully.

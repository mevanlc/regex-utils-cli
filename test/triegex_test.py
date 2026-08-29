from __future__ import annotations

import collections
import functools
import importlib
import importlib.util
import json
import operator
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from collections.abc import MutableSet
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "bin" / "triegex"
COMMIT = "85a25240b8821c2da257e6f6b784023e56a5b680"


def run(*arguments: str, input: bytes | None = None, cwd: Path | None = None,
        executable: Path = CLI, env: dict[str, str] | None = None,
        timeout: float = 10) -> subprocess.CompletedProcess[bytes]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        [sys.executable, os.fspath(executable), *arguments],
        input=input,
        cwd=cwd or ROOT,
        env=merged_env,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def json_lines(output: bytes) -> list[object]:
    assert output.endswith(b"\n")
    return [json.loads(line) for line in output.decode().splitlines()]


def shimmed_triegex():
    existed = hasattr(collections, "MutableSet")
    prior = getattr(collections, "MutableSet", None)
    try:
        if not existed:
            collections.MutableSet = MutableSet
        return importlib.import_module("triegex")
    finally:
        if existed:
            collections.MutableSet = prior
        elif hasattr(collections, "MutableSet"):
            del collections.MutableSet


class TriegexCliTest(unittest.TestCase):
    def assert_success(self, result: subprocess.CompletedProcess[bytes]) -> None:
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertEqual(result.stderr, b"")

    def test_help_and_version_are_stable(self) -> None:
        top = run("--help")
        self.assert_success(top)
        self.assertIn(b"triegex build", top.stdout)
        self.assertIn(b"triegex contains", top.stdout)
        self.assertIn(b"triegex match", top.stdout)
        for command in ("build", "contains", "match"):
            result = run(command, "--help")
            self.assert_success(result)
            self.assertTrue(result.stdout.startswith(f"Usage: triegex {command}".encode()))
            if command == "build":
                self.assertNotIn(b"--candidate", result.stdout)
        version = run("--version")
        self.assert_success(version)
        self.assertEqual(
            version.stdout,
            f"triegex 0.0.4 (ZhukovAlexander/triegex {COMMIT})\n".encode(),
        )

    def test_build_preserves_exact_sorted_upstream_source(self) -> None:
        expected = rb"(?:ba(?:r\b|z\b)|foo\b|~^(?#match nothing))" + b"\n"
        for words in (("foo", "bar", "baz"), ("baz", "foo", "bar")):
            result = run("build", *words)
            self.assert_success(result)
            self.assertEqual(result.stdout, expected)
        self.assertEqual(run("build", "foo", "foo").stdout, rb"(?:foo\b|~^(?#match nothing))" + b"\n")

    def test_zero_words_and_raw_metacharacters_are_visible(self) -> None:
        empty = run("build", "--input", "-", input=b"")
        self.assert_success(empty)
        self.assertEqual(empty.stdout, rb"~^(?#match nothing)" + b"\n")
        raw = run("build", "a.b", "a*b")
        self.assert_success(raw)
        self.assertIn(rb".b\b", raw.stdout)
        self.assertIn(rb"*b\b", raw.stdout)
        invalid = run("build", "(")
        self.assert_success(invalid)
        self.assertIn(b"(", invalid.stdout)

    def test_word_and_candidate_files_preserve_records_and_controls(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            words = Path(directory) / "words"
            candidates = Path(directory) / "candidates"
            words.write_bytes("foo\r\ncafé\nspace word\ncr\r".encode() + b"\x00x\n")
            candidates.write_bytes("foo\r\ncafé\nspace word\ncr\r".encode() + b"\x00x\nnone\n")
            result = run(
                "contains", "--input", os.fspath(words),
                "--candidate-input", os.fspath(candidates),
            )
            self.assert_success(result)
            values = json_lines(result.stdout)
            self.assertEqual([value["candidate"] for value in values], [
                "foo", "café", "space word", "cr\r\x00x", "none",
            ])
            self.assertEqual([value["contains"] for value in values], [True, True, True, True, False])

        direct = run("build", "foo")
        explicit = run("build", "--input", "-", input=b"foo\n")
        implicit = run("build", input=b"foo\n")
        self.assertEqual(explicit.stdout, direct.stdout)
        self.assertEqual(implicit.stdout, direct.stdout)

    def test_contains_is_exact_and_independent_of_generated_regex(self) -> None:
        candidates = ["foo", "food", "", "foo!", "(", "("]
        result = run(
            "contains", "foo", "foo!", "(",
            *functools.reduce(operator.iadd, (["--candidate", candidate] for candidate in candidates), []),
        )
        self.assert_success(result)
        self.assertEqual(json_lines(result.stdout), [
            {"candidate": candidate, "contains": candidate in {"foo", "foo!", "("}}
            for candidate in candidates
        ])

    def test_match_preserves_unanchored_boundaries_and_detailed_spans(self) -> None:
        result = run("match", "foo", "bar", "--candidate", "food foo bar!", "--candidate", "none")
        self.assert_success(result)
        values = json_lines(result.stdout)
        self.assertEqual(values[0], {
            "candidate": "food foo bar!",
            "matched": True,
            "matches": [
                {"text": "foo", "start": 5, "end": 8, "groups": [], "groupdict": {}},
                {"text": "bar", "start": 9, "end": 12, "groups": [], "groupdict": {}},
            ],
        })
        self.assertEqual(values[1], {"candidate": "none", "matched": False, "matches": []})

        boundaries = run(
            "match", "--boolean", "foo", "café", "茶",
            "--candidate", "xxfoo!", "--candidate", "food", "--candidate", "café ",
            "--candidate", "茶 ",
        )
        self.assert_success(boundaries)
        self.assertEqual([value["matched"] for value in json_lines(boundaries.stdout)],
                         [True, False, True, True])
        symbols = run(
            "match", "--boolean", "foo!", "💩",
            "--candidate", "foo!", "--candidate", "💩",
        )
        self.assert_success(symbols)
        self.assertEqual([value["matched"] for value in json_lines(symbols.stdout)], [False, False])

    def test_match_exposes_unescaped_operators_and_captures(self) -> None:
        wildcard = run("match", "a.b", "--candidate", "axb")
        self.assert_success(wildcard)
        matches = json_lines(wildcard.stdout)[0]["matches"]
        self.assertEqual([match["text"] for match in matches], ["axb"])

        star = run("match", "a*b", "--candidate", "b")
        self.assert_success(star)
        self.assertEqual(json_lines(star.stdout)[0]["matches"][0]["text"], "b")

        capture = run("match", "(foo)", "--candidate", "xxfoo!")
        self.assert_success(capture)
        self.assertEqual(json_lines(capture.stdout)[0]["matches"][0]["groups"], ["foo"])

        invalid = run("match", "(", "--candidate", "anything")
        self.assertEqual(invalid.returncode, 1)
        self.assertEqual(invalid.stdout, b"")
        self.assertIn(b"match failed:", invalid.stderr)
        self.assertNotIn(b"Traceback", invalid.stderr)

    def test_candidate_stdin_and_boolean_schema(self) -> None:
        result = run(
            "match", "--boolean", "foo", "bar", "--candidate-input", "-",
            input=b"food foo bar!\nnone\n",
        )
        self.assert_success(result)
        self.assertEqual(json_lines(result.stdout), [
            {"candidate": "food foo bar!", "matched": True},
            {"candidate": "none", "matched": False},
        ])

    def test_empty_word_and_input_failures_are_runtime_errors(self) -> None:
        empty = run("build", "")
        self.assertEqual(empty.returncode, 1)
        self.assertEqual(empty.stdout, b"")
        self.assertIn(b"build failed:", empty.stderr)
        with tempfile.TemporaryDirectory() as directory:
            invalid = Path(directory) / "invalid"
            invalid.write_bytes(b"\xff")
            for arguments in (
                ("build", "--input", os.fspath(invalid)),
                ("contains", "foo", "--candidate-input", os.fspath(invalid)),
                ("build", "--input", os.fspath(Path(directory) / "missing")),
            ):
                result = run(*arguments)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, b"")
                self.assertNotIn(b"Traceback", result.stderr)
        zero = run("contains", "foo", "--candidate-input", "-", input=b"")
        self.assertEqual(zero.returncode, 1)
        self.assertEqual(zero.stderr, b"triegex: candidate input contains no records\n")

    def test_invalid_command_lines_are_usage_errors(self) -> None:
        cases = [
            (),
            ("unknown",),
            ("build", "--candidate", "x", "foo"),
            ("contains", "foo"),
            ("contains", "foo", "--candidate", "x", "--candidate-input", "file"),
            ("contains", "--boolean", "foo", "--candidate", "foo"),
            ("build", "--input", "a", "--input", "b"),
            ("build", "--input", "file", "foo"),
            ("match", "foo", "--candidate-input", "-", "--input", "-"),
            ("--version", "extra"),
            ("match", "--help", "foo"),
        ]
        for arguments in cases:
            with self.subTest(arguments=arguments):
                result = run(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, b"")
                self.assertTrue(result.stderr.startswith(b"triegex:"))
                self.assertNotIn(b"Traceback", result.stderr)

    def test_dependency_loader_restores_collections_alias(self) -> None:
        before = getattr(collections, "MutableSet", None)
        existed = hasattr(collections, "MutableSet")
        loader = SourceFileLoader("triegex_cli_test_module", os.fspath(CLI))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        spec.loader.exec_module(module)
        constructor = module.dependency()
        self.assertTrue(callable(constructor))
        self.assertEqual(hasattr(collections, "MutableSet"), existed)
        if existed:
            self.assertIs(collections.MutableSet, before)

        direct = subprocess.run(
            [sys.executable, "-c", "import triegex"],
            capture_output=True, check=False,
        )
        self.assertNotEqual(direct.returncode, 0)
        self.assertIn(b"MutableSet", direct.stderr)

    def test_iterator_and_discard_defects_remain_unexposed(self) -> None:
        Triegex = shimmed_triegex().Triegex
        one = Triegex("a")
        self.assertEqual(list(one), ["a", "a"])
        self.assertEqual(len(one), 2)
        prefix = Triegex("foo", "foobar")
        prefix.discard("foo")
        self.assertIn("foo", prefix)

    def test_help_is_bootstrap_free_and_dependency_check_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bin").mkdir()
            (root / "lib").mkdir()
            shutil.copy2(CLI, root / "bin" / "triegex")
            shutil.copy2(ROOT / "lib" / "python_cli.py", root / "lib" / "python_cli.py")
            help_result = subprocess.run(
                [sys.executable, "-S", root / "bin" / "triegex", "--help"],
                capture_output=True, check=False,
            )
            self.assertEqual(help_result.returncode, 0)
            version = subprocess.run(
                [sys.executable, "-S", root / "bin" / "triegex", "--version"],
                capture_output=True, check=False,
            )
            self.assertEqual(version.returncode, 1)
            self.assertEqual(version.stdout, b"")
            self.assertEqual(
                version.stderr,
                b"triegex: pinned triegex 0.0.4 is unavailable; run uv sync --frozen\n",
            )

    def test_controlled_dependency_proves_direct_api_calls(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bin").mkdir()
            (root / "lib").mkdir()
            site = root / "site"
            metadata = site / "triegex-0.0.4.dist-info"
            site.mkdir()
            metadata.mkdir()
            shutil.copy2(CLI, root / "bin" / "triegex")
            shutil.copy2(ROOT / "lib" / "python_cli.py", root / "lib" / "python_cli.py")
            (metadata / "METADATA").write_text("Metadata-Version: 2.1\nName: triegex\nVersion: 0.0.4\n")
            (metadata / "direct_url.json").write_text(json.dumps({
                "url": "https://github.com/ZhukovAlexander/triegex.git",
                "vcs_info": {"vcs": "git", "commit_id": COMMIT},
            }))
            (site / "triegex.py").write_text(textwrap.dedent("""
                import os
                def log(value):
                    with open(os.environ['TRIEGEX_CALLS'], 'a') as stream: stream.write(value + '\\n')
                class Triegex:
                    def __init__(self, *words): self.words=words; log('init:' + repr(words))
                    def to_regex(self): log('to_regex'); return 'yes'
                    def __contains__(self, value): log('contains:' + value); return value == 'yes'
            """))
            calls = root / "calls"
            environment = {"PYTHONPATH": os.fspath(site), "TRIEGEX_CALLS": os.fspath(calls)}
            result = subprocess.run(
                [sys.executable, "-S", root / "bin" / "triegex", "contains", "zebra", "apple",
                 "--candidate", "yes", "--candidate", "no"],
                env={**os.environ, **environment}, capture_output=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls.read_text().splitlines(), [
                "init:()", "init:('zebra', 'apple')", "contains:yes", "contains:no",
            ])
            self.assertNotIn("to_regex", calls.read_text())

    def test_command_runs_outside_checkout_and_code_shaped_words_are_inert(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sentinel = root / "ran"
            word = f"(?{{__import__('pathlib').Path({os.fspath(sentinel)!r}).touch()}})"
            result = run("contains", word, "--candidate", word, cwd=root)
            self.assert_success(result)
            self.assertTrue(json_lines(result.stdout)[0]["contains"])
            self.assertFalse(sentinel.exists())


if __name__ == "__main__":
    unittest.main()

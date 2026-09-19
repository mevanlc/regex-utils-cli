from __future__ import annotations

import importlib.metadata
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = Path(sys.prefix) / "bin" / "exrex"


def run(*arguments: str, cwd: Path | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [os.fspath(CLI), *arguments],
        cwd=cwd or ROOT,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        timeout=10,
        check=False,
    )


class ExrexCliTest(unittest.TestCase):
    def assert_success(self, result: subprocess.CompletedProcess[bytes]) -> None:
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertEqual(result.stderr, b"")

    def test_locked_distribution_and_native_help(self) -> None:
        self.assertEqual(importlib.metadata.version("exrex"), "0.12.0")
        result = run("--help")
        self.assert_success(result)
        self.assertIn(b"exrex - regular expression string generator", result.stdout)
        self.assertIn(b"--max-number", result.stdout)

    def test_enumeration_is_lazy_ordered_and_bounded(self) -> None:
        result = run("[ab]{1,2}", "--max-number", "4")
        self.assert_success(result)
        self.assertEqual(result.stdout, b"a\nb\naa\nab\n")

        unbounded = run("a+", "--limit", "3", "--max-number", "4")
        self.assert_success(unbounded)
        self.assertEqual(unbounded.stdout, b"a\naa\naaa\n")

    def test_delimiter_count_simplification_and_backreferences(self) -> None:
        delimited = run("[ab]", "--delimiter", "|")
        counted = run("[01]{0,9}", "--count")
        simplified = run("(ab|ac)", "--simplify")
        referenced = run(r"(ex)r\1")
        for result in (delimited, counted, simplified, referenced):
            self.assert_success(result)
        self.assertEqual(delimited.stdout, b"a|b")
        self.assertEqual(counted.stdout, b"1023\n")
        self.assertEqual(simplified.stdout, b"(a[bc])\n")
        self.assertEqual(referenced.stdout, b"exrex\n")

    def test_random_value_matches_the_supplied_python_regex(self) -> None:
        result = run(r"(foo|bar)[0-9]{2}", "--random")
        self.assert_success(result)
        value = result.stdout.decode().removesuffix("\n")
        self.assertIsNotNone(re.fullmatch(r"(foo|bar)[0-9]{2}", value))

    def test_output_file_uses_the_native_stream_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "values"
            result = run("[xy]", "--output", os.fspath(output))
            self.assert_success(result)
            self.assertEqual(result.stdout, b"")
            self.assertEqual(output.read_bytes(), b"x\ny\n")

    def test_errors_retain_upstream_statuses_and_diagnostics(self) -> None:
        invalid = run("(")
        self.assertEqual(invalid.returncode, 1)
        self.assertEqual(invalid.stdout, b"")
        self.assertTrue(invalid.stderr.startswith(b"[!] Error:"))

        usage = run("--bogus", "[a]")
        self.assertEqual(usage.returncode, 2)
        self.assertEqual(usage.stdout, b"")
        self.assertIn(b"unrecognized arguments: --bogus", usage.stderr)

        empty = run("")
        self.assertEqual(empty.returncode, 1)
        self.assertEqual(empty.stdout, b"")
        self.assertIn(b"TypeError: 'list' object is not an iterator", empty.stderr)

    def test_console_script_works_outside_the_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = run("[ab]", cwd=Path(directory))
        self.assert_success(result)
        self.assertEqual(result.stdout, b"a\nb\n")


if __name__ == "__main__":
    unittest.main()

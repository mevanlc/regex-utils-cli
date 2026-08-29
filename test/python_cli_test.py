from __future__ import annotations

import errno
from pathlib import Path
import sys
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "lib"))

from python_cli import CliError, split_records, write_stdout  # noqa: E402


class PythonCliHelpersTest(unittest.TestCase):
    def test_record_splitting_preserves_contract(self) -> None:
        self.assertEqual(split_records(""), [])
        self.assertEqual(split_records("a\n"), ["a"])
        self.assertEqual(split_records("a\n\n"), ["a", ""])
        self.assertEqual(split_records("\n"), [""])
        self.assertEqual(split_records("a\r\nb\rc"), ["a", "b\rc"])
        self.assertEqual(split_records("a\r"), ["a\r"])

    def test_stdout_epipe_is_quiet(self) -> None:
        with (
            patch("python_cli.os.write", side_effect=BrokenPipeError(errno.EPIPE, "closed")),
            patch("python_cli.os.open", return_value=99),
            patch("python_cli.os.dup2"),
            patch("python_cli.os.close"),
        ):
            write_stdout("complete output\n")

    def test_other_stdout_failures_are_runtime_errors(self) -> None:
        with patch("python_cli.os.write", side_effect=OSError(errno.EIO, "injected")):
            with self.assertRaises(CliError) as raised:
                write_stdout("complete output\n")
        self.assertEqual(raised.exception.status, 1)
        self.assertIn("cannot write stdout", str(raised.exception))

    def test_partial_writes_are_completed(self) -> None:
        chunks: list[bytes] = []

        def partial(_fd: int, data: memoryview) -> int:
            count = min(2, len(data))
            chunks.append(bytes(data[:count]))
            return count

        with patch("python_cli.os.write", side_effect=partial):
            write_stdout("abcdef")
        self.assertEqual(b"".join(chunks), b"abcdef")


if __name__ == "__main__":
    unittest.main()

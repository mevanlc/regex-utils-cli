from __future__ import annotations

import functools
import json
import operator
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "bin" / "retrie"


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


class RetrieCliTest(unittest.TestCase):
    def assert_success(self, result: subprocess.CompletedProcess[bytes]) -> None:
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertEqual(result.stderr, b"")

    def test_help_and_version_are_stable(self) -> None:
        top = run("--help")
        self.assert_success(top)
        for command in ("build", "check", "filter", "cleanse", "replace"):
            self.assertIn(f"retrie {command}".encode(), top.stdout)
            result = run(command, "--help")
            self.assert_success(result)
            self.assertTrue(result.stdout.startswith(f"Usage: retrie {command}".encode()))
        version = run("--version")
        self.assert_success(version)
        self.assertEqual(version.stdout, b"retrie 0.3.1\n")

    def test_build_is_exact_deterministic_and_literal(self) -> None:
        for keys in (("abc", "foo", "abs"), ("foo", "abs", "abc")):
            result = run("build", *keys)
            self.assert_success(result)
            self.assertEqual(result.stdout, rb"(?:ab[cs]|foo)" + b"\n")
        escaped = run("build", "a.b", "a*b", "[x]", "café", "a.b")
        self.assert_success(escaped)
        self.assertIn(rb"a(?:\*b|\.b)", escaped.stdout)
        self.assertIn(rb"\[x\]", escaped.stdout)
        self.assertIn("café".encode(), escaped.stdout)

    def test_build_preserves_empty_key_distinctions(self) -> None:
        zero = run("build", "--input", "-", input=b"")
        one_empty = run("build", "")
        optional = run("build", "", "foo")
        for result in (zero, one_empty, optional):
            self.assert_success(result)
        self.assertEqual(zero.stdout, b"\n")
        self.assertEqual(one_empty.stdout, b"\n")
        self.assertEqual(optional.stdout, b"(?:foo)?\n")

    def test_key_and_candidate_records_preserve_controls_and_order(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            keys = Path(directory) / "keys"
            candidates = Path(directory) / "candidates"
            keys.write_bytes("foo\r\ncafé\nspace word\ncr\r".encode() + b"\x00x\n\n")
            candidates.write_bytes("FOO\r\ncafé\nspace word\ncr\r".encode() + b"\x00x\nnone\n")
            result = run(
                "check", "whitelist", "--substring", "--input", os.fspath(keys),
                "--candidate-input", os.fspath(candidates),
            )
            self.assert_success(result)
            values = json_lines(result.stdout)
            self.assertEqual([value["candidate"] for value in values], [
                "FOO", "café", "space word", "cr\r\x00x", "none",
            ])
            self.assertEqual([value["whitelisted"] for value in values], [True] * 5)

        direct = run("build", "foo")
        explicit = run("build", "--input", "-", input=b"foo\n")
        implicit = run("build", input=b"foo\n")
        self.assertEqual(explicit.stdout, direct.stdout)
        self.assertEqual(implicit.stdout, direct.stdout)

    def test_check_modes_boundaries_case_and_substrings(self) -> None:
        candidates = ["foo", "FOO", "foobar", "a foo bar", "none"]
        for mode, property_name in (("blacklist", "blacklisted"), ("whitelist", "whitelisted")):
            result = run(
                "check", mode, "foo",
                *functools.reduce(operator.iadd, (["--candidate", candidate] for candidate in candidates), []),
            )
            self.assert_success(result)
            self.assertEqual([value[property_name] for value in json_lines(result.stdout)],
                             [True, True, False, True, False])

        substring = run("check", "blacklist", "--substring", "foo", "--candidate", "foobar")
        sensitive = run("check", "blacklist", "--case-sensitive", "foo", "--candidate", "FOO")
        self.assertTrue(json_lines(substring.stdout)[0]["blacklisted"])
        self.assertFalse(json_lines(sensitive.stdout)[0]["blacklisted"])

    def test_zero_key_checklist_preserves_upstream_boundary_quirk(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            empty = Path(directory) / "empty"
            empty.write_bytes(b"")
            result = run(
                "check", "blacklist", "--input", os.fspath(empty),
                "--candidate", "abc", "--candidate", "!!!",
            )
        self.assert_success(result)
        self.assertEqual(json_lines(result.stdout), [
            {"candidate": "abc", "blacklisted": True},
            {"candidate": "!!!", "blacklisted": False},
        ])

    def test_filter_calls_mode_direction_and_preserves_duplicates(self) -> None:
        arguments = ["--candidate", "good", "--candidate", "foo", "--candidate", "good"]
        blacklist = run("filter", "blacklist", "foo", *arguments)
        whitelist = run("filter", "whitelist", "foo", *arguments)
        self.assert_success(blacklist)
        self.assert_success(whitelist)
        self.assertEqual(json_lines(blacklist.stdout), [{"candidate": "good"}, {"candidate": "good"}])
        self.assertEqual(json_lines(whitelist.stdout), [{"candidate": "foo"}])
        empty = run("filter", "whitelist", "foo", "--candidate", "none")
        self.assert_success(empty)
        self.assertEqual(empty.stdout, b"")

    def test_cleanse_preserves_distinct_mode_semantics_and_raw_bytes(self) -> None:
        blacklist = run("cleanse", "blacklist", "abc", "foo", "abs", "--text", "good ABC foobar")
        whitelist = run("cleanse", "whitelist", "abc", "foo", "abs", "--text", "good ABC foobar")
        self.assert_success(blacklist)
        self.assert_success(whitelist)
        self.assertEqual(blacklist.stdout, b"good  foobar")
        self.assertEqual(whitelist.stdout, b"ABC")
        substring = run("cleanse", "whitelist", "--substring", "abc", "foo", "--text", "ABCfoobar")
        self.assertEqual(substring.stdout, b"ABCfoo")
        sensitive = run("cleanse", "blacklist", "--case-sensitive", "café", "--text", "CAFÉ café")
        self.assertEqual(sensitive.stdout, "CAFÉ ".encode())
        empty = run("cleanse", "blacklist", "foo", "--text", "")
        self.assert_success(empty)
        self.assertEqual(empty.stdout, b"")

    def test_cleanse_reads_complete_text_without_normalization(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            keys = Path(directory) / "keys"
            text = Path(directory) / "text"
            keys.write_bytes(b"x\x00y\n")
            text.write_bytes(b"before\nx\x00y\nafter\n")
            result = run(
                "cleanse", "blacklist", "--substring", "--input", os.fspath(keys),
                "--text-input", os.fspath(text),
            )
        self.assert_success(result)
        self.assertEqual(result.stdout, b"before\n\nafter\n")

    def test_replace_argv_pairs_count_case_and_substrings(self) -> None:
        base = (
            "replace", "--replacement", "abc", "new1", "--replacement", "foo", "new2",
            "--replacement", "abs", "new3", "--text", "ABS ...foo... foobar",
        )
        all_result = run(*base)
        one = run(*base, "--count", "1")
        substring = run(*base, "--substring")
        self.assert_success(all_result)
        self.assertEqual(all_result.stdout, b"new3 ...new2... foobar")
        self.assertEqual(one.stdout, b"new3 ...foo... foobar")
        self.assertEqual(substring.stdout, b"new3 ...new2... new2bar")

        sensitive = run(
            "replace", "--case-sensitive", "--replacement", "x", "one",
            "--replacement", "X", "two", "--text", "x X",
        )
        self.assert_success(sensitive)
        self.assertEqual(sensitive.stdout, b"one two")

    def test_replace_json_lines_preserves_arbitrary_strings(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            mappings = Path(directory) / "mappings"
            text = Path(directory) / "text"
            mappings.write_text(
                json.dumps({"old": "a.b", "new": "line\nNUL\x00$"}) + "\n" +
                json.dumps({"old": "x", "new": "\\1"}) + "\n",
            )
            text.write_bytes(b"a.b x")
            result = run(
                "replace", "--replacement-input", os.fspath(mappings),
                "--text-input", os.fspath(text),
            )
        self.assert_success(result)
        self.assertEqual(result.stdout, b"line\nNUL\x00$ \\1")

    def test_replacement_collisions_and_malformed_mappings_fail_cleanly(self) -> None:
        collision = run(
            "replace", "--replacement", "x", "one", "--replacement", "X", "two",
            "--text", "x X",
        )
        self.assertEqual(collision.returncode, 1)
        self.assertEqual(collision.stdout, b"")
        self.assertIn(b"replace failed:", collision.stderr)

        duplicate = run(
            "replace", "--replacement", "x", "one", "--replacement", "x", "two",
            "--text", "x",
        )
        self.assertEqual(duplicate.returncode, 1)
        self.assertIn(b"duplicate replacement key", duplicate.stderr)

        with tempfile.TemporaryDirectory() as directory:
            mapping = Path(directory) / "mapping"
            invalid_records = [
                b"", b"\n", b"not-json\n", b"[]\n", b'{"old":"x"}\n',
                b'{"old":"x","new":"y","extra":1}\n', b'{"old":1,"new":"y"}\n',
            ]
            for data in invalid_records:
                mapping.write_bytes(data)
                result = run("replace", "--replacement-input", os.fspath(mapping), "--text", "x")
                self.assertEqual(result.returncode, 1, data)
                self.assertEqual(result.stdout, b"")
                self.assertNotIn(b"Traceback", result.stderr)

    def test_invalid_command_lines_are_usage_errors(self) -> None:
        cases = [
            (),
            ("unknown",),
            ("check",),
            ("check", "unknown", "foo", "--candidate", "foo"),
            ("build", "--substring", "foo"),
            ("build", "--input", "a", "--input", "b"),
            ("build", "--input", "file", "foo"),
            ("check", "blacklist", "foo"),
            ("check", "blacklist", "foo", "--candidate", "x", "--candidate-input", "file"),
            ("cleanse", "blacklist", "foo", "--text", "x", "--text-input", "file"),
            ("replace", "--text", "x"),
            ("replace", "--replacement", "x", "y", "--count", "-1", "--text", "x"),
            ("replace", "--replacement", "x", "y", "--count", " 1", "--text", "x"),
            ("replace", "--replacement", "x", "y", "--count", "1.0", "--text", "x"),
            ("check", "blacklist", "--input", "-", "--candidate-input", "-"),
            ("replace", "--replacement-input", "-", "--text-input", "-"),
            ("--version", "extra"),
            ("replace", "--help", "extra"),
        ]
        for arguments in cases:
            with self.subTest(arguments=arguments):
                result = run(*arguments, input=b"")
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, b"")
                self.assertTrue(result.stderr.startswith(b"retrie:"))
                self.assertNotIn(b"Traceback", result.stderr)

    def test_file_utf8_candidate_and_recursion_failures_are_normalized(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            invalid = Path(directory) / "invalid"
            invalid.write_bytes(b"\xff")
            for arguments in (
                ("build", "--input", os.fspath(invalid)),
                ("check", "blacklist", "foo", "--candidate-input", os.fspath(invalid)),
                ("cleanse", "blacklist", "foo", "--text-input", os.fspath(invalid)),
                ("build", "--input", os.fspath(Path(directory) / "missing")),
            ):
                result = run(*arguments)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, b"")
                self.assertNotIn(b"Traceback", result.stderr)
        zero = run("check", "blacklist", "foo", "--candidate-input", "-", input=b"")
        self.assertEqual(zero.returncode, 1)
        self.assertEqual(zero.stderr, b"retrie: candidate input contains no records\n")
        deep = run("build", "x" * 2000)
        self.assertEqual(deep.returncode, 1)
        self.assertEqual(deep.stdout, b"")
        self.assertIn(b"build failed:", deep.stderr)
        self.assertNotIn(b"Traceback", deep.stderr)

    def test_help_is_bootstrap_free_and_dependency_check_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bin").mkdir()
            (root / "lib").mkdir()
            shutil.copy2(CLI, root / "bin" / "retrie")
            shutil.copy2(ROOT / "lib" / "python_cli.py", root / "lib" / "python_cli.py")
            help_result = subprocess.run(
                [sys.executable, "-S", root / "bin" / "retrie", "--help"],
                capture_output=True, check=False,
            )
            self.assertEqual(help_result.returncode, 0)
            version = subprocess.run(
                [sys.executable, "-S", root / "bin" / "retrie", "--version"],
                capture_output=True, check=False,
            )
            self.assertEqual(version.returncode, 1)
            self.assertEqual(version.stdout, b"")
            self.assertEqual(
                version.stderr,
                b"retrie: pinned retrie 0.3.1 is unavailable; run uv sync --frozen\n",
            )

    def test_controlled_dependency_proves_direct_public_api_mapping(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bin").mkdir()
            (root / "lib").mkdir()
            site = root / "site"
            package = site / "retrie"
            metadata = site / "retrie-0.3.1.dist-info"
            package.mkdir(parents=True)
            metadata.mkdir()
            shutil.copy2(CLI, root / "bin" / "retrie")
            shutil.copy2(ROOT / "lib" / "python_cli.py", root / "lib" / "python_cli.py")
            (metadata / "METADATA").write_text("Metadata-Version: 2.1\nName: retrie\nVersion: 0.3.1\n")
            (package / "__init__.py").write_text("")
            (package / "trie.py").write_text(textwrap.dedent("""
                import os
                def log(value):
                    with open(os.environ['RETRIE_CALLS'], 'a') as stream: stream.write(value + '\\n')
                class Trie:
                    def __init__(self, *keys): log('Trie:' + repr(keys))
                    def pattern(self): log('pattern'); return 'fake'
            """))
            (package / "retrie.py").write_text(textwrap.dedent("""
                import os
                def log(value):
                    with open(os.environ['RETRIE_CALLS'], 'a') as stream: stream.write(value + '\\n')
                class Base:
                    def __init__(self, keys, **options): log(type(self).__name__ + ':' + repr(keys) + ':' + repr(options))
                    def is_blacklisted(self, value): log('is_blacklisted:' + value); return True
                    def is_whitelisted(self, value): log('is_whitelisted:' + value); return True
                    def filter(self, values): log('filter:' + repr(values)); return iter(values[:1])
                    def cleanse_text(self, text): log('cleanse_text:' + text); return 'clean'
                class Blacklist(Base): pass
                class Whitelist(Base): pass
                class Replacer:
                    def __init__(self, mapping, **options): log('Replacer:' + repr(mapping) + ':' + repr(options))
                    def replace(self, text, count=0): log('replace:' + text + ':' + str(count)); return 'replaced'
            """))
            calls = root / "calls"
            environment = {"PYTHONPATH": os.fspath(site), "RETRIE_CALLS": os.fspath(calls)}
            commands = [
                (["build", "zebra", "apple"], ["Trie:('zebra', 'apple')", "pattern"]),
                (["check", "blacklist", "--case-sensitive", "zebra", "--candidate", "yes"],
                 ["Blacklist:['zebra']:{'re_flags': None}", "is_blacklisted:yes"]),
                (["filter", "whitelist", "--substring", "zebra", "--candidate", "yes", "--candidate", "no"],
                 ["Whitelist:['zebra']:{'match_substrings': True}", "filter:['yes', 'no']"]),
                (["cleanse", "blacklist", "zebra", "--text", "text"],
                 ["Blacklist:['zebra']:{}", "cleanse_text:text"]),
                (["replace", "--replacement", "old", "new", "--count", "2", "--text", "text"],
                 ["Replacer:{'old': 'new'}:{}", "replace:text:2"]),
            ]
            for arguments, expected in commands:
                if calls.exists():
                    calls.unlink()
                result = subprocess.run(
                    [sys.executable, "-S", root / "bin" / "retrie", *arguments],
                    env={**os.environ, **environment}, capture_output=True, check=False,
                )
                self.assertEqual(result.returncode, 0, (arguments, result.stderr))
                self.assertEqual(calls.read_text().splitlines(), expected)

    def test_command_runs_outside_checkout_and_code_shaped_keys_are_inert(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sentinel = root / "ran"
            key = f"__import__('pathlib').Path({os.fspath(sentinel)!r}).touch()"
            result = run("build", key, cwd=root)
            self.assert_success(result)
            self.assertFalse(sentinel.exists())


if __name__ == "__main__":
    unittest.main()

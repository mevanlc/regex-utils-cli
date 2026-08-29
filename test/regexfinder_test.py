from __future__ import annotations

import json
import inspect
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "bin" / "regexfinder"
COMMIT = "88b50c683f77c68ff232f75e111ea6650940c4b5"


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
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def json_lines(output: bytes) -> list[object]:
    assert output.endswith(b"\n")
    return [json.loads(line) for line in output.decode().splitlines()]


class RegexfinderCliTest(unittest.TestCase):
    def assert_success(self, result: subprocess.CompletedProcess[bytes]) -> None:
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertEqual(result.stderr, b"")

    def test_help_and_version_are_stable(self) -> None:
        top = run("--help")
        self.assert_success(top)
        self.assertIn(b"regexfinder analyze", top.stdout)
        self.assertNotIn(b"matching-text", top.stdout)
        for command in ("analyze", "optimize", "search"):
            result = run(command, "--help")
            self.assert_success(result)
            self.assertTrue(result.stdout.startswith(f"Usage: regexfinder {command}".encode()))
        version = run("--version")
        self.assert_success(version)
        self.assertEqual(
            version.stdout,
            f"regexfinder 0.0.0 (mevanlc/regexfinder {COMMIT})\n".encode(),
        )

    def test_analyze_preserves_direct_leaf_defect_and_metric_types(self) -> None:
        result = run("analyze", "[ab]")
        self.assert_success(result)
        self.assertEqual(
            json.loads(result.stdout),
            {
                "input_regex": "[ab]",
                "alpha": 1.0,
                "graph": {
                    "out_regex": "[ab]",
                    "cardinality": 2,
                    "log2_cardinality": 2.0,
                    "entropy": 1.0,
                    "complexity": 4,
                    "phi": 6.0,
                },
            },
        )
        self.assertEqual(result.stdout.count(b"\n"), 1)

    def test_alpha_maps_to_graph_without_wrapper_recalculation(self) -> None:
        zero = json.loads(run("analyze", "--alpha", "0", "a(b|c)d").stdout)
        half = json.loads(run("analyze", "--alpha", "0.5", "a(b|c)d").stdout)
        self.assertEqual(zero["graph"]["phi"], 1.0)
        self.assertEqual(half["graph"]["phi"], 4.5)
        self.assertEqual(zero["graph"]["complexity"], half["graph"]["complexity"])

    def test_optimize_reports_one_phi_reduction_and_captures_debug(self) -> None:
        quiet = run("optimize", "a(b|c)d")
        self.assert_success(quiet)
        value = json.loads(quiet.stdout)
        self.assertEqual(value["before"]["out_regex"], "a(b|c)d")
        self.assertEqual(value["before"]["phi"], 8.0)
        self.assertEqual(value["after"]["out_regex"], "a[bc]d")
        self.assertEqual(value["after"]["phi"], 7.0)
        self.assertTrue(value["changed"])

        verbose = run("optimize", "--verbose", "a(b|c)d")
        self.assertEqual(verbose.returncode, 0)
        self.assertEqual(verbose.stdout, quiet.stdout)
        self.assertIn(b"regexfinder: upstream: Nodes ", verbose.stderr)
        self.assertNotIn(b"Nodes ", verbose.stdout)

    def test_search_boolean_and_detailed_results_use_node_match(self) -> None:
        boolean = run("search", "--boolean", "ca[rt]", "car", "dog", "xxcat!")
        self.assert_success(boolean)
        self.assertEqual(
            json_lines(boolean.stdout),
            [
                {"text": "car", "matched": True},
                {"text": "dog", "matched": False},
                {"text": "xxcat!", "matched": True},
            ],
        )
        detailed = run("search", "(c)(a)(?P<last>t)", "xxcat cat")
        self.assert_success(detailed)
        value = json_lines(detailed.stdout)[0]
        self.assertEqual(value["text"], "xxcat cat")
        self.assertTrue(value["matched"])
        self.assertEqual([match["text"] for match in value["matches"]], ["cat", "cat"])
        self.assertEqual(value["matches"][0], {
            "text": "cat", "start": 2, "end": 5,
            "groups": ["c", "a", "t"], "groupdict": {"last": "t"},
        })

    def test_candidate_sources_preserve_records_controls_and_order(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "candidates"
            source.write_bytes("car\r\ndog\n\n café\r".encode() + b"\x00x")
            file_result = run("search", "--boolean", "car|café|\\x00", "--input", os.fspath(source))
            self.assert_success(file_result)
            self.assertEqual(json_lines(file_result.stdout), [
                {"text": "car", "matched": True},
                {"text": "dog", "matched": False},
                {"text": "", "matched": False},
                {"text": " café\r\x00x", "matched": True},
            ])

        explicit = run("search", "--boolean", "ca[rt]", "--input", "-", input=b"car\ndog\n")
        implicit = run("search", "--boolean", "ca[rt]", input=b"car\ndog\n")
        self.assertEqual(explicit.stdout, implicit.stdout)
        self.assertEqual(json_lines(explicit.stdout)[0]["text"], "car")

    def test_empty_and_duplicate_candidate_records_remain_distinct(self) -> None:
        result = run("search", "--boolean", "^$", "", "x", "")
        self.assert_success(result)
        self.assertEqual(json_lines(result.stdout), [
            {"text": "", "matched": True},
            {"text": "x", "matched": False},
            {"text": "", "matched": True},
        ])

    def test_invalid_command_lines_are_usage_errors(self) -> None:
        cases = [
            (),
            ("unknown",),
            ("analyze",),
            ("analyze", "--alpha", "-1", "x"),
            ("analyze", "--alpha", "nan", "x"),
            ("analyze", "--alpha", "1", "--alpha", "2", "x"),
            ("analyze", "--verbose", "x"),
            ("optimize", "--input", "x", "pattern"),
            ("search", "pattern", "text", "--input", "file"),
            ("search", "--boolean", "--boolean", "pattern", "text"),
            ("--version", "extra"),
            ("search", "--help", "pattern"),
        ]
        for arguments in cases:
            with self.subTest(arguments=arguments):
                result = run(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, b"")
                self.assertTrue(result.stderr.startswith(b"regexfinder:"))
                self.assertNotIn(b"Traceback", result.stderr)

    def test_input_and_processing_failures_are_runtime_errors(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            invalid = Path(directory) / "invalid"
            invalid.write_bytes(b"\xff")
            cases = [
                ("search", "x", "--input", os.fspath(Path(directory) / "missing")),
                ("search", "x", "--input", os.fspath(invalid)),
            ]
            for arguments in cases:
                result = run(*arguments)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, b"")
                self.assertNotIn(b"Traceback", result.stderr)
        zero = run("search", "x", input=b"")
        self.assertEqual(zero.returncode, 1)
        self.assertEqual(zero.stderr, b"regexfinder: candidate input contains no records\n")
        for arguments in (("analyze", ""), ("analyze", "a+"), ("analyze", "("), ("search", "(", "x")):
            result = run(*arguments)
            self.assertEqual(result.returncode, 1, arguments)
            self.assertEqual(result.stdout, b"")
            self.assertNotIn(b"Traceback", result.stderr)

    def test_command_runs_outside_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = run("analyze", "[ab]", cwd=Path(directory))
        self.assert_success(result)
        self.assertEqual(json.loads(result.stdout)["graph"]["phi"], 6.0)

    def test_help_is_bootstrap_free_and_dependency_check_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bin").mkdir()
            (root / "lib").mkdir()
            shutil.copy2(CLI, root / "bin" / "regexfinder")
            shutil.copy2(ROOT / "lib" / "python_cli.py", root / "lib" / "python_cli.py")
            help_result = subprocess.run(
                [sys.executable, "-S", root / "bin" / "regexfinder", "--help"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            )
            self.assertEqual(help_result.returncode, 0)
            version = subprocess.run(
                [sys.executable, "-S", root / "bin" / "regexfinder", "--version"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            )
            self.assertEqual(version.returncode, 1)
            self.assertEqual(version.stdout, b"")
            self.assertEqual(
                version.stderr,
                b"regexfinder: pinned mevanlc/regexfinder dependency is unavailable; run uv sync --frozen\n",
            )

    def test_controlled_dependency_proves_direct_api_mapping(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bin").mkdir()
            (root / "lib").mkdir()
            site = root / "site"
            package = site / "regexfinder"
            metadata = site / "regexfinder-0.0.0.dist-info"
            package.mkdir(parents=True)
            metadata.mkdir()
            shutil.copy2(CLI, root / "bin" / "regexfinder")
            shutil.copy2(ROOT / "lib" / "python_cli.py", root / "lib" / "python_cli.py")
            (metadata / "METADATA").write_text("Metadata-Version: 2.1\nName: regexfinder\nVersion: 0.0.0\n")
            (metadata / "direct_url.json").write_text(json.dumps({
                "url": "https://github.com/mevanlc/regexfinder.git",
                "vcs_info": {"vcs": "git", "commit_id": COMMIT},
            }))
            (package / "__init__.py").write_text(textwrap.dedent("""
                import json, os, re
                def log(value):
                    with open(os.environ['REGEXFINDER_CALLS'], 'a') as stream: stream.write(value + '\\n')
                class GRAPH:
                    def __init__(self, regex=None, alpha=1): self.regex=regex; self.alpha=alpha; log(f'GRAPH:{regex}:{alpha}')
                    def partition(self): log('partition')
                    def reducePhi(self): log('reducePhi'); self.regex='after'
                    outRegex=property(lambda self: self.regex)
                    cardinality=property(lambda self: 2)
                    log2Cardinality=property(lambda self: 1)
                    entropy=property(lambda self: 1)
                    K=property(lambda self: 3)
                    phi=property(lambda self: 4)
                class NODE:
                    def __init__(self, regex=None): self.regex=regex; log(f'NODE:{regex}')
                    def match(self, text, boolean=False):
                        log(f'match:{text}:{boolean}')
                        matches=list(re.finditer(self.regex,text))
                        return bool(matches) if boolean else iter(matches)
            """))
            calls = root / "calls"
            environment = {"PYTHONPATH": os.fspath(site), "REGEXFINDER_CALLS": os.fspath(calls)}
            result = subprocess.run(
                [sys.executable, "-S", root / "bin" / "regexfinder", "optimize", "--alpha", "2", "before"],
                env={**os.environ, **environment}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls.read_text().splitlines(), ["GRAPH:before:2.0", "partition", "reducePhi"])
            calls.unlink()
            result = subprocess.run(
                [sys.executable, "-S", root / "bin" / "regexfinder", "search", "--boolean", "x", "x", "no"],
                env={**os.environ, **environment}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls.read_text().splitlines(), ["NODE:x", "match:x:True", "match:no:True"])

    def test_python_shaped_input_is_inert(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sentinel = Path(directory) / "ran"
            text = f"__import__('pathlib').Path({os.fspath(sentinel)!r}).touch()"
            result = run("search", "--boolean", "touch", text)
            self.assert_success(result)
            self.assertFalse(sentinel.exists())

    def test_unexposed_upstream_generation_and_visualization_limits_remain(self) -> None:
        from regexfinder import GRAPH

        graph = GRAPH(regex="[ab]")
        graph.partition()
        self.assertIsNone(graph.random)
        self.assertIn("dot.render(view=True)", inspect.getsource(GRAPH.createVisual))
        non_ascii = run("analyze", "café")
        self.assertEqual(non_ascii.returncode, 1)
        self.assertEqual(non_ascii.stdout, b"")
        self.assertIn(b"size 128", non_ascii.stderr)


if __name__ == "__main__":
    unittest.main()

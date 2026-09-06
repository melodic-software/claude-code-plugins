#!/usr/bin/env python3
"""Output-based tests for the mypy-report adapter at its command line.

mypy is an unmanaged out-of-process dependency, so it is stubbed: each test
generates a fake `mypy` in a temporary directory prepended to PATH that copies
the committed capture fixtures/tool-output/mypy-any-exprs.txt into the report
directory the adapter asked for (design T13; no executable is committed). The
table parser is also driven directly, because a capture with zero `Any`
expressions cannot show that a non-zero count is read from the right column.
"""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "mypy-report.py"
CAPTURE = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "mypy-any-exprs.txt"
SOURCES = "plugins/code-metrics/scripts/fixtures/sources"
REPO_ROOT = SCRIPT_DIR.parents[3]


def load_module():
    spec = importlib.util.spec_from_file_location("cm_mypy_report", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_stub(
    directory: Path,
    exit_code: int = 0,
    capture: Path | None = CAPTURE,
    stdout_line: str = "",
    stderr_line: str = "",
) -> None:
    """Write a `mypy` stub that replays the capture into the report directory."""
    copy = (
        f'cp "{capture}" "$dir/any-exprs.txt"\n'
        if capture is not None
        else "# the report is never written\n"
    )
    stub = directory / "mypy"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        'if [[ "${1:-}" == "--version" ]]; then printf \'mypy 1.19.1 (compiled: yes)\\n\'; exit 0; fi\n'
        'dir=""\nprev=""\n'
        'for arg in "$@"; do\n'
        '  [[ "$prev" == "--any-exprs-report" ]] && dir="$arg"\n'
        '  prev="$arg"\n'
        "done\n"
        '[[ -n "$dir" ]] && mkdir -p "$dir"\n' + copy + f"printf '%s' '{stdout_line}'\n"
        f"printf '%s' '{stderr_line}' >&2\n"
        f"exit {exit_code}\n",
        encoding="utf-8",
    )
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def run(*args: str, path_prefix: Path | None = None) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    if path_prefix is not None:
        env["PATH"] = f"{path_prefix}{os.pathsep}{env.get('PATH', '')}"
    else:
        env["PATH"] = str(
            Path(tempfile.gettempdir()) / "definitely-empty-path-for-mypy-tests"
        )
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=REPO_ROOT,
        check=False,
    )


class MypyReportProbeTests(unittest.TestCase):
    def test_probe_fails_when_mypy_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not on PATH", result.stderr)

    def test_probe_prints_the_version_when_the_stub_resolves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "1.19.1"))


class MypyReportCollectTests(unittest.TestCase):
    def test_collect_reads_the_total_row_into_one_per_lane_row(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(len(rows), 1)
            row = rows[0]
            self.assertEqual((row["file"], row["function"]), (None, None))
            self.assertEqual(row["lane"], "python")
            self.assertEqual(row["collector"], "mypy-report")
            self.assertEqual(
                row["values"],
                {
                    "any_expressions": 0,
                    "expressions_total": 13,
                    "type_coverage_pct": 100.0,
                },
            )
            self.assertEqual(row["labels"], [])

    def test_collect_removes_the_report_directory_it_asked_mypy_for(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            before = set(Path(tempfile.gettempdir()).glob("*"))
            run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            leaked = [
                p
                for p in set(Path(tempfile.gettempdir()).glob("*")) - before
                if (p / "any-exprs.txt").exists()
            ]
            self.assertEqual(leaked, [])

    def test_a_reporting_exit_code_still_yields_a_row_and_a_label(self) -> None:
        # mypy exits 1 on any type error while still writing the report (T1).
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(
                Path(tmp),
                exit_code=1,
                stdout_line="cm_sample.py:5: error: Incompatible return value type",
            )
            result = run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            row = json.loads(result.stdout.splitlines()[0])
            self.assertEqual(row["labels"], ["mypy-reported-errors"])
            self.assertEqual(row["values"]["expressions_total"], 13)

    def test_no_report_written_is_exit_3_with_the_tool_stderr_relayed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(
                Path(tmp),
                exit_code=2,
                capture=None,
                stderr_line="mypy: error: unrecognized arguments",
            )
            result = run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 3)
            self.assertIn("unrecognized arguments", result.stderr)
            self.assertEqual(result.stdout, "")

    def test_an_unreadable_table_is_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            garbled = Path(tmp) / "garbled.txt"
            garbled.write_text("no total row here\n", encoding="utf-8")
            make_stub(Path(tmp), capture=garbled)
            result = run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 3)
            self.assertIn("no Total row", result.stderr)


class MypyReportTableTests(unittest.TestCase):
    def test_the_total_row_is_read_from_a_table_with_several_modules(self) -> None:
        module = load_module()
        table = (
            "      Name   Anys   Exprs   Coverage\n"
            "-------------------------------------\n"
            "  cm_first      3       4     25.00%\n"
            " cm_second      0      12    100.00%\n"
            "-------------------------------------\n"
            "     Total      3      16     81.25%\n"
        )
        self.assertEqual(module.parse_total(table), (3, 16, 81.25))

    def test_a_table_without_a_total_row_is_a_value_error(self) -> None:
        module = load_module()
        with self.assertRaises(ValueError):
            module.parse_total("      Name   Anys   Exprs   Coverage\n")


class MypyReportVerbTests(unittest.TestCase):
    def test_other_verbs(self) -> None:
        self.assertEqual(run("measures").stdout.strip(), "python/type_coverage")
        self.assertIn("mypy", run("install_hint").stdout)
        self.assertEqual(run("collect", "python", "cyclomatic", "x.py").returncode, 2)
        self.assertEqual(run().returncode, 2)


if __name__ == "__main__":
    unittest.main()

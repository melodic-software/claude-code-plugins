#!/usr/bin/env python3
"""Output-based tests for the shellmetrics adapter at its command line.

The tool is an unmanaged out-of-process dependency, so it is stubbed: each
test generates a fake `shellmetrics` in a temporary directory prepended to
PATH that replays the committed capture
fixtures/tool-output/shellmetrics.csv (design T13; no executable is
committed).
"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from harness.stub_harness import (
    SOURCES,
    TOOL_OUTPUT,
    run_adapter,
    version_gate,
    write_stub,
)

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "shellmetrics.py"
CAPTURE = TOOL_OUTPUT / "shellmetrics.csv"


def make_stub(directory: Path, capture: Path | None = CAPTURE) -> None:
    write_stub(
        directory / "shellmetrics",
        version_gate("0.5.0") + (f'cat "{capture}"\n' if capture else "") + "exit 0\n",
    )


def run(*args: str, path_prefix: Path | None = None) -> subprocess.CompletedProcess:
    return run_adapter(SCRIPT, "shellmetrics", *args, path_prefix=path_prefix)


class ShellmetricsAdapterTests(unittest.TestCase):
    def test_probe_fails_when_shellmetrics_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not on PATH", result.stderr)

    def test_probe_prints_the_version_when_the_stub_resolves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "0.5.0"))

    def test_measures_lists_the_single_pair_it_serves(self) -> None:
        self.assertEqual(run("measures").stdout.split(), ["bash/cyclomatic"])

    def test_install_hint_names_the_tool(self) -> None:
        self.assertIn("shellmetrics", run("install_hint").stdout)

    def test_collect_drops_the_pseudo_rows_and_keeps_the_functions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect",
                "bash",
                "cyclomatic",
                f"{SOURCES}/cm-sample.sh",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual([r["function"] for r in rows], ["greet"])
            row = rows[0]
            self.assertEqual(row["file"], f"{SOURCES}/cm-sample.sh")
            self.assertEqual(row["values"], {"cyclomatic": 3})
            self.assertEqual(row["start_line"], 8)
            self.assertIsNone(row["end_line"])
            self.assertEqual(row["labels"], ["start-line-only"])
            self.assertEqual(row["collector"], "shellmetrics")
            self.assertEqual(row["lane"], "bash")

    def test_collect_reports_unparsable_output_as_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            broken = Path(tmp) / "broken.csv"
            broken.write_text("shellmetrics said nothing useful\n", encoding="utf-8")
            make_stub(Path(tmp), capture=broken)
            result = run(
                "collect",
                "bash",
                "cyclomatic",
                f"{SOURCES}/cm-sample.sh",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 3)
            self.assertIn("no parseable", result.stderr)

    def test_collect_reports_empty_output_as_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp), capture=None)
            result = run(
                "collect",
                "bash",
                "cyclomatic",
                f"{SOURCES}/cm-sample.sh",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 3)

    def test_usage_errors_exit_2(self) -> None:
        self.assertEqual(run("collect", "python", "cyclomatic", "x.py").returncode, 2)
        self.assertEqual(run("collect", "bash", "cognitive", "x.sh").returncode, 2)
        self.assertEqual(run("wat").returncode, 2)


if __name__ == "__main__":
    unittest.main()

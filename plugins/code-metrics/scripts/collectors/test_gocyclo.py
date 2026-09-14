#!/usr/bin/env python3
"""Output-based tests for the gocyclo adapter at its command line.

The tool is an unmanaged out-of-process dependency, so it is stubbed: each
test generates a fake `gocyclo` in a temporary directory prepended to PATH
that replays the committed capture fixtures/tool-output/gocyclo.txt (design
T13; no executable is committed).
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
    dash_version_gate,
    run_adapter,
    write_stub,
)

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "gocyclo.py"
CAPTURE = TOOL_OUTPUT / "gocyclo.txt"


def make_stub(
    directory: Path, version_line: str = "v0.6.0", capture: Path | None = CAPTURE
) -> None:
    write_stub(
        directory / "gocyclo",
        dash_version_gate(version_line)
        + (f'cat "{capture}"\n' if capture else "")
        + "exit 0\n",
    )


def run(*args: str, path_prefix: Path | None = None) -> subprocess.CompletedProcess:
    return run_adapter(SCRIPT, "gocyclo", *args, path_prefix=path_prefix)


class GocycloAdapterTests(unittest.TestCase):
    def test_probe_fails_when_gocyclo_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not on PATH", result.stderr)

    def test_probe_prints_the_version_when_the_stub_resolves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "0.6.0"))

    def test_probe_still_resolves_when_no_version_flag_is_understood(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp), version_line="usage: gocyclo [flags] paths")
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual(
                (result.returncode, result.stdout.strip()), (0, "unknown-version")
            )

    def test_measures_lists_the_single_pair_it_serves(self) -> None:
        self.assertEqual(run("measures").stdout.split(), ["go/cyclomatic"])

    def test_install_hint_names_the_tool(self) -> None:
        self.assertIn("gocyclo", run("install_hint").stdout)

    def test_collect_reports_a_start_line_only_row(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect",
                "go",
                "cyclomatic",
                f"{SOURCES}/cm-sample.go",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(len(rows), 1)
            row = rows[0]
            self.assertEqual(row["file"], f"{SOURCES}/cm-sample.go")
            self.assertEqual(row["function"], "Classify")
            self.assertEqual(row["values"], {"cyclomatic": 3})
            self.assertEqual(row["start_line"], 7)
            self.assertIsNone(row["end_line"])
            self.assertEqual(row["labels"], ["start-line-only"])
            self.assertEqual(row["collector"], "gocyclo")

    def test_collect_reports_unparsable_output_as_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            broken = Path(tmp) / "broken.txt"
            broken.write_text("gocyclo said nothing useful\n", encoding="utf-8")
            make_stub(Path(tmp), capture=broken)
            result = run(
                "collect",
                "go",
                "cyclomatic",
                f"{SOURCES}/cm-sample.go",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 3)
            self.assertIn("no parseable", result.stderr)

    def test_collect_reports_empty_output_as_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp), capture=None)
            result = run(
                "collect",
                "go",
                "cyclomatic",
                f"{SOURCES}/cm-sample.go",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 3)

    def test_usage_errors_exit_2(self) -> None:
        self.assertEqual(run("collect", "python", "cyclomatic", "x.py").returncode, 2)
        self.assertEqual(run("collect", "go", "cognitive", "x.go").returncode, 2)
        self.assertEqual(run("wat").returncode, 2)


if __name__ == "__main__":
    unittest.main()

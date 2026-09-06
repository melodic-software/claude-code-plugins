#!/usr/bin/env python3
"""Output-based tests for the lizard adapter at its command line.

The tool is an unmanaged out-of-process dependency, so it is stubbed: each
test generates a fake `lizard` in a temporary directory prepended to PATH
that replays the committed capture fixtures/tool-output/lizard.csv (design
T13; no executable is committed).
"""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "lizard.py"
CAPTURE = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "lizard.csv"
SOURCES = "plugins/code-metrics/scripts/fixtures/sources"
REPO_ROOT = SCRIPT_DIR.parents[3]


def make_stub(
    directory: Path, version_line: str = "1.24.0", capture: Path | None = CAPTURE
) -> None:
    body = f'cat "{capture}"\n' if capture else "exit 0\n"
    stub = directory / "lizard"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        'if [[ "${1:-}" == "--version" ]]; then printf \'%s\\n\' "'
        + version_line
        + '"; exit 0; fi\n'
        + body,
        encoding="utf-8",
    )
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def run(*args: str, path_prefix: Path | None = None) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    if path_prefix is not None:
        env["PATH"] = f"{path_prefix}{os.pathsep}{env.get('PATH', '')}"
    else:
        env["PATH"] = str(
            Path(tempfile.gettempdir()) / "definitely-empty-path-for-lizard-tests"
        )
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=REPO_ROOT,
        check=False,
    )


class LizardAdapterTests(unittest.TestCase):
    def test_probe_fails_when_lizard_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not on PATH", result.stderr)

    def test_probe_prints_the_version_when_the_stub_resolves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "1.24.0"))

    def test_measures_lists_every_lane_and_measure_pair(self) -> None:
        pairs = sorted(run("measures").stdout.split())
        self.assertEqual(
            pairs,
            [
                "go/cyclomatic",
                "go/function_lines",
                "python/cyclomatic",
                "python/function_lines",
                "typescript/cyclomatic",
                "typescript/function_lines",
            ],
        )

    def test_install_hint_names_the_tool(self) -> None:
        self.assertIn("lizard", run("install_hint").stdout)

    def test_collect_cyclomatic_carries_start_and_end_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect",
                "python",
                "cyclomatic",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(len(rows), 2)
            outer = next(r for r in rows if r["function"] == "classify")
            self.assertEqual(outer["file"], f"{SOURCES}/cm_sample.py")
            self.assertEqual((outer["start_line"], outer["end_line"]), (9, 20))
            self.assertEqual(outer["values"], {"cyclomatic": 3})
            self.assertEqual(outer["lane"], "python")
            self.assertEqual(outer["collector"], "lizard")
            self.assertEqual(outer["labels"], [])
            nested = next(r for r in rows if r["function"] == "classify.inner")
            self.assertEqual((nested["start_line"], nested["end_line"]), (12, 14))

    def test_collect_ignores_rows_for_files_that_were_not_requested(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect",
                "go",
                "cyclomatic",
                f"./{SOURCES}/cm-sample.go",
                path_prefix=Path(tmp),
            )
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual([r["file"] for r in rows], [f"./{SOURCES}/cm-sample.go"])

    def test_collect_function_lines_reports_the_iso_percentage(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect",
                "python",
                "function_lines",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            outer = next(r for r in rows if r["function"] == "classify")
            self.assertEqual(outer["values"]["function_lines"], 10)
            self.assertAlmostEqual(
                outer["values"]["function_lines_pct"], 66.67, places=2
            )
            self.assertEqual((outer["start_line"], outer["end_line"]), (9, 20))

    def test_collect_reports_unparsable_output_as_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            broken = Path(tmp) / "broken.csv"
            broken.write_text("not a lizard record\n", encoding="utf-8")
            make_stub(Path(tmp), capture=broken)
            result = run(
                "collect",
                "python",
                "cyclomatic",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 3)
            self.assertIn("no parseable", result.stderr)

    def test_collect_reports_empty_output_as_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp), capture=None)
            result = run(
                "collect",
                "python",
                "cyclomatic",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 3)

    def test_usage_errors_exit_2(self) -> None:
        self.assertEqual(run("collect", "bash", "cyclomatic", "x.sh").returncode, 2)
        self.assertEqual(run("collect", "python", "halstead", "x.py").returncode, 2)
        self.assertEqual(run("wat").returncode, 2)


if __name__ == "__main__":
    unittest.main()

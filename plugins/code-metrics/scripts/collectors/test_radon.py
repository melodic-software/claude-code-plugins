#!/usr/bin/env python3
"""Output-based tests for the radon adapter at its command line.

The tool is an unmanaged out-of-process dependency, so it is stubbed: each
test generates a fake `radon` in a temporary directory prepended to PATH that
answers `--version`, `cc -j` from the committed capture
fixtures/tool-output/radon-cc.json, and `hal -j` from
fixtures/tool-output/radon-hal.json (design T13; no executable is committed).
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
SCRIPT = SCRIPT_DIR / "radon.py"
TOOL_OUTPUT = SCRIPT_DIR.parent / "fixtures" / "tool-output"
CC_CAPTURE = TOOL_OUTPUT / "radon-cc.json"
HAL_CAPTURE = TOOL_OUTPUT / "radon-hal.json"
SOURCES = "plugins/code-metrics/scripts/fixtures/sources"
REPO_ROOT = SCRIPT_DIR.parents[3]


def make_stub(
    directory: Path,
    version_line: str = "6.0.1",
    cc: Path | None = CC_CAPTURE,
    hal: Path | None = HAL_CAPTURE,
) -> None:
    stub = directory / "radon"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        'if [[ "${1:-}" == "--version" ]]; then printf \'%s\\n\' "'
        + version_line
        + '"; exit 0; fi\n'
        + (f'if [[ "${{1:-}}" == "cc" ]]; then cat "{cc}"; exit 0; fi\n' if cc else "")
        + (
            f'if [[ "${{1:-}}" == "hal" ]]; then cat "{hal}"; exit 0; fi\n'
            if hal
            else ""
        )
        + "exit 0\n",
        encoding="utf-8",
    )
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def run(*args: str, path_prefix: Path | None = None) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    if path_prefix is not None:
        env["PATH"] = f"{path_prefix}{os.pathsep}{env.get('PATH', '')}"
    else:
        env["PATH"] = str(
            Path(tempfile.gettempdir()) / "definitely-empty-path-for-radon-tests"
        )
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=REPO_ROOT,
        check=False,
    )


class RadonAdapterTests(unittest.TestCase):
    def test_probe_fails_when_radon_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not on PATH", result.stderr)

    def test_probe_prints_the_version_when_the_stub_resolves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "6.0.1"))

    def test_measures_lists_every_lane_and_measure_pair(self) -> None:
        self.assertEqual(
            sorted(run("measures").stdout.split()),
            ["python/cyclomatic", "python/function_lines", "python/halstead"],
        )

    def test_install_hint_names_the_tool(self) -> None:
        self.assertIn("radon", run("install_hint").stdout)

    def test_collect_cyclomatic_includes_closures_with_their_own_ranges(self) -> None:
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
            self.assertEqual(sorted(r["function"] for r in rows), ["classify", "inner"])
            outer = next(r for r in rows if r["function"] == "classify")
            self.assertEqual((outer["start_line"], outer["end_line"]), (9, 20))
            self.assertEqual(outer["values"], {"cyclomatic": 3})
            self.assertEqual(outer["collector"], "radon")
            self.assertEqual(outer["file"], f"{SOURCES}/cm_sample.py")
            closure = next(r for r in rows if r["function"] == "inner")
            self.assertEqual((closure["start_line"], closure["end_line"]), (12, 14))
            self.assertEqual(closure["values"], {"cyclomatic": 2})

    def test_collect_halstead_has_no_line_range_and_says_so(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect",
                "python",
                "halstead",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(len(rows), 1)
            row = rows[0]
            self.assertEqual(row["function"], "classify")
            self.assertIsNone(row["start_line"])
            self.assertIsNone(row["end_line"])
            self.assertEqual(row["labels"], ["no-line-range"])
            self.assertEqual(
                row["values"],
                {
                    "halstead_difficulty": 2.0,
                    "halstead_volume": 12.0,
                    "halstead_effort": 24.0,
                },
            )

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
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            outer = next(r for r in rows if r["function"] == "classify")
            self.assertEqual(outer["values"]["function_lines"], 10)
            self.assertAlmostEqual(
                outer["values"]["function_lines_pct"], 66.67, places=2
            )

    def test_collect_reports_unparsable_output_as_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            broken = Path(tmp) / "broken.json"
            broken.write_text("not json", encoding="utf-8")
            make_stub(Path(tmp), cc=broken)
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
            make_stub(Path(tmp), cc=None)
            result = run(
                "collect",
                "python",
                "cyclomatic",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 3)

    def test_usage_errors_exit_2(self) -> None:
        self.assertEqual(run("collect", "go", "cyclomatic", "x.go").returncode, 2)
        self.assertEqual(run("collect", "python", "cognitive", "x.py").returncode, 2)
        self.assertEqual(run("wat").returncode, 2)


if __name__ == "__main__":
    unittest.main()

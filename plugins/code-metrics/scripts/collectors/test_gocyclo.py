#!/usr/bin/env python3
"""Output-based tests for the gocyclo adapter at its command line.

The tool is an unmanaged out-of-process dependency, so it is stubbed: each
test generates a fake `gocyclo` in a temporary directory prepended to PATH
that replays the committed capture fixtures/tool-output/gocyclo.txt (design
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
SCRIPT = SCRIPT_DIR / "gocyclo.py"
CAPTURE = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "gocyclo.txt"
SOURCES = "plugins/code-metrics/scripts/fixtures/sources"
REPO_ROOT = SCRIPT_DIR.parents[3]


def make_stub(
    directory: Path, version_line: str = "v0.6.0", capture: Path | None = CAPTURE
) -> None:
    stub = directory / "gocyclo"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        'case "${1:-}" in -version | --version) '
        "printf '%s\\n' \""
        + version_line
        + '"; exit 0 ;; esac\n'
        + (f'cat "{capture}"\n' if capture else "")
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
            Path(tempfile.gettempdir()) / "definitely-empty-path-for-gocyclo-tests"
        )
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=REPO_ROOT,
        check=False,
    )


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

#!/usr/bin/env python3
"""Output-based tests for the multimetric adapter at its command line.

The tool is an unmanaged out-of-process dependency, so it is stubbed: each
test generates a fake `multimetric` in a temporary directory prepended to
PATH that replays the committed capture
fixtures/tool-output/multimetric.json (design T13; no executable is
committed). The capture keys its files by absolute path, which is what the
adapter's path mapping has to survive.
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
SCRIPT = SCRIPT_DIR / "multimetric.py"
CAPTURE = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "multimetric.json"
SOURCES = "plugins/code-metrics/scripts/fixtures/sources"
REPO_ROOT = SCRIPT_DIR.parents[3]


def make_stub(
    directory: Path, version_line: str = "2.4.4", capture: Path | None = CAPTURE
) -> None:
    stub = directory / "multimetric"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        'if [[ "${1:-}" == "--version" ]]; then printf \'%s\\n\' "'
        + version_line
        + '"; exit 0; fi\n'
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
            Path(tempfile.gettempdir()) / "definitely-empty-path-for-multimetric-tests"
        )
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=REPO_ROOT,
        check=False,
    )


class MultimetricAdapterTests(unittest.TestCase):
    def test_probe_fails_when_multimetric_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not on PATH", result.stderr)

    def test_probe_prints_the_version_when_the_stub_resolves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "2.4.4"))

    def test_measures_lists_every_lane_and_measure_pair(self) -> None:
        self.assertEqual(
            sorted(run("measures").stdout.split()),
            [
                "bash/cyclomatic",
                "bash/halstead",
                "go/halstead",
                "python/halstead",
                "typescript/halstead",
            ],
        )

    def test_install_hint_names_the_tool(self) -> None:
        self.assertIn("multimetric", run("install_hint").stdout)

    def test_collect_halstead_is_file_level_with_no_function(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect",
                "typescript",
                "halstead",
                f"{SOURCES}/cm-sample.ts",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(len(rows), 1)
            row = rows[0]
            self.assertEqual(row["file"], f"{SOURCES}/cm-sample.ts")
            self.assertIsNone(row["function"])
            self.assertIsNone(row["start_line"])
            self.assertIsNone(row["end_line"])
            self.assertEqual(row["labels"], ["file-level"])
            self.assertEqual(
                row["values"],
                {
                    "halstead_difficulty": 6.0,
                    "halstead_volume": 106.606,
                    "halstead_effort": 639.636,
                },
            )

    def test_collect_bash_cyclomatic_is_labelled_an_approximation(self) -> None:
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
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["values"], {"cyclomatic": 4})
            self.assertEqual(rows[0]["labels"], ["multimetric-approximation"])
            self.assertIsNone(rows[0]["function"])

    def test_collect_reports_unparsable_output_as_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            broken = Path(tmp) / "broken.json"
            broken.write_text("not json", encoding="utf-8")
            make_stub(Path(tmp), capture=broken)
            result = run(
                "collect",
                "go",
                "halstead",
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
                "halstead",
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

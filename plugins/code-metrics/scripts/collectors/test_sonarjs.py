#!/usr/bin/env python3
"""Output-based tests for the sonarjs adapter at its command line.

The tool is an unmanaged out-of-process dependency, so it is stubbed: each
test generates a fake `eslint` in a temporary directory prepended to PATH
that replays the committed capture fixtures/tool-output/sonarjs.json and
exits 1, the code ESLint uses whenever it reports anything (design T1). The
plugin half of the gate is stubbed by creating
`node_modules/eslint-plugin-sonarjs/package.json` in the working directory.
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
SCRIPT = SCRIPT_DIR / "sonarjs.py"
CAPTURE = TOOL_OUTPUT / "sonarjs.json"


def make_stub(
    directory: Path, capture: Path | None = CAPTURE, exit_code: int = 1
) -> None:
    body = f'cat "{capture}"\n' if capture else ""
    write_stub(
        directory / "eslint",
        version_gate("v10.1.0") + body + f"exit {exit_code}\n",
    )


def make_plugin(directory: Path) -> Path:
    package = directory / "node_modules" / "eslint-plugin-sonarjs"
    package.mkdir(parents=True, exist_ok=True)
    (package / "package.json").write_text(
        '{"name": "eslint-plugin-sonarjs", "version": "3.0.5"}\n', encoding="utf-8"
    )
    return directory


def run(
    *args: str, path_prefix: Path | None = None, cwd: Path | None = None
) -> subprocess.CompletedProcess:
    return run_adapter(SCRIPT, "sonarjs", *args, path_prefix=path_prefix, cwd=cwd)


class SonarjsAdapterTests(unittest.TestCase):
    def test_probe_fails_when_eslint_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("eslint", result.stderr)

    def test_probe_fails_when_only_eslint_resolves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual(result.returncode, 1)
            self.assertIn("eslint-plugin-sonarjs", result.stderr)

    def test_probe_prints_the_version_when_both_halves_resolve(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            work = make_plugin(Path(tmp) / "project")
            result = run("probe", path_prefix=Path(tmp), cwd=work)
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "10.1.0"))

    def test_measures_lists_the_single_pair_it_serves(self) -> None:
        self.assertEqual(run("measures").stdout.split(), ["typescript/cognitive"])

    def test_install_hint_names_the_plugin(self) -> None:
        self.assertIn("eslint-plugin-sonarjs", run("install_hint").stdout)

    def test_collect_treats_the_reporting_exit_code_as_success(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp), exit_code=1)
            work = make_plugin(Path(tmp) / "project")
            result = run(
                "collect",
                "typescript",
                "cognitive",
                f"{SOURCES}/cm-sample.ts",
                path_prefix=Path(tmp),
                cwd=work,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(len(rows), 1)
            row = rows[0]
            self.assertEqual(row["file"], f"{SOURCES}/cm-sample.ts")
            self.assertEqual(row["function"], "classify")
            self.assertEqual(row["values"], {"cognitive": 2})
            self.assertEqual(row["start_line"], 4)
            self.assertIsNone(row["end_line"])
            self.assertEqual(row["labels"], ["start-line-only"])
            self.assertEqual(row["collector"], "sonarjs")

    def test_collect_reports_unparsable_output_as_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            broken = Path(tmp) / "broken.json"
            broken.write_text("not json", encoding="utf-8")
            make_stub(Path(tmp), capture=broken)
            work = make_plugin(Path(tmp) / "project")
            result = run(
                "collect",
                "typescript",
                "cognitive",
                f"{SOURCES}/cm-sample.ts",
                path_prefix=Path(tmp),
                cwd=work,
            )
            self.assertEqual(result.returncode, 3)
            self.assertIn("no parseable", result.stderr)

    def test_collect_reports_empty_output_as_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp), capture=None)
            work = make_plugin(Path(tmp) / "project")
            result = run(
                "collect",
                "typescript",
                "cognitive",
                f"{SOURCES}/cm-sample.ts",
                path_prefix=Path(tmp),
                cwd=work,
            )
            self.assertEqual(result.returncode, 3)

    def test_usage_errors_exit_2(self) -> None:
        self.assertEqual(run("collect", "go", "cognitive", "x.go").returncode, 2)
        self.assertEqual(
            run("collect", "typescript", "cyclomatic", "x.ts").returncode, 2
        )
        self.assertEqual(run("wat").returncode, 2)


if __name__ == "__main__":
    unittest.main()

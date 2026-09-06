#!/usr/bin/env python3
"""Output-based tests for the type-coverage adapter at its command line.

type-coverage is an unmanaged out-of-process dependency, so it is stubbed:
each test generates a fake `type-coverage` that replays the committed capture
fixtures/tool-output/type-coverage.json, either on a temporary directory
prepended to PATH or inside a scratch project's node_modules/.bin (design T13;
no executable is committed). The probe's second requirement, a resolvable
`typescript`, is stubbed by a scratch node_modules/typescript/package.json.
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
SCRIPT = SCRIPT_DIR / "type-coverage.py"
CAPTURE = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "type-coverage.json"
SOURCES = "plugins/code-metrics/scripts/fixtures/sources"
REPO_ROOT = SCRIPT_DIR.parents[3]
NO_TYPESCRIPT = "type-coverage needs a resolvable typescript (the probe found none)"


def write_stub(path: Path, capture: Path = CAPTURE, exit_code: int = 0) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "#!/usr/bin/env bash\n"
        'if [[ "${1:-}" == "--version" ]]; then printf \'Version: 2.30.1\\n\'; exit 0; fi\n'
        f'cat "{capture}"\n'
        f"exit {exit_code}\n",
        encoding="utf-8",
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def make_project(root: Path, with_typescript: bool = True, local_stub: bool = False):
    """A scratch cwd: optional node_modules/typescript and a local binary."""
    if with_typescript:
        package = root / "node_modules" / "typescript" / "package.json"
        package.parent.mkdir(parents=True, exist_ok=True)
        package.write_text('{"name": "typescript", "version": "5.9.3"}\n', "utf-8")
    if local_stub:
        write_stub(root / "node_modules" / ".bin" / "type-coverage")


def run(
    *args: str, path_prefix: Path | None = None, cwd: Path | None = None
) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    if path_prefix is not None:
        env["PATH"] = f"{path_prefix}{os.pathsep}{env.get('PATH', '')}"
    else:
        env["PATH"] = str(
            Path(tempfile.gettempdir()) / "definitely-empty-path-for-tc-tests"
        )
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=str(cwd or REPO_ROOT),
        check=False,
    )


class TypeCoverageProbeTests(unittest.TestCase):
    def test_probe_fails_when_the_binary_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not on PATH", result.stderr)
        self.assertNotIn(NO_TYPESCRIPT, result.stderr)

    def test_probe_fails_with_its_own_sentence_when_typescript_does_not_resolve(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stubs = Path(tmp) / "bin"
            write_stub(stubs / "type-coverage")
            project = Path(tmp) / "project"
            project.mkdir()
            make_project(project, with_typescript=False)
            result = run("probe", path_prefix=stubs, cwd=project)
            self.assertEqual(result.returncode, 1)
            self.assertIn(NO_TYPESCRIPT, result.stderr)

    def test_probe_passes_when_both_the_binary_and_typescript_resolve(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stubs = Path(tmp) / "bin"
            write_stub(stubs / "type-coverage")
            project = Path(tmp) / "project"
            project.mkdir()
            make_project(project)
            result = run("probe", path_prefix=stubs, cwd=project)
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "2.30.1"))

    def test_probe_finds_the_binary_in_the_project_node_modules(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            empty = Path(tmp) / "bin"
            empty.mkdir()
            project = Path(tmp) / "project"
            project.mkdir()
            make_project(project, local_stub=True)
            result = run("probe", path_prefix=empty, cwd=project)
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "2.30.1"))


class TypeCoverageCollectTests(unittest.TestCase):
    def _collect(self, tmp: str, capture: Path = CAPTURE, exit_code: int = 0):
        stubs = Path(tmp) / "bin"
        write_stub(stubs / "type-coverage", capture=capture, exit_code=exit_code)
        return run(
            "collect",
            "typescript",
            "type_coverage",
            f"{SOURCES}/cm-sample.ts",
            path_prefix=stubs,
        )

    def test_collect_translates_the_capture_into_one_per_lane_row(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = self._collect(tmp)
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(len(rows), 1)
            row = rows[0]
            self.assertEqual((row["file"], row["function"]), (None, None))
            self.assertEqual(row["lane"], "typescript")
            self.assertEqual(row["collector"], "type-coverage")
            self.assertEqual(
                row["values"],
                {
                    "type_coverage_pct": 55.55,
                    "typed_identifiers": 5,
                    "total_identifiers": 9,
                    "any_count": 4,
                },
            )

    def test_a_reporting_exit_code_still_yields_a_row(self) -> None:
        # --at-least makes the tool exit non-zero while still printing its JSON.
        with tempfile.TemporaryDirectory() as tmp:
            result = self._collect(tmp, exit_code=1)
            self.assertEqual(result.returncode, 0, result.stderr)
            row = json.loads(result.stdout.splitlines()[0])
            self.assertEqual(row["values"]["type_coverage_pct"], 55.55)

    def test_a_capture_without_details_reports_a_null_any_count(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = json.loads(CAPTURE.read_text(encoding="utf-8"))
            payload.pop("details")
            terse = Path(tmp) / "terse.json"
            terse.write_text(json.dumps(payload), encoding="utf-8")
            result = self._collect(tmp, capture=terse)
            self.assertEqual(result.returncode, 0, result.stderr)
            row = json.loads(result.stdout.splitlines()[0])
            self.assertIsNone(row["values"]["any_count"])
            self.assertEqual(row["values"]["typed_identifiers"], 5)

    def test_a_null_percent_stays_null_rather_than_becoming_zero(self) -> None:
        # No tsconfig means nothing was counted: the tool prints percent null.
        with tempfile.TemporaryDirectory() as tmp:
            empty = Path(tmp) / "empty.json"
            empty.write_text(
                json.dumps(
                    {
                        "succeeded": True,
                        "details": [],
                        "correctCount": 0,
                        "percent": None,
                        "percentString": "NaN",
                        "totalCount": 0,
                    }
                ),
                encoding="utf-8",
            )
            result = self._collect(tmp, capture=empty)
            self.assertEqual(result.returncode, 0, result.stderr)
            row = json.loads(result.stdout.splitlines()[0])
            self.assertIsNone(row["values"]["type_coverage_pct"])
            self.assertEqual(row["values"]["any_count"], 0)

    def test_unparsable_output_is_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            broken = Path(tmp) / "broken.json"
            broken.write_text("ts.SyntaxKind is undefined", encoding="utf-8")
            result = self._collect(tmp, capture=broken)
            self.assertEqual(result.returncode, 3)
            self.assertIn("unparsable", result.stderr)


class TypeCoverageVerbTests(unittest.TestCase):
    def test_other_verbs(self) -> None:
        self.assertEqual(run("measures").stdout.strip(), "typescript/type_coverage")
        self.assertIn("type-coverage", run("install_hint").stdout)
        self.assertIn("typescript", run("install_hint").stdout)
        self.assertEqual(
            run("collect", "typescript", "cyclomatic", "x.ts").returncode, 2
        )
        self.assertEqual(run().returncode, 2)


if __name__ == "__main__":
    unittest.main()

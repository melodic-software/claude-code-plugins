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
# A real `--detail --json-output --show-relative-path` capture (2.30.1,
# typescript 5.9) over a scratch project: src/a.ts and src/sub/b.ts carry
# any-typed identifiers, src/clean.ts none, and other/outside.ts sits outside
# the tsconfig's `include`, so the tool never names it.
DETAIL = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "type-coverage-detail.json"
DETAIL_SCOPE = ("src/a.ts", "src/sub/b.ts", "src/clean.ts", "other/outside.ts")
SOURCES = "plugins/code-metrics/scripts/fixtures/sources"
REPO_ROOT = SCRIPT_DIR.parents[3]
NO_TYPESCRIPT = "type-coverage needs a resolvable typescript (the probe found none)"


def write_stub(
    path: Path,
    capture: Path = CAPTURE,
    exit_code: int = 0,
    argv_log: Path | None = None,
) -> None:
    """A `type-coverage` stub replaying `capture`; with `argv_log` it also
    records every argument it received, one per line."""
    path.parent.mkdir(parents=True, exist_ok=True)
    log = f'printf \'%s\\n\' "$@" >"{argv_log}"\n' if argv_log is not None else ""
    path.write_text(
        "#!/usr/bin/env bash\n"
        'if [[ "${1:-}" == "--version" ]]; then printf \'Version: 2.30.1\\n\'; exit 0; fi\n'
        + log
        + f'cat "{capture}"\n'
        f"exit {exit_code}\n",
        encoding="utf-8",
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def write_node_stub(
    path: Path, program: list[str] | None, exit_code: int = 0, stderr: str = ""
) -> None:
    """A `node` stub standing in for the tsconfig-program listing: prints
    `program` as JSON (`null` for no tsconfig), or fails with `stderr`."""
    path.parent.mkdir(parents=True, exist_ok=True)
    listing = json.dumps(program) if program is not None else "null"
    path.write_text(
        "#!/usr/bin/env bash\n"
        f"printf '%s\\n' '{listing}'\n"
        + (f"printf '%s\\n' '{stderr}' >&2\n" if stderr else "")
        + f"exit {exit_code}\n",
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
        write_node_stub(stubs / "node", [f"{SOURCES}/cm-sample.ts"])
        return run(
            "collect",
            "typescript",
            "type_coverage",
            f"{SOURCES}/cm-sample.ts",
            path_prefix=stubs,
        )

    def test_collect_translates_the_capture_into_a_file_row_and_the_lane_row(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = self._collect(tmp)
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(len(rows), 2)
            # The lane row leads: the lane's figure is the first row.
            lane_row, file_row = rows
            self.assertEqual(result.stderr, "")
            self.assertEqual(
                (file_row["file"], file_row["function"], file_row["labels"]),
                (f"{SOURCES}/cm-sample.ts", None, []),
            )
            # The CLI gives no per-file denominator: a file row carries the
            # occurrences listed for it and nothing else.
            self.assertEqual(
                file_row["values"],
                {
                    "type_coverage_pct": None,
                    "typed_identifiers": None,
                    "total_identifiers": None,
                    "any_count": 4,
                },
            )
            self.assertEqual((lane_row["file"], lane_row["function"]), (None, None))
            self.assertEqual(lane_row["lane"], "typescript")
            self.assertEqual(lane_row["collector"], "type-coverage")
            self.assertEqual(lane_row["labels"], ["lane-total"])
            self.assertEqual(
                lane_row["values"],
                {
                    "type_coverage_pct": 55.55,
                    "typed_identifiers": 5,
                    "total_identifiers": 9,
                    "any_count": 4,
                },
            )

    def test_file_rows_group_the_listed_occurrences_by_scope_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stubs = Path(tmp) / "bin"
            argv_log = Path(tmp) / "argv"
            write_stub(stubs / "type-coverage", capture=DETAIL, argv_log=argv_log)
            # The program holds the three files under src/, as the real
            # listing over the scratch project's tsconfig did.
            write_node_stub(
                stubs / "node", ["src/a.ts", "src/clean.ts", "src/sub/b.ts"]
            )
            result = run(
                "collect",
                "typescript",
                "type_coverage",
                *DETAIL_SCOPE,
                path_prefix=stubs,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(
                [(r["file"], r["values"]["any_count"]) for r in rows],
                [
                    (None, 9),
                    ("src/a.ts", 5),
                    ("src/sub/b.ts", 4),
                    # in the program with no listed occurrence: a measured 0
                    ("src/clean.ts", 0),
                    # other/outside.ts is outside the program: no row
                ],
            )
            self.assertEqual(rows[0]["values"]["type_coverage_pct"], 57.14)
            self.assertEqual(rows[0]["labels"], ["lane-total"])
            self.assertEqual(
                result.stderr.strip(),
                "1 scope file(s) are outside the tsconfig program and were not "
                "measured: other/outside.ts",
            )
            argv = argv_log.read_text(encoding="utf-8").splitlines()
            self.assertEqual(
                argv[:5],
                ["--detail", "--json-output", "--show-relative-path", "--", "src/a.ts"],
            )

    def test_an_unreadable_program_keeps_only_the_listed_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stubs = Path(tmp) / "bin"
            write_stub(stubs / "type-coverage", capture=DETAIL)
            write_node_stub(
                stubs / "node", None, exit_code=1, stderr="Cannot find module"
            )
            result = run(
                "collect",
                "typescript",
                "type_coverage",
                *DETAIL_SCOPE,
                path_prefix=stubs,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(
                [r["file"] for r in rows], [None, "src/a.ts", "src/sub/b.ts"]
            )
            self.assertEqual(
                result.stderr.strip(),
                "the tsconfig program could not be read (Cannot find module); "
                "only scope files with a listed occurrence have a row",
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
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            # Nothing counted: no file row either, only the lane row.
            self.assertEqual(len(rows), 1)
            self.assertIsNone(rows[0]["values"]["type_coverage_pct"])
            self.assertEqual(rows[0]["values"]["any_count"], 0)

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

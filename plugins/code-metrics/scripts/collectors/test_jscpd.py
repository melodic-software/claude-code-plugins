#!/usr/bin/env python3
"""Output-based tests for the jscpd adapter at its command line.

jscpd is an unmanaged out-of-process dependency, so it is stubbed: each test
generates a fake `jscpd` in a temporary directory prepended to PATH that
copies the committed capture fixtures/tool-output/jscpd.json into the
`--output` directory the adapter passes, the way jscpd 5 writes its own
report (design T13; no executable is committed). The capture came from a live
jscpd 5.1.2 run over the two-copy cluster under
fixtures/sources/cluster/{alpha,beta}/shared/shared-utils.sh.
"""

from __future__ import annotations

import glob
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "jscpd.py"
CAPTURE = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "jscpd.json"
CLUSTER = "plugins/code-metrics/scripts/fixtures/sources/cluster"
ALPHA = f"{CLUSTER}/alpha/shared/shared-utils.sh"
BETA = f"{CLUSTER}/beta/shared/shared-utils.sh"
REPO_ROOT = SCRIPT_DIR.parents[3]


def make_stub(
    directory: Path,
    version_line: str = "jscpd 5.1.2",
    capture: Path = CAPTURE,
    exit_code: int = 0,
    argv_log: Path | None = None,
) -> None:
    stub = directory / "jscpd"
    log = f'printf \'%s\\n\' "$*" >>"{argv_log}"\n' if argv_log else ""
    stub.write_text(
        "#!/usr/bin/env bash\n"
        'if [[ "${1:-}" == "--version" ]]; then printf \'%s\\n\' "'
        + version_line
        + '"; exit 0; fi\n'
        + log
        + "out=''\n"
        "while [[ $# -gt 0 ]]; do\n"
        '  if [[ "$1" == "--output" ]]; then out="$2"; shift 2; continue; fi\n'
        "  shift\n"
        "done\n"
        'mkdir -p "$out"\n'
        f'cp "{capture}" "$out/jscpd-report.json"\n'
        f"exit {exit_code}\n",
        encoding="utf-8",
    )
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def run(
    *args: str, path_prefix: Path | None = None, env_extra: dict | None = None
) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    if path_prefix is not None:
        env["PATH"] = f"{path_prefix}{os.pathsep}{env.get('PATH', '')}"
    else:
        env["PATH"] = str(
            Path(tempfile.gettempdir()) / "definitely-empty-path-for-jscpd-tests"
        )
    env.update(env_extra or {})
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=REPO_ROOT,
        check=False,
    )


class JscpdAdapterTests(unittest.TestCase):
    def test_probe_fails_when_jscpd_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not on PATH", result.stderr)

    def test_probe_prints_the_version_when_the_stub_resolves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "5.1.2"))

    def test_collect_translates_the_capture_into_one_clone_group(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect", "bash", "duplication", ALPHA, BETA, path_prefix=Path(tmp)
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(len(rows), 1)
            row = rows[0]
            self.assertIsNone(row["file"])
            self.assertIsNone(row["function"])
            self.assertEqual(row["lane"], "bash")
            self.assertEqual(row["collector"], "jscpd")
            self.assertEqual([i["file"] for i in row["instances"]], [ALPHA, BETA])
            self.assertEqual(
                [(i["start_line"], i["end_line"]) for i in row["instances"]],
                [(1, 41), (1, 41)],
            )
            self.assertEqual(row["values"], {"lines": 41, "tokens": 110})

    def test_a_reporting_exit_code_from_jscpd_is_not_a_failure(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp), exit_code=1)
            result = run(
                "collect", "bash", "duplication", ALPHA, BETA, path_prefix=Path(tmp)
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(result.stdout.splitlines()), 1)

    def test_absolute_report_paths_are_made_relative_to_the_working_directory(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            absolute = Path(tmp) / "absolute.json"
            absolute.write_text(
                json.dumps(
                    {
                        "duplicates": [
                            {
                                "firstFile": {
                                    "name": str(REPO_ROOT / ALPHA),
                                    "start": 1,
                                    "end": 41,
                                },
                                "secondFile": {
                                    "name": str(REPO_ROOT / BETA),
                                    "start": 1,
                                    "end": 41,
                                },
                                "lines": 41,
                                "tokens": 110,
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )
            make_stub(Path(tmp), capture=absolute)
            result = run(
                "collect", "bash", "duplication", ALPHA, BETA, path_prefix=Path(tmp)
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            row = json.loads(result.stdout.splitlines()[0])
            self.assertEqual([i["file"] for i in row["instances"]], [ALPHA, BETA])

    def test_the_configured_tunables_reach_the_command_line(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "argv.log"
            make_stub(Path(tmp), argv_log=log)
            result = run(
                "collect",
                "bash",
                "duplication",
                ALPHA,
                path_prefix=Path(tmp),
                env_extra={
                    "CODE_METRICS_DUP_MIN_TOKENS": "77",
                    "CODE_METRICS_DUP_MIN_LINES": "9",
                    "CODE_METRICS_DUP_IGNORE": "**/vendor/**,**/dist/**",
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            argv = log.read_text(encoding="utf-8")
            self.assertIn("--min-tokens 77", argv)
            self.assertIn("--min-lines 9", argv)
            self.assertIn("--ignore **/vendor/**,**/dist/**", argv)

    def test_no_report_file_is_exit_3_with_the_tool_stderr(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stub = Path(tmp) / "jscpd"
            stub.write_text(
                "#!/usr/bin/env bash\n"
                'if [[ "${1:-}" == "--version" ]]; then printf \'jscpd 5.1.2\\n\'; exit 0; fi\n'
                "printf 'jscpd: unsupported format\\n' >&2\n"
                "exit 1\n",
                encoding="utf-8",
            )
            stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
            result = run("collect", "bash", "duplication", ALPHA, path_prefix=Path(tmp))
            self.assertEqual(result.returncode, 3)
            self.assertIn("jscpd-report.json", result.stderr)
            self.assertIn("unsupported format", result.stderr)

    def test_the_temporary_output_directory_is_removed(self) -> None:
        pattern = os.path.join(tempfile.gettempdir(), "code-metrics-jscpd-*")
        before = set(glob.glob(pattern))
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            run("collect", "bash", "duplication", ALPHA, BETA, path_prefix=Path(tmp))
        self.assertEqual(set(glob.glob(pattern)) - before, set())

    def test_other_verbs(self) -> None:
        self.assertEqual(run("measures").stdout.strip(), "*/duplication")
        self.assertIn("kucherenko/jscpd", run("install_hint").stdout)
        self.assertEqual(run("collect", "bash", "cyclomatic", "x.sh").returncode, 2)
        self.assertEqual(run("wat").returncode, 2)


if __name__ == "__main__":
    unittest.main()

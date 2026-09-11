#!/usr/bin/env python3
"""Output-based tests for the jscpd adapter at its command line.

jscpd is an unmanaged out-of-process dependency, so it is stubbed: each test
generates a fake `jscpd` in a temporary directory prepended to PATH that
copies the committed capture fixtures/tool-output/jscpd.json into the
`--output` directory the adapter passes, the way jscpd 5 writes its own
report (design T13; no executable is committed). The capture came from a live
jscpd 5.1.2 run over the two-copy cluster under
fixtures/sources/cluster/{alpha,beta}/shared/shared-utils.sh; 5.2.0 writes the
same document plus a per-duplicate `kind` the adapter does not read, and 4.3.0
writes the same keys the adapter does read, so one capture stands in for both
majors and the stub only varies the version line.
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
    version_line: str = "jscpd 5.2.0",
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
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "5.2.0"))

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
                'if [[ "${1:-}" == "--version" ]]; then printf \'jscpd 5.2.0\\n\'; exit 0; fi\n'
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

    def test_explicit_caps_reach_the_command_line_on_both_majors(self) -> None:
        for version in ("jscpd 4.3.0", "jscpd 5.2.0"):
            with tempfile.TemporaryDirectory() as tmp:
                log = Path(tmp) / "argv.log"
                make_stub(Path(tmp), version_line=version, argv_log=log)
                result = run(
                    "collect",
                    "bash",
                    "duplication",
                    ALPHA,
                    BETA,
                    path_prefix=Path(tmp),
                    env_extra={
                        "CODE_METRICS_DUP_MAX_SIZE": "1mb",
                        "CODE_METRICS_DUP_MAX_LINES": "",
                    },
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                argv = log.read_text(encoding="utf-8")
                # One byte above the adapter's own bound, so the pre-filter is
                # the only gate on either major.
                self.assertIn("--max-size 1048577", argv, version)
                self.assertIn("--max-lines 1000000", argv, version)

    def test_a_zero_cap_means_no_cap_and_is_never_passed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "argv.log"
            make_stub(Path(tmp), version_line="jscpd 4.3.0", argv_log=log)
            result = run(
                "collect",
                "bash",
                "duplication",
                ALPHA,
                path_prefix=Path(tmp),
                env_extra={
                    "CODE_METRICS_DUP_MAX_SIZE": "0",
                    "CODE_METRICS_DUP_MAX_LINES": "0",
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            argv = log.read_text(encoding="utf-8")
            self.assertNotIn("--max-size 0 ", argv + " ")
            self.assertNotIn("--max-lines 0 ", argv + " ")
            self.assertIn("--max-lines 1000000", argv)
            self.assertIn("--max-size 1099511627776", argv)

    def test_the_size_grammar_uses_binary_multipliers(self) -> None:
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
                    "CODE_METRICS_DUP_MAX_SIZE": "2kb",
                    "CODE_METRICS_DUP_MAX_LINES": "44",
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            argv = log.read_text(encoding="utf-8")
            self.assertIn("--max-size 2049", argv)
            self.assertIn("--max-lines 45", argv)

    def test_files_over_the_cap_are_skipped_and_the_reason_is_recorded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "argv.log"
            note = Path(tmp) / "partial"
            big = Path(tmp) / "big.sh"
            big.write_text("echo line\n" * 100, encoding="utf-8")
            make_stub(Path(tmp), argv_log=log)
            result = run(
                "collect",
                "bash",
                "duplication",
                ALPHA,
                str(big),
                path_prefix=Path(tmp),
                env_extra={
                    "CODE_METRICS_DUP_MAX_LINES": "50",
                    "CODE_METRICS_PARTIAL_REASON_FILE": str(note),
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            argv = log.read_text(encoding="utf-8")
            self.assertIn(ALPHA, argv)
            self.assertNotIn("big.sh", argv)
            self.assertRegex(
                note.read_text(encoding="utf-8").strip(),
                r"^1 of 2 files skipped by duplication\.max_size 1mb / max_lines 50; "
                r"largest: .*big\.sh \(\d+ bytes, 100 lines\)$",
            )

    def test_all_files_skipped_returns_zero_without_invoking_jscpd(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "argv.log"
            note = Path(tmp) / "partial"
            make_stub(Path(tmp), argv_log=log)
            result = run(
                "collect",
                "bash",
                "duplication",
                ALPHA,
                BETA,
                path_prefix=Path(tmp),
                env_extra={
                    "CODE_METRICS_DUP_MAX_SIZE": "10",
                    "CODE_METRICS_PARTIAL_REASON_FILE": str(note),
                },
            )
            self.assertEqual((result.returncode, result.stdout), (0, ""), result.stderr)
            self.assertFalse(log.exists(), "jscpd was invoked with no files")
            self.assertTrue(
                note.read_text(encoding="utf-8").startswith(
                    "2 of 2 files skipped by duplication.max_size 10 / max_lines none"
                ),
                note.read_text(encoding="utf-8"),
            )

    def test_the_skip_reason_goes_to_stderr_when_no_reason_file_is_set(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect",
                "bash",
                "duplication",
                ALPHA,
                BETA,
                path_prefix=Path(tmp),
                env_extra={"CODE_METRICS_DUP_MAX_SIZE": "10"},
            )
            self.assertEqual(result.returncode, 0)
            self.assertIn("2 of 2 files skipped", result.stderr)

    def test_other_verbs(self) -> None:
        self.assertEqual(run("measures").stdout.strip(), "*/duplication")
        self.assertIn("kucherenko/jscpd", run("install_hint").stdout)
        self.assertEqual(run("collect", "bash", "cyclomatic", "x.sh").returncode, 2)
        self.assertEqual(run("wat").returncode, 2)


if __name__ == "__main__":
    unittest.main()

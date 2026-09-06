#!/usr/bin/env python3
"""Output-based tests for the PMD CPD adapter at its command line.

PMD is an unmanaged out-of-process dependency, so it is stubbed: each test
generates a fake `pmd` in a temporary directory prepended to PATH that prints
the committed fixture fixtures/tool-output/cpd.xml (design T13; no executable
is committed). That fixture follows the documented CPD XML report format and
is unverified against a live run, which the adapter's docstring records.
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
SCRIPT = SCRIPT_DIR / "cpd.py"
CAPTURE = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "cpd.xml"
REPO_ROOT = SCRIPT_DIR.parents[3]
ALPHA = "internal/alpha/orchard.go"
BETA = "internal/beta/orchard.go"


def make_stub(
    directory: Path,
    version_line: str = "PMD 7.27.0",
    capture: Path = CAPTURE,
    exit_code: int = 4,
    argv_log: Path | None = None,
) -> None:
    stub = directory / "pmd"
    log = f'printf \'%s\\n\' "$*" >>"{argv_log}"\n' if argv_log else ""
    stub.write_text(
        "#!/usr/bin/env bash\n"
        'if [[ "${1:-}" == "--version" ]]; then printf \'%s\\n\' "'
        + version_line
        + '"; exit 0; fi\n'
        + log
        + f'cat "{capture}"\n'
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
            Path(tempfile.gettempdir()) / "definitely-empty-path-for-cpd-tests"
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


class CpdAdapterTests(unittest.TestCase):
    def test_probe_fails_when_pmd_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not on PATH", result.stderr)

    def test_probe_prints_the_version_when_the_stub_resolves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "7.27.0"))

    def test_collect_translates_duplication_elements_despite_the_exit_code(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("collect", "go", "duplication", ALPHA, path_prefix=Path(tmp))
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(len(rows), 1, "the 3-line group is under the default 5")
            row = rows[0]
            self.assertIsNone(row["file"])
            self.assertIsNone(row["function"])
            self.assertEqual(row["lane"], "go")
            self.assertEqual(row["collector"], "cpd")
            self.assertEqual([i["file"] for i in row["instances"]], [ALPHA, BETA])
            self.assertEqual(
                [(i["start_line"], i["end_line"]) for i in row["instances"]],
                [(1, 41), (13, 53)],
            )
            self.assertEqual(row["values"], {"lines": 41, "tokens": 110})

    def test_min_lines_is_applied_by_the_adapter(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect",
                "go",
                "duplication",
                ALPHA,
                path_prefix=Path(tmp),
                env_extra={"CODE_METRICS_DUP_MIN_LINES": "3"},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual([r["values"]["lines"] for r in rows], [41, 3])

    def test_min_tokens_and_the_file_list_reach_the_command_line(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "argv.log"
            make_stub(Path(tmp), argv_log=log)
            result = run(
                "collect",
                "go",
                "duplication",
                ALPHA,
                path_prefix=Path(tmp),
                env_extra={"CODE_METRICS_DUP_MIN_TOKENS": "77"},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            argv = log.read_text(encoding="utf-8")
            self.assertIn("cpd --minimum-tokens 77", argv)
            self.assertIn("--format xml", argv)
            self.assertIn("--language go", argv)
            self.assertIn("--file-list", argv)

    def test_a_lane_cpd_cannot_lex_is_exit_3_with_the_reason(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect", "bash", "duplication", "a.sh", path_prefix=Path(tmp)
            )
            self.assertEqual(result.returncode, 3)
            self.assertIn("no CPD-capable language for the bash lane", result.stderr)

    def test_unparsable_xml_is_exit_3_with_the_tool_stderr(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            broken = Path(tmp) / "broken.xml"
            broken.write_text("<pmd-cpd", encoding="utf-8")
            make_stub(Path(tmp), capture=broken)
            result = run("collect", "go", "duplication", ALPHA, path_prefix=Path(tmp))
            self.assertEqual(result.returncode, 3)
            self.assertIn("unparsable CPD XML", result.stderr)

    def test_other_verbs(self) -> None:
        self.assertIn("go/duplication", run("measures").stdout.splitlines())
        self.assertNotIn("bash/duplication", run("measures").stdout.splitlines())
        self.assertIn("pmd.github.io", run("install_hint").stdout)
        self.assertEqual(run("collect", "go", "cyclomatic", "x.go").returncode, 2)
        self.assertEqual(run("wat").returncode, 2)


if __name__ == "__main__":
    unittest.main()

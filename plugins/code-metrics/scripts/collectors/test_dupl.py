#!/usr/bin/env python3
"""Output-based tests for the dupl adapter at its command line.

dupl is an unmanaged out-of-process dependency, so it is stubbed: each test
generates a fake `dupl` in a temporary directory prepended to PATH that prints
the committed fixture fixtures/tool-output/dupl.txt (design T13; no executable
is committed). That fixture follows mibk/dupl's text printer and is unverified
against a live run, which the adapter's docstring records.
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
SCRIPT = SCRIPT_DIR / "dupl.py"
CAPTURE = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "dupl.txt"
REPO_ROOT = SCRIPT_DIR.parents[3]
ALPHA = "internal/alpha/orchard.go"
BETA = "internal/beta/orchard.go"
GAMMA = "internal/gamma/orchard.go"


def make_stub(
    directory: Path,
    capture: Path = CAPTURE,
    exit_code: int = 1,
    argv_log: Path | None = None,
) -> None:
    stub = directory / "dupl"
    log = f'printf \'%s\\n\' "$*" >>"{argv_log}"\n' if argv_log else ""
    stub.write_text(
        "#!/usr/bin/env bash\n" + log + f'cat "{capture}"\n' + f"exit {exit_code}\n",
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
            Path(tempfile.gettempdir()) / "definitely-empty-path-for-dupl-tests"
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


class DuplAdapterTests(unittest.TestCase):
    def test_probe_fails_when_dupl_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not on PATH", result.stderr)

    def test_probe_reports_an_unknown_version_when_the_stub_resolves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual(
                (result.returncode, result.stdout.strip()), (0, "unknown-version")
            )

    def test_collect_translates_the_text_report_and_reports_no_tokens(self) -> None:
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
            self.assertEqual(row["collector"], "dupl")
            self.assertEqual([i["file"] for i in row["instances"]], [ALPHA, BETA])
            self.assertEqual(
                [(i["start_line"], i["end_line"]) for i in row["instances"]],
                [(12, 53), (31, 72)],
            )
            self.assertEqual(row["values"], {"lines": 42, "tokens": None})

    def test_a_group_of_three_copies_stays_one_row(self) -> None:
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
            self.assertEqual([len(r["instances"]) for r in rows], [2, 3])
            self.assertEqual([i["file"] for i in rows[1]["instances"]][2], GAMMA)

    def test_the_token_threshold_reaches_the_command_line(self) -> None:
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
            self.assertIn(f"-t 77 {ALPHA}", log.read_text(encoding="utf-8"))

    def test_a_lane_dupl_cannot_parse_is_exit_3_with_the_reason(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect", "python", "duplication", "a.py", path_prefix=Path(tmp)
            )
            self.assertEqual(result.returncode, 3)
            self.assertIn("parses Go only", result.stderr)

    def test_an_unparsable_report_is_exit_3_with_the_tool_stderr(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stub = Path(tmp) / "dupl"
            stub.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'dupl: cannot parse a.go\\n' >&2\n"
                "exit 2\n",
                encoding="utf-8",
            )
            stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
            result = run("collect", "go", "duplication", "a.go", path_prefix=Path(tmp))
            self.assertEqual(result.returncode, 3)
            self.assertIn("cannot parse a.go", result.stderr)

    def test_a_clean_run_with_no_clones_is_exit_0_with_no_rows(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            empty = Path(tmp) / "empty.txt"
            empty.write_text("\nFound total 0 clone groups.\n", encoding="utf-8")
            make_stub(Path(tmp), capture=empty, exit_code=0)
            result = run("collect", "go", "duplication", ALPHA, path_prefix=Path(tmp))
            self.assertEqual((result.returncode, result.stdout), (0, ""))

    def test_other_verbs(self) -> None:
        self.assertEqual(run("measures").stdout.strip(), "go/duplication")
        self.assertIn("mibk/dupl", run("install_hint").stdout)
        self.assertEqual(run("collect", "go", "cyclomatic", "x.go").returncode, 2)
        self.assertEqual(run("wat").returncode, 2)


if __name__ == "__main__":
    unittest.main()

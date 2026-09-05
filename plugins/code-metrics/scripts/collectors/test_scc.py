#!/usr/bin/env python3
"""Output-based tests for the scc adapter at its command line.

The tool is an unmanaged out-of-process dependency, so it is stubbed: each
test generates a fake `scc` in a temporary directory prepended to PATH that
replays the committed capture fixtures/tool-output/scc.json (design T13; no
executable is committed).
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
SCRIPT = SCRIPT_DIR / "scc.py"
CAPTURE = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "scc.json"
SOURCES = "plugins/code-metrics/scripts/fixtures/sources"
REPO_ROOT = SCRIPT_DIR.parents[3]


def make_stub(
    directory: Path, version_line: str = "scc version 3.7.0", capture: Path = CAPTURE
) -> None:
    stub = directory / "scc"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        'if [[ "${1:-}" == "--version" ]]; then printf \'%s\\n\' "'
        + version_line
        + '"; exit 0; fi\n'
        f'cat "{capture}"\n',
        encoding="utf-8",
    )
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def run(*args: str, path_prefix: Path | None = None) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    if path_prefix is not None:
        env["PATH"] = f"{path_prefix}{os.pathsep}{env.get('PATH', '')}"
    else:
        env["PATH"] = str(
            Path(tempfile.gettempdir()) / "definitely-empty-path-for-scc-tests"
        )
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=REPO_ROOT,
        check=False,
    )


class SccAdapterTests(unittest.TestCase):
    def test_probe_fails_when_scc_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not on PATH", result.stderr)

    def test_probe_prints_the_version_when_the_stub_resolves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "3.7.0"))

    def test_collect_translates_the_capture_into_rows_for_the_requested_files(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect",
                "python",
                "file_lines",
                f"{SOURCES}/cm_sample.py",
                f"./{SOURCES}/cm-sample.sh",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(
                [r["file"] for r in rows],
                [f"{SOURCES}/cm_sample.py", f"./{SOURCES}/cm-sample.sh"],
            )
            py = rows[0]
            self.assertEqual(
                py["values"],
                {
                    "lines_total": 20,
                    "lines_blank": 4,
                    "lines_comment": 8,
                    "lines_code": 8,
                    "lines_non_blank": 16,
                },
            )
            self.assertEqual(py["collector"], "scc")
            self.assertNotIn("complexity", json.dumps(rows).lower())

    def test_collect_reports_unparsable_output_as_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            broken = Path(tmp) / "broken.json"
            broken.write_text("not json", encoding="utf-8")
            make_stub(Path(tmp), capture=broken)
            result = run(
                "collect",
                "python",
                "file_lines",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 3)
            self.assertIn("unparsable", result.stderr)

    def test_other_verbs(self) -> None:
        self.assertEqual(run("measures").stdout.strip(), "*/file_lines")
        self.assertIn("boyter/scc", run("install_hint").stdout)
        self.assertEqual(run("collect", "python", "cyclomatic", "x.py").returncode, 2)


if __name__ == "__main__":
    unittest.main()

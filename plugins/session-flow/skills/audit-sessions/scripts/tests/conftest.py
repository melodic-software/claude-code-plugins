"""Shared helpers for the audit-sessions suite.

The one place the suite puts `AS/scripts` and `plugins/session-flow/scripts` on `sys.path`, so
tests import `transcript_reader`, `redact` and `census` plainly; no test file inserts paths itself.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
PLUGIN_SCRIPTS = Path(__file__).resolve().parents[4] / "scripts"
FIXTURES = Path(__file__).resolve().parent / "fixtures"

for _path in (str(SCRIPTS), str(PLUGIN_SCRIPTS)):
    if _path not in sys.path:
        sys.path.insert(0, _path)


def run_cli(script: str, *args: str) -> subprocess.CompletedProcess[str]:
    """Run an audit-sessions script by subprocess, as a consumer would."""
    return subprocess.run(
        [sys.executable, str(SCRIPTS / script), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
    )


def envelope(result: subprocess.CompletedProcess[str]) -> dict:
    return json.loads(result.stdout)


@pytest.fixture
def data_dir(tmp_path: Path) -> Path:
    path = tmp_path / "data"
    path.mkdir()
    return path


@pytest.fixture
def copy_fixture(tmp_path: Path):
    """Copy a named fixture tree under `fixtures/` to `tmp_path` and return the copy."""

    def _copy(name: str) -> Path:
        dest = tmp_path / "projects" / name
        shutil.copytree(FIXTURES / name, dest)
        return dest

    return _copy

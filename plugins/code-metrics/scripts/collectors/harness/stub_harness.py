"""The PATH stubbing every collector suite one directory up shares.

Each adapter is driven at its own command line against an out-of-process tool
that no suite may assume is installed, so a suite writes a fake executable into
a temporary directory and prepends that directory to PATH (design T13; no
executable is committed). With no stub the PATH is replaced by a directory that
does not exist, so the adapter sees the tool as absent; the replacement keeps
the suite's own name in it so a stray PATH entry is traceable to the suite that
set it.

This module sits in its own directory because `skills/setup` enumerates
`scripts/collectors/*.py` as the adapter set: anything beside the adapters is
reported as one of them. The suites import it as `harness.stub_harness`, which
resolves through the collectors directory both runners already put on
`sys.path`.
"""

from __future__ import annotations

import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

COLLECTORS = Path(__file__).resolve().parents[1]
TOOL_OUTPUT = COLLECTORS.parent / "fixtures" / "tool-output"
REPO_ROOT = COLLECTORS.parents[3]
SOURCES = "plugins/code-metrics/scripts/fixtures/sources"


def version_gate(version_line: str) -> str:
    """The `--version` answer a stub opens with, before anything else it does."""
    return (
        'if [[ "${1:-}" == "--version" ]]; then '
        f"printf '%s\\n' \"{version_line}\"; exit 0; fi\n"
    )


def dash_version_gate(version_line: str) -> str:
    """The same answer for a tool that also understands `-version`."""
    return (
        'case "${1:-}" in -version | --version) '
        f"printf '%s\\n' \"{version_line}\"; exit 0 ;; esac\n"
    )


def write_stub(path: Path, body: str) -> None:
    """Write `body` as an executable bash stub at `path`."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def run_adapter(
    script: Path,
    slug: str,
    *args: str,
    path_prefix: Path | None = None,
    env_extra: dict[str, str] | None = None,
    cwd: Path | str | None = None,
    real_path: bool = False,
) -> subprocess.CompletedProcess:
    """`script` at its command line, from the repository root by default.

    `path_prefix` goes in front of the inherited PATH; without one the PATH
    becomes a directory named for `slug` that does not exist, unless
    `real_path` asks for the inherited PATH untouched.
    """
    env = dict(os.environ)
    if path_prefix is not None:
        env["PATH"] = f"{path_prefix}{os.pathsep}{env.get('PATH', '')}"
    elif not real_path:
        env["PATH"] = str(
            Path(tempfile.gettempdir()) / f"definitely-empty-path-for-{slug}-tests"
        )
    env.update(env_extra or {})
    return subprocess.run(
        [sys.executable, str(script), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=str(cwd if cwd is not None else REPO_ROOT),
        check=False,
    )

"""The subprocess harness every coverage-parser suite in this directory shares.

Each parser is driven at its own command line, prints one JSON document on
stdout, and is handed reports a fixture cannot carry by writing them into a
temporary directory first, so the three moves live here once.

pytest loads this file for the suites beside it and puts its directory on
`sys.path`, so a suite reaches the harness by importing it under this name,
whether pytest or the suite's own `unittest.main()` is driving.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

PARSERS = Path(__file__).resolve().parent
FIXTURES = PARSERS.parent / "fixtures" / "coverage"


def run_parser(
    script: Path, *args: str, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess:
    """`script` at its command line, inheriting the environment unless `env`."""
    return subprocess.run(
        [sys.executable, str(script), *args],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )


def parsed_output(script: Path, *args: str, env: dict[str, str] | None = None) -> dict:
    """The document `script` printed, with its stderr in the failure message."""
    result = run_parser(script, *args, env=env)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def write(tmp: str, name: str, body: str) -> str:
    """`body` as a file named `name` under `tmp`, at its path."""
    path = Path(tmp) / name
    path.write_text(body, encoding="utf-8")
    return str(path)

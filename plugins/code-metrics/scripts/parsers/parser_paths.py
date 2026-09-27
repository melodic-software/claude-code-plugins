"""The pieces every coverage parser in this directory shares.

Each parser reads one artifact format into the same mapping

    {file: {"lines": {line: hits}, "functions": [...] | None}}

and every one of them spells a report's file paths and its integer fields the
same way, so the two readers and the interpreter floor live here once.

Paths are returned as the artifact spells them, with backslashes folded to
forward slashes and a leading `./` removed. Nothing else is normalized here:
only the caller knows the repository root and the configured prefixes, so the
join finishes the job.

The parsers stay runnable as standalone subprocesses (`join.py`,
`audit-coverage.sh` and the suites each invoke them that way), which is why
this module sits beside them rather than in the collectors' directory.
"""

from __future__ import annotations

import sys
from typing import Any

MIN_PYTHON = (3, 9)


def require_python(script: str) -> None:
    """Exit 2 when the interpreter is below the parser set's floor."""
    if sys.version_info < MIN_PYTHON:
        print(
            f"{script} needs Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]} or later",
            file=sys.stderr,
        )
        sys.exit(2)


def norm(path: str) -> str:
    """Forward slashes, no surrounding whitespace, and no leading `./`."""
    path = path.strip().replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def to_int(text: Any) -> int | None:
    """The integer `text` spells, or None when it is absent or not one.

    A malformed field drops the one record that carries it rather than the
    whole report: producers of these formats disagree often enough that a
    strict read would report nothing at all.
    """
    if text is None:
        return None
    try:
        return int(str(text).strip())
    except ValueError:
        return None

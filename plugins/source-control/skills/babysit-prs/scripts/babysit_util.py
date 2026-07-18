#!/usr/bin/env python3
"""Shared low-level primitives for the babysit-prs engine and CLIs.

Deliberately small mixed-utility module: stdio configuration, JSON narrowing
helpers, timestamp parsing, the head-SHA pin floor, and the single subprocess
core every script funnels through. Splitting these tiny concerns into separate
modules would cost more coupling than it buys cohesion.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from collections.abc import Collection
from contextlib import suppress
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, cast

# Minimum accepted hex-prefix length for --expected-head-sha pins. Lives here --
# not in the state module -- so the guarded mutation CLIs can validate pins
# without importing any snapshot/state machinery.
MIN_HEAD_SHA_PREFIX_LENGTH = 12
DEFAULT_COMMAND_TIMEOUT_SECONDS = 60.0


def is_json_object(value: Any) -> bool:
    """True when a decoded JSON value is an object with string keys."""
    return isinstance(value, dict)


def is_json_array(value: Any) -> bool:
    """True when a decoded JSON value is an array."""
    return isinstance(value, list)


def json_object(value: Any) -> dict[str, Any]:
    """Return a shallow copy of a JSON object, or an empty object."""
    return dict(value) if is_json_object(value) else {}


def json_array(value: Any) -> list[Any]:
    """Return a shallow copy of a JSON array, or an empty array."""
    return list(value) if is_json_array(value) else []


def dig(value: Any, *keys: str) -> Any:
    """Walk nested dict keys, returning None if any level is absent or not a dict.

    Lets callers narrow untyped JSON without inline type-ignore suppressions.
    """
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = cast(dict[str, Any], value).get(key)
    return value


def configure_stdio() -> None:
    """Force UTF-8 text output so non-cp1252 characters survive the console.

    PR titles and bot-feedback previews carry arbitrary Unicode (`->`, em dash,
    box drawing). On Windows the interpreter defaults stdout/stderr to the ANSI
    code page (cp1252), so printing such text raises UnicodeEncodeError. Calling
    `reconfigure` at runtime overrides that inherited encoding without requiring
    the caller to set PEP 540 UTF-8 mode or PYTHONIOENCODING, and is the fix the
    CPython docs point to (https://docs.python.org/3/library/io.html#io.TextIOWrapper.reconfigure,
    https://peps.python.org/pep-0540/). `errors="replace"` keeps a truly
    un-encodable stream from crashing. Guarded for streams that lack
    `reconfigure` (an in-test StringIO, a redirected pipe, or `None` under
    pythonw) so it never masks an unrelated failure.
    """
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is None:
            continue
        with suppress(ValueError, OSError):
            reconfigure(encoding="utf-8", errors="replace")


def parse_timestamp(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def run_command(
    argv: list[str],
    *,
    allowed_executables: Collection[str],
    timeout_seconds: float = DEFAULT_COMMAND_TIMEOUT_SECONDS,
    check: bool = True,
    cwd: str | Path | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run one allowlisted executable and capture its output.

    The single subprocess seam for every babysit script: argv is never a shell
    command, the executable must be named in `allowed_executables` and resolve
    on PATH, and a timeout always raises. With `check` (the default) a nonzero
    exit raises with the captured stderr; callers that inspect the returncode
    themselves pass `check=False`.
    """
    if not argv:
        raise ValueError("argv must name an executable")
    name = argv[0]
    if name not in allowed_executables:
        raise ValueError(f"executable {name!r} is not in the caller's allowlist")
    executable = shutil.which(name)
    if executable is None:
        raise RuntimeError(f"{name} executable not found on PATH")
    try:
        proc = subprocess.run(
            [executable, *argv[1:]],
            check=False,
            text=True,
            capture_output=True,
            encoding="utf-8",
            timeout=timeout_seconds,
            cwd=str(cwd) if cwd is not None else None,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            f"{' '.join(argv)} timed out after {timeout_seconds:g}s"
        ) from exc
    if check and proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip()
        raise RuntimeError(f"{' '.join(argv)} failed: {detail}")
    return proc

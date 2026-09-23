#!/usr/bin/env python3
"""Shared low-level primitives for the babysit-prs engine and CLIs.

Deliberately small mixed-utility module: stdio configuration, JSON narrowing
helpers, timestamp parsing, comma-separated option parsing, the head-SHA pin
floor, the pull-request skill-evidence block parser, and the single subprocess
core every script funnels through. Splitting these tiny concerns into separate
modules would cost more coupling than it buys cohesion.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from collections.abc import Collection, Mapping
from contextlib import suppress
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, TypeGuard

# Minimum accepted hex-prefix length for --expected-head-sha pins. Lives here --
# not in the state module -- so the guarded mutation CLIs can validate pins
# without importing any snapshot/state machinery.
MIN_HEAD_SHA_PREFIX_LENGTH = 12
DEFAULT_COMMAND_TIMEOUT_SECONDS = 60.0

# A pull request carries the skills that ran for its head in one fenced block
# with this info string, one `<skill> <sha> <utc-timestamp>` row per skill.
# `plugins/source-control/scripts/skill-evidence.sh` renders it and
# `plugins/source-control/reference/config-resolution.md` owns the grammar.
SKILL_EVIDENCE_INFO_STRING = "skill-evidence"
_FENCE_RE = re.compile(r"^(?P<fence>`{3,}|~{3,})(?P<info>[^`~]*)$")
_SKILL_EVIDENCE_ROW_RE = re.compile(
    r"^(?P<skill>\S+)[ \t]+(?P<sha>[0-9a-fA-F]{40})[ \t]+(?P<timestamp>\S+)$"
)
# The body is markdown, where an HTML comment is invisible to a reader. A
# commented-out row is not evidence a human can see, so comments come out
# before the fences are read rather than being parsed and then filtered.
_HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)


def is_json_object(value: Any) -> TypeGuard[dict[Any, Any]]:
    """True when a decoded JSON value is an object.

    The guard narrows to `dict[Any, Any]`, which is exactly what the
    `isinstance` test establishes. JSON grammar does guarantee string keys, but
    this check never inspects them, so claiming `dict[str, Any]` would hand the
    type checker a promise the runtime test has not made. Callers index these
    dicts with string literals, which `dict[Any, Any]` already permits, so the
    narrower claim costs them nothing.
    """
    return isinstance(value, dict)


def is_json_array(value: Any) -> TypeGuard[list[Any]]:
    """True when a decoded JSON value is an array.

    Narrows to `list[Any]`: the check establishes the container and inspects no
    element, which is precisely what `Any` element type asserts.
    """
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
        if not is_json_object(value):
            return None
        value = value.get(key)
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


def parse_csv_set(raw: str | None) -> set[str]:
    """Split a comma-separated option value into its non-empty trimmed tokens."""
    if not raw:
        return set()
    return {part.strip() for part in raw.split(",") if part.strip()}


def parse_allowed_owners(raw: str | None) -> set[str]:
    """Casefolded owner allowlist parsed from a comma-separated option value.

    Owner comparison is case-insensitive everywhere the guarded CLIs test scope,
    so the allowlist is folded once here rather than at each membership test.
    """
    return {owner.casefold() for owner in parse_csv_set(raw)}


def split_owner(repo: str) -> str:
    """The owner half of an `owner/repo` pair."""
    return repo.split("/", 1)[0]


def parse_skill_evidence_block(body: Any) -> dict[str, Any]:
    """Read the skill-evidence block out of a pull-request body.

    Pure text: no network, no filesystem, no verdict. The caller decides what a
    row means; this only reports what the body claims.

    Returns `present` (a block with the info string exists), `parsed` (the
    block's content is entirely rows this grammar accepts), `rows` (the latest
    row per skill, sorted by skill name) and `blocks` (how many blocks carry the
    info string). Only the FIRST block is read, because a body may legitimately
    quote the shape in prose; a second one is reported through `blocks` so a
    caller can warn, never treated as fatal. An unparsable block stays
    `present` with `parsed` false and whatever rows did match, so a malformed
    body degrades to "cannot confirm" rather than to an exception.
    """
    text = (
        _HTML_COMMENT_RE.sub("", body.replace("\r\n", "\n"))
        if isinstance(body, str)
        else ""
    )
    blocks = 0
    fence: str | None = None
    capturing = False
    captured: list[str] = []
    for line in text.split("\n"):
        match = _FENCE_RE.match(line.strip())
        if fence is None:
            if match and match["info"].strip() == SKILL_EVIDENCE_INFO_STRING:
                blocks += 1
                fence = match["fence"]
                capturing = blocks == 1
            continue
        closes = (
            match is not None
            and match["fence"][0] == fence[0]
            and len(match["fence"]) >= len(fence)
            and not match["info"].strip()
        )
        if closes:
            fence = None
            capturing = False
            continue
        if capturing:
            captured.append(line)
    if not blocks:
        return {"present": False, "parsed": False, "rows": [], "blocks": 0}
    latest: dict[str, dict[str, str]] = {}
    malformed = False
    for line in captured:
        content = line.strip()
        if not content:
            continue
        row = _SKILL_EVIDENCE_ROW_RE.match(content)
        if row is None:
            malformed = True
            continue
        # Last row per skill wins: the renderer appends, so a re-run of the
        # same skill leaves both rows behind and the later one is the claim.
        latest[row["skill"]] = {
            "skill": row["skill"],
            "sha": row["sha"].lower(),
            "timestamp": row["timestamp"],
        }
    rows = [latest[skill] for skill in sorted(latest)]
    return {
        "present": True,
        "parsed": bool(rows) and not malformed,
        "rows": rows,
        "blocks": blocks,
    }


def run_command(
    argv: list[str],
    *,
    allowed_executables: Collection[str],
    timeout_seconds: float = DEFAULT_COMMAND_TIMEOUT_SECONDS,
    check: bool = True,
    cwd: str | Path | None = None,
    env_overrides: Mapping[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run one allowlisted executable and capture its output.

    The single subprocess seam for every babysit script: argv is never a shell
    command, the executable must be named in `allowed_executables` and resolve
    on PATH, and a timeout always raises. With `check` (the default) a nonzero
    exit raises with the captured stderr; callers that inspect the returncode
    themselves pass `check=False`.

    `env_overrides` layers onto the inherited environment for this call only --
    the seam a caller uses to pin a child's locale when it must read a decision
    out of that child's human-readable output, which is otherwise translated.
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
            env=({**os.environ, **env_overrides} if env_overrides else None),
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            f"{' '.join(argv)} timed out after {timeout_seconds:g}s"
        ) from exc
    if check and proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip()
        raise RuntimeError(f"{' '.join(argv)} failed: {detail}")
    return proc

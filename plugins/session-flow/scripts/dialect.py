# -*- coding: utf-8 -*-
"""American spelling for the prose a session-flow tool writes on the model's behalf.

`americanize(text, cwd)` runs `typos --locale en-us` over the text and applies each finding
that has exactly one correction, returning the new text and the `(typo, correction)` pairs it
applied. Text a file quotes rather than authors is masked first and never changed: fenced code
blocks, inline code spans, `>` blockquote lines, double-quoted spans, tokens shaped like a path,
URL, file name, flag or identifier (snake_case, camelCase), and any span the caller's `keep` pattern matches. With no `typos` on PATH the
text comes back unchanged and nothing is printed; a `typos` that fails or times out leaves the text unchanged and writes one stderr line.
Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

TYPOS_TIMEOUT_SECONDS = 10
FENCE_RE = re.compile(r"^\s*(```|~~~)")
BLOCKQUOTE_RE = re.compile(r"^\s*>")
QUOTED_RE = re.compile(
    r"(?P<ticks>`+)[^\n]*?(?P=ticks)|\"[^\"\n]*\"|“[^”\n]*”|[^\s\"“”`]*[/\\][^\s\"“”`]*|\S+\.\w{1,6}\b"
    r"|\w*_\w*|\w*[a-z][A-Z]\w*|(?<!\S)-\S+"
)


def _blank(match: re.Match[str]) -> str:
    """Spaces with the matched text's UTF-8 byte length per line, so typos' line numbers and byte
    offsets still fit."""
    return "\n".join(" " * len(part.encode("utf-8")) for part in match.group(0).split("\n"))


def _masked_lines(lines: list[str]) -> list[str]:
    masked, fenced = [], False
    for line in lines:
        fence = bool(FENCE_RE.match(line))
        if fenced or fence or BLOCKQUOTE_RE.match(line):
            masked.append(" " * len(line.encode("utf-8")))
        else:
            masked.append(QUOTED_RE.sub(_blank, line))
        if fence:
            fenced = not fenced
    return masked


def _findings(masked: str, cwd: Path | None) -> list[dict]:
    typos = shutil.which("typos")
    if typos is None:
        return []
    try:
        result = subprocess.run(
            [typos, "--locale", "en-us", "--format", "json", "-"],
            input=masked.encode("utf-8"),
            capture_output=True,
            cwd=cwd if cwd is not None and cwd.is_dir() else None,
            timeout=TYPOS_TIMEOUT_SECONDS,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        sys.stderr.write(f"dialect: typos did not run, text left as written: {type(exc).__name__}: {exc}\n")
        return []
    if result.returncode not in (0, 2):
        sys.stderr.write(
            f"dialect: typos exited {result.returncode}, text left as written: "
            f"{result.stderr.decode('utf-8', 'replace').strip()[:300]}\n"
        )
        return []
    found = []
    for raw in result.stdout.decode("utf-8", "replace").splitlines():
        try:
            item = json.loads(raw)
        except ValueError:
            continue
        if item.get("type") == "typo" and len(item.get("corrections") or []) == 1:
            found.append(item)
    return found


def americanize(
    text: str, cwd: Path | None = None, keep: re.Pattern[str] | None = None
) -> tuple[str, list[tuple[str, str]]]:
    """`text` with each single-correction typos finding applied outside quoted spans and outside
    the spans `keep` matches."""
    if not text.strip():
        return text, []
    lines = text.split("\n")
    unkept = keep.sub(_blank, text).split("\n") if keep else lines
    findings = _findings("\n".join(_masked_lines(unkept)), cwd)
    if not findings:
        return text, []
    encoded = [line.encode("utf-8") for line in lines]
    applied: list[tuple[str, str]] = []
    for item in sorted(findings, key=lambda x: (x["line_num"], x["byte_offset"]), reverse=True):
        index, offset = item["line_num"] - 1, item["byte_offset"]
        typo, fix = item["typo"], item["corrections"][0]
        word = typo.encode("utf-8")
        if not 0 <= index < len(encoded) or encoded[index][offset : offset + len(word)] != word:
            continue
        encoded[index] = encoded[index][:offset] + fix.encode("utf-8") + encoded[index][offset + len(word) :]
        applied.append((typo, fix))
    applied.reverse()
    return "\n".join(line.decode("utf-8") for line in encoded), applied

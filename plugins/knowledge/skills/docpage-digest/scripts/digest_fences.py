"""Shared fence and section parsing for the docpage-digest standing gates.

Stdlib only. Python 3.9+. Both gates stay standalone-runnable: they insert
this directory on sys.path and import from here. Parsing is exact — no
``.strip()`` on fence payloads — because a per-line strip is how indented-fence
corruption and a load-bearing trailing space earned a clean quote-gate result.
"""

from __future__ import annotations

import re
import sys
from typing import Iterator, List, NamedTuple, NoReturn, Optional, Tuple

MIN_PYTHON = (3, 9)

CLAIM_LABEL = re.compile(r"^\*\*C(\d+)\.\*\*(.*)$")
ATX_H2 = re.compile(r"^##[ \t]+(.+?)\s*$")
NONE_MARKERS = frozenset({
    "none",
    "n/a",
    "(none)",
    "no prompt snippets",
    "no snippets",
    "none.",
})


class Failures:
    """Named check failures, echoed to stderr as they land under ``prog``."""

    def __init__(self, prog: str):
        self.prog = prog
        self.items: List[str] = []

    def add(self, message: str) -> None:
        self.items.append(message)
        sys.stderr.write(f"{self.prog}: FAIL: {message}\n")


class Fence(NamedTuple):
    start_line: int  # 1-based, opener
    indented: bool
    payload: str  # exact body; no strip; no closer-line newline


class Claim(NamedTuple):
    number: int
    label_line: int
    rest: str
    fence: Optional[Fence]
    unfenced_blockquote: bool
    unfenced_inline_code: bool


def fail(prog: str, code: int, message: str) -> NoReturn:
    sys.stderr.write(f"{prog}: ERROR: {message}\n")
    raise SystemExit(code)


def read_text(path: str, prog: str, what: str) -> str:
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError as exc:
        fail(prog, 2, f"cannot read {what} {path!r}: {exc}")
    if not raw:
        fail(prog, 2, f"{what} {path!r} is empty (0 bytes).")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        fail(prog, 2, f"{what} {path!r} is not UTF-8: {exc}")


def split_lines(text: str) -> List[str]:
    if text.endswith("\n"):
        return text[:-1].split("\n")
    return text.split("\n")


def iter_h2_sections(text: str) -> Iterator[Tuple[str, str, int]]:
    """Yield (heading-rest, section-body, heading-line-number) for each ``## ``.

    H2-looking lines inside a fence are payload, not section boundaries —
    a verbatim quote of a docs heading must not truncate Key claims.
    """
    lines = split_lines(text)
    starts: List[Tuple[int, str]] = []
    in_fence = False
    for idx, line in enumerate(lines):
        is_open, _indented = _is_fence_opener(line)
        if in_fence:
            if _is_fence_closer(line):
                in_fence = False
            continue
        if is_open:
            in_fence = True
            continue
        match = ATX_H2.match(line)
        if match:
            starts.append((idx, match.group(1)))
    for i, (idx, title) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(lines)
        body = "\n".join(lines[idx + 1:end])
        yield title, body, idx + 1


def find_section(text: str, prefix: str) -> Optional[Tuple[str, str, int]]:
    """First H2 whose title starts with ``prefix`` (case-insensitive)."""
    wanted = prefix.lower()
    for title, body, line in iter_h2_sections(text):
        if title.lower().startswith(wanted):
            return title, body, line
    return None


def _is_fence_opener(line: str) -> Tuple[bool, bool]:
    """Return (is_opener, indented)."""
    stripped = line.lstrip(" \t")
    if stripped.startswith("```"):
        return True, (len(line) != len(stripped))
    return False, False


def _is_fence_closer(line: str) -> bool:
    stripped = line.lstrip(" \t")
    return stripped.startswith("```") and stripped.strip("` \t") == ""


def extract_fences(text: str, *, start_line: int = 1) -> List[Fence]:
    """Column-aware fence walk. An indented opener is recorded, not repaired."""
    lines = split_lines(text)
    fences: List[Fence] = []
    i = 0
    while i < len(lines):
        is_open, indented = _is_fence_opener(lines[i])
        if not is_open:
            i += 1
            continue
        opener_line = start_line + i
        i += 1
        body_lines: List[str] = []
        closed = False
        while i < len(lines):
            if _is_fence_closer(lines[i]):
                closed = True
                break
            body_lines.append(lines[i])
            i += 1
        if not closed:
            raise ValueError(f"unclosed fence opening at line {opener_line}")
        fences.append(Fence(opener_line, indented, "\n".join(body_lines)))
        i += 1
    return fences


def parse_claims(section_body: str, *, start_line: int = 1) -> List[Claim]:
    """Parse ``**CN.**`` labels and the fence that must follow each one."""
    lines = split_lines(section_body)
    label_idxs: List[int] = []
    for i, line in enumerate(lines):
        if CLAIM_LABEL.match(line):
            label_idxs.append(i)
    claims: List[Claim] = []
    for n, idx in enumerate(label_idxs):
        match = CLAIM_LABEL.match(lines[idx])
        assert match is not None
        end = label_idxs[n + 1] if n + 1 < len(label_idxs) else len(lines)
        block = "\n".join(lines[idx + 1:end])
        block_start = start_line + idx + 1
        try:
            fences = extract_fences(block, start_line=block_start)
        except ValueError:
            fences = []
            unclosed = True
        else:
            unclosed = False
        fence = fences[0] if fences else None
        prose = block if not fences else block.split("```", 1)[0]
        # Forbidden carriers are defects even when a later fence is valid —
        # a leftover blockquote/inline quote is still hook-corruptible.
        has_bq = bool(re.search(r"(?m)^>", prose))
        has_inline = bool(re.search(r"(?<!`)`[^`\n]+`(?!`)", prose))
        if unclosed:
            fence = None
        claims.append(Claim(
            number=int(match.group(1)),
            label_line=start_line + idx,
            rest=match.group(2),
            fence=fence,
            unfenced_blockquote=has_bq,
            unfenced_inline_code=has_inline,
        ))
    return claims


def is_none_section(body: str) -> bool:
    """True only for an explicit none-marker. Blank is not an assertion."""
    return body.strip().lower() in NONE_MARKERS


def payload_in_source(payload: str, source: str) -> bool:
    """Exact contiguous match. No strip, no whitespace forgiveness.

    A payload that is a prefix of a source line and leaves only trailing
    spaces/tabs on that line is a *lost trailing space*, not a match —
    ``"keep me" in "keep me \\n"`` is True, and that is the hook defect.
    Mid-line substrings whose remainder is real text still match.
    An empty payload is never a match (``str.find('')`` is always 0).
    """
    if not payload:
        return False
    start = 0
    while True:
        idx = source.find(payload, start)
        if idx < 0:
            return False
        rest_of_line = source[idx + len(payload):].split("\n", 1)[0]
        lost_trailing = (
            bool(rest_of_line)
            and rest_of_line.strip(" \t") == ""
            and not (payload.endswith(" ") or payload.endswith("\t"))
        )
        if not lost_trailing:
            return True
        start = idx + 1

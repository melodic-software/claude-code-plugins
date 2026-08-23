#!/usr/bin/env python3
"""Mark I29 restatement candidates in skill-like markdown files.

I29-a — a body H2 section whose content is wholly recoverable from the file's
        own `description` (always in the model's context).
I29-b — a body H2 section whose content is wholly recoverable from a sibling
        H2 section of the same file.

"Wholly recoverable" is the load-bearing predicate. A section that opens with
an echo of the description and then adds a proper noun, path, threshold,
version, or any other content token the source does not carry is partial
overlap, and partial overlap is not a finding. Flagging the echo alone would
gut load-bearing Purpose sections. The remediation is always "cut the body
restatement", never "trim the description".

Body-scoped by construction: rows point at the section heading, which sits
after frontmatter. Frontmatter is never a finding target.

Advisory: prints `file:line:check-id` rows and always exits 0 (exit 2 only
when the script cannot run). Does not fail a run on candidates.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

CHECK_DESC = "I29-a"
CHECK_SIBLING = "I29-b"

# Footer / index headings are sources for sibling comparison but are never
# themselves a restatement finding: audit-noise protects them, and a
# Cross-references section that happens to be shorter than a NOT-do section
# is the source, not the defect.
NEVER_FLAG_HEADINGS = frozenset(
    {
        "sources",
        "history",
        "external authority",
        "recheck triggers",
        "cross-references",
        "gotchas",
        "variables",
        "arguments",
        "flags",
        "usage",
    }
)

STOPWORDS = frozenset(
    """
    a an the and or of to for in on at is it this that with as by from be are
    was were not do does did its own than then also just only also into over
    after before about into than so if when where which who whom whose what
    their there here such any all each every both few more most other some
    no nor but yet can may must should would could will shall been being
    has have had having use used using via per
    """.split()
)

WORD_RE = re.compile(r"[a-z0-9]+(?:'[a-z]+)?")
HEADING_RE = re.compile(r"^(#{2,6})\s+(.+?)\s*$")
FENCE_RE = re.compile(r"^(\s*)(```|~~~)")
BULLET_RE = re.compile(r"^(\s*)[-*+]\s+")
SENTENCE_RE = re.compile(r"(?<=[.!?])\s+(?=[A-Z*\"'`])")


@dataclass
class Section:
    heading: str
    heading_norm: str
    line: int  # 1-based heading line
    body: str
    units: list[tuple[int, str]] = field(default_factory=list)


def strip_md(text: str) -> str:
    text = re.sub(r"`[^`]+`", " ", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"[*_~>#]+", " ", text)
    text = text.replace("\\", " ")
    return text


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", strip_md(text).lower()).strip()


def content_tokens(text: str) -> set[str]:
    return {m.group(0) for m in WORD_RE.finditer(normalize(text)) if m.group(0) not in STOPWORDS}


def extract_frontmatter(lines: list[str]) -> tuple[int, list[str]]:
    """Return (body_start_index, frontmatter_lines). body_start is 0-based."""
    if not lines or not re.match(r"^---\s*$", lines[0]):
        return 0, []
    fm: list[str] = []
    for i in range(1, len(lines)):
        if re.match(r"^---\s*$", lines[i]):
            return i + 1, fm
        fm.append(lines[i])
    return len(lines), fm  # unclosed: fail-safe, no body


def frontmatter_field(fm: list[str], key: str) -> str:
    prefix = f"{key}:"
    i = 0
    while i < len(fm):
        line = fm[i]
        if not line.startswith(prefix):
            i += 1
            continue
        raw = line[len(prefix) :].strip()
        if re.match(r"^[|>]([0-9][+-]?|[+-][0-9]?)?\s*(#.*)?$", raw):
            fold = raw.startswith(">")
            parts: list[str] = []
            i += 1
            while i < len(fm) and (fm[i].startswith(" ") or fm[i].startswith("\t") or fm[i].strip() == ""):
                if fm[i].strip() == "":
                    if parts:
                        parts.append("")
                    i += 1
                    continue
                parts.append(fm[i].lstrip())
                i += 1
            joiner = " " if fold else "\n"
            return joiner.join(parts).strip()
        if (raw.startswith('"') and raw.endswith('"') and len(raw) >= 2) or (
            raw.startswith("'") and raw.endswith("'") and len(raw) >= 2
        ):
            return raw[1:-1]
        return raw
    return ""


def split_units(body_lines: list[tuple[int, str]]) -> list[tuple[int, str]]:
    """(line, unit-text) for bullets and sentences, skipping fences."""
    units: list[tuple[int, str]] = []
    fence: str | None = None
    buf: list[tuple[int, str]] = []

    def flush() -> None:
        if not buf:
            return
        text = " ".join(t for _, t in buf).strip()
        if not text:
            buf.clear()
            return
        start = buf[0][0]
        for piece in SENTENCE_RE.split(text):
            piece = piece.strip()
            if piece:
                units.append((start, piece))
        buf.clear()

    for lineno, raw in body_lines:
        if FENCE_RE.match(raw):
            flush()
            marker = "```" if "```" in raw else "~~~"
            if fence is None:
                fence = marker
            elif fence == marker:
                fence = None
            continue
        if fence is not None:
            continue
        if not raw.strip():
            flush()
            continue
        if BULLET_RE.match(raw):
            flush()
            units.append((lineno, BULLET_RE.sub("", raw).strip()))
            continue
        if HEADING_RE.match(raw):
            flush()
            continue
        buf.append((lineno, raw.rstrip()))
    flush()
    return units


def parse_sections(lines: list[str], body_start: int) -> list[Section]:
    sections: list[Section] = []
    current: Section | None = None
    body_acc: list[tuple[int, str]] = []

    def close() -> None:
        nonlocal current, body_acc
        if current is None:
            return
        current.body = "\n".join(t for _, t in body_acc)
        current.units = split_units(body_acc)
        sections.append(current)
        current = None
        body_acc = []

    for idx in range(body_start, len(lines)):
        raw = lines[idx].rstrip("\n")
        m = HEADING_RE.match(raw)
        if m and len(m.group(1)) == 2:
            close()
            heading = m.group(2).strip()
            current = Section(
                heading=heading,
                heading_norm=normalize(heading),
                line=idx + 1,
                body="",
            )
            continue
        if current is not None:
            body_acc.append((idx + 1, raw))
    close()
    return sections


def recoverable(unit: str, source: str) -> bool:
    """True iff `unit` adds no content token the source does not already carry."""
    nunit = normalize(unit)
    nsrc = normalize(source)
    if len(nunit) < 24:
        return False
    if nunit and nunit in nsrc:
        return True
    utoks = content_tokens(unit)
    stoks = content_tokens(source)
    if len(utoks) < 5:
        return False
    unique = utoks - stoks
    if not unique:
        return True
    # Near-verbatim: one leftover token is still a restatement when almost
    # every content token is already in the source (the leftover is usually
    # a synonym or a heading-word like "purpose").
    overlap = utoks & stoks
    if len(utoks) >= 8 and len(unique) == 1 and len(overlap) / len(utoks) >= 0.85:
        return True
    return False


def section_wholly_recoverable(section: Section, source: str) -> bool:
    if not section.units:
        # A heading-only or one-sentence section with no split units: judge
        # the body as a single unit.
        body = section.body.strip()
        return bool(body) and recoverable(body, source)
    return all(recoverable(text, source) for _, text in section.units)


def scan_file(path: Path) -> list[str]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return []
    lines = text.splitlines()
    body_start, fm = extract_frontmatter(lines)
    description = frontmatter_field(fm, "description")
    # Drop the Use-when / Not-for tail so a section that restates the
    # capability sentence is not rescued by trigger-phrase tokens, and so a
    # section that only restates the trigger list is not a finding (those
    # phrases are the listing, not body ceremony).
    desc_capability = re.split(r"(?i)\buse when\b|\bnot for\b", description, maxsplit=1)[0]
    sections = parse_sections(lines, body_start)
    rows: list[str] = []
    for section in sections:
        if section.heading_norm in NEVER_FLAG_HEADINGS:
            continue
        if not section.body.strip():
            continue
        # Locate the first body unit (or the heading if the body did not
        # split). The fixer should see the restating prose, not only the
        # heading, and emit-findings' quoted-trigger fence reads this line.
        loc = section.units[0][0] if section.units else section.line
        if desc_capability and section_wholly_recoverable(section, desc_capability):
            rows.append(f"{path}:{loc}:{CHECK_DESC}")
            continue
        for other in sections:
            if other is section:
                continue
            if not other.body.strip():
                continue
            if section_wholly_recoverable(section, other.body):
                rows.append(f"{path}:{loc}:{CHECK_SIBLING}")
                break
    return rows


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Mark I29 description-restatement and sibling-section-restatement candidates."
    )
    parser.add_argument("files", nargs="*", help="markdown files to scan")
    parser.add_argument("--count", action="store_true", help="print the integer candidate count only")
    parser.add_argument(
        "--body-only",
        action="store_true",
        help="accepted for flag-parity with instruction-scan.sh; I29 is body-scoped by construction",
    )
    args = parser.parse_args(argv)
    if not args.files:
        if args.count:
            print(0)
        return 0
    rows: list[str] = []
    for raw in args.files:
        p = Path(raw)
        if not p.is_file():
            continue
        rows.extend(scan_file(p))
    if args.count:
        print(len(rows))
        return 0
    for row in rows:
        print(row)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

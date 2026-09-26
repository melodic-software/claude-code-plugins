#!/usr/bin/env python3
"""Deterministic gate for source applicability in a /discovery:research slice.

Reads the YAML front matter of <slice>/RESEARCH.md and of every
<slice>/RESEARCH-*.md sidecar (no recursion into sub-slices) and checks that
each claim's sources are graded for the version the claim is about: a source
written for an older version never passes as current evidence for a newer one.

Rules (each violation on stderr as <file>: claim <n>[: source <m>]: <reason>):
  R1 every claim has a parseable applies_to.
  R2 every source has published: YYYY, YYYY-MM or YYYY-MM-DD (a real date, not
     after today) or the literal undated.
  R3 every source has a parseable applies_to.
  R4 every source has standing: current or historical.
  R5 every source has role: primary or corroborator; each claim has exactly
     one primary.
  R6 the stored standing matches the standing this script derives.
  R7 each claim's primary is current (stored and derived) and dated.

Exit 0 = every rule holds (status=pass)
Exit 1 = at least one violation (status=fail); includes an index evidence_use
         that differs from --expect-evidence-use
Exit 2 = ungradeable, FAIL CLOSED: missing slice dir, no RESEARCH.md, no
         sidecar, a sidecar with no or unterminated front matter, a claims item
         that cannot be parsed, an evidence_use outside internal|publish (index
         or flag), an unreadable or non-UTF-8 file, or a usage error
         (status=ungradeable)

Usage:
  python3 check-source-applicability.py <slice-dir> [--expect-evidence-use internal|publish]
  python3 check-source-applicability.py --help
"""

from __future__ import annotations

import datetime
import re
import sys
from pathlib import Path

USAGE = (
    __doc__
    + """
applies_to grammar (claims and sources): version-independent, or
<product> <range> where <range> is <v>, <v>-<v> or <v>+ and <v> is dotted
integers. A shorter version is a prefix: 2.1 means every 2.1.x.

Derived standing is current iff both legs hold, else historical:
  coverage: the claim is version-independent, or the source names the same
            product (case-insensitive) and its range contains the claim's.
  date:     published is a date, or the source is an undated corroborator on a
            version-independent claim and the effective mode is not publish.
The effective mode is publish when the index or --expect-evidence-use says so.

Output (stdout, one line):
  status=pass evidence_use=<mode> claims=<n> sources=<n> historical=<n>
  status=fail violations=<n> evidence_use=<mode> claims=<n> sources=<n> historical=<n>
  status=ungradeable
"""
)

MODES = ("internal", "publish")
VERSION_INDEPENDENT = "version-independent"
APPLIES_TO = re.compile(r"^(.+?)\s+(\d+(?:\.\d+)*)(?:\s*-\s*(\d+(?:\.\d+)*)|(\+))?$")
DATE = re.compile(r"^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$")
KEY = re.compile(r"^([A-Za-z_][\w-]*)\s*:(?:\s+(.*)|\s*)$")
DASH = re.compile(r"^-(?:\s+(.*))?$")
INF = float("inf")


class Ungradeable(Exception):
    pass


def scalar(raw: str | None) -> str | None:
    """Unquote a YAML scalar; drop a trailing comment on a plain one."""
    if raw is None:
        return None
    text = raw.strip()
    if text[:1] in ("'", '"'):
        quote = text[0]
        out: list[str] = []
        i = 1
        while i < len(text):
            ch = text[i]
            if quote == '"' and ch == "\\" and i + 1 < len(text):
                out.append(text[i + 1])
                i += 2
                continue
            if ch == quote:
                if quote == "'" and text[i + 1 : i + 2] == "'":
                    out.append("'")
                    i += 2
                    continue
                return "".join(out)
            out.append(ch)
            i += 1
        return text
    text = re.split(r"\s#", text, maxsplit=1)[0].strip()
    return text or None


def read_text(path: Path) -> str:
    try:
        text = path.read_bytes().decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise Ungradeable(f"{path}: unreadable: {exc}") from exc
    return text.removeprefix("\ufeff")


def front_matter(path: Path, required: bool) -> list[str] | None:
    lines = read_text(path).splitlines()
    if not lines or lines[0].rstrip() != "---":
        if required:
            raise Ungradeable(f"{path}: no front matter")
        return None
    for end in range(1, len(lines)):
        if lines[end].rstrip() == "---":
            return [line.rstrip() for line in lines[1:end]]
    raise Ungradeable(f"{path}: unterminated front matter")


def indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def top_level(lines: list[str], key: str) -> tuple[int, str | None] | None:
    for i, line in enumerate(lines):
        if indent(line) == 0:
            m = KEY.match(line)
            if m and m.group(1) == key:
                return i, m.group(2)
    return None


def parse_claims(path: Path, lines: list[str]) -> list[dict]:
    found = top_level(lines, "claims")
    if found is None:
        return []
    start, inline = found
    value = scalar(inline)
    if value == "[]":
        return []
    if value is not None:
        raise Ungradeable(f"{path}: claims: expected a block list, got {value}")

    claims: list[dict] = []
    claim: dict | None = None
    source: dict | None = None
    claim_dash = claim_key = source_dash = source_key = -1
    in_sources = False
    for n, line in enumerate(lines[start + 1 :], start=start + 2):
        body = line.strip()
        if not body or body.startswith("#"):
            continue
        ind = indent(line)
        dash = DASH.match(body)
        if ind == 0 and not dash:
            break
        where = f"{path}: front matter line {n}"
        if dash:
            rest = dash.group(1) or ""
            key_col = len(line) - len(rest)
            item = KEY.match(rest)
            if claim is None or ind <= claim_dash:
                if claim is not None and ind != claim_dash:
                    raise Ungradeable(f"{where}: claims item at an unexpected indent")
                if not item or item.group(1) != "claim":
                    raise Ungradeable(
                        f"{where}: claims item does not start with claim:"
                    )
                claim = {"claim": scalar(item.group(2)), "sources": []}
                claims.append(claim)
                claim_dash, claim_key = ind, key_col
                source, in_sources, source_dash = None, False, -1
                continue
            if in_sources and (source is None or ind <= source_dash):
                if source is not None and ind != source_dash:
                    raise Ungradeable(f"{where}: sources item at an unexpected indent")
                if not item or item.group(1) != "url":
                    raise Ungradeable(f"{where}: sources item does not start with url:")
                source = {"url": scalar(item.group(2))}
                claim["sources"].append(source)
                source_dash, source_key = ind, key_col
            continue
        if claim is None:
            raise Ungradeable(f"{where}: content before the first claims item")
        item = KEY.match(body)
        if source is not None and ind > source_dash:
            if ind == source_key and item:
                source.setdefault(item.group(1), scalar(item.group(2)))
            elif ind < source_key:
                raise Ungradeable(f"{where}: source key at an unexpected indent")
            continue
        if ind > claim_key:
            continue
        if ind < claim_key or not item:
            raise Ungradeable(f"{where}: claim key at an unexpected indent")
        key = item.group(1)
        source = None
        in_sources = key == "sources"
        if in_sources:
            source_dash = -1
            if scalar(item.group(2)) not in (None, "[]"):
                raise Ungradeable(f"{where}: sources: expected a block list")
        else:
            claim.setdefault(key, scalar(item.group(2)))
    return claims


def version(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in text.split("."))


def pad(v: tuple[int, ...], width: int, fill: float) -> tuple[float, ...]:
    return tuple(v) + (fill,) * (width - len(v))


def applies_to(value: str | None) -> tuple | None:
    """None when unparseable, "vi" for version-independent, else a range."""
    if value is None:
        return None
    value = value.strip()
    if value == VERSION_INDEPENDENT:
        return ("vi",)
    m = APPLIES_TO.match(value)
    if not m:
        return None
    product = " ".join(m.group(1).split()).casefold()
    low = version(m.group(2))
    high = version(m.group(3)) if m.group(3) else None if m.group(4) else low
    if high is not None:
        width = max(len(low), len(high)) + 1
        if pad(low, width, 0) > pad(high, width, INF):
            return None
    return ("range", product, low, high)


def covers(src: tuple, claim: tuple) -> bool:
    if claim[0] == "vi":
        return True
    if src[0] == "vi" or src[1] != claim[1]:
        return False
    parts = [v for v in (src[2], src[3], claim[2], claim[3]) if v is not None]
    width = max(len(v) for v in parts) + 1

    def high(v: tuple[int, ...] | None) -> tuple[float, ...]:
        return (INF,) * width if v is None else pad(v, width, INF)

    return pad(src[2], width, 0) <= pad(claim[2], width, 0) and high(claim[3]) <= high(
        src[3]
    )


def published(value: str | None, today: datetime.date) -> str | None:
    """'dated', 'undated', or None when missing, invalid or in the future."""
    if value == "undated":
        return "undated"
    m = DATE.match(value or "")
    if not m:
        return None
    year, month, day = (int(g) if g else None for g in m.groups())
    try:
        first = datetime.date(year, month or 1, day or 1)
    except ValueError:
        return None
    return "dated" if first <= today else None


def mode_value(raw: str | None, where: str) -> str:
    if raw not in MODES:
        raise Ungradeable(
            f"{where}: evidence_use must be internal or publish, got {raw}"
        )
    return raw


def grade(slice_dir: Path, expected: str | None) -> tuple[int, str]:
    if not slice_dir.is_dir():
        raise Ungradeable(f"slice directory not found: {slice_dir}")
    index = slice_dir / "RESEARCH.md"
    if not index.is_file():
        raise Ungradeable(f"no index: {index}")
    sidecars = sorted(p for p in slice_dir.glob("RESEARCH-*.md") if p.is_file())
    if not sidecars:
        raise Ungradeable(f"no RESEARCH-*.md sidecar in {slice_dir}")

    violations: list[str] = []
    index_lines = front_matter(index, required=False) or []
    found = top_level(index_lines, "evidence_use")
    recorded = "internal" if found is None else mode_value(scalar(found[1]), str(index))
    if expected is not None and expected != recorded:
        violations.append(
            f"{index}: evidence_use: index records {recorded}, caller expects {expected}"
        )
    mode = "publish" if "publish" in (recorded, expected) else "internal"

    today = datetime.date.today()
    n_claims = n_sources = n_historical = 0
    for sidecar in sidecars:
        claims = parse_claims(sidecar, front_matter(sidecar, required=True))
        for c_no, claim in enumerate(claims, start=1):
            n_claims += 1
            here = f"{sidecar}: claim {c_no}"
            claim_at = applies_to(claim.get("applies_to"))
            if claim_at is None:
                violations.append(
                    f"{here}: applies_to missing or unparseable: {claim.get('applies_to')}"
                )
            roles = [s.get("role") for s in claim["sources"]]
            if roles.count("primary") != 1:
                violations.append(
                    f"{here}: expected exactly one primary source, found {roles.count('primary')}"
                )
            for s_no, src in enumerate(claim["sources"], start=1):
                n_sources += 1
                at = f"{here}: source {s_no}"
                role, stored = src.get("role"), src.get("standing")
                date = published(src.get("published"), today)
                src_at = applies_to(src.get("applies_to"))
                if date is None:
                    violations.append(
                        f"{at}: published missing, invalid or in the future: {src.get('published')}"
                    )
                if src_at is None:
                    violations.append(
                        f"{at}: applies_to missing or unparseable: {src.get('applies_to')}"
                    )
                if stored not in ("current", "historical"):
                    violations.append(
                        f"{at}: standing must be current or historical: {stored}"
                    )
                if role not in ("primary", "corroborator"):
                    violations.append(
                        f"{at}: role must be primary or corroborator: {role}"
                    )

                derived = None
                if claim_at is not None and src_at is not None and date is not None:
                    dated_ok = date == "dated" or (
                        claim_at[0] == "vi"
                        and role == "corroborator"
                        and mode != "publish"
                    )
                    current = covers(src_at, claim_at) and dated_ok
                    derived = "current" if current else "historical"
                    if stored in ("current", "historical") and stored != derived:
                        violations.append(
                            f"{at}: standing is {stored} but derives {derived} "
                            f"(source {src.get('applies_to')}, published {src.get('published')}, "
                            f"claim {claim.get('applies_to')}, evidence_use {mode})"
                        )
                if (derived or stored) == "historical":
                    n_historical += 1
                if role == "primary":
                    if date != "dated":
                        violations.append(f"{at}: primary source must be dated")
                    if "historical" in (stored, derived):
                        violations.append(f"{at}: primary source must be current")

    counts = f"evidence_use={mode} claims={n_claims} sources={n_sources} historical={n_historical}"
    for line in violations:
        print(line, file=sys.stderr)
    if violations:
        return 1, f"status=fail violations={len(violations)} {counts}"
    return 0, f"status=pass {counts}"


def main(argv: list[str]) -> int:
    slice_arg: str | None = None
    expected: str | None = None
    args = argv[1:]
    try:
        i = 0
        while i < len(args):
            arg = args[i]
            if arg in ("--help", "-h"):
                print(USAGE, end="")
                return 0
            if arg == "--expect-evidence-use":
                if i + 1 >= len(args):
                    raise Ungradeable("--expect-evidence-use needs a value")
                expected = mode_value(args[i + 1], "--expect-evidence-use")
                i += 2
                continue
            if arg.startswith("-"):
                raise Ungradeable(f"unknown argument: {arg}")
            if slice_arg is not None:
                raise Ungradeable(
                    f"expected exactly one slice directory, got a second: {arg}"
                )
            slice_arg = arg
            i += 1
        if slice_arg is None:
            raise Ungradeable("a slice directory is required")
        code, summary = grade(Path(slice_arg), expected)
    except Ungradeable as exc:
        print(f"error: {exc}", file=sys.stderr)
        print("status=ungradeable")
        return 2
    print(summary)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))

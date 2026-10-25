#!/usr/bin/env python3
"""Advisory check: a line that names a labeled claim keeps the claim's label.

Reads the claims: list in the front matter of every <slice>/RESEARCH-*.md
sidecar (no recursion into sub-slices), with check-source-applicability.py's
parser, and collects each claim's id: and confidence:. A claim at
HIGH (single source), MEDIUM or LOW is a labeled claim. Then it reads every
line of <slice>/RESEARCH.md and of each sidecar, outside a sidecar's claims:
block, and finds each labeled claim's ID on it. The line must carry that
claim's confidence label verbatim. A summary line, a Settled or handoff
bullet, a table row and a sidecar abstract are each one line here, so a
restatement that dropped its label is caught wherever it sits. A plain HIGH
claim needs no label, and a claim with no id: is not looked for.

Lines under a heading that names the fetch log are skipped, down to the next
heading at the same or a higher level: the fetch log keys its rows by claim
and restates nothing.

Rule: skills/research/context/artifact-shape.md, "Restatements cite; they do
not restate". The research parent runs this check after the acceptance gate
and briefs the verifier on what it reports; it is advisory until it runs clean
on real slices, so a non-zero exit does not halt the run.

Exit 0 = every line naming a labeled claim carries its label (status=pass)
Exit 1 = at least one line drops a label (status=fail), each on stderr as
         <file>:<line>: <id> (<label>) appears without its label
Exit 2 = ungradeable, FAIL CLOSED: missing slice dir, no RESEARCH.md, no
         sidecar, a sidecar header the parser cannot read, an id: that is not
         a claim ID, one ID declared twice in the slice, an unreadable or
         non-UTF-8 file, a parser that cannot be loaded, or a usage error
         (status=ungradeable)

Usage:
  python3 check-restatement-labels.py <slice-dir>
  python3 check-restatement-labels.py --help
"""

from __future__ import annotations

import fnmatch
import importlib.util
import re
import sys
from pathlib import Path

USAGE = (
    __doc__
    + """
Claim ID grammar: one or more capital letters, an optional hyphen, digits, and
an optional lowercase letter: M1, K9, CI-02, S2a. IDs are unique across the
slice. An ID matches on a line only as a whole token: M1 is not found in M10,
and S2 is not found in S2a.

Output (stdout, one line):
  status=pass ids=<n> labeled=<n> mentions=<n>
  status=fail violations=<n> ids=<n> labeled=<n> mentions=<n>
  status=ungradeable
"""
)

LABELS = ("HIGH (single source)", "MEDIUM", "LOW")
CLAIM_ID = re.compile(r"^[A-Z]+-?[0-9]+[a-z]?$")
HEADING = re.compile(r"^ {0,3}(#{1,6})\s+(.*)$")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
FETCH_LOG = re.compile(r"\bfetch log\b", re.IGNORECASE)
LABEL_ON_LINE = {
    label: re.compile(r"(?<![A-Za-z])" + re.escape(label) + r"(?![A-Za-z])")
    for label in LABELS
}


def load_parser():
    """Load check-source-applicability.py, the one sidecar-header parser."""
    path = Path(__file__).resolve().with_name("check-source-applicability.py")
    spec = importlib.util.spec_from_file_location("check_source_applicability", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.dont_write_bytecode = True
    spec.loader.exec_module(module)
    return module


def claims_block(csa, lines: list[str]) -> range:
    """Front-matter indexes of the claims: block, by the parser's own stop rule."""
    found = csa.top_level(lines, "claims", "front matter")
    if found is None:
        return range(0)
    start = found[0]
    end = start + 1
    while end < len(lines):
        body = lines[end].strip()
        if body and not body.startswith("#") and csa.indent(lines[end]) == 0:
            if not csa.DASH.match(body):
                break
        end += 1
    return range(start, end)


def body_start(lines: list[str]) -> int:
    """Index of the first line after the front matter, or 0 when there is none."""
    if not lines or lines[0].rstrip() != "---":
        return 0
    for i in range(1, len(lines)):
        if lines[i].rstrip() == "---":
            return i + 1
    return len(lines)


def grade(csa, slice_dir: Path) -> tuple[int, str]:
    if not slice_dir.is_dir():
        raise csa.Ungradeable(f"slice directory not found: {slice_dir}")
    index = slice_dir / "RESEARCH.md"
    if not index.is_file():
        raise csa.Ungradeable(f"no index: {index}")
    # fnmatchcase, not glob: pathlib's glob is case-insensitive on Windows and
    # would take the lowercase research-checklist.md ledger for a sidecar.
    sidecars = sorted(
        p
        for p in slice_dir.iterdir()
        if fnmatch.fnmatchcase(p.name, "RESEARCH-*.md") and p.is_file()
    )
    if not sidecars:
        raise csa.Ungradeable(f"no RESEARCH-*.md sidecar in {slice_dir}")

    declared: dict[str, Path] = {}
    labeled: dict[str, str] = {}
    skip: dict[Path, range] = {}
    for sidecar in sidecars:
        header = csa.front_matter(sidecar, required=True)
        claims = csa.parse_claims(sidecar, header)
        skip[sidecar] = claims_block(csa, header)
        for c_no, claim in enumerate(claims, start=1):
            if "id" not in claim:
                continue
            cid = claim["id"]
            if cid is None or not CLAIM_ID.match(cid):
                raise csa.Ungradeable(
                    f"{sidecar}: claim {c_no}: id is not a claim ID: {cid}"
                )
            if cid in declared:
                raise csa.Ungradeable(
                    f"{sidecar}: claim {c_no}: id {cid} is already declared in {declared[cid]}"
                )
            declared[cid] = sidecar
            if claim.get("confidence") in LABELS:
                labeled[cid] = claim["confidence"]

    violations: list[str] = []
    mentions = 0
    if labeled:
        ids = sorted(labeled, key=len, reverse=True)
        pattern = re.compile(
            r"(?<![A-Za-z0-9_])(" + "|".join(map(re.escape, ids)) + r")(?![A-Za-z0-9_])"
        )
        for path in [index, *sidecars]:
            lines = csa.read_text(path).splitlines()
            block = skip.get(path, range(0))
            start = body_start(lines)
            fence: str | None = None
            fetch_level = 0
            for i, line in enumerate(lines):
                # Front-matter index j is lines[j + 1]: lines[0] is the opening ---.
                if i - 1 in block:
                    continue
                if i >= start:
                    opener = FENCE.match(line)
                    heading = HEADING.match(line) if fence is None else None
                    if opener:
                        if fence is None:
                            fence = opener.group(1)
                        elif line.strip().startswith(fence):
                            fence = None
                    elif heading:
                        level = len(heading.group(1))
                        if fetch_level and level <= fetch_level:
                            fetch_level = 0
                        if not fetch_level and FETCH_LOG.search(heading.group(2)):
                            fetch_level = level
                if fetch_level:
                    continue
                for cid in sorted({m.group(1) for m in pattern.finditer(line)}):
                    mentions += 1
                    label = labeled[cid]
                    if not LABEL_ON_LINE[label].search(line):
                        violations.append(
                            f"{path}:{i + 1}: {cid} ({label}) appears without its label"
                        )

    counts = f"ids={len(declared)} labeled={len(labeled)} mentions={mentions}"
    for line in violations:
        print(line, file=sys.stderr)
    if violations:
        return 1, f"status=fail violations={len(violations)} {counts}"
    return 0, f"status=pass {counts}"


def main(argv: list[str]) -> int:
    slice_arg: str | None = None
    usage_error: str | None = None
    for arg in argv[1:]:
        if arg in ("--help", "-h"):
            print(USAGE, end="")
            return 0
        if arg.startswith("-"):
            usage_error = f"unknown argument: {arg}"
        elif slice_arg is not None:
            usage_error = f"expected exactly one slice directory, got a second: {arg}"
        else:
            slice_arg = arg
    if usage_error is None and slice_arg is None:
        usage_error = "a slice directory is required"
    if usage_error is not None:
        print(f"error: {usage_error}", file=sys.stderr)
        print("status=ungradeable")
        return 2
    try:
        csa = load_parser()
    except (ImportError, OSError, SyntaxError) as exc:
        print(f"error: cannot load the header parser: {exc}", file=sys.stderr)
        print("status=ungradeable")
        return 2
    try:
        code, summary = grade(csa, Path(slice_arg))
    except csa.Ungradeable as exc:
        print(f"error: {exc}", file=sys.stderr)
        print("status=ungradeable")
        return 2
    print(summary)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""Check that a line naming a claim cites it and keeps its label.

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

A line of RESEARCH.md that names any claim's ID must not also carry a sweep
word (every, all, none, only, any case): the index points at claims, and a
sweep word on a pointer line widens the claim it names. Sidecar bodies are
where a claim is said in full, so this rule reads the index only.

Lines under a heading that names the fetch log are skipped, down to the next
heading at the same or a higher level: the fetch log keys its rows by claim
and restates nothing.

--sub-slice <dir>, repeatable, is for a slice-root synthesis that cites its
sub-slices' claims by ID. The claims declared in each named sub-slice's
sidecars (again no recursion) join the root's own, so a root line that points
at a sub-slice claim must carry that claim's label, and a root index line that
names one must carry no sweep word. Only the root's RESEARCH.md and the root's
own sidecars are read for lines; each sub-slice was graded on its own before
synthesis. With --sub-slice the root needs no sidecar of its own, and each
named sub-slice must hold at least one. An ID declared in two sub-slices, or
in a sub-slice and the root, is ambiguous and ungradeable like any duplicate.

Rule: skills/research/context/artifact-shape.md, "Restatements cite; they do
not restate". The researcher runs this check before hand-back and fixes every
line it reports; the research parent re-runs it in the acceptance gate.

Exit 0 = every line naming a labeled claim carries its label and no index
         line naming a claim carries a sweep word (status=pass)
Exit 1 = at least one violation (status=fail), each on stderr as
         <file>:<line>: <id> (<label>) appears without its label
         <file>:<line>: <id>[, <id>...] cited beside the sweep word "<word>"
Exit 2 = ungradeable, FAIL CLOSED: missing slice or sub-slice dir, no
         RESEARCH.md, no sidecar (at the root without --sub-slice, or in a
         named sub-slice), a sidecar header the parser cannot read, an id:
         that is not a claim ID, one ID declared twice across the files read,
         an unreadable or non-UTF-8 file, a parser that cannot be loaded, or a
         usage error (status=ungradeable)

Usage:
  python3 check-restatement-labels.py <slice-dir>
  python3 check-restatement-labels.py <slice-root> --sub-slice <dir> [--sub-slice <dir>]...
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
SWEEP = re.compile(r"(?<![A-Za-z])(?:every|all|none|only)(?![A-Za-z])", re.IGNORECASE)


def id_pattern(ids) -> re.Pattern:
    """Match any of ids as a whole token, longest first."""
    alternatives = "|".join(map(re.escape, sorted(ids, key=len, reverse=True)))
    return re.compile(r"(?<![A-Za-z0-9_])(" + alternatives + r")(?![A-Za-z0-9_])")


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


def sidecars_in(directory: Path) -> list[Path]:
    """The RESEARCH-*.md sidecars directly in directory, sorted."""
    # fnmatchcase, not glob: pathlib's glob is case-insensitive on Windows and
    # would take the lowercase research-checklist.md ledger for a sidecar.
    return sorted(
        p
        for p in directory.iterdir()
        if fnmatch.fnmatchcase(p.name, "RESEARCH-*.md") and p.is_file()
    )


def grade(csa, slice_dir: Path, sub_slices: list[Path] | None = None) -> tuple[int, str]:
    sub_slices = sub_slices or []
    if not slice_dir.is_dir():
        raise csa.Ungradeable(f"slice directory not found: {slice_dir}")
    index = slice_dir / "RESEARCH.md"
    if not index.is_file():
        raise csa.Ungradeable(f"no index: {index}")
    sidecars = sidecars_in(slice_dir)
    if not sidecars and not sub_slices:
        raise csa.Ungradeable(f"no RESEARCH-*.md sidecar in {slice_dir}")
    # A sub-slice's sidecars declare claims only: their lines were graded in
    # the sub-slice's own run, so only the root's files are read for lines.
    declaring = list(sidecars)
    for sub in sub_slices:
        if not sub.is_dir():
            raise csa.Ungradeable(f"sub-slice directory not found: {sub}")
        found = sidecars_in(sub)
        if not found:
            raise csa.Ungradeable(f"no RESEARCH-*.md sidecar in sub-slice {sub}")
        declaring.extend(found)

    declared: dict[str, Path] = {}
    labeled: dict[str, str] = {}
    skip: dict[Path, range] = {}
    for sidecar in declaring:
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
    if declared:
        pattern = id_pattern(declared)
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
                cited = sorted({m.group(1) for m in pattern.finditer(line)})
                sweep = SWEEP.search(line) if path == index and cited else None
                if sweep:
                    violations.append(
                        f"{path}:{i + 1}: {', '.join(cited)} cited beside the sweep word "
                        f'"{sweep.group(0)}"'
                    )
                for cid in cited:
                    if cid not in labeled:
                        continue
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
    sub_args: list[str] = []
    usage_error: str | None = None
    args = iter(argv[1:])
    for arg in args:
        if arg in ("--help", "-h"):
            print(USAGE, end="")
            return 0
        if arg == "--sub-slice":
            value = next(args, None)
            if value is None or value.startswith("-"):
                usage_error = "--sub-slice needs a directory"
                break
            sub_args.append(value)
        elif arg.startswith("-"):
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
        code, summary = grade(csa, Path(slice_arg), [Path(s) for s in sub_args])
    except csa.Ungradeable as exc:
        print(f"error: {exc}", file=sys.stderr)
        print("status=ungradeable")
        return 2
    print(summary)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))

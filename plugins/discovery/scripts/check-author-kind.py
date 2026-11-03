#!/usr/bin/env python3
"""Deterministic check that a Direct claim rests on a person's own words.

Reads the claims: list in the front matter of every <slice>/INTENT-*.md sidecar
(no recursion into sub-slices), with check-source-applicability.py's parser.
Only the recorded fields are read: whether a source's author_kind is the right
kind stays with the tracer and the verifier.

Rules (each violation on stderr as <file>: claim <n>[: source <m>]: <reason>):
  A1 every claim has one of the five tiers, so a misspelled Direct cannot skip
     A2 and A3.
  A2 every source of a Direct claim has author_kind: owner-quote or agent-relay.
  A3 a Direct claim has at least one owner-quote source.
Claims at other tiers carry no such limit: an Unknown claim's sources name
searches, not writers.

Rule: skills/trace-intent/context/artifact-shape.md, "author_kind says who wrote
the words". The tracer runs this check before hand-back and the parent re-runs
it in the acceptance gate.

Exit 0 = every rule holds (status=pass)
Exit 1 = at least one violation (status=fail)
Exit 2 = ungradeable, FAIL CLOSED: missing slice dir, no INTENT.md, no sidecar,
         a sidecar header the parser cannot read, an unreadable or non-UTF-8
         file, a parser that cannot be loaded, or a usage error
         (status=ungradeable)

Usage:
  python3 check-author-kind.py <slice-dir>
  python3 check-author-kind.py --help
"""

from __future__ import annotations

import fnmatch
import importlib.util
import re
import sys
from pathlib import Path

USAGE = (
    (__doc__ or "")
    + """
Output (stdout, one line):
  status=pass claims=<n> direct=<n>
  status=fail violations=<n> claims=<n> direct=<n>
  status=ungradeable
"""
)

TIERS = ("Direct", "Supported", "Inferred", "Speculative", "Unknown")
OWNER_QUOTE = "owner-quote"
KINDS = (OWNER_QUOTE, "agent-relay")
# The parser opens a source item on url:; an intent source opens on ref:.
SOURCE_REF = re.compile(r"^(\s*- )ref(\s*:)")


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


def parse_sidecar(csa, sidecar: Path) -> list[dict]:
    lines = [
        SOURCE_REF.sub(r"\1url\2", line)
        for line in csa.front_matter(sidecar, required=True)
    ]
    try:
        return csa.parse_claims(sidecar, lines)
    except csa.Ungradeable as exc:
        raise csa.Ungradeable(str(exc).replace("url:", "ref:")) from exc


def check_claim(claim: dict) -> list[str]:
    tier = claim.get("tier")
    if tier not in TIERS:
        return [f"tier is {tier!r}, not one of {', '.join(TIERS)}"]
    if tier != "Direct":
        return []
    kinds = [source.get("author_kind") for source in claim["sources"]]
    problems = [
        f"source {n}: author_kind is {kind!r}, not {' or '.join(KINDS)}"
        for n, kind in enumerate(kinds, start=1)
        if kind not in KINDS
    ]
    if not problems and OWNER_QUOTE not in kinds:
        problems.append(
            "Direct needs an owner-quote source: find the person's own words "
            "or lower the tier"
        )
    return problems


def grade(csa, slice_dir: Path) -> tuple[int, str]:
    if not slice_dir.is_dir():
        raise csa.Ungradeable(f"slice directory not found: {slice_dir}")
    if not (slice_dir / "INTENT.md").is_file():
        raise csa.Ungradeable(f"no index: {slice_dir / 'INTENT.md'}")
    # fnmatchcase, not glob: pathlib's glob is case-insensitive on Windows.
    sidecars = sorted(
        p
        for p in slice_dir.iterdir()
        if fnmatch.fnmatchcase(p.name, "INTENT-*.md") and p.is_file()
    )
    if not sidecars:
        raise csa.Ungradeable(f"no INTENT-*.md sidecar in {slice_dir}")

    violations: list[str] = []
    total = direct = 0
    for sidecar in sidecars:
        for c_no, claim in enumerate(parse_sidecar(csa, sidecar), start=1):
            total += 1
            direct += claim.get("tier") == "Direct"
            for reason in check_claim(claim):
                violations.append(f"{sidecar}: claim {c_no}: {reason}")

    counts = f"claims={total} direct={direct}"
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
    except (ImportError, OSError, SyntaxError, TypeError) as exc:
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

#!/usr/bin/env python3
"""Deterministic check of each claim's confidence against its own header.

Reads the claims: list in the front matter of every <slice>/RESEARCH-*.md
sidecar (no recursion into sub-slices), with check-source-applicability.py's
parser, and checks the parts of outcome-gate rows 4 and 7 that the header
alone settles. Whether a single_source: reason holds, whether claim_kind is
the right kind, and whether a source measures the claim stay with the
verifier; this script only refuses a header whose recorded fields cannot
support the confidence it claims.

Rules (each violation on stderr as <file>: claim <n> [<id>]: <reason>):
  E1 every claim has claim_kind: content or behavior.
  E2 every claim has a non-empty source_owner: (who owns the artifact or the
     product the claim is about).
  E3 confidence is HIGH, HIGH (single source), MEDIUM or LOW.
  E4 HIGH (single source) needs claim_kind: content, a single_source:
     reason, and a primary source whose pool equals source_owner (a
     first-party page or paper; a third-party report is not eligible). A
     claim at any other confidence carries no single_source:. (row 4)
  E5 HIGH needs at least three current Tier 0/1 sources in distinct pools:
     2 Tier 1 + 1 Tier 2 is MEDIUM, not HIGH. (row 7)
  E6 a claim carrying subject_pool: is a single-publisher fact: at most
     MEDIUM, and never also carrying single_source:. (rows 4 and 7)
Pools and source_owner compare case-insensitively, trimmed.

Rule: skills/research/context/discipline.md, "Single-source first-party
content claims" and "Confidence calibration". The researcher runs this check
before hand-back and the parent re-runs it in the acceptance gate.

Exit 0 = every rule holds (status=pass)
Exit 1 = at least one violation (status=fail)
Exit 2 = ungradeable, FAIL CLOSED: missing slice dir, no RESEARCH.md, no
         sidecar, a sidecar header the parser cannot read, an unreadable or
         non-UTF-8 file, a parser that cannot be loaded, or a usage error
         (status=ungradeable)

Usage:
  python3 check-claim-eligibility.py <slice-dir>
  python3 check-claim-eligibility.py --help
"""

from __future__ import annotations

import fnmatch
import importlib.util
import sys
from pathlib import Path

USAGE = (
    __doc__
    + """
Output (stdout, one line):
  status=pass claims=<n> high=<n> flagged=<n>
  status=fail violations=<n> claims=<n> high=<n> flagged=<n>
  status=ungradeable
"""
)

KINDS = ("content", "behavior")
CONFIDENCES = ("HIGH", "HIGH (single source)", "MEDIUM", "LOW")
FLAG = "HIGH (single source)"
HIGH_POOLS = 3


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


def norm(value: str | None) -> str:
    return (value or "").strip().casefold()


def check_claim(claim: dict) -> list[str]:
    problems: list[str] = []
    kind = claim.get("claim_kind")
    owner = norm(claim.get("source_owner"))
    confidence = claim.get("confidence")
    sources = claim["sources"]

    if kind not in KINDS:
        problems.append(f"claim_kind is {kind!r}, not content or behavior")
    if not owner:
        problems.append("source_owner is missing or empty")
    if confidence not in CONFIDENCES:
        problems.append(f"confidence is {confidence!r}, not one of {', '.join(CONFIDENCES)}")
        return problems

    has_reason = bool(norm(claim.get("single_source")))
    if confidence == FLAG:
        if kind != "content":
            problems.append(f"{FLAG} needs claim_kind: content; a {kind} claim gets no flag")
        if not has_reason:
            problems.append(f"{FLAG} needs a single_source: reason")
        if owner and not any(
            s.get("role") == "primary" and norm(s.get("pool")) == owner for s in sources
        ):
            problems.append(
                f"{FLAG} needs a primary whose pool is the source_owner "
                f"({claim.get('source_owner')}); a third-party report is not eligible"
            )
    elif has_reason:
        problems.append(f"single_source: is only for {FLAG}, not {confidence}")

    if confidence == "HIGH":
        pools = {
            norm(s.get("pool"))
            for s in sources
            if s.get("tier") in ("0", "1")
            and s.get("standing") == "current"
            and norm(s.get("pool"))
        }
        if len(pools) < HIGH_POOLS:
            problems.append(
                f"HIGH needs {HIGH_POOLS} current Tier 0/1 sources in distinct pools, "
                f"found {len(pools)}; that mix is MEDIUM"
            )

    if claim.get("subject_pool") is not None:
        if confidence in ("HIGH", FLAG):
            problems.append(f"a subject_pool claim is at most MEDIUM, not {confidence}")
        if has_reason:
            problems.append("a claim carries single_source: or subject_pool:, never both")
    return problems


def grade(csa, slice_dir: Path) -> tuple[int, str]:
    if not slice_dir.is_dir():
        raise csa.Ungradeable(f"slice directory not found: {slice_dir}")
    if not (slice_dir / "RESEARCH.md").is_file():
        raise csa.Ungradeable(f"no index: {slice_dir / 'RESEARCH.md'}")
    # fnmatchcase, not glob: pathlib's glob is case-insensitive on Windows.
    sidecars = sorted(
        p
        for p in slice_dir.iterdir()
        if fnmatch.fnmatchcase(p.name, "RESEARCH-*.md") and p.is_file()
    )
    if not sidecars:
        raise csa.Ungradeable(f"no RESEARCH-*.md sidecar in {slice_dir}")

    violations: list[str] = []
    total = high = flagged = 0
    for sidecar in sidecars:
        header = csa.front_matter(sidecar, required=True)
        for c_no, claim in enumerate(csa.parse_claims(sidecar, header), start=1):
            total += 1
            high += claim.get("confidence") == "HIGH"
            flagged += claim.get("confidence") == FLAG
            label = f" [{claim['id']}]" if claim.get("id") else ""
            for reason in check_claim(claim):
                violations.append(f"{sidecar}: claim {c_no}{label}: {reason}")

    counts = f"claims={total} high={high} flagged={flagged}"
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

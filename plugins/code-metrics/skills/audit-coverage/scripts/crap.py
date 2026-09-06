#!/usr/bin/env python3
"""The CRAP score for one function: `comp^2 * (1 - cov/100)^3 + comp`.

    crap.py --comp <int> --cov <number|null>

Prints the value (an integer when whole, otherwise up to three decimals), or
`null` when `cov` is `null`. Exit 0 on success, 2 on a usage error, which
includes a negative complexity or a coverage percentage outside 0..100.

The formula is Savoia and Evans' (Agitar Labs, 2007). It is a description of
two numbers a reader already has, not a validated predictor of change risk,
and no standard sets a threshold for it; `/code-metrics:principles` carries
that provenance and the caveats.

`cov` of `null` propagates: a function with no executable lines in the
coverage artifact has no coverage percentage, and treating that absence as 0
would report the maximal CRAP the formula can produce for its complexity.
"""

from __future__ import annotations

import argparse
import sys

MIN_PYTHON = (3, 9)


def crap(comp: int, cov: float | None) -> float | None:
    """CRAP for a function of cyclomatic complexity `comp` at `cov` percent
    line coverage; `None` coverage gives `None`."""
    if comp < 0:
        raise ValueError("complexity must not be negative")
    if cov is None:
        return None
    if cov < 0 or cov > 100:
        raise ValueError("coverage must be a percentage between 0 and 100")
    return comp * comp * (1 - cov / 100.0) ** 3 + comp


def render(value: float | None) -> str:
    """The printed form: `null`, an integer when whole, else 3 decimals."""
    if value is None:
        return "null"
    rounded = round(value, 3)
    if rounded == int(rounded):
        return str(int(rounded))
    return f"{rounded:.3f}".rstrip("0").rstrip(".")


def _coverage(text: str) -> float | None:
    if text.strip().lower() in ("null", "none"):
        return None
    return float(text)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="crap.py", add_help=True)
    parser.add_argument("--comp", required=True, type=int)
    parser.add_argument("--cov", required=True)
    args = parser.parse_args(argv)
    print(render(crap(args.comp, _coverage(args.cov))))
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("crap.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1:]))
    except ValueError as exc:
        print(f"crap.py: {exc}", file=sys.stderr)
        sys.exit(2)

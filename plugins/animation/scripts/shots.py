#!/usr/bin/env python3
"""Shot-cut reader. shots.json is the only owner of cut times (#4591, T16).

inkstats.py --cuts and produce.py both call shot_starts. A path to shots.json
yields each shot's start, in order. Any other value is the old comma list
(a hyphen is a comma, the same way inkstats.nums reads --cuts).
"""

import json
import sys
from pathlib import Path


def numeric_cuts(spec):
    """Comma or hyphen separated seconds, or None when spec is empty."""
    if not spec:
        return None
    return [float(part) for part in spec.replace("-", ",").split(",") if part != ""]


def shot_starts(spec):
    """Cut times from a shots.json path, or from a comma list.

    A value that looks like a file (a .json suffix, a slash, or an existing
    file) is shots.json. A missing file is an error, not a fallthrough to the
    comma parser.
    """
    if not spec:
        return None
    path = Path(spec)
    looks_like_file = path.suffix.lower() == ".json" or "/" in spec or "\\" in spec or path.is_file()
    if not looks_like_file:
        return numeric_cuts(spec)
    if not path.is_file():
        sys.exit(f"shots: cuts file not found: {spec}")
    data = json.loads(path.read_text(encoding="utf-8"))
    shots = data.get("shots") if isinstance(data, dict) else None
    if not isinstance(shots, list) or not shots:
        sys.exit(f"shots: {spec} has no shots")
    starts = []
    for shot in shots:
        if not isinstance(shot, dict) or ("t0" not in shot and "start" not in shot):
            sys.exit(f"shots: a shot in {spec} has no t0")
        starts.append(float(shot["t0"] if "t0" in shot else shot["start"]))
    return starts


def main(argv=None):
    spec = (argv or sys.argv[1:])[0] if (argv or sys.argv[1:]) else ""
    starts = shot_starts(spec)
    if starts is None:
        return 0
    print(",".join(f"{s:g}" for s in starts))
    return 0


if __name__ == "__main__":
    sys.exit(main())

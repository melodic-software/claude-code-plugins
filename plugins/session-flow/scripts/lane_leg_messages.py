#!/usr/bin/env python3
"""Print a sealed lane leg's messages, one per line, so a reader can open a gzipped transcript.

Usage:
    lane_leg_messages.py <leg.json.gz> [--from N] [--to N]

Each line is `<index><TAB><message JSON>`, the index being the message's position in the leg's
array, the position a finding cites. `--from` and `--to` bound the indexes, both inclusive. A plain
(not gzipped) array reads the same. The output is the leg's own text, which a lane read from
outside actors: it goes to the caller's terminal only, never to a file. Exit 0, or 2 when the leg is
missing or is not a readable JSON array. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import gzip
import json
import sys
import zlib
from pathlib import Path


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="lane_leg_messages.py", description=__doc__.splitlines()[0])
    parser.add_argument("leg", type=Path)
    parser.add_argument("--from", dest="start", type=int, default=0)
    parser.add_argument("--to", dest="end", type=int)
    ns = parser.parse_args(argv)
    try:
        raw = ns.leg.read_bytes()
        if raw[:2] == b"\x1f\x8b":
            raw = gzip.decompress(raw)
        messages = json.loads(raw.decode("utf-8", errors="replace"))
    except (OSError, EOFError, ValueError, zlib.error):
        messages = None
    if not isinstance(messages, list):
        print(f"lane_leg_messages.py: {ns.leg} is not a readable lane leg", file=sys.stderr)
        return 2
    end = len(messages) - 1 if ns.end is None else ns.end
    for index in range(max(ns.start, 0), min(end, len(messages) - 1) + 1):
        print(f"{index}\t{json.dumps(messages[index], ensure_ascii=False)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

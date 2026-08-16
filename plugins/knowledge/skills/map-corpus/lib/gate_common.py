"""Primitives shared by the map-corpus gates (check_linkmap, check_inventory).

Imported via a sys.path insert by each gate; both stay standalone-runnable
scripts with no third-party dependency. Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import sys


def reject_duplicate_keys(pairs):
    """object_pairs_hook: json.loads is last-wins on duplicate keys, so a
    duplicated field would let unvalidated bytes ride under a validated name
    (parser-differential fail-open). Reject at any depth instead."""
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise ValueError(f"duplicate JSON key {key!r}")
        seen[key] = value
    return seen


class Failures:
    """Named check failures, echoed to stderr as they land under `prog`."""

    def __init__(self, prog: str):
        self.prog = prog
        self.items = []

    def add(self, message: str):
        self.items.append(message)
        sys.stderr.write(f"{self.prog}: FAIL: {message}\n")

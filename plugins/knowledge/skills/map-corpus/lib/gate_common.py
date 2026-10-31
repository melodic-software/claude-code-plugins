"""Primitives shared by the map-corpus gates (check_linkmap, check_inventory).

Imported via a sys.path insert by each gate; both stay standalone-runnable
scripts with no third-party dependency. Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import os
import sys

sys.dont_write_bytecode = True  # the plugin's own tree is not a cache
sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, os.pardir, os.pardir, "lib")
)
from gates.failures import Failures  # noqa: E402  (the plugin's shared gate primitives)

__all__ = ["Failures", "is_int", "reject_duplicate_keys"]


def is_int(value) -> bool:
    """True for a real int; JSON booleans are ints in Python and are not."""
    return isinstance(value, int) and not isinstance(value, bool)


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

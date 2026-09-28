#!/usr/bin/env python3
"""Read a statusline JSON payload and print the native prompt-cache miss cause.

The statusline ``prompt_cache.last_miss_cause`` object is the field Claude Code
2.1.260 added. ``causes`` holds names such as ``tools_changed``,
``system_prompt_changed``, ``ttl_expired_5m``, or ``likely_server_side``.
``tools_added`` and ``tools_removed`` ride with ``tools_changed``;
``system_char_delta`` rides with ``system_prompt_changed``. The object is null
until the first diagnosed miss, and again when the latest miss has no cause.

Basis: https://code.claude.com/docs/en/statusline#last-miss-cause
As of: 2026-09-28.
Recheck: that section renames ``last_miss_cause`` or its ``causes`` names.

Stdout is TSV. Exit 0 when the payload is an object (including a missing or
null cause). Exit 2 when stdin is not a JSON object or the cause is the wrong
shape.
"""

from __future__ import annotations

import json
import sys

COUNT_FIELDS = ("tools_added", "tools_removed", "system_char_delta")


def main() -> int:
    try:
        data = json.loads(sys.stdin.read() or "null")
    except json.JSONDecodeError:
        print("prompt-cache-cause: stdin is not JSON", file=sys.stderr)
        return 2
    if not isinstance(data, dict):
        print("prompt-cache-cause: stdin is not a JSON object", file=sys.stderr)
        return 2
    cache = data.get("prompt_cache")
    if not isinstance(cache, dict):
        print("last_miss_cause\tabsent")
        return 0
    cause = cache.get("last_miss_cause")
    if cause is None:
        print("last_miss_cause\tnull")
        return 0
    if not isinstance(cause, dict):
        print("prompt-cache-cause: last_miss_cause is not an object", file=sys.stderr)
        return 2
    causes = cause.get("causes", [])
    if not isinstance(causes, list) or any(not isinstance(item, str) for item in causes):
        print("prompt-cache-cause: causes is not a list of strings", file=sys.stderr)
        return 2
    print("causes\t" + ",".join(causes))
    for key in COUNT_FIELDS:
        if key in cause:
            print(f"{key}\t{cause[key]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

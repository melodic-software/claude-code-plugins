# GENERATED from lib/transcript_values.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# -*- coding: utf-8 -*-
"""Values every transcript reader shares: entrypoint classes, timestamps and version order.

- `AUTOMATED_ENTRYPOINTS`: the `entrypoint` values of headless and Agent SDK runs;
  `UNKNOWN_ENTRYPOINT` stands in for a session that records none.
- `epoch(value)` is an ISO-8601 timestamp as epoch seconds, a naive one read as UTC; None when not one.
- `version_key(version)` orders Claude Code version strings numerically.

Callers put this directory on `sys.path` and `import transcript_values`. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

from datetime import datetime, timezone

UNKNOWN_ENTRYPOINT = "unknown"
# Headless and Agent SDK `entrypoint` values, as the `app.entrypoint` attribute lists them:
# https://code.claude.com/docs/en/monitoring-usage#standard-attributes
AUTOMATED_ENTRYPOINTS = frozenset({"sdk-cli", "sdk-ts", "sdk-py"})


def epoch(value: object) -> float | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return (parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)).timestamp()


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int("".join(c for c in part if c.isdigit()) or 0) for part in version.split("."))

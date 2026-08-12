#!/usr/bin/env python3
"""Compare a Claude usage-limit reset clause against the current clock.

Exit codes:
  0 — the stated reset time is at or before now (limit lifted; proceed)
  1 — the reset time is still in the future (limit active; hand back)
  2 — could not parse the input

Example limit text:
  You've hit your session limit · resets 2:30am (America/New_York)
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo


RESET_RE = re.compile(
    r"resets\s+"
    r"(?P<hour>\d{1,2})(?P<minute>:[0-5]\d)?"
    r"(?P<ampm>am|pm)"
    r"(?:\s*\((?P<tz>[^)]+)\))?",
    re.IGNORECASE,
)


def parse_reset(text: str, *, now: datetime | None = None) -> datetime:
    match = RESET_RE.search(text)
    if not match:
        raise ValueError("no reset clause found")
    hour = int(match.group("hour"))
    minute = int((match.group("minute") or ":00")[1:])
    ampm = match.group("ampm").lower()
    if hour == 12:
        hour = 0
    if ampm == "pm":
        hour += 12
    tz_raw = match.group("tz")
    if tz_raw:
        zone = ZoneInfo(tz_raw.strip())
    elif now is not None:
        zone = now.tzinfo or ZoneInfo("UTC")
    else:
        local = datetime.now().astimezone().tzinfo
        zone = local if local is not None else ZoneInfo("UTC")
    current = now.astimezone(zone) if now is not None else datetime.now(zone)
    reset_at = current.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if reset_at > current:
        # After midnight, an evening reset already passed yesterday; an early-morning
        # reset is still ahead on today's calendar.
        if ampm == "pm" and current.hour < 12:
            reset_at -= timedelta(days=1)
    return reset_at


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "text",
        nargs="?",
        help="Limit message text containing a resets clause (stdin when omitted)",
    )
    parser.add_argument(
        "--now",
        help="ISO-8601 override for tests (must include offset or Z)",
    )
    args = parser.parse_args(argv)
    text = args.text
    if text is None:
        text = sys.stdin.read()
    now = datetime.fromisoformat(args.now.replace("Z", "+00:00")) if args.now else None
    try:
        reset_at = parse_reset(text, now=now)
    except Exception as exc:  # noqa: BLE001 — CLI boundary
        print(f"unparsed: {exc}", file=sys.stderr)
        return 2
    current = now.astimezone(reset_at.tzinfo) if now is not None else datetime.now(reset_at.tzinfo)
    if current >= reset_at:
        print(f"lifted: reset was {reset_at.isoformat()}; now is {current.isoformat()}")
        return 0
    print(f"blocked: reset at {reset_at.isoformat()}; now is {current.isoformat()}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Compare a Claude usage-limit reset clause against the current clock.

Exit codes:
  0 — the stated reset time is at or before now (limit lifted; proceed)
  1 — the reset time is still in the future (limit active; hand back)
  2 — could not parse the input
  3 — parsed an IANA timezone the runtime cannot resolve

Example limit text:
  You've hit your session limit · resets 2:30am (America/New_York)

On Windows (and any host without a system IANA TZDB) ``zoneinfo`` needs the
first-party ``tzdata`` package. This script extracts a bundled
``vendor/tzdata-zoneinfo.zip`` into a tempfile cache and puts that on
``sys.path`` so IANA names in limit messages resolve without a pip install.
"""

from __future__ import annotations

import argparse
import getpass
import hashlib
import os
import re
import shutil
import sys
import tempfile
import zipfile
from datetime import datetime, timedelta
from pathlib import Path

# Bundled tzdata must be importable before any ZoneInfo(IANA) call so hosts
# without a system TZDB (notably Windows) can resolve limit-message zones.
_VENDOR_ZIP = Path(__file__).resolve().parent / "vendor" / "tzdata-zoneinfo.zip"


def _cache_owner_suffix() -> str:
    """A per-user component for the cache directory name.

    Without it the cache path is fully predictable — the digest comes from a
    publicly committed file — so on a shared world-writable /tmp any local user
    could pre-create the directory and have it imported (CWE-377, CWE-426).
    """
    try:
        return f"-{os.getuid()}"  # type: ignore[attr-defined]
    except AttributeError:
        # Windows: %TEMP% is already per-user, but keep the name distinct.
        return f"-{getpass.getuser()}"


def _ensure_bundled_tzdata() -> None:
    """Extract the vendored tzdata zip once into a tempfile cache on sys.path.

    Every failure here is non-fatal by design: the caller degrades to exit 3
    ("timezone-unavailable"), which is the documented "cannot determine" code.
    An exception escaping this function would abort the script with exit 1,
    and in this script's contract exit 1 means "the limit still holds" — a
    corrupt bundle would tell the caller to keep waiting.
    """
    if not _VENDOR_ZIP.is_file():
        return
    try:
        digest = hashlib.sha256()
        with _VENDOR_ZIP.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        cache_root = Path(tempfile.gettempdir()) / (
            f"session-flow-tzdata-{digest.hexdigest()[:16]}{_cache_owner_suffix()}"
        )
        if not (cache_root / "tzdata").is_dir():
            staging = Path(
                tempfile.mkdtemp(
                    prefix=f"{cache_root.name}-",
                    dir=str(cache_root.parent),
                )
            )
            try:
                with zipfile.ZipFile(_VENDOR_ZIP) as archive:
                    archive.extractall(staging)
                if (staging / "tzdata").is_dir():
                    try:
                        staging.rename(cache_root)
                    except OSError:
                        # Another process likely finished extraction first.
                        if not (cache_root / "tzdata").is_dir():
                            raise
            finally:
                if staging.exists():
                    shutil.rmtree(staging, ignore_errors=True)
        if not (cache_root / "tzdata").is_dir():
            return
        # Trust the cache only if we own it. A directory planted by another
        # user is skipped rather than imported; the run then degrades to the
        # same exit 3 as a missing bundle.
        if not _cache_is_trusted(cache_root):
            return
        cache_path = str(cache_root)
        if cache_path not in sys.path:
            sys.path.insert(0, cache_path)
    except Exception:
        # Corrupt or truncated zip, read-only TEMP, disk full, unreadable
        # bundle, failed rename — all degrade to "no bundled tzdata".
        return


def _cache_is_trusted(cache_root: Path) -> bool:
    """True when the cache directory is safe to put on ``sys.path``.

    Two independent checks, because neither covers every host:

    * **Not a symlink.** A symlinked cache root could redirect the import
      somewhere else entirely, on any platform.
    * **Owned by this user**, where the platform can say so. ``os.getuid``
      exists on POSIX; on Windows it does not, so this check is a no-op there
      and the per-user directory name carries the isolation instead —
      ``%TEMP%`` is already per-user on Windows, which is why the predictable
      shared-directory problem is a POSIX-shared-``/tmp`` problem in the first
      place.
    """
    try:
        if cache_root.is_symlink():
            return False
        stat_result = os.stat(cache_root)
    except OSError:
        return False
    getuid = getattr(os, "getuid", None)
    if getuid is not None and stat_result.st_uid != getuid():
        return False
    return True


_ensure_bundled_tzdata()

try:
    import tzdata  # noqa: F401 — IANA DB fallback for zoneinfo
except ImportError:
    pass

from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


class TimezoneUnavailableError(RuntimeError):
    """IANA zone key could not be resolved (distinct from an unparsable message)."""


RESET_RE = re.compile(
    r"resets\s+"
    r"(?P<hour>\d{1,2})(?P<minute>:[0-5]\d)?"
    r"(?P<ampm>am|pm)"
    r"(?:\s*\((?P<tz>[^)]+)\))?",
    re.IGNORECASE,
)


def resolve_zone(name: str) -> ZoneInfo:
    """Resolve an IANA zone key, surfacing a clear error when the TZDB is missing."""
    try:
        return ZoneInfo(name)
    except ZoneInfoNotFoundError as exc:
        # ZoneInfoNotFoundError is a KeyError subclass; its str() quotes the
        # message. Raise a plain RuntimeError so the CLI line stays readable.
        raise TimezoneUnavailableError(
            f"No time zone found with key {name} "
            "(system IANA TZDB unavailable and tzdata could not resolve it; "
            "the plugin bundles tzdata as scripts/vendor/tzdata-zoneinfo.zip — "
            "reinstall the plugin, or pip install tzdata)"
        ) from exc


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
        zone = resolve_zone(tz_raw.strip())
    elif now is not None:
        zone = now.tzinfo or resolve_zone("UTC")
    else:
        local = datetime.now().astimezone().tzinfo
        zone = local if local is not None else resolve_zone("UTC")
    current = now.astimezone(zone) if now is not None else datetime.now(zone)
    reset_at = current.replace(hour=hour, minute=minute, second=0, microsecond=0)
    # After midnight, an evening reset already passed yesterday; an early-morning
    # reset is still ahead on today's calendar.
    if reset_at > current and ampm == "pm" and current.hour < 12:
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
    except TimezoneUnavailableError as exc:
        print(f"timezone-unavailable: {exc}", file=sys.stderr)
        return 3
    except Exception as exc:  # noqa: BLE001 — CLI boundary
        print(f"unparsed: {exc}", file=sys.stderr)
        return 2
    current = (
        now.astimezone(reset_at.tzinfo)
        if now is not None
        else datetime.now(reset_at.tzinfo)
    )
    if current >= reset_at:
        print(f"lifted: reset was {reset_at.isoformat()}; now is {current.isoformat()}")
        return 0
    print(f"blocked: reset at {reset_at.isoformat()}; now is {current.isoformat()}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

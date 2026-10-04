# -*- coding: utf-8 -*-
"""Census aggregate and drift classifier over the audit-sessions store.

Reads stored `session-record/v1` files only, never a transcript, so `collect.py` (the `census`
and `drift` subcommands) and `sweep.py` share it. Each record carries its session's census:
`census["<version>|<model or *>"]["<section>:<key>"] = count`. The aggregate sums those rows;
the classifier compares Claude Code versions:

- `new`: a key at `min_count` or more in the newest version, absent from every earlier version
  of a model already seen before it.
- `vanished`: a key at `min_count` or more over the baseline versions and absent in each of the
  last `versions` versions in which its model has `min_count` records.
- `canary-lost`: a canary from `reference/canaries.json` missing from the newest version (or,
  with `expect: absent`, counted `min_count` times or more in it) while that version holds
  `min_count` records of the canary's population (default `record_type:<record_type>`) across
  at least `session_floor` sessions.
- `unknown-record-type`: a record type the collector's reader does not know, with its count.

Only versions holding `min_count` records take part, and the `unknown` version bucket (records
without a `version`) never does. The drift defaults, `session_class` (a record's stored
`entrypoints` read as automated, interactive or unknown) and `write_atomic` live here too, so both
scripts share one store layer without `sweep.py` importing `collect.py` and its reader.
Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import json
import os
import tempfile
import time
from collections import Counter
from pathlib import Path

RECORD_SCHEMA = "session-record/v1"
CANARY_SCHEMA = "audit-sessions.canaries/v1"
BUNDLED_CANARIES = Path(__file__).resolve().parents[1] / "reference" / "canaries.json"
CLASSES = ("new", "vanished", "canary-lost", "unknown-record-type")
SECTIONS = frozenset(
    {
        "record_type",
        "key_path",
        "system_subtype",
        "attachment_type",
        "usage_key",
        "effort_value",
        "assistant_error",
        "invariant",
    }
)
UNKNOWN_VERSION = "unknown"
UNKNOWN_ENTRYPOINT = "unknown"
# Transcript `entrypoint` values of headless (`claude -p`) and Agent SDK runs. The transcript key is
# undocumented; its values match the `app.entrypoint` telemetry attribute. Pointer:
# https://code.claude.com/docs/en/monitoring-usage#standard-attributes (as of 2026-10-04; recheck
# when that row adds an SDK entrypoint or a drift run reports the entrypoint canary lost).
AUTOMATED_ENTRYPOINTS = frozenset({"sdk-cli", "sdk-ts", "sdk-py"})
DEFAULT_MIN_COUNT = 20
DEFAULT_VERSIONS = 3
# Sessions the newest version needs before a missing canary counts as lost.
DEFAULT_SESSION_FLOOR = 3


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int("".join(c for c in part if c.isdigit()) or 0) for part in version.split("."))


def store_dir(data_dir: Path) -> Path:
    return data_dir / "audit-sessions" / "store" / "v1" / "sessions"


def write_atomic(path: Path, payload: dict | str) -> bool:
    """Write JSON (a dict) or text via a unique temp file and os.replace; False when a reader lock
    outlasts the retries."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            if isinstance(payload, str):
                handle.write(payload)
            else:
                json.dump(payload, handle, indent=2, sort_keys=True)
                handle.write("\n")
        # Windows refuses the replace while a reader holds the target open.
        for _ in range(20):
            try:
                os.replace(tmp, path)
                return True
            except PermissionError:
                time.sleep(0.05)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise
    Path(tmp).unlink(missing_ok=True)
    return False


def load_records(data_dir: Path) -> tuple[list[dict], int]:
    """Stored records, plus the count of unreadable or wrong-schema files skipped."""
    if not store_dir(data_dir).is_dir():
        raise FileNotFoundError(f"no audit-sessions store under {data_dir}; run collect first")
    records, skipped = [], 0
    for path in sorted(store_dir(data_dir).glob("p-*/*.json")):
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            record = None
        if isinstance(record, dict) and record.get("schema") == RECORD_SCHEMA:
            records.append(record)
        else:
            skipped += 1
    return records, skipped


def session_class(record: dict) -> str:
    """`automated` when every stored entrypoint is an SDK one, `unknown` when none is known, else `interactive`.

    A session resumed interactively after a headless start carries both and counts as interactive.
    """
    values = record.get("entrypoints")
    known = [v for v in values if isinstance(v, str) and v != UNKNOWN_ENTRYPOINT] if isinstance(values, list) else []
    if not known:
        return "unknown"
    return "automated" if all(v in AUTOMATED_ENTRYPOINTS for v in known) else "interactive"


def load_canaries(path: Path) -> dict:
    canaries = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(canaries, dict) or canaries.get("schema") != CANARY_SCHEMA:
        raise ValueError(f"{path}: not an {CANARY_SCHEMA} file")
    entries = canaries.get("canaries", [])
    if not isinstance(entries, list) or not all(_valid_canary(c) for c in entries):
        raise ValueError(f"{path}: each canary needs string key and record_type and a list of feeds")
    return canaries


def _valid_canary(canary: object) -> bool:
    return (
        isinstance(canary, dict)
        and all(isinstance(canary.get(f), str) for f in ("key", "record_type"))
        and isinstance(canary.get("feeds"), list)
        and all(isinstance(f, str) for f in canary["feeds"])
        and isinstance(canary.get("population", ""), str)
        and canary.get("expect", "present") in ("present", "absent")
    )


def _counts(value: object) -> dict[str, int]:
    if not isinstance(value, dict):
        return {}
    return {k: n for k, n in value.items() if isinstance(n, int) and not isinstance(n, bool)}


def _rows(record: dict) -> dict[str, dict]:
    rows = record.get("census")
    return {b: r for b, r in rows.items() if isinstance(r, dict)} if isinstance(rows, dict) else {}


def aggregate(records: list[dict], version: str | None = None, model: str | None = None) -> dict:
    """`{"<version>|<model>": {records, sessions, keys}}` summed over records."""
    out: dict[str, dict] = {}
    for record in records:
        for bucket, keys in _rows(record).items():
            bucket_version, _, bucket_model = bucket.partition("|")
            if (version is not None and bucket_version != version) or (model is not None and bucket_model != model):
                continue
            row = out.setdefault(bucket, {"records": 0, "sessions": 0, "keys": Counter()})
            row["sessions"] += 1
            row["keys"].update(_counts(keys))
    for row in out.values():
        row["records"] = sum(n for k, n in row["keys"].items() if k.startswith("record_type:"))
        row["keys"] = dict(row["keys"])
    return out


def drift(records: list[dict], canaries: list[dict], *, min_count: int, versions: int, session_floor: int) -> dict:
    by_version: dict[str, dict[str, dict]] = {}
    for bucket, row in aggregate(records).items():
        version, _, model = bucket.partition("|")
        if version != UNKNOWN_VERSION:
            by_version.setdefault(version, {})[model] = row
    ordered = sorted(by_version, key=version_key)
    window = [v for v in ordered if sum(r["records"] for r in by_version[v].values()) >= min_count]
    baseline = window[:-versions]
    newest = window[-1] if window else None

    def count(version: str, model: str, key: str) -> int:
        return by_version[version].get(model, {}).get("keys", {}).get(key, 0)

    def model_records(version: str, model: str) -> int:
        return by_version[version].get(model, {}).get("records", 0)

    changes: list[dict] = []
    series = sorted(
        {(m, k) for v in ordered for m, row in by_version[v].items() for k in row["keys"] if not k.startswith("invariant:")}
    )
    if newest is not None:
        earlier = ordered[: ordered.index(newest)]
        for model, key in series:
            if (
                count(newest, model, key) >= min_count
                and any(model in by_version[v] for v in earlier)
                and not any(count(v, model, key) for v in earlier)
            ):
                changes.append(
                    {"class": "new", "key": key, "model": model, "count": count(newest, model, key), "first_seen_version": newest}
                )
        for model, key in series:
            # Each model gets its own window: the versions where it has min_count records.
            model_window = [v for v in window if model_records(v, model) >= min_count]
            model_recent, model_baseline = model_window[-versions:], model_window[:-versions]
            if not model_baseline:
                continue
            seen = sum(count(v, model, key) for v in model_baseline)
            # Every version from the start of the recent window on, thin ones included: a key still
            # seen in any of them has not vanished.
            since_window = ordered[ordered.index(model_recent[0]) :]
            if seen >= min_count and not any(count(v, model, key) for v in since_window):
                last = max((v for v in ordered if count(v, model, key)), key=version_key)
                changes.append({"class": "vanished", "key": key, "model": model, "count": seen, "last_seen_version": last})
        for canary in canaries:
            population = canary.get("population") or f"record_type:{canary['record_type']}"
            pool = sum(row["keys"].get(population, 0) for row in by_version[newest].values())
            sessions = sum(
                1
                for r in records
                if any(b.partition("|")[0] == newest and _counts(keys).get(population) for b, keys in _rows(r).items())
            )
            if pool < min_count or sessions < session_floor:
                continue
            found = sum(row["keys"].get(canary["key"], 0) for row in by_version[newest].values())
            absent_expected = canary.get("expect", "present") == "absent"
            if (found >= min_count) if absent_expected else (found == 0):
                changes.append(
                    {"class": "canary-lost", "key": canary["key"], "model": None, "count": found, "feeds": list(canary["feeds"])}
                )
    unknown: Counter = Counter()
    for record in records:
        unknown_block = record.get("unknown")
        unknown.update(_counts(unknown_block.get("record_types") if isinstance(unknown_block, dict) else None))
    for kind, total in sorted(unknown.items()):
        seen_in = [v for v in ordered if any(count(v, m, f"record_type:{kind}") for m in by_version[v])]
        changes.append(
            {
                "class": "unknown-record-type",
                "key": kind,
                "model": None,
                "count": total,
                "last_seen_version": max(seen_in, key=version_key) if seen_in else None,
            }
        )
    return {
        "window": {"newest_version": newest, "baseline_versions": baseline, "min_count": min_count, "versions_n": versions},
        "counts": {cls: sum(c["class"] == cls for c in changes) for cls in CLASSES},
        "changes": changes,
        "degraded_metrics": sorted({m for c in changes if c["class"] == "canary-lost" for m in c["feeds"]}),
    }

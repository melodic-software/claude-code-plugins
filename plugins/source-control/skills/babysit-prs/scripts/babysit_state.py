#!/usr/bin/env python3
"""Durable queue-state storage for the babysit-prs engine.

Owns state-dir resolution (flag-only -- no environment fallback), the state
lock, atomic writes, corrupt-state quarantine, the persisted per-PR
projection, mutation-ledger merging, the scope-aware `save_state`, persistent
error quarantine, and cross-cycle sweep counters.
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
import time
from collections.abc import Callable, Iterable
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from babysit_util import (
    MIN_HEAD_SHA_PREFIX_LENGTH,
    is_json_object,
    json_array,
    json_object,
    parse_timestamp,
)

# Stamped by every writer; readers refuse a mismatch instead of guessing at a
# foreign layout. A state file from a different engine generation must be
# migrated deliberately, never reinterpreted silently.
STATE_SCHEMA_VERSION = 1
STATE_FILE_NAME = "queue-state.json"
# A PR that errors this many consecutive snapshot cycles is quarantined: its
# errors stop forcing the recommended cadence to "active" (they remain visible
# in the snapshot's error list) until the quarantine TTL lapses, at which point
# it gets a fresh chance to prove itself fixed.
ERROR_QUARANTINE_THRESHOLD = 3
ERROR_QUARANTINE_TTL_SECONDS = 24 * 60 * 60


def resolve_state_dir(value: str | None) -> Path:
    """Resolve the required --state-dir flag; flag-only by design.

    There is deliberately no environment fallback: a stray shell export must
    never silently redirect durable state. Empty and filesystem-root paths are
    hard errors -- both indicate a broken caller, and a root path would scatter
    lock/state files somewhere no one intends.
    """
    if value is None or not str(value).strip():
        raise ValueError("--state-dir is required and must not be empty")
    path = Path(str(value)).expanduser()
    resolved = path.resolve()
    if resolved.parent == resolved:
        raise ValueError(f"--state-dir must not be a filesystem root: {value}")
    return path


def state_path_for(state_dir: str | Path) -> Path:
    return Path(state_dir) / STATE_FILE_NAME


def _cold_state() -> dict[str, Any]:
    return {"schema_version": STATE_SCHEMA_VERSION, "prs": {}}


def quarantine_corrupt_state(path: Path) -> Path:
    """Move an unreadable state file to a timestamped `.corrupt` sibling."""
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    quarantine_path = path.with_name(f"{path.name}.{stamp}.corrupt")
    path.replace(quarantine_path)
    return quarantine_path


def load_state(path: Path) -> dict[str, Any]:
    """Load queue state, quarantining corruption and refusing foreign schemas.

    Corrupt JSON is moved aside (never deleted -- the bytes may matter for
    diagnosis) and the engine cold-starts loudly on stderr: silent data loss
    would masquerade as "every PR is new". A parseable file whose
    `schema_version` does not match raises instead -- unlike corruption, a
    foreign schema is intact data that a migration must handle deliberately.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return _cold_state()
    try:
        state = json.loads(text)
        if not is_json_object(state):
            raise ValueError("state root must be a JSON object")
    except ValueError:
        quarantine_path = quarantine_corrupt_state(path)
        print(
            f"WARNING: corrupt state file quarantined to {quarantine_path}; "
            "starting from a cold state (every PR will re-classify as new)",
            file=sys.stderr,
        )
        return _cold_state()
    version = state.get("schema_version")
    if version != STATE_SCHEMA_VERSION:
        raise RuntimeError(
            f"state file {path} has schema_version {version!r} but this engine "
            f"requires {STATE_SCHEMA_VERSION}; migrate or move the file before rerunning"
        )
    return state


@contextmanager
def state_lock(path: Path, timeout_seconds: float = 90.0) -> Any:
    """Serialize state transitions and outwait a default 60-second GitHub call."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_suffix(f"{path.suffix}.lock")
    handle = lock_path.open("a+b")
    handle.seek(0, os.SEEK_END)
    if handle.tell() == 0:
        handle.write(b"\0")
        handle.flush()

    deadline = time.monotonic() + timeout_seconds
    while True:
        try:
            handle.seek(0)
            if os.name == "nt":
                import msvcrt

                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except (BlockingIOError, OSError) as exc:
            if time.monotonic() >= deadline:
                handle.close()
                raise RuntimeError(
                    f"timed out waiting for state lock {lock_path}"
                ) from exc
            time.sleep(0.1)

    try:
        yield
    finally:
        handle.seek(0)
        if os.name == "nt":
            import msvcrt

            msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        handle.close()


def write_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(state, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def resolve_expected_head_sha(stored: str, provided: str) -> str:
    """Resolve an exact or unique-prefix --expected-head-sha to the stored SHA."""
    stored_sha = stored.strip().lower()
    provided_sha = provided.strip().lower()
    if not re.fullmatch(r"[0-9a-f]{40,64}", stored_sha):
        raise RuntimeError("stored snapshot head SHA is missing or malformed")
    if not re.fullmatch(
        rf"[0-9a-f]{{{MIN_HEAD_SHA_PREFIX_LENGTH},{len(stored_sha)}}}", provided_sha
    ):
        raise RuntimeError(
            f"--expected-head-sha must be the snapshot head SHA or a hex prefix of at least {MIN_HEAD_SHA_PREFIX_LENGTH} characters"
        )
    if not stored_sha.startswith(provided_sha):
        raise RuntimeError("snapshot head does not match --expected-head-sha")
    return stored_sha


def persisted_pr_state(pr: dict[str, Any]) -> dict[str, Any]:
    return {
        "head_sha": pr["head_sha"],
        "updated_at": pr["updated_at"],
        "is_draft": pr["is_draft"],
        "classification": pr["classification"],
        "author": pr["author"],
        "author_type": pr["author_type"],
        "merge_state": pr["merge_state"],
        "mergeable": pr["mergeable"],
        "human_stop": pr["human_stop"],
        "head_ref_uniqueness": pr["head_ref_uniqueness"],
        "mutation_policy": pr["mutation_policy"],
        "branch_freshness": pr["branch_freshness"],
        "branch_refresh": pr["branch_refresh"],
        "branch_refresh_history": pr["branch_refresh_history"],
        "review_trigger": pr["review_trigger"],
        "blocker_count": len(pr["blockers"]),
        "material_count": len(pr["material_findings"]),
        "blocking_feedback_ids": pr["feedback_ids"]["blocking"],
        "material_feedback_ids": pr["feedback_ids"]["material"],
        "human_feedback_ids": pr["feedback_ids"]["human"],
        "human_blocking_feedback_ids": pr["feedback_ids"]["human_blocking"],
        "checks_failing": list(pr["checks"]["failing"]),
        "checks_pending": list(pr["checks"]["pending"]),
        "checks_failing_identities": list(pr["checks"]["failing_identities"]),
        "checks_pending_identities": list(pr["checks"]["pending_identities"]),
        "last_worker_checkin_at": pr.get("last_worker_checkin_at") or "",
        "last_worker_checkin_head_sha": pr.get("last_worker_checkin_head_sha") or "",
        "pending_worker_dispatch_head_sha": pr.get("pending_worker_dispatch_head_sha")
        or "",
        "pending_worker_dispatch_unsuppressible": bool(
            pr.get("pending_worker_dispatch_unsuppressible")
        ),
        "pending_worker_dispatch_recorded_at": pr.get(
            "pending_worker_dispatch_recorded_at"
        )
        or "",
    }


def mutation_ledger_entry(pr: dict[str, Any]) -> dict[str, Any]:
    review_trigger = json_object(pr.get("review_trigger"))
    feedback_ids = json_object(pr.get("feedback_ids"))
    human_feedback_ids = json_array(
        pr.get("human_feedback_ids") or feedback_ids.get("human")
    )
    return {
        "branch_refresh_history": json_object(pr.get("branch_refresh_history")),
        "review_request_history": json_object(review_trigger.get("request_history")),
        "review_attempt_history": json_object(
            review_trigger.get("request_attempt_history")
        ),
        "seen_human_feedback_ids": list(human_feedback_ids),
    }


def merge_mutation_ledger_entry(
    existing: dict[str, Any], observed: dict[str, Any]
) -> dict[str, Any]:
    merged = dict(existing)
    for history_key in (
        "branch_refresh_history",
        "review_request_history",
        "review_attempt_history",
    ):
        observed_history = dict(observed.get(history_key) or {})
        if not observed_history:
            continue
        history = dict(merged.get(history_key) or {})
        history.update(observed_history)
        merged[history_key] = history
    seen_human_ids = {
        *merged.get("seen_human_feedback_ids", []),
        *observed.get("seen_human_feedback_ids", []),
    }
    if seen_human_ids:
        merged["seen_human_feedback_ids"] = sorted(seen_human_ids)
    return merged


def previous_with_ledger(
    previous: dict[str, Any] | None, ledger: dict[str, Any] | None
) -> dict[str, Any]:
    merged = dict(previous or {})
    entry = ledger or {}
    refresh_history = dict(merged.get("branch_refresh_history") or {})
    refresh_history.update(entry.get("branch_refresh_history") or {})
    merged["branch_refresh_history"] = refresh_history

    review_trigger = dict(merged.get("review_trigger") or {})
    request_history = dict(review_trigger.get("request_history") or {})
    request_history.update(entry.get("review_request_history") or {})
    attempt_history = dict(review_trigger.get("request_attempt_history") or {})
    attempt_history.update(entry.get("review_attempt_history") or {})
    review_trigger["request_history"] = request_history
    review_trigger["request_attempt_history"] = attempt_history
    merged["review_trigger"] = review_trigger
    merged["feedback_dispositions"] = dict(entry.get("feedback_dispositions") or {})
    merged["advisory_fix_rounds"] = dict(entry.get("advisory_fix_rounds") or {})
    checkin_fields = ("last_worker_checkin_at", "last_worker_checkin_head_sha")
    if any(field in entry for field in checkin_fields):
        merged["last_worker_checkin_at"] = str(
            entry.get("last_worker_checkin_at") or ""
        )
        merged["last_worker_checkin_head_sha"] = str(
            entry.get("last_worker_checkin_head_sha") or ""
        )
    merged["human_feedback_ids"] = sorted(
        {
            *merged.get("human_feedback_ids", []),
            *entry.get("seen_human_feedback_ids", []),
        }
    )
    return merged


def update_error_quarantine(
    previous_errors: Any,
    error_keys: Iterable[str],
    generated_at: str,
    *,
    threshold: int = ERROR_QUARANTINE_THRESHOLD,
    ttl_seconds: float = ERROR_QUARANTINE_TTL_SECONDS,
) -> tuple[dict[str, Any], set[str]]:
    """Advance per-PR error streaks and return the currently quarantined keys.

    Only the keys observed erroring THIS cycle stay in the map -- a cycle
    without an error breaks the streak. A key that has errored `threshold`
    consecutive cycles is quarantined until `ttl_seconds` after entry, so one
    persistently broken PR cannot pin the recommended cadence at "active"
    forever; when the TTL lapses the streak restarts from one, giving the PR a
    fresh chance to either recover or re-prove it is still broken.
    """
    now = parse_timestamp(generated_at)
    previous = json_object(previous_errors)
    records: dict[str, Any] = {}
    quarantined: set[str] = set()
    for key in error_keys:
        entry = json_object(previous.get(key))
        quarantined_until = parse_timestamp(entry.get("quarantined_until"))
        if quarantined_until is not None and now is not None and quarantined_until <= now:
            # Quarantine lapsed: restart the streak rather than resuming it, so
            # re-entry requires the same sustained evidence as first entry.
            entry = {}
            quarantined_until = None
        consecutive = int(entry.get("consecutive_errors") or 0) + 1
        record: dict[str, Any] = {
            "first_errored_at": str(entry.get("first_errored_at") or generated_at),
            "last_errored_at": generated_at,
            "consecutive_errors": consecutive,
        }
        if quarantined_until is None and consecutive >= threshold and now is not None:
            quarantined_until = now + timedelta(seconds=ttl_seconds)
        if quarantined_until is not None:
            record["quarantined_until"] = quarantined_until.isoformat()
            quarantined.add(key)
        records[key] = record
    return records, quarantined


def _repo_of_key(key: str) -> str:
    return key.rsplit("#", 1)[0].casefold()


def save_state(
    path: Path,
    snapshot: dict[str, Any],
    *,
    recommend_cadence: Callable[[list[str]], str],
    scope_repos: Iterable[str] | None = None,
    pr_errors: dict[str, Any] | None = None,
) -> None:
    """Persist a non-stale snapshot without dropping out-of-scope records.

    `recommend_cadence` is injected by the caller so this module never imports
    the delta engine. `scope_repos` names the repositories a `--repo`-scoped
    queue run actually discovered against: a complete scoped run replaces (and
    deletes stale records for) ONLY those repositories, leaving every other
    repository's records and ledger intact -- an unscoped complete queue run
    still replaces the whole map.

    The staleness guard is scope-aware for the same reason: it compares the
    snapshot's `generated_at` only against the last write that touched THIS
    run's scope, so two sessions scoped to disjoint repositories sharing one
    state file can interleave saves without livelocking each other into
    "state changed after this snapshot started".
    """
    with state_lock(path):
        current = load_state(path)
        generated = parse_timestamp(snapshot.get("generated_at"))
        current_prs = json_object(current.get("prs"))
        scope = (
            {repo.casefold() for repo in scope_repos} if scope_repos else None
        )
        mode = snapshot["mode"]
        snapshot_prs = [
            pr for pr in json_array(snapshot.get("prs")) if is_json_object(pr)
        ]
        if mode == "queue" and scope is None:
            in_scope_keys = set(current_prs)
        elif mode == "queue":
            in_scope_keys = {
                key for key in current_prs if _repo_of_key(key) in scope
            }
        else:
            in_scope_keys = {str(pr["key"]) for pr in snapshot_prs} & set(current_prs)

        stale_markers = [
            json_object(current_prs.get(key)).get("recorded_at")
            for key in in_scope_keys
        ]
        if mode == "queue" and scope is None:
            stale_markers.append(current.get("updated_at"))
        latest_in_scope = max(
            (
                stamp
                for stamp in (parse_timestamp(marker) for marker in stale_markers)
                if stamp is not None
            ),
            default=None,
        )
        if (
            latest_in_scope is not None
            and generated is not None
            and latest_in_scope > generated
        ):
            raise RuntimeError(
                "state changed after this snapshot started; rerun before writing state"
            )

        ledger = json_object(current.get("mutation_ledger"))
        for key, current_pr in current_prs.items():
            if not is_json_object(current_pr):
                continue
            existing = json_object(ledger.get(key))
            merged_entry = merge_mutation_ledger_entry(
                existing, mutation_ledger_entry(current_pr)
            )
            if merged_entry:
                ledger[key] = merged_entry

        # A complete sweep visited and classified every PR. The snapshot's own
        # `complete` flag already excludes advisory-only errors (a degraded
        # head-ref alias cross-check leaves per-PR state intact), so an
        # advisory-only run still advances the full sweep; deriving it from raw
        # `errors` here would wrongly hold the sweep back. The fallback keeps
        # callers that omit `complete` on the pre-split "no errors" meaning.
        complete_queue = mode == "queue" and snapshot.get(
            "complete", not snapshot["errors"]
        )
        if complete_queue and scope is None:
            prs: dict[str, Any] = {}
        elif complete_queue:
            prs = {
                key: value
                for key, value in current_prs.items()
                if key not in in_scope_keys
            }
        else:
            prs = current_prs
        for pr in snapshot_prs:
            record = persisted_pr_state(pr)
            record["recorded_at"] = snapshot["generated_at"]
            prs[pr["key"]] = record
        for pr in snapshot_prs:
            existing = json_object(ledger.get(pr["key"]))
            observed = mutation_ledger_entry(pr)
            merged_entry = merge_mutation_ledger_entry(existing, observed)
            if merged_entry:
                ledger[pr["key"]] = merged_entry
        cadence_blocking_errors = snapshot.get(
            "cadence_blocking_errors", snapshot["errors"]
        )
        persisted_cadence = (
            "active"
            if cadence_blocking_errors
            else recommend_cadence(
                [
                    str(pr.get("classification") or "quiet")
                    for pr in prs.values()
                    if is_json_object(pr)
                ]
            )
        )
        if complete_queue and scope is None:
            last_full_sweep_generated_at = str(snapshot["generated_at"])
            cycles_since_full_sweep = 0
        else:
            last_full_sweep_generated_at = str(
                current.get("last_full_sweep_generated_at") or ""
            )
            cycles_since_full_sweep = (
                int(current.get("cycles_since_full_sweep") or 0) + 1
            )
# An unscoped queue run owns the whole error map; scoped and single
        # runs replace only the keys they observed and preserve the rest.
        if mode == "queue" and scope is None:
            merged_errors: dict[str, Any] = {}
        elif mode == "queue":
            merged_errors = {
                key: value
                for key, value in json_object(current.get("pr_errors")).items()
                if _repo_of_key(key) not in scope
            }
        else:
            observed_keys = {str(pr["key"]) for pr in snapshot_prs} | set(
                pr_errors or {}
            )
            merged_errors = {
                key: value
                for key, value in json_object(current.get("pr_errors")).items()
                if key not in observed_keys
            }
        merged_errors.update(pr_errors or {})
        state = {
            **current,
            "schema_version": STATE_SCHEMA_VERSION,
            "updated_at": snapshot["generated_at"],
            "recommended_cadence": persisted_cadence,
            "prs": prs,
            "mutation_ledger": ledger,
            "pr_errors": merged_errors,
            "last_full_sweep_generated_at": last_full_sweep_generated_at,
            "cycles_since_full_sweep": cycles_since_full_sweep,
        }
        write_state(path, state)

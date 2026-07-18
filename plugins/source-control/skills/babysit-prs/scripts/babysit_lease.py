#!/usr/bin/env python3
"""Lease library for babysit queue and worker scopes.

Owns lease paths (including repo-scoped queue leases), acquire/heartbeat/
release/reap cores, stale-holder takeover, ownership checks, and the
snapshot<->lease scope-pairing validation. The lease CLI and every sibling
script that coordinates through leases import this module; none reimplement
any of it.
"""

from __future__ import annotations

import hashlib
import json
import secrets
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, cast

from babysit_gh import parse_repo, parse_repo_number
from babysit_state import state_lock, write_state
from babysit_util import parse_timestamp

DEFAULT_QUEUE_TTL_SECONDS = 3600
DEFAULT_WORKER_TTL_SECONDS = 5400

# The holder promises to heartbeat at least this often (see
# reference/orchestration.md). It matches the skill's tightest "active" cadence.
DEFAULT_HEARTBEAT_INTERVAL_SECONDS = 300
# A held-but-unexpired lease is reclaimable only after this many seconds without
# a heartbeat -- three missed intervals of margin, far below the TTL backstop, so
# a live run always refreshes before it can be mistaken for dead.
DEFAULT_STALE_TAKEOVER_SECONDS = 900
# Refuse a takeover threshold small enough to race a legitimately slow heartbeat.
MIN_STALE_TAKEOVER_SECONDS = 300


class LeaseHeldError(RuntimeError):
    """Raised when another unexpired lease owns the requested scope."""


def generate_lease_token() -> str:
    """Return a token that never starts with '-', which argparse would treat
    as an option in a space-separated `--token <value>`."""
    while True:
        token = secrets.token_urlsafe(24)
        if token[0].isalnum():
            return token


def normalize_scope_repos(value: Any) -> tuple[str, ...]:
    """Normalize a repo-scope argument (csv string or iterable) into a sorted,
    deduplicated tuple of validated, casefolded `owner/repo` keys."""
    if value is None:
        return ()
    if isinstance(value, str):
        raw = [part for part in value.split(",")]
    else:
        raw = [str(part) for part in value]
    repos = sorted({parse_repo(part) for part in raw if part.strip()})
    return tuple(repos)


def active_workers_dir(state_dir: str | Path) -> Path:
    return Path(state_dir) / "active-workers"


def queue_lock_name(repos: tuple[str, ...]) -> str:
    """Deterministic queue-lock filename for a repo scope.

    The empty scope is the legacy whole-owner-sweep lock: exactly one such run
    may hold it system-wide. A single-repo scope keys its own per-repo lock so
    sessions scoped to different repositories never contend. A multi-repo
    scope hashes its canonical sorted key list -- the filename only needs to
    be deterministic and collision-resistant; the lease record itself carries
    the authoritative scope for validation.
    """
    if not repos:
        return "queue-run-lock.json"
    if len(repos) == 1:
        owner, name = repos[0].split("/", 1)
        return f"queue-run-lock__{owner}__{name}.json"
    digest = hashlib.sha256(",".join(repos).encode("utf-8")).hexdigest()[:16]
    return f"queue-run-lock__scope-{digest}.json"


def lease_path(
    state_dir: str | Path,
    scope: str,
    pr: str | None,
    repos: tuple[str, ...] | str | None = None,
) -> Path:
    root = Path(state_dir)
    scope_repos = normalize_scope_repos(repos)
    if scope == "queue":
        if pr:
            raise ValueError("--pr is only valid with --scope worker")
        return root / queue_lock_name(scope_repos)
    if scope_repos:
        raise ValueError("--repo is only valid with --scope queue")
    if not pr:
        raise ValueError("--pr is required with --scope worker")
    repo, number = parse_repo_number(pr)
    owner, name = repo.split("/", 1)
    return active_workers_dir(root) / f"{owner}__{name}__pr-{number}.json"


def load_lease(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    if not isinstance(value, dict):
        raise RuntimeError(f"invalid lease object in {path}")
    return cast(dict[str, Any], value)


def lease_expiry(lease: dict[str, Any]) -> datetime:
    expiry = parse_timestamp(lease.get("expires_at"))
    if expiry is None:
        raise RuntimeError("existing lease has no valid expires_at")
    return expiry


def lease_scope_repos(lease: dict[str, Any]) -> tuple[str, ...]:
    """The repo scope a queue lease record carries; empty = whole-owner sweep."""
    value = lease.get("repos")
    if not isinstance(value, list):
        return ()
    return normalize_scope_repos(value)


def lease_is_stale(
    lease: dict[str, Any], now: datetime, stale_after_seconds: int
) -> bool:
    """Whether a held lease's holder is provably dead.

    A live holder heartbeats on its recorded cadence, advancing `updated_at`. A
    gap longer than `stale_after_seconds` therefore means the run died without
    releasing. Staleness must be *proven*: a missing or unparsable `updated_at`
    returns False so a genuinely-live scope is never stolen on bad data.

    The takeover window must also clear the *holder's* recorded
    `heartbeat_interval_seconds` -- the same invariant the CLI enforces between
    the stealer's own `--stale-after-seconds` and `--heartbeat-interval-seconds`
    at acquire time. Otherwise a holder that promised a slower cadence than this
    stealer's `stale_after_seconds` could be evicted before it has missed even
    one of its own heartbeats. When the window does not clear the holder's
    cadence death is unprovable, so the lease stays held until its TTL backstop
    expires and `acquire` frees it outright.
    """
    updated = parse_timestamp(lease.get("updated_at"))
    if updated is None:
        return False
    holder_interval = lease.get("heartbeat_interval_seconds")
    if not isinstance(holder_interval, int) or holder_interval <= 0:
        holder_interval = DEFAULT_HEARTBEAT_INTERVAL_SECONDS
    if stale_after_seconds <= holder_interval:
        return False
    return (now - updated).total_seconds() > stale_after_seconds


def require_owned_lease(path: Path, token: str | None) -> dict[str, Any]:
    if not token:
        raise ValueError("a lease token is required")
    current = load_lease(path)
    if not current:
        raise RuntimeError("lease does not exist")
    if lease_expiry(current) <= datetime.now(UTC):
        raise RuntimeError("lease has expired")
    if current.get("token") != token:
        raise LeaseHeldError("lease token does not match the current owner")
    return current


def write_lease(path: Path, lease: dict[str, Any]) -> None:
    write_state(path, lease)


def acquire(
    path: Path,
    scope: str,
    token: str | None,
    run_id: str | None,
    ttl_seconds: int,
    *,
    repos: tuple[str, ...] = (),
    steal_stale: bool = False,
    stale_after_seconds: int = DEFAULT_STALE_TAKEOVER_SECONDS,
    heartbeat_interval_seconds: int = DEFAULT_HEARTBEAT_INTERVAL_SECONDS,
) -> dict[str, Any]:
    now = datetime.now(UTC)
    current = load_lease(path)
    reclaimed_stale = False
    if current and lease_expiry(current) > now:
        if token and current.get("token") == token:
            # Re-acquiring our own live lease: keep its identity, extend the TTL.
            started_at = str(current.get("started_at") or now.isoformat())
            lease_token = token
            effective_run_id = run_id or current.get("run_id") or ""
        elif steal_stale and lease_is_stale(current, now, stale_after_seconds):
            # Provably dead holder: take over with a fresh token. Rotating the
            # token fences the evicted run -- its next heartbeat or release fails
            # the ownership check instead of mutating a scope it no longer holds.
            started_at = now.isoformat()
            lease_token = generate_lease_token()
            effective_run_id = run_id or ""
            reclaimed_stale = True
        else:
            raise LeaseHeldError(
                f"lease held until {current['expires_at']} by {current.get('run_id') or 'an unidentified nonce'}"
            )
    else:
        started_at = now.isoformat()
        lease_token = token or generate_lease_token()
        effective_run_id = run_id or (current or {}).get("run_id") or ""

    lease = {
        "version": 1,
        "scope": scope,
        "repos": list(repos or lease_scope_repos(current or {})),
        "token": lease_token,
        "run_id": effective_run_id,
        "started_at": started_at,
        "updated_at": now.isoformat(),
        "expires_at": (now + timedelta(seconds=ttl_seconds)).isoformat(),
        "heartbeat_interval_seconds": heartbeat_interval_seconds,
    }
    write_lease(path, lease)
    return {
        "action": "acquire",
        "acquired": True,
        "reclaimed_stale": reclaimed_stale,
        "path": str(path),
        **lease,
    }


def heartbeat(
    path: Path, token: str | None, run_id: str | None, ttl_seconds: int
) -> dict[str, Any]:
    if not token:
        raise ValueError("--token is required for heartbeat")
    current = require_owned_lease(path, token)
    now = datetime.now(UTC)
    current.update(
        {
            "run_id": run_id or current.get("run_id") or "",
            "updated_at": now.isoformat(),
            "expires_at": (now + timedelta(seconds=ttl_seconds)).isoformat(),
            "heartbeat_interval_seconds": current.get("heartbeat_interval_seconds")
            or DEFAULT_HEARTBEAT_INTERVAL_SECONDS,
        }
    )
    write_lease(path, current)
    return {
        "action": "heartbeat",
        "refreshed": True,
        "path": str(path),
        **current,
    }


def release(path: Path, token: str | None) -> dict[str, Any]:
    current = require_owned_lease(path, token)
    path.unlink(missing_ok=True)
    return {
        "action": "release",
        "released": True,
        "path": str(path),
        "scope": current.get("scope"),
        "token": token,
    }


def reap(
    state_dir: str | Path, *, apply: bool = False, now: datetime | None = None
) -> list[dict[str, Any]]:
    """Report, and with `apply=True` delete, worker leases past `expires_at`.

    A lease whose holder never released it (crashed, or the PR was merged/
    closed and nobody re-acquired that scope again) is left behind forever
    with a stale `expires_at` -- `acquire` already treats it as free to take
    over, but nothing ever removes the dead file, so `active-workers/`
    accumulates garbage indefinitely. This reaps it.

    Dry-run by default: with `apply=False` this only reports which files are
    expired and would be reaped; nothing is deleted until `apply=True`.

    Each candidate is re-read and re-checked under its own `state_lock` --
    the same lock `acquire`/`heartbeat`/`release` hold for that file -- with
    the unlink (when applying) still inside that lock. A concurrent
    `acquire` (which writes a fresh, unexpired lease under the same lock)
    can therefore never be raced: either it runs first and this reap sees
    the renewed lease and skips it, or it blocks on the lock until this
    reap has decided (and, if expired and applying, already deleted the old
    file) and then proceeds exactly like acquiring a scope with no current
    holder.
    """
    directory = active_workers_dir(state_dir)
    if not directory.is_dir():
        return []
    results: list[dict[str, Any]] = []
    for path in sorted(directory.glob("*.json")):
        with state_lock(path):
            current = load_lease(path)
            if current is None:
                # Already released or reaped by a concurrent run.
                continue
            try:
                expiry = lease_expiry(current)
            except RuntimeError:
                # Never guess at an unparsable expiry; leave it for a human.
                results.append(
                    {
                        "path": str(path),
                        "reaped": False,
                        "reason": "invalid expires_at",
                        "scope": current.get("scope"),
                        "run_id": current.get("run_id"),
                        "expires_at": current.get("expires_at"),
                    }
                )
                continue
            check_time = now if now is not None else datetime.now(UTC)
            if expiry > check_time:
                results.append(
                    {
                        "path": str(path),
                        "reaped": False,
                        "reason": "not expired",
                        "expires_at": current.get("expires_at"),
                    }
                )
                continue
            if not apply:
                results.append(
                    {
                        "path": str(path),
                        "reaped": False,
                        "reason": "expired; dry run (pass --apply to reap)",
                        "scope": current.get("scope"),
                        "run_id": current.get("run_id"),
                        "expires_at": current.get("expires_at"),
                    }
                )
                continue
            path.unlink(missing_ok=True)
            results.append(
                {
                    "path": str(path),
                    "reaped": True,
                    "scope": current.get("scope"),
                    "run_id": current.get("run_id"),
                    "expires_at": current.get("expires_at"),
                }
            )
    return results


def validate_snapshot_scope(
    state_dir: str | Path,
    repos: tuple[str, ...] | str | None,
    token: str | None = None,
) -> None:
    """Validate that a repo-scoped snapshot run pairs with its queue lease.

    The lease record carries its scope, so a scoped snapshot can prove it is
    running under the lease that was actually acquired for the SAME repo set:
    a mismatch means two sessions believe they own different slices of the
    same lock file, or a caller passed different `--repo` values to the lease
    and the snapshot. With a `token` the lease must also exist, be unexpired,
    and be owned by that token; without one, an absent lease is fine (lease
    use is opt-in) but a present lease must still record the identical scope.
    """
    scope_repos = normalize_scope_repos(repos)
    path = lease_path(state_dir, "queue", None, repos=scope_repos)
    lease = load_lease(path)
    if lease is None:
        if token:
            raise RuntimeError(
                f"no queue lease found at {path} for this repo scope; acquire one "
                "with the same --repo value before passing --lease-token"
            )
        return
    recorded = lease_scope_repos(lease)
    if recorded != scope_repos:
        raise RuntimeError(
            f"queue lease at {path} records scope {list(recorded)} but this run "
            f"is scoped to {list(scope_repos)}; acquire a lease with the same "
            "--repo value"
        )
    if token:
        require_owned_lease(path, token)

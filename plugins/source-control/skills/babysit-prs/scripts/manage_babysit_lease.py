#!/usr/bin/env python3
"""Atomically acquire, refresh, or release babysit queue and worker leases."""

from __future__ import annotations

import argparse
import json
import sys

import babysit_lease as leases
from babysit_state import resolve_state_dir, state_lock
from babysit_util import configure_stdio


def run(args: argparse.Namespace) -> dict:
    state_dir = resolve_state_dir(args.state_dir)
    if args.action == "reap":
        results = leases.reap(state_dir, apply=args.apply)
        return {
            "action": "reap",
            "state_dir": str(state_dir),
            "apply": args.apply,
            "reaped_count": sum(1 for row in results if row.get("reaped")),
            "results": results,
        }
    repos = leases.normalize_scope_repos(args.repo)
    path = leases.lease_path(state_dir, args.scope, args.pr, repos=repos)
    ttl_seconds = args.ttl_seconds or (
        leases.DEFAULT_QUEUE_TTL_SECONDS
        if args.scope == "queue"
        else leases.DEFAULT_WORKER_TTL_SECONDS
    )
    if ttl_seconds < 60:
        raise ValueError("--ttl-seconds must be at least 60")
    if args.steal_stale:
        if args.stale_after_seconds < leases.MIN_STALE_TAKEOVER_SECONDS:
            raise ValueError(
                f"--stale-after-seconds must be at least {leases.MIN_STALE_TAKEOVER_SECONDS}"
            )
        if args.stale_after_seconds <= args.heartbeat_interval_seconds:
            raise ValueError(
                "--stale-after-seconds must exceed --heartbeat-interval-seconds so a "
                + "live heartbeat always refreshes the lease before it looks stale"
            )
    with state_lock(path):
        if args.action == "acquire":
            return leases.acquire(
                path,
                args.scope,
                args.token,
                args.run_id,
                ttl_seconds,
                repos=repos,
                steal_stale=args.steal_stale,
                stale_after_seconds=args.stale_after_seconds,
                heartbeat_interval_seconds=args.heartbeat_interval_seconds,
            )
        if args.action == "heartbeat":
            return leases.heartbeat(path, args.token, args.run_id, ttl_seconds)
        return leases.release(path, args.token)


def main() -> int:
    configure_stdio()
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("action", choices=("acquire", "heartbeat", "release", "reap"))
    parser.add_argument(
        "--scope",
        choices=("queue", "worker"),
        help="required for acquire, heartbeat, and release; unused by reap",
    )
    parser.add_argument("--pr", help="PR URL or owner/repo#number for worker scope")
    parser.add_argument(
        "--repo",
        default=None,
        help=(
            "Comma-separated owner/repo list to scope a queue lease to specific "
            "repositories, so parallel queue runs on different repositories "
            "never contend. Pass the same value as pr_queue_snapshot.py's "
            "--repo so the two scopes pair. Omit only for the legacy single "
            "system-wide whole-owner-sweep lock."
        ),
    )
    parser.add_argument("--token", help="opaque token returned by acquire")
    parser.add_argument("--run-id", help="task/run identifier for diagnostics")
    parser.add_argument("--ttl-seconds", type=int, default=0)
    parser.add_argument(
        "--steal-stale",
        action="store_true",
        help=(
            "acquire only: reclaim an unexpired lease whose holder has not "
            "heartbeat within --stale-after-seconds (a provably dead run). A "
            "still-fresh lease is refused with exit 3 as usual."
        ),
    )
    parser.add_argument(
        "--stale-after-seconds",
        type=int,
        default=leases.DEFAULT_STALE_TAKEOVER_SECONDS,
        help=(
            "heartbeat-staleness threshold that makes a lease reclaimable by "
            f"--steal-stale (default {leases.DEFAULT_STALE_TAKEOVER_SECONDS})."
        ),
    )
    parser.add_argument(
        "--heartbeat-interval-seconds",
        type=int,
        default=leases.DEFAULT_HEARTBEAT_INTERVAL_SECONDS,
        help=(
            "cadence the holder promises to heartbeat at; recorded in the lease "
            f"(default {leases.DEFAULT_HEARTBEAT_INTERVAL_SECONDS})."
        ),
    )
    parser.add_argument(
        "--state-dir",
        required=True,
        help=(
            "Durable state directory. Required: state-dir resolution is "
            "flag-only, with no environment fallback."
        ),
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help=(
            "reap only: actually delete expired worker lease files (default: "
            "dry run, report which files are expired without deleting them)."
        ),
    )
    args = parser.parse_args()
    if args.action != "reap" and not args.scope:
        parser.error("--scope is required for acquire, heartbeat, and release")
    try:
        print(json.dumps(run(args), indent=2, sort_keys=True))
    except leases.LeaseHeldError as exc:
        print(f"HELD: {exc}", file=sys.stderr)
        return 3
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

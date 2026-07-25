#!/usr/bin/env python3
"""Record guarded feedback dispositions, advisory fix rounds, and worker
check-ins for one PR."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, cast

import babysit_delta as delta
import babysit_lease as leases
from babysit_gh import parse_repo_number
from babysit_state import (
    load_state,
    resolve_expected_head_sha,
    resolve_state_dir,
    state_lock,
    state_path_for,
    write_state,
)
from babysit_util import MIN_HEAD_SHA_PREFIX_LENGTH, configure_stdio, is_json_object


def require_worker_lease(
    args: argparse.Namespace, state_dir: Path, repo: str, number: int
) -> None:
    if not args.apply:
        return
    path = leases.lease_path(state_dir, "worker", f"{repo}#{number}")
    with state_lock(path):
        leases.require_owned_lease(path, getattr(args, "lease_token", None))


def dispose(
    args: argparse.Namespace,
    key: str,
    pr_state: dict[str, Any],
    ledger_entry: dict[str, Any],
    head_sha: str,
) -> dict[str, Any]:
    known_ids: set[Any] = {
        *(pr_state.get("blocking_feedback_ids") or []),
        *(pr_state.get("material_feedback_ids") or []),
    }
    if args.feedback_id not in known_ids:
        raise RuntimeError(
            f"feedback id is not a blocking or material bot feedback id in the stored snapshot for {key}; re-run 'pr_queue_snapshot.py --pr {key} --write-state' first"
        )
    dispositions = dict(ledger_entry.get("feedback_dispositions") or {})
    existing = dispositions.get(args.feedback_id)
    # Scoped to the CURRENT head, mirroring `pr_queue_snapshot.py`'s own
    # `dispositions_at_current_head` read of this same map: a disposition
    # recorded for this id at an OLDER head does not cover a bot's reuse of
    # that id for genuinely different content at a new head (`classify_pr`
    # already dispatches a fresh worker for that reuse via
    # `new_material_feedback`'s head-scoped escape valve). Rejecting a
    # same-id-different-head dispose here would leave that reused id
    # permanently undisposable -- re-arming `quiet_recheck_due` forever
    # instead of letting the worker record its current-head triage. Only a
    # disposition already recorded at this exact head blocks a duplicate.
    if is_json_object(existing) and existing.get("head_sha") == head_sha:
        raise RuntimeError(
            "feedback id already has a recorded disposition at this head"
        )
    record = {
        "pr": key,
        "feedback_id": args.feedback_id,
        "disposed_at": datetime.now(UTC).isoformat(),
        "reason": args.reason,
        "head_sha": head_sha,
    }
    result = {"action": "dispose", "eligible": True, "record": record}
    if not args.apply:
        return result
    dispositions[args.feedback_id] = record
    ledger_entry["feedback_dispositions"] = dispositions
    return {**result, "recorded": True}


def record_advisory_round(
    args: argparse.Namespace,
    key: str,
    ledger_entry: dict[str, Any],
    head_sha: str,
) -> dict[str, Any]:
    advisory = dict(ledger_entry.get("advisory_fix_rounds") or {})
    rounds = dict(advisory.get("rounds") or {})
    if head_sha in rounds:
        raise RuntimeError(
            "an advisory fix round is already recorded for this head SHA"
        )
    if len(rounds) >= args.fix_round_cap:
        raise RuntimeError(
            f"advisory fix-round cap ({args.fix_round_cap}) reached for {key}; new advisory findings are report-only pending user decision"
        )
    recorded_at = datetime.now(UTC).isoformat()
    result = {
        "action": "record-advisory-round",
        "eligible": True,
        "count_after": len(rounds) + 1,
        "cap": args.fix_round_cap,
        "cap_reached_after": len(rounds) + 1 >= args.fix_round_cap,
    }
    if not args.apply:
        return result
    rounds[head_sha] = {"recorded_at": recorded_at}
    ledger_entry["advisory_fix_rounds"] = {
        "count": len(rounds),
        "updated_at": recorded_at,
        "rounds": rounds,
    }
    return {**result, "recorded": True}


def record_worker_checkin(
    args: argparse.Namespace,
    ledger_entry: dict[str, Any],
    head_sha: str,
) -> dict[str, Any]:
    checked_in_at = datetime.now(UTC).isoformat()
    result = {
        "action": "record-worker-checkin",
        "eligible": True,
        "checked_in_at": checked_in_at,
        "head_sha": head_sha,
    }
    if not args.apply:
        return result
    ledger_entry["last_worker_checkin_at"] = checked_in_at
    ledger_entry["last_worker_checkin_head_sha"] = head_sha
    return {**result, "recorded": True}


def run(args: argparse.Namespace) -> dict[str, Any]:
    state_dir = resolve_state_dir(args.state_dir)
    state_path = state_path_for(state_dir)
    with state_lock(state_path):
        return run_locked(args, state_dir, state_path)


def run_locked(
    args: argparse.Namespace, state_dir: Path, state_path: Path
) -> dict[str, Any]:
    repo, number = parse_repo_number(args.pr)
    key = f"{repo}#{number}"
    require_worker_lease(args, state_dir, repo, number)
    state = load_state(state_path)
    pr_state_value: Any = cast(Any, state.get("prs") or {}).get(key)
    if not isinstance(pr_state_value, dict):
        raise RuntimeError(f"missing snapshot state for {key}; run --write-state first")
    pr_state = cast(dict[str, Any], pr_state_value)
    head_sha = resolve_expected_head_sha(
        str(pr_state.get("head_sha") or ""), args.expected_head_sha
    )
    ledger_entry = cast(
        dict[str, Any], state.setdefault("mutation_ledger", {}).setdefault(key, {})
    )
    if args.action == "dispose":
        result = dispose(args, key, pr_state, ledger_entry, head_sha)
    elif args.action == "record-advisory-round":
        result = record_advisory_round(args, key, ledger_entry, head_sha)
    else:
        result = record_worker_checkin(args, ledger_entry, head_sha)
    if args.apply:
        state["updated_at"] = datetime.now(UTC).isoformat()
        write_state(state_path, state)
    return {"key": key, "head_sha": head_sha, "apply": args.apply, **result}


def main() -> int:
    configure_stdio()
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument(
        "action",
        choices=("dispose", "record-advisory-round", "record-worker-checkin"),
    )
    parser.add_argument("--pr", required=True, help="PR URL or owner/repo#number")
    parser.add_argument(
        "--expected-head-sha",
        required=True,
        help=(
            "snapshot head SHA, full or a hex prefix of at least "
            f"{MIN_HEAD_SHA_PREFIX_LENGTH} characters"
        ),
    )
    parser.add_argument(
        "--feedback-id",
        help="snapshot feedback id to dispose, verbatim (e.g. comment:123456789)",
    )
    parser.add_argument(
        "--reason",
        help="dispose triage outcome, typically approval, stale, or non-actionable",
    )
    parser.add_argument(
        "--state-dir",
        required=True,
        help=(
            "Durable state directory. Required: state-dir resolution is "
            "flag-only, with no environment fallback."
        ),
    )
    parser.add_argument("--lease-token", help="opaque token for this PR's worker lease")
    parser.add_argument(
        "--apply", action="store_true", help="record the guarded ledger entry"
    )
    parser.add_argument(
        "--fix-round-cap",
        type=int,
        default=delta.ADVISORY_FIX_ROUND_CAP,
        help=(
            "Advisory fix-round cap before new advisory findings are report-only "
            f"(default {delta.ADVISORY_FIX_ROUND_CAP})."
        ),
    )
    args = parser.parse_args()
    if args.action == "dispose" and not (args.feedback_id and args.reason):
        parser.error("dispose requires --feedback-id and --reason")
    if args.action != "dispose" and (args.feedback_id or args.reason):
        parser.error("--feedback-id and --reason are only valid with dispose")
    try:
        print(json.dumps(run(args), indent=2, sort_keys=True))
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

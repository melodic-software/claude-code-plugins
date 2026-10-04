#!/usr/bin/env python3
"""Record guarded feedback dispositions, advisory fix rounds, check reruns,
and worker check-ins for one PR."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, cast

import babysit_delta as delta
from babysit_checks import RERUN_ID_LENGTH, check_identity_key, check_rerun_id
from babysit_state import (
    FLAKE_RERUN_CAP,
    FlakeCapReached,
    record_rerun as record_check_rerun,
    resolve_state_dir,
    rerun_count,
    state_lock,
    state_path_for,
    write_state,
)
from guarded_mutation import begin_guarded_mutation
from babysit_util import MIN_HEAD_SHA_PREFIX_LENGTH, configure_stdio, is_json_object

RERUN_ID_PATTERN = re.compile(f"[0-9a-f]{{{RERUN_ID_LENGTH}}}")
# Distinct from 2 (argument and every other refusal) so a caller can tell the
# flake cap firing from a refusal it should fix and retry.
EXIT_FLAKE_CAP = 4


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
    finding_classes = {
        name: args.finding_class.count(name) for name in delta.ADVISORY_ROUND_CLASSES
    }
    # The ledger serializes with sorted keys and timestamps can tie, so an
    # explicit monotonic sequence is the only chronology that survives a
    # reload (`ordered_advisory_rounds` sorts by it).
    sequence = 1 + max(
        (delta.advisory_round_sequence(record) for record in rounds.values()),
        default=0,
    )
    record = {
        "recorded_at": recorded_at,
        "sequence": sequence,
        "finding_classes": finding_classes,
    }
    result = {
        "action": "record-advisory-round",
        "eligible": True,
        "count_after": len(rounds) + 1,
        "cap": args.fix_round_cap,
        "cap_reached_after": len(rounds) + 1 >= args.fix_round_cap,
        "finding_classes": finding_classes,
        "composition": delta.advisory_round_composition(record),
        # Reported on the dry run too, so a caller can see what recording this
        # round would arm before it writes.
        "non_convergence_tripwire": delta.advisory_non_convergence_tripwire(
            {**rounds, head_sha: record}
        ),
    }
    if not args.apply:
        return result
    rounds[head_sha] = record
    ledger_entry["advisory_fix_rounds"] = {
        "count": len(rounds),
        "updated_at": recorded_at,
        "rounds": rounds,
    }
    return {**result, "recorded": True}


def record_rerun(
    args: argparse.Namespace,
    key: str,
    mutation_ledger: dict[str, Any],
    pr_state: dict[str, Any],
    head_sha: str,
) -> dict[str, Any]:
    # The id is recomputed from each stored triple rather than read from a
    # stored `rerun_id`, so a snapshot written before ids existed still resolves.
    matches = [
        identity
        for identity in pr_state.get("checks_failing_identities") or []
        if is_json_object(identity) and check_rerun_id(identity) == args.check_id
    ]
    if not matches:
        raise RuntimeError(
            f"--check-id is not a failing check in the stored snapshot for {key}; re-run 'pr_queue_snapshot.py --pr {key} --write-state' first"
        )
    if len({check_identity_key(identity) for identity in matches}) > 1:
        raise RuntimeError(
            f"--check-id matches more than one failing check in the stored snapshot for {key}; report it, do not record a rerun"
        )
    check = {
        field: str(matches[0].get(field) or "")
        for field in ("type", "name", "workflow_name")
    }
    count_before = rerun_count(mutation_ledger, key, head_sha, check)
    # A dry run records into a scratch copy, so it refuses at the cap exactly as
    # the write would.
    target = mutation_ledger if args.apply else json.loads(json.dumps(mutation_ledger))
    count_after = record_check_rerun(
        target, key, head_sha, check, recorded_at=datetime.now(UTC).isoformat()
    )
    result = {
        "action": "record-rerun",
        "eligible": True,
        "check": check,
        "count_before": count_before,
        "count_after": count_after,
        "cap": FLAKE_RERUN_CAP,
    }
    return {**result, "recorded": True} if args.apply else result


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
    opened = begin_guarded_mutation(args, state_dir, state_path)
    key, state, pr_state, head_sha = (
        opened.key,
        opened.state,
        opened.pr_state,
        opened.head_sha,
    )
    ledger_entry = cast(
        dict[str, Any], state.setdefault("mutation_ledger", {}).setdefault(key, {})
    )
    if args.action == "dispose":
        result = dispose(args, key, pr_state, ledger_entry, head_sha)
    elif args.action == "record-advisory-round":
        result = record_advisory_round(args, key, ledger_entry, head_sha)
    elif args.action == "record-rerun":
        result = record_rerun(args, key, state["mutation_ledger"], pr_state, head_sha)
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
        choices=(
            "dispose",
            "record-advisory-round",
            "record-rerun",
            "record-worker-checkin",
        ),
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
        "--finding-class",
        action="append",
        choices=delta.ADVISORY_ROUND_CLASSES,
        default=[],
        help=(
            "provenance class of ONE finding in this advisory round, repeated once "
            "per finding: a (genuine duplicate), b (new and distinct), c "
            "(self-inflicted). Required for record-advisory-round."
        ),
    )
    parser.add_argument(
        "--check-id",
        help=(
            "record-rerun: the failing check's rerun_id from the snapshot's "
            f"checks.failing_identities ({RERUN_ID_LENGTH} lowercase hex characters)"
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
    if args.action == "record-advisory-round" and not args.finding_class:
        parser.error(
            "record-advisory-round requires --finding-class once per finding in the "
            "round; an unclassified round leaves the second-consecutive-all-(c) "
            "non-convergence tripwire nothing to read after context rollover"
        )
    if args.action != "record-advisory-round" and args.finding_class:
        parser.error("--finding-class is only valid with record-advisory-round")
    if args.action == "record-rerun" and args.check_id is None:
        parser.error("record-rerun requires --check-id")
    if args.action != "record-rerun" and args.check_id is not None:
        parser.error("--check-id is only valid with record-rerun")
    if args.check_id is not None and not RERUN_ID_PATTERN.fullmatch(args.check_id):
        parser.error(
            f"--check-id must be {RERUN_ID_LENGTH} lowercase hex characters, "
            "the rerun_id the snapshot lists"
        )
    try:
        print(json.dumps(run(args), indent=2, sort_keys=True))
    except FlakeCapReached as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_FLAKE_CAP
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Request one guarded default-merge refresh for a behind PR branch."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, cast

import babysit_lease as leases
from babysit_delta import compute_branch_freshness, head_repository_scope
from babysit_feedback import fetch_current_human_stop
from babysit_gh import (
    find_open_prs_for_head_ref,
    gh_json,
    parse_repo_number,
    view_pr,
)
from babysit_state import (
    load_state,
    resolve_expected_head_sha,
    resolve_state_dir,
    state_lock,
    state_path_for,
    write_state,
)
from babysit_util import MIN_HEAD_SHA_PREFIX_LENGTH, configure_stdio, json_object


def allowed_owners_from_policy(policy: dict[str, Any]) -> frozenset[str]:
    """Rebuild the owner allowlist the snapshot already blessed for this PR.

    The snapshot computed and stored `mutation_policy` under the configured
    watched-owner set, and this run only reaches the live re-check after the
    stored policy proved the head writable -- so the base and head owners it
    recorded were both inside that set. Re-deriving `head_repository_scope` on
    the LIVE PR against exactly those two owners re-checks archived-status,
    head-metadata, and head-owner drift without re-importing any ambient owner
    configuration; deriving the allowlist from the live PR's own owners instead
    would make it trivially true and detect no drift at all.
    """
    owners = {str(policy.get(key) or "") for key in ("base_owner", "head_owner")}
    return frozenset(owner for owner in owners if owner)


def validate_current_candidate(
    repo: str, number: int, expected_head_sha: str, allowed_owners: frozenset[str]
) -> dict[str, Any]:
    current = view_pr(repo, number)
    if str(current.get("state") or "").upper() != "OPEN":
        raise RuntimeError("PR is no longer open")
    current_policy = head_repository_scope(current, allowed_owners)
    if (
        not current_policy["head_metadata_complete"]
        or not current_policy["branch_write_allowed"]
    ):
        raise RuntimeError("current PR head repository is outside branch-write scope")
    if current.get("headRefOid") != expected_head_sha:
        raise RuntimeError("PR head changed after the snapshot")
    if str(current.get("mergeable") or "").upper() == "CONFLICTING":
        raise RuntimeError("PR has a merge conflict; refusing branch refresh")
    if compute_branch_freshness(current)["state"] != "behind":
        raise RuntimeError("PR is no longer behind its base branch")
    if fetch_current_human_stop(repo, number, current)["required"]:
        raise RuntimeError("human review stop is active; refusing branch refresh")
    matching_prs = find_open_prs_for_head_ref(current)
    if matching_prs != [f"{repo}#{number}"]:
        raise RuntimeError(
            "head branch is shared or its uniqueness could not be verified"
        )
    return current


def require_worker_lease(
    args: argparse.Namespace,
    state_dir: Path,
    repo: str,
    number: int,
    *,
    renew: bool = False,
) -> None:
    if not args.apply:
        return
    path = leases.lease_path(state_dir, "worker", f"{repo}#{number}")
    with state_lock(path):
        token = getattr(args, "lease_token", None)
        if renew:
            leases.heartbeat(path, token, None, leases.DEFAULT_WORKER_TTL_SECONDS)
        else:
            leases.require_owned_lease(path, token)


def run(args: argparse.Namespace) -> dict[str, object]:
    state_dir = resolve_state_dir(args.state_dir)
    state_path = state_path_for(state_dir)
    with state_lock(state_path):
        return run_locked(args, state_dir, state_path)


def run_locked(
    args: argparse.Namespace, state_dir: Path, state_path: Path
) -> dict[str, object]:
    repo, number = parse_repo_number(args.pr)
    key = f"{repo}#{number}"
    require_worker_lease(args, state_dir, repo, number)
    state = load_state(state_path)
    pr_state_value: Any = cast(Any, state.get("prs") or {}).get(key)
    if not isinstance(pr_state_value, dict):
        raise RuntimeError(f"missing snapshot state for {key}; run --write-state first")
    pr_state = cast(dict[str, Any], pr_state_value)
    expected_head_sha = resolve_expected_head_sha(
        str(pr_state.get("head_sha") or ""), args.expected_head_sha
    )
    if str(pr_state.get("mergeable") or "").upper() == "CONFLICTING":
        raise RuntimeError("snapshot classifies the PR as conflicting")
    if json_object(pr_state.get("branch_freshness")).get("state") != "behind":
        raise RuntimeError(
            f"snapshot does not classify the PR as behind its base branch; re-run 'pr_queue_snapshot.py --pr {key} --write-state' to refresh the stored state, then retry"
        )
    snapshot_policy = json_object(pr_state.get("mutation_policy"))
    if not snapshot_policy.get("head_metadata_complete") or not snapshot_policy.get(
        "branch_write_allowed"
    ):
        raise RuntimeError("snapshot does not allow writes to this PR head repository")
    if json_object(pr_state.get("human_stop")).get("required"):
        raise RuntimeError("snapshot has an active human review stop")
    uniqueness = json_object(pr_state.get("head_ref_uniqueness"))
    if not uniqueness.get("checked") or not uniqueness.get("unique"):
        raise RuntimeError("snapshot does not prove that the head branch is unique")
    allowed_owners = allowed_owners_from_policy(snapshot_policy)

    prior = json_object(pr_state.get("branch_refresh"))
    ledger = cast(dict[str, Any], state.setdefault("mutation_ledger", {}))
    ledger_entry = cast(dict[str, Any], ledger.setdefault(key, {}))
    history = json_object(pr_state.get("branch_refresh_history"))
    history.update(json_object(ledger_entry.get("branch_refresh_history")))
    if expected_head_sha in history:
        raise RuntimeError("a refresh was already attempted for this source SHA")
    if prior.get("requested_source_sha") == expected_head_sha:
        raise RuntimeError("a refresh was already requested for this source SHA")

    validate_current_candidate(repo, number, expected_head_sha, allowed_owners)

    result: dict[str, object] = {
        "key": key,
        "expected_head_sha": expected_head_sha,
        "apply": args.apply,
        "eligible": True,
    }
    if not args.apply:
        return result

    requested_at = datetime.now(UTC).isoformat()
    record = {
        "requested_source_sha": expected_head_sha,
        "requested_at": requested_at,
        "status": "requesting",
    }
    pr_state["branch_refresh"] = record
    history[expected_head_sha] = record
    pr_state["branch_refresh_history"] = history
    ledger_entry["branch_refresh_history"] = history
    state["updated_at"] = requested_at
    write_state(state_path, state)

    try:
        validate_current_candidate(repo, number, expected_head_sha, allowed_owners)
        require_worker_lease(args, state_dir, repo, number, renew=True)
        response = gh_json(
            [
                "api",
                "--method",
                "PUT",
                f"repos/{repo}/pulls/{number}/update-branch",
                "-f",
                f"expected_head_sha={expected_head_sha}",
            ]
        )
    except Exception as exc:
        failed_at = datetime.now(UTC).isoformat()
        record.update({"status": "failed", "failed_at": failed_at, "error": str(exc)})
        state["updated_at"] = failed_at
        write_state(state_path, state)
        raise

    accepted_at = datetime.now(UTC).isoformat()
    record.update(
        {"status": "accepted", "accepted_at": accepted_at, "response": response}
    )
    state["updated_at"] = accepted_at
    write_state(state_path, state)
    result.update({"requested": True, **record})
    return result


def main() -> int:
    configure_stdio()
    parser = argparse.ArgumentParser(description=__doc__)
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
        "--state-dir",
        required=True,
        help=(
            "Durable state directory. Required: state-dir resolution is "
            "flag-only, with no environment fallback."
        ),
    )
    parser.add_argument("--lease-token", help="opaque token for this PR's worker lease")
    parser.add_argument(
        "--apply", action="store_true", help="request the guarded branch update"
    )
    args = parser.parse_args()
    try:
        print(json.dumps(run(args), indent=2, sort_keys=True))
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

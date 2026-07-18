#!/usr/bin/env python3
"""Status-check rollup classification: state enums, normalization, dedupe,
durable identities, and the generic rollup classifier.

The identity keying defined here is the single source both the snapshot engine
and the guarded merge gate use, so a StatusContext can never hide -- or be
hidden by -- a same-named CheckRun.
"""

from __future__ import annotations

from typing import Any

from babysit_util import is_json_array, is_json_object, json_array

CHECK_FAILURE_STATES = {
    "ACTION_REQUIRED",
    "CANCELLED",
    "ERROR",
    "FAILURE",
    "STALE",
    "STARTUP_FAILURE",
    "TIMED_OUT",
}
CHECK_SUCCESS_STATES = {"NEUTRAL", "SKIPPED", "SUCCESS"}
CHECK_PENDING_STATES = {
    "EXPECTED",
    "IN_PROGRESS",
    "PENDING",
    "QUEUED",
    "REQUESTED",
    "WAITING",
}


def check_category(state: str) -> str:
    if state in CHECK_FAILURE_STATES:
        return "failing"
    if state in CHECK_SUCCESS_STATES:
        return "success"
    if state in CHECK_PENDING_STATES or not state:
        return "pending"
    return "pending"


def normalize_check(check: dict[str, Any]) -> dict[str, Any]:
    typename = str(check.get("__typename") or "Unknown")
    name = str(
        check.get("name")
        or check.get("context")
        or check.get("workflowName")
        or "check"
    )
    status = str(check.get("status") or "").upper()
    conclusion = str(check.get("conclusion") or "").upper()
    context_state = str(check.get("state") or "").upper()

    if typename == "StatusContext":
        effective_state = context_state
    elif typename == "CheckRun":
        effective_state = conclusion or status
    else:
        effective_state = context_state or conclusion or status

    sort_key = str(
        check.get("completedAt")
        or check.get("startedAt")
        or check.get("createdAt")
        or ""
    )

    return {
        "name": name,
        "type": typename,
        "category": check_category(effective_state),
        "effective_state": effective_state,
        "status": status,
        "conclusion": conclusion,
        "state": context_state,
        "details_url": str(check.get("detailsUrl") or ""),
        "target_url": str(check.get("targetUrl") or ""),
        "workflow_name": str(check.get("workflowName") or ""),
        "_sort_key": sort_key,
    }


def summarized_state(checks: list[dict[str, Any]]) -> str:
    categories = {check["category"] for check in checks}
    if "failing" in categories:
        return "failing"
    if "pending" in categories:
        return "pending"
    if "success" in categories:
        return "success"
    return "absent"


def dedupe_latest_checks(checks: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Keep only the most recent run per (type, name, workflow_name).

    GitHub's `statusCheckRollup` does not supersede an older `CheckRun` when a
    same-named workflow re-runs (e.g. after a PR-metadata edit retriggers a
    title check); both the stale and current run remain in the rollup. Ordering
    by ISO-8601 completedAt/startedAt/createdAt (falls back to list order when
    a timestamp is missing) and keeping the latest per (type, name,
    workflow_name) avoids a superseded failure permanently blocking the gate.
    `workflow_name` is included because `normalize_check()` preserves it
    per-CheckRun and two independent workflows can expose the same job/check
    name (e.g. both have a `test` job); without it, a later success from one
    workflow could hide an earlier failure from a different workflow. A true
    rerun of the same check keeps the same `workflow_name`, so it still
    collapses correctly. StatusContext entries are never merged with
    same-named CheckRun entries -- the two typenames carry distinct signals.
    """
    latest: dict[tuple[str, str, str], dict[str, Any]] = {}
    for index, check in enumerate(checks):
        key = (check["type"], check["name"], check["workflow_name"])
        candidate = (check["_sort_key"], index)
        existing = latest.get(key)
        if existing is None or candidate >= (existing["_sort_key"], existing["_order"]):
            enriched = dict(check)
            enriched["_order"] = index
            latest[key] = enriched
    return [latest[key] for key in sorted(latest, key=lambda k: latest[k]["_order"])]


def check_identity(check: dict[str, Any]) -> dict[str, str]:
    """Return the durable identity for one normalized status-rollup entry."""
    return {
        "type": str(check.get("type") or ""),
        "name": str(check.get("name") or ""),
        "workflow_name": str(check.get("workflow_name") or ""),
    }


def check_identity_key(identity: dict[str, Any]) -> tuple[str, str, str]:
    return (
        str(identity.get("type") or ""),
        str(identity.get("name") or ""),
        str(identity.get("workflow_name") or ""),
    )


def persisted_check_identity_keys(value: Any, field: str) -> set[tuple[str, str, str]]:
    if not is_json_array(value):
        raise ValueError(f"persisted {field} must be an array")
    identities: set[tuple[str, str, str]] = set()
    for index, raw_identity in enumerate(value):
        if not is_json_object(raw_identity):
            raise ValueError(f"persisted {field}[{index}] must be an object")
        if not all(
            key in raw_identity and isinstance(raw_identity[key], str)
            for key in ("type", "name", "workflow_name")
        ):
            raise ValueError(
                f"persisted {field}[{index}] must contain string type, name, and workflow_name"
            )
        identity = check_identity_key(raw_identity)
        if not identity[0] or not identity[1]:
            raise ValueError(
                f"persisted {field}[{index}] must contain non-empty type and name"
            )
        identities.add(identity)
    return identities


def classify_checks(status_rollup: Any) -> dict[str, Any]:
    """Classify a status-check rollup into failing/pending/success buckets.

    Generic: any review-gate interpretation of specific contexts is layered on
    top by the review-trigger module, never baked in here.
    """
    checks = dedupe_latest_checks(
        [
            normalize_check(check)
            for check in json_array(status_rollup)
            if is_json_object(check)
        ]
    )
    failing = [check["name"] for check in checks if check["category"] == "failing"]
    pending = [check["name"] for check in checks if check["category"] == "pending"]
    failing_identities = [
        check_identity(check) for check in checks if check["category"] == "failing"
    ]
    pending_identities = [
        check_identity(check) for check in checks if check["category"] == "pending"
    ]
    success = sum(check["category"] == "success" for check in checks)

    return {
        "total": len(checks),
        "success": success,
        "failing": failing,
        "pending": pending,
        "failing_identities": failing_identities,
        "pending_identities": pending_identities,
        "checks": checks,
    }

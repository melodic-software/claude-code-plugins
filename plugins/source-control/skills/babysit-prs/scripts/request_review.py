#!/usr/bin/env python3
"""Post one state-guarded review-trigger comment for a PR head SHA."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, cast

import babysit_lease as leases
from babysit_delta import compute_branch_freshness, head_repository_scope
from babysit_feedback import fetch_current_human_stop
from babysit_gh import (
    flatten_paginated_items,
    gh_json,
    parse_repo_number,
    view_pr,
)
from babysit_review_trigger import (
    ReviewTriggerConfig,
    fetch_reaction_signals,
    fetch_review_evidence,
    has_current_head_review,
    resolve_associated_reactions,
    trigger_regex,
)
from babysit_state import (
    load_state,
    resolve_expected_head_sha,
    resolve_state_dir,
    state_lock,
    state_path_for,
    write_state,
)
from babysit_util import (
    MIN_HEAD_SHA_PREFIX_LENGTH,
    configure_stdio,
    is_json_object,
    json_object,
    parse_timestamp,
)


def _csv(value: str | None) -> frozenset[str]:
    return frozenset(part.strip() for part in (value or "").split(",") if part.strip())


def build_trigger_config(args: argparse.Namespace) -> ReviewTriggerConfig:
    return ReviewTriggerConfig(
        trigger_phrase=str(args.trigger_phrase or ""),
        reviewer_logins=_csv(getattr(args, "review_bot_logins", None)),
    )


def allowed_owners_from_policy(policy: dict[str, Any]) -> frozenset[str]:
    """Rebuild the owner allowlist the snapshot already blessed for this PR.

    The snapshot computed and stored `mutation_policy` under the configured
    watched-owner set, and this run only reaches the live re-check after the
    stored policy proved the base repository review-trigger-allowed -- so the
    base and head owners it recorded were both inside that set. Re-deriving
    `head_repository_scope` on the LIVE PR against exactly those two owners
    re-checks archived-status and ownership drift without re-importing any
    ambient owner configuration; deriving the allowlist from the live PR's own
    owners instead would make it trivially true and detect no drift at all.
    """
    owners = {str(policy.get(key) or "") for key in ("base_owner", "head_owner")}
    return frozenset(owner for owner in owners if owner)


def flatten_pages(value: Any) -> list[dict[str, Any]]:
    return flatten_paginated_items(value, "PR issue comments")


def validate_current_candidate(
    repo: str,
    number: int,
    expected_head_sha: str,
    config: ReviewTriggerConfig,
    allowed_owners: frozenset[str],
    review_trigger: dict[str, Any],
) -> dict[str, Any]:
    current = view_pr(repo, number)
    if str(current.get("state") or "").upper() != "OPEN":
        raise RuntimeError("PR is no longer open")
    if not head_repository_scope(current, allowed_owners)["review_trigger_allowed"]:
        raise RuntimeError(
            "PR base repository is outside the configured owners or archived"
        )
    if current.get("headRefOid") != expected_head_sha:
        raise RuntimeError("PR head changed after the snapshot")
    merge_state = str(current.get("mergeStateStatus") or "").upper()
    mergeable = str(current.get("mergeable") or "").upper()
    # BLOCKED can mask BEHIND: a head behind its base still reports BLOCKED, not
    # BEHIND. Reuse the compare-confirmed freshness signal (`view_pr` already
    # enriched `_blocked_base_compare`) so a stale-behind head is rejected here
    # and the branch-refresh flow runs first, instead of spending the one-shot
    # review request on a SHA that is about to be rebuilt.
    behind = compute_branch_freshness(current)["state"] == "behind"
    if (
        current.get("isDraft")
        or behind
        or merge_state
        in {
            "",
            "BEHIND",
            "DIRTY",
            "DRAFT",
            "UNKNOWN",
        }
        or mergeable == "CONFLICTING"
    ):
        if mergeable == "CONFLICTING":
            reason = "CONFLICTING"
        elif behind:
            reason = "BEHIND"
        else:
            reason = merge_state
        raise RuntimeError(
            f"PR is not a stable fresh review candidate: {reason or 'UNKNOWN'}"
        )
    review_evidence = fetch_review_evidence(repo, number, config=config)
    reaction_signals = fetch_reaction_signals(repo, number, current, config)
    # Reactions carry no commit SHA, so a reaction left on an earlier head
    # persists across pushes. Scope through the same current-head-association
    # rule as the state machine's candidate predicate (`classify_review_
    # request`) -- gating on the raw `reaction_signals` here would re-block
    # every head this guard is meant to unblock.
    associated_reactions = resolve_associated_reactions(
        reaction_signals, expected_head_sha, review_trigger
    )
    human_stop = fetch_current_human_stop(repo, number, current)
    if human_stop["required"]:
        raise RuntimeError(
            "human review stop is active; refusing to post a review trigger"
        )
    if has_current_head_review(
        current, expected_head_sha, review_evidence, config=config
    ):
        raise RuntimeError(
            "a current-head review already exists; refusing to post another review trigger"
        )
    if associated_reactions:
        raise RuntimeError(
            "reviewer reaction signal is present but cannot prove current-head "
            "completion; refusing to post another review trigger"
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


def existing_trigger(
    repo: str,
    number: int,
    recognizer: re.Pattern[str],
    known_comment_ids: set[str] | None = None,
) -> dict[str, Any] | None:
    """Return an exact trigger that durable state cannot already attribute."""
    pages = gh_json(
        [
            "api",
            f"repos/{repo}/issues/{number}/comments?per_page=100",
            "--paginate",
            "--slurp",
        ]
    )
    for comment in flatten_pages(pages):
        if not recognizer.fullmatch(str(comment.get("body") or "")):
            continue
        if str(comment.get("id")) in (known_comment_ids or set()):
            continue
        return comment
    return None


def record_request(
    state_path: Path,
    state: dict[str, Any],
    key: str,
    pr_state: dict[str, Any],
    head_sha: str,
    comment: dict[str, Any],
) -> dict[str, Any]:
    review_trigger = json_object(pr_state.get("review_trigger"))
    requested_at = str(comment.get("created_at") or datetime.now(UTC).isoformat())
    confirmed_at = datetime.now(UTC).isoformat()
    history = json_object(review_trigger.get("request_history"))
    history[head_sha] = {
        "comment_id": comment.get("id"),
        "requested_at": requested_at,
    }
    attempt_history = json_object(review_trigger.get("request_attempt_history"))
    attempt_history[head_sha] = {
        "status": "confirmed",
        "attempted_at": str(review_trigger.get("request_attempted_at") or confirmed_at),
        "confirmed_at": confirmed_at,
        "comment_id": comment.get("id"),
    }
    review_trigger.update(
        {
            "state": "requested",
            "request_eligible": False,
            "requested_head_sha": head_sha,
            "request_attempt_head_sha": head_sha,
            "request_attempted_at": str(
                review_trigger.get("request_attempted_at") or requested_at
            ),
            "request_attempt_status": "confirmed",
            "request_attempt_error": "",
            "request_history": history,
            "request_attempt_history": attempt_history,
            "request_comment_id": comment.get("id"),
            "requested_at": requested_at,
        }
    )
    pr_state["review_trigger"] = review_trigger
    ledger_entry = cast(
        dict[str, Any], state.setdefault("mutation_ledger", {}).setdefault(key, {})
    )
    ledger_entry["review_request_history"] = history
    ledger_entry["review_attempt_history"] = attempt_history
    state["updated_at"] = confirmed_at
    write_state(state_path, state)
    return review_trigger


def record_attempt_problem(
    state_path: Path,
    state: dict[str, Any],
    key: str,
    pr_state: dict[str, Any],
    head_sha: str,
    error: str,
    created_comment: dict[str, Any] | None = None,
    found_trigger: dict[str, Any] | None = None,
) -> None:
    recorded_at = datetime.now(UTC).isoformat()
    review_trigger = json_object(pr_state.get("review_trigger"))
    attempt_history = json_object(review_trigger.get("request_attempt_history"))
    attempt = json_object(attempt_history.get(head_sha))
    attempt.update(
        {
            "status": "ambiguous",
            "recorded_at": recorded_at,
            "error": error,
        }
    )
    if created_comment:
        attempt["comment_id"] = created_comment.get("id")
        attempt["comment_url"] = created_comment.get("html_url")
    if found_trigger:
        attempt["found_trigger_id"] = found_trigger.get("id")
        attempt["found_trigger_url"] = found_trigger.get("html_url")
    attempt_history[head_sha] = attempt
    review_trigger.update(
        {
            "state": "request_ambiguous",
            "request_eligible": False,
            "request_attempt_head_sha": head_sha,
            "request_attempt_status": "ambiguous",
            "request_attempt_error": error,
            "request_attempt_history": attempt_history,
        }
    )
    pr_state["review_trigger"] = review_trigger
    ledger_entry = cast(
        dict[str, Any], state.setdefault("mutation_ledger", {}).setdefault(key, {})
    )
    ledger_entry["review_attempt_history"] = attempt_history
    state["updated_at"] = recorded_at
    write_state(state_path, state)


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
    config = build_trigger_config(args)
    recognizer = trigger_regex(config.trigger_phrase)
    if recognizer is None:
        raise RuntimeError("a non-empty review trigger phrase is required")
    require_worker_lease(args, state_dir, repo, number)
    state = load_state(state_path)
    pr_state_value: Any = cast(Any, state.get("prs") or {}).get(key)
    if not isinstance(pr_state_value, dict):
        raise RuntimeError(f"missing snapshot state for {key}; run --write-state first")
    pr_state = cast(dict[str, Any], pr_state_value)
    expected_head_sha = resolve_expected_head_sha(
        str(pr_state.get("head_sha") or ""), args.expected_head_sha
    )
    mutation_policy = json_object(pr_state.get("mutation_policy"))
    if not mutation_policy.get("review_trigger_allowed"):
        raise RuntimeError(
            "snapshot base repository is outside configured owners or archived"
        )
    if json_object(pr_state.get("human_stop")).get("required"):
        raise RuntimeError("snapshot has an active human review stop")
    allowed_owners = allowed_owners_from_policy(mutation_policy)

    review_trigger = json_object(pr_state.get("review_trigger"))
    ledger_entry = cast(
        dict[str, Any], state.setdefault("mutation_ledger", {}).setdefault(key, {})
    )
    request_history = json_object(review_trigger.get("request_history"))
    request_history.update(json_object(ledger_entry.get("review_request_history")))
    attempt_history = json_object(review_trigger.get("request_attempt_history"))
    attempt_history.update(json_object(ledger_entry.get("review_attempt_history")))
    review_trigger["request_history"] = request_history
    review_trigger["request_attempt_history"] = attempt_history
    pr_state["review_trigger"] = review_trigger
    if expected_head_sha in request_history:
        raise RuntimeError("a review was already requested for this head SHA")
    prior_attempt = attempt_history.get(expected_head_sha)
    if is_json_object(prior_attempt) and (
        prior_attempt.get("status") == "requesting"
        and prior_attempt.get("comment_id") is None
    ):
        raise RuntimeError(
            "a review request attempt is still 'requesting' with no recorded comment; the process may have stopped mid-flight, so inspect durable state before any manual clear"
        )
    if prior_attempt is not None:
        raise RuntimeError("a review was already attempted for this head SHA")
    if review_trigger.get("requested_head_sha") == expected_head_sha:
        raise RuntimeError("a review was already requested for this head SHA")
    if review_trigger.get("request_attempt_head_sha") == expected_head_sha:
        raise RuntimeError("a review was already attempted for this head SHA")
    if not review_trigger.get("request_eligible"):
        raise RuntimeError(
            "snapshot state has not passed the review request observation gate"
        )
    first_seen = parse_timestamp(review_trigger.get("missing_first_seen_at"))
    last_seen = parse_timestamp(review_trigger.get("missing_last_seen_at"))
    if (
        review_trigger.get("missing_head_sha") != expected_head_sha
        or int(review_trigger.get("missing_observations") or 0) < 2
        or first_seen is None
        or last_seen is None
        or (last_seen - first_seen).total_seconds() < 180
    ):
        raise RuntimeError("durable review observation evidence is incomplete")
    branch_history = json_object(pr_state.get("branch_refresh_history"))
    ledger_branch_history = json_object(ledger_entry.get("branch_refresh_history"))
    if (
        expected_head_sha in branch_history
        or expected_head_sha in ledger_branch_history
    ):
        raise RuntimeError("current head has a branch-refresh attempt")

    validate_current_candidate(
        repo, number, expected_head_sha, config, allowed_owners, review_trigger
    )

    history = json_object(review_trigger.get("request_history"))
    attempts = json_object(review_trigger.get("request_attempt_history"))
    known_comment_ids = {
        str(entry.get("comment_id"))
        for entry in (*history.values(), *attempts.values())
        if is_json_object(entry) and entry.get("comment_id") is not None
    }
    if review_trigger.get("request_comment_id") is not None:
        known_comment_ids.add(str(review_trigger["request_comment_id"]))
    found = existing_trigger(repo, number, recognizer, known_comment_ids)
    result: dict[str, object] = {
        "key": key,
        "expected_head_sha": expected_head_sha,
        "apply": args.apply,
        "eligible": True,
        "existing_trigger": bool(found),
    }
    if found:
        raise RuntimeError(
            "found a review trigger that durable state cannot attribute to a head SHA"
        )
    if not args.apply:
        return result

    attempted_at = datetime.now(UTC).isoformat()
    review_trigger = json_object(pr_state.get("review_trigger"))
    attempt_history = json_object(review_trigger.get("request_attempt_history"))
    attempt_history[expected_head_sha] = {
        "status": "requesting",
        "attempted_at": attempted_at,
    }
    review_trigger.update(
        {
            "state": "requesting",
            "request_eligible": False,
            "request_attempt_head_sha": expected_head_sha,
            "request_attempted_at": attempted_at,
            "request_attempt_status": "requesting",
            "request_attempt_error": "",
            "request_attempt_history": attempt_history,
        }
    )
    pr_state["review_trigger"] = review_trigger
    ledger_entry["review_request_history"] = json_object(
        review_trigger.get("request_history")
    )
    ledger_entry["review_attempt_history"] = attempt_history
    state["updated_at"] = attempted_at
    write_state(state_path, state)

    try:
        require_worker_lease(args, state_dir, repo, number)
        validate_current_candidate(
            repo, number, expected_head_sha, config, allowed_owners, review_trigger
        )
        late_trigger = existing_trigger(repo, number, recognizer, known_comment_ids)
    except Exception as exc:
        record_attempt_problem(
            state_path,
            state,
            key,
            pr_state,
            expected_head_sha,
            str(exc),
        )
        raise
    if late_trigger:
        error = "found a new unattributed review trigger immediately before posting"
        record_attempt_problem(
            state_path,
            state,
            key,
            pr_state,
            expected_head_sha,
            error,
            found_trigger=late_trigger,
        )
        raise RuntimeError(error)

    try:
        require_worker_lease(args, state_dir, repo, number, renew=True)
        comment = gh_json(
            [
                "api",
                f"repos/{repo}/issues/{number}/comments",
                "--method",
                "POST",
                "-f",
                f"body={args.trigger_phrase}",
            ]
        )
    except Exception as exc:
        record_attempt_problem(
            state_path,
            state,
            key,
            pr_state,
            expected_head_sha,
            str(exc),
        )
        raise
    if not is_json_object(comment) or not comment.get("id"):
        error = "GitHub did not return the created trigger comment"
        record_attempt_problem(
            state_path,
            state,
            key,
            pr_state,
            expected_head_sha,
            error,
        )
        raise RuntimeError(error)

    try:
        after = view_pr(repo, number)
    except Exception as exc:
        error = f"unable to verify PR head after posting: {exc}"
        record_attempt_problem(
            state_path,
            state,
            key,
            pr_state,
            expected_head_sha,
            error,
            created_comment=comment,
        )
        raise RuntimeError(error) from exc
    after_head = str(after.get("headRefOid") or "")
    after_state = str(after.get("state") or "").upper()
    if after_head != expected_head_sha or after_state != "OPEN":
        error = (
            "PR changed while posting the review request: "
            f"state={after_state or 'UNKNOWN'} head={after_head or 'UNKNOWN'}"
        )
        record_attempt_problem(
            state_path,
            state,
            key,
            pr_state,
            expected_head_sha,
            error,
            created_comment=comment,
        )
        raise RuntimeError(error)

    post_known_comment_ids = {*known_comment_ids, str(comment["id"])}
    try:
        concurrent_trigger = existing_trigger(
            repo, number, recognizer, post_known_comment_ids
        )
        post_reactions = fetch_reaction_signals(repo, number, after, config)
    except Exception as exc:
        error = f"unable to verify trigger uniqueness after posting: {exc}"
        record_attempt_problem(
            state_path,
            state,
            key,
            pr_state,
            expected_head_sha,
            error,
            created_comment=comment,
        )
        raise RuntimeError(error) from exc
    # Scope to this head before flagging "unexpected" -- otherwise a stale
    # earlier-head reaction still sitting on the PR (or on an older,
    # already-attributed trigger comment) would abort an otherwise-clean
    # post every time, the same staleness bug as the pre-POST guard above.
    unexpected_reactions = [
        signal
        for signal in resolve_associated_reactions(
            post_reactions, expected_head_sha, review_trigger
        )
        if not (
            signal.get("scope") == "trigger_comment"
            and str(signal.get("comment_id") or "") == str(comment["id"])
        )
    ]
    if concurrent_trigger or unexpected_reactions:
        details: list[str] = []
        if concurrent_trigger:
            details.append(f"concurrent trigger comment {concurrent_trigger.get('id')}")
        if unexpected_reactions:
            details.append("unexpected reviewer reaction signal")
        error = "trigger uniqueness became ambiguous after posting: " + ", ".join(
            details
        )
        record_attempt_problem(
            state_path,
            state,
            key,
            pr_state,
            expected_head_sha,
            error,
            created_comment=comment,
            found_trigger=concurrent_trigger,
        )
        raise RuntimeError(error)
    record_request(state_path, state, key, pr_state, expected_head_sha, comment)
    result.update(
        {
            "requested": True,
            "comment_id": comment.get("id"),
            "url": comment.get("html_url"),
        }
    )
    return result


def main() -> int:
    configure_stdio()
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
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
        "--apply", action="store_true", help="post the exact one-shot review request"
    )
    parser.add_argument(
        "--trigger-phrase",
        required=True,
        help=(
            "Exact review-trigger comment body to post and recognize. Required: "
            "the CLI is inert without it."
        ),
    )
    parser.add_argument(
        "--review-bot-logins",
        default=None,
        help=(
            "Comma-separated reviewer-bot logins whose reviews and reactions "
            "count as engagement (structural bot detection is primary)."
        ),
    )
    args = parser.parse_args()
    if not (args.trigger_phrase or "").strip():
        parser.error("--trigger-phrase must not be empty")
    try:
        print(json.dumps(run(args), indent=2, sort_keys=True))
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

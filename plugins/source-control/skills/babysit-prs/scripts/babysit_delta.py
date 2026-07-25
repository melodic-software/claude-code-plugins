#!/usr/bin/env python3
"""Per-PR classification and the fan-out delta engine.

Owns branch-freshness classification, the trust-boundary mutation policy, the
per-PR classifier with its suppressible/unsuppressible worker-dispatch deltas,
the head-ref uniqueness guard, and cadence recommendation.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

from babysit_checks import (
    check_identity_key,
    classify_checks,
    classify_stuck_checks,
    persisted_check_identity_keys,
)
from babysit_classify import (
    DEFAULT_FEEDBACK_CONFIG,
    FeedbackConfig,
    actor_kind,
    author_login,
    is_self_login,
    normalize_self_logins,
)
from babysit_feedback import collect_feedback
from babysit_gh import find_open_prs_for_head_ref
from babysit_review_trigger import (
    DEFAULT_REVIEW_TRIGGER_CONFIG,
    ReviewTriggerConfig,
    classify_review_request,
    issue_comment_database_id,
    review_gate_state,
    trigger_regex,
)
from babysit_util import (
    is_json_array,
    is_json_object,
    json_array,
    json_object,
    parse_timestamp,
)

# Merge states a worker can actually act on (merge-gate check, possible merge).
# Used only for a *directional* transition check (into, not any diff) since
# GitHub recomputes mergeStateStatus asynchronously and flaps e.g.
# UNKNOWN<->CLEAN without any real change to react to.
ACTIONABLE_MERGE_STATES = {"CLEAN", "HAS_HOOKS"}
# Marker embedded in the message of a head-ref alias cross-check failure. That
# check is purely advisory: it proves global branch uniqueness across the fleet
# and its failure leaves every per-PR classification and the persisted state
# intact, so callers must be able to tell it apart from a substantive per-PR
# hydration or discovery error. Both construction sites (the queue path here and
# the single-PR path in pr_queue_snapshot.py) build the message through this
# constant so the two cannot drift.
HEAD_REF_ALIAS_ERROR_MARKER = "head-ref alias check:"
# Fan-out safety net: force a worker check-in on an otherwise-unchanged PR at
# least this often, so "nothing changed" can never mean "never checked again"
# (a classifier blind spot or a forgotten stuck PR). Snapshot-level detection
# already runs every cadence cycle regardless; this bounds only the coarser,
# expensive fresh-worker dispatch. Override with --max-quiet-recheck-seconds.
DEFAULT_MAX_QUIET_RECHECK_SECONDS = 4 * 60 * 60
# A pending check must be at least this old before a stuck-check class that
# ages out (`stuck_queued`, `never_settling`) fires, so normal in-flight CI and
# freshly-started non-required checks are never reported stuck. Override with
# --stuck-check-age-seconds. Orphaned StatusContexts (no backing run) are
# detected structurally and are not subject to this threshold.
DEFAULT_STUCK_CHECK_AGE_SECONDS = 30 * 60
ADVISORY_FIX_ROUND_CAP = 100


@dataclass(frozen=True)
class ClassifyConfig:
    """Everything the classifier needs that used to be ambient.

    All identity sets ship empty and every scalar carries its safe default, so
    an unconfigured classifier is dormant on every optional integration and
    fail-closed on every trust boundary.
    """

    allowed_owners: frozenset[str] = field(default_factory=frozenset)
    self_logins: frozenset[str] = field(default_factory=frozenset)
    intended_write_identity: str = ""
    feedback: FeedbackConfig = DEFAULT_FEEDBACK_CONFIG
    review_trigger: ReviewTriggerConfig = DEFAULT_REVIEW_TRIGGER_CONFIG
    max_quiet_recheck_seconds: float = DEFAULT_MAX_QUIET_RECHECK_SECONDS
    stuck_check_age_seconds: float = DEFAULT_STUCK_CHECK_AGE_SECONDS
    advisory_fix_round_cap: int = ADVISORY_FIX_ROUND_CAP


DEFAULT_CLASSIFY_CONFIG = ClassifyConfig()


def validated_max_quiet_recheck_seconds(value: float) -> float:
    try:
        seconds = float(value)
    except (TypeError, ValueError) as error:
        raise ValueError(
            "--max-quiet-recheck-seconds must be a finite number greater than zero"
        ) from error
    if not math.isfinite(seconds) or seconds <= 0:
        raise ValueError(
            "--max-quiet-recheck-seconds must be a finite number greater than zero"
        )
    return seconds


def validated_stuck_check_age_seconds(value: float) -> float:
    try:
        seconds = float(value)
    except (TypeError, ValueError) as error:
        raise ValueError(
            "--stuck-check-age-seconds must be a finite number greater than zero"
        ) from error
    if not math.isfinite(seconds) or seconds <= 0:
        raise ValueError(
            "--stuck-check-age-seconds must be a finite number greater than zero"
        )
    return seconds


def compute_branch_freshness(pr: dict[str, Any]) -> dict[str, Any]:
    """Classify branch staleness from `mergeStateStatus`, with one fallback.

    Pure function: the only I/O this depends on (the BLOCKED-branch compare)
    happens once, in `view_pr`, and is read here off `pr["_blocked_base_compare"]`.
    This keeps classification network-free and keeps `view_pr` the single choke
    point both the snapshot orchestrator and the branch-refresh CLI's
    revalidation already call, so a live re-check gets the same enrichment for
    free.

    Falls back to the compare-confirmed signal only when `mergeStateStatus` is
    BLOCKED and the compare proves outstanding base commits (`behind_by > 0`,
    `status` in {behind, diverged}). Every other cause of BLOCKED (a real merge
    conflict, a pending human review, ...) is untouched by this function -- it
    only ever flips BLOCKED to "behind"; conflict, human-stop, lease, unique
    head-ref, and the per-source-SHA refresh ledger are all still enforced
    independently by the caller.
    """
    merge_state = str(pr.get("mergeStateStatus") or "").upper()
    mergeable = str(pr.get("mergeable") or "").upper()
    if merge_state == "DIRTY" or mergeable == "CONFLICTING":
        return {"state": "conflicting", "source": "mergeStateStatus"}
    if merge_state == "BEHIND":
        return {"state": "behind", "source": "mergeStateStatus"}
    if merge_state in {"", "UNKNOWN"}:
        return {"state": "unknown", "source": "mergeStateStatus"}
    if merge_state == "BLOCKED":
        compare = pr.get("_blocked_base_compare")
        if (
            is_json_object(compare)
            and compare.get("status") in {"behind", "diverged"}
            and isinstance(compare.get("behind_by"), int)
            and compare["behind_by"] > 0
        ):
            return {"state": "behind", "source": "compare_api", "compare": compare}
    return {"state": "not_reported_behind", "source": "mergeStateStatus"}


def head_repository_scope(
    pr: dict[str, Any], allowed_owners: frozenset[str]
) -> dict[str, Any]:
    """Resolve the branch-write trust boundary for one PR.

    `allowed_owners` is the caller-supplied allowlist, resolved at decision
    time -- there is no ambient owner configuration to inherit.
    """
    repo = str(pr.get("repo") or "")
    base_owner = repo.split("/", 1)[0].casefold() if "/" in repo else ""
    head_repo = pr.get("headRepository")
    head_repo_name = (
        str(head_repo.get("nameWithOwner") or "") if is_json_object(head_repo) else ""
    )
    head_owner_value = pr.get("headRepositoryOwner")
    head_owner = (
        str(head_owner_value.get("login") or "")
        if is_json_object(head_owner_value)
        else str(head_owner_value or "")
    ).casefold()
    cross_repository = pr.get("isCrossRepository")
    same_repository = (
        bool(head_repo_name) and head_repo_name.casefold() == repo.casefold()
    )
    if same_repository and not head_owner:
        head_owner = base_owner
    configured_owners = {owner.casefold() for owner in allowed_owners}
    base_repo_allowed = base_owner in configured_owners
    base_repo_archived = bool(pr.get("baseRepositoryArchived"))
    review_trigger_allowed = base_repo_allowed and not base_repo_archived
    head_metadata_complete = bool(head_repo_name) and cross_repository in {
        True,
        False,
    }
    branch_write_allowed = (
        review_trigger_allowed
        and head_metadata_complete
        and (
            same_repository
            or (
                cross_repository is True
                and bool(head_repo_name)
                and head_owner in configured_owners
            )
        )
    )
    return {
        "base_owner": base_owner,
        "base_repo_allowed": base_repo_allowed,
        "base_repo_archived": base_repo_archived,
        "review_trigger_allowed": review_trigger_allowed,
        "head_repo": head_repo_name,
        "head_owner": head_owner,
        "is_cross_repository": cross_repository,
        "head_metadata_complete": head_metadata_complete,
        "maintainer_can_modify": bool(pr.get("maintainerCanModify")),
        "branch_write_allowed": branch_write_allowed,
    }


def detect_foreign_activity(
    pr: dict[str, Any],
    previous: dict[str, Any] | None,
    config: ClassifyConfig,
) -> dict[str, Any]:
    """Detect same-login activity our mutation ledger never recorded.

    Every mutation this system performs under the operator's login is recorded
    in the mutation ledger before or alongside the act. A trigger-phrase
    comment authored by one of `self_logins` whose comment id appears in no
    ledger history therefore proves a SECOND driver (another session, another
    machine, another tool) is working this PR under the same identity --
    dispatching our own worker on top of it would double-act. Observable only
    through the configured trigger phrase; with no phrase or no self logins
    the arm is dormant.
    """
    recognizer = trigger_regex(config.review_trigger.trigger_phrase)
    self_logins = normalize_self_logins(config.self_logins)
    if recognizer is None or not self_logins:
        return {"detected": False, "evidence": []}
    prior = json_object((previous or {}).get("review_trigger"))
    known_comment_ids: set[str] = set()
    for history_key in ("request_history", "request_attempt_history"):
        for entry in json_object(prior.get(history_key)).values():
            if is_json_object(entry) and entry.get("comment_id") is not None:
                known_comment_ids.add(str(entry["comment_id"]))
    evidence: list[dict[str, str]] = []
    for comment in json_array(pr.get("comments")):
        if not is_json_object(comment):
            continue
        if not is_self_login(author_login(comment), self_logins):
            continue
        if not recognizer.fullmatch(str(comment.get("body") or "")):
            continue
        comment_id = issue_comment_database_id(comment)
        if comment_id and comment_id in known_comment_ids:
            continue
        evidence.append(
            {
                "comment_id": comment_id,
                "author": author_login(comment),
                "url": str(comment.get("url") or ""),
                "created_at": str(comment.get("createdAt") or ""),
            }
        )
    return {"detected": bool(evidence), "evidence": evidence}


def detect_attribution_drift(
    pr: dict[str, Any],
    previous: dict[str, Any] | None,
    config: ClassifyConfig,
) -> dict[str, Any]:
    """Detect a recorded write that landed under the wrong self-identity.

    `detect_foreign_activity` asks whether a self-login timeline event is
    unaccounted for in our ledger; this asks the complementary question about
    the events that ARE ours. `self_logins` defines *acceptable-as-mine*, not
    *intended-as-author*: when a bot write-identity degrades to the operator's
    personal login (e.g. a bot-token mint fails and the write silently falls
    back), the write still lands under an accepted self-login, so no existing
    arm notices. Here a write the ledger recorded performing whose landed
    author is a self-login OTHER than `intended_write_identity` is attribution
    drift. Pure authorship verification against our own ledger -- it needs no
    signal from the identity wrapper that minted (or failed to mint) the token.

    Coverage is bounded to the write class the mutation ledger records with a
    recoverable landed author: review-trigger comments (`request_history` /
    `request_attempt_history`, keyed by `comment_id`). Reactions, classification
    replies, and branch pushes are not yet ledgered with authorship, so drift on
    them is out of reach until the ledger records their identifiers (tracked as
    a follow-up). Dormant when no `intended_write_identity` is configured, so an
    unconfigured classifier never fires false positives.
    """
    intended = config.intended_write_identity.casefold()
    self_logins = normalize_self_logins(config.self_logins)
    if not intended or not self_logins:
        return {"detected": False, "evidence": []}
    prior = json_object((previous or {}).get("review_trigger"))
    recorded_comment_ids: set[str] = set()
    for history_key in ("request_history", "request_attempt_history"):
        for entry in json_object(prior.get(history_key)).values():
            if is_json_object(entry) and entry.get("comment_id") is not None:
                recorded_comment_ids.add(str(entry["comment_id"]))
    if not recorded_comment_ids:
        return {"detected": False, "evidence": []}
    evidence: list[dict[str, str]] = []
    for comment in json_array(pr.get("comments")):
        if not is_json_object(comment):
            continue
        comment_id = issue_comment_database_id(comment)
        if not comment_id or comment_id not in recorded_comment_ids:
            continue
        landed = author_login(comment)
        landed_cf = landed.casefold()
        # Only a landed author that is still one of our accepted self-logins is
        # drift (the degrade case). A non-self author on a ledgered id is not
        # this arm's concern -- foreign-activity semantics, and structurally
        # unreachable for an immutable comment we posted.
        if landed_cf == intended or not is_self_login(landed, self_logins):
            continue
        evidence.append(
            {
                "comment_id": comment_id,
                "landed_author": landed,
                "intended_author": config.intended_write_identity,
                "url": str(comment.get("url") or ""),
                "created_at": str(comment.get("createdAt") or ""),
            }
        )
    return {"detected": bool(evidence), "evidence": evidence}


def classify_pr(
    pr: dict[str, Any],
    previous: dict[str, Any] | None,
    inline_comments: list[dict[str, Any]] | None,
    observed_at: str,
    review_evidence: list[dict[str, str]] | None = None,
    reaction_signals: list[dict[str, str]] | None = None,
    config: ClassifyConfig = DEFAULT_CLASSIFY_CONFIG,
) -> dict[str, Any]:
    # Validate once before any actionable/draft/closed short-circuit can skip
    # the quiet fallback expression. A malformed override is an operator error
    # for the whole snapshot, not only for PRs that happen to be quiet.
    quiet_recheck_seconds = validated_max_quiet_recheck_seconds(
        config.max_quiet_recheck_seconds
    )
    stuck_age_seconds = validated_stuck_check_age_seconds(
        config.stuck_check_age_seconds
    )
    repo = pr["repo"]
    number = int(pr["number"])
    key = f"{repo}#{number}"
    checks = classify_checks(pr.get("statusCheckRollup"))
    gate = review_gate_state(checks, config.review_trigger)
    prev = previous or {}
    dispositions = dict(prev.get("feedback_dispositions") or {})
    feedback = collect_feedback(pr, inline_comments, dispositions, config.feedback)
    review_decision = str(pr.get("reviewDecision") or "")
    human_changes_requested = any(
        item.get("kind") == "review" and item.get("state") == "CHANGES_REQUESTED"
        for item in feedback["human_blocking"]
    )
    human_stop = {
        "required": bool(feedback["human_blocking"]),
        "human_changes_requested": human_changes_requested,
        "human_blocking_count": len(feedback["human_blocking"]),
    }
    merge_state = str(pr.get("mergeStateStatus") or "").upper()
    # Stuck-check detection reuses the already-normalized checks (no new fetch).
    # Attached to the same `checks` dict returned below as `checks["stuck"]`,
    # always present (empty when none) for a stable consumer contract. Surfaced
    # only as a material finding below -- never a blocker.
    checks["stuck"] = classify_stuck_checks(
        checks["checks"],
        observed_at,
        merge_state=merge_state,
        age_threshold_seconds=stuck_age_seconds,
    )
    mergeable = str(pr.get("mergeable") or "").upper()
    head_sha = str(pr.get("headRefOid") or "")
    updated_at = str(pr.get("updatedAt") or "")
    branch_freshness = compute_branch_freshness(pr)
    # Computed this early (rather than alongside the other fan-out deltas
    # below) so `new_material_feedback` can consult it: whether a
    # blocking-id-turned-material transition happened at the same head it
    # was recorded blocking at, or on a fresh head.
    head_sha_changed = bool(prev) and prev.get("head_sha") != head_sha
    # Only a disposition recorded at the CURRENT head legitimately suppresses
    # the reused-id escape valve below -- mirrors `collect_feedback`'s own
    # `disposition_applies` check. `item["id"] not in dispositions` alone
    # would let a *stale* (older-head) disposition record keep disabling the
    # escape valve even after the PR has moved to a new head, silently
    # swallowing genuinely new material content that a bot reused the id for.
    dispositions_at_current_head = {
        fid
        for fid, record in dispositions.items()
        if is_json_object(record) and record.get("head_sha") == head_sha
    }
    mutation_policy = head_repository_scope(pr, config.allowed_owners)
    review_trigger = classify_review_request(
        pr,
        gate,
        prev,
        observed_at,
        review_evidence,
        reaction_signals,
        bool(human_stop["required"]),
        review_trigger_allowed=bool(mutation_policy["review_trigger_allowed"]),
        config=config.review_trigger,
    )
    foreign_activity = detect_foreign_activity(pr, prev, config)
    attribution_drift = detect_attribution_drift(pr, prev, config)
    advisory_rounds = dict(prev.get("advisory_fix_rounds") or {})
    advisory_round_count = len(dict(advisory_rounds.get("rounds") or {}))
    advisory_cap_reached = advisory_round_count >= config.advisory_fix_round_cap
    branch_refresh = dict(prev.get("branch_refresh") or {})
    branch_refresh_history = dict(prev.get("branch_refresh_history") or {})
    if branch_refresh.get("requested_source_sha"):
        branch_refresh_history.setdefault(
            str(branch_refresh["requested_source_sha"]), dict(branch_refresh)
        )
    refresh_for_head = dict(branch_refresh_history.get(head_sha) or {})
    refresh_status = (
        str(refresh_for_head.get("status") or "attempted") if refresh_for_head else ""
    )
    # `reference/freshness.md`'s runbook, step 3: once the branch-refresh CLI's
    # `202 Accepted` is recorded for this exact head (`refresh_for_head` is
    # keyed by `requested_source_sha`, so this is scoped to that one head, not
    # any refresh ever attempted), the orchestrator must "end work on that PR
    # until a later snapshot observes a different head SHA... even if merge
    # state transiently changes". Consulted below to freeze the entire
    # fan-out gate -- not just `pr_clean_ready_for_direct_gate` (which the
    # "awaiting a new head" blocker already handles) -- while this holds; see
    # `needs_worker`'s definition for why the blocker alone is not enough.
    refresh_accepted_awaiting_head = refresh_status == "accepted"
    prev_blocking_ids = set(prev.get("blocking_feedback_ids") or [])
    prev_material_ids = set(prev.get("material_feedback_ids") or [])
    prev_human_ids = set(prev.get("human_feedback_ids") or [])
    # Distinct from `prev_human_ids`: that set contains every human id ever
    # seen regardless of blocking state, so it cannot tell "this id was
    # already blocking last cycle" apart from "this id existed but wasn't
    # blocking last cycle". `prev_human_blocking_ids` tracks only ids that
    # were classified `human_blocking` as of the previous snapshot, so a
    # comment/review that keeps the same id but is edited or reclassified
    # from nonblocking into blocking is detected as new blocking information
    # below, mirroring `prev_blocking_ids`'s role for bot feedback.
    prev_human_blocking_ids = set(prev.get("human_blocking_feedback_ids") or [])
    blocking_feedback_ids = [item["id"] for item in feedback["blocking"]]
    material_feedback_ids = [item["id"] for item in feedback["material"]]
    human_blocking_feedback_ids = [item["id"] for item in feedback["human_blocking"]]
    human_feedback_ids = [
        item["id"] for item in (*feedback["human_blocking"], *feedback["human"])
    ]
    # Parity with the bot delta arms' *structural* self-filter: bot feedback can
    # never contain this engine's own posts, because the engine comments under
    # the operator's human login and `collect_feedback` only routes bot-authored
    # items to `feedback["blocking"]`/`["material"]`. The human arms have no such
    # structural guard, so without this an operator whose login is the configured
    # self-login sees every prior-round worker reply (classification tables,
    # "Fixed in <sha>" follow-ups) counted as new human-authored feedback --
    # manufacturing a self-inflicted, unsuppressible `new_human_blocking_feedback`
    # dispatch that re-fires forever with zero real work. This brings the
    # deterministic delta to the same rule `reference/review-discipline.md` §1
    # already mandates for the worker's own classification replies.
    #
    # Deliberately scoped to the new-feedback deltas only, NOT to
    # `collect_feedback`'s classification: a self-authored item still lands in
    # `feedback["human_blocking"]` above, so a genuine "don't merge, I found a
    # problem" comment the maintainer posts under their own login keeps
    # `human_stop`/the triage blocker intact and continues to halt the merge
    # gate. Filtering it there instead would silently strip the solo maintainer's
    # ability to human-stop their own PR. Here it only stops re-dispatching a
    # worker onto the engine's own prior output.
    self_logins = normalize_self_logins(config.self_logins)
    new_blocking_feedback = [
        item for item in feedback["blocking"] if item["id"] not in prev_blocking_ids
    ]
    # A blocking bot item the agent just triaged via the feedback ledger's
    # dispose action reclassifies from `blocking` to `material` at the same id
    # and head (see `collect_feedback`'s `disposition_applies` branch). That id
    # was already seen in `prev_blocking_ids`, so it is not new information a
    # fresh worker needs to act on -- excluding it here mirrors `resolved_*`
    # deltas that also fold prior state into "already known" rather than "new".
    #
    # But GitHub sometimes reuses/edits an existing review comment's id
    # instead of posting a new one, so the same id can resurface as
    # genuinely different content on a new head (e.g. a P1 turning into a
    # bot execution-error note, or one bot-error note replaced by another).
    # Treating every id that was merely *seen* before -- whether it was
    # blocking or already material -- as "already known" would silently
    # swallow that fresh finding. Only suppress an id when it is still the
    # same head it was last recorded at, or a disposition *recorded at that
    # same current head* exists for it (either legitimately absorbs the
    # reuse into "already known"). This mirrors `prev_blocking_ids`'s escape
    # valve, applied to `prev_material_ids` as well since a bot can reuse an
    # id that was *already* material just as readily as one that was
    # blocking. `dispositions_at_current_head` (not raw `dispositions`) is
    # deliberate: a disposition from an older head must not keep suppressing
    # this valve once the PR has moved to a new head -- see its definition
    # above.
    new_material_feedback = [
        item
        for item in feedback["material"]
        if (
            item["id"] not in prev_material_ids
            or (head_sha_changed and item["id"] not in dispositions_at_current_head)
        )
        and (
            item["id"] not in prev_blocking_ids
            or (head_sha_changed and item["id"] not in dispositions_at_current_head)
        )
    ]
    new_human_feedback = [
        item
        for item in (*feedback["human_blocking"], *feedback["human"])
        if item["id"] not in prev_human_ids
        and not is_self_login(item.get("author"), self_logins)
    ]
    changed = bool(prev) and (
        prev.get("head_sha") != head_sha or prev.get("updated_at") != updated_at
    )
    new_to_state = not bool(prev)

    # Blockers/material and status are derived here -- ahead of the fan-out
    # gate below -- purely so the gate can consult `blockers` to recognize a
    # clean, non-draft, zero-blocker PR and route it straight to the
    # mode-appropriate merge gate instead of dispatching a worker it does not
    # need (see `pr_clean_ready_for_direct_gate` below). Every input here
    # (feedback, human_stop, merge_state, mutation_policy, review_trigger,
    # refresh_for_head, review_decision, checks, changed, new_to_state) is
    # already computed above this point.
    blockers: list[str] = []
    material: list[str] = []
    if pr.get("isDraft"):
        material.append("draft")
    if merge_state == "DIRTY" or mergeable == "CONFLICTING":
        blockers.append("merge conflict; dedicated conflict-resolution agent required")
    if refresh_for_head:
        if refresh_accepted_awaiting_head:
            blockers.append("branch refresh accepted; awaiting a new head and fresh CI")
            material.append("pending branch refresh")
        else:
            blockers.append(f"branch refresh {refresh_status}; user decision required")
            material.append("branch refresh must not be retried automatically")
    elif branch_freshness["state"] == "behind":
        base_label = pr.get("baseRefName") or "base"
        if merge_state == "BEHIND":
            blockers.append(f"branch behind {base_label}")
        else:
            blockers.append(
                f"branch behind {base_label}; reported {merge_state} (confirmed via base compare)"
            )
    if mutation_policy["base_repo_archived"]:
        blockers.append("base repository is archived; user decision required")
        material.append("GitHub mutations are disabled for archived repositories")
    elif (
        not mutation_policy["base_repo_allowed"]
        or not mutation_policy["head_metadata_complete"]
    ):
        blockers.append("head repository scope could not be verified")
        material.append("user decision required before any branch write")
    elif not mutation_policy["branch_write_allowed"]:
        material.append("head-branch writes disabled for external fork")
    if checks["failing"]:
        blockers.append(f"{len(checks['failing'])} failing check(s)")
    if checks["pending"]:
        blockers.append(f"{len(checks['pending'])} pending check(s)")
    if review_decision == "CHANGES_REQUESTED":
        blockers.append("review decision changes requested")
    if feedback["blocking"]:
        blockers.append(f"{len(feedback['blocking'])} blocking bot feedback item(s)")
    if feedback["material"]:
        material.append(f"{len(feedback['material'])} material bot feedback item(s)")
    if advisory_cap_reached:
        material.append(
            "advisory fix-round cap reached; new advisory bot findings are report-only pending user decision"
        )
    if feedback["human_blocking"]:
        blockers.append(
            f"{len(feedback['human_blocking'])} unresolved or blocking human-authored feedback item(s) require user triage"
        )
    if new_blocking_feedback:
        material.append(
            f"{len(new_blocking_feedback)} new blocking bot feedback item(s)"
        )
    if new_material_feedback:
        material.append(
            f"{len(new_material_feedback)} new material bot feedback item(s)"
        )
    if new_human_feedback:
        material.append(
            f"{len(new_human_feedback)} new human-authored feedback item(s)"
        )
    if foreign_activity["detected"]:
        material.append(
            "foreign same-login activity detected; a concurrent babysit session "
            "appears to be driving this PR (worker dispatch suppressed)"
        )
    if attribution_drift["detected"]:
        material.append(
            f"attribution drift: {len(attribution_drift['evidence'])} recorded "
            f"write(s) landed under a self-login other than the intended write "
            f"identity '{config.intended_write_identity}' -- a degraded bot "
            "write-identity (e.g. bot-token fallback to a personal login), not a "
            "concurrent session; investigate the identity binding"
        )
    if merge_state in {"", "UNKNOWN"}:
        material.append("merge state unknown")
    elif merge_state not in {"BEHIND", "CLEAN", "HAS_HOOKS"}:
        material.append(f"merge state {merge_state}")
    # Report-only escalation signal: a non-required check degrading
    # mergeStateStatus to UNSTABLE without completing. Deliberately material,
    # never a blocker -- a blocker would re-pin the PR active and re-dispatch a
    # worker every cycle for a check no branch action clears. The runbook routes
    # remediation (branch CI vs org/settings); the engine only reports.
    if checks["stuck"]:
        material.append(
            f"{len(checks['stuck'])} check(s) holding mergeStateStatus at "
            "UNSTABLE without completing (stuck/orphaned/never-settling); "
            "escalate for routing rather than auto-fix"
        )
    review_attempt_for_head = json_object(
        json_object(review_trigger.get("request_attempt_history")).get(head_sha)
    )
    review_requested_before = head_sha in json_object(
        review_trigger.get("request_history")
    )
    review_state = str(review_trigger.get("state") or "")
    if review_state == "gate_success_unverified":
        blockers.append(
            "review gate succeeded without current-head review evidence; user decision required"
        )
    elif review_state == "engagement_signal_unverified":
        blockers.append(
            "reviewer reaction cannot be tied authoritatively to the current head; user decision required"
        )
    elif review_state == "engaged_reaction_reviewing":
        blockers.append("reviewer reacted with eyes; awaiting a current-head review")
    if review_attempt_for_head and str(review_attempt_for_head.get("status") or "") in {
        "ambiguous",
        "failed",
        "requesting",
    }:
        attempt_status = str(review_attempt_for_head.get("status") or "attempted")
        blockers.append(f"review request {attempt_status}; user decision required")
        material.append("review request must not be retried automatically")
    elif review_trigger["request_eligible"]:
        material.append("review trigger eligible")
    elif (
        review_requested_before or review_trigger["requested_head_sha"] == head_sha
    ) and review_trigger["gate_state"] == "pending":
        material.append("awaiting requested review")
    if changed:
        material.append("changed since previous snapshot")
    if new_to_state:
        material.append("new to babysit state")

    if blockers:
        status = "active"
    elif changed or new_to_state:
        status = "normal"
    elif pr.get("state") == "OPEN":
        status = "quiet"
    else:
        status = "idle"

    # A material bot-feedback item with no disposition recorded at the
    # CURRENT head has never actually been triaged for this head's content
    # -- e.g. the write-ahead worker check-in landed (clearing
    # `worker_checkin_head_unconfirmed`) but the dispatched worker crashed
    # before ever disposing it through the feedback ledger.
    # Checked against `dispositions_at_current_head` (not the full raw
    # `dispositions` map), mirroring `new_material_feedback`'s own
    # head-scoped escape valve above: when a bot reuses a material id's
    # content on a new head, `new_material_feedback` already dispatches a
    # fresh worker for that head's content precisely because a disposition
    # from an older head does not "cover" it. Checking the full
    # `dispositions` map here would then contradict that -- a stale head-A
    # disposition would make the item look already-triaged again on head B,
    # even though the head-B content was never disposed, permanently
    # suppressing `quiet_recheck_due` if the dispatched worker crashes
    # before disposing it. A disposition recorded at the current head is a
    # durable "this exact head's content was looked at" signal (`dispose`
    # accepts material ids, not just blocking ones).
    untriaged_material_feedback = [
        item
        for item in feedback["material"]
        if item["id"] not in dispositions_at_current_head
    ]

    # A clean, non-draft PR with zero blockers and no untriaged material bot
    # feedback is routed straight to the mode-appropriate merge gate per the
    # runbook (`SKILL.md`, "Fan Out"), never dispatched a worker just for
    # being newly-seen or for lacking a worker check-in at this head -- there
    # is nothing for a worker to do. Drafts are excluded so the runbook's
    # zero-blocker-draft exception (always route through a worker to assess
    # completeness) still holds. `ACTIONABLE_MERGE_STATES` (CLEAN, and
    # HAS_HOOKS on GHES repos with pre-receive hooks) is the same set the
    # merge gate itself treats as merge-ready -- HAS_HOOKS must not be
    # excluded here or a ready GHES PR would be denied the direct-gate path
    # and get a needless worker dispatch instead.
    #
    # Untriaged material feedback must also keep this PR out of the direct
    # gate: the merge gate never inspects bot feedback content, only
    # gate-level signals, so routing there would silently drop the material
    # item on the floor forever. Excluding it here does not by itself force
    # `needs_worker` -- an already-known (non-new) untriaged material item
    # still only re-dispatches a worker via `quiet_recheck_due`'s periodic
    # fallback below, once `pr_clean_ready_for_direct_gate` no longer
    # suppresses it.
    pr_clean_ready_for_direct_gate = bool(
        not pr.get("isDraft")
        and merge_state in ACTIONABLE_MERGE_STATES
        and not blockers
        and not untriaged_material_feedback
    )

    # Fan-out gate: does this PR need a fresh 1:1 worker *this cycle*? Grounded
    # in deltas against the previous snapshot, not the raw classification --
    # `classification == "active"` is sticky (e.g. the same still-pending CI
    # check re-reports every cycle) and would otherwise spawn a worker forever
    # on a PR that is simply still waiting, not newly actionable.
    identity_fields = (
        "checks_failing_identities",
        "checks_pending_identities",
    )
    identity_fields_present = [field_name in prev for field_name in identity_fields]
    if any(identity_fields_present) and not all(identity_fields_present):
        raise ValueError(
            "persisted check identity state must contain both failing and pending arrays"
        )
    # Deliberately narrower than "the pending/failing sets differ": a check
    # simply *starting* (moving into pending) or one of several pending checks
    # completing while siblings are still pending is not itself actionable and
    # would otherwise dispatch a worker that finds "still waiting" on every
    # such micro-transition during a normal CI run. Only these are actionable:
    # a genuinely new failing check (regression), a previously-failing check
    # clearing (retry or otherwise, without a new commit -- may now be
    # mergeable), or every previously-pending check having settled (CI as a
    # whole finished, worth a merge-gate check).
    if all(identity_fields_present):
        prev_checks_failing = persisted_check_identity_keys(
            prev.get("checks_failing_identities"), "checks_failing_identities"
        )
        prev_checks_pending = persisted_check_identity_keys(
            prev.get("checks_pending_identities"), "checks_pending_identities"
        )
        current_checks_failing = {
            check_identity_key(identity) for identity in checks["failing_identities"]
        }
        current_checks_pending = {
            check_identity_key(identity) for identity in checks["pending_identities"]
        }
    else:
        # One-cycle migration for snapshots written before stable identities
        # were persisted. Display names remain available for compatibility,
        # then the next saved snapshot carries the unambiguous identity arrays.
        prev_checks_failing = {
            ("LegacyDisplayName", str(name), "")
            for name in json_array(prev.get("checks_failing"))
        }
        prev_checks_pending = {
            ("LegacyDisplayName", str(name), "")
            for name in json_array(prev.get("checks_pending"))
        }
        current_checks_failing = {
            ("LegacyDisplayName", str(name), "") for name in checks["failing"]
        }
        current_checks_pending = {
            ("LegacyDisplayName", str(name), "") for name in checks["pending"]
        }
    new_failing_checks = bool(current_checks_failing - prev_checks_failing)
    resolved_failing_checks = (
        bool(prev_checks_failing - (current_checks_failing | current_checks_pending))
        and not current_checks_pending
    )
    ci_settled = bool(prev_checks_pending) and not current_checks_pending
    checks_changed = bool(prev) and (
        new_failing_checks or resolved_failing_checks or ci_settled
    )
    prev_merge_state = str(prev.get("merge_state") or "")
    merge_state_became_actionable = (
        bool(prev)
        and merge_state in ACTIONABLE_MERGE_STATES
        and prev_merge_state not in ACTIONABLE_MERGE_STATES
    )
    # Compared against `prev_human_blocking_ids`, not `prev_human_ids`: an id
    # that was present last cycle only as nonblocking `human` feedback must
    # still trip this arm when it is edited or reclassified into
    # `human_blocking` at the same id, instead of being silently filtered out
    # as merely "already seen".
    new_human_blocking_feedback = [
        item
        for item in feedback["human_blocking"]
        if item["id"] not in prev_human_blocking_ids
        and not is_self_login(item.get("author"), self_logins)
    ]
    # Symmetric to `resolved_failing_checks`: a PR previously blocked only by
    # human feedback (CHANGES_REQUESTED, an unresolved inline thread) that the
    # user has since addressed -- with no accompanying head SHA, check, or
    # merge-state change -- must still get a fresh worker/merge-gate check
    # promptly rather than waiting for `quiet_recheck_due`'s fallback window.
    prev_human_stop = json_object(prev.get("human_stop")) if bool(prev) else {}
    prev_human_blocking_required = bool(prev_human_stop.get("required"))
    resolved_human_blocking = bool(
        prev_human_blocking_required and not feedback["human_blocking"]
    )
    # Symmetric to `resolved_human_blocking`: a bot blocker that clears at the
    # same head -- the bot moves CHANGES_REQUESTED to APPROVED, deletes the
    # comment, or an inline bot thread resolves -- leaves every other delta
    # false (no new blocking/material id, no check or merge-state change), so
    # without this arm a PR that just lost its last bot blocker would sit
    # unprocessed until `quiet_recheck_due`'s fallback window even though it
    # may now be ready for the merge/follow-up gate. Excludes ids that merely
    # reclassified into `material` (a ledger dispose or downgrade, mirroring
    # `new_material_feedback`'s exclusion) -- that is a triage the agent just
    # performed, not a blocker actually clearing, and must not re-dispatch a
    # worker on its own.
    genuinely_cleared_blocking_ids = (
        prev_blocking_ids - set(blocking_feedback_ids) - set(material_feedback_ids)
    )
    resolved_blocking_feedback = (
        bool(genuinely_cleared_blocking_ids) and not feedback["blocking"]
    )
    # A draft PR marked ready for review is only reflected in `updatedAt`, not
    # `head_sha`/checks/merge-state, so it needs its own delta -- otherwise a
    # freshly-actionable PR sits unprocessed until `quiet_recheck_due` (up to
    # 4 hours) if a worker already checked in on it while still a draft.
    #
    # `"is_draft" in prev` distinguishes "key genuinely absent" (state
    # persisted by a pre-upgrade version of this engine, before `is_draft`
    # was written at all) from "key present and False" (a PR this engine has
    # already classified as not-a-draft). A bare `prev.get("is_draft")` would
    # collapse both to a falsy default, so a legacy draft PR marked ready
    # before the first post-upgrade `--write-state` call would never trip
    # this delta -- silently skipping the draft-completeness worker
    # assessment the Fan Out contract requires for a draft->ready
    # transition. Legacy/unknown previous state is treated as "was a draft"
    # (worker-required), not "wasn't", so it fails safe toward one extra
    # worker dispatch rather than a missed completeness check.
    prev_was_draft = bool(prev.get("is_draft")) if "is_draft" in prev else bool(prev)
    became_ready_for_review = bool(prev_was_draft and not pr.get("isDraft"))
    last_worker_checkin_head_sha = str(prev.get("last_worker_checkin_head_sha") or "")
    worker_checkin_head_unconfirmed = bool(
        prev and last_worker_checkin_head_sha != head_sha
    )
    # Computed here (rather than alongside `quiet_recheck_due` below) so
    # `dispatch_pending_unconfirmed` can consult it too.
    last_worker_checkin = parse_timestamp(prev.get("last_worker_checkin_at"))
    # Closes a snapshot-then-dispatch crash gap distinct from the one
    # `worker_checkin_head_unconfirmed` alone covers. `--write-state` persists
    # this cycle's `is_draft`/feedback-id state unconditionally, but
    # `record-worker-checkin` only runs later, write-ahead at actual dispatch
    # (`reference/orchestration.md`'s Fan-Out Gate Safety Net). If the run
    # exits between those two writes, the *next* snapshot's `prev` already
    # reflects the resolved delta (e.g. `is_draft` already `false`, the new
    # material id already known) -- so `became_ready_for_review`/
    # `new_material_feedback` no longer fire, and
    # `worker_checkin_head_unconfirmed` (still true, since no check-in was
    # ever recorded) is the only signal left standing. But that arm is
    # suppressible, so a PR that is otherwise clean/non-draft/zero-blocker at
    # the unchanged head would have it suppressed too -- silently dropping a
    # dispatch this run had already decided was required, straight past the
    # worker it was supposed to get and onto the direct merge gate.
    # `pending_worker_dispatch_head_sha` closes this: persisted at the *same*
    # atomic `--write-state` that absorbs the transient delta (below,
    # alongside `needs_worker`), so the two can never desync. It records "a
    # dispatch was owed as of this head", and the override below fires only
    # while that specific head's dispatch remains unconfirmed.
    #
    # Confirmation is NOT simply "the last recorded check-in head equals the
    # current head" (i.e. NOT `not worker_checkin_head_unconfirmed`) -- that
    # head-only comparison has no notion of *when* the check-in happened
    # relative to *when the obligation was created*. If the head never
    # changes across cycles (e.g. a draft is marked ready with no new
    # commit), an OLD check-in from a prior, unrelated dispatch at that same
    # head reads as "confirmed" purely by coincidence, even though it
    # predates the pending obligation entirely and never actually confirmed
    # it. That would let `worker_checkin_head_unconfirmed` read `False` while
    # a same-head dispatch obligation is still outstanding, silently
    # dropping it once the transient delta that created it (e.g.
    # `became_ready_for_review`) is itself absorbed into `prev` on the
    # following cycle. Instead, confirmation requires a check-in recorded at
    # or after the moment the obligation itself was recorded
    # (`pending_worker_dispatch_recorded_at`, persisted alongside the head
    # SHA below, from the *same* `observed_at` this run computed
    # `needs_worker` from) -- self-clearing the moment a real
    # post-obligation check-in lands at this head, or the head moves again
    # (which re-arms via `head_sha_changed`/a fresh pending head instead). A
    # legacy snapshot written before this field existed has no recorded
    # timestamp, so confirmation can never be proven -- failing safe toward
    # one extra worker dispatch, consistent with every other
    # legacy-migration default in this function.
    #
    # The override is further scoped to *why* the obligation must survive
    # becoming `pr_clean_ready_for_direct_gate`, via two independent
    # conditions rather than trusting the persisted
    # `pending_worker_dispatch_unsuppressible` class alone:
    #
    # 1. `prev_pending_dispatch_unsuppressible`: if every delta that created
    #    the obligation was suppressible (e.g. `new_to_state` while CI was
    #    still pending) and this cycle's PR is now clean-ready, forcing a
    #    worker here would dispatch one that finds nothing to do -- the exact
    #    over-dispatch the suppressible/unsuppressible split exists to
    #    prevent, just reached via the crash-recovery path instead of a
    #    same-cycle delta. An obligation that included at least one
    #    unsuppressible delta (something the direct merge gate cannot do on
    #    its own, e.g. `new_material_feedback` or `became_ready_for_review`)
    #    survives on this condition alone.
    #
    # 2. `not pr_clean_ready_for_direct_gate` (this cycle's freshly derived
    #    value, never a persisted one): a delta is only ever classified
    #    suppressible because the direct merge gate re-validates the same
    #    signal *once the PR reaches clean-ready*. If the PR is still not
    #    clean-ready this cycle -- e.g. `checks_changed` woke it while a
    #    blocking bot comment was still outstanding, so
    #    `pending_worker_dispatch_unsuppressible` was correctly persisted
    #    `False` (the delta genuinely is suppressible-class) -- the direct
    #    gate has not actually taken over verifying that obligation's
    #    concern, and the worker check it was owed still never happened.
    #    Gating solely on the persisted class would drop that obligation the
    #    moment the triggering delta is absorbed into `prev` on the next
    #    cycle, even though the PR remains exactly as blocked as when the
    #    obligation was created -- silently skipping the owed worker until
    #    `quiet_recheck_due`'s fallback window instead. Re-deriving readiness
    #    fresh each cycle (rather than trusting the persisted class in
    #    isolation) is what actually decides whether the direct gate has --
    #    or has not -- taken over.
    #
    # A legacy snapshot written before `pending_worker_dispatch_unsuppressible`
    # existed has no recorded reason kind, so it defaults to `True` -- failing
    # safe toward one extra worker dispatch, consistent with every other
    # legacy-migration default in this function.
    prev_pending_dispatch_head_sha = str(
        prev.get("pending_worker_dispatch_head_sha") or ""
    )
    prev_pending_dispatch_unsuppressible = bool(
        prev.get("pending_worker_dispatch_unsuppressible", True)
    )
    prev_pending_dispatch_recorded_at = parse_timestamp(
        prev.get("pending_worker_dispatch_recorded_at")
    )
    dispatch_confirmed_by_checkin = bool(
        prev_pending_dispatch_recorded_at is not None
        and last_worker_checkin is not None
        and last_worker_checkin >= prev_pending_dispatch_recorded_at
    )
    dispatch_pending_unconfirmed = bool(
        prev_pending_dispatch_head_sha
        and prev_pending_dispatch_head_sha == head_sha
        and (prev_pending_dispatch_unsuppressible or not pr_clean_ready_for_direct_gate)
        and not dispatch_confirmed_by_checkin
    )
    # Delta arms split into two groups against `pr_clean_ready_for_direct_gate`.
    #
    # Suppressible: each of these is fully re-validated by the direct merge
    # gate itself (mergeStateStatus already integrates required checks,
    # approvals, and conversation resolution), so a worker dispatched for one
    # of them on a cycle where the PR is clean, non-draft, and zero-blocker
    # would find nothing left to do -- whether the PR is newly-seen already
    # clean, its head SHA changed on a routine push while it stayed clean, or
    # a blocker/check/merge-state/human-review delta just resolved into this
    # same clean state (that resolution is exactly what makes
    # `pr_clean_ready_for_direct_gate` newly true this cycle).
    # `worker_checkin_head_unconfirmed` was already suppressed here before
    # this fan-out was split into two groups; it stays.
    suppressible_delta = bool(
        new_to_state
        or head_sha_changed
        or resolved_human_blocking
        or resolved_blocking_feedback
        or checks_changed
        or merge_state_became_actionable
        or worker_checkin_head_unconfirmed
    )
    # Never suppressed: each of these names something the direct merge gate
    # cannot do, so a worker is required even on an otherwise fully clean PR.
    # - `new_blocking_feedback`/`new_human_blocking_feedback` structurally
    #   cannot coincide with `pr_clean_ready_for_direct_gate` (both already
    #   feed `blockers`), listed for completeness only.
    # - `new_material_feedback` is a nonblocking bot finding the merge gate
    #   never inspects or triages -- only a worker resolves it.
    # - `became_ready_for_review`: SKILL.md's Fan Out section requires a
    #   worker to assess draft completeness on every draft-to-ready
    #   transition regardless of CI cleanliness ("Zero-blocker drafts are
    #   the exception: always route them through a worker"); the merge gate
    #   only re-validates mergeability, never completeness.
    unsuppressible_delta = bool(
        new_blocking_feedback
        or new_material_feedback
        or new_human_blocking_feedback
        or became_ready_for_review
    )
    worker_actionable_delta = bool(
        (suppressible_delta and not pr_clean_ready_for_direct_gate)
        or unsuppressible_delta
        # Bypasses the direct-gate suppression on its own -- see
        # `dispatch_pending_unconfirmed`'s definition above for why a
        # cross-cycle dispatch obligation must win even when every delta that
        # originally created it has since been absorbed into `prev`.
        or dispatch_pending_unconfirmed
    )
    # `last_worker_checkin` is computed earlier, alongside
    # `dispatch_pending_unconfirmed`, which also needs it.
    observed = parse_timestamp(observed_at)
    # Also gated on `pr_clean_ready_for_direct_gate`: a clean, non-draft,
    # zero-blocker PR routed straight to the merge gate never gets a worker
    # check-in recorded (that only happens at worker dispatch), so without
    # this guard `last_worker_checkin is None` would stay permanently true
    # for it and this fallback would force `needs_worker` every single cycle
    # -- silently reintroducing the same over-dispatch the
    # `suppressible_delta` group above was added to fix.
    quiet_recheck_due = bool(
        not worker_actionable_delta
        and not pr_clean_ready_for_direct_gate
        and str(pr.get("state") or "").upper() == "OPEN"
        and not pr.get("isDraft")
        and (
            last_worker_checkin is None
            or (
                observed is not None
                and (observed - last_worker_checkin).total_seconds()
                >= quiet_recheck_seconds
            )
        )
    )
    # `refresh_accepted_awaiting_head` overrides every delta and the quiet
    # fallback alike, not just the suppressible group
    # `pr_clean_ready_for_direct_gate` already gates: the "awaiting a new
    # head" blocker (above) correctly keeps this PR out of
    # `pr_clean_ready_for_direct_gate`, but that same falseness is exactly
    # what lets the suppressible-delta group's
    # `not pr_clean_ready_for_direct_gate` clause escape suppression -- so
    # `checks_changed` reporting transiently while GitHub settles the refresh,
    # `worker_checkin_head_unconfirmed` (no check-in was ever recorded for
    # this stale, about-to-be-replaced head), `merge_state_became_actionable`
    # flickering, or even a stale `dispatch_pending_unconfirmed` obligation
    # from before the refresh was requested, would all still fan out a
    # worker to a PR the runbook says must sit idle
    # (`reference/freshness.md`, step 3: "end work on that PR until a
    # later snapshot observes a different head SHA... even if merge state
    # transiently changes"). `quiet_recheck_due`'s periodic fallback must be
    # suppressed the same way -- it is itself a worker dispatch, and waiting
    # out GitHub's async update is not "quiet", it is expected. This lifts on
    # its own the moment the head actually changes: `refresh_for_head` is
    # keyed by the exact requested source SHA, so a new head either finds no
    # entry at all or one for a distinct, unrelated refresh.
    #
    # `foreign_activity` suppresses the same way, for a different reason: the
    # mutation ledger proves another driver is already working this PR under
    # our own login, so dispatching our own worker on top of it would
    # double-act. The suppression is reported as a contention finding above,
    # never silently.
    needs_worker = bool(
        (worker_actionable_delta or quiet_recheck_due)
        and not refresh_accepted_awaiting_head
        and not foreign_activity["detected"]
    )
    # Reasons in the suppressible group are filtered through the same
    # `pr_clean_ready_for_direct_gate` check as `suppressible_delta` above,
    # so a raw delta suppressed this cycle (e.g. a head SHA change on an
    # already-clean PR) is never reported as a reason when `needs_worker` is
    # actually False. Reasons in the unsuppressible group are never filtered.
    # Every reason is additionally dropped while
    # `refresh_accepted_awaiting_head` or a foreign-activity hold is in
    # effect, mirroring `needs_worker`'s own overrides just above --
    # otherwise a populated reasons list would contradict `needs_worker`
    # being forced `False`.
    needs_worker_reasons = (
        []
        if refresh_accepted_awaiting_head or foreign_activity["detected"]
        else [
            reason
            for reason, present, suppressible in (
                ("new_to_state", new_to_state, True),
                ("head_sha_changed", head_sha_changed, True),
                ("new_blocking_feedback", bool(new_blocking_feedback), False),
                ("new_material_feedback", bool(new_material_feedback), False),
                (
                    "new_human_blocking_feedback",
                    bool(new_human_blocking_feedback),
                    False,
                ),
                ("resolved_human_blocking", resolved_human_blocking, True),
                ("resolved_blocking_feedback", resolved_blocking_feedback, True),
                ("checks_changed", checks_changed, True),
                ("merge_state_became_actionable", merge_state_became_actionable, True),
                ("became_ready_for_review", became_ready_for_review, False),
                # Not suppressible while a same-head dispatch remains unconfirmed
                # from a prior cycle -- see `dispatch_pending_unconfirmed` above.
                (
                    "worker_checkin_head_unconfirmed",
                    worker_checkin_head_unconfirmed,
                    not dispatch_pending_unconfirmed,
                ),
                # `dispatch_pending_unconfirmed` can be true while
                # `worker_checkin_head_unconfirmed` is false -- a same-head
                # check-in that predates the pending obligation confirms neither
                # signal the same way, so this needs its own reason: without it,
                # a worker forced in solely by an unconfirmed crash-recovered
                # obligation would report no reason at all. Never suppressible:
                # by the time this is true, either `prev_pending_dispatch_unsuppressible`
                # already gated it to an obligation the direct merge gate cannot
                # resolve on its own, or (per its definition above) the PR is
                # still not `pr_clean_ready_for_direct_gate` this cycle -- in
                # that case the direct gate has not taken over the obligation's
                # concern either, so it must not be filtered out the way other
                # suppressible reasons are.
                ("dispatch_pending_unconfirmed", dispatch_pending_unconfirmed, False),
                ("quiet_recheck_due", quiet_recheck_due, True),
            )
            if present and (not suppressible or not pr_clean_ready_for_direct_gate)
        ]
    )

    # Write-ahead companion to `record-worker-checkin`: this snapshot's own
    # verdict on whether a worker was required, keyed to the head it was
    # required for. Persisted unconditionally by `--write-state` (see
    # `persisted_pr_state`) in the same atomic write as the transient state
    # this fixes the crash gap for, so the two can never desync -- unlike the
    # ledger check-in, which is written later, only at actual dispatch.
    pending_worker_dispatch_head_sha = head_sha if needs_worker else ""
    # Recorded alongside the head SHA so a later cycle's
    # `dispatch_pending_unconfirmed` (above) can tell a suppressible-only
    # obligation from one that included an unsuppressible delta -- see that
    # variable's definition for why the distinction matters. `unsuppressible_delta`
    # is exactly the same predicate the reasons list above labels
    # non-suppressible, so no new classification is introduced here.
    pending_worker_dispatch_unsuppressible = bool(needs_worker and unsuppressible_delta)
    # Recorded from the same `observed_at` this run computed `needs_worker`
    # from, so a later cycle's `dispatch_confirmed_by_checkin` (above) can
    # tell a check-in that actually confirms this obligation from one that
    # merely happens to share this head's SHA by coincidence (e.g. an older,
    # unrelated check-in at a head that never changed across cycles) -- see
    # `dispatch_pending_unconfirmed`'s definition above for why head-SHA
    # equality alone cannot prove confirmation.
    pending_worker_dispatch_recorded_at = observed_at if needs_worker else ""

    return {
        "key": key,
        "repo": repo,
        "number": number,
        "url": pr.get("url"),
        "title": pr.get("title"),
        "author": author_login(pr),
        "author_type": actor_kind(pr, config.feedback),
        "head_ref": pr.get("headRefName"),
        "head_sha": head_sha,
        "base_ref": pr.get("baseRefName"),
        "base_sha": pr.get("baseRefOid"),
        "head_repository": mutation_policy["head_repo"],
        "head_repository_owner": mutation_policy["head_owner"],
        "is_cross_repository": mutation_policy["is_cross_repository"],
        "maintainer_can_modify": mutation_policy["maintainer_can_modify"],
        "mutation_policy": mutation_policy,
        "head_ref_uniqueness": {
            "checked": False,
            "unique": False,
            "matching_prs": [],
            "shared_with": [],
        },
        "updated_at": updated_at,
        "is_draft": bool(pr.get("isDraft")),
        "review_decision": review_decision,
        "human_stop": human_stop,
        "merge_state": merge_state,
        "mergeable": mergeable,
        "branch_freshness": branch_freshness,
        "branch_refresh": branch_refresh,
        "branch_refresh_history": branch_refresh_history,
        "advisory_fix_rounds": {
            "count": advisory_round_count,
            "cap": config.advisory_fix_round_cap,
            "cap_reached": advisory_cap_reached,
        },
        "checks": checks,
        "review_trigger": review_trigger,
        "foreign_activity": foreign_activity,
        "attribution_drift": attribution_drift,
        "feedback": {
            "blocking": feedback["blocking"],
            "material": feedback["material"],
            "human_blocking": feedback["human_blocking"],
            "human": feedback["human"],
        },
        "new_feedback": {
            "blocking": new_blocking_feedback,
            "material": new_material_feedback,
            "human": new_human_feedback,
        },
        "classification": status,
        "blockers": blockers,
        "material_findings": material,
        "feedback_ids": {
            "blocking": blocking_feedback_ids,
            "material": material_feedback_ids,
            "human": human_feedback_ids,
            "human_blocking": human_blocking_feedback_ids,
        },
        "needs_worker": needs_worker,
        "needs_worker_reasons": needs_worker_reasons,
        # Surfaced (not just used locally) so `apply_head_ref_guard`'s late
        # branch-uniqueness-clear arm can consult the exact same verdict
        # instead of recomputing a shorter version of this predicate that
        # omits `untriaged_material_feedback` -- see that guard's use of this
        # field for why the two must never diverge. Same-cycle only, not
        # persisted by `persisted_pr_state`.
        "pr_clean_ready_for_direct_gate": pr_clean_ready_for_direct_gate,
        "last_worker_checkin_at": prev.get("last_worker_checkin_at") or "",
        "last_worker_checkin_head_sha": last_worker_checkin_head_sha,
        "pending_worker_dispatch_head_sha": pending_worker_dispatch_head_sha,
        "pending_worker_dispatch_unsuppressible": pending_worker_dispatch_unsuppressible,
        "pending_worker_dispatch_recorded_at": pending_worker_dispatch_recorded_at,
    }


def apply_head_ref_guard(
    pr: dict[str, Any],
    *,
    checked: bool,
    matching_prs: list[str],
    prev_unique: bool | None = None,
) -> None:
    current_key = str(pr.get("key") or "")
    peers = sorted(key for key in set(matching_prs) if key != current_key)
    unique = checked and not peers
    pr["head_ref_uniqueness"] = {
        "checked": checked,
        "unique": unique,
        "matching_prs": sorted(set(matching_prs)),
        "shared_with": peers,
    }
    if unique:
        # This guard runs after `classify_pr` already computed `needs_worker`
        # from the prior snapshot, so a PR blocked only by an unresolved or
        # shared head ref last cycle -- now cleared -- would otherwise wait
        # out `quiet_recheck_due`'s fallback window even though branch writes
        # just became allowed. Force it in, same as any other cleared blocker
        # -- unless the PR is otherwise direct-gate-ready. Reads
        # `pr_clean_ready_for_direct_gate` verbatim from `classify_pr` rather
        # than recomputing it here: a local re-derivation previously omitted
        # the `untriaged_material_feedback` clause, so a PR with already-known
        # material bot feedback and a recent check-in was wrongly treated as
        # direct-gate-ready the moment branch uniqueness cleared, suppressing
        # `branch_uniqueness_cleared` even though the merge gate never
        # triages bot feedback. This guard never adds a blocker on the unique
        # path, so `pr["blockers"]` here already reflects every *other*
        # blocker for the current cycle. A non-draft, CLEAN/HAS_HOOKS PR with
        # none of those left, and no untriaged material feedback, has nothing
        # left for a worker to do and belongs on the direct merge gate per
        # the runbook's Fan Out contract.
        if prev_unique is False and not pr.get("needs_worker"):
            direct_gate_ready = bool(pr.get("pr_clean_ready_for_direct_gate"))
            if not direct_gate_ready:
                pr["needs_worker"] = True
                reasons = pr.get("needs_worker_reasons")
                if (
                    is_json_array(reasons)
                    and "branch_uniqueness_cleared" not in reasons
                ):
                    reasons.append("branch_uniqueness_cleared")
                # `classify_pr` already finalized `pending_worker_dispatch_head_sha`
                # (empty, since `needs_worker` was False there) before this
                # late arm ran and flipped `needs_worker` to True. Without
                # this, `--write-state` would persist an empty pending-dispatch
                # head for a PR this cycle just decided needs a worker,
                # reopening the exact crash gap `pending_worker_dispatch_head_sha`
                # exists to close (see its definition in `classify_pr`), but
                # for this one arm. The `not pr.get("needs_worker")` guard
                # above -- required to even reach this branch -- guarantees
                # `pending_worker_dispatch_head_sha` is still `""` here (it is
                # only ever non-empty when `needs_worker` was already True),
                # so setting it unconditionally cannot clobber an obligation
                # recorded earlier this cycle for a different reason.
                pr["pending_worker_dispatch_head_sha"] = str(pr.get("head_sha") or "")
                # `pending_worker_dispatch_unsuppressible` was likewise
                # finalized `False` by `classify_pr` (the same "needs_worker
                # was False there" guarantee above), and is deliberately left
                # as-is here rather than set `True`: this arm only ever fires
                # while `not direct_gate_ready`, the same "not yet
                # clean-ready" condition every other suppressible reason is
                # gated on, so `branch_uniqueness_cleared` belongs in that
                # same suppressible category, not the unsuppressible one.
                # `pending_worker_dispatch_recorded_at` is left at `classify_pr`'s
                # empty finalization for the same reason: `dispatch_pending_unconfirmed`
                # only ever consults it while `pending_worker_dispatch_unsuppressible`
                # is `True`, which this suppressible-only obligation never is.
        return
    pr["mutation_policy"]["branch_write_allowed"] = False
    if peers:
        blocker = "head branch is shared by multiple open PRs; user decision required"
        material = "shared head ref: " + ", ".join(peers)
    else:
        blocker = "head-branch uniqueness could not be verified"
        material = "branch writes disabled until a complete alias check succeeds"
    if blocker not in pr["blockers"]:
        pr["blockers"].append(blocker)
    if material not in pr["material_findings"]:
        pr["material_findings"].append(material)
    pr["classification"] = "active"


def prev_head_ref_unique(
    pr: dict[str, Any], previous_prs: dict[str, Any] | None
) -> bool | None:
    if not previous_prs:
        return None
    prev = json_object(previous_prs.get(str(pr.get("key") or "")))
    if not prev:
        return None
    prev_uniqueness = json_object(prev.get("head_ref_uniqueness"))
    if not prev_uniqueness:
        return None
    return bool(prev_uniqueness.get("unique"))


def is_head_ref_alias_error(message: str) -> bool:
    """True for an advisory head-ref alias cross-check failure (valid snapshot)."""
    return HEAD_REF_ALIAS_ERROR_MARKER in message


def annotate_queue_head_refs(
    prs: list[dict[str, Any]],
    complete: bool,
    errors: list[str] | None = None,
    previous_prs: dict[str, Any] | None = None,
) -> None:
    """Prove branch uniqueness globally for each distinct watched head ref."""
    groups: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for pr in prs:
        head_repo = str(pr.get("head_repository") or "").casefold()
        head_ref = str(pr.get("head_ref") or "")
        if complete and head_repo and head_ref:
            groups.setdefault((head_repo, head_ref), []).append(pr)
        else:
            apply_head_ref_guard(
                pr,
                checked=False,
                matching_prs=[],
                prev_unique=prev_head_ref_unique(pr, previous_prs),
            )

    for group_prs in groups.values():
        representative = group_prs[0]
        try:
            matches = find_open_prs_for_head_ref(representative)
            expected = {str(pr["key"]).casefold() for pr in group_prs}
            checked = expected.issubset({key.casefold() for key in matches})
            if not checked:
                raise RuntimeError("association query did not return every watched PR")
        except Exception as exc:
            message = (
                f"{representative['key']} {HEAD_REF_ALIAS_ERROR_MARKER} {exc}"
            )
            if errors is not None:
                errors.append(message)
            for pr in group_prs:
                apply_head_ref_guard(
                    pr,
                    checked=False,
                    matching_prs=[],
                    prev_unique=prev_head_ref_unique(pr, previous_prs),
                )
            continue
        for pr in group_prs:
            apply_head_ref_guard(
                pr,
                checked=True,
                matching_prs=matches,
                prev_unique=prev_head_ref_unique(pr, previous_prs),
            )


def recommend_cadence(classifications: list[str]) -> str:
    if not classifications:
        return "idle"
    if "active" in classifications:
        return "active"
    if "normal" in classifications:
        return "normal"
    return "quiet"

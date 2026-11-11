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
    classify_approval_held_checks,
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
from babysit_feedback import collect_feedback, human_stop_from_feedback
from babysit_gh import compare_shows_behind, find_open_prs_for_head_ref
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
# Provenance classes in `safety.md`'s (a)/(b)/(c) round taxonomy: (a) a genuine
# duplicate, (b) a new distinct finding, (c) a self-inflicted finding against
# text this lane's own prior fix introduced.
ADVISORY_ROUND_CLASSES = ("a", "b", "c")


def legacy_check_identity_keys(names: Any) -> set[tuple[str, str, str]]:
    """Key a pre-identity snapshot's display names into the identity tuple shape.

    `LegacyDisplayName` is a type no live rollup entry carries, so a migrated
    name can only ever compare equal to another migrated name: a one-cycle
    display-name comparison, never a false match against a real
    StatusContext/CheckRun identity.
    """
    return {("LegacyDisplayName", str(name), "") for name in json_array(names)}


def advisory_round_composition(record: Any) -> str:
    """Classify one recorded advisory round as `all-c`, `mixed`, or `unknown`.

    `unknown` is the answer for every round recorded before per-finding classes
    were persisted, and for any record whose counts are unreadable. It is not a
    synonym for "no (c) findings": the tripwire treats it as fail-closed.
    """
    if not is_json_object(record):
        return "unknown"
    classes = json_object(record.get("finding_classes"))
    counts: dict[str, int] = {}
    for name in ADVISORY_ROUND_CLASSES:
        value = classes.get(name)
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            return "unknown"
        counts[name] = value
    if not sum(counts.values()):
        return "unknown"
    return "all-c" if counts["c"] and not counts["a"] and not counts["b"] else "mixed"


def advisory_round_sequence(record: Any) -> int:
    """The explicit write sequence of one recorded round, 0 when absent."""
    if not is_json_object(record):
        return 0
    value = record.get("sequence")
    if isinstance(value, int) and not isinstance(value, bool) and value > 0:
        return value
    return 0


def ordered_advisory_rounds(rounds: Any) -> list[tuple[str, dict[str, Any]]]:
    """Recorded advisory rounds oldest first, by their explicit write sequence.

    The sequence is the chronology: the ledger serializes with sorted keys, so
    after a reload the mapping order is head-SHA order, and a timestamp can tie
    or be unreadable -- neither survives as write order. Rounds recorded before
    sequences were persisted have only their write-ahead timestamp; they sort
    before every sequenced round, which is when they were written, with equal
    or unreadable timestamps left to the stable sort.
    """

    def order(item: tuple[str, dict[str, Any]]) -> tuple[int, str, int]:
        sequence = advisory_round_sequence(item[1])
        if not sequence:
            return (0, str(item[1].get("recorded_at") or ""), 0)
        return (1, "", sequence)

    records = json_object(rounds)
    return sorted(
        ((str(head), json_object(record)) for head, record in records.items()),
        key=order,
    )


def _advisory_round_summary(entry: tuple[str, dict[str, Any]]) -> dict[str, Any]:
    head, record = entry
    return {"head_sha": head, "composition": advisory_round_composition(record)}


def advisory_non_convergence_tripwire(rounds: Any) -> dict[str, Any]:
    """Evaluate `safety.md`'s second-consecutive-all-(c) tripwire from the ledger.

    The test is over consecutive ADVISORY rounds -- the only rounds the ledger
    records -- and it fails closed on an unclassified predecessor, so a round
    recorded before classification was persisted arms the tripwire rather than
    silently resetting the count.
    """
    ordered = ordered_advisory_rounds(rounds)
    result: dict[str, Any] = {
        "armed": False,
        "latest": _advisory_round_summary(ordered[-1]) if ordered else {},
        "previous": _advisory_round_summary(ordered[-2]) if len(ordered) > 1 else {},
    }
    if len(ordered) < 2:
        return {**result, "basis": "fewer than two recorded advisory rounds"}
    latest = str(result["latest"]["composition"])
    previous = str(result["previous"]["composition"])
    if latest != "all-c":
        return {
            **result,
            "basis": f"the latest advisory round is {latest}, not all-(c)",
        }
    if previous == "all-c":
        basis = "two consecutive all-(c) advisory rounds"
    elif previous == "unknown":
        basis = (
            "the latest advisory round is all-(c) and the round before it is "
            "unclassified; an unclassified predecessor fails closed"
        )
    else:
        return {
            **result,
            "basis": f"the latest advisory round is all-(c) but the round before it is {previous}",
        }
    return {**result, "armed": True, "basis": basis}


@dataclass(frozen=True)
class ClassifyConfig:
    """All identity sets ship empty and every scalar carries its safe default,
    so an unconfigured classifier is dormant on every optional integration and
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


def _validated_positive_seconds(value: float, flag: str) -> float:
    """Coerce one seconds-valued override, refusing anything not finite/positive.

    Shared by the per-flag validators below so the two cannot drift; `flag`
    names the CLI option in the refusal so the message stays specific.
    """
    message = f"{flag} must be a finite number greater than zero"
    try:
        seconds = float(value)
    except (TypeError, ValueError) as error:
        raise ValueError(message) from error
    if not math.isfinite(seconds) or seconds <= 0:
        raise ValueError(message)
    return seconds


def validated_max_quiet_recheck_seconds(value: float) -> float:
    return _validated_positive_seconds(value, "--max-quiet-recheck-seconds")


def validated_stuck_check_age_seconds(value: float) -> float:
    return _validated_positive_seconds(value, "--stuck-check-age-seconds")


def compute_branch_freshness(pr: dict[str, Any]) -> dict[str, Any]:
    """Classify branch staleness from `mergeStateStatus`, with one fallback.

    Pure function: the only I/O this depends on (the base compare, and for a
    behind CLEAN/HAS_HOOKS head the merge-queue rules read) happens once, in
    `view_pr`, and is read here off `pr["_base_compare"]` and
    `pr["_base_merge_queue"]`. This keeps classification network-free and keeps
    `view_pr` the single choke point both the snapshot orchestrator and the
    branch-refresh CLI's revalidation already call, so a live re-check gets the
    same enrichment for free.

    Falls back to the compare-confirmed signal only when the compare proves
    outstanding base commits (`behind_by > 0`, `status` in {behind, diverged})
    and `mergeStateStatus` is BLOCKED, or CLEAN/HAS_HOOKS on a base whose rules
    were read and require no merge queue (a queue tests the PR against the
    latest base itself; an unread answer leaves the head not behind this cycle).
    Every other cause of BLOCKED (a real merge conflict, a pending human review,
    ...) is untouched by this function -- it only ever flips those states to
    "behind"; conflict, human-stop, lease, unique head-ref, and the
    per-source-SHA refresh ledger are all still enforced independently by the
    caller.
    """
    merge_state = str(pr.get("mergeStateStatus") or "").upper()
    mergeable = str(pr.get("mergeable") or "").upper()
    if merge_state == "DIRTY" or mergeable == "CONFLICTING":
        return {"state": "conflicting", "source": "mergeStateStatus"}
    if merge_state == "BEHIND":
        return {"state": "behind", "source": "mergeStateStatus"}
    if merge_state in {"", "UNKNOWN"}:
        return {"state": "unknown", "source": "mergeStateStatus"}
    compare = pr.get("_base_compare")
    if compare_shows_behind(compare) and (
        merge_state == "BLOCKED"
        or (
            merge_state in {"CLEAN", "HAS_HOOKS"}
            and pr.get("_base_merge_queue") is False
        )
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
            or (cross_repository is True and head_owner in configured_owners)
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


def _ledgered_comment_ids(prior: dict[str, Any]) -> set[str]:
    """Every review-trigger comment id our own mutation ledger recorded.

    The two same-login arms below ask opposite questions of the same evidence --
    `detect_foreign_activity` looks for a trigger comment that is NOT in here,
    `detect_attribution_drift` for one that IS -- so the ledger read is shared:
    a divergence between the two would silently change which comments each arm
    considers accounted for.
    """
    recorded: set[str] = set()
    for history_key in ("request_history", "request_attempt_history"):
        for entry in json_object(prior.get(history_key)).values():
            if is_json_object(entry) and entry.get("comment_id") is not None:
                recorded.add(str(entry["comment_id"]))
    return recorded


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
    known_comment_ids = _ledgered_comment_ids(prior)
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
    recorded_comment_ids = _ledgered_comment_ids(prior)
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
    self_logins = normalize_self_logins(config.self_logins)
    human_stop = human_stop_from_feedback(feedback, self_logins)
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
    # Held for approval: failing in the rollup (the merge gate keeps holding),
    # but escalated to a person here rather than counted as a fixable failure.
    checks["approval_held"] = classify_approval_held_checks(checks["checks"])
    approval_held_keys = {
        check_identity_key(check) for check in checks["approval_held"]
    }
    fixable_failing = [
        identity
        for identity in checks["failing_identities"]
        if check_identity_key(identity) not in approval_held_keys
    ]
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
        branch_behind=branch_freshness["state"] == "behind",
        config=config.review_trigger,
    )
    foreign_activity = detect_foreign_activity(pr, prev, config)
    attribution_drift = detect_attribution_drift(pr, prev, config)
    advisory_rounds = dict(prev.get("advisory_fix_rounds") or {})
    recorded_advisory_rounds = dict(advisory_rounds.get("rounds") or {})
    advisory_round_count = len(recorded_advisory_rounds)
    advisory_cap_reached = advisory_round_count >= config.advisory_fix_round_cap
    advisory_tripwire = advisory_non_convergence_tripwire(recorded_advisory_rounds)
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
    prev_human_blocking_ids = set(prev.get("human_blocking_feedback_ids") or [])
    blocking_feedback_ids = [item["id"] for item in feedback["blocking"]]
    material_feedback_ids = [item["id"] for item in feedback["material"]]
    human_blocking_feedback_ids = [item["id"] for item in feedback["human_blocking"]]
    human_items = (*feedback["human_blocking"], *feedback["human"])
    human_feedback_ids = [item["id"] for item in human_items]
    new_blocking_feedback = [
        item for item in feedback["blocking"] if item["id"] not in prev_blocking_ids
    ]
    # An id already seen as blocking or material is not new: a ledger dispose
    # reclassifies a blocking item to material at the same id and head. GitHub
    # can also reuse a comment id for different content on a new head, so a
    # seen id counts as new again once the head changed, unless a disposition
    # recorded at the current head covers it (an older-head one does not).
    new_material_feedback = [
        item
        for item in feedback["material"]
        if (
            item["id"] not in prev_material_ids
            and item["id"] not in prev_blocking_ids
        )
        or (head_sha_changed and item["id"] not in dispositions_at_current_head)
    ]
    # The human arms drop this engine's own posts: it comments under the
    # operator's login, so without this every prior worker reply would count
    # as new human feedback and re-dispatch forever (the rule
    # `reference/review-discipline.md` §1 sets for classification replies).
    # Bot arms need no such filter, since `collect_feedback` routes only
    # bot-authored items there. Only the new-feedback deltas filter:
    # self-authored items stay in `feedback["human_blocking"]`, so a maintainer
    # can still human-stop their own PR.
    new_human_feedback = [
        item
        for item in human_items
        if item["id"] not in prev_human_ids
        and not is_self_login(item.get("author"), self_logins)
    ]
    # Against `prev_human_blocking_ids`, not `prev_human_ids`, so an id edited
    # or reclassified from nonblocking into blocking still trips this arm.
    new_human_blocking_feedback = [
        item
        for item in feedback["human_blocking"]
        if item["id"] not in prev_human_blocking_ids
        and not is_self_login(item.get("author"), self_logins)
    ]
    changed = head_sha_changed or (
        bool(prev) and prev.get("updated_at") != updated_at
    )
    new_to_state = not prev

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
    if fixable_failing:
        blockers.append(f"{len(fixable_failing)} failing check(s)")
    if checks["approval_held"]:
        material.append(
            f"{len(checks['approval_held'])} check(s) held for approval "
            "(action_required); only a maintainer can release them in the web UI "
            "-- escalate, never re-run, push, or wait"
        )
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
    if advisory_tripwire["armed"]:
        material.append(
            f"non-convergence tripwire armed ({advisory_tripwire['basis']}); change METHOD per safety.md's Verify Before Escalating Non-Convergence"
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
    attempt_status = str(review_attempt_for_head.get("status") or "")
    if attempt_status in {"ambiguous", "failed", "requesting"}:
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

    # A material item with no disposition at the CURRENT head was never
    # triaged for this head's content (e.g. the worker checked in, then
    # crashed before disposing it). An older-head disposition does not count,
    # matching `new_material_feedback`; counting it would suppress
    # `quiet_recheck_due` for content no one disposed.
    untriaged_material_feedback = [
        item
        for item in feedback["material"]
        if item["id"] not in dispositions_at_current_head
    ]

    # A clean, non-draft PR with zero blockers goes straight to the merge gate
    # (`SKILL.md`, "Fan Out"): a worker would have nothing to do. Drafts always
    # route through a worker to assess completeness. `ACTIONABLE_MERGE_STATES`
    # is the set the merge gate treats as merge-ready, HAS_HOOKS (GHES)
    # included. Untriaged material feedback keeps the PR out too, since the
    # merge gate never reads bot feedback; a known untriaged item still waits
    # for `quiet_recheck_due` rather than forcing `needs_worker`.
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
    has_failing = "checks_failing_identities" in prev
    if has_failing != ("checks_pending_identities" in prev):
        raise ValueError(
            "persisted check identity state must contain both failing and pending arrays"
        )
    # Narrower than "the check sets differ": a check starting, or one of
    # several pending checks finishing, is not actionable. Only a new failing
    # check, a failing check clearing, or all pending checks settling is.
    if has_failing:
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
        prev_checks_failing = legacy_check_identity_keys(prev.get("checks_failing"))
        prev_checks_pending = legacy_check_identity_keys(prev.get("checks_pending"))
        current_checks_failing = legacy_check_identity_keys(checks["failing"])
        current_checks_pending = legacy_check_identity_keys(checks["pending"])
    new_failing_checks = bool(
        current_checks_failing - prev_checks_failing - approval_held_keys
    )
    resolved_failing_checks = not current_checks_pending and bool(
        prev_checks_failing - current_checks_failing
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
    # Symmetric to `resolved_failing_checks`: a PR previously blocked only by
    # human feedback (CHANGES_REQUESTED, an unresolved inline thread) that the
    # user has since addressed -- with no accompanying head SHA, check, or
    # merge-state change -- must still get a fresh worker/merge-gate check
    # promptly rather than waiting for `quiet_recheck_due`'s fallback window.
    resolved_human_blocking = bool(
        json_object(prev.get("human_stop")).get("required")
        and not feedback["human_blocking"]
    )
    # The same for a bot blocker clearing at the same head, which trips no
    # other delta. An id that only reclassified into `material` (a ledger
    # dispose or downgrade) is a triage just performed, not a clearing.
    genuinely_cleared_blocking_ids = (
        prev_blocking_ids - set(blocking_feedback_ids) - set(material_feedback_ids)
    )
    resolved_blocking_feedback = (
        bool(genuinely_cleared_blocking_ids) and not feedback["blocking"]
    )
    # Draft-to-ready shows only in `updatedAt`, so it needs its own delta. A
    # legacy `prev` with no `is_draft` key counts as a draft, failing safe
    # toward one extra worker dispatch over a missed completeness check.
    prev_was_draft = bool(prev.get("is_draft")) if "is_draft" in prev else bool(prev)
    became_ready_for_review = bool(prev_was_draft and not pr.get("isDraft"))
    last_worker_checkin_head_sha = str(prev.get("last_worker_checkin_head_sha") or "")
    worker_checkin_head_unconfirmed = bool(
        prev and last_worker_checkin_head_sha != head_sha
    )
    # Computed here (rather than alongside `quiet_recheck_due` below) so
    # `dispatch_pending_unconfirmed` can consult it too.
    last_worker_checkin = parse_timestamp(prev.get("last_worker_checkin_at"))
    # Crash gap: `--write-state` persists this cycle's delta state, but
    # `record-worker-checkin` runs only later, at dispatch
    # (`reference/orchestration.md`'s Fan-Out Gate Safety Net). A run that
    # exits between them leaves the next `prev` with the delta absorbed, and
    # the one arm still standing, `worker_checkin_head_unconfirmed`, is
    # suppressible. `pending_worker_dispatch_head_sha`, persisted in the same
    # write as the delta, records the owed dispatch so it survives.
    #
    # Confirmation needs a check-in at or after the obligation's
    # `pending_worker_dispatch_recorded_at`, not just one at the same head: an
    # older check-in at an unchanged head predates the obligation. The
    # obligation survives a clean-ready PR only when it included an
    # unsuppressible delta, and otherwise only while the PR is still not
    # clean-ready this cycle, since the direct gate has then not taken over.
    # Legacy snapshots missing either field fail safe toward one extra
    # dispatch.
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

    # The write-ahead dispatch obligation `dispatch_pending_unconfirmed` reads
    # next cycle: `--write-state` persists it in the same write as this
    # cycle's delta state, unlike the check-in written only at dispatch.
    pending_worker_dispatch_head_sha = head_sha if needs_worker else ""
    pending_worker_dispatch_unsuppressible = bool(needs_worker and unsuppressible_delta)
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
        # False when this PR was hydrated over REST because the session is not
        # served GraphQL: thread resolution is unproven for it, so the merge
        # gate will hold it as readiness UNPROVEN. Absent key means the record
        # predates the fallback, which was always a GraphQL read.
        "graphql_available": bool(pr.get("_graphql_available", True)),
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
            "non_convergence_tripwire": advisory_tripwire,
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
        # than recomputing it here: a local re-derivation can drift (omitting
        # the `untriaged_material_feedback` clause, say, would treat a PR with
        # already-known material bot feedback and a recent check-in as
        # direct-gate-ready the moment branch uniqueness cleared, suppressing
        # `branch_uniqueness_cleared` even though the merge gate never
        # triages bot feedback). This guard never adds a blocker on the unique
        # path, so `pr["blockers"]` here already reflects every *other*
        # blocker for the current cycle. A non-draft, CLEAN/HAS_HOOKS PR with
        # none of those left, and no untriaged material feedback, has nothing
        # left for a worker to do and belongs on the direct merge gate per
        # the runbook's Fan Out contract.
        if (
            prev_unique is False
            and not pr.get("needs_worker")
            and not pr.get("pr_clean_ready_for_direct_gate")
        ):
            pr["needs_worker"] = True
            reasons = pr.get("needs_worker_reasons")
            if is_json_array(reasons) and "branch_uniqueness_cleared" not in reasons:
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
            # while the PR is not `pr_clean_ready_for_direct_gate`, the same
            # "not yet clean-ready" condition every other suppressible reason
            # is gated on, so `branch_uniqueness_cleared` belongs in that
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
    prev_uniqueness = json_object(prev.get("head_ref_uniqueness"))
    return bool(prev_uniqueness.get("unique")) if prev_uniqueness else None


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

    def guard(pr: dict[str, Any], checked: bool, matches: list[str]) -> None:
        apply_head_ref_guard(
            pr,
            checked=checked,
            matching_prs=matches,
            prev_unique=prev_head_ref_unique(pr, previous_prs),
        )

    groups: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for pr in prs:
        head_repo = str(pr.get("head_repository") or "").casefold()
        head_ref = str(pr.get("head_ref") or "")
        if complete and head_repo and head_ref:
            groups.setdefault((head_repo, head_ref), []).append(pr)
        else:
            guard(pr, False, [])

    for group_prs in groups.values():
        representative = group_prs[0]
        try:
            matches = find_open_prs_for_head_ref(representative)
            expected = {str(pr["key"]).casefold() for pr in group_prs}
            checked = expected.issubset({key.casefold() for key in matches})
            if not checked:
                raise RuntimeError("association query did not return every watched PR")
        except Exception as exc:
            message = f"{representative['key']} {HEAD_REF_ALIAS_ERROR_MARKER} {exc}"
            if errors is not None:
                errors.append(message)
            checked, matches = False, []
        for pr in group_prs:
            guard(pr, checked, matches)


def recommend_cadence(classifications: list[str]) -> str:
    if not classifications:
        return "idle"
    if "active" in classifications:
        return "active"
    if "normal" in classifications:
        return "normal"
    return "quiet"

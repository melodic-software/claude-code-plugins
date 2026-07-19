#!/usr/bin/env python3
"""GitHub-read-only PR queue snapshot CLI for the babysit-prs skill.

Thin orchestrator over the engine modules: discovery, hydration,
classification, the head-ref guard, error quarantine, and state persistence.
All configuration arrives as explicit CLI flags -- there are no environment
seams and no baked-in identities.

Exit-code taxonomy (a caller contract):

* ``0`` -- a valid snapshot with no errors; state written when requested.
* ``1`` -- a valid snapshot carrying at least one *substantive* error (a per-PR
  hydration failure or a discovery failure); state still written. A substantive
  error means one or more PRs could not be classified this cycle.
* ``2`` -- a fatal run: an exception escaped before a snapshot existed, so no
  state was written and no snapshot is emitted.
* ``3`` -- a valid snapshot whose only errors are *advisory*: the global
  head-ref alias cross-check degraded but every per-PR classification and the
  persisted state are intact. Split out from ``1`` so an advisory-only run is
  distinguishable from a substantive per-PR failure. Advisory errors are
  identified structurally via ``babysit_delta.is_head_ref_alias_error``.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime
from typing import Any

import babysit_checks as checks_engine
import babysit_delta as delta
import babysit_gh as gh
import babysit_lease as leases
import babysit_review_trigger as trigger
import babysit_state as state_store
from babysit_feedback import FeedbackConfig
from babysit_review_trigger import ReviewTriggerConfig
from babysit_util import configure_stdio, json_object


def _csv(value: str | None) -> frozenset[str]:
    return frozenset(
        part.strip() for part in (value or "").split(",") if part.strip()
    )


def build_config(args: argparse.Namespace) -> delta.ClassifyConfig:
    owners = _csv(getattr(args, "owners", None))
    resolved_authors = getattr(args, "resolved_authors", None)
    if resolved_authors is None:
        # Hand-built Namespaces (tests, callers) may skip resolution; derive
        # the self set from the raw --author, dropping the unresolvable '@me'.
        self_logins = frozenset(
            login for login in _csv(getattr(args, "author", None)) if login != "@me"
        )
    else:
        self_logins = frozenset(resolved_authors)
    return delta.ClassifyConfig(
        allowed_owners=owners,
        self_logins=self_logins,
        feedback=FeedbackConfig(
            extra_bot_logins=_csv(getattr(args, "extra_bot_logins", None)),
            approval_downgrade_logins=_csv(
                getattr(args, "approval_downgrade_logins", None)
            ),
            skip_downgrade_logins=_csv(getattr(args, "skip_downgrade_logins", None)),
        ),
        review_trigger=ReviewTriggerConfig(
            trigger_phrase=str(getattr(args, "trigger_phrase", None) or ""),
            reviewer_logins=_csv(getattr(args, "review_bot_logins", None)),
            gate_context=str(getattr(args, "review_gate_context", None) or ""),
            ci_gateway_context=str(getattr(args, "ci_gateway_context", None) or ""),
        ),
        max_quiet_recheck_seconds=float(
            getattr(args, "max_quiet_recheck_seconds", None)
            or delta.DEFAULT_MAX_QUIET_RECHECK_SECONDS
        ),
        advisory_fix_round_cap=int(
            getattr(args, "fix_round_cap", None) or delta.ADVISORY_FIX_ROUND_CAP
        ),
    )


def resolve_scope_repos(
    args: argparse.Namespace, owners: frozenset[str]
) -> tuple[str, ...]:
    """Validate --repo against the watched-owner set and the queue lease."""
    repo_arg = getattr(args, "repo", None)
    if not repo_arg:
        return ()
    repos = leases.normalize_scope_repos(repo_arg)
    allowed_owner_set = {owner.casefold() for owner in owners}
    for repo in repos:
        owner = repo.split("/", 1)[0]
        if owner not in allowed_owner_set:
            raise ValueError(
                f"--repo {repo} is outside the watched owner allowlist "
                f"({', '.join(sorted(allowed_owner_set))})"
            )
    leases.validate_snapshot_scope(
        args.state_dir, repos, getattr(args, "lease_token", None)
    )
    return repos


def build_snapshot(args: argparse.Namespace) -> dict[str, Any]:
    generated_at = datetime.now(UTC).isoformat()
    config = build_config(args)
    state_path = state_store.state_path_for(args.state_dir)
    state = state_store.load_state(state_path)
    previous_prs = json_object(state.get("prs"))
    mutation_ledger = json_object(state.get("mutation_ledger"))

    targets: list[tuple[str, int]]
    errors: list[str]
    scope_repos: tuple[str, ...] = ()
    if args.pr:
        targets = [gh.parse_repo_number(args.pr)]
        errors = []
    else:
        # build_snapshot also runs from hand-built Namespaces (tests, callers)
        # that may omit optional flags; default the optional --author/--repo
        # rather than require them.
        authors = gh.resolve_authors(getattr(args, "author", None))
        args.resolved_authors = authors
        config = build_config(args)
        scope_repos = resolve_scope_repos(args, config.allowed_owners)
        if scope_repos:
            targets, errors = gh.discover_prs(
                repos=scope_repos, authors=authors, limit=args.limit
            )
        else:
            owners = [
                owner.strip() for owner in args.owners.split(",") if owner.strip()
            ]
            targets, errors = gh.discover_prs(
                owners=owners, authors=authors, limit=args.limit
            )

    trigger_config = config.review_trigger
    prs: list[dict[str, Any]] = []
    pr_error_keys: list[str] = []
    for repo, number in targets:
        key = f"{repo}#{number}"
        try:
            pr = gh.view_pr(repo, number)
            pr["comments"] = gh.fetch_issue_comments(repo, number)
            pr["_issue_comments_complete"] = True
            pr["reviews"] = gh.fetch_pull_request_reviews(repo, number)
            inline_comments = gh.fetch_unresolved_review_comments(repo, number)
            checks = checks_engine.classify_checks(pr.get("statusCheckRollup"))
            gate_state = trigger.review_gate_state(checks, trigger_config)
            review_evidence: list[dict[str, str]] | None = None
            reaction_signals: list[dict[str, str]] | None = None
            if trigger_config.configured and (
                gate_state["gate_state"] != "absent"
                or gate_state["workflow_state"] != "absent"
            ):
                review_evidence = trigger.fetch_review_evidence(
                    repo,
                    number,
                    reviews=pr["reviews"],
                    review_comments=gh.fetch_pull_request_review_comments(
                        repo, number
                    ),
                    config=trigger_config,
                )
                if not trigger.has_current_head_review(
                    pr,
                    str(pr.get("headRefOid") or ""),
                    review_evidence,
                    config=trigger_config,
                ):
                    reaction_signals = trigger.fetch_reaction_signals(
                        repo, number, pr, trigger_config
                    )
            previous = state_store.previous_with_ledger(
                previous_prs.get(key), mutation_ledger.get(key)
            )
            prs.append(
                delta.classify_pr(
                    pr,
                    previous,
                    inline_comments,
                    generated_at,
                    review_evidence,
                    reaction_signals,
                    config,
                )
            )
        except Exception as exc:
            errors.append(f"{key}: {exc}")
            pr_error_keys.append(key)

    if args.pr and prs:
        try:
            matches = gh.find_open_prs_for_head_ref(prs[0])
            delta.apply_head_ref_guard(
                prs[0],
                checked=prs[0]["key"] in matches,
                matching_prs=matches,
                prev_unique=delta.prev_head_ref_unique(prs[0], previous_prs),
            )
        except Exception as exc:
            errors.append(
                f"{prs[0]['key']} {delta.HEAD_REF_ALIAS_ERROR_MARKER} {exc}"
            )
            delta.apply_head_ref_guard(
                prs[0],
                checked=False,
                matching_prs=[],
                prev_unique=delta.prev_head_ref_unique(prs[0], previous_prs),
            )
    else:
        delta.annotate_queue_head_refs(
            prs, complete=not errors, errors=errors, previous_prs=previous_prs
        )

    # Persistent-error quarantine: a PR that has errored several consecutive
    # cycles stops forcing the cadence to "active" (its errors stay visible)
    # until its quarantine TTL lapses -- one broken PR must not pin the whole
    # queue at the tightest cadence forever.
    pr_errors, quarantined = state_store.update_error_quarantine(
        state.get("pr_errors"), pr_error_keys, generated_at
    )
    cadence_blocking_errors = [
        message
        for message in errors
        if message.split(":", 1)[0] not in quarantined
    ]
    cadence = (
        "active"
        if cadence_blocking_errors
        else delta.recommend_cadence([pr["classification"] for pr in prs])
    )
    snapshot = {
        "generated_at": generated_at,
        "mode": "single" if args.pr else "queue",
        "complete": not errors,
        "recommended_cadence": cadence,
        "state_path": str(state_path),
        "pr_count": len(prs),
        "prs": prs,
        "errors": errors,
        "cadence_blocking_errors": cadence_blocking_errors,
        "quarantined_errors": sorted(quarantined),
        "scope_repos": list(scope_repos),
    }
    if args.write_state:
        state_store.save_state(
            state_path,
            snapshot,
            recommend_cadence=delta.recommend_cadence,
            scope_repos=scope_repos or None,
            pr_errors=pr_errors,
        )
    return snapshot


def print_text(snapshot: dict[str, Any]) -> None:
    print(
        f"Babysit PR snapshot: {snapshot['pr_count']} PR(s), cadence={snapshot['recommended_cadence']}"
    )
    if snapshot["errors"]:
        print("Errors:")
        for err in snapshot["errors"]:
            print(f"- {err}")
    if snapshot.get("quarantined_errors"):
        print(
            "Quarantined (persistently erroring, no longer forcing cadence): "
            + ", ".join(snapshot["quarantined_errors"])
        )
    for pr in snapshot["prs"]:
        print()
        worker_flag = "needs_worker" if pr["needs_worker"] else "no_worker"
        print(
            f"{pr['key']} (@{pr['author'] or 'unknown'}) "
            + f"{pr['classification']} [{worker_flag}]: {pr['title']}"
        )
        print(f"  {pr['url']}")
        print(
            f"  head={pr['head_ref']} {pr['head_sha'][:12]} "
            + f"review={pr['review_decision'] or 'none'} "
            + f"merge={pr['merge_state'] or 'unknown'} "
            + f"trigger={pr['review_trigger']['state']}"
        )
        if pr["needs_worker"] and pr["needs_worker_reasons"]:
            print(f"  needs_worker_reasons: {', '.join(pr['needs_worker_reasons'])}")
        if pr.get("foreign_activity", {}).get("detected"):
            print(
                "  contention: foreign same-login activity detected; "
                "worker dispatch suppressed"
            )
        if pr["blockers"]:
            print("  blockers:")
            for blocker in pr["blockers"]:
                print(f"  - {blocker}")
        if pr["material_findings"]:
            print("  material:")
            for finding in pr["material_findings"]:
                print(f"  - {finding}")
        failing = pr["checks"]["failing"]
        pending = pr["checks"]["pending"]
        if failing:
            print(f"  failing checks: {', '.join(failing)}")
        if pending:
            print(f"  pending checks: {', '.join(pending)}")
        for item in pr["feedback"]["blocking"]:
            print(f"  blocking feedback: {item['author']} {item['preview']}")
        for item in pr["feedback"]["material"]:
            print(f"  material feedback: {item['author']} {item['preview']}")
        for item in pr["feedback"]["human_blocking"]:
            print(f"  blocking human feedback: {item['author']} {item['preview']}")
        for item in pr["new_feedback"]["blocking"]:
            print(f"  new blocking feedback: {item['author']} {item['preview']}")
        for item in pr["new_feedback"]["material"]:
            print(f"  new material feedback: {item['author']} {item['preview']}")
        for item in pr["new_feedback"]["human"]:
            print(f"  new human feedback: {item['author']} {item['preview']}")


def exit_code_for(snapshot: dict[str, Any]) -> int:
    """Map a valid snapshot to its exit code (see the module docstring).

    Substantive errors take precedence over advisory ones: a run carrying both
    reports ``1`` so the substantive failure is never masked by the advisory
    split.
    """
    errors = snapshot["errors"]
    if any(not delta.is_head_ref_alias_error(message) for message in errors):
        return 1
    if errors:
        return 3
    return 0


def main() -> int:
    configure_stdio()
    parser = argparse.ArgumentParser(
        description="Read-only GitHub PR babysitting snapshot."
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--queue",
        action="store_true",
        help="Inspect every open PR under watched owners.",
    )
    group.add_argument("--pr", help="Inspect one PR URL or owner/repo#number.")
    parser.add_argument(
        "--owners",
        required=True,
        help=(
            "Comma-separated watched owners. Required: this is the trust "
            "boundary for discovery and branch-write policy, and there is no "
            "baked-in default."
        ),
    )
    parser.add_argument(
        "--repo",
        default=None,
        help=(
            "Comma-separated owner/repo list to scope queue mode to specific "
            "repositories instead of sweeping every repo under --owners. This "
            "is the normal shape for one babysit session per repo; pass the "
            "same value to manage_babysit_lease.py's --repo so the queue lease "
            "is scoped identically. Owners must be within --owners."
        ),
    )
    parser.add_argument(
        "--author",
        default=None,
        help=(
            "Restrict queue discovery to PRs by these authors (deterministic "
            "scope gate). Accepts a comma-separated list of GitHub logins and/or "
            "'@me' (resolved to the authenticated user); each login is queried "
            "separately and the results unioned. Omit to include every author "
            "under the watched owners."
        ),
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=1000,
        help="Maximum PRs per owner search and per repository reconcile.",
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
        "--write-state",
        action="store_true",
        help="Persist snapshot state for adaptive cadence.",
    )
    parser.add_argument(
        "--json", action="store_true", help="Print JSON instead of a text summary."
    )
    parser.add_argument(
        "--lease-token",
        default=None,
        help=(
            "Queue lease token for a --repo-scoped run; the run then validates "
            "that it owns the identically scoped queue lease."
        ),
    )
    parser.add_argument(
        "--gh-timeout-seconds",
        type=float,
        default=None,
        help="Per-call gh timeout in seconds (default 60).",
    )
    parser.add_argument(
        "--max-quiet-recheck-seconds",
        type=float,
        default=delta.DEFAULT_MAX_QUIET_RECHECK_SECONDS,
        help=(
            "Force a worker check-in on an otherwise-unchanged PR at least "
            f"this often (default {delta.DEFAULT_MAX_QUIET_RECHECK_SECONDS})."
        ),
    )
    parser.add_argument(
        "--fix-round-cap",
        type=int,
        default=delta.ADVISORY_FIX_ROUND_CAP,
        help=(
            "Advisory fix-round cap before new advisory bot findings become "
            f"report-only (default {delta.ADVISORY_FIX_ROUND_CAP})."
        ),
    )
    parser.add_argument(
        "--trigger-phrase",
        default=None,
        help=(
            "Exact review-trigger comment phrase. Absent (with the other "
            "review-trigger flags) leaves the review-trigger module dormant."
        ),
    )
    parser.add_argument(
        "--review-bot-logins",
        default=None,
        help="Comma-separated reviewer-bot logins for the review trigger.",
    )
    parser.add_argument(
        "--review-gate-context",
        default=None,
        help="Status context name of the review gate check.",
    )
    parser.add_argument(
        "--ci-gateway-context",
        default=None,
        help="Status context name of the aggregate CI gateway check.",
    )
    parser.add_argument(
        "--extra-bot-logins",
        default=None,
        help=(
            "Comma-separated logins to treat as bots when structural detection "
            "cannot classify them (ships empty)."
        ),
    )
    parser.add_argument(
        "--approval-downgrade-logins",
        default=None,
        help=(
            "Comma-separated reviewer-bot logins whose blocking-looking text "
            "may downgrade on an explicit approval verdict (ships empty)."
        ),
    )
    parser.add_argument(
        "--skip-downgrade-logins",
        default=None,
        help=(
            "Comma-separated reviewer-bot logins whose not-approving text may "
            "downgrade when their review provably could not run (ships empty)."
        ),
    )
    args = parser.parse_args()

    try:
        args.state_dir = str(state_store.resolve_state_dir(args.state_dir))
        if args.gh_timeout_seconds is not None:
            gh.set_gh_timeout_seconds(args.gh_timeout_seconds)
        delta.validated_max_quiet_recheck_seconds(args.max_quiet_recheck_seconds)
        snapshot = build_snapshot(args)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(snapshot, indent=2, sort_keys=True))
    else:
        print_text(snapshot)
    return exit_code_for(snapshot)


if __name__ == "__main__":
    raise SystemExit(main())

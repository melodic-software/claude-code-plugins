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
  persisted state are intact; state is still written when requested. Split out
  from ``1`` so an advisory-only run is distinguishable from a substantive
  per-PR failure. Advisory errors are identified structurally via
  ``babysit_delta.is_head_ref_alias_error``.
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


def _csv_list(value: str | None) -> list[str]:
    return [part.strip() for part in (value or "").split(",") if part.strip()]


def build_config(args: argparse.Namespace) -> delta.ClassifyConfig:
    owners = _csv(getattr(args, "owners", None))
    # `self_logins` (the posting identities whose comments to suppress) is resolved
    # by `resolve_self_logins` from the dedicated self flags, never from the
    # `--author` discovery filter (#511). A hand-built Namespace that omits
    # `resolved_self_logins` supplies no self set; `--author` is deliberately not
    # consulted as a fallback, so no discovery author can leak in.
    resolved_self_logins = getattr(args, "resolved_self_logins", None)
    self_logins = (
        frozenset(resolved_self_logins)
        if resolved_self_logins is not None
        else frozenset()
    )
    return delta.ClassifyConfig(
        allowed_owners=owners,
        self_logins=self_logins,
        intended_write_identity=str(
            getattr(args, "intended_write_identity", None) or ""
        ),
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
        stuck_check_age_seconds=float(
            getattr(args, "stuck_check_age_seconds", None)
            or delta.DEFAULT_STUCK_CHECK_AGE_SECONDS
        ),
        advisory_fix_round_cap=int(
            getattr(args, "fix_round_cap", None) or delta.ADVISORY_FIX_ROUND_CAP
        ),
    )


def resolve_self_logins(
    self_csv: str | None, extra_self_csv: str | None
) -> list[str]:
    """Resolve the posting identities whose comments self-classification suppresses.

    Independent of the `--author` discovery filter (#511): which authors' PRs to
    discover is a distinct concern from whose comments to suppress, so the self set
    must never ride on `--author`. Mirrors `babysit-readiness-gate.sh`'s
    `--self`/`--extra-self` flag semantics: `--self` is a full override (exactly the
    given logins, `@me` not added); otherwise the authenticated `@me` is unioned with
    any `--extra-self` logins. Autopilot widening drops `--author` but keeps
    `--extra-self`, so configured extra identities still survive, and a discovery
    `--author` never leaks in. Structural parity, not exact on one edge: an
    unresolvable `@me` raises here (via `resolve_author`) rather than degrading to the
    extras as the gate does — fail-loud on broken auth; parity tracked in #881.
    """
    if self_csv is not None:
        source = _csv_list(self_csv)
    else:
        source = _csv_list(extra_self_csv)
        self_login = gh.resolve_author("@me")
        if self_login:
            source.append(self_login)
    resolved: list[str] = []
    seen: set[str] = set()
    for login in source:
        key = login.casefold()
        if key not in seen:
            seen.add(key)
            resolved.append(login)
    return resolved


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


def substantive_errors(errors: list[str]) -> list[str]:
    """Errors that mark the sweep incomplete -- everything but advisory ones.

    An advisory head-ref alias failure leaves every per-PR classification and
    the persisted state intact, so it neither forces the tight cadence nor
    holds back full-sweep advancement; only substantive errors (per-PR
    hydration or discovery failures) do. The single source of truth for the
    advisory predicate is ``babysit_delta.is_head_ref_alias_error``.
    """
    return [
        message for message in errors if not delta.is_head_ref_alias_error(message)
    ]


def build_snapshot(args: argparse.Namespace) -> dict[str, Any]:
    generated_at = datetime.now(UTC).isoformat()
    state_path = state_store.state_path_for(args.state_dir)
    state = state_store.load_state(state_path)
    previous_prs = json_object(state.get("prs"))
    mutation_ledger = json_object(state.get("mutation_ledger"))

    # Resolve the self-identity set from the dedicated `--self`/`--extra-self`
    # flags, independent of the `--author` discovery filter and of `--pr` vs
    # `--queue` scope (#511). `self_logins` gates same-login classification
    # (foreign-activity and attribution-drift) and self-comment suppression
    # whether or not discovery runs; resolving it here (before the scope split)
    # covers single-PR scope too and never inherits a discovery author. Autopilot
    # widening drops `--author` but keeps `--extra-self`, so configured extra
    # identities still hold. build_snapshot also runs from hand-built Namespaces
    # (tests, callers) that may omit optional flags; default them rather than
    # require them.
    authors = gh.resolve_authors(getattr(args, "author", None))
    args.resolved_self_logins = resolve_self_logins(
        getattr(args, "self_logins", None), getattr(args, "extra_self_logins", None)
    )
    config = build_config(args)

    targets: list[tuple[str, int]]
    errors: list[str]
    scope_repos: tuple[str, ...] = ()
    if args.pr:
        targets = [gh.parse_repo_number(args.pr)]
        errors = []
    else:
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
            gh.rest_hydrate_reviews(pr, repo, number)
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
        and not delta.is_head_ref_alias_error(message)
    ]
    cadence = (
        "active"
        if cadence_blocking_errors
        else delta.recommend_cadence([pr["classification"] for pr in prs])
    )
    snapshot = {
        "generated_at": generated_at,
        "mode": "single" if args.pr else "queue",
        "complete": not substantive_errors(errors),
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
    if substantive_errors(errors):
        return 1
    if errors:
        return 3
    return 0


def main() -> int:
    configure_stdio()
    parser = argparse.ArgumentParser(
        description="Read-only GitHub PR babysitting snapshot.", allow_abbrev=False
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
            "under the watched owners. Discovery only: it never sets the "
            "self-identity set -- use --self / --extra-self for that."
        ),
    )
    parser.add_argument(
        "--self",
        dest="self_logins",
        default=None,
        help=(
            "Full override of the self-identity set: exactly these comma-separated "
            "logins are treated as self (whose comments self-classification "
            "suppresses and whose activity gates the same-login checks). '@me' is "
            "NOT added. Resolved independently of --author. Mirrors "
            "babysit-readiness-gate.sh --self; prefer --extra-self unless you must "
            "exclude the authenticated login. Ignored (with --self taking full "
            "precedence) when --extra-self is also supplied."
        ),
    )
    parser.add_argument(
        "--extra-self",
        dest="extra_self_logins",
        default=None,
        help=(
            "Extra self posting identities added on top of the authenticated "
            "'@me' login (e.g. a project bot account whose comments the babysit "
            "worker posts). Comma-separated. Resolved independently of the "
            "--author discovery filter, so these survive autopilot widening that "
            "drops --author. The invoking skill wires the babysit_self_logins "
            "userConfig option here. Mirrors babysit-readiness-gate.sh "
            "--extra-self. Ignored when --self is also supplied."
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
        "--stuck-check-age-seconds",
        type=float,
        default=delta.DEFAULT_STUCK_CHECK_AGE_SECONDS,
        help=(
            "Minimum age before a pending non-required check under UNSTABLE is "
            "reported as stuck (stuck_queued / never_settling). Orphaned "
            "StatusContexts are detected structurally and ignore this "
            f"threshold (default {delta.DEFAULT_STUCK_CHECK_AGE_SECONDS})."
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
            "Comma-separated reviewer-bot logins whose approval is surfaced as a "
            "material finding rather than ignored in the one case the structural "
            "downgrade reaches: a review body carrying blocking-looking prose that "
            "still parses as an approval verdict (no CRITICAL/IMPORTANT or "
            "required-fix marker). Every bot's such approval is downgraded to "
            "non-blocking by default; naming a login opts its own into the "
            "more-conservative material bucket instead of ignored. Does not affect "
            "a review already in the APPROVED state or a plain clean approval with "
            "no blocking-looking prose -- both are ignored regardless (ships empty)."
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
    parser.add_argument(
        "--intended-write-identity",
        default=None,
        help=(
            "Login the orchestrator's own writes are intended to land under "
            "(e.g. a bot posting identity). A recorded write that lands under a "
            "different self-login is surfaced as attribution drift. Absent: the "
            "check is dormant."
        ),
    )
    args = parser.parse_args()

    try:
        args.state_dir = str(state_store.resolve_state_dir(args.state_dir))
        if args.gh_timeout_seconds is not None:
            gh.set_gh_timeout_seconds(args.gh_timeout_seconds)
        delta.validated_max_quiet_recheck_seconds(args.max_quiet_recheck_seconds)
        delta.validated_stuck_check_age_seconds(args.stuck_check_age_seconds)
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

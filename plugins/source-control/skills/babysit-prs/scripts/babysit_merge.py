#!/usr/bin/env python3
"""Guarded merge-readiness check and gated merge for babysit PRs.

This is a narrow, self-validating privileged helper. It exists so the babysit
workflow can be granted exactly one capability -- "merge a PR that is provably,
100% ready" -- instead of a broad `gh pr merge` / `gh api graphql` allow rule.

Contract enforced here (encoded as code, not convention):

- Owner must be in the caller-supplied `--allowed-owners` allowlist; an empty or
  missing allowlist hard-refuses (fail closed) rather than merging anything.
- Default action is READ-ONLY: report merge readiness plus every branch rule and
  check that governs the merge, and the exact blockers, so the caller can react.
- A merge only happens with `--merge` AND only when every readiness gate passes.
- Merges use the repository's allowed method (squash preferred) and NEVER pass
  `--admin`. This helper cannot bypass branch protection, resolve or reply to
  review threads, force-push, or change settings.
- A PR authored by a dependency manager (Dependabot/Renovate-class) is held --
  never merged -- unless `--allow-dependency` is passed.
- A PR on an unprotected base (zero required reviews AND zero required contexts)
  authored by someone other than a configured self login is held unless
  `--allow-unprotected` is passed: on such a base `CLEAN` proves nothing.

Readiness is gated on GitHub's own `mergeStateStatus == CLEAN` (which integrates
required checks, up-to-date, approvals, and conversation resolution) plus
explicit cross-checks so the *reason* for a block is always reported: the
effective branch rules (`rules/branches`), the review decision, unresolved
review threads, and the status-check rollup.

Exit codes: 0 ready (or merged), 10 not ready (blockers), 2 usage/runtime
error, 3 owner out of scope (or no allowlist). Output is a single JSON object
on stdout.
"""

from __future__ import annotations

import argparse
import json
import re
from typing import Any, cast

from babysit_checks import check_identity_key, classify_checks
from babysit_classify import is_dependency_author, is_self_login, normalize_self_logins
from babysit_gh import (
    fetch_review_threads,
    gh_capture,
    gh_json,
    parse_repo_number,
    resolve_authors,
)
from babysit_util import MIN_HEAD_SHA_PREFIX_LENGTH, configure_stdio, is_json_object

EXPECTED_HEAD_RE = re.compile(rf"^[0-9a-fA-F]{{{MIN_HEAD_SHA_PREFIX_LENGTH},64}}$")

# GitHub's own fixed enum contract. MergeStateStatus values meaning "mergeable,
# all commit status passing": CLEAN on github.com, HAS_HOOKS when the repo has
# pre-receive hooks (GHES) -- GitHub returns one OR the other, so both are ready.
READY_MERGE_STATES = {"CLEAN", "HAS_HOOKS"}


def split_owner(repo: str) -> str:
    return repo.split("/", 1)[0]


def parse_allowed_owners(raw: str | None) -> set[str]:
    if not raw:
        return set()
    return {part.strip().casefold() for part in raw.split(",") if part.strip()}


def unresolved_threads(repo: str, number: int) -> list[dict[str, object]]:
    """Unresolved review threads via the single shared paginator.

    One comment per thread is enough to attribute the finding; the paginator
    drops resolved threads and fails closed on a malformed connection, so a
    hidden page can never falsely report zero unresolved threads.
    """

    def project(thread: dict[str, Any]) -> dict[str, object]:
        comments = thread.get("comments")
        first = comments[0] if isinstance(comments, list) and comments else {}
        first_object = cast(dict[str, Any], first) if isinstance(first, dict) else {}
        author = first_object.get("author")
        author_object = (
            cast(dict[str, Any], author) if isinstance(author, dict) else {}
        )
        return {
            "author": author_object.get("login"),
            "path": first_object.get("path"),
            "isOutdated": thread.get("isOutdated", False),
        }

    return [
        cast(dict[str, object], record)
        for record in fetch_review_threads(
            repo, number, include_resolved=False, comments_first=1, projection=project
        )
    ]


def branch_rules(repo: str, branch: str) -> dict[str, object]:
    """Summarize the effective merge-governing rules for the base branch."""
    summary: dict[str, object] = {
        "requiredContexts": [],
        "requiredApprovingReviews": 0,
        "requireThreadResolution": False,
        "requireSignatures": False,
        "requireLinearHistory": False,
        "mergeQueueRequired": False,
    }
    try:
        rules = gh_json(["api", f"repos/{repo}/rules/branches/{branch}"])
    except (RuntimeError, json.JSONDecodeError) as exc:
        # Rules are advisory context; a read failure must never fail the run.
        summary["error"] = f"could not read branch rules: {exc}"
        return summary
    for rule in cast(list[Any], rules) if isinstance(rules, list) else []:
        if not isinstance(rule, dict):
            continue
        rule_object = cast(dict[str, Any], rule)
        rtype = rule_object.get("type")
        raw_params = rule_object.get("parameters")
        params = (
            cast(dict[str, Any], raw_params) if isinstance(raw_params, dict) else {}
        )
        if rtype == "required_status_checks":
            summary["requiredContexts"] = [
                cast(dict[str, Any], c).get("context")
                for c in params.get("required_status_checks", [])
                if isinstance(c, dict)
            ]
        elif rtype == "pull_request":
            summary["requiredApprovingReviews"] = params.get(
                "required_approving_review_count", 0
            )
            summary["requireThreadResolution"] = params.get(
                "required_review_thread_resolution", False
            )
        elif rtype == "required_signatures":
            summary["requireSignatures"] = True
        elif rtype == "required_linear_history":
            summary["requireLinearHistory"] = True
        elif rtype == "merge_queue":
            summary["mergeQueueRequired"] = True
    return summary


def evaluate(
    repo: str,
    number: int,
    expected_head: str | None,
    allowed: set[str],
    self_logins: frozenset[str],
    allow_dependency: bool,
    allow_unprotected: bool,
) -> dict[str, Any]:
    owner = split_owner(repo)
    pr_data = gh_json(
        [
            "pr",
            "view",
            str(number),
            "-R",
            repo,
            "--json",
            "state,isDraft,mergeable,mergeStateStatus,reviewDecision,"
            "headRefOid,baseRefName,author,url,title,labels,statusCheckRollup",
        ]
    )
    pr = cast(dict[str, Any], pr_data) if isinstance(pr_data, dict) else {}
    threads = unresolved_threads(repo, number)
    checks = classify_checks(pr.get("statusCheckRollup"))
    failing = checks["failing"]
    pending = checks["pending"]
    checks_by_key: dict[tuple[str, str, str], dict[str, Any]] = {
        check_identity_key(check): check for check in checks["checks"]
    }
    rules = branch_rules(repo, str(pr.get("baseRefName") or "main"))
    head = pr.get("headRefOid")
    head_matches = (
        None
        if not expected_head
        else bool(head and str(head).startswith(expected_head))
    )
    review_decision = pr.get("reviewDecision") or ""
    labels = [
        label.get("name")
        for label in cast(list[Any], pr.get("labels") or [])
        if is_json_object(label) and label.get("name")
    ]
    author = pr.get("author")
    author_login = author.get("login") if is_json_object(author) else None

    # Reconcile each required status-check context against the deduped rollup.
    required_contexts = rules.get("requiredContexts")
    required_check_status: list[dict[str, object]] = []
    for raw_context in (
        cast(list[Any], required_contexts)
        if isinstance(required_contexts, list)
        else []
    ):
        ctx = str(raw_context)
        match = next(
            (
                check
                for key, check in checks_by_key.items()
                if key[1] and (key[1] == ctx or ctx.endswith(key[1]) or key[1].endswith(ctx))
            ),
            None,
        )
        satisfied = bool(match) and (match or {}).get("category") == "success"
        required_check_status.append(
            {
                "context": ctx,
                "found": bool(match),
                "satisfied": satisfied,
                "category": (match or {}).get("category"),
            }
        )

    required_reviews = rules.get("requiredApprovingReviews") or 0
    required_context_list = (
        required_contexts if isinstance(required_contexts, list) else []
    )
    base_is_unprotected = not required_reviews and not required_context_list

    blockers: list[str] = []
    if owner not in allowed:
        blockers.append(f"owner {owner!r} out of scope")
    if pr.get("state") != "OPEN":
        blockers.append(f"state={pr.get('state')} (not OPEN)")
    if pr.get("isDraft"):
        blockers.append("PR is a draft -- mark ready first")
    if pr.get("mergeable") != "MERGEABLE":
        blockers.append(
            f"mergeable={pr.get('mergeable')} (conflict or still computing)"
        )
    if pr.get("mergeStateStatus") not in READY_MERGE_STATES:
        blockers.append(
            f"mergeStateStatus={pr.get('mergeStateStatus')} "
            + "(need CLEAN/HAS_HOOKS: integrates required checks, up-to-date, "
            + "approvals, conversation resolution)"
        )
    if review_decision == "CHANGES_REQUESTED":
        blockers.append(
            "reviewDecision=CHANGES_REQUESTED -- a reviewer requested changes (human stop)"
        )
    elif required_reviews and review_decision != "APPROVED":
        blockers.append(
            f"needs {required_reviews} approving review(s); "
            f"reviewDecision={review_decision or 'none'}"
        )
    if threads:
        who = ", ".join(sorted({str(t.get("author")) for t in threads}))
        blockers.append(
            f"{len(threads)} unresolved review thread(s) [{who}] "
            "-- resolve or address the finding"
        )
    if failing:
        blockers.append("failing checks: " + ", ".join(str(name) for name in failing))
    if pending:
        blockers.append("pending checks: " + ", ".join(str(name) for name in pending))
    unmet_required = [r["context"] for r in required_check_status if not r["satisfied"]]
    if unmet_required:
        blockers.append(
            "required checks not satisfied: "
            + ", ".join(str(c) for c in unmet_required)
        )
    if rules.get("mergeQueueRequired"):
        blockers.append(
            "base branch requires a merge queue -- a direct merge is not allowed; "
            "add to the queue"
        )
    if head_matches is False:
        blockers.append(
            f"head moved: live={str(head)[:12] if head else None} expected={expected_head}"
        )
    # A dependency-manager PR is held in every tier unless explicitly allowed:
    # its update should be reviewed, not auto-merged on a green gate alone.
    if is_dependency_author(str(author_login or "")) and not allow_dependency:
        blockers.append(
            f"author {author_login!r} is a dependency manager "
            "-- held (pass --allow-dependency to override)"
        )
    # On an unprotected base, CLEAN proves nothing (no required checks/reviews).
    # A non-self author's PR there is held unless explicitly allowed.
    author_is_self = is_self_login(author_login, self_logins)
    if base_is_unprotected and not author_is_self and not allow_unprotected:
        blockers.append(
            "base branch is unprotected (0 required reviews AND 0 required "
            f"contexts) and author {author_login!r} is not a configured self "
            "login -- held (pass --allow-unprotected to override)"
        )

    ready = not blockers
    return {
        "pr": f"{repo}#{number}",
        "url": pr.get("url"),
        "title": pr.get("title"),
        "author": author_login,
        "owner": owner,
        "inScope": owner in allowed,
        "baseRef": pr.get("baseRefName"),
        "baseUnprotected": base_is_unprotected,
        "state": pr.get("state"),
        "isDraft": pr.get("isDraft"),
        "mergeable": pr.get("mergeable"),
        "mergeStateStatus": pr.get("mergeStateStatus"),
        "reviewDecision": review_decision,
        "headRefOid": head,
        "labels": labels,  # surfaced for agent reasoning; no hardcoded hold-label list
        "expectedHead": expected_head,
        "headMatches": head_matches,
        "effectiveRules": rules,
        "requiredChecks": required_check_status,
        "unresolvedThreadCount": len(threads),
        "unresolvedThreads": threads,
        "failingChecks": failing,
        "pendingChecks": pending,
        "ready": ready,
        "blockers": blockers,
    }


def allowed_method(repo: str, requested: str | None) -> str:
    data = gh_json(
        [
            "repo",
            "view",
            repo,
            "--json",
            "squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed",
        ]
    )
    data = cast(dict[str, Any], data) if isinstance(data, dict) else {}
    allowed = {
        "squash": bool(data.get("squashMergeAllowed")),
        "merge": bool(data.get("mergeCommitAllowed")),
        "rebase": bool(data.get("rebaseMergeAllowed")),
    }
    if requested:
        if not allowed.get(requested):
            raise RuntimeError(f"merge method {requested!r} not enabled on {repo}")
        return requested
    for method in ("squash", "merge", "rebase"):
        if allowed[method]:
            return method
    raise RuntimeError(f"no merge method enabled on {repo}")


def main() -> int:
    configure_stdio()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pr", help="owner/repo#number or PR URL")
    parser.add_argument(
        "--allowed-owners",
        default=None,
        help="comma-separated owners the helper may act under (required; empty refuses)",
    )
    parser.add_argument(
        "--self-logins",
        default=None,
        help=(
            "comma-separated logins treated as self (exempt from the "
            "unprotected-base hold); '@me' resolves to your gh login"
        ),
    )
    parser.add_argument(
        "--merge",
        action="store_true",
        help="merge iff the PR is 100%% ready; default is check-only",
    )
    parser.add_argument(
        "--expected-head",
        default=None,
        help=(
            "require the live head SHA to match this hex SHA (or a prefix of at "
            f"least {MIN_HEAD_SHA_PREFIX_LENGTH} chars) before merging"
        ),
    )
    parser.add_argument(
        "--method",
        choices=("squash", "merge", "rebase"),
        default=None,
        help="force a merge method (must be enabled); default prefers squash",
    )
    parser.add_argument(
        "--allow-dependency",
        action="store_true",
        help="permit merging a dependency-manager-authored PR (held by default)",
    )
    parser.add_argument(
        "--allow-unprotected",
        action="store_true",
        help="permit merging a non-self PR on an unprotected base (held by default)",
    )
    parser.add_argument(
        "--allow-unpinned-head",
        action="store_true",
        help=(
            "permit --merge without --expected-head (interactive only); disables "
            "the TOCTOU guard that pins the vetted head SHA"
        ),
    )
    args = parser.parse_args()

    allowed = parse_allowed_owners(args.allowed_owners)
    if not allowed:
        print(
            json.dumps(
                {
                    "pr": args.pr,
                    "inScope": False,
                    "error": (
                        "--allowed-owners is required and must be non-empty; "
                        "refusing to act without an owner allowlist"
                    ),
                }
            )
        )
        return 3

    try:
        repo, number = parse_repo_number(args.pr)
    except ValueError as exc:
        print(json.dumps({"error": str(exc)}))
        return 2

    if args.expected_head and not EXPECTED_HEAD_RE.match(args.expected_head):
        print(
            json.dumps(
                {
                    "pr": args.pr,
                    "error": (
                        "--expected-head must be a hex SHA prefix of at least "
                        f"{MIN_HEAD_SHA_PREFIX_LENGTH} characters (a shorter prefix "
                        "is ambiguous and could match an unvetted push)"
                    ),
                }
            )
        )
        return 2

    owner = split_owner(repo)
    if owner not in allowed:
        print(
            json.dumps(
                {
                    "pr": args.pr,
                    "inScope": False,
                    "error": f"owner {owner!r} out of scope; allowed: {sorted(allowed)}",
                }
            )
        )
        return 3

    # Resolve self logins only after every argument-shape refusal above: '@me'
    # resolution is a network call, and the guard's contract is that malformed
    # input is rejected before any network access.
    try:
        self_logins = normalize_self_logins(resolve_authors(args.self_logins))
    except RuntimeError:
        # '@me' could not be resolved to a gh login; fail closed by keeping only
        # the explicit non-'@me' logins -- an unresolved self identity holds own
        # PRs on an unprotected base rather than merging on a guessed identity.
        self_logins = normalize_self_logins(
            token
            for token in (args.self_logins or "").split(",")
            if token.strip().casefold() != "@me"
        )

    try:
        result = evaluate(
            repo,
            number,
            args.expected_head,
            allowed,
            self_logins,
            args.allow_dependency,
            args.allow_unprotected,
        )
    except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
        # Surface any gh/parse failure as JSON rather than a traceback.
        print(json.dumps({"pr": args.pr, "error": f"{type(exc).__name__}: {exc}"}))
        return 2

    result["action"] = "merge" if args.merge else "check"
    result["merged"] = False
    result["merge"] = None

    if not args.merge:
        print(json.dumps(result, indent=2))
        return 0 if result["ready"] else 10

    # TOCTOU guard: never merge whatever head happens to be live at run time. The
    # worker/autopilot flow must pass the SHA it vetted; unpinned merges are an
    # explicit interactive override only.
    if not args.expected_head and not args.allow_unpinned_head:
        reason = (
            "--merge requires --expected-head to pin the vetted head SHA "
            "(a newer push could be CLEAN yet unvetted); pass "
            "--allow-unpinned-head to override interactively"
        )
        result["ready"] = False
        result["blockers"].append(reason)
        result["merge"] = {"attempted": False, "reason": reason}
        print(json.dumps(result, indent=2))
        return 10

    if not result["ready"]:
        result["merge"] = {"attempted": False, "reason": "not ready"}
        print(json.dumps(result, indent=2))
        return 10

    try:
        method = allowed_method(repo, args.method)
    except (RuntimeError, json.JSONDecodeError) as exc:
        # A method-lookup failure is reported, not raised, so output stays JSON.
        result["error"] = f"{type(exc).__name__}: {exc}"
        print(json.dumps(result, indent=2))
        return 2

    result["mergeMethod"] = method
    merge_cmd = ["pr", "merge", str(number), "-R", repo, f"--{method}"]
    # Atomic head pin: GitHub refuses the merge unless the head still equals the
    # exact full SHA we vetted, closing the preflight-to-merge TOCTOU window.
    vetted_head = result.get("headRefOid")
    if args.expected_head and isinstance(vetted_head, str) and vetted_head:
        merge_cmd += ["--match-head-commit", vetted_head]
    proc = gh_capture(merge_cmd)
    result["merge"] = {
        "attempted": True,
        "success": proc.returncode == 0,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
    }
    result["merged"] = proc.returncode == 0
    print(json.dumps(result, indent=2))
    return 0 if proc.returncode == 0 else 10


if __name__ == "__main__":
    raise SystemExit(main())

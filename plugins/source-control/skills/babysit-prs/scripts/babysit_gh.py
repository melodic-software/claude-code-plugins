#!/usr/bin/env python3
"""GitHub read helpers for the babysit-prs engine: gh runner, discovery,
hydration, REST pagination, and the single GraphQL review-thread paginator."""

from __future__ import annotations

import json
import math
import re
import subprocess
from collections.abc import Callable, Iterable
from typing import Any, cast
from urllib.parse import quote, unquote, urlparse

from babysit_util import (
    DEFAULT_COMMAND_TIMEOUT_SECONDS,
    dig,
    is_json_array,
    is_json_object,
    json_array,
    json_object,
    run_command,
)

REPOSITORY_LIST_LIMIT = 1001
VIEW_FIELD_NAMES: tuple[str, ...] = tuple(
    [
        "author",
        "baseRefName",
        "comments",
        "headRefName",
        "headRefOid",
        "headRepository",
        "headRepositoryOwner",
        "isDraft",
        "isCrossRepository",
        "latestReviews",
        "mergeStateStatus",
        "mergeable",
        "maintainerCanModify",
        "number",
        "reviewDecision",
        "reviews",
        "state",
        "statusCheckRollup",
        "title",
        "updatedAt",
        "url",
    ]
)
VIEW_FIELDS = ",".join(VIEW_FIELD_NAMES)
SEARCH_FIELDS = "number,repository,url,title,updatedAt,isDraft"
RECONCILE_FIELDS = "number,url,title,updatedAt,isDraft"
GITHUB_OWNER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]*$")
GITHUB_REPOSITORY_RE = re.compile(r"^[A-Za-z0-9._-]+$")

_default_timeout_seconds = DEFAULT_COMMAND_TIMEOUT_SECONDS


def set_gh_timeout_seconds(seconds: float) -> None:
    """Set the process-wide default gh timeout (fed by a `--gh-timeout-seconds`
    CLI flag; a per-call `timeout_seconds` argument still overrides it)."""
    if not math.isfinite(seconds) or seconds <= 0:
        raise ValueError("gh timeout must be a finite number greater than zero")
    global _default_timeout_seconds
    _default_timeout_seconds = float(seconds)


def gh_timeout_seconds() -> float:
    return _default_timeout_seconds


def _run_gh(
    args: list[str], *, timeout_seconds: float | None, check: bool
) -> subprocess.CompletedProcess[str]:
    """The one gh invocation seam; `None` means the process-wide default timeout."""
    return run_command(
        ["gh", *args],
        allowed_executables=("gh",),
        timeout_seconds=(
            timeout_seconds if timeout_seconds is not None else _default_timeout_seconds
        ),
        check=check,
    )


def run_gh(args: list[str], *, timeout_seconds: float | None = None) -> str:
    """Run a gh command, raising on timeout or nonzero exit; returns stdout."""
    return _run_gh(args, timeout_seconds=timeout_seconds, check=True).stdout


def gh_capture(
    args: list[str], *, timeout_seconds: float | None = None
) -> subprocess.CompletedProcess[str]:
    """Run a gh command capturing stdout/stderr/returncode without raising on
    nonzero exit -- for callers that inspect the returncode themselves."""
    return _run_gh(args, timeout_seconds=timeout_seconds, check=False)


def gh_json(args: list[str]) -> Any:
    text = run_gh(args)
    return json.loads(text) if text.strip() else None


# `gh` reports the HTTP status in its own stderr message, e.g.
# `gh: Forbidden (HTTP 403)`. The exit code alone is 1 for every failure, so
# this is the only signal separating "the API answered no" from "the call never
# landed". Same parse as `babysit_resolve_thread.gh_http_status`, which reads it
# for the resolve wrapper's 404/410 distinction.
GH_HTTP_STATUS_RE = re.compile(r"\(HTTP (\d{3})\)")
# Sandboxed sessions (Claude Code on the web and remote execution) serve only a
# pinned set of GraphQL operations and refuse the rest with HTTP 403. The
# refusal names the session rather than the credential, so it reads like an
# expired token or a missing scope and is neither: re-authenticating never
# clears it, and the only remedy is to source the same fact over REST.
GRAPHQL_UNAVAILABLE_MARKERS = ("not enabled for this session",)


class GraphQLUnavailableError(RuntimeError):
    """GitHub's GraphQL API is not served to this session.

    Distinct from a GraphQL call that failed on its merits: the operation was
    never dispatched, so nothing about the pull request was learned or refuted.
    Callers either re-source the same fact over REST or fail closed; none may
    read this as a negative answer.
    """


def gh_http_status(text: str) -> int | None:
    """The HTTP status `gh` reported in a failure message, or None if it named none.

    Ported from `babysit_resolve_thread.gh_http_status`, which reads the same
    string off a `CompletedProcess`; here the text arrives inside the
    `RuntimeError` `run_command` raises, which embeds the captured stderr. None
    covers every failure that never reached an HTTP response -- a timeout, an
    unreachable API, a `gh` that failed before dispatching -- and means
    "unverifiable", never a negative answer. The LAST status in the stream wins:
    a retried request prints one line per attempt.

    This parses another tool's message text, so it is deliberately
    unparsable-safe rather than robust: if `gh` reformats or localizes that
    string, every failure returns None and every caller degrades to
    "unverifiable", which is the recoverable direction.
    """
    matches = GH_HTTP_STATUS_RE.findall(text or "")
    return int(matches[-1]) if matches else None


def is_graphql_unavailable(failure: BaseException | str) -> bool:
    """Whether a failed GraphQL-backed `gh` call was refused the API itself.

    Two signals, either sufficient: the pinned-operation refusal text, and a
    403. Applied ONLY to GraphQL-backed calls, where both readings lead
    somewhere safe -- a REST re-source that either answers or fails loudly on
    its own, or a fail-closed verdict. It is never used to decide a fact, so a
    false positive costs an extra REST round trip and never a wrong answer.
    """
    text = (str(failure) or "").casefold()
    if any(marker in text for marker in GRAPHQL_UNAVAILABLE_MARKERS):
        return True
    return gh_http_status(text) == 403 or "403" in text


def gh_json_graphql(args: list[str], *, label: str) -> Any:
    """Run a GraphQL-backed `gh` command, separating the refusal from a failure.

    Raises `GraphQLUnavailableError` when the session is not served GraphQL at
    all, and re-raises everything else unchanged, so a caller can substitute
    REST for the first without swallowing the second. Routed through `gh_json`
    so this stays the module's one gh-JSON seam.
    """
    try:
        return gh_json(args)
    except RuntimeError as exc:
        if is_graphql_unavailable(exc):
            raise GraphQLUnavailableError(
                f"{label}: GitHub's GraphQL API is not served to this session ({exc})"
            ) from exc
        raise


def is_owner_repo_pair(owner: str, repo: str) -> bool:
    """Whether `owner`/`repo` are both well-formed GitHub path segments.

    The one place the segment rules live. The PR-reference and scope-key parsers
    below, and both call sites in `babysit_resolve_thread.py`, all route through
    here, so none of the four can drift apart on what it accepts. `.` and `..`
    match `GITHUB_REPOSITORY_RE` but are path traversal, never a repository.
    """
    return bool(
        GITHUB_OWNER_RE.fullmatch(owner)
        and GITHUB_REPOSITORY_RE.fullmatch(repo)
        and repo not in {".", ".."}
    )


def parse_repo_number(value: str) -> tuple[str, int]:
    value = value.strip()
    owner = ""
    repo = ""
    number = ""
    parsed = urlparse(value)
    if parsed.scheme or parsed.netloc:
        parts = [unquote(part) for part in parsed.path.strip("/").split("/")]
        if (
            parsed.scheme.casefold() == "https"
            and parsed.hostname
            and parsed.hostname.casefold() == "github.com"
            and parsed.username is None
            and parsed.password is None
            and parsed.port is None
            and len(parts) == 4
            and parts[2].casefold() == "pull"
        ):
            owner, repo, number = parts[0], parts[1], parts[3]
    else:
        short_match = re.fullmatch(r"([^/\\#\s]+)/([^/\\#\s]+)#(\d+)", value)
        if short_match:
            owner, repo, number = short_match.groups()
    if is_owner_repo_pair(owner, repo) and number.isdigit():
        return f"{owner}/{repo}".casefold(), int(number)
    raise ValueError(f"Expected PR URL or owner/repo#number, got: {value}")


def parse_repo(value: str) -> str:
    """Validate and normalize an `owner/repo` scope key (no PR number)."""
    match = re.fullmatch(r"([^/\\#\s]+)/([^/\\#\s]+)", value.strip())
    if not match or not is_owner_repo_pair(match.group(1), match.group(2)):
        raise ValueError(f"Expected owner/repo, got: {value}")
    return f"{match.group(1)}/{match.group(2)}".casefold()


def list_repos_for_owner(owner: str) -> list[str]:
    text = run_gh(
        [
            "repo",
            "list",
            owner,
            "--limit",
            str(REPOSITORY_LIST_LIMIT),
            "--json",
            "nameWithOwner",
            "--jq",
            ".[].nameWithOwner",
        ]
    )
    repos = [line.strip().casefold() for line in text.splitlines() if line.strip()]
    if len(repos) >= REPOSITORY_LIST_LIMIT:
        raise RuntimeError(
            f"repository result limit {REPOSITORY_LIST_LIMIT} reached for {owner}; queue may be incomplete"
        )
    return repos


def resolve_author(author: str | None) -> str | None:
    """Resolve an author filter to a concrete login. '@me' -> authenticated user.

    Resolving '@me' up front keeps the scope gate deterministic and identical
    across `gh search prs` and `gh pr list`, which differ in how they treat the
    '@me' token.
    """
    if not author:
        return None
    if author != "@me":
        return author
    login = run_gh(["api", "user", "--jq", ".login"]).strip()
    if not login:
        raise RuntimeError("could not resolve '@me': gh returned no login")
    return login


def resolve_authors(value: str | None) -> list[str]:
    """Resolve a comma-separated author filter to concrete logins.

    `self_logins` is a multi-value key, but `gh`'s `--author` accepts a single
    login: a comma-joined value would match no one, silently dropping owned PRs
    for users with more than one login. Split it, resolve each ('@me' -> the
    authenticated user), and deduplicate case-insensitively (GitHub logins are
    case-insensitive) while preserving order.
    """
    resolved: dict[str, str] = {}
    for part in (value or "").split(","):
        login = resolve_author(part.strip())
        if login:
            resolved.setdefault(login.casefold(), login)
    return list(resolved.values())


def _search_prs_for_owners(
    owners: list[str], limit: int, author: str | None
) -> tuple[dict[str, tuple[str, int]], list[str]]:
    found: dict[str, tuple[str, int]] = {}
    errors: list[str] = []
    per_owner_limit = max(limit, 1)
    for owner in owners:
        try:
            rows = gh_json(
                [
                    "search",
                    "prs",
                    "--state",
                    "open",
                    "--owner",
                    owner,
                    *(["--author", author] if author else []),
                    "--json",
                    SEARCH_FIELDS,
                    "--limit",
                    str(per_owner_limit),
                ]
            )
        except RuntimeError as exc:
            try:
                owner_has_repos = bool(list_repos_for_owner(owner))
            except RuntimeError:
                owner_has_repos = True  # unconfirmed; fail closed as before.
            if not owner_has_repos:
                # GitHub's search API rejects an owner qualifier that has zero
                # repositories rather than returning empty results. The repo
                # listing above authoritatively confirms there is nothing to
                # search, so this is not queue-completeness uncertainty.
                continue
            errors.append(f"owner search {owner}: {exc}")
            continue
        for row in json_array(rows):
            if not is_json_object(row):
                continue
            repo_obj = json_object(row.get("repository"))
            repo = str(repo_obj.get("nameWithOwner") or "").casefold()
            number = row.get("number")
            if repo and number:
                found[f"{repo}#{number}"] = (repo, int(number))
    return found, errors


def _list_prs_for_repo(
    repo: str,
    per_repo_limit: int,
    author: str | None,
    found: dict[str, tuple[str, int]],
    errors: list[str],
) -> None:
    try:
        rows = gh_json(
            [
                "pr",
                "list",
                "-R",
                repo,
                "--state",
                "open",
                *(["--author", author] if author else []),
                "--json",
                RECONCILE_FIELDS,
                "--limit",
                str(per_repo_limit),
            ]
        )
    except RuntimeError as exc:
        errors.append(f"repository reconcile {repo}: {exc}")
        return
    if len(rows or []) >= per_repo_limit:
        errors.append(
            f"repository reconcile {repo}: result limit {per_repo_limit} reached; queue may be incomplete"
        )
    for row in json_array(rows):
        if not is_json_object(row):
            continue
        repo_obj = json_object(row.get("repository"))
        repo_name = str(repo_obj.get("nameWithOwner") or repo).casefold()
        number = row.get("number")
        if repo_name and number:
            found[f"{repo_name}#{number}"] = (repo_name, int(number))


def _list_prs_for_owners(
    owners: list[str], limit: int, author: str | None
) -> tuple[dict[str, tuple[str, int]], list[str]]:
    found: dict[str, tuple[str, int]] = {}
    errors: list[str] = []
    per_repo_limit = max(limit, 1)
    for owner in owners:
        try:
            repos = list_repos_for_owner(owner)
        except RuntimeError as exc:
            errors.append(f"repository list {owner}: {exc}")
            continue
        for repo in repos:
            _list_prs_for_repo(repo, per_repo_limit, author, found, errors)
    return found, errors


def discover_prs(
    *,
    owners: Iterable[str] | None = None,
    repos: Iterable[str] | None = None,
    authors: Iterable[str] | None = None,
    limit: int = 1000,
) -> tuple[list[tuple[str, int]], list[str]]:
    """Discover open PRs along exactly one axis: watched owners or explicit repos.

    Owner mode unions two independent strategies so neither's blind spot loses
    a PR: an owner-wide search (tolerates owners with zero repositories, whose
    search qualifier GitHub rejects outright) and a per-repository listing
    sweep (detects when a repository hits the per-repo result limit and flags
    the queue as possibly incomplete). Explicit-repo mode lists just those
    repositories -- the normal shape for one babysit session per repo -- with
    the same limit-reached detection and no owner-wide sweep. Output is always
    sorted and deduplicated by `owner/repo#number`.

    `gh`'s `--author` accepts a single login, so multiple authors are queried
    one at a time and their results unioned; an empty author list discovers
    every author under the axis. Errors are deduplicated across author passes
    since they are keyed by owner/repo, not author.
    """
    owner_list = [owner for owner in (owners or []) if owner]
    repo_list = [repo for repo in (repos or []) if repo]
    if bool(owner_list) == bool(repo_list):
        raise ValueError("discover_prs requires exactly one of owners or repos")
    author_list: list[str | None] = [author for author in (authors or []) if author]
    if not author_list:
        author_list = [None]
    found: dict[str, tuple[str, int]] = {}
    errors: list[str] = []
    if repo_list:
        per_repo_limit = max(limit, 1)
        for author in author_list:
            for repo in repo_list:
                _list_prs_for_repo(repo, per_repo_limit, author, found, errors)
    else:
        for author in author_list:
            searched, search_errors = _search_prs_for_owners(owner_list, limit, author)
            listed, list_errors = _list_prs_for_owners(owner_list, limit, author)
            found.update(searched)
            found.update(listed)
            errors.extend(search_errors)
            errors.extend(list_errors)
    return sorted(found.values()), list(dict.fromkeys(errors))


def fetch_pull_request_author(repo: str, number: int) -> str:
    """The PR author's login from `gh pr view --json author`."""
    repo = repo.casefold()
    author = gh_json(["pr", "view", str(number), "--repo", repo, "--json", "author"])
    if not is_json_object(author):
        raise RuntimeError(f"Unexpected gh pr view author for {repo}#{number}")
    return str(author.get("login") or "")


def view_pr_fields(
    repo: str,
    number: int,
    fields: Iterable[str],
    *,
    run_json: Callable[[list[str]], Any] | None = None,
) -> tuple[dict[str, Any], bool]:
    """`gh pr view --json <fields>`, re-sourced over REST when GraphQL is refused.

    `gh pr view --json` is implemented entirely over GraphQL, so it is the first
    read in this engine to fail where only a pinned set of GraphQL operations is
    served. Returns the field bundle plus whether it came from GraphQL; a REST
    bundle carries only the fields `rest_view_pr` can rebuild, so a caller that
    asked for a GraphQL-only field (`closingIssuesReferences`) gets it absent
    rather than fabricated, and must fail closed on the absence.

    `run_json` lets a caller supply its own gh-JSON seam so the snapshot engine
    and the merge gate share this one implementation while each keeps the
    single call seam its own module already exposes; it defaults to this
    module's `gh_json`.
    """
    runner = gh_json if run_json is None else run_json
    requested = list(fields)
    try:
        data = runner(
            ["pr", "view", str(number), "--repo", repo, "--json", ",".join(requested)]
        )
    except RuntimeError as exc:
        if not is_graphql_unavailable(exc):
            raise
        rest = rest_view_pr(repo, number)
        return {name: rest[name] for name in requested if name in rest}, False
    if not is_json_object(data):
        raise RuntimeError(f"Unexpected gh pr view response for {repo}#{number}")
    return cast(dict[str, Any], data), True


def repository_is_archived(repo: str) -> bool:
    """Whether the repository is archived, over GraphQL or REST.

    `gh repo view --json` is GraphQL-backed and 403s alongside `gh pr view`;
    `GET /repos/{owner}/{repo}` reports the same fact as `.archived`.
    """
    try:
        repository = gh_json_graphql(
            ["repo", "view", repo, "--json", "isArchived"],
            label=f"{repo} archived state",
        )
        archived = repository.get("isArchived") if is_json_object(repository) else None
    except GraphQLUnavailableError:
        rest = gh_json(["api", f"repos/{repo}", "--jq", "{archived: .archived}"])
        archived = rest.get("archived") if is_json_object(rest) else None
    if not isinstance(archived, bool):
        raise RuntimeError(f"Unable to determine whether {repo} is archived")
    return archived


def view_pr(repo: str, number: int) -> dict[str, Any]:
    repo = repo.casefold()
    data, graphql_available = view_pr_fields(repo, number, VIEW_FIELD_NAMES)
    data["repo"] = repo
    data["_graphql_available"] = graphql_available
    data["baseRepositoryArchived"] = repository_is_archived(repo)
    if str(data.get("mergeStateStatus") or "").upper() == "BLOCKED":
        data["_blocked_base_compare"] = fetch_blocked_base_compare(
            repo,
            str(data.get("baseRefName") or ""),
            str(data.get("headRefOid") or ""),
        )
    return data


def rest_check_rollup(repo: str, head_sha: str) -> list[dict[str, Any]]:
    """Rebuild GraphQL's `statusCheckRollup` for one commit out of REST.

    Two endpoints, because the rollup is a union of two node types that
    `babysit_checks.normalize_check` keys apart by `__typename`:
    `/commits/{sha}/check-runs` supplies the CheckRun half and
    `/commits/{sha}/status` the StatusContext half. REST spells the enum values
    in lower case where GraphQL spells them upper; `normalize_check` upper-cases
    them itself, so the raw strings pass through unchanged.

    REST check-runs carry no workflow name, and `dedupe_latest_checks` keys on
    it so that two workflows exposing the same job name cannot hide each other's
    result. It is recovered best-effort from the commit's workflow runs, keyed by
    check-suite id; when that lookup is unavailable (Actions disabled, a
    permission gap) the name is left empty, which is the pre-existing behaviour
    for any rollup entry GitHub reports without one.
    """
    workflow_names: dict[int, str] = {}
    try:
        runs = gh_json(
            ["api", f"repos/{repo}/actions/runs?head_sha={head_sha}&per_page=100"]
        )
    except (RuntimeError, json.JSONDecodeError):
        runs = None
    for run in json_array(json_object(runs).get("workflow_runs")):
        if not is_json_object(run):
            continue
        suite_id = run.get("check_suite_id")
        if isinstance(suite_id, int):
            workflow_names[suite_id] = str(run.get("name") or "")

    rollup: list[dict[str, Any]] = []
    for run in fetch_paginated_api(
        f"repos/{repo}/commits/{head_sha}/check-runs?per_page=100",
        f"{repo}@{head_sha} check runs",
    ):
        suite_id = json_object(run.get("check_suite")).get("id")
        rollup.append(
            {
                "__typename": "CheckRun",
                "name": str(run.get("name") or ""),
                "status": str(run.get("status") or ""),
                "conclusion": str(run.get("conclusion") or ""),
                "startedAt": str(run.get("started_at") or ""),
                "completedAt": str(run.get("completed_at") or ""),
                "detailsUrl": str(run.get("details_url") or ""),
                "workflowName": workflow_names.get(
                    suite_id if isinstance(suite_id, int) else -1, ""
                ),
            }
        )

    combined = gh_json(["api", f"repos/{repo}/commits/{head_sha}/status"])
    for status in json_array(json_object(combined).get("statuses")):
        if not is_json_object(status):
            continue
        rollup.append(
            {
                "__typename": "StatusContext",
                "context": str(status.get("context") or ""),
                "state": str(status.get("state") or ""),
                "targetUrl": str(status.get("target_url") or ""),
                "createdAt": str(status.get("created_at") or ""),
            }
        )
    return rollup


def rest_review_decision(reviews: list[dict[str, Any]]) -> str:
    """The one direction of `reviewDecision` REST can prove: CHANGES_REQUESTED.

    GraphQL's `reviewDecision` folds in CODEOWNERS and the branch's required
    reviewer count, neither of which the reviews list carries, so a derived
    `APPROVED` would claim more than the evidence supports and would clear the
    merge gate's `required_reviews and reviewDecision != "APPROVED"` hold. The
    blocking direction is safe to derive and dangerous to lose: it is the human
    stop that both the snapshot and the merge gate key on. So the latest
    decisive review per author is folded, a single CHANGES_REQUESTED wins, and
    everything else reports empty -- which the merge gate already treats as
    "not approved" and holds on any protected base.
    """
    latest: dict[str, str] = {}
    for review in sorted(reviews, key=lambda item: str(item.get("submittedAt") or "")):
        state = str(review.get("state") or "").upper()
        if state not in {"APPROVED", "CHANGES_REQUESTED", "DISMISSED"}:
            continue
        login = str(json_object(review.get("author")).get("login") or "")
        latest[login] = state
    return "CHANGES_REQUESTED" if "CHANGES_REQUESTED" in latest.values() else ""


def rest_view_pr(repo: str, number: int) -> dict[str, Any]:
    """The `gh pr view --json` bundle rebuilt from REST, field for field.

    Every field in `VIEW_FIELD_NAMES` that REST can source is sourced here, so
    the engine keeps reading the same fact from the same key whichever API
    answered. Three deliberate gaps:

    * `comments` is left empty. It is the issue-comment list, which the snapshot
      overwrites with `fetch_issue_comments` (REST already) on the very next
      line; refetching it here would double the call for no new fact.
    * `latestReviews` is omitted entirely, exactly as `rest_hydrate_reviews`
      drops it -- the paginated `reviews` list supersedes it.
    * `reviewDecision` carries only the blocking direction (see
      `rest_review_decision`).

    Nothing here reconstructs review-thread RESOLUTION: REST has no equivalent,
    and inventing one would substitute a lesser signal for a gate verdict
    (`reference/safety.md`). `fetch_review_threads` fails closed instead.
    """
    data = gh_json(["api", f"repos/{repo}/pulls/{number}"])
    if not is_json_object(data):
        raise RuntimeError(f"Unexpected REST pull request response for {repo}#{number}")
    pull = cast(dict[str, Any], data)
    head = json_object(pull.get("head"))
    base = json_object(pull.get("base"))
    head_repo = str(json_object(head.get("repo")).get("full_name") or "")
    base_repo = str(json_object(base.get("repo")).get("full_name") or "")
    head_sha = str(head.get("sha") or "")
    mergeable = pull.get("mergeable")
    reviews = fetch_pull_request_reviews(repo, number)
    return {
        "author": normalized_rest_author(pull),
        "baseRefName": str(base.get("ref") or ""),
        "comments": [],
        "headRefName": str(head.get("ref") or ""),
        "headRefOid": head_sha,
        "headRepository": {"nameWithOwner": head_repo},
        "headRepositoryOwner": {
            "login": str(
                json_object(json_object(head.get("repo")).get("owner")).get("login")
                or ""
            )
        },
        "isDraft": bool(pull.get("draft")),
        "isCrossRepository": bool(head_repo and base_repo and head_repo != base_repo),
        # REST labels already carry `name`, the only key any caller reads.
        "labels": json_array(pull.get("labels")),
        "mergeStateStatus": str(pull.get("mergeable_state") or "").upper(),
        # REST reports a tri-state boolean where GraphQL reports an enum; `null`
        # means GitHub has not finished computing it, which is UNKNOWN, never
        # mergeable.
        "mergeable": (
            "MERGEABLE"
            if mergeable is True
            else "CONFLICTING"
            if mergeable is False
            else "UNKNOWN"
        ),
        "maintainerCanModify": bool(pull.get("maintainer_can_modify")),
        "number": pull.get("number"),
        "reviewDecision": rest_review_decision(reviews),
        "reviews": reviews,
        "state": (
            "MERGED" if pull.get("merged") else str(pull.get("state") or "").upper()
        ),
        "statusCheckRollup": rest_check_rollup(repo, head_sha) if head_sha else [],
        "title": str(pull.get("title") or ""),
        "updatedAt": str(pull.get("updated_at") or ""),
        "url": str(pull.get("html_url") or ""),
    }


def fetch_blocked_base_compare(
    repo: str, base_ref: str, head_sha: str
) -> dict[str, Any] | None:
    """Best-effort divergence check for a BLOCKED PR against the LIVE base tip.

    GitHub's `mergeStateStatus` is a single-valued field: when a PR is both
    genuinely behind its base AND blocked by another gate (failing required
    checks, missing review, ...), GitHub reports BLOCKED and the BEHIND signal
    is lost -- observed live, not documented. This recovers that signal from
    GitHub's own compare endpoint so a stale-but-BLOCKED branch is not
    permanently invisible to the refresh gate.

    Compares against the base ref NAME, never the PR's cached `baseRefOid`:
    that field lags once the base branch advances past the PR's last sync
    (verified empirically -- a real PR's `baseRefOid` reported `ahead_by=0`
    against its own stale value while the live base branch tip reported
    `behind_by=11`, `status=diverged`, for the identical head commit). Only a
    ref NAME resolves to the live tip at query time.

    Best-effort and fail-closed: any error returns None, and the caller falls
    back to `not_reported_behind` -- identical to the no-fallback behavior. A
    hiccup here must never fail the whole snapshot for that PR, and never
    grants eligibility on uncertain data.
    """
    if not base_ref or not re.fullmatch(r"[0-9a-fA-F]{7,40}", head_sha):
        return None
    try:
        data = gh_json(
            ["api", f"repos/{repo}/compare/{quote(base_ref, safe='')}...{head_sha}"]
        )
    except RuntimeError:
        return None
    if not is_json_object(data):
        return None
    status = str(data.get("status") or "")
    ahead_by = data.get("ahead_by")
    behind_by = data.get("behind_by")
    if (
        status not in {"identical", "ahead", "behind", "diverged"}
        or not isinstance(ahead_by, int)
        or not isinstance(behind_by, int)
    ):
        return None
    return {"status": status, "ahead_by": ahead_by, "behind_by": behind_by}


def flatten_paginated_items(value: Any, label: str) -> list[dict[str, Any]]:
    """Flatten `gh api --paginate --slurp` output and reject unknown shapes."""
    if not is_json_array(value):
        raise RuntimeError(f"Unexpected paginated response for {label}")
    if value and all(is_json_array(page) for page in value):
        items = [item for page in value for item in page]
        if not all(is_json_object(item) for item in items):
            raise RuntimeError(f"Unexpected paginated response items for {label}")
        return items
    if all(is_json_object(item) for item in value):
        return list(value)
    raise RuntimeError(f"Unexpected paginated response items for {label}")


def fetch_paginated_api(endpoint: str, label: str) -> list[dict[str, Any]]:
    return flatten_paginated_items(
        gh_json(["api", endpoint, "--paginate", "--slurp"]), label
    )


def normalized_rest_author(item: dict[str, Any]) -> dict[str, Any]:
    user = item.get("user")
    if not is_json_object(user):
        return {"login": ""}
    typename = str(user.get("type") or "")
    return {
        "__typename": typename,
        "login": str(user.get("login") or ""),
        "is_bot": typename == "Bot",
    }


def fetch_issue_comments(repo: str, number: int) -> list[dict[str, Any]]:
    rows = fetch_paginated_api(
        f"repos/{repo}/issues/{number}/comments?per_page=100",
        f"{repo}#{number} issue comments",
    )
    return [
        {
            "id": row.get("id"),
            "author": normalized_rest_author(row),
            "authorAssociation": str(row.get("author_association") or ""),
            "body": str(row.get("body") or ""),
            "createdAt": str(row.get("created_at") or ""),
            "updatedAt": str(row.get("updated_at") or ""),
            "url": str(row.get("html_url") or ""),
        }
        for row in rows
    ]


def fetch_pull_request_commits(repo: str, number: int) -> list[dict[str, Any]]:
    """Every commit on the PR with its signature-verification verdict.

    Reads `.commit.verification` per commit -- `verified` plus GitHub's
    `reason` string (`valid`, `unsigned`, `no_user`, `unknown_key`, ...). A row
    whose verification block is missing is reported unverified with reason
    `unreadable` rather than skipped: the caller enforcing a signature rule may
    only ever over-report.

    GitHub's `GET /repos/{owner}/{repo}/pulls/{n}/commits` endpoint returns at
    most **250** commits regardless of pagination; when the PR carries more, this
    raises `RuntimeError` so callers fail closed rather than under-report.
    """
    rows = fetch_paginated_api(
        f"repos/{repo}/pulls/{number}/commits?per_page=100",
        f"{repo}#{number} commits",
    )
    reported_total = gh_json(
        ["api", f"repos/{repo}/pulls/{number}", "--jq", ".commits"]
    )
    total = int(reported_total) if isinstance(reported_total, int) else 0
    # GitHub documents a 250-commit ceiling on this endpoint; pagination does not
    # lift it, so a short walk against a larger PR is under-reporting.
    if total > len(rows) and len(rows) >= 250:
        raise RuntimeError(
            f"commit list exceeded the API's 250-commit cap "
            f"(walked {len(rows)} of {total})"
        )
    out: list[dict[str, Any]] = []
    for row in rows:
        commit = row.get("commit")
        verification = commit.get("verification") if is_json_object(commit) else None
        if is_json_object(verification):
            verified = verification.get("verified") is True
            reason = str(verification.get("reason") or "unreadable")
        else:
            verified = False
            reason = "unreadable"
        out.append(
            {"sha": str(row.get("sha") or ""), "verified": verified, "reason": reason}
        )
    return out


def fetch_pull_request_reviews(repo: str, number: int) -> list[dict[str, Any]]:
    rows = fetch_paginated_api(
        f"repos/{repo}/pulls/{number}/reviews?per_page=100",
        f"{repo}#{number} reviews",
    )
    return [
        {
            "id": row.get("id"),
            "author": normalized_rest_author(row),
            "authorAssociation": str(row.get("author_association") or ""),
            "body": str(row.get("body") or ""),
            "submittedAt": str(row.get("submitted_at") or ""),
            "state": str(row.get("state") or ""),
            "commit": {"oid": str(row.get("commit_id") or "")},
            "url": str(row.get("html_url") or ""),
        }
        for row in rows
    ]


def rest_hydrate_reviews(pr: dict[str, Any], repo: str, number: int) -> None:
    """Replace `pr["reviews"]` with the fully-typed REST list, in place, and
    drop the stale `pr["latestReviews"]` `gh pr view --json` carried.

    `gh pr view --json reviews,latestReviews` (`view_pr`'s `VIEW_FIELDS`)
    returns each review's `author` as `{login}` only -- no `__typename`, no
    `is_bot`, and a bot's login without its `[bot]` suffix (verified live:
    GraphQL's own `latestReviews.nodes.author` reports `__typename: "Bot"`
    for the same actor, so this is a `gh` CLI JSON-field limitation, not a
    GraphQL one). `fetch_pull_request_reviews` (REST) attaches proper typing
    via `normalized_rest_author`, so every current classification caller
    already overwrites `reviews` with it -- but `latestReviews` was left
    behind untouched. `collect_feedback`'s `latest_reviews_by_author` merges
    both collections, so the untyped `latestReviews` entry for the same bot
    actor keyed under a different (suffix-less) login and was not deduped
    against the correctly-typed `reviews` entry, surfacing as a spurious
    "new human feedback" line (#683). Dropping `latestReviews` here is safe:
    the REST `reviews` list is complete and paginated, so
    `latest_reviews_by_author` already derives the latest review per author
    from it alone.
    """
    pr["reviews"] = fetch_pull_request_reviews(repo, number)
    pr.pop("latestReviews", None)


def fetch_pull_request_review_comments(repo: str, number: int) -> list[dict[str, Any]]:
    return fetch_paginated_api(
        f"repos/{repo}/pulls/{number}/comments?per_page=100",
        f"{repo}#{number} review comments",
    )


def fetch_review_threads(
    repo: str,
    number: int,
    *,
    include_resolved: bool = False,
    comments_first: int = 100,
    projection: Callable[[dict[str, Any]], Any] | None = None,
) -> list[Any]:
    """The single GraphQL reviewThreads paginator behind every consumer.

    Pages the thread connection with fail-closed pageInfo validation: any
    malformed node, connection, or cursor raises, because an undisclosed page
    could hide an unresolved thread. Comment-connection size is the deliberate
    exception -- a thread with more than `comments_first` comments is returned
    truncated with `comments_truncated` True, and a zero-comment thread is
    returned with an empty list, so one oversized or degenerate thread can
    never fail the whole snapshot. Callers that need every comment (or an
    exact count) consult `comments_truncated`/`comments_total_count` instead
    of trusting `comments` to be complete.

    Raises `GraphQLUnavailableError` where the session is not served GraphQL.
    Thread RESOLUTION has no REST equivalent, and an empty list would read as
    "zero unresolved threads" -- a false-clean signal on the exact input the
    merge gate keys on -- so the refusal is raised as itself and every caller
    fails closed on it. Callers that need only the comments, not their
    resolution state, re-source those over REST
    (`fetch_unresolved_review_comments`).

    Each thread record carries: `id`, `isResolved`, `isOutdated`, `comments`
    (each with author{__typename login}, body, path, url, createdAt, updatedAt,
    databaseId), `comments_total_count`, and `comments_truncated`. Resolved
    threads are dropped unless `include_resolved`. `projection` maps each
    record to the caller's shape inside the loop.
    """
    if not isinstance(comments_first, int) or not 1 <= comments_first <= 100:
        raise ValueError("comments_first must be an integer between 1 and 100")
    owner, name = repo.split("/", 1)
    query = (
        "query($o:String!,$r:String!,$n:Int!,$cursor:String){"
        "repository(owner:$o,name:$r){pullRequest(number:$n){"
        "reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor} "
        "nodes{id isResolved isOutdated "
        f"comments(first:{comments_first})"
        "{totalCount pageInfo{hasNextPage} "
        "nodes{author{__typename login} body path url createdAt updatedAt databaseId}}}}}}}"
    )
    threads: list[Any] = []
    cursor: str | None = None
    while True:
        args = [
            "api",
            "graphql",
            "-f",
            f"query={query}",
            "-F",
            f"o={owner}",
            "-F",
            f"r={name}",
            "-F",
            f"n={number}",
        ]
        if cursor:
            args.extend(["-F", f"cursor={cursor}"])
        data = gh_json_graphql(args, label=f"{repo}#{number} review threads")
        if not is_json_object(data) or data.get("errors"):
            raise RuntimeError(f"Incomplete review-thread response for {repo}#{number}")
        connection = dig(data, "data", "repository", "pullRequest", "reviewThreads")
        if not is_json_object(connection):
            raise RuntimeError(f"Missing review-thread connection for {repo}#{number}")
        nodes = connection.get("nodes")
        page_info = connection.get("pageInfo")
        if not is_json_array(nodes) or not is_json_object(page_info):
            raise RuntimeError(
                f"Malformed review-thread connection for {repo}#{number}"
            )
        has_next_page = page_info.get("hasNextPage")
        if not isinstance(has_next_page, bool):
            raise RuntimeError(f"Malformed review-thread page info for {repo}#{number}")
        for thread in nodes:
            if (
                not is_json_object(thread)
                or not isinstance(thread.get("id"), str)
                or not isinstance(thread.get("isResolved"), bool)
                or not isinstance(thread.get("isOutdated"), bool)
            ):
                raise RuntimeError(f"Malformed review thread for {repo}#{number}")
            if thread["isResolved"] and not include_resolved:
                continue
            comment_connection = thread.get("comments")
            if not is_json_object(comment_connection):
                raise RuntimeError(
                    f"Malformed comments connection in review thread {thread['id']}"
                )
            comment_page_info = comment_connection.get("pageInfo")
            comment_nodes = comment_connection.get("nodes")
            total_count = comment_connection.get("totalCount")
            if (
                not is_json_object(comment_page_info)
                or not isinstance(comment_page_info.get("hasNextPage"), bool)
                or not is_json_array(comment_nodes)
                or not isinstance(total_count, int)
            ):
                raise RuntimeError(
                    f"Malformed comments connection in review thread {thread['id']}"
                )
            comments: list[dict[str, Any]] = []
            for comment in comment_nodes:
                if not is_json_object(comment):
                    raise RuntimeError(
                        f"Malformed comment in review thread {thread['id']}"
                    )
                author = comment.get("author")
                if author is not None and not is_json_object(author):
                    raise RuntimeError(
                        f"Malformed comment author in review thread {thread['id']}"
                    )
                if any(
                    key not in comment
                    for key in (
                        "body",
                        "path",
                        "url",
                        "createdAt",
                        "updatedAt",
                        "databaseId",
                    )
                ):
                    raise RuntimeError(
                        f"Incomplete comment in review thread {thread['id']}"
                    )
                comments.append(dict(comment))
            record = {
                "id": thread["id"],
                "isResolved": thread["isResolved"],
                "isOutdated": thread["isOutdated"],
                "comments": comments,
                "comments_total_count": total_count,
                "comments_truncated": bool(comment_page_info["hasNextPage"]),
            }
            threads.append(projection(record) if projection is not None else record)
        if not has_next_page:
            break
        cursor = str(page_info.get("endCursor") or "")
        if not cursor:
            raise RuntimeError(f"Missing review-thread cursor for {repo}#{number}")
    return threads


def fetch_unresolved_review_comments(repo: str, number: int) -> list[dict[str, Any]]:
    """Fetch unresolved inline review comments (gh pr view omits these).

    Where GraphQL is refused, the comments themselves are still REST-readable --
    only their thread's resolution state is not. Rather than drop the PR's inline
    feedback entirely, every inline comment is returned with
    `threadResolutionUnproven` set, `threadIsOutdated` False, and no resolved
    thread filtered out. That over-reports (a long-settled thread reads as open)
    and over-reporting is the safe direction here: it sends more feedback to a
    human, where the under-report would let addressed-looking work through. It is
    NOT a substitute for the merge gate's thread-resolution input, which fails
    closed separately.
    """
    try:
        threads = fetch_review_threads(repo, number)
    except GraphQLUnavailableError:
        return [
            {
                "author": normalized_rest_author(row),
                "body": str(row.get("body") or ""),
                "path": str(row.get("path") or ""),
                "url": str(row.get("html_url") or ""),
                "createdAt": str(row.get("created_at") or ""),
                "updatedAt": str(row.get("updated_at") or ""),
                "databaseId": row.get("id"),
                "threadIsOutdated": False,
                "threadResolutionUnproven": True,
            }
            for row in fetch_pull_request_review_comments(repo, number)
        ]
    return [
        {**comment, "threadIsOutdated": thread["isOutdated"]}
        for thread in threads
        for comment in thread["comments"]
    ]


def find_open_prs_for_head_ref(pr: dict[str, Any]) -> list[str]:
    head_repo = str(
        pr.get("head_repository")
        or json_object(pr.get("headRepository")).get("nameWithOwner")
        or ""
    ).casefold()
    head_ref = str(pr.get("head_ref") or pr.get("headRefName") or "")
    head_sha = str(pr.get("head_sha") or pr.get("headRefOid") or "")
    if (
        not head_repo
        or not head_ref
        or not re.fullmatch(r"[0-9a-fA-F]{40,64}", head_sha)
    ):
        raise RuntimeError("head repository/ref/SHA metadata is incomplete")
    rows = fetch_paginated_api(
        f"repos/{head_repo}/commits/{head_sha}/pulls?per_page=100",
        f"{head_repo}@{head_sha} associated pull requests",
    )
    matches: list[str] = []
    for row in rows:
        state = row.get("state")
        if not isinstance(state, str):
            raise RuntimeError("Associated pull request has no state")
        if state.casefold() != "open":
            continue
        base_repo = dig(row, "base", "repo", "full_name")
        candidate_head_repo = dig(row, "head", "repo", "full_name")
        candidate_head_ref = dig(row, "head", "ref")
        number = row.get("number")
        if (
            not isinstance(base_repo, str)
            or not isinstance(candidate_head_repo, str)
            or not isinstance(candidate_head_ref, str)
            or not isinstance(number, int)
        ):
            raise RuntimeError("Associated open pull request metadata is incomplete")
        if (
            candidate_head_repo.casefold() != head_repo
            or candidate_head_ref != head_ref
        ):
            continue
        canonical_repo, canonical_number = parse_repo_number(f"{base_repo}#{number}")
        matches.append(f"{canonical_repo}#{canonical_number}")
    return sorted(set(matches))

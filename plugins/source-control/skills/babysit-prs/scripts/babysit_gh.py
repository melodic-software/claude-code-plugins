#!/usr/bin/env python3
"""GitHub read helpers for the babysit-prs engine: gh runner, discovery,
hydration, REST pagination, and the single GraphQL review-thread paginator."""

from __future__ import annotations

import json
import math
import re
import subprocess
from collections.abc import Callable, Iterable
from typing import Any
from urllib.parse import quote, unquote, urlparse

from babysit_util import (
    DEFAULT_COMMAND_TIMEOUT_SECONDS,
    is_json_array,
    is_json_object,
    json_array,
    json_object,
    run_command,
)

REPOSITORY_LIST_LIMIT = 1001
VIEW_FIELDS = ",".join(
    [
        "author",
        "baseRefName",
        "baseRefOid",
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


def run_gh(args: list[str], *, timeout_seconds: float | None = None) -> str:
    """Run a gh command, raising on timeout or nonzero exit; returns stdout."""
    proc = run_command(
        ["gh", *args],
        allowed_executables=("gh",),
        timeout_seconds=(
            timeout_seconds if timeout_seconds is not None else _default_timeout_seconds
        ),
        check=True,
    )
    return proc.stdout


def gh_capture(
    args: list[str], *, timeout_seconds: float | None = None
) -> subprocess.CompletedProcess[str]:
    """Run a gh command capturing stdout/stderr/returncode without raising on
    nonzero exit -- for callers that inspect the returncode themselves."""
    return run_command(
        ["gh", *args],
        allowed_executables=("gh",),
        timeout_seconds=(
            timeout_seconds if timeout_seconds is not None else _default_timeout_seconds
        ),
        check=False,
    )


def gh_json(args: list[str]) -> Any:
    text = run_gh(args)
    return json.loads(text) if text.strip() else None


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
    if (
        GITHUB_OWNER_RE.fullmatch(owner)
        and GITHUB_REPOSITORY_RE.fullmatch(repo)
        and repo not in {".", ".."}
        and number.isdigit()
    ):
        return f"{owner}/{repo}".casefold(), int(number)
    raise ValueError(f"Expected PR URL or owner/repo#number, got: {value}")


def parse_repo(value: str) -> str:
    """Validate and normalize an `owner/repo` scope key (no PR number)."""
    match = re.fullmatch(r"([^/\\#\s]+)/([^/\\#\s]+)", value.strip())
    if (
        not match
        or not GITHUB_OWNER_RE.fullmatch(match.group(1))
        or not GITHUB_REPOSITORY_RE.fullmatch(match.group(2))
        or match.group(2) in {".", ".."}
    ):
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


def view_pr(repo: str, number: int) -> dict[str, Any]:
    repo = repo.casefold()
    data = gh_json(["pr", "view", str(number), "--repo", repo, "--json", VIEW_FIELDS])
    if not is_json_object(data):
        raise RuntimeError(f"Unexpected gh pr view response for {repo}#{number}")
    repository = gh_json(["repo", "view", repo, "--json", "isArchived"])
    if not is_json_object(repository) or not isinstance(
        repository.get("isArchived"), bool
    ):
        raise RuntimeError(f"Unable to determine whether {repo} is archived")
    data["repo"] = repo
    data["baseRepositoryArchived"] = repository["isArchived"]
    if str(data.get("mergeStateStatus") or "").upper() == "BLOCKED":
        data["_blocked_base_compare"] = fetch_blocked_base_compare(
            repo,
            str(data.get("baseRefName") or ""),
            str(data.get("headRefOid") or ""),
        )
    return data


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
        data = gh_json(args)
        if not is_json_object(data) or data.get("errors"):
            raise RuntimeError(f"Incomplete review-thread response for {repo}#{number}")
        root = data.get("data")
        repository = root.get("repository") if is_json_object(root) else None
        pull_request = (
            repository.get("pullRequest") if is_json_object(repository) else None
        )
        connection = (
            pull_request.get("reviewThreads") if is_json_object(pull_request) else None
        )
        if not is_json_object(connection):
            raise RuntimeError(f"Missing review-thread connection for {repo}#{number}")
        nodes = connection.get("nodes")
        page_info = connection.get("pageInfo")
        if not is_json_array(nodes) or not is_json_object(page_info):
            raise RuntimeError(f"Malformed review-thread connection for {repo}#{number}")
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
                    for key in ("body", "path", "url", "createdAt", "updatedAt", "databaseId")
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
    """Fetch unresolved inline review comments (gh pr view omits these)."""
    threads = fetch_review_threads(repo, number)
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
        base = row.get("base")
        base_repository = base.get("repo") if is_json_object(base) else None
        base_repo = (
            base_repository.get("full_name")
            if is_json_object(base_repository)
            else None
        )
        candidate_head = row.get("head")
        candidate_repository = (
            candidate_head.get("repo") if is_json_object(candidate_head) else None
        )
        candidate_head_repo = (
            candidate_repository.get("full_name")
            if is_json_object(candidate_repository)
            else None
        )
        candidate_head_ref = (
            candidate_head.get("ref") if is_json_object(candidate_head) else None
        )
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

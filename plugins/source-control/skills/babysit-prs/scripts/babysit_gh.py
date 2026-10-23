#!/usr/bin/env python3
"""GitHub read helpers for the babysit-prs engine: gh runner, discovery,
hydration, REST pagination, and the single GraphQL review-thread paginator."""

from __future__ import annotations

import atexit
import contextlib
import json
import math
import os
import re
import subprocess
import sys
from collections.abc import Callable, Iterable, Iterator, Mapping
from typing import Any, Literal, cast, overload
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
VIEW_FIELD_NAMES: tuple[str, ...] = (
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
)
VIEW_FIELDS = ",".join(VIEW_FIELD_NAMES)
# `mergeStateStatus` values under which `view_pr` compares the head against the
# live base: BLOCKED can mask BEHIND, and CLEAN/HAS_HOOKS do not imply an
# up-to-date head on a base that does not require one.
BASE_COMPARE_MERGE_STATES = frozenset({"BLOCKED", "CLEAN", "HAS_HOOKS"})
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


GH_CALLS_PREFIX = "babysit-gh-calls"
_GH_API_VALUE_FLAGS = frozenset(
    {"-X", "--method", "-f", "--raw-field", "-F", "--field", "-H", "--header"}
    | {"-q", "--jq", "-t", "--template", "--input", "-p", "--preview"}
    | {"--hostname", "--cache"}
)
_GH_API_BODY_FLAGS = frozenset({"-f", "--raw-field", "-F", "--field", "--input"})
# The REST route words the babysit scripts call. Any other segment is logged
# as `{}`, so a value that happens to look like a word (a branch, an owner, a
# label) never reaches the log; a new route word reads as `{}` until it is
# added here.
_ROUTE_WORDS = frozenset(
    {"actions", "activity", "annotations", "app", "artifacts", "attempts"}
    | {"branches", "check-runs", "collaborators", "comments", "commits"}
    | {"compare", "contents", "dependabot", "dispatches", "files", "git"}
    | {"heads", "issues", "jobs", "labels", "logs", "merge-async"}
    | {"organization-variables", "orgs", "permission", "pulls", "reactions"}
    | {"ref", "repos", "rerun", "rerun-failed-jobs", "reviews", "rules", "runs"}
    | {"stacks", "status", "timeline", "trees", "update-branch", "user"}
    | {"users", "variables", "workflows", "zip"}
)
# Everything after one of these is a single value that may hold slashes (a
# branch, a file path), so the rest of the route is one `{}`.
_REST_IS_VALUE_WORDS = frozenset({"contents", "heads"})
# The segment after one of these is always a value (an owner, a branch, a
# commit-ish, a range), even when it spells a route word.
_VALUE_AFTER_WORDS = frozenset({"orgs", "users", "branches", "commits", "compare"})
_gh_call_counts: dict[str, int] = {}


def gh_call_kind(args: list[str], env_overrides: Mapping[str, str] | None) -> str:
    """The counter key for one gh invocation: token, then endpoint kind.

    The token is `override` when the call carries its own `GH_TOKEN`, else
    `default`. An `api` call is `graphql` or its HTTP method and route template:
    `gh api` sends GET, or POST once a body flag is given, unless `-X` names one.
    Every segment that is not one of `_ROUTE_WORDS`, the owner and repository
    after `repos/`, the segment after a `_VALUE_AFTER_WORDS` word, and
    everything after `contents` or `heads` become `{}`, and
    the query string is dropped, so no identifier, branch name, path,
    or other value reaches the log. `+paginate` marks a key whose invocations
    each make one HTTP request per page. Any other subcommand is `gh <sub> <verb>`.
    """
    token = "override" if env_overrides and "GH_TOKEN" in env_overrides else "default"
    if not args or args[0] != "api":
        return f"{token} gh {' '.join(args[:2])}"
    method = ""
    has_body = paginate = False
    endpoint = None
    rest = iter(args[1:])
    for arg in rest:
        flag, has_value, value = arg.partition("=")
        if arg.startswith("-") and flag in _GH_API_VALUE_FLAGS:
            value = value if has_value else next(rest, "")
            if flag in ("-X", "--method"):
                method = value.upper()
            has_body = has_body or flag in _GH_API_BODY_FLAGS
        elif arg == "--paginate":
            paginate = True
        elif not arg.startswith("-") and endpoint is None:
            endpoint = arg
    suffix = "+paginate" if paginate else ""
    if endpoint == "graphql":
        return f"{token} graphql{suffix}"
    segments = (endpoint or "").split("?", 1)[0].strip("/").split("/")
    route: list[str] = []
    for index, segment in enumerate(segments):
        owned = (segments[0] == "repos" and index in (1, 2)) or (
            index > 0 and segments[index - 1] in _VALUE_AFTER_WORDS
        )
        route.append(segment if segment in _ROUTE_WORDS and not owned else "{}")
        if segment in _REST_IS_VALUE_WORDS and not owned:
            route += ["{}"] if index < len(segments) - 1 else []
            break
    method = method or ("POST" if has_body else "GET")
    return f"{token} {method} {'/'.join(route)}{suffix}"


def gh_call_counts() -> dict[str, int]:
    """This process's gh invocations so far, by `gh_call_kind`."""
    return dict(_gh_call_counts)


def reset_gh_call_counts() -> None:
    _gh_call_counts.clear()


def gh_call_summary() -> str | None:
    """One line for the job log, or None when this process made no gh call."""
    if not _gh_call_counts:
        return None
    payload = {
        "unit": "gh invocations",
        "script": os.path.basename(sys.argv[0]) if sys.argv else "",
        "total": sum(_gh_call_counts.values()),
        "calls": dict(sorted(_gh_call_counts.items())),
    }
    return f"{GH_CALLS_PREFIX} {json.dumps(payload, sort_keys=True)}"


def _emit_gh_call_summary() -> None:
    line = gh_call_summary()
    if line is not None:
        print(line, file=sys.stderr, flush=True)


atexit.register(_emit_gh_call_summary)


def _run_gh(
    args: list[str],
    *,
    timeout_seconds: float | None,
    check: bool,
    env_overrides: Mapping[str, str] | None = None,
    binary: bool = False,
) -> subprocess.CompletedProcess[Any]:
    """The one gh invocation seam; `None` means the process-wide default timeout.
    `env_overrides` layers onto the environment for this call only, such as a
    `GH_TOKEN` other than the process's; `binary` keeps stdout as bytes. Every
    call is counted before it runs, so a failed or timed-out call is counted
    too, and the process prints the counts to stderr on exit
    (`gh_call_summary`)."""
    kind = gh_call_kind(args, env_overrides)
    _gh_call_counts[kind] = _gh_call_counts.get(kind, 0) + 1
    token = None if binary else _api_budget_token(args, env_overrides)
    proc = run_command(
        ["gh", "api", "-i", *args[1:]] if token else ["gh", *args],
        allowed_executables=("gh",),
        timeout_seconds=(
            timeout_seconds if timeout_seconds is not None else _default_timeout_seconds
        ),
        check=check and not token,
        env_overrides=env_overrides,
        binary=binary,
    )
    if token:
        proc.stdout = _api_budget_read(proc.stdout, token)
        if check and proc.returncode != 0:
            detail = proc.stderr.strip() or proc.stdout.strip()
            raise RuntimeError(f"{' '.join(['gh', *args])} failed: {detail}")
    return proc


# Rate-limit readings for the job-end api-budget notice
# (.github/actions/log-api-budget/api-budget.bash holds the line shape and the
# notice). Only in a job that names the token: API_BUDGET_TOKEN for a call on
# the process's own GH_TOKEN, API_BUDGET_OVERRIDE_TOKEN for one that carries
# its own. Such an `api` call runs with -i; its leading header block becomes one
# reading line in $RUNNER_TEMP/api-budget/<token> and is dropped from stdout,
# so the caller sees the output it would have without -i.
# --paginate prints a header block per page, which could not be told from
# body text that looks like one, so such a call runs as it is.
_API_BUDGET_SKIP_FLAGS = frozenset(
    {"-i", "--include", "--silent", "--slurp", "--paginate"}
)
_API_BUDGET_NAME = re.compile(r"[a-z][a-z0-9-]{0,39}")
_API_BUDGET_STATUS = re.compile(r"HTTP/[0-9.]+ ([0-9]{3})(?:\s|$)")
_API_BUDGET_VALUES = {
    "limit": re.compile(r"[0-9]+"),
    "remaining": re.compile(r"[0-9]+"),
    "used": re.compile(r"[0-9]+"),
    "reset": re.compile(r"[0-9]+"),
    "resource": re.compile(r"[a-z_]+"),
}


def _api_budget_token(
    args: list[str], env_overrides: Mapping[str, str] | None
) -> str | None:
    if not args or args[0] != "api" or _API_BUDGET_SKIP_FLAGS.intersection(args):
        return None
    own = bool(env_overrides and "GH_TOKEN" in env_overrides)
    name = os.environ.get(
        "API_BUDGET_OVERRIDE_TOKEN" if own else "API_BUDGET_TOKEN", ""
    )
    if not os.environ.get("RUNNER_TEMP") or not _API_BUDGET_NAME.fullmatch(name):
        return None
    return name


def _api_budget_read(stdout: str, token: str) -> str:
    """`gh api -i` output without its leading header block, which is appended
    as a reading. Only the block at the very start is headers: body text that
    looks like a status line stays body. Never raises: a reading that cannot be
    written is dropped."""
    lines = stdout.splitlines(keepends=True)
    match = _API_BUDGET_STATUS.match(lines[0].rstrip("\r\n")) if lines else None
    if match is None:
        return stdout
    headers: dict[str, str] = {}
    offset = len(lines[0])
    for line in lines[1:]:
        offset += len(line)
        bare = line.rstrip("\r\n")
        if bare == "":
            break
        name, _, value = bare.partition(":")
        key = name.strip().lower()
        if key.startswith("x-ratelimit-"):
            headers[key.removeprefix("x-ratelimit-")] = value.strip()
    try:
        path = os.path.join(os.environ["RUNNER_TEMP"], "api-budget")
        os.makedirs(path, exist_ok=True)
        with open(os.path.join(path, token), "a", encoding="utf-8") as handle:
            handle.write(_api_budget_line(match.group(1), headers))
    except OSError:
        pass
    return stdout[offset:]


def _api_budget_line(status: str, headers: Mapping[str, str]) -> str:
    values = [
        headers[key] if pattern.fullmatch(headers.get(key, "")) else "na"
        for key, pattern in _API_BUDGET_VALUES.items()
    ]
    return f"{status} {' '.join(values)}\n"


def run_gh(args: list[str], *, timeout_seconds: float | None = None) -> str:
    """Run a gh command, raising on timeout or nonzero exit; returns stdout."""
    return _run_gh(args, timeout_seconds=timeout_seconds, check=True).stdout


@overload
def gh_capture(
    args: list[str],
    *,
    timeout_seconds: float | None = ...,
    env_overrides: Mapping[str, str] | None = ...,
    binary: Literal[False] = ...,
) -> subprocess.CompletedProcess[str]: ...


@overload
def gh_capture(
    args: list[str],
    *,
    timeout_seconds: float | None = ...,
    env_overrides: Mapping[str, str] | None = ...,
    binary: Literal[True],
) -> subprocess.CompletedProcess[Any]: ...


def gh_capture(
    args: list[str],
    *,
    timeout_seconds: float | None = None,
    env_overrides: Mapping[str, str] | None = None,
    binary: bool = False,
) -> subprocess.CompletedProcess[Any]:
    """Run a gh command capturing stdout/stderr/returncode without raising on
    nonzero exit -- for callers that inspect the returncode themselves.
    `binary` keeps stdout as bytes."""
    return _run_gh(
        args,
        timeout_seconds=timeout_seconds,
        check=False,
        env_overrides=env_overrides,
        binary=binary,
    )


def gh_json(args: list[str], env_overrides: Mapping[str, str] | None = None) -> Any:
    text = _run_gh(
        args, timeout_seconds=None, check=True, env_overrides=env_overrides
    ).stdout
    return json.loads(text) if text.strip() else None


# `gh` reports the HTTP status in its own stderr message, e.g.
# `gh: Forbidden (HTTP 403)` (verified against gh 2.95.0). The exit code alone is
# 1 for every failure, so this is the only signal separating "the API answered
# no" from "the call never landed".
GH_HTTP_STATUS_RE = re.compile(r"\(HTTP (\d{3})\)")
# Sandboxed sessions (Claude Code on the web and remote execution) route GitHub
# through a proxy that refuses GraphQL requests with HTTP 403, whatever the
# credential. The refusal reads like an expired token or a missing scope and is
# neither: re-authenticating never clears it, and the only remedy is to source
# the same fact over REST. The marker is the casefolded GraphQL refusal wording
# from the section below, matched with or without its leading "GitHub"; its repository-scope refusal is a different failure
# and deliberately not a marker.
#   Pointer: <https://code.claude.com/docs/en/cloud-environments#github-proxy>
#   As-of: 2026-10-11.
#   Recheck trigger: that section stops rejecting GraphQL outright, or changes
#   the refusal's message prefix.
GRAPHQL_UNAVAILABLE_MARKERS = ("graphql is not available from claude code sessions",)


class GraphQLUnavailableError(RuntimeError):
    """GitHub's GraphQL API is not served to this session.

    Distinct from a GraphQL call that failed on its merits: the operation was
    never dispatched, so nothing about the pull request was learned or refuted.
    Callers either re-source the same fact over REST or fail closed; none may
    read this as a negative answer.
    """


def gh_http_status(text: str) -> int | None:
    """The HTTP status `gh` reported in a failure message, or None if it named none.

    The single parse of that string: `babysit_resolve_thread.gh_http_status`
    reads it off a `CompletedProcess` through here, while the text arrives here
    inside the `RuntimeError` `run_command` raises, which embeds stderr. None
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


def gh_rate_limited(text: str) -> bool:
    """Whether a `gh` failure message reports a rate limit: HTTP 429, or a 403
    whose message names one ("API rate limit exceeded", "secondary rate
    limit"). Any other 403 is a refusal, not a limit."""
    status = gh_http_status(text)
    return status == 429 or (status == 403 and "rate limit" in text.casefold())


def is_graphql_unavailable(failure: BaseException | str) -> bool:
    """Whether a failed GraphQL-backed `gh` call was refused the API itself.

    Two signals, either sufficient: a refusal wording from
    `GRAPHQL_UNAVAILABLE_MARKERS`, and a PARSED 403 status. Applied ONLY to
    GraphQL-backed calls, where both readings lead somewhere safe -- a REST
    re-source that either answers or fails loudly on its own, or a
    fail-closed verdict.

    Neither signal may be a bare substring scan of the failure text. That text
    is `run_command`'s, which embeds the whole argv, and every GraphQL call
    here passes the PR number as `-F n=<number>`: a scan for "403" reports the
    session refusal for any failure whatsoever on PR #403, including a timeout,
    which would substitute REST for a call that never reached GitHub. Only the
    status `gh` itself reported, and the refusal wording, name the condition.
    The status regex is case-sensitive on `(HTTP nnn)`, so it reads the
    original text while the marker match casefolds its own copy.
    """
    text = str(failure) or ""
    if any(marker in text.casefold() for marker in GRAPHQL_UNAVAILABLE_MARKERS):
        return True
    return gh_http_status(text) == 403


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


def rest_list_repos_for_owner(owner: str) -> list[str]:
    """`gh repo list` rebuilt from REST, for a session whose GraphQL calls are refused.

    `gh repo list --json` is a GraphQL `RepositoryList` query, so it 403s
    alongside `gh pr view` and takes owner-mode discovery with it. REST spells
    the same listing two ways and nothing upstream knows which kind of account
    an owner is, so the organization endpoint is tried first and its 404 -- the
    answer for a user account -- falls through to the user endpoint. Any other
    failure is re-raised: a listing that failed for another reason must not
    read as an owner with no repositories.

    Pagination walks every page, so unlike the GraphQL path there is no result
    cap to detect and no truncation to warn about.
    """
    if not GITHUB_OWNER_RE.fullmatch(owner):
        raise ValueError(f"Expected a GitHub owner, got: {owner}")
    try:
        rows = fetch_paginated_api(
            f"orgs/{owner}/repos?per_page=100", f"{owner} repositories"
        )
    except RuntimeError as exc:
        if gh_http_status(str(exc)) != 404:
            raise
        rows = fetch_paginated_api(
            f"users/{owner}/repos?per_page=100", f"{owner} repositories"
        )
    repos: list[str] = []
    for row in rows:
        name = str(row.get("full_name") or "").strip().casefold()
        if name:
            repos.append(name)
    return repos


def list_repos_for_owner(owner: str) -> list[str]:
    try:
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
    except RuntimeError as exc:
        if not is_graphql_unavailable(exc):
            raise
        return rest_list_repos_for_owner(owner)
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


def rest_list_prs_for_repo(
    repo: str, per_repo_limit: int, author: str | None
) -> list[dict[str, Any]]:
    """`gh pr list --json` rebuilt from REST, in the shape discovery reads.

    `gh pr list --json` is a GraphQL `PullRequestList` query -- confirmed
    against a restricted session, which answers it with the proxy's GraphQL
    403 that takes out `gh pr view`. Queue discovery is the FIRST
    call in the fleet loop, so without this substitution the loop finds no PRs
    and every REST hydration path downstream is never reached.

    Only the two members discovery actually reads are rebuilt --
    `repository.nameWithOwner` and `number`. The rest of `RECONCILE_FIELDS`
    (`url`, `title`, `updatedAt`, `isDraft`) is read by nobody here: each PR is
    hydrated field for field by `view_pr`, which has its own REST path.

    `--author` filters server-side over GraphQL and `GET /pulls` has no author
    parameter, so the filter is applied here, and truncation to
    `per_repo_limit` happens after it -- keeping the caller's "result limit
    reached" warning meaning exactly what it means on the GraphQL path.
    """
    rows = fetch_paginated_api(
        f"repos/{repo}/pulls?state=open&per_page=100",
        f"{repo} open pull requests",
    )
    out: list[dict[str, Any]] = []
    for row in rows:
        number = row.get("number")
        if not isinstance(number, int):
            continue
        login = str(json_object(row.get("user")).get("login") or "")
        if author and login.casefold() != author.casefold():
            continue
        base_repo = str(
            json_object(json_object(row.get("base")).get("repo")).get("full_name")
            or repo
        )
        out.append({"number": number, "repository": {"nameWithOwner": base_repo}})
        if len(out) >= per_repo_limit:
            break
    return out


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
        if not is_graphql_unavailable(exc):
            errors.append(f"repository reconcile {repo}: {exc}")
            return
        try:
            rows = rest_list_prs_for_repo(repo, per_repo_limit, author)
        except RuntimeError as rest_exc:
            errors.append(f"repository reconcile {repo}: {rest_exc}")
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

    Which of the three underlying `gh` commands are GraphQL matters here,
    because discovery runs before any hydration: a queue that cannot be built
    never reaches the REST substitutions downstream. `gh repo list` and
    `gh pr list --json` are GraphQL (`RepositoryList`, `PullRequestList`) and
    each has a REST substitute (`rest_list_repos_for_owner`,
    `rest_list_prs_for_repo`) wired in behind `is_graphql_unavailable`.
    `gh search prs` is NOT: it calls the REST search API (`GET /search/issues`)
    and needs no substitute, so leave it alone.
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
    read in this engine to fail where the session's GitHub proxy refuses
    GraphQL. Returns the field bundle plus whether it came from GraphQL; a REST
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


_archived_by_repo: dict[str, bool] = {}


def repository_is_archived(repo: str) -> bool:
    """Whether the repository is archived, over GraphQL or REST.

    `gh repo view --json` is GraphQL-backed and 403s alongside `gh pr view`;
    `GET /repos/{owner}/{repo}` reports the same fact as `.archived`. The
    answer is kept per process, keyed by the casefolded repository, so a
    snapshot of N pull requests in one repository reads it once; a failed
    read is not kept, and the next lookup reads again.
    """
    key = repo.casefold()
    if key not in _archived_by_repo:
        _archived_by_repo[key] = _read_repository_archived(repo)
    return _archived_by_repo[key]


def reset_repository_archived_cache() -> None:
    _archived_by_repo.clear()


def _read_repository_archived(repo: str) -> bool:
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
    merge_state = str(data.get("mergeStateStatus") or "").upper()
    if merge_state in BASE_COMPARE_MERGE_STATES:
        base_ref = str(data.get("baseRefName") or "")
        compare = fetch_base_compare(repo, base_ref, str(data.get("headRefOid") or ""))
        data["_base_compare"] = compare
        # Only a mergeable head behind its base pays the rules read: BLOCKED
        # keeps its queue-blind fallback, and an up-to-date head needs no answer.
        if merge_state != "BLOCKED" and compare_shows_behind(compare):
            data["_base_merge_queue"] = base_requires_merge_queue(repo, base_ref)
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
    permission gap) the name is left empty, which is the pre-existing behavior
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
    # An object endpoint: each page is `{total_count, check_runs: [...]}`, so
    # the items live under `check_runs` rather than being the page itself.
    for run in fetch_paginated_api(
        f"repos/{repo}/commits/{head_sha}/check-runs?per_page=100",
        f"{repo}@{head_sha} check runs",
        items_key="check_runs",
    ):
        suite_id = json_object(run.get("check_suite")).get("id")
        rollup.append(
            {
                "__typename": "CheckRun",
                "databaseId": run.get("id"),
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
        "body": str(pull.get("body") or ""),
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


def fetch_base_compare(
    repo: str,
    base_ref: str,
    head_sha: str,
    *,
    run_json: Callable[[list[str]], Any] | None = None,
) -> dict[str, Any] | None:
    """Best-effort divergence check for a PR head against the LIVE base tip.

    `mergeStateStatus` hides a behind head in two shapes. It is single-valued:
    when a PR is both genuinely behind its base AND blocked by another gate
    (failing required checks, missing review, ...), GitHub reports BLOCKED and
    the BEHIND signal is lost -- observed live, not documented. And BEHIND is
    reported only where the base requires branches to be up to date: loose
    required checks let a behind head merge, so it reports CLEAN
    (`reference/freshness.md` carries the source record). This recovers the
    signal from GitHub's own compare endpoint for both.

    `run_json` lets the merge gate keep its own gh seam, as `view_pr_fields`.

    Compares against the base ref NAME, never the PR's cached `baseRefOid`:
    that field lags once the base branch advances past the PR's last sync
    (verified empirically -- a real PR's `baseRefOid` reported `ahead_by=0`
    against its own stale value while the live base branch tip reported
    `behind_by=11`, `status=diverged`, for the identical head commit). Only a
    ref NAME resolves to the live tip at query time.

    Best-effort: any error returns None. The snapshot then falls back to
    `not_reported_behind` -- identical to the no-fallback behavior, so a hiccup
    never fails the whole snapshot for that PR and never grants refresh
    eligibility on uncertain data -- and the merge gate holds the PR instead.
    """
    if not base_ref or not re.fullmatch(r"[0-9a-fA-F]{7,40}", head_sha):
        return None
    runner = gh_json if run_json is None else run_json
    try:
        data = runner(
            ["api", f"repos/{repo}/compare/{quote(base_ref, safe='')}...{head_sha}"]
        )
    except (RuntimeError, json.JSONDecodeError):
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


def compare_shows_behind(compare: Any) -> bool:
    """Whether a `fetch_base_compare` result proves outstanding base commits."""
    return (
        is_json_object(compare)
        and compare.get("status") in {"behind", "diverged"}
        and isinstance(compare.get("behind_by"), int)
        and compare["behind_by"] > 0
    )


def base_requires_merge_queue(repo: str, base_ref: str) -> bool | None:
    """Whether a ruleset requires a merge queue on the base branch.

    A queue tests the PR against the latest base itself, so a behind head on a
    queue base needs no refresh (`reference/freshness.md` carries the source
    record). An unreadable answer is None, not False: the refresh disarms
    auto-merge and its push reruns CI and the AI reviews, so a transient read
    failure must not start one on a queue base. The head reads not behind for
    that cycle and the next snapshot reads the rules again.
    """
    try:
        rules = gh_json(
            ["api", f"repos/{repo}/rules/branches/{quote(base_ref, safe='')}"]
        )
    except (RuntimeError, json.JSONDecodeError):
        return None
    if not is_json_array(rules):
        return None
    return any(
        is_json_object(rule) and rule.get("type") == "merge_queue"
        for rule in json_array(rules)
    )


def flatten_paginated_items(
    value: Any, label: str, *, items_key: str | None = None
) -> list[dict[str, Any]]:
    """Flatten `gh api --paginate --slurp` output and reject unknown shapes.

    `--slurp` collects one entry per page and each entry keeps the endpoint's
    own shape: an ARRAY endpoint (`/pulls`, `/issues/{n}/comments`) yields an
    array per page, and an OBJECT endpoint yields an object per page. Most of
    this module's endpoints are the first kind, which the default handles.

    `items_key` names the member carrying the items on the second kind. It is
    required there, because an object page is indistinguishable from a single
    item by shape alone: without it, the check-runs payload
    `{total_count, check_runs: [...]}` is returned AS a check run, one per
    page, each with no name, no status and no conclusion, and every real check
    run on the commit disappears behind it.
    """
    if items_key is not None:
        pages = value if is_json_array(value) else [value]
        items: list[Any] = []
        for page in pages:
            if not is_json_object(page) or not is_json_array(page.get(items_key)):
                raise RuntimeError(f"Unexpected paginated response for {label}")
            items.extend(page[items_key])
        if not all(is_json_object(item) for item in items):
            raise RuntimeError(f"Unexpected paginated response items for {label}")
        return items
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


# A filtered workflow-run listing returns at most this many runs per search:
# https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-workflow
# (as of 2026-10-23; recheck when that page's result limit changes).
RUN_SEARCH_CAP = 1000


def run_search_capped(payload: Any, items: list[dict[str, Any]]) -> int | None:
    """The listing's `total_count` when a paginated run listing reached
    RUN_SEARCH_CAP, by that count or by the items its pages carried; None
    below it. A listing at the cap may be missing runs, so it is never a
    complete read."""
    pages = payload if is_json_array(payload) else [payload]
    total = max(
        (
            p["total_count"]
            for p in pages
            if is_json_object(p) and isinstance(p.get("total_count"), int)
        ),
        default=0,
    )
    return total if max(total, len(items)) >= RUN_SEARCH_CAP else None


def fetch_paginated_api(
    endpoint: str,
    label: str,
    *,
    items_key: str | None = None,
    env_overrides: Mapping[str, str] | None = None,
) -> list[dict[str, Any]]:
    args = ["api", endpoint, "--paginate", "--slurp"]
    data = gh_json(args, env_overrides) if env_overrides else gh_json(args)
    return flatten_paginated_items(data, label, items_key=items_key)


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


# One candidate's reads of a pull request's commits, keyed by (repo, number,
# head SHA): the commit rows and the record's commit count. None outside
# `candidate_reads`, so nothing is shared beyond one candidate's gate process.
_CANDIDATE_COMMITS: dict[tuple[str, int, str], list[dict[str, Any]]] | None = None
_CANDIDATE_TOTALS: dict[tuple[str, int, str], int] | None = None


@contextlib.contextmanager
def candidate_reads() -> Iterator[None]:
    """Within this scope a pull request's commits are read once per head."""
    global _CANDIDATE_COMMITS, _CANDIDATE_TOTALS
    saved = _CANDIDATE_COMMITS, _CANDIDATE_TOTALS
    _CANDIDATE_COMMITS, _CANDIDATE_TOTALS = {}, {}
    try:
        yield
    finally:
        _CANDIDATE_COMMITS, _CANDIDATE_TOTALS = saved


def _candidate_key(repo: str, number: int, head: Any) -> tuple[str, int, str]:
    return repo.casefold(), number, str(head or "")


def pull_request_commits_once(
    repo: str, number: int, head: Any, read: Callable[[], list[dict[str, Any]]]
) -> list[dict[str, Any]]:
    """`read()`'s commit rows, or an earlier read's for the same head in this
    `candidate_reads` scope. Kept only when the list ends at `head`, so a list
    read while the head moved, or cut at the API's cap, is read again."""
    if _CANDIDATE_COMMITS is None or not head:
        return read()
    key = _candidate_key(repo, number, head)
    rows = _CANDIDATE_COMMITS.get(key)
    if rows is None:
        rows = read()
        if rows and rows[-1].get("sha") == head:
            _CANDIDATE_COMMITS[key] = rows
    return list(rows)


def record_pull_request_total(repo: str, number: int, head: Any, total: Any) -> None:
    """Keep a pull request record's commit count for its head in this
    `candidate_reads` scope."""
    if _CANDIDATE_TOTALS is None or not head or isinstance(total, bool):
        return
    if isinstance(total, int):
        _CANDIDATE_TOTALS[_candidate_key(repo, number, head)] = total


def fetch_pull_request_commits(
    repo: str, number: int, head: str | None = None
) -> list[dict[str, Any]]:
    """Every commit on the PR with its signature-verification verdict.

    Reads `.commit.verification` per commit -- `verified` plus GitHub's
    `reason` string (`valid`, `unsigned`, `no_user`, `unknown_key`, ...). A row
    whose verification block is missing is reported unverified with reason
    `unreadable` rather than skipped: the caller enforcing a signature rule may
    only ever over-report.

    GitHub's `GET /repos/{owner}/{repo}/pulls/{n}/commits` endpoint returns at
    most **250** commits regardless of pagination; when the PR carries more, this
    raises `RuntimeError` so callers fail closed rather than under-report.
    `head`, the expected head SHA, lets a `candidate_reads` scope reuse the
    rows and the record's count already read for that head.
    """
    rows = pull_request_commits_once(
        repo,
        number,
        head,
        lambda: fetch_paginated_api(
            f"repos/{repo}/pulls/{number}/commits?per_page=100",
            f"{repo}#{number} commits",
        ),
    )
    # The record's count is for `head`; rows that do not end there were read
    # after the head moved, so they need a count read alongside them.
    reported_total = None
    if rows and rows[-1].get("sha") == head:
        reported_total = (_CANDIDATE_TOTALS or {}).get(
            _candidate_key(repo, number, head)
        )
    if reported_total is None:
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

    When the bundle already came from REST (`_graphql_available` False), its
    `reviews` list IS this function's output: `rest_view_pr` builds it with the
    same `fetch_pull_request_reviews` call, to derive `reviewDecision`. Fetching
    it again would repeat an identical paginated request per PR per pass, so
    the drop of `latestReviews` still runs and the refetch does not.
    """
    if pr.get("_graphql_available") is False and is_json_array(pr.get("reviews")):
        pr.pop("latestReviews", None)
        return
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

    Each thread record carries: `id`, `isResolved`, `isOutdated`, `resolvedBy`
    ({__typename login}, or None when open or the resolver is unknown),
    `originalStartLine` and `originalLine` (the commented range), `comments`
    (each with author{__typename login}, body, path, url, createdAt, updatedAt,
    databaseId, diffHunk, originalCommit{oid}), `comments_total_count`, and `comments_truncated`. Resolved
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
        "nodes{id isResolved isOutdated resolvedBy{__typename login} "
        "originalStartLine originalLine "
        f"comments(first:{comments_first})"
        "{totalCount pageInfo{hasNextPage} "
        "nodes{author{__typename login} body path url createdAt updatedAt databaseId "
        "diffHunk originalCommit{oid}}}}}}}}"
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
                or not (
                    thread.get("resolvedBy") is None
                    or is_json_object(thread["resolvedBy"])
                )
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
                "resolvedBy": thread.get("resolvedBy"),
                "originalStartLine": thread.get("originalStartLine"),
                "originalLine": thread.get("originalLine"),
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


def collect_lane_runs(
    repo: str,
    number: int,
    head_ref: str,
    lanes: Iterable[tuple[str, str]],
    created_at: str = "",
    env_overrides: Mapping[str, str] | None = None,
) -> list[dict[str, Any]]:
    """The `runs` input of `babysit_review_evidence.bind()` for one pull request.

    `lanes` gives each lane's (caller workflow path, lane job name suffix).
    Each workflow's `pull_request` runs are listed by `head_ref` with no
    `head_sha` filter and kept when their `pull_requests` name `number`, so
    earlier heads' reviews are included. `created_at`, the pull request's
    creation time, bounds the listing to runs created since: GitHub labels a
    reused branch's older runs with whichever pull request is open on it now,
    so without the bound a long-lived branch reads every earlier pull
    request's runs. A value that is not a UTC timestamp leaves it unbounded. Each kept run's attempt count comes
    from a fresh `GET actions/runs/{id}` taken after the listing, and that
    response stands in for its latest attempt, so only earlier attempts are
    read from `attempts/{n}`; each attempt
    carries its jobs, and each lane job its check run's annotations. Any read
    failure, a deleted or expired run included, raises `RuntimeError`, which
    the caller turns into unbound evidence; so does a listing that reached
    RUN_SEARCH_CAP, which may be missing runs. `env_overrides` applies to
    every read, all of them GETs.
    """
    env = env_overrides

    def read(path: str) -> Any:
        return gh_json(["api", path], env) if env else gh_json(["api", path])

    def read_all(path: str) -> Any:
        args = ["api", path, "--paginate", "--slurp"]
        return gh_json(args, env) if env else gh_json(args)

    def pages(endpoint: str, label: str, items_key: str | None = None) -> list[Any]:
        return fetch_paginated_api(
            endpoint, label, items_key=items_key, env_overrides=env
        )

    runs: list[dict[str, Any]] = []
    since = (
        f"&created={quote('>=' + created_at, safe='')}"
        if re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", created_at)
        else ""
    )
    for path, job_suffix in lanes:
        workflow = quote(path.rsplit("/", 1)[-1], safe="")
        payload = read_all(
            f"repos/{repo}/actions/workflows/{workflow}/runs"
            f"?branch={quote(head_ref, safe='')}&event=pull_request{since}"
            "&per_page=100"
        )
        listing = flatten_paginated_items(
            payload, f"{workflow} runs", items_key="workflow_runs"
        )
        total = run_search_capped(payload, listing)
        if total is not None:
            raise RuntimeError(
                f"{workflow} runs: total_count {total}, {len(listing)} returned, "
                f"at the {RUN_SEARCH_CAP}-run search cap"
            )
        for item in listing:
            if not any(
                json_object(pr).get("number") == number
                for pr in json_array(item.get("pull_requests"))
            ):
                continue
            run_id = item.get("id")
            if not isinstance(run_id, int) or isinstance(run_id, bool):
                raise RuntimeError(f"{workflow} run without an id")
            latest = json_object(read(f"repos/{repo}/actions/runs/{run_id}"))
            count = latest.get("run_attempt")
            if not isinstance(count, int) or isinstance(count, bool) or count < 1:
                raise RuntimeError(f"run {run_id}: no attempt count")
            attempts = []
            for n in range(1, count + 1):
                base = f"repos/{repo}/actions/runs/{run_id}/attempts/{n}"
                # The run object is its latest attempt: the two responses
                # differ only in `jobs_url` and `logs_url`, which nothing reads.
                attempt = latest if n == count else json_object(read(base))
                jobs = pages(f"{base}/jobs?per_page=100", f"run {run_id} jobs", "jobs")
                for job in jobs:
                    if str(job.get("name") or "").rsplit(" / ", 1)[-1] == job_suffix:
                        job["annotations"] = pages(
                            f"repos/{repo}/check-runs/{job.get('id')}/annotations"
                            "?per_page=100",
                            f"job {job.get('id')} annotations",
                        )
                attempts.append({**attempt, "jobs": jobs})
            runs.append({**item, "attempts": attempts})
    return runs


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

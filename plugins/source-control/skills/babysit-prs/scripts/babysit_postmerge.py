#!/usr/bin/env python3
"""Post-merge check for the unattended merge path of the babysit merge gate.

`check()` derives every auto-merge since a floor from GitHub and judges it on
four signals: the scheduled full `pr-require-checks` run, the full run the
agent identity dispatches after a merge, the silent-revert canary, and a
read-back that the merged head equals the SHA the wrapper pinned. Nothing is
stored on the host, so every host reaches the same verdict.

An auto-merge is any merge whose `AddedToMergeQueueEvent` `actor` or
`enqueuer` is null or not a human, or that bypassed the queue with a null or
non-human `mergedBy` (`babysit_merge_policy.derive_auto_merge`, which
`in_flight` shares); a queue-bypassing merge by a human is reported as the
warning `unqueued-merge`. It is verified when a green
dispatch run by the identity on a SHA containing the merge, a green canary
run on such a SHA, and a matching read-back all exist, and no red full run or
canary run counted against it first. Only an enqueue by the identity has a
pinned SHA to read back; any other enqueue verifies on the dispatch and canary
runs alone. A red full run is attributed after one `rerun-failed-jobs` the
wrapper triggers: red again is a failure, green is a flake.

`remediate()` acts on failures in order: dequeue the identity's merge-queue
entries, file or comment on the demotion issue, then record the telemetry
count. `attribute()` triggers the one re-run, and `dispatch_full_run()` the
dispatch. The CLI is read-only unless `--remediate` is given; with it, a cycle
also dispatches one full run on the branch tip whenever an unverified
auto-merge has no identity dispatch run covering it, so a merge nobody
dispatched for (a sync App's own enqueue) cannot hold the lane forever.

Exit codes: 0 no failure, 1 a failure, 2 usage or a refused identity (not a
dedicated App login, or `--remediate` under another acting login), 3
unreadable, 4 a write failed.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Callable, Collection, Iterable
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any
from urllib.parse import quote

import babysit_merge_policy as policy
from babysit_gh import (
    flatten_paginated_items,
    gh_capture,
    gh_http_status,
    is_owner_repo_pair,
)
from babysit_util import is_json_array, is_json_object, json_array, json_object

FULL_RUN_WORKFLOW = "pr-require-checks.yml"
CANARY_WORKFLOW = "post-merge-detect-silent-revert.yml"
DISPATCH_DEADLINE = timedelta(hours=6)
DEMOTION_FILERS = ("github-actions[bot]",)
DEFAULT_ROLE_LABEL = "needs-human"
TRACKER_CONFIG = ".work-item-tracker.json"
# The follow-up note on an existing record; the demotion-alert workflow writes
# the same prefix, so either filer's note is a sighting to the other.
FAILURE_NOTE = "The post-merge check found this failure again: "
MERGED_PAGE_SIZE = 100
MERGED_PAGE_LIMIT = 10

SIGNAL_SCHEDULE = "schedule"
SIGNAL_DISPATCH = "dispatch"
SIGNAL_CANARY = "canary"
SIGNAL_READ_BACK = "read-back"

GREEN, FLAKE, RED, RERUN, PENDING = "green", "flake", "red", "rerun", "pending"

IsHuman = Callable[[Any], bool]


class PostMergeReadError(RuntimeError):
    """A GitHub read the verdict depends on failed or returned an unknown shape."""


class PostMergeWriteError(RuntimeError):
    """A remediation write failed."""


# One type and one derivation with `babysit_merge_policy.in_flight`, so both
# judge the same merges and `PostMergeVerdict.is_verified` serves as its
# `verified` callable.
AutoMerge = policy.AutoMerge


@dataclass(frozen=True)
class Failure:
    signal: str
    merge: AutoMerge
    run_url: str | None
    detail: str

    @property
    def marker(self) -> str:
        return demotion_marker(self.merge.merge_commit or "", self.signal)


@dataclass(frozen=True)
class Rerun:
    """A red full run waiting for the wrapper's one `rerun-failed-jobs`."""

    run_id: int
    url: str
    signal: str


@dataclass(frozen=True)
class MergeState:
    merge: AutoMerge
    verified: bool
    pending: tuple[str, ...]
    # An identity dispatch run, in any state, exists on a SHA containing it.
    dispatch_covered: bool


@dataclass(frozen=True)
class PostMergeVerdict:
    readable: bool
    reason: str | None = None
    merges: tuple[MergeState, ...] = ()
    failures: tuple[Failure, ...] = ()
    reruns: tuple[Rerun, ...] = ()
    flakes: tuple[str, ...] = ()
    warnings: tuple[str, ...] = ()
    # The branch judged: the caller's, or the repository's default branch.
    branch: str | None = None

    @property
    def ok(self) -> bool:
        return self.readable and not self.failures

    @property
    def needs_dispatch(self) -> bool:
        """An unverified auto-merge has no identity dispatch run covering it.
        One run on the branch tip covers every earlier merge."""
        return self.readable and any(
            not s.verified and not s.dispatch_covered for s in self.merges
        )

    def is_verified(self, merge: Any) -> bool:
        """Whether the auto-merge numbered like `merge` is verified; the
        `verified` callable for `in_flight`. Unknown or unreadable is False."""
        number = getattr(merge, "number", None)
        return self.ok and any(
            s.verified and s.merge.number == number for s in self.merges
        )

    def report(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "readable": self.readable,
            "reason": self.reason,
            "autoMerges": [
                {
                    "number": s.merge.number,
                    "url": s.merge.url,
                    "mergeCommit": s.merge.merge_commit,
                    "mergedAt": s.merge.merged_at,
                    "verified": s.verified,
                    "pending": list(s.pending),
                }
                for s in self.merges
            ],
            "failures": [
                {
                    "signal": f.signal,
                    "number": f.merge.number,
                    "mergeCommit": f.merge.merge_commit,
                    "run": f.run_url,
                    "detail": f.detail,
                }
                for f in self.failures
            ],
            "reruns": [
                {"runId": r.run_id, "url": r.url, "signal": r.signal}
                for r in self.reruns
            ],
            "flakes": list(self.flakes),
            "needsDispatch": self.needs_dispatch,
            "warnings": list(self.warnings),
            "branch": self.branch,
        }


def demotion_marker(sha: str, signal: str) -> str:
    return f"<!-- babysit-merge-demotion sha={sha} signal={signal} -->"


# --- GitHub access ------------------------------------------------------------------


def _split_repo(repo: str) -> tuple[str, str]:
    owner, _, name = repo.partition("/")
    if not is_owner_repo_pair(owner, name):
        raise PostMergeReadError(f"not an owner/repo pair: {repo!r}")
    return owner, name


def _login_key(login: Any) -> str:
    """A REST login (an App is `app[bot]`), compared exactly: a User may own the
    bare slug `app`, so the suffix is never stripped."""
    return str(login or "").strip().casefold()


_actor_key = policy.actor_key


def _time(value: Any) -> datetime:
    try:
        parsed = datetime.fromisoformat(str(value))
    except ValueError as exc:
        raise PostMergeReadError(f"not a timestamp: {value!r}") from exc
    if parsed.utcoffset() is None:
        raise PostMergeReadError(f"a timestamp without an offset: {value!r}")
    return parsed


def _call(args: list[str], label: str, error: type[RuntimeError]) -> Any:
    try:
        proc = gh_capture(args)
    except (RuntimeError, ValueError, OSError) as exc:
        raise error(f"{label}: {exc}") from exc
    if proc.returncode != 0:
        raise error(f"{label}: {(proc.stderr or '').strip() or proc.returncode}")
    try:
        return json.loads(proc.stdout) if proc.stdout.strip() else None
    except ValueError as exc:
        raise error(f"{label}: {exc}") from exc


def _read(args: list[str], label: str) -> Any:
    return _call(args, label, PostMergeReadError)


def _write(args: list[str], label: str) -> Any:
    return _call(args, label, PostMergeWriteError)


def _paginated(
    endpoint: str, label: str, items_key: str | None = None
) -> list[dict[str, Any]]:
    payload = _read(["api", endpoint, "--paginate", "--slurp"], label)
    try:
        return flatten_paginated_items(payload, label, items_key=items_key)
    except RuntimeError as exc:
        raise PostMergeReadError(str(exc)) from exc


def _graphql(
    query: str,
    label: str,
    error: type[RuntimeError] = PostMergeReadError,
    **variables: str | None,
) -> dict[str, Any]:
    args = ["api", "graphql", "-f", f"query={query}"]
    for name, value in variables.items():
        if value is not None:
            args += ["-f", f"{name}={value}"]
    payload = _call(args, label, error)
    if (
        not is_json_object(payload)
        or payload.get("errors")
        or not is_json_object(payload.get("data"))
    ):
        raise error(f"{label}: the response carried no data")
    return payload["data"]


MERGED_QUERY = (
    "query PostMergeMerged($o:String!,$r:String!,$b:String!,$c:String){"
    "repository(owner:$o,name:$r){pullRequests(baseRefName:$b,states:MERGED,"
    f"first:{MERGED_PAGE_SIZE},after:$c,orderBy:{{field:UPDATED_AT,direction:DESC}}){{"
    "pageInfo{hasNextPage endCursor} nodes{number url mergedAt updatedAt headRefOid "
    "mergedBy{__typename login} "
    "mergeCommit{oid} timelineItems(itemTypes:[ADDED_TO_MERGE_QUEUE_EVENT],last:1){nodes{"
    "... on AddedToMergeQueueEvent{createdAt actor{__typename login} enqueuer{__typename login}}}}}}}}"
)
QUEUE_QUERY = (
    "query PostMergeQueue($o:String!,$r:String!,$b:String!){repository(owner:$o,name:$r){"
    "mergeQueue(branch:$b){entries(first:100){totalCount nodes{"
    "enqueuer{__typename login} pullRequest{id number}}}}}}"
)
DEQUEUE_MUTATION = "mutation PostMergeDequeue($id:ID!){dequeuePullRequest(input:{id:$id}){clientMutationId}}"


def _default_branch(owner: str, name: str) -> str:
    """The repository's default branch; an unreadable one fails the read, so
    the check never judges a branch the repository does not merge into."""
    branch = json_object(_read(["api", f"repos/{owner}/{name}"], "repository")).get(
        "default_branch"
    )
    if not isinstance(branch, str) or not branch.strip():
        raise PostMergeReadError("repository: no default branch")
    return branch


def _merged_since(
    owner: str, name: str, branch: str, since: datetime
) -> list[dict[str, Any]]:
    """Pull requests merged into `branch` at or after `since`. A merge updates
    the PR, so reading newest-updated first can stop at the first PR last
    updated before the floor. A PR updated mid-read jumps to page 1 and can
    slip past the walk, so page 1 is read again afterwards: any merge there
    the walk missed makes the history unreadable."""
    found = _walk_merged(owner, name, branch, since)
    numbers = {pr.get("number") for pr in found}
    for pr in _merged_page(owner, name, branch, None)[0]:
        if _time(pr.get("updatedAt")) < since:
            break
        if _time(pr.get("mergedAt")) >= since and pr.get("number") not in numbers:
            raise PostMergeReadError(
                "merged pull requests: the history changed while it was read"
            )
    return found


def _merged_page(
    owner: str, name: str, branch: str, cursor: str | None
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    data = _graphql(
        MERGED_QUERY, "merged pull requests", o=owner, r=name, b=branch, c=cursor
    )
    page = json_object(json_object(data.get("repository")).get("pullRequests"))
    info = page.get("pageInfo")
    if not is_json_array(page.get("nodes")) or not is_json_object(info):
        raise PostMergeReadError("merged pull requests: no page")
    return [json_object(pr) for pr in page["nodes"]], info


def _walk_merged(
    owner: str, name: str, branch: str, since: datetime
) -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []
    cursor: str | None = None
    for _ in range(MERGED_PAGE_LIMIT):
        nodes, info = _merged_page(owner, name, branch, cursor)
        for pr in nodes:
            if _time(pr.get("updatedAt")) < since:
                return found
            if _time(pr.get("mergedAt")) >= since:
                found.append(pr)
        if info.get("hasNextPage") is False:
            return found
        cursor = info.get("endCursor")
        if (
            info.get("hasNextPage") is not True
            or not isinstance(cursor, str)
            or not cursor
        ):
            raise PostMergeReadError("merged pull requests: an unreadable next page")
    raise PostMergeReadError(
        "merged pull requests: the history is longer than the read limit"
    )


@dataclass(frozen=True)
class Run:
    id: int
    attempt: int
    status: str
    conclusion: str | None
    head_sha: str
    head_branch: str | None
    created_at: datetime
    url: str
    actor: str
    triggering_actor: str

    @classmethod
    def from_api(cls, payload: Any) -> Run:
        item = json_object(payload)
        run_id, attempt = item.get("id"), item.get("run_attempt")
        if (
            not isinstance(run_id, int)
            or not isinstance(attempt, int)
            or not isinstance(item.get("head_sha"), str)
        ):
            raise PostMergeReadError(
                f"workflow run: an unknown shape {str(payload)[:120]!r}"
            )
        return cls(
            id=run_id,
            attempt=attempt,
            status=str(item.get("status") or ""),
            conclusion=item.get("conclusion"),
            head_sha=item["head_sha"],
            head_branch=item.get("head_branch"),
            created_at=_time(item.get("created_at")),
            url=str(item.get("html_url") or ""),
            actor=_login_key(json_object(item.get("actor")).get("login")),
            triggering_actor=_login_key(
                json_object(item.get("triggering_actor")).get("login")
            ),
        )


def _runs(
    owner: str, name: str, workflow: str, event: str, branch: str, since: datetime
) -> list[Run]:
    created = quote(
        f">={since.astimezone(UTC).strftime('%Y-%m-%dT%H:%M:%SZ')}", safe=""
    )
    endpoint = (
        f"repos/{owner}/{name}/actions/workflows/{workflow}/runs"
        f"?event={event}&branch={quote(branch, safe='')}&created={created}&per_page=100"
    )
    runs = [
        Run.from_api(item)
        for item in _paginated(endpoint, f"{workflow} {event} runs", "workflow_runs")
    ]
    return [r for r in runs if r.created_at >= since and r.head_branch == branch]


def _attempt(owner: str, name: str, run_id: int, attempt: int) -> Run | None:
    args = ["api", f"repos/{owner}/{name}/actions/runs/{run_id}/attempts/{attempt}"]
    try:
        proc = gh_capture(args)
    except (RuntimeError, ValueError, OSError) as exc:
        raise PostMergeReadError(f"run {run_id} attempt {attempt}: {exc}") from exc
    if proc.returncode != 0:
        if gh_http_status(proc.stderr or "") == 404:
            return None
        raise PostMergeReadError(
            f"run {run_id} attempt {attempt}: {(proc.stderr or '').strip()}"
        )
    try:
        return Run.from_api(json.loads(proc.stdout))
    except ValueError as exc:
        raise PostMergeReadError(f"run {run_id} attempt {attempt}: {exc}") from exc


# --- Judging runs -------------------------------------------------------------------


@dataclass
class _Context:
    owner: str
    name: str
    identity: str
    contains_cache: dict[tuple[str, str], bool] = field(default_factory=dict)
    outcome_cache: dict[tuple[int, str], tuple[str, str]] = field(default_factory=dict)
    # Full runs whose red verdict came from the wrapper's re-run (attempt 2).
    red_on_rerun: set[int] = field(default_factory=set)

    def contains(self, ancestor: str, sha: str) -> bool:
        """Whether `sha` is `ancestor` or has it in its history."""
        key = (ancestor, sha)
        if key not in self.contains_cache:
            if ancestor == sha:
                self.contains_cache[key] = True
            else:
                compare = _read(
                    [
                        "api",
                        f"repos/{self.owner}/{self.name}/compare/{ancestor}...{sha}",
                    ],
                    f"compare {ancestor[:12]}...{sha[:12]}",
                )
                self.contains_cache[key] = json_object(compare).get("status") in (
                    "ahead",
                    "identical",
                )
        return self.contains_cache[key]

    def outcome(self, run: Run, *, attributable: bool) -> tuple[str, str]:
        """(state, detail). Attempt 1 decides; for a full run (`attributable`)
        a red attempt 1 waits for the wrapper's attempt 2, and any later attempt
        is ignored."""
        key = (run.id, "full" if attributable else "canary")
        if key not in self.outcome_cache:
            self.outcome_cache[key] = self._outcome(run, attributable)
        return self.outcome_cache[key]

    def _attempt(self, run: Run, n: int) -> Run | None:
        return run if run.attempt == n else _attempt(self.owner, self.name, run.id, n)

    def _outcome(self, run: Run, attributable: bool) -> tuple[str, str]:
        first = self._attempt(run, 1)
        if first is None:
            raise PostMergeReadError(f"run {run.id}: attempt 1 is missing")
        if first.status != "completed":
            return PENDING, "run-in-progress"
        if first.conclusion == "success":
            return GREEN, "attempt 1 success"
        if not attributable:
            return RED, f"attempt 1 {first.conclusion}"
        second = self._attempt(run, 2) if run.attempt >= 2 else None
        if second is None:
            return RERUN, f"attempt 1 {first.conclusion}; awaiting the wrapper's re-run"
        if second.triggering_actor != self.identity:
            return (
                RED,
                f"attempt 1 {first.conclusion}; attempt 2 not triggered by the agent identity",
            )
        if second.status != "completed":
            return PENDING, "re-run-in-progress"
        if second.conclusion == "success":
            return FLAKE, "attempt 1 failed, the wrapper's re-run passed"
        self.red_on_rerun.add(run.id)
        return RED, f"attempt 1 {first.conclusion}; re-run {second.conclusion}"

    def sighting(self, run: Run) -> str:
        """The failing attempt's URL, in the demotion workflow's form: a run's
        URL names no attempt, and a later failing attempt is a new sighting."""
        return f"{run.url}/attempts/{2 if run.id in self.red_on_rerun else 1}"


@dataclass
class _Tally:
    failures: list[Failure] = field(default_factory=list)
    reruns: dict[int, Rerun] = field(default_factory=dict)
    flakes: dict[str, None] = field(default_factory=dict)


def _judge(
    merge: AutoMerge,
    ctx: _Context,
    *,
    full_runs: list[tuple[str, Run]],
    canary_runs: list[Run],
    pinned: str | None,
    now: datetime,
    tally: _Tally,
) -> MergeState:
    pending: list[str] = []
    failures: list[Failure] = []
    if not merge.merge_commit or not merge.merged_at:
        # No dispatch can ever cover it, so it would hold the lane forever.
        raise PostMergeReadError(f"#{merge.number}: merge commit unknown")
    merged_at = _time(merge.merged_at)
    commit = merge.merge_commit

    def relevant(run: Run) -> bool:
        return run.created_at >= merged_at and ctx.contains(commit, run.head_sha)

    fulls = [(signal, run) for signal, run in full_runs if relevant(run)]
    canaries = [run for run in canary_runs if relevant(run)]
    own = [
        run
        for signal, run in fulls
        if signal == SIGNAL_DISPATCH and run.actor == ctx.identity
    ]
    green_dispatch = [
        r for r in own if ctx.outcome(r, attributable=True)[0] in (GREEN, FLAKE)
    ]
    green_canary = [
        r for r in canaries if ctx.outcome(r, attributable=False)[0] == GREEN
    ]

    if merge.by_identity and pinned is None:
        pending.append("read-back-unrecorded")
    elif merge.by_identity and pinned != merge.head_ref_oid:
        failures.append(
            Failure(
                SIGNAL_READ_BACK,
                merge,
                None,
                f"headRefOid {merge.head_ref_oid} is not the pinned {pinned}",
            )
        )

    verified_at = None
    if green_dispatch and green_canary:
        verified_at = max(
            min(r.created_at for r in green_dispatch),
            min(r.created_at for r in green_canary),
        )
    if not green_dispatch:
        pending.append("dispatch-run-pending")
    if not green_canary:
        pending.append("canary-run-pending")
    in_window = (
        (lambda run: run.created_at <= verified_at)
        if verified_at
        else (lambda run: True)
    )

    for signal, run in fulls:
        if not in_window(run):
            continue
        state, detail = ctx.outcome(run, attributable=True)
        if state == RED:
            failures.append(Failure(signal, merge, ctx.sighting(run), detail))
        elif state == RERUN:
            tally.reruns[run.id] = Rerun(run.id, run.url, signal)
            pending.append(f"attribution-pending:{run.id}")
        elif state == FLAKE:
            tally.flakes[run.url] = None
        elif state == PENDING:
            pending.append(f"{signal}-run-in-progress:{run.id}")
    for run in canaries:
        if in_window(run) and ctx.outcome(run, attributable=False)[0] == RED:
            failures.append(
                Failure(
                    SIGNAL_CANARY,
                    merge,
                    ctx.sighting(run),
                    ctx.outcome(run, attributable=False)[1],
                )
            )

    deadline = merged_at + DISPATCH_DEADLINE
    if not any(r.created_at <= deadline for r in own) and now > deadline:
        failures.append(
            Failure(
                SIGNAL_DISPATCH,
                merge,
                None,
                "no dispatch run by the agent identity within 6 h",
            )
        )

    tally.failures.extend(failures)
    verified = verified_at is not None and not failures and not pending
    return MergeState(merge, verified, tuple(pending), dispatch_covered=bool(own))


def check(
    repo: str,
    *,
    agent_identity: str | None,
    is_human: IsHuman,
    merged_since: datetime | None,
    now: datetime | None = None,
    pinned_sha: Callable[[AutoMerge], str | None] | None = None,
    branch: str | None = None,
) -> PostMergeVerdict:
    """Judge every auto-merge into `branch` since `merged_since`; with no
    `branch`, the repository's default branch, read once from the repos API.

    `is_human` is the Design's human test for one GraphQL actor (null included).
    `pinned_sha` returns the head SHA the wrapper pinned for a merge, or None when
    no record exists, which leaves the merge unverified without failing it. Any
    read failure makes the verdict unreadable, which is never ok."""
    if not agent_identity:
        return PostMergeVerdict(False, "agent-identity-unconfigured")
    if merged_since is None:
        return PostMergeVerdict(False, "merged-since-unset")
    if merged_since.utcoffset() is None:
        return PostMergeVerdict(False, "merged-since-not-timezone-aware")
    now = now or datetime.now(UTC)
    try:
        owner, name = _split_repo(repo)
        branch = branch or _default_branch(owner, name)
        merges: list[AutoMerge] = []
        warnings: list[str] = []
        identity = _login_key(agent_identity)
        for pr in _merged_since(owner, name, branch, merged_since):
            derived = policy.derive_auto_merge(pr, is_human, identity)
            if isinstance(derived, str):
                warnings.append(derived)
            elif derived is not None:
                merges.append(derived)
        merges.sort(key=lambda m: (str(m.merged_at), m.number))
        if not merges:
            return PostMergeVerdict(True, warnings=tuple(warnings), branch=branch)
        floor = (
            min(_time(m.merged_at) for m in merges if m.merged_at)
            if any(m.merged_at for m in merges)
            else merged_since
        )
        full_runs = [
            (SIGNAL_SCHEDULE, r)
            for r in _runs(owner, name, FULL_RUN_WORKFLOW, "schedule", branch, floor)
        ] + [
            (SIGNAL_DISPATCH, r)
            for r in _runs(
                owner, name, FULL_RUN_WORKFLOW, "workflow_dispatch", branch, floor
            )
        ]
        full_runs.sort(key=lambda item: item[1].created_at)
        canary_runs = sorted(
            _runs(owner, name, CANARY_WORKFLOW, "push", branch, floor),
            key=lambda r: r.created_at,
        )
        ctx = _Context(owner, name, identity)
        tally = _Tally()
        states = tuple(
            _judge(
                merge,
                ctx,
                full_runs=full_runs,
                canary_runs=canary_runs,
                pinned=pinned_sha(merge) if pinned_sha else None,
                now=now,
                tally=tally,
            )
            for merge in merges
        )
    except (PostMergeReadError, policy.PolicyReadError) as exc:
        return PostMergeVerdict(False, f"unreadable: {exc}")
    return PostMergeVerdict(
        True,
        merges=states,
        failures=tuple(tally.failures),
        reruns=tuple(tally.reruns.values()),
        flakes=tuple(tally.flakes),
        warnings=tuple(warnings),
        branch=branch,
    )


# --- Writes -------------------------------------------------------------------------


def dispatch_full_run(repo: str, *, ref: str) -> None:
    """Dispatch the full `pr-require-checks` run on `ref`; called only by
    `--remediate` when the verdict needs a dispatch. Without `--remediate` under
    the identity nobody dispatches, so each auto-merge fails at the deadline."""
    owner, name = _split_repo(repo)
    _write(
        [
            "api",
            "-X",
            "POST",
            f"repos/{owner}/{name}/actions/workflows/{FULL_RUN_WORKFLOW}/dispatches",
            "-f",
            f"ref={ref}",
        ],
        "dispatch the full run",
    )


def attribute(repo: str, verdict: PostMergeVerdict) -> list[int]:
    """Trigger the one `rerun-failed-jobs` on each red full run awaiting it."""
    owner, name = _split_repo(repo)
    for rerun in verdict.reruns:
        _write(
            [
                "api",
                "-X",
                "POST",
                f"repos/{owner}/{name}/actions/runs/{rerun.run_id}/rerun-failed-jobs",
            ],
            f"re-run {rerun.run_id}",
        )
    return [r.run_id for r in verdict.reruns]


def _role_label(owner: str, name: str) -> str:
    """The tracker's human-gated role label, or the default on any doubt."""
    try:
        config = _read(
            [
                "api",
                "-H",
                "Accept: application/vnd.github.raw+json",
                f"repos/{owner}/{name}/contents/{TRACKER_CONFIG}",
            ],
            TRACKER_CONFIG,
        )
    except PostMergeReadError:
        return DEFAULT_ROLE_LABEL
    label = json_object(
        json_object(json_object(config).get("config")).get("role_labels")
    ).get("human-gated")
    return (
        label.strip()
        if isinstance(label, str) and label.strip()
        else DEFAULT_ROLE_LABEL
    )


def _identity_entries(
    owner: str, name: str, branch: str, identity: str
) -> tuple[list[tuple[str, int]], int]:
    """The identity's entries (node id, PR number), and how many entries have
    an unknown enqueuer: those cannot be judged the identity's, so the caller
    dequeues the known ones and still reports the unknown ones as an error."""
    data = _graphql(QUEUE_QUERY, "merge queue", o=owner, r=name, b=branch)
    queue = json_object(json_object(data.get("repository")).get("mergeQueue"))
    entries = json_object(queue.get("entries"))
    nodes = [json_object(n) for n in json_array(entries.get("nodes"))]
    if entries.get("totalCount") != len(nodes):
        raise PostMergeReadError(
            "merge queue: the entries read are not the whole queue"
        )
    found = []
    unknown = 0
    for entry in nodes:
        enqueuer = _actor_key(entry.get("enqueuer"))
        if not enqueuer:
            unknown += 1
        elif enqueuer == _login_key(identity):
            pr = json_object(entry.get("pullRequest"))
            found.append((str(pr.get("id")), pr.get("number")))
    return found, unknown


def _demotion_issues(
    owner: str, name: str, filers: Iterable[str]
) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    for filer in dict.fromkeys(filers):
        endpoint = f"repos/{owner}/{name}/issues?state=all&creator={quote(filer, safe='')}&per_page=100"
        issues += [
            i
            for i in _paginated(endpoint, f"issues by {filer}")
            if "pull_request" not in i
        ]
    return issues


def _first_line(text: Any) -> str:
    return str(text or "").lstrip().split("\n", 1)[0].strip()


def _issue_body(failure: Failure) -> str:
    merge = failure.merge
    return "\n".join(
        [
            failure.marker,
            "",
            f"The post-merge check found a `{failure.signal}` failure after an unattended merge. The",
            "unattended merge path stays at rung off until a human closes this issue directly (not",
            "through a pull request's closing keyword).",
            "",
            f"- Pull request: {merge.url or f'#{merge.number}'}",
            f"- Merge commit: `{merge.merge_commit}`",
            f"- Failing run: {failure.run_url or 'none'}",
            f"- Detail: {failure.detail}",
            "",
            "To revert the merge, a human runs:",
            "",
            "```sh",
            f"git revert {merge.merge_commit}",
            "```",
        ]
    )


def _sighting(failure: Failure) -> str:
    return failure.run_url or failure.detail


def _body_line(failure: Failure) -> str:
    """The record body line naming the sighting, as `_issue_body` writes it."""
    if failure.run_url:
        return f"- Failing run: {failure.run_url}"
    return f"- Detail: {failure.detail}"


def _lines(text: Any) -> set[str]:
    return {line.rstrip() for line in str(text or "").split("\n")}


def _recorded(failure: Failure, record: dict[str, Any], notes: Iterable[Any]) -> bool:
    """Whether the record already names this sighting: its body line, or a
    filer's failure note, each matched as a whole line, so attempt 1 is not
    attempt 10. A "re-run passed" note never counts."""
    if _body_line(failure) in _lines(record.get("body")):
        return True
    note = f"{FAILURE_NOTE}{_sighting(failure)}"
    return any(note in _lines(body) for body in notes)


def remediate(
    repo: str,
    verdict: PostMergeVerdict,
    *,
    agent_identity: str,
    branch: str | None = None,
    label: str | None = None,
    record_telemetry: Callable[[int], None] | None = None,
) -> dict[str, Any]:
    """Act on the verdict's failures: dequeue every merge-queue entry the agent
    identity enqueued, then file one demotion issue per (signal, merge SHA) or
    comment on the existing one (reopening it first when closed and the sighting
    is new; only the filers' own comments count as a prior sighting), then
    record the number of new issues as
    `demotion_events`. Each step runs even when an earlier one failed; errors are
    listed in the report. No failure, no write."""
    report: dict[str, Any] = {
        "dequeued": [],
        "issues": [],
        "comments": [],
        "reopened": [],
        "telemetry": {"demotion_events": 0},
        "errors": [],
    }
    if not verdict.failures:
        return report
    owner, name = _split_repo(repo)
    try:
        # The queue is the judged branch's unless the caller names another.
        queue_branch = branch or verdict.branch
        if not queue_branch:
            raise PostMergeReadError("no branch to read the merge queue of")
        entries, unknown = _identity_entries(owner, name, queue_branch, agent_identity)
        for pr_id, number in entries:
            _graphql(
                DEQUEUE_MUTATION, f"dequeue #{number}", PostMergeWriteError, id=pr_id
            )
            report["dequeued"].append(number)
        if unknown:
            raise PostMergeReadError(
                f"merge queue: {unknown} entries have an unknown enqueuer"
            )
    except (PostMergeReadError, PostMergeWriteError) as exc:
        report["errors"].append(f"dequeue: {exc}")

    created = 0
    try:
        filers = {_login_key(f) for f in (agent_identity, *DEMOTION_FILERS)}
        existing = _demotion_issues(owner, name, (agent_identity, *DEMOTION_FILERS))
        role_label = label or _role_label(owner, name)
        # One record per marker (signal, SHA); every distinct sighting under it
        # is checked against that record, so a second red run on a closed
        # record reopens it.
        records: dict[str, dict[str, Any]] = {}
        notes_by_issue: dict[Any, list[Any]] = {}
        seen: set[tuple[str, str]] = set()
        for failure in verdict.failures:
            if (failure.marker, _sighting(failure)) in seen:
                continue
            seen.add((failure.marker, _sighting(failure)))
            match = records.get(failure.marker) or next(
                (i for i in existing if _first_line(i.get("body")) == failure.marker),
                None,
            )
            if match is None:
                issue = _write(
                    [
                        "api",
                        "-X",
                        "POST",
                        f"repos/{owner}/{name}/issues",
                        "-f",
                        f"title=Post-merge {failure.signal} failure after #{failure.merge.number}: unattended merging demoted",
                        "-f",
                        f"body={_issue_body(failure)}",
                        "-f",
                        f"labels[]={role_label}",
                    ],
                    "file the demotion issue",
                )
                created += 1
                filed = json_object(issue).get("number")
                report["issues"].append(filed)
                if not isinstance(filed, int):
                    raise PostMergeWriteError("the filed issue carried no number")
                records[failure.marker] = {
                    "number": filed,
                    "state": "open",
                    "body": _issue_body(failure),
                }
                notes_by_issue[filed] = []
                continue
            records[failure.marker] = match
            number = match.get("number")
            if number not in notes_by_issue:
                comments = _paginated(
                    f"repos/{owner}/{name}/issues/{number}/comments?per_page=100",
                    f"#{number} comments",
                )
                notes_by_issue[number] = [
                    c.get("body")
                    for c in comments
                    if _login_key(json_object(c.get("user")).get("login")) in filers
                ]
            notes = notes_by_issue[number]
            if _recorded(failure, match, notes):
                continue
            if match.get("state") != "open":
                # A record a human closed must hold the rung again on a new
                # failure; a reopen is no content edit, so a later close clears.
                _write(
                    [
                        "api",
                        "-X",
                        "PATCH",
                        f"repos/{owner}/{name}/issues/{number}",
                        "-f",
                        "state=open",
                    ],
                    f"reopen #{number}",
                )
                report["reopened"].append(number)
                records[failure.marker] = {**match, "state": "open"}
            _write(
                [
                    "api",
                    "-X",
                    "POST",
                    f"repos/{owner}/{name}/issues/{number}/comments",
                    "-f",
                    f"body={FAILURE_NOTE}{_sighting(failure)}",
                ],
                f"comment on #{number}",
            )
            report["comments"].append(number)
            notes.append(f"{FAILURE_NOTE}{_sighting(failure)}")
    except (PostMergeReadError, PostMergeWriteError) as exc:
        report["errors"].append(f"demotion issue: {exc}")

    report["telemetry"] = {"demotion_events": created}
    if record_telemetry is not None:
        record_telemetry(created)
    return report


# --- CLI ----------------------------------------------------------------------------


def _default_is_human(
    repo: str, identity: str, self_logins: Collection[str]
) -> IsHuman:
    """The merge policy's human test. A null actor, the identity, a self login,
    an automation login, or a login with no write permission is non-human. A
    permission read that fails raises `PostMergeReadError`, so the verdict is
    unreadable rather than a human enqueue misjudged as an auto-merge."""
    cache: dict[str, str | None] = {}

    def permission(login: str) -> str | None:
        if login not in cache:
            owner, name = _split_repo(repo)
            endpoint = (
                f"repos/{owner}/{name}/collaborators/{quote(login, safe='')}/permission"
            )
            label = f"permission of {login}"
            try:
                proc = gh_capture(["api", endpoint])
            except (RuntimeError, ValueError, OSError) as exc:
                raise PostMergeReadError(f"{label}: {exc}") from exc
            if proc.returncode != 0:
                if gh_http_status(proc.stderr or "") != 404:
                    raise PostMergeReadError(
                        f"{label}: {(proc.stderr or '').strip() or proc.returncode}"
                    )
                cache[login] = None
            else:
                try:
                    value = json_object(json.loads(proc.stdout)).get("permission")
                except ValueError as exc:
                    raise PostMergeReadError(f"{label}: {exc}") from exc
                if not isinstance(value, str):
                    raise PostMergeReadError(f"{label}: no permission in the response")
                cache[login] = value
        return cache[login]

    return lambda actor: policy.is_human(
        actor,
        repo=repo,
        agent_identity=identity,
        self_logins=self_logins,
        permission=permission,
    )


def _since(value: str) -> datetime:
    parsed = datetime.fromisoformat(value)
    if parsed.utcoffset() is None:
        raise argparse.ArgumentTypeError("--since needs a timezone offset")
    return parsed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="babysit_postmerge.py",
        description="Check every unattended merge since a floor; read-only unless --remediate.",
        allow_abbrev=False,
    )
    parser.add_argument("--repo", required=True, help="owner/repo")
    parser.add_argument(
        "--agent-identity", required=True, help="the merge.agent-identity login"
    )
    parser.add_argument(
        "--since", required=True, type=_since, help="ISO 8601 floor with an offset"
    )
    parser.add_argument(
        "--branch",
        help="the branch to judge (default: the repository's default branch)",
    )
    parser.add_argument(
        "--self-login",
        action="append",
        default=[],
        help="a lane or bot self login (repeatable)",
    )
    parser.add_argument(
        "--remediate",
        action="store_true",
        help=(
            "trigger the one attribution re-run, dispatch a full run when no run covers an "
            "unverified merge, dequeue, file the demotion issue (the only writes)"
        ),
    )
    args = parser.parse_args(argv)

    # Only a dedicated App identity can be judged, and only that identity may
    # remediate: its dispatches, re-runs and filed issues are what the check
    # and the demotion record count.
    acting = args.agent_identity
    if args.remediate:
        try:
            acting = policy.read_acting_login()
        except policy.PolicyReadError:
            acting = None
    refusal = policy.resolve_identity(
        args.agent_identity, acting, args.self_login
    ).reason
    if refusal:
        json.dump({"ok": False, "error": refusal}, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 2

    verdict = check(
        args.repo,
        agent_identity=args.agent_identity,
        is_human=_default_is_human(args.repo, args.agent_identity, args.self_login),
        merged_since=args.since,
        branch=args.branch,
    )
    report = verdict.report()
    code = 3 if not verdict.readable else 1 if verdict.failures else 0
    branch = verdict.branch
    if verdict.readable and not branch:
        # A readable verdict always names its branch; refuse before any write
        # rather than dispatch or dequeue on an unknown ref.
        report["reason"] = "branch-unknown"
        code = 3
    elif args.remediate and verdict.readable and branch:
        errors: list[str] = []
        try:
            report["rerunsTriggered"] = attribute(args.repo, verdict)
        except PostMergeWriteError as exc:
            errors.append(f"re-run: {exc}")
        report["dispatched"] = False
        if verdict.needs_dispatch:
            try:
                dispatch_full_run(args.repo, ref=branch)
                report["dispatched"] = True
            except PostMergeWriteError as exc:
                errors.append(f"dispatch: {exc}")
        report["remediation"] = remediate(
            args.repo, verdict, agent_identity=args.agent_identity
        )
        report["remediation"]["errors"] = errors + report["remediation"]["errors"]
        if report["remediation"]["errors"]:
            code = 4
    json.dump(report, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return code


if __name__ == "__main__":
    sys.exit(main())

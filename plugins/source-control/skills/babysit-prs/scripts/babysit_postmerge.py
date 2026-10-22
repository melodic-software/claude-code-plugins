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
wrapper triggers: red again is a failure, green is a flake. A red full run the
pr-merge lane dispatched gets that one re-run from pr-merge.yml's own
`post-merge-dispatch` job, which records it (`_Context.lane_rerun`). It counts only
for checks that were not already failing on the newest completed run of the
same event before the merge (`_Context.regressions`); with none left it is
reported as unattributed and passes like a green run.

`remediate()` acts on failures in order: dequeue the identity's merge-queue
entries, file or comment on the demotion issue, then record the telemetry
count. `attribute()` triggers the one re-run, and `dispatch_full_run()` the
dispatch. The CLI is read-only unless `--remediate` is given; with it, a cycle
also dispatches one full run on the branch tip whenever an unverified
auto-merge has no identity dispatch run covering it, so a merge nobody
dispatched for (a sync App's own enqueue) cannot hold the lane forever.

The pinned SHA is read from the agent identity's `<!-- babysit-merge-pin
sha=<S> -->` comment, which `babysit_merge.py --unattended` posts immediately
before it enqueues. Without `--since` the floor is the merge gate's: the later
of the enabling config commit and the newest human close of a demotion record.

Exit codes: 0 no failure and every auto-merge verified, 1 a failure, 2 usage
or a refused identity (not a dedicated App login, or `--remediate` under
another acting login), 3 unreadable, 4 a write failed, 5 no failure but an
auto-merge not yet verified. Only 0 lets a merge proceed.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import sys
import tempfile
from collections.abc import Callable, Collection, Iterable
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import quote

import babysit_merge_policy as policy
from babysit_gh import (
    flatten_paginated_items,
    gh_capture,
    gh_http_status,
    is_owner_repo_pair,
)
from babysit_util import (
    is_json_array,
    is_json_object,
    json_array,
    json_object,
    run_command,
)

FULL_RUN_WORKFLOW = "pr-require-checks.yml"
CANARY_WORKFLOW = "post-merge-detect-silent-revert.yml"
# The pr-merge lane dispatches the full run with its own GITHUB_TOKEN (the
# lanes App holds no actions: write) and records the dispatched run's id in an
# artifact named with this prefix; `_Context.lane_dispatched` reads it.
LANE_DISPATCH_WORKFLOW = ".github/workflows/pr-merge.yml"
LANE_DISPATCH_ARTIFACT = "pr-merge-dispatched-"
LANE_DISPATCH_ACTOR = "github-actions[bot]"
# Its post-merge-dispatch job starts the one re-run of a red lane-dispatched
# full run, also under GITHUB_TOKEN, and records it in an artifact named
# `<prefix><run id>-attempt-2`; `_Context.lane_rerun` reads it.
LANE_RERUN_ARTIFACT = "pr-merge-rerun-"
# The events of the pr-merge.yml jobs that upload each record: dispatch-full-run
# (push, and after the merge job) and post-merge-dispatch (schedule and
# workflow_dispatch) write the dispatch record; only post-merge-dispatch writes
# the re-run record.
LANE_DISPATCH_EVENTS = frozenset({"schedule", "workflow_dispatch", "push"})
LANE_RERUN_EVENTS = frozenset({"schedule", "workflow_dispatch"})
DISPATCH_DEADLINE = timedelta(hours=6)
DEMOTION_FILERS = ("github-actions[bot]",)
HUMAN_GATED_ROLE = "human-gated"
DEFAULT_ROLE_LABEL = "needs-human"
# The role marking a pull request whose only writer is the standards sync App.
STANDARDS_SYNC_ROLE = "standards-sync"
DEFAULT_STANDARDS_SYNC_LABEL = "standards-sync"
TRACKER_CONFIG = ".work-item-tracker.json"
# The follow-up note on an existing record; the demotion-alert workflow writes
# the same prefix, so either filer's note is a sighting to the other.
FAILURE_NOTE = "The post-merge check found this failure again: "
MERGED_PAGE_SIZE = 100
MERGED_PAGE_LIMIT = 30
# A red full run counts against a merge only for a check that was not already
# failing on the branch's newest completed run of the same event before it.
# A check is a failed job, or one gate the hygiene aggregator step names in a
# titled failure annotation (`<gate> failed`). The lane aggregator job is red
# whenever another job is, so beside one it adds nothing; the gitleaks gate
# scans every fetched branch on these events, so no merge into the branch can
# turn it red. post-merge-demotion-alert.yml applies the same rule.
FAILED_CONCLUSIONS = (
    "failure",
    "timed_out",
    "cancelled",
    "startup_failure",
    "action_required",
)
LANE_AGGREGATE_JOB = "ci-status"
HYGIENE_AGGREGATE_STEP = "Aggregate hygiene results"
UNATTRIBUTABLE_GATES = frozenset({"gitleaks failed"})
# A newly failing check demotes only when one of its failing suites is in the
# affected set of the merges since the branch's last green full run, or no
# suite can be named. The unit is the suite (a test file). Only a test leg
# whose one failed step is its suite step names its suites, from its log: the
# runner's `FAIL: <suite>` lines, or each pytest invocation's summary. The
# affected set is scripts/plan-test-lanes.sh, the PR runs' own selector, over
# the diff from the last green full run's SHA, run in a worktree of the red
# run's SHA. A suite outside the set, or one with an open quarantine issue,
# demotes nothing: an out-of-set suite with no such issue gets one
# (`file_quarantines`). A quarantine issue older than `merge.quarantine-days`
# no longer excuses its suite, and the merge gate's own suites are never
# excused. post-merge-demotion-alert.yml applies the same rule through
# `--judge-run`.
SUITE_STEPS = {
    "Run this leg's shell suites": "bash",
    "Run this leg's Python suites": "python",
}
PLAN_SCRIPT = "scripts/plan-test-lanes.sh"
PLAN_TIMEOUT_SECONDS = 600
# The merge gate's own suites, by path prefix: their failure always demotes.
GATE_SUITE_PREFIXES = (
    "plugins/source-control/skills/babysit-prs/scripts/",
    "docs/conventions/pr-pipeline/",
    ".github/actions/",
    ".github/scripts/pr-merge/",
    ".github/scripts/post-merge-demotion-alert/",
    "scripts/post-merge-demotion-alert.",
)
QUARANTINE_NOTE = "The quarantined suite failed again: "
BORN_TRIAGED = "<!-- work-items:born-triaged -->"
CODEOWNERS_PATHS = (".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS")
_SUITE_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9._/-]*")

SIGNAL_SCHEDULE = "schedule"
SIGNAL_DISPATCH = "dispatch"
SIGNAL_CANARY = "canary"
SIGNAL_READ_BACK = "read-back"
FULL_RUN_EVENTS = {SIGNAL_SCHEDULE: "schedule", SIGNAL_DISPATCH: "workflow_dispatch"}

GREEN, FLAKE, RED, RERUN, PENDING = "green", "flake", "red", "rerun", "pending"

EXIT_FAILURE, EXIT_UNREADABLE, EXIT_WRITE_FAILED, EXIT_UNVERIFIED = 1, 3, 4, 5

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
    # The pr-merge lane dispatched it, so its post-merge-dispatch job starts
    # the re-run: the lanes App and so the lane's `--remediate` cannot.
    lane: bool = False


@dataclass(frozen=True)
class Quarantine:
    """A failing suite excused from demotion: outside the affected set (no
    open quarantine issue yet, `file_quarantines` files one) or under an open
    one that has not expired (it gets a sighting comment)."""

    suite: str
    run_url: str
    sha: str


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
    # Red full runs charged to no merge: every failing check was already
    # failing before the merge, or is one no merge can cause.
    unattributed: tuple[str, ...] = ()
    warnings: tuple[str, ...] = ()
    # The branch judged: the caller's, or the repository's default branch.
    branch: str | None = None
    quarantines: tuple[Quarantine, ...] = ()

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
                {
                    "runId": r.run_id,
                    "url": r.url,
                    "signal": r.signal,
                    "laneDispatched": r.lane,
                }
                for r in self.reruns
            ],
            "flakes": list(self.flakes),
            "unattributed": list(self.unattributed),
            "quarantines": [
                {"suite": q.suite, "run": q.run_url, "sha": q.sha}
                for q in self.quarantines
            ],
            "needsDispatch": self.needs_dispatch,
            "warnings": list(self.warnings),
            "branch": self.branch,
        }


def demotion_marker(sha: str, signal: str) -> str:
    return f"<!-- babysit-merge-demotion sha={sha} signal={signal} -->"


def quarantine_marker(suite: str) -> str:
    return f"<!-- post-merge-quarantine suite={suite} -->"


def is_gate_suite(suite: str) -> bool:
    return suite.startswith(GATE_SUITE_PREFIXES)


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

_FULL_SHA = re.compile(r"[0-9a-f]{40}")


def _full_history_clones() -> list[Path]:
    """The distinct non-shallow clones among the merge gate's history
    checkouts (`babysit_merge_policy._history_checkouts`)."""
    roots: list[Path] = []
    for checkout in policy._history_checkouts():
        top = policy._git(checkout, "rev-parse", "--show-toplevel")
        if not top or not top.strip():
            continue
        root = Path(top.strip())
        if root not in roots and (
            policy._git(root, "rev-parse", "--is-shallow-repository") == "false\n"
        ):
            roots.append(root)
    return roots


_LOG_STAMP = re.compile(r"^\ufeff?\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z ?")
_BASH_START = re.compile(r"=== (\S+) ===")
_BASH_PASS = re.compile(r"PASS: (\S+)")
_BASH_FAIL = re.compile(
    r"FAIL: (\S+)(?: \(no result recorded; the worker never reported\))?"
)
_BASH_ADVISORY = re.compile(
    r"(?:::warning::|##\[warning\])(\S+) failed \(exit \d+\) but is advisory"
)
_PYTEST_CALL = re.compile(r"python -m pytest .* -- (\S+)")
_PYTEST_SUMMARY = re.compile(
    r"=*\s*(no tests ran|\d+ [a-z]+(?:, \d+ [a-z]+)*) in \d+(?:\.\d+)?s\b.*"
)


def suite_failures(log: str, kind: str) -> frozenset[str] | None:
    """The suites a test leg's log shows failing, or None when the log cannot
    name every one: a suite with no result, a discriminating skip (which
    fails the leg with no suite failed), or no failing suite at all.
    `kind` is "bash" (scripts/run-plugin-tests.sh) or "python" (one pytest
    invocation per suite, echoed by `xargs -t`)."""
    lines = [_LOG_STAMP.sub("", line.rstrip("\r")) for line in log.split("\n")]
    failed: set[str] = set()
    if kind == "bash":
        started: set[str] = set()
        passed: set[str] = set()
        advisory: set[str] = set()
        for line in lines:
            if line.startswith("DISCRIMINATING SKIP"):
                return None
            if m := _BASH_START.fullmatch(line):
                started.add(m[1])
            elif m := _BASH_PASS.fullmatch(line):
                passed.add(m[1])
            elif m := _BASH_FAIL.fullmatch(line):
                failed.add(m[1])
            elif m := _BASH_ADVISORY.match(line):
                advisory.add(m[1])
        if started - passed - failed:
            return None
        failed -= advisory
    else:
        suite: str | None = None
        outcome: str | None = None
        for line in [*lines, None]:
            m = _PYTEST_CALL.fullmatch(line) if line is not None else None
            if line is None or m:
                if suite is not None:
                    if outcome is None:
                        return None
                    if outcome == "failed":
                        failed.add(suite)
                suite, outcome = (m[1], None) if m else (None, None)
            elif suite is not None and (s := _PYTEST_SUMMARY.fullmatch(line)):
                words = {w.split(" ")[-1] for w in s[1].split(", ")}
                bad = s[1] == "no tests ran" or words & {"failed", "error", "errors"}
                outcome = "failed" if bad else "passed"
    if not failed or not all(_SUITE_RE.fullmatch(f) for f in failed):
        return None
    return frozenset(failed)


def affected_suites(base_sha: str, head_sha: str) -> frozenset[str] | None:
    """The suites the PR runs' selector picks for the change `base_sha..
    head_sha`: every suite of `PLAN_SCRIPT`'s bash and Python plans, run in a
    temporary worktree of `head_sha` in a local full-history clone holding
    both commits. None when no clone holds them, the tree has no plan
    script, or the plan fails."""
    if not (_FULL_SHA.fullmatch(base_sha) and _FULL_SHA.fullmatch(head_sha)):
        return None
    root = next(
        (
            r
            for r in policy._clones_holding(head_sha)
            if policy._git(r, "cat-file", "-e", f"{base_sha}^{{commit}}") is not None
        ),
        None,
    )
    if root is None:
        return None
    with tempfile.TemporaryDirectory(prefix="postmerge-affected-") as tmp:
        tree = Path(tmp) / "tree"
        if (
            policy._git(root, "worktree", "add", "--detach", str(tree), head_sha)
            is None
        ):
            return None
        try:
            if not (tree / PLAN_SCRIPT).is_file():
                return None
            try:
                proc = run_command(
                    ["bash", PLAN_SCRIPT, "--base", base_sha],
                    allowed_executables=("bash",),
                    check=False,
                    cwd=tree,
                    timeout_seconds=PLAN_TIMEOUT_SECONDS,
                )
            except (RuntimeError, ValueError, OSError):
                return None
            if proc.returncode != 0:
                return None
            suites: set[str] = set()
            for line in proc.stdout.splitlines():
                key, _, value = line.partition("=")
                if key in ("bash_plan", "python_plan"):
                    try:
                        legs = json_object(json.loads(value))
                    except ValueError:
                        return None
                    suites |= {str(x) for leg in legs.values() for x in json_array(leg)}
            return frozenset(suites)
        finally:
            policy._git(root, "worktree", "remove", "--force", str(tree))


@dataclass
class _Context:
    owner: str
    name: str
    identity: str
    contains_cache: dict[tuple[str, str], bool] = field(default_factory=dict)
    outcome_cache: dict[tuple[int, str], tuple[str, str]] = field(default_factory=dict)
    # Full runs whose red verdict came from the wrapper's re-run (attempt 2).
    red_on_rerun: set[int] = field(default_factory=set)
    branch: str = ""
    branch_tip: str | None = None
    lane_cache: dict[str, bool] = field(default_factory=dict)
    checks_cache: dict[tuple[int, int], frozenset[str]] = field(default_factory=dict)
    # Full-history clones `contains` asks first; None until first resolved.
    local_clones: list[Path] | None = None
    baseline_cache: dict[tuple[str, datetime], frozenset[str] | None] = field(
        default_factory=dict
    )
    # When quarantine issues are judged, and `merge.quarantine-days` (None:
    # read at the red run's head the first time it is needed).
    now: datetime = field(default_factory=lambda: datetime.now(UTC))
    quarantine_days: int | None = None
    # The failed jobs of each attempt by check name, and each job's suites.
    check_jobs: dict[tuple[int, int], dict[str, dict[str, Any]]] = field(
        default_factory=dict
    )
    suite_cache: dict[Any, frozenset[str] | None] = field(default_factory=dict)
    affected_cache: dict[int, frozenset[str] | None] = field(default_factory=dict)
    demoting_cache: dict[tuple[int, int, frozenset[str]], frozenset[str]] = field(
        default_factory=dict
    )
    # Each suite's newest open quarantine issue by a filer; None until read.
    quarantine_issues: dict[str, dict[str, Any]] | None = None
    # Excused failing suites, by (suite, sighting).
    quarantines: dict[tuple[str, str], Quarantine] = field(default_factory=dict)

    def regressions(self, signal: str, run: Run, merged_at: datetime) -> frozenset[str]:
        """The checks failing on red full run `run` that were not failing on
        the newest completed run of the same event before the merge, less the
        test legs whose every failing suite is excused (`demoting`). With no
        such run, every failing check counts, as before the baseline existed."""
        attempt = 2 if run.id in self.red_on_rerun else 1
        failing = self.failing_checks(run.id, attempt)
        baseline = self._baseline(signal, merged_at) if failing else None
        new = failing if baseline is None else failing - baseline
        return self.demoting(run, attempt, new) if new else new

    def demoting(
        self, run: Run, attempt: int, checks: frozenset[str]
    ) -> frozenset[str]:
        """The checks among `checks` (failing on `attempt` of `run`) that
        demote: any whose suites cannot be named, and any with a failing
        suite that is a gate suite, is under an expired quarantine issue, or
        is in the merges' affected set, or with no computable set. Each other
        failing suite is recorded in `quarantines`."""
        key = (run.id, attempt, checks)
        if key in self.demoting_cache:
            return self.demoting_cache[key]
        named = {c: self.failing_suites(run.id, attempt, c) for c in checks}
        demote = {c for c, suites in named.items() if suites is None}
        judged = {c: suites for c, suites in named.items() if suites is not None}
        sighting = f"{run.url}/attempts/{attempt}"
        excused: list[Quarantine] = []
        if judged:
            issues = self._quarantine_issues()
            days = self._quarantine_days(run.head_sha)
            for check, suites in judged.items():
                for suite in sorted(suites):
                    issue = issues.get(suite)
                    if is_gate_suite(suite):
                        demote.add(check)
                    elif issue is not None:
                        created = _time(issue.get("created_at"))
                        if self.now >= created + timedelta(days=days):
                            demote.add(check)
                        else:
                            excused.append(Quarantine(suite, sighting, run.head_sha))
                    elif (affected := self.affected(run)) is None or suite in affected:
                        demote.add(check)
                    else:
                        excused.append(Quarantine(suite, sighting, run.head_sha))
        for q in excused:
            self.quarantines[(q.suite, q.run_url)] = q
        self.demoting_cache[key] = frozenset(demote)
        return self.demoting_cache[key]

    def failing_suites(
        self, run_id: int, attempt: int, check: str
    ) -> frozenset[str] | None:
        """The suites failing check `check` names, or None: the check is not
        a test leg whose one failed step is its suite step, or its log cannot
        be read or name them (`suite_failures`)."""
        self.failing_checks(run_id, attempt)
        job = self.check_jobs.get((run_id, attempt), {}).get(check)
        if job is None:
            return None
        failed = {
            str(s.get("name") or "")
            for s in map(json_object, json_array(job.get("steps")))
            if s.get("conclusion") in FAILED_CONCLUSIONS
        }
        kind = SUITE_STEPS.get(next(iter(failed))) if len(failed) == 1 else None
        job_id = job.get("id")
        if kind is None or not isinstance(job_id, int):
            return None
        if job_id not in self.suite_cache:
            try:
                proc = gh_capture(
                    [
                        "api",
                        f"repos/{self.owner}/{self.name}/actions/jobs/{job_id}/logs",
                    ]
                )
            except (RuntimeError, ValueError, OSError):
                proc = None
            self.suite_cache[job_id] = (
                suite_failures(proc.stdout or "", kind)
                if proc is not None and proc.returncode == 0
                else None
            )
        return self.suite_cache[job_id]

    def affected(self, run: Run) -> frozenset[str] | None:
        """The affected set of the merges between the branch's newest green
        full run before `run` and `run` itself (`affected_suites`), or None
        when there is no such run or the set cannot be computed."""
        if run.id not in self.affected_cache:
            created = quote(
                f"<{run.created_at.astimezone(UTC).strftime('%Y-%m-%dT%H:%M:%SZ')}",
                safe="",
            )
            greens: list[Run] = []
            for event in FULL_RUN_EVENTS.values():
                listing = _read(
                    [
                        "api",
                        f"repos/{self.owner}/{self.name}/actions/workflows/{FULL_RUN_WORKFLOW}"
                        f"/runs?event={event}&branch={quote(self.branch, safe='')}"
                        f"&status=success&created={created}&per_page=20",
                    ],
                    f"{FULL_RUN_WORKFLOW} {event} green runs",
                )
                greens += [
                    r
                    for r in map(
                        Run.from_api,
                        json_array(json_object(listing).get("workflow_runs")),
                    )
                    if r.conclusion == "success"
                    and r.head_branch == self.branch
                    and r.created_at < run.created_at
                    and r.head_sha != run.head_sha
                ]
            green = max(greens, key=lambda r: r.created_at, default=None)
            self.affected_cache[run.id] = (
                None if green is None else affected_suites(green.head_sha, run.head_sha)
            )
        return self.affected_cache[run.id]

    def _quarantine_days(self, sha: str) -> int:
        if self.quarantine_days is None:
            self.quarantine_days = policy.read_config_at(
                f"{self.owner}/{self.name}", sha
            ).quarantine_days
        return self.quarantine_days

    def _quarantine_issues(self) -> dict[str, dict[str, Any]]:
        """Each suite's newest open quarantine issue that a filer opened
        (the agent identity or github-actions[bot]): a quarantine anyone
        else opens counts for nothing."""
        if self.quarantine_issues is None:
            found: dict[str, dict[str, Any]] = {}
            for issue in _demotion_issues(
                self.owner, self.name, (self.identity, *DEMOTION_FILERS)
            ):
                suite = _quarantined_suite(issue.get("body"))
                if suite is None or issue.get("state") != "open":
                    continue
                if suite not in found or str(issue.get("created_at")) > str(
                    found[suite].get("created_at")
                ):
                    found[suite] = issue
            self.quarantine_issues = found
        return self.quarantine_issues

    def _baseline(self, signal: str, before: datetime) -> frozenset[str] | None:
        key = (signal, before)
        if key not in self.baseline_cache:
            created = quote(
                f"<{before.astimezone(UTC).strftime('%Y-%m-%dT%H:%M:%SZ')}", safe=""
            )
            listing = _read(
                [
                    "api",
                    f"repos/{self.owner}/{self.name}/actions/workflows/{FULL_RUN_WORKFLOW}"
                    f"/runs?event={FULL_RUN_EVENTS[signal]}&branch={quote(self.branch, safe='')}"
                    f"&status=completed&created={created}&per_page=20",
                ],
                f"{FULL_RUN_WORKFLOW} {signal} baseline",
            )
            runs = [
                r
                for r in map(
                    Run.from_api, json_array(json_object(listing).get("workflow_runs"))
                )
                if r.created_at < before
                and r.head_branch == self.branch
                and r.status == "completed"
            ]
            newest = max(runs, key=lambda r: r.created_at, default=None)
            self.baseline_cache[key] = (
                None
                if newest is None
                else frozenset()
                if newest.conclusion == "success"
                else self.failing_checks(newest.id, newest.attempt)
            )
        return self.baseline_cache[key]

    def failing_checks(self, run_id: int, attempt: int) -> frozenset[str]:
        """The checks one attempt of a full run failed (see FAILED_CONCLUSIONS)."""
        key = (run_id, attempt)
        if key not in self.checks_cache:
            jobs = [
                j
                for j in _paginated(
                    f"repos/{self.owner}/{self.name}/actions/runs/{run_id}"
                    f"/attempts/{attempt}/jobs?per_page=100",
                    f"run {run_id} attempt {attempt} jobs",
                    "jobs",
                )
                if j.get("conclusion") in FAILED_CONCLUSIONS
            ]
            # A red run with no failed job (a workflow file that does not
            # load) is one check of its own, never excused.
            checks: set[str] = (
                set() if jobs else {f"{FULL_RUN_WORKFLOW}: no failed jobs"}
            )
            by_name: dict[str, dict[str, Any]] = {}
            for job in jobs:
                name = str(job.get("name") or "")
                if name == LANE_AGGREGATE_JOB and len(jobs) > 1:
                    continue
                by_name[name] = job
                gates = self._failed_gates(job.get("id"))
                steps = {
                    str(s.get("name") or "")
                    for s in map(json_object, json_array(job.get("steps")))
                    if s.get("conclusion") in FAILED_CONCLUSIONS
                }
                if not gates or steps - {HYGIENE_AGGREGATE_STEP}:
                    checks.add(name)
                checks |= {f"{name}: {g}" for g in gates - UNATTRIBUTABLE_GATES}
            self.check_jobs[key] = by_name
            self.checks_cache[key] = frozenset(checks)
        return self.checks_cache[key]

    def _failed_gates(self, job_id: Any) -> frozenset[str]:
        """The titles of a job's failure annotations. A job id is its check
        run id; an annotation read the token may not make (403, 404) yields
        none, so the whole job stays one check and nothing is excused."""
        args = [
            "api",
            f"repos/{self.owner}/{self.name}/check-runs/{job_id}/annotations?per_page=100",
        ]
        try:
            proc = gh_capture(args)
        except (RuntimeError, ValueError, OSError) as exc:
            raise PostMergeReadError(f"job {job_id} annotations: {exc}") from exc
        if proc.returncode != 0:
            if gh_http_status(proc.stderr or "") in (403, 404):
                return frozenset()
            raise PostMergeReadError(
                f"job {job_id} annotations: {(proc.stderr or '').strip()}"
            )
        try:
            items = json_array(json.loads(proc.stdout or "[]"))
        except ValueError as exc:
            raise PostMergeReadError(f"job {job_id} annotations: {exc}") from exc
        return frozenset(
            str(a.get("title")).strip()
            for a in map(json_object, items)
            if a.get("annotation_level") == "failure"
            and str(a.get("title") or "").strip()
        )

    def lane_dispatched(self, run: Run) -> bool:
        """Whether the pr-merge lane sent this github-actions[bot] dispatch:
        its `pr-merge-dispatched-<id>` artifact was uploaded by a run of
        pr-merge.yml in this repository on the branch."""
        return run.actor == LANE_DISPATCH_ACTOR and self._lane_record(
            f"{LANE_DISPATCH_ARTIFACT}{run.id}", LANE_DISPATCH_EVENTS
        )

    def lane_rerun(self, run: Run) -> bool:
        """Whether pr-merge.yml started attempt 2 of this lane-dispatched run:
        its post-merge-dispatch job uploads `pr-merge-rerun-<id>-attempt-2`
        only after its own `rerun-failed-jobs` call made that attempt."""
        return self.lane_dispatched(run) and self._lane_record(
            f"{LANE_RERUN_ARTIFACT}{run.id}-attempt-2", LANE_RERUN_EVENTS
        )

    def _lane_record(self, artifact: str, events: frozenset[str]) -> bool:
        """Whether a run of the branch's own pr-merge.yml (`_lane_sender`)
        uploaded an artifact named `artifact`. Only steps of a run can upload
        its artifacts. A failed read raises, so the verdict is unreadable
        rather than the record taken as present."""
        if artifact not in self.lane_cache:
            repo = f"{self.owner}/{self.name}"
            listing = _read(
                [
                    "api",
                    f"repos/{repo}/actions/artifacts?name={artifact}&per_page=100",
                ],
                f"record {artifact}",
            )
            senders = {
                json_object(a.get("workflow_run")).get("id")
                for a in map(
                    json_object, json_array(json_object(listing).get("artifacts"))
                )
                if a.get("name") == artifact
            }
            self.lane_cache[artifact] = any(
                isinstance(sender, int)
                and self._lane_sender(
                    json_object(
                        _read(
                            ["api", f"repos/{repo}/actions/runs/{sender}"],
                            f"run {sender}",
                        )
                    ),
                    events,
                )
                for sender in senders
            )
        return self.lane_cache[artifact]

    def _lane_sender(self, record: dict[str, Any], events: frozenset[str]) -> bool:
        """Whether workflow run `record` ran this repository's own pr-merge.yml
        from the branch, on an event of the job that writes the record. A fork's
        `pull_request` run carries the base repository as `repository` and its
        own branch name, which can be the branch's, as `head_branch`, so the
        head repository is checked and `head_sha`, the commit whose copy of
        the file ran, must be on the branch's tip as `refs/heads/` names it:
        that also refuses a tag named like the branch, which a bare name
        would resolve to first."""
        repo = f"{self.owner}/{self.name}"
        head_sha = record.get("head_sha")
        return (
            record.get("path") == LANE_DISPATCH_WORKFLOW
            and record.get("event") in events
            and record.get("head_branch") == self.branch
            and json_object(record.get("repository")).get("full_name") == repo
            and json_object(record.get("head_repository")).get("full_name") == repo
            and isinstance(head_sha, str)
            and _FULL_SHA.fullmatch(head_sha) is not None
            and self.contains(head_sha, self._branch_tip())
        )

    def _branch_tip(self) -> str:
        """The branch's tip commit, read from `refs/heads/<branch>` once. A
        failed or malformed read raises, so the verdict is unreadable."""
        if self.branch_tip is None:
            ref = json_object(
                _read(
                    [
                        "api",
                        f"repos/{self.owner}/{self.name}/git/ref/heads/"
                        f"{quote(self.branch, safe='/')}",
                    ],
                    f"branch {self.branch}",
                )
            )
            sha = json_object(ref.get("object")).get("sha")
            if not isinstance(sha, str) or _FULL_SHA.fullmatch(sha) is None:
                raise PostMergeReadError(f"branch {self.branch}: no tip commit")
            self.branch_tip = sha
        return self.branch_tip

    def contains(self, ancestor: str, sha: str) -> bool:
        """Whether `sha` is `ancestor` or has it in its history: from a local
        full-history clone when one holds both commits, else from the compare
        API, whose `ahead` or `identical` status means `ancestor` is reachable
        from `sha`, which is what `git merge-base --is-ancestor` tests."""
        key = (ancestor, sha)
        if key not in self.contains_cache:
            if ancestor == sha:
                self.contains_cache[key] = True
            elif (local := self._local_contains(ancestor, sha)) is not None:
                self.contains_cache[key] = local
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

    def _local_contains(self, ancestor: str, sha: str) -> bool | None:
        """`git merge-base --is-ancestor` in the first local clone that can
        decide (exit 0 or 1), or None. Only full SHA-1 ids are asked: a ref
        name can point elsewhere locally than on GitHub. A shallow clone is
        never asked, and graft files and replace refs are ignored, as any of
        them would cut history and answer False for an ancestor. A partial
        clone never lazy-fetches a missing commit: it exits non-zero and the
        compare API answers."""
        if not (_FULL_SHA.fullmatch(ancestor) and _FULL_SHA.fullmatch(sha)):
            return None
        if self.local_clones is None:
            self.local_clones = _full_history_clones()
        for root in self.local_clones:
            try:
                proc = run_command(
                    [
                        "git",
                        "--no-replace-objects",
                        "-C",
                        str(root),
                        "merge-base",
                        "--is-ancestor",
                        ancestor,
                        sha,
                    ],
                    allowed_executables=("git",),
                    check=False,
                    env_overrides=policy.HISTORY_GIT_ENV,
                )
            except (RuntimeError, ValueError, OSError):
                return None
            if proc.returncode in (0, 1):
                return proc.returncode == 0
        return None

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
        # A re-run by anyone else (a person re-running until green) cannot
        # clear a red attempt 1. Two github-actions[bot] re-runs can:
        # post-merge-demotion-alert.yml's single re-run, which re-runs no run
        # the bot started, and for a run the pr-merge lane dispatched, the one
        # its post-merge-dispatch job recorded. That job uploads the record
        # just after its re-run starts, so a bot attempt 2 of a lane-dispatched
        # run still in progress waits for its record instead of reading red.
        if (
            second.status != "completed"
            and second.triggering_actor == LANE_DISPATCH_ACTOR
            and first.triggering_actor == LANE_DISPATCH_ACTOR
            and self.lane_dispatched(run)
        ):
            return PENDING, "re-run-in-progress"
        if second.triggering_actor != self.identity and not (
            second.triggering_actor == LANE_DISPATCH_ACTOR
            and (first.triggering_actor != LANE_DISPATCH_ACTOR or self.lane_rerun(run))
        ):
            return (
                RED,
                f"attempt 1 {first.conclusion}; attempt 2 not triggered by the agent identity",
            )
        if second.status != "completed":
            return PENDING, "re-run-in-progress"
        if second.conclusion == "success":
            return FLAKE, "attempt 1 failed, the one re-run passed"
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
    unattributed: dict[str, None] = field(default_factory=dict)


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
        if signal == SIGNAL_DISPATCH
        and (run.actor == ctx.identity or ctx.lane_dispatched(run))
    ]

    def passes(run: Run) -> bool:
        state = ctx.outcome(run, attributable=True)[0]
        return state in (GREEN, FLAKE) or (
            state == RED and not ctx.regressions(SIGNAL_DISPATCH, run, merged_at)
        )

    green_dispatch = [r for r in own if passes(r)]
    green_canary = [
        r for r in canaries if ctx.outcome(r, attributable=False)[0] == GREEN
    ]

    if merge.by_identity and pinned is None:
        # A missing or edited pin is pending until the dispatch deadline, then
        # a failure, so a demotion record is filed and a human close restarts
        # the floor instead of the lane holding forever.
        if now > merged_at + DISPATCH_DEADLINE:
            failures.append(
                Failure(
                    SIGNAL_READ_BACK,
                    merge,
                    None,
                    "no unedited pin comment by the agent identity",
                )
            )
        else:
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
            new = ctx.regressions(signal, run, merged_at)
            if new:
                failures.append(
                    Failure(
                        signal,
                        merge,
                        ctx.sighting(run),
                        f"{detail}; newly failing: {', '.join(sorted(new))}",
                    )
                )
            else:
                tally.unattributed[ctx.sighting(run)] = None
        elif state == RERUN:
            tally.reruns[run.id] = Rerun(
                run.id,
                run.url,
                signal,
                lane=signal == SIGNAL_DISPATCH and ctx.lane_dispatched(run),
            )
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
    lane_merges_only: bool = False,
    quarantine_days: int | None = None,
) -> PostMergeVerdict:
    """Judge every auto-merge into `branch` since `merged_since`; with no
    `branch`, the repository's default branch, read once from the repos API.
    With `lane_merges_only` (the pr-merge lane), only merges the agent
    identity enqueued are judged.

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
            derived = policy.derive_auto_merge(
                pr, is_human, identity, lane_merges_only=lane_merges_only
            )
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
        ctx = _Context(
            owner,
            name,
            identity,
            branch=branch,
            now=now,
            quarantine_days=quarantine_days,
        )
        tally = _Tally()
        states = tuple(
            _judge(
                merge,
                ctx,
                full_runs=full_runs,
                canary_runs=canary_runs,
                pinned=pinned_sha(merge) if pinned_sha and merge.by_identity else None,
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
        unattributed=tuple(tally.unattributed),
        warnings=tuple(warnings),
        branch=branch,
        quarantines=tuple(ctx.quarantines.values()),
    )


# --- Writes -------------------------------------------------------------------------


def dispatch_full_run(repo: str, *, ref: str) -> None:
    """Dispatch the full `pr-require-checks` run on `ref`; called by
    `--remediate` when the verdict needs a dispatch, and by the unattended
    merge gate (`babysit_merge.py`) once a landed merge reads back at its pin.
    When neither dispatches under the identity, each auto-merge fails at the
    deadline."""
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
    """Trigger the one `rerun-failed-jobs` on each red full run awaiting it,
    unless another re-run (post-merge-demotion-alert.yml's) started since."""
    owner, name = _split_repo(repo)
    triggered: list[int] = []
    for rerun in verdict.reruns:
        current = json_object(
            _call(
                ["api", f"repos/{owner}/{name}/actions/runs/{rerun.run_id}"],
                f"run {rerun.run_id}",
                PostMergeWriteError,
            )
        ).get("run_attempt")
        if not isinstance(current, int) or current >= 2:
            continue
        triggered.append(rerun.run_id)
        _write(
            [
                "api",
                "-X",
                "POST",
                f"repos/{owner}/{name}/actions/runs/{rerun.run_id}/rerun-failed-jobs",
            ],
            f"re-run {rerun.run_id}",
        )
    return triggered


def _role_label(
    owner: str,
    name: str,
    *,
    strict: bool = False,
    role: str = HUMAN_GATED_ROLE,
    default: str = DEFAULT_ROLE_LABEL,
) -> str:
    """The tracker's label for `role` (human-gated unless named), or `default`
    when the tracker config is absent (404) or maps none. Any other failed
    read is the default too, unless `strict`: then it raises
    `PostMergeReadError`, so a gate never acts on a label the tracker may
    have remapped."""
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
    except PostMergeReadError as exc:
        if strict and gh_http_status(str(exc)) != 404:
            raise
        return default
    label = json_object(
        json_object(json_object(config).get("config")).get("role_labels")
    ).get(role)
    return label.strip() if isinstance(label, str) and label.strip() else default


def standards_sync_label(owner: str, name: str) -> str:
    """The tracker's standards-sync role label (`standards-sync` unless
    `.work-item-tracker.json` maps it). No branch refresh updates a pull
    request carrying it: the sync App is its only writer. A failed read other
    than a 404 raises `PostMergeReadError`."""
    return _role_label(
        owner,
        name,
        strict=True,
        role=STANDARDS_SYNC_ROLE,
        default=DEFAULT_STANDARDS_SYNC_LABEL,
    )


def standards_sync_skip(owner: str, name: str, labels: Any) -> str | None:
    """Why no branch refresh may update a pull request carrying the REST
    `labels`, or None: it carries the standards-sync role label (matched
    case-insensitively), whose only writer is the sync App. An unreadable
    label raises `PostMergeReadError`."""
    label = standards_sync_label(owner, name)
    if is_json_array(labels) and any(
        str(json_object(item).get("name") or "").casefold() == label.casefold()
        for item in labels
    ):
        return f"the PR carries the {label!r} standards-sync label"
    return None


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


def identity_queue(repo: str, branch: str, identity: str) -> tuple[list[int], int]:
    """The pull request numbers of the agent identity's merge-queue entries on
    `branch`, and how many entries have an unknown enqueuer."""
    owner, name = _split_repo(repo)
    entries, unknown = _identity_entries(owner, name, branch, identity)
    return [number for _, number in entries], unknown


def dequeue_identity_entries(
    repo: str,
    branch: str,
    identity: str,
    *,
    numbers: Collection[int] | None = None,
    dequeued: list[int] | None = None,
) -> int:
    """Dequeue the agent identity's merge-queue entries on `branch`, only those
    for `numbers` when given, appending each pull request number to
    `dequeued` as it goes. Returns how many entries have an unknown enqueuer:
    those cannot be judged the identity's and are left for the caller to
    report. Never touches another actor's entry. Every entry is tried; a
    failed one does not stop the rest. Raises `PostMergeReadError`, or
    `PostMergeWriteError` naming every failed entry."""
    owner, name = _split_repo(repo)
    entries, unknown = _identity_entries(owner, name, branch, identity)
    failed: list[str] = []
    for pr_id, number in entries:
        if numbers is not None and number not in numbers:
            continue
        try:
            _graphql(
                DEQUEUE_MUTATION, f"dequeue #{number}", PostMergeWriteError, id=pr_id
            )
        except PostMergeWriteError as exc:
            failed.append(str(exc))
            continue
        if dequeued is not None:
            dequeued.append(number)
    if failed:
        raise PostMergeWriteError("; ".join(failed))
    return unknown


# The pinned-head record: an identity-authored comment the wrapper posts on the
# pull request immediately before it enqueues, so the read-back has a source no
# host stores.
PIN_RE = re.compile(r"^<!-- babysit-merge-pin sha=([0-9a-f]{40}) -->$")
PIN_QUERY = (
    "query PostMergePin($o:String!,$r:String!,$n:Int!,$c:String){repository(owner:$o,name:$r){"
    "pullRequest(number:$n){comments(first:100,after:$c){"
    "pageInfo{hasNextPage endCursor} nodes{"
    "author{__typename login} body lastEditedAt}}}}}"
)
# Comment pages the pin read walks: 3000 comments. A longer thread reads as
# no pin, which fails the read-back once the dispatch deadline passes.
PIN_PAGE_LIMIT = 30


def pin_comment(sha: str) -> str:
    return (
        f"<!-- babysit-merge-pin sha={sha} -->\n"
        f"The unattended merge path enqueued this pull request at head `{sha}`."
    )


def read_pin(repo: str, number: int, identity: str) -> str | None:
    """The head SHA the agent identity pinned for `number`: its newest pin
    comment, read through every comment page, or None when there is none,
    the thread runs past `PIN_PAGE_LIMIT` pages, or that comment was edited
    (anyone with write access can edit it)."""
    owner, name = _split_repo(repo)
    pins: list[dict[str, Any]] = []
    cursor: str | None = None
    for _ in range(PIN_PAGE_LIMIT):
        args = ["api", "graphql", "-f", f"query={PIN_QUERY}", "-f", f"o={owner}"]
        args += ["-f", f"r={name}", "-F", f"n={number}"]
        if cursor:
            args += ["-f", f"c={cursor}"]
        payload = _read(args, f"#{number} pin")
        if not is_json_object(payload) or payload.get("errors"):
            raise PostMergeReadError(f"#{number} pin: the response carried no data")
        pull = json_object(
            json_object(json_object(payload.get("data")).get("repository")).get(
                "pullRequest"
            )
        )
        page = json_object(pull.get("comments"))
        nodes, info = page.get("nodes"), json_object(page.get("pageInfo"))
        if not is_json_array(nodes) or not isinstance(info.get("hasNextPage"), bool):
            raise PostMergeReadError(f"#{number} pin: no comment page")
        pins += [
            node
            for node in map(json_object, nodes)
            if _actor_key(node.get("author")) == _login_key(identity)
            and PIN_RE.match(_first_line(node.get("body")))
        ]
        cursor = info.get("endCursor")
        if not info["hasNextPage"]:
            break
        if not isinstance(cursor, str) or not cursor:
            raise PostMergeReadError(f"#{number} pin: a next page with no cursor")
    else:
        return None
    if not pins or pins[-1].get("lastEditedAt"):
        return None
    match = PIN_RE.match(_first_line(pins[-1].get("body")))
    return match[1] if match else None


def pin_reader(repo: str, identity: str) -> Callable[[AutoMerge], str | None]:
    """`check()`'s `pinned_sha` callable: the identity's pin on each merge."""
    return lambda merge: read_pin(repo, merge.number, identity)


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


_QUARANTINE_RE = re.compile(r"<!-- post-merge-quarantine suite=(\S+) -->")


def _quarantined_suite(body: Any) -> str | None:
    """The suite a quarantine issue's first line names, or None."""
    match = _QUARANTINE_RE.fullmatch(_first_line(body))
    return match[1] if match and _SUITE_RE.fullmatch(match[1]) else None


def _issue_body(failure: Failure, also: Iterable[AutoMerge] = ()) -> str:
    merge = failure.merge
    others = ", ".join(f"#{m.number} (`{m.merge_commit}`)" for m in also)
    return "\n".join(
        [
            failure.marker,
            "",
            f"The post-merge check found a `{failure.signal}` failure after an unattended merge. The",
            "unattended merge path stays at rung off while any demotion record is open. Fix main",
            "first, then close every open demotion record directly (not through a pull request's",
            "closing keyword); a new sighting of the same failure reopens its record.",
            "",
            f"- Pull request: {merge.url or f'#{merge.number}'}",
            f"- Merge commit: `{merge.merge_commit}`",
            f"- Failing run: {failure.run_url or 'none'}",
            f"- Detail: {failure.detail}",
            *(
                [
                    f"- Also charged by this run: {others}",
                    "",
                    "A human reads the failing suites in the run above, picks the merge responsible,",
                    "and reverts that one.",
                ]
                if others
                else [
                    "",
                    "To revert the merge, a human runs:",
                    "",
                    "```sh",
                    f"git revert {merge.merge_commit}",
                    "```",
                ]
            ),
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


def _same_run(failure: Failure, body: Any) -> bool:
    """Whether a demotion record names the same failing run, any attempt. The
    alert workflow keys its marker on the run's head SHA and this check on the
    merge commit, so one red run would otherwise get a record from each filer.
    The alert's post-merge-failure record never holds the gate, so it is not
    this failure's record."""
    if not failure.run_url or "/attempts/" not in failure.run_url:
        return False
    if not _first_line(body).startswith(policy.DEMOTION_MARKER):
        return False
    prefix = f"- Failing run: {failure.run_url.rsplit('/attempts/', 1)[0]}/attempts/"
    return any(line.startswith(prefix) for line in _lines(body))


def _codeowners_pattern(pattern: str) -> re.Pattern[str]:
    """A CODEOWNERS pattern as a regex over a repository path, with
    gitignore's rules: a leading or inner `/` anchors it at the root, `**`
    spans directories, `*` and `?` do not, and a pattern also matches every
    path under a directory it names."""
    anchored = "/" in pattern.rstrip("/")
    body = pattern.strip("/")
    out = ""
    i = 0
    while i < len(body):
        if body.startswith("**", i):
            out += ".*"
            i += 2
        elif body[i] == "*":
            out += "[^/]*"
            i += 1
        elif body[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(body[i])
            i += 1
    return re.compile(("" if anchored else "(?:.*/)?") + out + "(?:/.*)?")


def suite_owner(text: str, suite: str) -> str | None:
    """The first user login the last CODEOWNERS rule matching `suite`
    names, or None: no rule matches, the rule names no owner, or only teams
    and emails, which an issue cannot be assigned to."""
    owners: list[str] | None = None
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        pattern, *names = line.split()
        if _codeowners_pattern(pattern).fullmatch(suite):
            owners = names
    return next(
        (o[1:] for o in owners or () if o.startswith("@") and "/" not in o), None
    )


def _codeowners(owner: str, name: str, sha: str) -> str:
    """The CODEOWNERS file GitHub reads at `sha`, or "" when none reads."""
    for path in CODEOWNERS_PATHS:
        try:
            proc = gh_capture(
                [
                    "api",
                    "-H",
                    "Accept: application/vnd.github.raw+json",
                    f"repos/{owner}/{name}/contents/{path}?ref={sha}",
                ]
            )
        except (RuntimeError, ValueError, OSError):
            return ""
        if proc.returncode == 0:
            return proc.stdout or ""
    return ""


def _quarantine_body(q: Quarantine, branch: str, days: int) -> str:
    return "\n".join(
        [
            quarantine_marker(q.suite),
            "",
            f"The suite `{q.suite}` failed on {branch} outside the affected set of the",
            "merges since the last green full run, so no merge caused it and it demotes",
            "nothing. It is quarantined: it keeps running, and while this issue is open its",
            f"failures demote no unattended merge, for at most {days} days from when this",
            "issue was filed (`merge.quarantine-days`); after that they demote again. Fix",
            "the suite, then close this issue.",
            "",
            f"- Suite: `{q.suite}`",
            f"- Failing run: {q.run_url}",
            f"- Main at the failing run: `{q.sha}`",
            "",
            BORN_TRIAGED,
        ]
    )


def file_quarantines(
    repo: str,
    quarantines: Iterable[Quarantine],
    *,
    agent_identity: str,
    branch: str,
    days: int,
    report: dict[str, Any],
    label: str | None = None,
) -> None:
    """File one quarantine issue per suite with no open one (needs-human,
    assigned to the suite's CODEOWNERS user when a rule names one), or
    comment each new sighting on the open one. Only the filers' issues and
    comments count. Appends issue numbers to `report["issues"]` and
    `report["comments"]`; raises `PostMergeReadError` or
    `PostMergeWriteError`."""
    owner, name = _split_repo(repo)
    filers = (agent_identity, *DEMOTION_FILERS)
    keys = {_login_key(f) for f in filers}
    open_issues: dict[str, dict[str, Any]] = {}
    for issue in _demotion_issues(owner, name, filers):
        suite = _quarantined_suite(issue.get("body"))
        if suite is not None and issue.get("state") == "open":
            open_issues.setdefault(suite, issue)
    role_label = label or _role_label(owner, name)
    codeowners: dict[str, str] = {}
    for q in quarantines:
        if not _SUITE_RE.fullmatch(q.suite):
            continue
        issue = open_issues.get(q.suite)
        if issue is None:
            if q.sha not in codeowners:
                codeowners[q.sha] = _codeowners(owner, name, q.sha)
            assignee = suite_owner(codeowners[q.sha], q.suite)
            body = _quarantine_body(q, branch, days)
            args = [
                "api",
                "-X",
                "POST",
                f"repos/{owner}/{name}/issues",
                "-f",
                f"title=Quarantined suite fails on {branch}: {q.suite}",
                "-f",
                f"body={body}",
                "-f",
                f"labels[]={role_label}",
            ]
            try:
                filed = _write(
                    [*args, *(["-f", f"assignees[]={assignee}"] if assignee else [])],
                    f"file the quarantine issue for {q.suite}",
                )
            except PostMergeWriteError:
                if not assignee:
                    raise
                # An owner the repository cannot assign: file it unassigned.
                filed = _write(args, f"file the quarantine issue for {q.suite}")
            number = json_object(filed).get("number")
            if not isinstance(number, int):
                raise PostMergeWriteError(
                    "the filed quarantine issue carried no number"
                )
            report["issues"].append(number)
            open_issues[q.suite] = {"number": number, "body": body, "notes": []}
            continue
        number = issue.get("number")
        if "notes" not in issue:
            issue["notes"] = [
                c.get("body")
                for c in _paginated(
                    f"repos/{owner}/{name}/issues/{number}/comments?per_page=100",
                    f"#{number} comments",
                )
                if _login_key(json_object(c.get("user")).get("login")) in keys
            ]
        note = f"{QUARANTINE_NOTE}{q.run_url}"
        if f"- Failing run: {q.run_url}" in _lines(issue.get("body")) or any(
            note in _lines(b) for b in issue["notes"]
        ):
            continue
        _write(
            [
                "api",
                "-X",
                "POST",
                f"repos/{owner}/{name}/issues/{number}/comments",
                "-f",
                f"body={note}",
            ],
            f"comment on #{number}",
        )
        report["comments"].append(number)
        issue["notes"].append(note)


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
    failing run, or comment on the existing one, also found by its failing run (reopening it first when closed and the sighting
    is new; only the filers' own comments count as a prior sighting), then
    record the number of new issues as
    `demotion_events`. Each step runs even when an earlier one failed; errors are
    listed in the report. No failure, no write."""
    report: dict[str, Any] = {
        "dequeued": [],
        "issues": [],
        "comments": [],
        "reopened": [],
        "quarantine": {"issues": [], "comments": []},
        "telemetry": {"demotion_events": 0},
        "errors": [],
    }
    owner, name = _split_repo(repo)
    if verdict.quarantines:
        try:
            file_quarantines(
                repo,
                verdict.quarantines,
                agent_identity=agent_identity,
                branch=branch or verdict.branch or "the default branch",
                days=policy.read_config_at(
                    repo, verdict.quarantines[0].sha
                ).quarantine_days,
                report=report["quarantine"],
                label=label,
            )
        except (PostMergeReadError, PostMergeWriteError, policy.PolicyReadError) as exc:
            report["errors"].append(f"quarantine issue: {exc}")
    if not verdict.failures:
        return report
    try:
        # The queue is the judged branch's unless the caller names another.
        queue_branch = branch or verdict.branch
        if not queue_branch:
            raise PostMergeReadError("no branch to read the merge queue of")
        unknown = dequeue_identity_entries(
            repo, queue_branch, agent_identity, dequeued=report["dequeued"]
        )
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
                (
                    i
                    for i in existing
                    if _first_line(i.get("body")) == failure.marker
                    or _same_run(failure, i.get("body"))
                ),
                None,
            )
            if match is None:
                # The record names every merge this run charges; those merges
                # then find it by run below.
                also = [
                    f.merge
                    for f in verdict.failures
                    if f.run_url
                    and f.run_url == failure.run_url
                    and f.merge.number != failure.merge.number
                ]
                body = _issue_body(failure, {m.number: m for m in also}.values())
                issue = _write(
                    [
                        "api",
                        "-X",
                        "POST",
                        f"repos/{owner}/{name}/issues",
                        "-f",
                        f"title=Post-merge {failure.signal} failure after #{failure.merge.number}: unattended merging demoted",
                        "-f",
                        f"body={body}",
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
                    "body": body,
                }
                # A later merge charged by the same run finds it by run, as a
                # later pass would.
                existing.append(records[failure.marker])
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


def verdict_exit(verdict: PostMergeVerdict) -> int:
    """3 unreadable, 1 a failure, 5 an auto-merge not yet verified, else 0:
    only 0 lets a merge proceed, so code, not prose, holds the lane."""
    if not verdict.readable:
        return EXIT_UNREADABLE
    if verdict.failures:
        return EXIT_FAILURE
    if any(not state.verified for state in verdict.merges):
        return EXIT_UNVERIFIED
    return 0


def default_floor(
    repo: str, identity: str, self_logins: Collection[str]
) -> tuple[datetime, dict[str, Any]]:
    """The merge gate's floor at the default branch head
    (`babysit_merge_policy.merged_since_floor`), and what it was read from:
    the head, its newest pipeline-config commit and the demotion record
    (`shared` in the report, `read_shared`). Raises `PolicyReadError`."""
    _, head = policy._default_branch_head(repo)
    config = policy.newest_config_commit(repo, head)
    demotion = policy.read_demotion(
        repo, agent_identity=identity, self_logins=self_logins
    )
    floor = policy.merged_since_floor(repo, head, demotion)
    times = (demotion.newest_created, demotion.cleared_at)
    newest, cleared = (t.isoformat() if t else None for t in times)
    return floor, {
        "mainSha": head,
        "configSha": config,
        "demotion": {
            "active": demotion.active,
            "reason": demotion.reason,
            "records": list(demotion.records),
            "newestCreated": newest,
            "clearedAt": cleared,
        },
    }


def gate_from_report(report: dict[str, Any]) -> policy.PostMergeGate:
    """The merge gate's view of a verdict's `report()`: a refusal unless ok,
    and the merges it verified. One derivation for a fresh verdict and a
    shared one, so both decide alike."""
    ok = report.get("ok") is True
    refusal = None
    if not ok:
        refusal = report.get("reason") or "failure:" + ",".join(
            f"{f.get('signal')}#{f.get('number')}"
            for f in map(json_object, json_array(report.get("failures")))
        )
    verified = frozenset(
        m.get("number")
        for m in map(json_object, json_array(report.get("autoMerges")))
        if ok and m.get("verified") is True
    )
    return policy.PostMergeGate(
        refusal, report, lambda merge: getattr(merge, "number", None) in verified
    )


def read_shared(path: str) -> policy.SharedPostMerge | None:
    """The run's shared answer from this script's own report at `path`, or
    None when it is missing, malformed, unreadable as a verdict, or has no
    `shared` binding (a `--since` or `--branch` run)."""
    try:
        with open(path, encoding="utf-8") as handle:
            payload = json_object(json.load(handle))
        shared = json_object(payload.get("shared"))
        record = json_object(shared.get("demotion"))
        times = [record.get("newestCreated"), record.get("clearedAt")]
        newest, cleared = (None if t is None else policy._time(t) for t in times)
        records = json_array(record.get("records"))
        selves = json_array(shared.get("selfLogins"))
        fields = (
            shared.get("mainSha"),
            shared.get("configSha"),
            shared.get("identity"),
            record.get("reason"),
        )
        if not (
            payload.get("readable") is True
            and all(isinstance(r, int) for r in records)
            and all(isinstance(s, str) for s in selves)
            and isinstance(record.get("active"), bool)
            and isinstance(shared.get("laneMergesOnly"), bool)
            and policy.SHA_RE.fullmatch(str(fields[0]))
            and policy.SHA_RE.fullmatch(str(fields[1]))
            and isinstance(fields[2], str)
            and fields[2]
            and (fields[3] is None or isinstance(fields[3], str))
        ):
            return None
        demotion = policy.Demotion(
            record["active"], fields[3], tuple(records), newest, cleared
        )
        report = {k: v for k, v in payload.items() if k not in ("since", "shared")}
        return policy.SharedPostMerge(
            main_sha=fields[0],
            config_sha=fields[1],
            identity=fields[2],
            self_logins=frozenset(selves),
            lane_merges_only=shared["laneMergesOnly"],
            computed_at=policy._time(shared.get("computedAt")),
            demotion=demotion,
            floor=policy._time(payload.get("since")),
            gate=gate_from_report(report),
        )
    except (OSError, ValueError, policy.PolicyReadError):
        return None


def write_shared(path: str, shared: policy.SharedPostMerge) -> bool:
    """Replace the report at `path` with `shared` in this script's schema, so
    the next candidate's `read_shared` reuses a gate's recompute. A temp file
    in the same directory, then `os.replace`: a reader sees the old file or
    the new one, never part of one. The pr-merge job runs its candidates one
    after another, so there is no concurrent writer. Best effort: a failure is
    logged, the old file stays, and the caller's verdict stands."""
    demotion = shared.demotion
    times = (demotion.newest_created, demotion.cleared_at)
    newest, cleared = (t.isoformat() if t else None for t in times)
    payload = {
        **shared.gate.report,
        "since": shared.floor.isoformat(),
        "shared": {
            "mainSha": shared.main_sha,
            "configSha": shared.config_sha,
            "demotion": {
                "active": demotion.active,
                "reason": demotion.reason,
                "records": list(demotion.records),
                "newestCreated": newest,
                "clearedAt": cleared,
            },
            "identity": shared.identity,
            "selfLogins": sorted(shared.self_logins),
            "laneMergesOnly": shared.lane_merges_only,
            "computedAt": shared.computed_at.isoformat(),
        },
    }
    tmp: Path | None = None
    try:
        target = Path(path)
        tmp = target.with_name(f"{target.name}.{os.getpid()}.tmp")
        tmp.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        os.replace(tmp, target)
    except (OSError, TypeError, ValueError) as exc:
        print(f"post-merge answer not written to {path}: {exc}", file=sys.stderr)
        if tmp is not None:
            with contextlib.suppress(OSError):
                tmp.unlink(missing_ok=True)
        return False
    return True


def _since(value: str) -> datetime:
    parsed = datetime.fromisoformat(value)
    if parsed.utcoffset() is None:
        raise argparse.ArgumentTypeError("--since needs a timezone offset")
    return parsed


def _preflight(repo: str, identity: str | None, self_logins: Collection[str]) -> int:
    """The merge gate's identity rule and credential chokepoint alone: a lane
    writes nothing unless both pass. With no identity given, the one the
    repository configures on its default branch is checked (push-branch.sh's
    lane path). Pushes are bound to the identity at push time by
    scripts/lane-push.sh, not here."""
    report: dict[str, Any]
    if identity is None:
        try:
            identity = policy.resolve(repo).agent_identity
        except policy.PolicyReadError as exc:
            report = {"ok": False, "error": f"config-unreadable: {exc}"}
            json.dump(report, sys.stdout, indent=2)
            sys.stdout.write("\n")
            return 2
    try:
        acting = policy.read_acting_login()
    except policy.PolicyReadError:
        acting = None
    resolved = policy.resolve_identity(identity, acting, self_logins)
    refusal = resolved.reason
    if refusal is None and resolved.login:
        credentials = policy.credential_refusal(resolved.login)
        refusal = f"credentials:{credentials}" if credentials else None
    report = (
        {"ok": False, "error": refusal}
        if refusal
        else {"ok": True, "identity": resolved.login}
    )
    json.dump(report, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 2 if refusal else 0


def _judge_run(args: argparse.Namespace) -> int:
    """`--judge-run`: which of one red full run's newly failing checks demote
    (`_Context.demoting`), with the identity read from the default branch
    when not given. Exit 0 none, 1 some, 2 a refused identity or no check,
    3 unreadable, 4 a quarantine write failed. Writes only with
    --file-quarantine."""
    report: dict[str, Any] = {"ok": False}
    try:
        with open(args.checks_file, encoding="utf-8") as handle:
            checks = frozenset(line.strip() for line in handle if line.strip())
        identity = args.agent_identity or policy.resolve(args.repo).agent_identity
        refusal = policy.resolve_identity(identity, identity, args.self_login).reason
        if refusal or not identity or not checks:
            report["error"] = refusal or "no agent identity or no checks"
            code = 2
        else:
            owner, name = _split_repo(args.repo)
            run = Run.from_api(
                _read(
                    [
                        "api",
                        f"repos/{owner}/{name}/actions/runs/{args.judge_run}"
                        f"/attempts/{args.attempt}",
                    ],
                    f"run {args.judge_run}",
                )
            )
            ctx = _Context(
                owner, name, _login_key(identity), branch=run.head_branch or ""
            )
            demoting = ctx.demoting(run, args.attempt, checks)
            quarantines = list(ctx.quarantines.values())
            report = {
                "ok": not demoting,
                "run": f"{run.url}/attempts/{args.attempt}",
                "demoting": sorted(demoting),
                "quarantines": [
                    {"suite": q.suite, "run": q.run_url, "sha": q.sha}
                    for q in quarantines
                ],
            }
            code = EXIT_FAILURE if demoting else 0
            if args.file_quarantine and quarantines:
                report["quarantine"] = {"issues": [], "comments": []}
                try:
                    file_quarantines(
                        args.repo,
                        quarantines,
                        agent_identity=identity,
                        branch=ctx.branch,
                        days=ctx._quarantine_days(run.head_sha),
                        report=report["quarantine"],
                    )
                except (PostMergeReadError, PostMergeWriteError) as exc:
                    report["error"] = f"quarantine issue: {exc}"
                    code = code or EXIT_WRITE_FAILED
    except (OSError, PostMergeReadError, policy.PolicyReadError) as exc:
        report = {"ok": False, "error": f"unreadable: {exc}"}
        code = EXIT_UNREADABLE
    json.dump(report, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return code


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="babysit_postmerge.py",
        description="Check every unattended merge since a floor; read-only unless --remediate.",
        allow_abbrev=False,
    )
    parser.add_argument("--repo", required=True, help="owner/repo")
    parser.add_argument(
        "--agent-identity",
        help=(
            "the merge.agent-identity login (required except with --preflight, "
            "which reads it from the default branch when omitted)"
        ),
    )
    parser.add_argument(
        "--since",
        type=_since,
        help=(
            "ISO 8601 floor with an offset (default: the floor the merge gate "
            "uses, the later of the enabling config commit and the newest human "
            "close of a demotion record)"
        ),
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
        "--lane-merges-only",
        action="store_true",
        help=(
            "judge only merges the agent identity enqueued (the pr-merge lane); "
            "another App's or a person's merge is not the lane's"
        ),
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--remediate",
        action="store_true",
        help=(
            "trigger the one attribution re-run, dispatch a full run when no run covers an "
            "unverified merge, dequeue, file the demotion issue (the only writes)"
        ),
    )
    mode.add_argument(
        "--judge-run",
        type=int,
        metavar="RUN_ID",
        help=(
            "judge one red full run's newly failing checks (--checks-file, one "
            "per line) by suite: exit 0 when none demotes, 1 when one does "
            "(post-merge-demotion-alert.yml); read-only unless --file-quarantine"
        ),
    )
    parser.add_argument("--attempt", type=int, default=1, help="with --judge-run")
    parser.add_argument("--checks-file", help="with --judge-run")
    parser.add_argument(
        "--file-quarantine",
        action="store_true",
        help="with --judge-run: file or comment on each excused suite's quarantine issue",
    )
    mode.add_argument(
        "--preflight",
        action="store_true",
        help=(
            "check only that the session acts as the identity and holds no "
            "other account (the lane identity gate, run every cycle); exit 0 or 2"
        ),
    )
    args = parser.parse_args(argv)

    if args.preflight:
        return _preflight(args.repo, args.agent_identity, args.self_login)
    if args.file_quarantine and args.judge_run is None:
        parser.error("--file-quarantine needs --judge-run")
    if args.judge_run is not None:
        if not args.checks_file:
            parser.error("--judge-run needs --checks-file")
        return _judge_run(args)
    if args.agent_identity is None:
        parser.error(
            "--agent-identity is required except with --preflight or --judge-run"
        )

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

    is_human = _default_is_human(args.repo, args.agent_identity, args.self_login)
    since = args.since
    shared: dict[str, Any] | None = None
    if since is None:
        computed_at = datetime.now(UTC)
        try:
            since, read_from = default_floor(
                args.repo, args.agent_identity, args.self_login
            )
            # The merge gate's `--postmerge-result` reuses this report only
            # for the default branch it judges (`policy.shared_refusal`).
            if args.branch is None and not args.remediate:
                shared = {
                    **read_from,
                    "identity": args.agent_identity,
                    "selfLogins": list(args.self_login),
                    "laneMergesOnly": args.lane_merges_only,
                    "computedAt": computed_at.isoformat(),
                }
        except policy.PolicyReadError as exc:
            json.dump({"ok": False, "error": f"floor unreadable: {exc}"}, sys.stdout)
            sys.stdout.write("\n")
            return EXIT_UNREADABLE
    verdict = check(
        args.repo,
        agent_identity=args.agent_identity,
        is_human=is_human,
        merged_since=since,
        branch=args.branch,
        pinned_sha=pin_reader(args.repo, args.agent_identity),
        lane_merges_only=args.lane_merges_only,
    )
    report = verdict.report()
    report["since"] = since.isoformat()
    if shared is not None:
        report["shared"] = shared
    code = verdict_exit(verdict)
    branch = verdict.branch
    if verdict.readable and not branch:
        # A readable verdict always names its branch; refuse before any write
        # rather than dispatch or dequeue on an unknown ref.
        report["reason"] = "branch-unknown"
        code = EXIT_UNREADABLE
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
            code = EXIT_WRITE_FAILED
    json.dump(report, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return code


if __name__ == "__main__":
    sys.exit(main())

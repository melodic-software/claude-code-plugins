"""Per-lane AI review evidence, bound to the lane's workflow runs and the
pinned head SHA.

A green review check alone proves nothing: a lane has concluded success
with no review done. `bind()` counts a lane as reviewed only when its newest
workflow run on the pinned head succeeded on an allowed attempt, the lane
job left exactly one completion record for that head, an incremental or
no-change record leads back to a whole review, and the lane's
reviewed-head marker names the head. Anything doubtful is unbound; the
function never raises.

Inputs are raw GitHub API shapes the caller collects for one pull request:

- `runs`: the caller workflow runs of both lanes on this pull request (the
  `actions/workflows/{file}/runs` listing), each with an `attempts` list
  (`actions/runs/{id}/attempts/{n}`), each attempt with its `jobs`
  (`.../attempts/{n}/jobs`), each job with its check run's `annotations`
  (`check-runs/{job id}/annotations`).
- `comments`: the pull request's issue comments (REST).
- `threads`: `babysit_gh.fetch_review_threads(..., include_resolved=True)`,
  or None when they could not be read.
- `is_human`: the merge policy's test of one GraphQL actor (or None).
- `head_file`: reads a file at the pinned head, given its path and the
  commit a thread was raised on: its text, None when that file was deleted
  since, raising when neither is proven.

The record format is the lane producer's (ci-workflows
`.github/workflows/pr-review.yml`, "Report the review status" and "Record
the reviewed head").
"""

from __future__ import annotations

import re
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from babysit_risk import LaneEvidence

# Lane id -> (caller workflow path, lane job name suffix). Fixed in code: a
# weaker table could only come from a file a pull request can edit.
LANES: dict[str, tuple[str, str]] = {
    "claude-review": (".github/workflows/pr-review-hosted.yml", "claude-review-status"),
    "claude-security-review": (
        ".github/workflows/pr-review-security-hosted.yml",
        "security-review",
    ),
}

RECORD_TITLE = "claude-lane-review-complete"
_SHA = r"[0-9a-f]{40}"
_COUNT = r"\d{1,6}"
RECORD_RE = re.compile(
    rf"^{RECORD_TITLE} lane=(?P<lane>[\w-]+) sha=(?P<sha>{_SHA}) "
    rf"(?:findings=(?P<n>{_COUNT}) inline=(?P<k>{_COUNT}) "
    rf"scope=(?:(?P<whole>whole)|incremental since=(?P<since>{_SHA}))"
    rf"|skip=no-change through=(?P<through>{_SHA})"
    rf"|skip=(?P<skip>[\w-]+))$"
)
SHA_RE = re.compile(rf"^{_SHA}$")
HUNK_HEADER_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
# The wrapper re-runs a review only after a usage-limit failure, once.
RATE_LIMIT_CLASS_RE = re.compile(r"\bclass=rate-limit\b")
MARKER_AUTHOR = "github-actions[bot]"
MARKER_RE = re.compile(
    rf"^<!-- claude-lane-reviewed-head lane=([\w-]+) sha=({_SHA}) -->$"
)
CLAUDE_APP_LOGINS = frozenset({"claude", "claude[bot]"})
LANE_TAG_RE = re.compile(r"^\s*`?claude-lane: ([\w-]+)`?\s*$", re.MULTILINE)
MAX_CHAIN = 100


@dataclass(frozen=True)
class _Record:
    sha: str
    findings: int | None = None
    inline: int | None = None
    whole: bool = False
    since: str | None = None  # incremental review base
    through: str | None = None  # no-change skip target
    skip: str | None = None  # any other skip
    completed: datetime | None = None  # when the lane job that left it completed


class Unbound(Exception):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


def bind(
    head_sha: str,
    runs: Sequence[Mapping[str, Any]],
    comments: Sequence[Mapping[str, Any]],
    threads: Sequence[Mapping[str, Any]] | None,
    *,
    is_human: Callable[[Any], bool],
    base_changed: bool = False,
    head_file: Callable[[str, str], str | None] | None = None,
) -> tuple[LaneEvidence, ...]:
    """Evidence for every lane in `LANES`, in that order.

    Caller contract (`babysit_gh.collect_lane_runs` meets it): list each lane
    workflow's runs by branch, with no `head_sha` filter, and keep those whose
    `pull_requests` name this pull request, so the earlier whole reviews an
    incremental chain leads back to are included. Read each run's attempt
    numbers from a fresh `GET actions/runs/{id}` taken after the listing, not
    from the listing's `run_attempt`, so a re-run that starts in between is
    seen. `is_human` takes one actor and must return False for the agent
    identity, the pull request's author and its head pushers. `base_changed`
    is True when the pull request was ever retargeted: the reviews read a
    diff against another base, so no lane binds.

    A lane binds only when every head its reviewed-head markers name still
    has a listed run: a deleted or expired run would drop its findings from
    the count, so it unbinds the lane rather than lowering the count.
    """
    try:
        if not isinstance(head_sha, str) or not SHA_RE.match(head_sha):
            raise Unbound("bad-head")
        if base_changed is not False:
            raise Unbound("base-retargeted")
        # Thread ids already standing for a recorded finding in some lane.
        # LANES order matters: claude-review claims first, so a doubtful
        # untagged thread leaves the count on the security lane.
        claimed: set[str] = set()
        return tuple(
            _bind_lane(
                lane, head_sha, runs, comments, threads, is_human, claimed, head_file
            )
            for lane in LANES
        )
    except Exception as exc:  # noqa: BLE001 - any doubt is unbound
        reason = exc.reason if isinstance(exc, Unbound) else "evidence-error"
        return tuple(LaneEvidence(lane, False, reason, None) for lane in LANES)


def _bind_lane(
    lane: str,
    head: str,
    runs: Sequence[Mapping[str, Any]],
    comments: Sequence[Mapping[str, Any]],
    threads: Sequence[Mapping[str, Any]] | None,
    is_human: Callable[[Any], bool],
    claimed: set[str],
    head_file: Callable[[str, str], str | None] | None,
) -> LaneEvidence:
    try:
        lane_runs = _lane_runs(lane, runs)
        reviewed, chain = _resolve(lane, head, lane_runs)
        _require_marker(lane, head, comments)
        _require_marked_runs(lane, lane_runs, comments)
        count, clears = _open_findings(
            lane, lane_runs, threads, is_human, claimed, reviewed, chain, head_file
        )
    except Unbound as exc:
        return LaneEvidence(lane, False, exc.reason, None)
    return LaneEvidence(lane, True, None, count, clears)


def _lane_runs(lane: str, runs: Sequence[Mapping[str, Any]]) -> list[Mapping[str, Any]]:
    path = LANES[lane][0]
    if not isinstance(runs, list | tuple):
        raise Unbound("evidence-error")
    selected = []
    for item in runs:
        if not isinstance(item, Mapping):
            raise Unbound("evidence-error")
        if item.get("path") != path or item.get("event") != "pull_request":
            continue
        if not isinstance(item.get("id"), int) or not isinstance(
            item.get("head_sha"), str
        ):
            raise Unbound("evidence-error")
        selected.append(item)
    return selected


def _resolve(
    lane: str, head: str, lane_runs: list[Mapping[str, Any]]
) -> tuple[str, list[_Record]]:
    """Require a bound run at `head` whose record leads back to a whole review,
    and return the head of the review that covers `head` with the chain of
    review records that covers it, newest first, back to the whole review.

    A no-change skip binds to the review it names, one hop; an incremental
    review needs every earlier link bound, back to a whole review. Each link
    is the newest run's latest attempt at its head (`_bound_record`).
    """
    rec = _bound_record(lane, head, lane_runs)
    seen = {head}
    if rec.skip is not None:
        raise Unbound("skip-not-no-change")
    if rec.through is not None:
        rec = _skip_target(lane, rec.through, lane_runs, seen)
    reviewed = rec.sha
    chain = [rec]
    for _ in range(MAX_CHAIN):
        if rec.whole:
            return reviewed, chain
        rec = _link(lane, rec.since, lane_runs, seen)  # type: ignore[arg-type]
        if rec.skip is not None:
            raise Unbound("incremental-gap")
        if rec.through is not None:
            rec = _skip_target(lane, rec.through, lane_runs, seen)
        chain.append(rec)
    raise Unbound("incremental-gap")


def _skip_target(
    lane: str, sha: str, lane_runs: list[Mapping[str, Any]], seen: set[str]
) -> _Record:
    rec = _link(lane, sha, lane_runs, seen)
    if rec.through is not None or rec.skip is not None:
        raise Unbound("skip-chain")
    return rec


def _link(
    lane: str, sha: str, lane_runs: list[Mapping[str, Any]], seen: set[str]
) -> _Record:
    """An earlier head in the chain; any failure to bind it is a gap."""
    if sha in seen:
        raise Unbound("incremental-gap")
    seen.add(sha)
    try:
        return _bound_record(lane, sha, lane_runs)
    except Unbound as exc:
        if exc.reason in {"count-inconsistent", "evidence-error", "evidence-missing"}:
            raise
        raise Unbound("incremental-gap") from exc


def _bound_record(lane: str, sha: str, lane_runs: list[Mapping[str, Any]]) -> _Record:
    at_sha = [item for item in lane_runs if item["head_sha"] == sha]
    if not at_sha:
        raise Unbound("no-run")
    newest = max(
        at_sha, key=lambda item: (str(item.get("created_at") or ""), item["id"])
    )
    if newest.get("status") != "completed" or newest.get("conclusion") != "success":
        raise Unbound("run-not-success")
    latest_n = newest.get("run_attempt")
    if not isinstance(latest_n, int) or isinstance(latest_n, bool) or latest_n < 1:
        raise Unbound("evidence-error")
    attempts = _attempts(newest)
    latest = attempts.get(latest_n)
    if latest is None:
        raise Unbound("evidence-missing")
    if max(attempts) != latest_n:
        # The listing predates a re-run the attempts already show.
        raise Unbound("evidence-error")
    if (
        latest.get("status") != "completed"
        or latest.get("conclusion") != "success"
        or latest.get("head_sha") != sha
    ):
        raise Unbound("run-not-success")
    if latest_n > 1:
        first = attempts.get(1)
        if latest_n > 2:
            raise Unbound("rerun-not-allowed")
        if first is None:
            raise Unbound("evidence-missing")
        if first.get("conclusion") != "failure" or not _rate_limited(
            _lane_job(lane, newest["id"], first)
        ):
            raise Unbound("rerun-not-allowed")
    job = _lane_job(lane, newest["id"], latest)
    if job.get("conclusion") != "success" or job.get("head_sha") != sha:
        raise Unbound("run-not-success")
    rec = _record(lane, sha, job)
    if rec is None:
        raise Unbound("no-record")
    if rec.findings is not None and rec.findings < rec.inline:  # type: ignore[operator]
        raise Unbound("count-inconsistent")
    return rec


def _attempts(item: Mapping[str, Any]) -> dict[int, Mapping[str, Any]]:
    attempts = item.get("attempts")
    if not isinstance(attempts, list | tuple):
        raise Unbound("evidence-missing")
    by_n: dict[int, Mapping[str, Any]] = {}
    for attempt in attempts:
        if not isinstance(attempt, Mapping):
            raise Unbound("evidence-error")
        n = attempt.get("run_attempt")
        if not isinstance(n, int) or n in by_n or attempt.get("id") != item["id"]:
            raise Unbound("evidence-error")
        by_n[n] = attempt
    return by_n


def _lane_job(lane: str, run_id: int, attempt: Mapping[str, Any]) -> Mapping[str, Any]:
    suffix = LANES[lane][1]
    jobs = attempt.get("jobs")
    if not isinstance(jobs, list | tuple):
        raise Unbound("evidence-missing")
    matches = [
        job
        for job in jobs
        if isinstance(job, Mapping)
        and isinstance(job.get("name"), str)
        and job["name"].rsplit(" / ", 1)[-1] == suffix
    ]
    if not matches:
        raise Unbound("no-lane-job" if jobs else "evidence-missing")
    if len(matches) > 1:
        raise Unbound("record-malformed")
    job = matches[0]
    if job.get("run_id") != run_id or job.get("run_attempt") != attempt.get(
        "run_attempt"
    ):
        raise Unbound("evidence-error")
    if not isinstance(job.get("annotations"), list | tuple):
        raise Unbound("evidence-missing")
    return job


def _rate_limited(job: Mapping[str, Any]) -> bool:
    return any(
        isinstance(a, Mapping)
        and a.get("annotation_level") == "failure"
        and RATE_LIMIT_CLASS_RE.search(str(a.get("message") or ""))
        for a in job["annotations"]
    )


def _record(lane: str, sha: str, job: Mapping[str, Any]) -> _Record | None:
    """The job's one completion record for `sha`, None when it left none."""
    found = [
        a
        for a in job["annotations"]
        if isinstance(a, Mapping) and a.get("title") == RECORD_TITLE
    ]
    if not found:
        return None
    if len(found) > 1 or found[0].get("annotation_level") != "notice":
        raise Unbound("record-malformed")
    match = RECORD_RE.match(str(found[0].get("message") or ""))
    if not match or match["lane"] != lane or match["sha"] != sha:
        raise Unbound("record-malformed")
    if match["skip"] is not None:
        return _Record(sha, skip=match["skip"])
    if match["through"] is not None:
        return _Record(sha, through=match["through"])
    return _Record(
        sha,
        findings=int(match["n"]),
        inline=int(match["k"]),
        whole=match["whole"] is not None,
        since=match["since"],
        completed=_time(job.get("completed_at")),
    )


def _require_marker(
    lane: str, head: str, comments: Sequence[Mapping[str, Any]]
) -> None:
    """The newest reviewed-head marker the lane job wrote must name `head`."""
    if not isinstance(comments, list | tuple):
        raise Unbound("evidence-error")
    newest: tuple[str, int, str] | None = None
    for comment in comments:
        if not isinstance(comment, Mapping):
            raise Unbound("evidence-error")
        user = comment.get("user")
        if not isinstance(user, Mapping) or user.get("login") != MARKER_AUTHOR:
            continue
        first_line = str(comment.get("body") or "").split("\n", 1)[0].rstrip("\r")
        match = MARKER_RE.match(first_line)
        if not match or match[1] != lane:
            continue
        key = (
            str(comment.get("created_at") or ""),
            int(comment.get("id") or 0),
            match[2],
        )
        if newest is None or key[:2] > newest[:2]:
            newest = key
    if newest is None or newest[2] != head:
        raise Unbound("no-marker")


def _require_marked_runs(
    lane: str,
    lane_runs: list[Mapping[str, Any]],
    comments: Sequence[Mapping[str, Any]],
) -> None:
    """Every head a reviewed-head marker of the lane names has a listed run, so
    no reviewed run's findings are missing from the count."""
    listed = {item["head_sha"] for item in lane_runs}
    for comment in comments:
        user = comment.get("user")
        if not isinstance(user, Mapping) or user.get("login") != MARKER_AUTHOR:
            continue
        first_line = str(comment.get("body") or "").split("\n", 1)[0].rstrip("\r")
        match = MARKER_RE.match(first_line)
        if match and match[1] == lane and match[2] not in listed:
            raise Unbound("run-missing")


def _open_findings(
    lane: str,
    lane_runs: list[Mapping[str, Any]],
    threads: Sequence[Mapping[str, Any]] | None,
    is_human: Callable[[Any], bool],
    claimed: set[str],
    reviewed: str,
    chain: Sequence[_Record],
    head_file: Callable[[str, str], str | None] | None = None,
) -> tuple[int, bool]:
    """Summary findings of the review chain covering the pinned head
    (`chain`, from `_resolve`), plus inline threads still open, plus inline
    findings of the chain whose thread is gone. A summary or thread-less
    inline finding from a review of an earlier head outside that chain is
    closed: the covering review no longer reports it. Reviews of one head (a
    reopen or a draft toggle re-runs a whole one) never supersede each other:
    a whole-review link counts the most findings any completed whole review
    of its head reported, and every link counts the most inline findings
    left without a thread by any review of its kind (whole or incremental)
    at its head. A link counts only reviews of its own kind at its head, so
    the other kind's thread-less inline findings at that head drop.

    A resolved thread is closed when:
    - a human resolved it;
    - the covering chain reports no finding at all and the thread was opened
      before the covering review's job completed, so that review read past it.
      A whole review of the head is a chain of one, so a clean whole review
      closes a thread whoever resolved it; an incremental review reads only
      what changed and never closes an unchanged thread this way. Closure is
      per lane: a security-lane (HIGH) thread needs the security lane's own
      clean whole review;
    - or GitHub marks it outdated, it was opened before the first review at
      `reviewed` (the head whose review covers the pinned head) started, and
      no line of its flagged range is left at the pinned head
      (`_line_changed`): a later review read the changed lines.
    Otherwise it stays open until a human resolves it: resolving a thread
    alone never closes it, so the reviewer clears a finding, not the agent
    that resolved it. A thread stands for a recorded inline finding only when
    it was opened inside that lane job's run, and it stands for one finding
    across both lanes (`claimed`), so neither an unrecorded review's thread
    nor the other lane's untagged thread hides a missing one.

    Also returns whether a clean whole review of `reviewed` would close every
    open finding: none is an unresolved thread, no completed review of
    `reviewed` reported a finding, and none of them was a whole review."""
    if threads is None:
        raise Unbound("threads-unread")
    # (job started, job completed, inline findings) per recorded attempt.
    windows: list[tuple[datetime | None, datetime | None, int]] = []
    # (head, whole review) per window, to count missing ones on the chain.
    kinds: list[tuple[str, bool]] = []
    # When the first review at `reviewed` started; unknown keeps every
    # thread's human test.
    first: datetime | None = None
    # Per head, the most (findings, summary findings) any completed whole
    # review of it reported.
    whole_max: dict[str, tuple[int, int]] = {}
    # Whether any review of `reviewed` was whole or reported a finding.
    head_spent = False
    for item in lane_runs:
        for attempt in _attempts(item).values():
            # A draft-skipped run has only the caller job and reviewed nothing.
            if (
                attempt.get("status") != "completed"
                or attempt.get("conclusion") == "skipped"
            ):
                continue
            job = _lane_job(lane, item["id"], attempt)
            rec = _record(lane, item["head_sha"], job)
            if rec is None or rec.findings is None:
                continue
            if rec.findings < rec.inline:  # type: ignore[operator]
                raise Unbound("count-inconsistent")
            if rec.whole:
                n, m = whole_max.get(rec.sha, (0, 0))
                whole_max[rec.sha] = (
                    max(n, rec.findings),
                    max(m, rec.findings - rec.inline),  # type: ignore[operator]
                )
            started = _time(job.get("started_at"))
            windows.append(
                (
                    started,
                    _time(job.get("completed_at")),
                    rec.inline,  # type: ignore[arg-type]
                )
            )
            kinds.append((rec.sha, rec.whole))
            if rec.sha == reviewed and (rec.whole or rec.findings > 0):
                head_spent = True
            if (
                item["head_sha"] == reviewed
                and started
                and (first is None or started < first)
            ):
                first = started
    counts = [
        whole_max.get(rec.sha, (0, 0))
        if rec.whole
        else (rec.findings, rec.findings - rec.inline)  # type: ignore[operator]
        for rec in chain
    ]
    summary = sum(m for _, m in counts)
    cleared = all(n == 0 for n, _ in counts)
    # The covering review read only threads opened before its job completed.
    read_through = chain[0].completed
    if not isinstance(threads, list | tuple):
        raise Unbound("evidence-error")
    covered = [0] * len(windows)
    open_threads = 0
    unresolved = 0
    for thread in threads:
        if not isinstance(thread, Mapping):
            raise Unbound("evidence-error")
        if not _lane_thread(lane, thread):
            continue
        created = _time(thread["comments"][0].get("createdAt"))
        thread_id = thread.get("id")
        if created and isinstance(thread_id, str) and thread_id not in claimed:
            for i, (start, end, k) in enumerate(windows):
                if start and end and start <= created <= end and covered[i] < k:
                    covered[i] += 1
                    claimed.add(thread_id)
                    break
        if thread.get("isResolved") is not True:
            open_threads += 1
            unresolved += 1
        elif cleared and read_through and created and created < read_through:
            continue
        elif not (
            thread.get("isOutdated") is True
            and first
            and created
            and created < first
            and _line_changed(thread, head_file)
        ) and not is_human(thread.get("resolvedBy")):
            open_threads += 1
    # Inline findings with no thread left, counted like summary findings:
    # per chain link, the most any review of its kind at its head left.
    gone = [max(k - n, 0) for (_, _, k), n in zip(windows, covered)]
    missing = sum(
        max(
            (g for g, kind in zip(gone, kinds) if kind == (rec.sha, rec.whole)),
            default=0,
        )
        for rec in chain
    )
    count = summary + open_threads + missing
    return count, count > 0 and not unresolved and not head_spent


def _line_changed(
    thread: Mapping[str, Any], head_file: Callable[[str, str], str | None] | None
) -> bool:
    """Whether every non-blank line of the range a thread flagged
    (`originalStartLine`..`originalLine` on the new side, read from the end of
    its diff hunk) is absent from its file at the pinned head, or the file was
    deleted. No reader, a range the hunk does not end on, an all-blank range
    or anything unreadable is no evidence."""
    if head_file is None:
        return False
    try:
        first = thread["comments"][0]
        path, hunk = first.get("path"), first.get("diffHunk")
        oid = (first.get("originalCommit") or {}).get("oid")
        end = thread.get("originalLine")
        start = thread.get("originalStartLine")
        start = end if start is None else start
        if not (
            isinstance(path, str)
            and path
            and isinstance(hunk, str)
            and isinstance(oid, str)
            and SHA_RE.match(oid)
            and type(start) is int
            and type(end) is int
            and 1 <= start <= end
        ):
            return False
        rows = [row.rstrip("\r") for row in hunk.rstrip("\n").split("\n")]
        header = HUNK_HEADER_RE.match(rows[0])
        if not header or rows[-1][:1] not in ("+", " "):
            return False
        number, flagged = int(header[1]), []
        for row in rows[1:]:
            if row[:1] in ("+", " "):
                if start <= number:
                    flagged.append(row[1:])
                number += 1
        # The hunk must end on the range's last line and hold all of it.
        if number - 1 != end or len(flagged) != end - start + 1:
            return False
        flagged = [line for line in flagged if line.strip()]
        if not flagged:
            return False
        text = head_file(path, oid)
        if text is None:
            return True
        if not isinstance(text, str):
            return False
        present = {line.rstrip("\r") for line in text.split("\n")}
        return not any(line in present for line in flagged)
    except Exception:  # noqa: BLE001 - unreadable is no evidence
        return False


def _time(value: Any) -> datetime | None:
    """An aware timestamp, or None when absent or unreadable."""
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else None


def _lane_thread(lane: str, thread: Mapping[str, Any]) -> bool:
    """A thread the Claude App opened that is untagged or tagged for `lane`."""
    comments = thread.get("comments")
    if not isinstance(comments, list | tuple):
        raise Unbound("evidence-error")
    if not comments:
        return False
    first = comments[0]
    if not isinstance(first, Mapping):
        raise Unbound("evidence-error")
    author = first.get("author")
    if not isinstance(author, Mapping):
        return False
    if (
        author.get("__typename") != "Bot"
        or author.get("login") not in CLAUDE_APP_LOGINS
    ):
        return False
    tag = LANE_TAG_RE.search(str(first.get("body") or ""))
    return tag is None or tag[1] == lane

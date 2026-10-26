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
`.github/workflows/pr-review-cli.yml`, and `pr-review.yml` for older runs).
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

# What a pull request's own checkout can feed or forge for its own review:
# its workflows (a pull_request event runs the head's copy of the callers, and
# any workflow it adds can post a github-actions[bot] reviewed-head marker),
# Claude Code project config and instruction files at any depth, the criteria the lane skills read from the checkout (REVIEW.md,
# the standards index, the instruction exception register, the
# untrusted-content contract), the lane's input directory .claude-lane/ (the
# code lane falls back to a context file there), and .gitattributes, which can
# hide a hunk from the lane's `git diff`. The callers run every local action
# from a checkout of main and the reusable runs its composites from its own
# repository, so the rest of .github/ feeds no review. A pull request that
# changes any listed path may have changed its own review, so its records
# prove no review by the default branch's lane. plugins/review/ is not listed:
# the reusable pr-review-cli.yml stages the review plugin from
# claude-code-plugins' default-branch tip, never the head, and
# scripts/ci-review-plugin-source.test.sh fails if a caller stops calling it
# pinned to a SHA or passes it a plugin path.
LANE_SOURCE_PREFIXES = (
    ".github/workflows/",
    "docs/standards/",
    "docs/conventions/instruction-exception-register/",
    "docs/conventions/untrusted-content/",
    ".claude-lane/",
)
LANE_SOURCE_SEGMENT = ".claude"
LANE_SOURCE_NAMES = (
    ".mcp.json",
    "CLAUDE.md",
    "CLAUDE.local.md",
    "AGENTS.md",
    "REVIEW.md",
    ".gitattributes",
)

RECORD_TITLE = "claude-lane-review-complete"
_SHA = r"[0-9a-f]{40}"
_COUNT = r"\d{1,6}"
RECORD_RE = re.compile(
    rf"^{RECORD_TITLE} lane=(?P<lane>[\w-]+) sha=(?P<sha>{_SHA}) "
    rf"(?:findings=(?P<n>{_COUNT}) inline=(?P<k>{_COUNT}) "
    rf"scope=(?:(?P<whole>whole)|incremental since=(?P<since>{_SHA}))"
    rf"|skip=no-change through=(?P<through>{_SHA})"
    rf"|skip=(?P<skip>[\w-]+))"
    # The subscription leg's review (ci-workflows pr-review-cli.yml).
    rf"(?: account=fallback)?$"
)
SHA_RE = re.compile(rf"^{_SHA}$")
HUNK_HEADER_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
# The reconciler re-runs any failed lane run once; attempt 2 binds only when
# attempt 1 failed on a usage limit.
RATE_LIMIT_CLASS_RE = re.compile(r"\bclass=rate-limit\b")
# Or on a rejected Claude credential: this lane's publish-review failure line
# (ci-workflows publish.cjs `fail`) with class `auth`. Like a usage limit,
# attempt 1 then left no verdict, so a re-run cannot trade one review for
# another. It binds a re-run but does not start one (rate_limited), since a
# re-run before the secret is fixed would spend the one allowed attempt. A
# spent key needs no entry: publish.cjs reports it as `rate-limit`.
AUTH_FAILURE_RE = re.compile(r"(?P<lane>[\w-]+): failure-class=auth: ")
# Or when the review's own post hit GitHub's API rate limit: the message opens
# with this lane's publish-review failure line (ci-workflows publish.cjs `fail`)
# whose detail, the request error's message, opens with GitHub's primary or
# secondary rate-limit text
# (https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).
# Any other publish failure stays refused, so a re-run cannot hide one.
PUBLISH_RATE_LIMIT_RE = re.compile(
    r"(?P<lane>[\w-]+): failure-class=publish-failed: [^(\n]*"
    r"\((?:API rate limit exceeded|You have exceeded a secondary rate limit)\b"
)
# Or when a kill switch stopped attempt 1 before the review started: the
# caller's `kill-switch` job succeeded and its `Report the kill switch` step
# wrote this lane's notice, whose `if` is the negation of the `proceed` output
# the lane job needs, and attempt 1 has no lane job. Attempt 1 then left no
# verdict. The step's text comes from the switch values only, and a head that
# edits a caller to forge it unbinds through `lane_source`. Like `auth`, it
# binds a re-run but does not start one: the gate cannot read the switch.
KILL_SWITCH_JOB = "kill-switch"
KILL_SWITCH_NOTICE_RE = {
    "claude-review": re.compile(r"a kill switch stops this review \("),
    "claude-security-review": re.compile(
        r"a kill switch stops this security review \("
    ),
}
MARKER_AUTHOR = "github-actions[bot]"
MARKER_RE = re.compile(
    rf"^<!-- claude-lane-reviewed-head lane=([\w-]+) sha=({_SHA}) -->$"
)
CLAUDE_APP_LOGINS = frozenset({"claude", "claude[bot]"})
LANE_TAG_RE = re.compile(r"^\s*`?claude-lane: ([\w-]+)`?\s*$", re.MULTILINE)
# ci-workflows pr-review-cli.yml posts as github-actions[bot] (REST login;
# GraphQL drops the suffix). Such a comment is the lane's only when its last
# non-blank line is that lane's footer.
ACTIONS_LOGINS = frozenset({"github-actions", "github-actions[bot]"})


def _footer_lane(body: str) -> str | None:
    """The lane a body's last non-blank line names as its `claude-lane:`
    footer, None when that line is no footer."""
    lines = [line for line in body.splitlines() if line.strip()]
    tag = LANE_TAG_RE.fullmatch(lines[-1]) if lines else None
    return tag[1] if tag else None


def _lane_comment(lane: str, login: object, body: str) -> bool:
    """A Claude App comment untagged or tagged for `lane`, or a
    github-actions[bot] comment whose footer names `lane`."""
    if login in CLAUDE_APP_LOGINS:
        tag = LANE_TAG_RE.search(body)
        return tag is None or tag[1] == lane
    return login in ACTIONS_LOGINS and _footer_lane(body) == lane


# The lane whose findings hold the merge only at its top tier, CRITICAL
# (/review:security-review, "Reporting"): each inline
# comment carries one `severity:` line, and the summary one
# `critical-findings:` line counting its CRITICAL findings with no inline
# comment. A comment or summary without exactly one readable line counts every
# finding it holds as CRITICAL.
SEVERITY_LANE = "claude-security-review"
SEVERITY_RE = re.compile(
    r"^\s*`?severity: (CRITICAL|IMPORTANT|SUGGESTION)`?\s*$", re.MULTILINE
)
SUMMARY_CRITICAL_RE = re.compile(
    r"^\s*`?critical-findings: (\d{1,6})`?\s*$", re.MULTILINE
)
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
    changed_paths: Sequence[str] | None,
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
    diff against another base, so no lane binds. `changed_paths` holds every
    path the pull request changes (both sides of a rename), or None when the
    list is unread or incomplete: no lane binds then, nor when one is a lane
    source (`lane_source`).

    A lane binds only when every head its reviewed-head markers name still
    has a listed run: a deleted or expired run would drop its findings from
    the count, so it unbinds the lane rather than lowering the count.
    """
    try:
        if not isinstance(head_sha, str) or not SHA_RE.match(head_sha):
            raise Unbound("bad-head")
        if base_changed is not False:
            raise Unbound("base-retargeted")
        if not isinstance(changed_paths, list | tuple):
            raise Unbound("changed-files-unread")
        if any(lane_source(path) for path in changed_paths):
            raise Unbound("lane-source-changed")
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


def lane_source(path: Any) -> bool:
    """Whether a changed path is one the pull request's checkout feeds its
    own review; a path that is not a string counts as one."""
    if not isinstance(path, str):
        return True
    # A bare directory path (a symlink in its place) counts as the directory.
    parts = path.split("/")
    return (
        f"{path}/".startswith(LANE_SOURCE_PREFIXES)
        or LANE_SOURCE_SEGMENT in parts
        or parts[-1] in LANE_SOURCE_NAMES
    )


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
        marker = _require_marker(lane, head, comments)
        _require_marked_runs(lane, lane_runs, comments)
        count, clears, critical = _open_findings(
            lane,
            lane_runs,
            threads,
            is_human,
            claimed,
            reviewed,
            chain,
            head_file,
            [(None, marker), *_summary_comments(lane, comments)],
        )
    except Unbound as exc:
        return LaneEvidence(lane, False, exc.reason, None)
    blocking = critical if lane == SEVERITY_LANE else None
    return LaneEvidence(lane, True, None, count, clears, blocking)


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
        if not rerun_binds(lane, newest["id"], first):
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


def _failures(job: Mapping[str, Any]) -> list[str]:
    """The messages of the job's failure-level annotations."""
    return [
        str(a.get("message") or "")
        for a in job["annotations"]
        if isinstance(a, Mapping) and a.get("annotation_level") == "failure"
    ]


def _lane_line(pattern: re.Pattern[str], lane: str, message: str) -> bool:
    """Whether `message` opens with `pattern` for this lane."""
    found = pattern.match(message)
    return found is not None and found["lane"] == lane


def rate_limited(lane: str, job: Mapping[str, Any]) -> bool:
    return any(
        RATE_LIMIT_CLASS_RE.search(m) or _lane_line(PUBLISH_RATE_LIMIT_RE, lane, m)
        for m in _failures(job)
    )


def rerun_binds(lane: str, run_id: int, first: Mapping[str, Any]) -> bool:
    """Whether attempt 1 (`first`) left no verdict, so attempt 2 binds: it
    failed on a rate limit or a rejected credential (AUTH_FAILURE_RE), or a
    kill switch stopped it (`_kill_switch_stopped`)."""
    if first.get("conclusion") == "success":
        return _kill_switch_stopped(lane, run_id, first)
    if first.get("conclusion") != "failure":
        return False
    job = _lane_job(lane, run_id, first)
    return rate_limited(lane, job) or any(
        _lane_line(AUTH_FAILURE_RE, lane, m) for m in _failures(job)
    )


def _kill_switch_stopped(lane: str, run_id: int, attempt: Mapping[str, Any]) -> bool:
    """Whether a kill switch stopped this attempt before its lane job existed."""
    jobs = attempt.get("jobs")
    if not isinstance(jobs, list | tuple) or not all(
        isinstance(job, Mapping) for job in jobs
    ):
        raise Unbound("evidence-missing")
    suffix = LANES[lane][1]
    if any(str(job.get("name") or "").rsplit(" / ", 1)[-1] == suffix for job in jobs):
        return False
    kills = [job for job in jobs if job.get("name") == KILL_SWITCH_JOB]
    if len(kills) != 1 or kills[0].get("conclusion") != "success":
        return False
    kill = kills[0]
    if kill.get("run_id") != run_id or kill.get("run_attempt") != attempt.get(
        "run_attempt"
    ):
        raise Unbound("evidence-error")
    if not isinstance(kill.get("annotations"), list | tuple):
        raise Unbound("evidence-missing")
    return any(
        isinstance(a, Mapping)
        and a.get("annotation_level") == "notice"
        and KILL_SWITCH_NOTICE_RE[lane].match(str(a.get("message") or ""))
        for a in kill["annotations"]
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


def _require_marker(lane: str, head: str, comments: Sequence[Mapping[str, Any]]) -> str:
    """The newest reviewed-head marker the lane job wrote must name `head`;
    its body, which carries the covering review's summary."""
    if not isinstance(comments, list | tuple):
        raise Unbound("evidence-error")
    newest: tuple[str, int, str, str] | None = None
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
            str(comment.get("body") or ""),
        )
        if newest is None or key[:2] > newest[:2]:
            newest = key
    if newest is None or newest[2] != head:
        raise Unbound("no-marker")
    return newest[3]


def _summary_comments(
    lane: str, comments: Sequence[Mapping[str, Any]]
) -> list[tuple[datetime | None, str]]:
    """Each lane comment of `lane` (`_lane_comment`) but a reviewed-head
    marker, which the caller reads already, with its creation time: the
    summary comments a lane producer posted."""
    found = []
    for comment in comments:
        user = comment.get("user")
        if not isinstance(user, Mapping):
            continue
        body = str(comment.get("body") or "")
        created = _time(comment.get("created_at"))
        if MARKER_RE.match(body.split("\n", 1)[0]):
            continue
        # A REST comment always carries the bot's suffixed login and type.
        if user.get("login") in ACTIONS_LOGINS and (
            user.get("login") != MARKER_AUTHOR or user.get("type") != "Bot"
        ):
            continue
        if _lane_comment(lane, user.get("login"), body) and created is not None:
            found.append((created, body))
    return found


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
    summaries: Sequence[tuple[datetime | None, str]] = (),
) -> tuple[int, bool, int]:
    """Summary findings of the review chain covering the pinned head
    (`chain`, from `_resolve`), plus inline threads still open, plus inline
    findings of the chain whose thread is gone. A summary or thread-less
    inline finding from a review of an earlier head outside that chain is
    closed: the covering review no longer reports it. Reviews of one head
    never supersede each other, whatever their kind: each link counts the
    most summary findings, and the most inline findings left without a
    thread, that any completed review of its head (whole or incremental)
    reported. So a finding any review of a head reported clears only by a
    new head (a fix) or a human resolution; re-running the review of the
    same head until it comes back clean never clears it.

    A resolved thread is closed when:
    - a human resolved it;
    - no completed review of a chain link's head (whole or incremental)
      reported a finding, and the thread was opened before the covering
      review's job completed, so that review read past it. A whole review of
      the head is a chain of one, so a clean whole review closes a thread
      whoever resolved it, unless another review of that head reported a
      finding. An incremental review reads only what changed and never closes
      an unchanged thread this way. Closure is per lane: a security-lane
      (HIGH) thread needs the security lane's own clean whole review;
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
    `reviewed` reported a finding, and none of them was a whole review; and
    how many open findings are CRITICAL (`SEVERITY_RE`): open threads whose
    comment is not marked IMPORTANT or SUGGESTION, every inline finding whose
    thread is gone, and the summary findings, of which only the covering
    review's own may count fewer: its one `critical-findings:` line, read
    from `summaries` (the reviewed-head marker, which carries the summary,
    and each Claude App summary comment posted inside that review's job). An
    earlier review's summary is not read, so all its findings count."""
    if threads is None:
        raise Unbound("threads-unread")
    # The covering review's job window, to place its summary comments.
    span: tuple[datetime | None, datetime | None] | None = None
    # (job started, job completed, inline findings) per recorded attempt.
    windows: list[tuple[datetime | None, datetime | None, int]] = []
    # The head per window, to count missing ones on the chain.
    heads: list[str] = []
    # When the first review at `reviewed` started; unknown keeps every
    # thread's human test.
    first: datetime | None = None
    # Per head, the most findings and the most summary findings any completed
    # review of it, whole or incremental, reported.
    head_max: dict[str, int] = {}
    summary_max: dict[str, int] = {}
    # Whether any review of `reviewed` was whole or reported a finding.
    head_spent = False
    for item in lane_runs:
        for attempt in _attempts(item).values():
            # A draft-skipped or kill-switched run reviewed nothing.
            if (
                attempt.get("status") != "completed"
                or attempt.get("conclusion") == "skipped"
            ) or _kill_switch_stopped(lane, item["id"], attempt):
                continue
            job = _lane_job(lane, item["id"], attempt)
            rec = _record(lane, item["head_sha"], job)
            if rec is None or rec.findings is None:
                continue
            if rec.findings < rec.inline:  # type: ignore[operator]
                raise Unbound("count-inconsistent")
            head_max[rec.sha] = max(head_max.get(rec.sha, 0), rec.findings)
            summary_max[rec.sha] = max(
                summary_max.get(rec.sha, 0),
                rec.findings - rec.inline,  # type: ignore[operator]
            )
            started = _time(job.get("started_at"))
            if rec == chain[0]:
                span = (started, rec.completed)
            windows.append(
                (
                    started,
                    _time(job.get("completed_at")),
                    rec.inline,  # type: ignore[arg-type]
                )
            )
            heads.append(rec.sha)
            if rec.sha == reviewed and (rec.whole or rec.findings > 0):
                head_spent = True
            if (
                item["head_sha"] == reviewed
                and started
                and (first is None or started < first)
            ):
                first = started
    summary = sum(summary_max.get(rec.sha, 0) for rec in chain)
    cleared = not any(head_max.get(rec.sha) for rec in chain)
    # The covering review read only threads opened before its job completed.
    read_through = chain[0].completed
    if not isinstance(threads, list | tuple):
        raise Unbound("evidence-error")
    covered = [0] * len(windows)
    # Open threads: unresolved ones, and resolved ones nothing closed.
    unresolved = held = critical = 0
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
            held += 1
        else:
            continue
        severities = SEVERITY_RE.findall(str(thread["comments"][0].get("body") or ""))
        if len(severities) != 1 or severities[0] == "CRITICAL":
            critical += 1
    # Inline findings with no thread left, counted like summary findings:
    # per chain link, the most any review at its head left.
    gone = [max(k - n, 0) for (_, _, k), n in zip(windows, covered)]
    missing = sum(
        max((g for g, sha in zip(gone, heads) if sha == rec.sha), default=0)
        for rec in chain
    )
    count = summary + unresolved + held + missing
    # The covering review's summary findings, when it was the head's only
    # summary count and its line reads no more than it reported.
    own = chain[0].findings - chain[0].inline  # type: ignore[operator]
    start, end = span or (None, None)
    lines = [
        line
        for at, body in summaries
        if at is None or (start and end and start <= at <= end)
        for line in SUMMARY_CRITICAL_RE.findall(body)
    ]
    rest = summary - summary_max.get(chain[0].sha, 0)
    if own == summary_max.get(chain[0].sha, 0) and len(lines) == 1:
        summary = rest + min(int(lines[0]), own)
    return (
        count,
        count > 0 and not unresolved and not head_spent,
        summary + critical + missing,
    )


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
    """A thread the Claude App opened, untagged or tagged for `lane`, or
    github-actions[bot] opened with `lane`'s footer last."""
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
    if author.get("__typename") != "Bot":
        return False
    return _lane_comment(lane, author.get("login"), str(first.get("body") or ""))

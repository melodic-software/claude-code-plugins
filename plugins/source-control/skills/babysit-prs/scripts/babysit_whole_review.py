#!/usr/bin/env python3
"""Request a whole review of a lane pull request's head when the only thing
holding it is findings on its review chain that an incremental review cannot
clear (`LaneEvidence.whole_review_clears`).

A whole review runs on `ready_for_review`, so the request converts the pull
request to a draft and marks it ready again, with the lane token (an App
token's events start workflows; GITHUB_TOKEN's do not). Bounds:

- once per head, and `MAX_TOGGLES` per pull request: the reasons comment
  carries a `record_line` per request, written before the toggle and kept
  on every rewrite;
- at most one request per pr-merge sweep: the first candidate to reach
  `limits` claims the `SPENT_ENV` file, whatever its answer; with no
  `SPENT_ENV` (the local babysit loop) nothing is requested;
- only while fewer than `MAX_RUNNING_JOBS` jobs run in the repository and
  both the lane token and the job's own token have `MIN_REMAINING` calls left.

`recover` marks ready a draft the toggle left behind (the run ended between
its two writes), only when the lane identity made its newest conversion to
draft within `CONVERT_WINDOW` of a record's time.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path
from collections.abc import Mapping, Sequence
from typing import Any

import babysit_risk
from babysit_gh import fetch_paginated_api, gh_capture

# The reasons comment babysit_merge.py writes; the record lives in it.
RISK_MARKER = "<!-- babysit-merge-risk -->"
RECORD_PREFIX = "Whole review requested at head `"
RECORD_RE = re.compile(
    rf"^{re.escape(RECORD_PREFIX)}([0-9a-f]{{40}})` at "
    r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ): .*$",
    re.MULTILINE,
)
# Whole reviews a lane pull request may request; past that a person decides.
MAX_TOGGLES = 2
# A lane conversion to draft this long after a record belongs to its toggle.
CONVERT_WINDOW = timedelta(minutes=10)
CONVERT_SKEW = timedelta(minutes=1)
SPENT_ENV = "BABYSIT_WHOLE_REVIEW_SPENT"
# The job's own token (GITHUB_TOKEN), which also reads the runs.
JOB_TOKEN_ENV = "BABYSIT_VERIFY_GH_TOKEN"
MAX_RUNNING_JOBS = 35
MIN_REMAINING = 1500
READY_TRIES = 3
RECOVER_HOURS = 24
FINDING_CODES = frozenset(code for code, _ in babysit_risk.LANES.values())
CONVERT = (
    "mutation($id: ID!) { convertPullRequestToDraft(input: {pullRequestId: $id})"
    " { pullRequest { isDraft } } }"
)
READY = (
    "mutation($id: ID!) { markPullRequestReadyForReview(input: {pullRequestId: $id})"
    " { pullRequest { isDraft } } }"
)


def record_line(head: str, at: datetime) -> str:
    """One request's line; `at` is when the gate wrote it, before the toggle."""
    stamp = at.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    return (
        f"{RECORD_PREFIX}{head}` at {stamp}: an incremental review cannot "
        "clear the findings below."
    )


def records(body: Any) -> list[tuple[str, datetime]]:
    """(head, time) of every request line in `body`, in order."""
    return [
        (m[1], datetime.fromisoformat(m[2]))
        for m in RECORD_RE.finditer(str(body or ""))
    ]


def recorded(body: Any, head: str) -> bool:
    return any(sha == head for sha, _ in records(body))


def with_records(body: str, lines: Sequence[str]) -> str:
    return "\n\n".join([body, "\n".join(lines)]) if lines else body


def record_lines(body: Any) -> list[str]:
    return [m[0] for m in RECORD_RE.finditer(str(body or ""))]


def wanted(
    reason: str | None,
    risk: babysit_risk.RiskResult,
    lanes: Sequence[babysit_risk.LaneEvidence],
) -> bool:
    """Every other gate passed (`reason` is None), the score's only reasons
    are open findings, and a clean whole review would close each lane's."""
    if reason is not None or risk.score is babysit_risk.Risk.LOW:
        return False
    if not all(r.code in FINDING_CODES for r in risk.reasons):
        return False
    held = [lane for lane in lanes if (lane.open_findings or 0) > 0]
    return bool(held) and all(lane.whole_review_clears for lane in held)


def _api(args: list[str], env: Mapping[str, str] | None = None) -> Any:
    proc = gh_capture(["api", *args], env_overrides=env)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or f"gh api {args[0]} failed")
    return json.loads(proc.stdout or "null")


def _remaining(env: Mapping[str, str] | None) -> int:
    # GET /rate_limit does not count against the limit it reports.
    resources = _api(["rate_limit"], env)["resources"]
    return min(
        int(resources["core"]["remaining"]), int(resources["graphql"]["remaining"])
    )


def _running_jobs(repo: str, env: Mapping[str, str]) -> int:
    """Unfinished jobs of the in-progress and queued runs, counted up to the
    cap; a run holds at least one, so that many runs needs no job read."""
    runs = [
        item
        for status in ("in_progress", "queued")
        for item in _api(
            [f"repos/{repo}/actions/runs?status={status}&per_page=100"], env
        )["workflow_runs"]
    ]
    if len(runs) >= MAX_RUNNING_JOBS:
        return len(runs)
    total = 0
    for item in runs:
        jobs = _api([f"repos/{repo}/actions/runs/{item['id']}/jobs?per_page=100"], env)
        total += sum(1 for job in jobs["jobs"] if job.get("status") != "completed")
        if total >= MAX_RUNNING_JOBS:
            break
    return total


def limits(repo: str) -> str | None:
    """None when this sweep may request one whole review, else why not. The
    first call in a sweep claims it, so a refusal also spends the sweep."""
    spent = os.environ.get(SPENT_ENV)
    if not spent:
        return "not-pr-merge"
    path = Path(spent)
    try:
        with path.open("x"):
            pass
    except FileExistsError:
        return "sweep-limit"
    except OSError as exc:
        return f"sweep-claim: {exc}"
    token = os.environ.get(JOB_TOKEN_ENV)
    if not token:
        return "job-token-missing"
    job = {"GH_TOKEN": token}
    try:
        for name, env in (("lane", None), ("job", job)):
            left = _remaining(env)
            if left < MIN_REMAINING:
                return f"rate-limit:{name}:{left}"
        running = _running_jobs(repo, job)
    except (RuntimeError, KeyError, TypeError, ValueError) as exc:
        return f"limits-unread: {exc}"
    if running >= MAX_RUNNING_JOBS:
        return f"running-jobs:{running}"
    return None


def _graphql(query: str, node_id: str) -> bool:
    proc = gh_capture(["api", "graphql", "-f", f"query={query}", "-f", f"id={node_id}"])
    return proc.returncode == 0


def toggle(node_id: str, *, sleep: Any = time.sleep) -> dict[str, Any]:
    """Draft, then ready again; `ready_for_review` runs a whole review."""
    if not _graphql(CONVERT, node_id):
        return {"toggled": False, "error": "convert-to-draft failed"}
    for attempt in range(1, READY_TRIES + 1):
        if _graphql(READY, node_id):
            return {"toggled": True}
        if attempt < READY_TRIES:
            sleep(5 * attempt)
    return {"toggled": False, "error": "stranded-draft: mark-ready failed"}


CONVERTER = (
    "query($id: ID!) { node(id: $id) { ... on PullRequest {"
    " timelineItems(itemTypes: [CONVERT_TO_DRAFT_EVENT], last: 1)"
    " { nodes { ... on ConvertToDraftEvent { actor { login } createdAt } } } } } }"
)


def _login(value: Any) -> str:
    """A login compared across REST (`app[bot]`) and GraphQL (`app`)."""
    return str(value or "").casefold().removesuffix("[bot]")


def _converter(node_id: str) -> tuple[str, datetime] | None:
    """Who made the newest conversion to draft and when (server time), or
    None when unread."""
    proc = gh_capture(
        ["api", "graphql", "-f", f"query={CONVERTER}", "-f", f"id={node_id}"]
    )
    if proc.returncode != 0:
        return None
    try:
        nodes = json.loads(proc.stdout)["data"]["node"]["timelineItems"]["nodes"]
        if not nodes:
            return None
        login = (nodes[-1].get("actor") or {}).get("login")
        at = datetime.fromisoformat(str(nodes[-1]["createdAt"]))
        return (str(login), at) if login and at.tzinfo else None
    except (KeyError, TypeError, ValueError, AttributeError, IndexError):
        return None


def recover(
    repo: str,
    identity: str,
    drafts: Sequence[Mapping[str, Any]],
    now: datetime | None = None,
) -> list[dict[str, Any]]:
    """Mark ready each recently updated draft whose newest reasons comment by
    `identity` records a whole-review request at any head, when `identity`
    also made its newest conversion to draft (server time) within
    `CONVERT_WINDOW` after one of those records: a draft a person made, or
    one the lane made outside a toggle, stays one. Two reads per such draft:
    its comments and that conversion."""
    now = now or datetime.now(UTC)
    out = []
    for pr in drafts:
        number, head, node_id = pr.get("number"), pr.get("head"), pr.get("id")
        labels = {str(name).casefold() for name in pr.get("labels") or ()}
        try:
            updated = datetime.fromisoformat(str(pr.get("updatedAt")))
        except ValueError:
            continue
        if (
            "do-not-merge" in labels
            or now - updated > timedelta(hours=RECOVER_HOURS)
            or not isinstance(node_id, str)
        ):
            continue
        try:
            comments = fetch_paginated_api(
                f"repos/{repo}/issues/{number}/comments?per_page=100",
                f"#{number} comments",
            )
        except (RuntimeError, ValueError) as exc:
            out.append({"pr": number, "error": str(exc)})
            continue
        reasons = [
            c
            for c in comments
            if _login((c.get("user") or {}).get("login")) == _login(identity)
            and RISK_MARKER
            in [
                line.rstrip("\r")
                for line in str(c.get("body") or "").split("\n", 2)[:2]
            ]
        ]
        newest = max(reasons, key=lambda c: str(c.get("created_at")), default=None)
        stamps = [at for _, at in records((newest or {}).get("body"))]
        if not stamps:
            continue
        converted = _converter(node_id)
        if converted is None or _login(converted[0]) != _login(identity):
            continue
        if not any(
            at - CONVERT_SKEW <= converted[1] <= at + CONVERT_WINDOW for at in stamps
        ):
            continue
        out.append({"pr": number, "head": head, "ready": _graphql(READY, node_id)})
    return out


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__.split("\n")[0], allow_abbrev=False
    )
    sub = parser.add_subparsers(dest="command", required=True)
    rec = sub.add_parser(
        "recover", help="mark ready a draft a toggle left", allow_abbrev=False
    )
    rec.add_argument("--repo", required=True)
    rec.add_argument("--identity", required=True)
    rec.add_argument("--drafts", required=True, help="JSON list of drafts")
    args = parser.parse_args(argv)
    drafts = json.loads(Path(args.drafts).read_text())
    result = recover(args.repo, args.identity, drafts)
    print(json.dumps(result))
    return 1 if any(not r.get("ready", False) for r in result) else 0


if __name__ == "__main__":
    sys.exit(main())

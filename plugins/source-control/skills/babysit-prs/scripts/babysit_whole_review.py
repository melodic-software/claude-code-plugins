#!/usr/bin/env python3
"""Request a whole review of a lane pull request's head when the only thing
holding it is findings on its review chain that an incremental review cannot
clear (`LaneEvidence.whole_review_clears`).

A whole review runs on `ready_for_review`, so the request converts the pull
request to a draft and marks it ready again, with the lane token (an App
token's events start workflows; GITHUB_TOKEN's do not). Bounds:

- once per head: the reasons comment carries `record_line(head)`, written
  before the toggle and carried on every rewrite at that head;
- at most one request per pr-merge sweep: the first candidate to reach
  `limits` claims the `SPENT_ENV` file, whatever its answer; with no
  `SPENT_ENV` (the local babysit loop) nothing is requested;
- only while fewer than `MAX_RUNNING_JOBS` jobs run in the repository and
  both the lane token and the job's own token have `MIN_REMAINING` calls left.

`recover` marks ready a draft the toggle left behind (the run ended between
its two writes).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path
from collections.abc import Mapping, Sequence
from typing import Any

import babysit_risk
from babysit_gh import fetch_paginated_api, gh_capture

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


def record_line(head: str) -> str:
    return (
        f"Whole review requested at head `{head}`: an incremental review cannot "
        "clear the findings below."
    )


def recorded(body: Any, head: str) -> bool:
    return record_line(head) in str(body or "")


def with_record(body: str, head: str) -> str:
    return f"{body}\n\n{record_line(head)}"


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
    """Unfinished jobs of the in-progress runs, counted up to the cap; a run
    holds at least one, so a page of that many runs needs no job read."""
    runs = _api([f"repos/{repo}/actions/runs?status=in_progress&per_page=100"], env)
    runs = runs["workflow_runs"]
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


def recover(
    repo: str,
    identity: str,
    drafts: Sequence[Mapping[str, Any]],
    now: datetime | None = None,
) -> list[dict[str, Any]]:
    """Mark ready each recently updated draft whose newest comment by
    `identity` records a whole-review request at its current head."""
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
            or not (isinstance(head, str) and isinstance(node_id, str))
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
        mine = [
            c
            for c in comments
            if str((c.get("user") or {}).get("login") or "").casefold()
            == identity.casefold()
        ]
        newest = max(mine, key=lambda c: str(c.get("created_at")), default=None)
        if newest is not None and recorded(newest.get("body"), head):
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

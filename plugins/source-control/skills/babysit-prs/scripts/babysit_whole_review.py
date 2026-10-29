#!/usr/bin/env python3
"""Request a whole review of a lane or adopted pull request's head when the
only thing holding it is findings on its review chain that an incremental
review cannot clear (`LaneEvidence.whole_review_clears`).

A whole review runs on `ready_for_review`, so the request converts the pull
request to a draft and marks it ready again, with the lane token (an App
token's events start workflows; GITHUB_TOKEN's do not). Bounds:

- once per head: the reasons comment carries a `record_line` per request,
  written before the toggle and kept on every rewrite;
- `MAX_TOGGLES` per pull request, counted from the record lines and from the
  lane identity's conversions to draft on the timeline, which the lane token
  cannot delete as it can edit the comment;
- at most one request per pr-merge sweep: the first candidate to reach
  `limits` claims the `SPENT_ENV` file, whatever its answer; with no
  `SPENT_ENV` (the local babysit loop) nothing is requested;
- only while fewer than `MAX_RUNNING_JOBS` jobs run in the repository and
  both the lane token and the job's own token have `MIN_SHARE` of each
  bucket's hourly limit left.

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
# Whole reviews a pull request may request; past that a person decides.
MAX_TOGGLES = 2
# A lane conversion to draft this long after a record belongs to its toggle.
CONVERT_WINDOW = timedelta(minutes=10)
CONVERT_SKEW = timedelta(minutes=1)
SPENT_ENV = "BABYSIT_WHOLE_REVIEW_SPENT"
# The job's own token (GITHUB_TOKEN), which also reads the runs.
JOB_TOKEN_ENV = "BABYSIT_VERIFY_GH_TOKEN"
MAX_RUNNING_JOBS = 35
# The share of each rate-limit bucket that must be left: 1,500 of 5,000, 300
# of GITHUB_TOKEN's 1,000 outside GitHub Enterprise Cloud.
MIN_SHARE = 0.3
READY_TRIES = 3
RECOVER_HOURS = 24
FINDING_CODES = frozenset(code for code, _ in babysit_risk.LANES.values())
# The lane whose clean review clears a `review-path:` hold.
SECURITY_LANE = "claude-security-review"
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


_FENCE_RE = re.compile(r"^```[^\n]*\n.*?^```[ \t]*$", re.MULTILINE | re.DOTALL)


def _unfenced(body: Any) -> str:
    """`body` without its fenced blocks, where a reason quotes changed paths:
    a record line counts only outside them."""
    return _FENCE_RE.sub("", str(body or "").replace("\r\n", "\n"))


def records(body: Any) -> list[tuple[str, datetime]]:
    """(head, time) of every request line in `body`, in order."""
    return [
        (m[1], datetime.fromisoformat(m[2]))
        for m in RECORD_RE.finditer(_unfenced(body))
    ]


def recorded(body: Any, head: str) -> bool:
    return any(sha == head for sha, _ in records(body))


def with_records(body: str, lines: Sequence[str]) -> str:
    return "\n\n".join([body, "\n".join(lines)]) if lines else body


def record_lines(body: Any) -> list[str]:
    return [m[0] for m in RECORD_RE.finditer(_unfenced(body))]


def wanted(
    reason: str | None,
    risk: babysit_risk.RiskResult,
    lanes: Sequence[babysit_risk.LaneEvidence],
) -> bool:
    """Every other gate passed (`reason` is None), the only reasons holding
    the score are open findings and `review-path:` holds, and a clean whole
    review would close each lane's. A `review-path:` hold stands while the
    security lane's bound review counts an open finding of any tier
    (`babysit_risk.security_review_clean`), so that lane must be one a whole
    review clears."""
    held_by = babysit_risk.holding(risk)
    if reason is not None or not held_by:
        return False
    path = babysit_risk.REVIEW_PATH_PREFIX
    if not all(r.code in FINDING_CODES or r.code.startswith(path) for r in held_by):
        return False
    codes = {r.code for r in held_by}
    review_path = any(code.startswith(path) for code in codes)
    held = [
        lane
        for lane in lanes
        if (
            babysit_risk.LANES.get(lane.lane, ("",))[0] in codes
            and (babysit_risk.blocking(lane) or 0) > 0
        )
        or (
            review_path
            and lane.lane == SECURITY_LANE
            and lane.bound
            and lane.unbound_reason is None
            and (lane.open_findings or 0) > 0
        )
    ]
    if review_path and not any(lane.lane == SECURITY_LANE for lane in held):
        return False
    return bool(held) and all(lane.whole_review_clears for lane in held)


def request(
    repo: str, text: Any, head: str, node_id: str, identity: str, at: datetime
) -> tuple[list[str], dict[str, Any] | None]:
    """The record lines the reasons comment `text` holds, plus one for `head`
    when this sweep may request a whole review of it, and the request:
    `{"toggle": True}` for a new record, a `skipped` answer at a cap or limit,
    or None when `head` is already recorded. The caller writes the lines
    before it toggles, so a failed write never toggles twice at a head."""
    lines = record_lines(text)
    if recorded(text, head):
        return lines, None
    if len(lines) >= MAX_TOGGLES:
        return lines, {"toggled": False, "skipped": f"toggle-cap:{len(lines)}"}
    # The timeline, not the comment the lane token can edit, holds the count.
    toggled = lane_toggles(node_id, identity)
    if toggled is None:
        return lines, {"toggled": False, "skipped": "toggle-cap:unread"}
    if toggled >= MAX_TOGGLES:
        return lines, {"toggled": False, "skipped": f"toggle-cap:{toggled}"}
    refusal = limits(repo)
    if refusal is not None:
        return lines, {"toggled": False, "skipped": refusal}
    return [*lines, record_line(head, at)], {"toggle": True}


def _api(args: list[str], env: Mapping[str, str] | None = None) -> Any:
    proc = gh_capture(["api", *args], env_overrides=env)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or f"gh api {args[0]} failed")
    return json.loads(proc.stdout or "null")


def _short_bucket(env: Mapping[str, str] | None) -> str | None:
    """`bucket:remaining/limit` for the first bucket under `MIN_SHARE` of its
    limit, else None. GET /rate_limit does not count against any bucket."""
    resources = _api(["rate_limit"], env)["resources"]
    for bucket in ("core", "graphql"):
        left = int(resources[bucket]["remaining"])
        limit = int(resources[bucket]["limit"])
        # A limit of zero or less is no budget to judge against, so it refuses.
        if limit <= 0 or left < MIN_SHARE * limit:
            return f"{bucket}:{left}/{limit}"
    return None


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
            short = _short_bucket(env)
            if short is not None:
                return f"rate-limit:{name}:{short}"
        running = _running_jobs(repo, job)
    except (RuntimeError, KeyError, TypeError, ValueError) as exc:
        return f"limits-unread: {exc}"
    if running >= MAX_RUNNING_JOBS:
        return f"running-jobs:{running}"
    return None


def _graphql(query: str, node_id: str) -> bool:
    proc = gh_capture(["api", "graphql", "-f", f"query={query}", "-f", f"id={node_id}"])
    return proc.returncode == 0


HOLD_STATE = (
    "query($id: ID!) { node(id: $id) { ... on PullRequest {"
    " isDraft body labels(first: 100) { totalCount nodes { name } } } } }"
)


def _held(node_id: str) -> str | None:
    """Why the pull request, read now, must not be toggled, or None: it is
    already a draft (a person's, whose hold a mark-ready would undo), carries
    a merge-hold label or a body hold, or did not read whole."""
    import babysit_merge_policy as merge_policy  # noqa: PLC0415 - import cycle

    proc = gh_capture(
        ["api", "graphql", "-f", f"query={HOLD_STATE}", "-f", f"id={node_id}"]
    )
    try:
        node = json.loads(proc.stdout)["data"]["node"] if proc.returncode == 0 else None
        labels = node["labels"]
        names = {str(n["name"]).casefold() for n in labels["nodes"]}
        whole = labels["totalCount"] == len(labels["nodes"])
        draft, body = node["isDraft"], str(node["body"] or "")
    except (KeyError, TypeError, ValueError):
        return "hold-state-unread"
    if draft is not False:
        return "already-draft"
    if not whole:
        return "hold-state-unread"
    if names & set(merge_policy.MERGE_HOLD_LABELS):
        return "hold-label"
    if merge_policy.BODY_MERGE_HOLD_RE.search(body):
        return "body-hold"
    return None


def toggle(node_id: str, *, sleep: Any = time.sleep) -> dict[str, Any]:
    """Draft, then ready again; `ready_for_review` runs a whole review. The
    draft state and holds are read just before, so a person's draft or hold
    set since the caller's listing is never undone."""
    held = _held(node_id)
    if held is not None:
        return {"toggled": False, "skipped": held}
    if not _graphql(CONVERT, node_id):
        return {"toggled": False, "error": "convert-to-draft failed"}
    for attempt in range(1, READY_TRIES + 1):
        if _graphql(READY, node_id):
            return {"toggled": True}
        if attempt < READY_TRIES:
            sleep(5 * attempt)
    return {"toggled": False, "error": "stranded-draft: mark-ready failed"}


# The newest 100: past that the cap is long reached.
CONVERSIONS = (
    "query($id: ID!) { node(id: $id) { ... on PullRequest {"
    " timelineItems(itemTypes: [CONVERT_TO_DRAFT_EVENT], last: 100)"
    " { nodes { ... on ConvertToDraftEvent { actor { login } createdAt } } } } } }"
)


def _login(value: Any) -> str:
    """A login compared across REST (`app[bot]`) and GraphQL (`app`)."""
    return str(value or "").casefold().removesuffix("[bot]")


def _conversions(node_id: str) -> list[dict[str, Any]] | None:
    """The pull request's conversions to draft, oldest first, or None when
    unread."""
    proc = gh_capture(
        ["api", "graphql", "-f", f"query={CONVERSIONS}", "-f", f"id={node_id}"]
    )
    if proc.returncode != 0:
        return None
    try:
        nodes = json.loads(proc.stdout)["data"]["node"]["timelineItems"]["nodes"]
    except (KeyError, TypeError, ValueError):
        return None
    return nodes if isinstance(nodes, list) else None


def lane_toggles(node_id: str, identity: str) -> int | None:
    """How many conversions to draft `identity` made, or None when unread.
    Any lane conversion counts, a toggle's or not."""
    nodes = _conversions(node_id)
    if nodes is None:
        return None
    return sum(
        1
        for n in nodes
        if isinstance(n, dict)
        and _login((n.get("actor") or {}).get("login")) == _login(identity)
    )


def _converter(node_id: str) -> tuple[str, datetime] | None:
    """Who made the newest conversion to draft and when (server time), or
    None when unread."""
    nodes = _conversions(node_id)
    if not nodes:
        return None
    try:
        login = (nodes[-1].get("actor") or {}).get("login")
        at = datetime.fromisoformat(str(nodes[-1]["createdAt"]))
        return (str(login), at) if login and at.tzinfo else None
    except (KeyError, TypeError, ValueError, AttributeError):
        return None


def toggled(node_id: str, identity: str, stamps: Sequence[datetime]) -> list[datetime]:
    """The record times in `stamps` whose toggle `identity` made: its newest
    conversion to draft (server time, which editing the reasons comment
    cannot move) falls within `CONVERT_WINDOW` after them. Empty when the
    conversion is unread or another actor's."""
    try:
        converted = _converter(node_id) if stamps else None
    except (RuntimeError, ValueError, OSError):
        converted = None
    if converted is None or _login(converted[0]) != _login(identity):
        return []
    return [
        at for at in stamps if at - CONVERT_SKEW <= converted[1] <= at + CONVERT_WINDOW
    ]


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
        if not toggled(node_id, identity, stamps):
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
    req = sub.add_parser(
        "request",
        help="the record line for a whole review of --head, the reasons comment on stdin",
        allow_abbrev=False,
    )
    tog = sub.add_parser(
        "toggle", help="draft, then ready again: a whole review", allow_abbrev=False
    )
    for cmd in (req, tog):
        cmd.add_argument("--node-id", required=True)
    for name in ("--repo", "--identity", "--head"):
        req.add_argument(name, required=True)
    args = parser.parse_args(argv)
    if args.command == "request":
        lines, answer = request(
            args.repo,
            sys.stdin.read().replace("\r\n", "\n"),
            args.head,
            args.node_id,
            args.identity,
            datetime.now(UTC),
        )
        print(json.dumps({"line": lines[-1]} if answer == {"toggle": True} else answer))
        return 0
    if args.command == "toggle":
        result = toggle(args.node_id)
        print(json.dumps(result))
        return 0 if result["toggled"] else 1
    drafts = json.loads(Path(args.drafts).read_text())
    result = recover(args.repo, args.identity, drafts)
    print(json.dumps(result))
    return 1 if any(not r.get("ready", False) for r in result) else 0


if __name__ == "__main__":
    sys.exit(main())

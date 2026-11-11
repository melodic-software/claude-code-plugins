#!/usr/bin/env python3
"""Finding-decomposition counting entrypoint for babysit-readiness-gate.sh.

The readiness gate is a pure predicate that blocks a readiness declaration while
source findings outnumber their per-finding classification rows. The gate shells
out here so the severity vocabulary lives once, in `babysit_classify`. The gate
keeps an equivalent bash count only for the Python-free safe-tier degrade (see
`reference/loop.md`); a convergence test pins the two on thread-state-free input.

Only currently-open findings count: a severity marker in a review thread GitHub
reports resolved or outdated belongs to an already-addressed round and must not
inflate the denominator. That discount is mechanical (resolved/outdated thread
state); the same concern restated across re-review rounds is not de-duplicated
(no reliable mechanical "same concern" signal), so restatements within
still-open threads still count.

Input is either a comments JSON file (`--comments-json`, the gate's fixture /
network-free path; the bash-emitted `fetch-all-pr-comments.sh` schema, optionally
carrying per-comment `isResolved` / `isOutdated`) or a live PR (`--pr`), for
which this entrypoint fetches issue comments, review summaries, and review
threads (with resolution state) itself.

Usage:
  babysit_findings.py --comments-json <file> --self <csv>
  babysit_findings.py --pr <number> --self <csv> [--repo <owner/repo>]

Stdout (one line, parsed by the gate):
  findings=<n> classified=<n>

Exit codes:
  0  counts emitted
  2  runtime failure (fetch / parse)
  3  invalid argument
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from babysit_classify import (
    count_effective_classified,
    count_findings,
    normalize_self_logins,
)
from babysit_gh import (
    fetch_issue_comments,
    fetch_pull_request_reviews,
    fetch_review_threads,
    run_gh,
)
from babysit_util import configure_stdio, is_json_array, is_json_object


def _author_login(author: Any) -> str:
    if is_json_object(author):
        return str(author.get("login") or author.get("name") or "")
    return str(author or "")


def _comment(
    author: Any, body: Any, thread: dict[str, Any] | None = None
) -> dict[str, Any]:
    state = thread or {}
    return {
        "author": _author_login(author),
        "body": str(body or ""),
        "in_review_thread": thread is not None,
        "isResolved": bool(state.get("isResolved")),
        "isOutdated": bool(state.get("isOutdated")),
    }


def load_comments_json(path: str) -> list[dict[str, Any]]:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if not is_json_array(data):
        raise ValueError("comments JSON must be an array")
    return [item for item in data if is_json_object(item)]


def resolve_repo(explicit: str | None) -> str:
    if explicit:
        return explicit
    return run_gh(
        ["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]
    ).strip()


def fetch_live_comments(repo: str, number: int) -> list[dict[str, Any]]:
    """Build the finding corpus for a live PR across all three feedback surfaces.

    Issue-level comments and review summaries are not review threads, so they
    carry no resolution state and always count; they are stamped as the PR-level
    surface (`in_review_thread` false) so a classification posted there is
    credited only against PR-level findings, never a fresh open-thread one.
    Inline review-thread comments are stamped `in_review_thread` and inherit
    their thread's `isResolved` / `isOutdated`, so an already-addressed thread's
    severity markers are discounted rather than silently dropped.

    `fetch_review_threads` flags a thread past its per-thread comment cap
    `comments_truncated` rather than raising. This counter needs every comment:
    a dropped severity marker or classification row would let the gate declare
    READINESS_OK while a later open finding sits unclassified. So a truncated
    thread raises; `main` maps that to exit 2, which emits no count line and
    leaves the gate on its complete REST/bash degrade count (`reference/loop.md`).
    """
    comments = [
        _comment(row.get("author"), row.get("body"))
        for rows in (
            fetch_issue_comments(repo, number),
            fetch_pull_request_reviews(repo, number),
        )
        for row in rows
    ]
    for thread in fetch_review_threads(repo, number, include_resolved=True):
        if not is_json_object(thread):
            continue
        if thread.get("comments_truncated"):
            raise RuntimeError(
                f"review thread {thread.get('id')} has "
                f"{thread.get('comments_total_count')} comments exceeding the "
                "per-thread fetch cap; failing closed to the bash finding count"
            )
        for node in thread.get("comments") or []:
            if is_json_object(node):
                comments.append(_comment(node.get("author"), node.get("body"), thread))
    return comments


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=True, allow_abbrev=False)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--pr", type=int, help="live PR number to fetch and count")
    source.add_argument("--comments-json", help="comments JSON file (no network)")
    parser.add_argument("--self", dest="self_csv", default="", help="self logins, csv")
    parser.add_argument("--repo", help="owner/repo (default: current repo)")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    configure_stdio()
    args = parse_args(sys.argv[1:] if argv is None else argv)
    self_logins = normalize_self_logins(args.self_csv.split(","))
    try:
        if args.comments_json:
            comments = load_comments_json(args.comments_json)
        else:
            comments = fetch_live_comments(resolve_repo(args.repo), args.pr)
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"babysit_findings: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    findings = count_findings(comments, self_logins)
    classified = count_effective_classified(comments, self_logins)
    print(f"findings={findings} classified={classified}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

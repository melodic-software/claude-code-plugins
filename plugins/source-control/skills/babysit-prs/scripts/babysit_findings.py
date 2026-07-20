#!/usr/bin/env python3
"""Finding-decomposition counting entrypoint for babysit-readiness-gate.sh.

The readiness gate is a pure predicate that blocks a readiness declaration while
source findings outnumber their per-finding classification rows. Counting "what
is a finding" used to be a bash grep re-implementation of the severity
vocabulary the Python classifier already owns; #534 makes the gate shell out
here so the vocabulary lives once, in `babysit_classify`. The gate retains an
equivalent bash count solely for the Python-free safe-tier degrade (see
`reference/loop.md`); a convergence test pins the two on thread-state-free input.

Counting only currently-open findings is the fix for #465: a severity marker
carried in a review thread GitHub reports resolved or outdated is a lifetime
artifact of an already-addressed round, not a live finding, and must not inflate
the denominator. That discount is mechanical (resolved/outdated thread state);
de-duplicating the same concern restated across re-review rounds is deliberately
out of scope (no reliable mechanical "same concern" signal), so restatements
within still-open threads still count.

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

from babysit_classify import count_classified, count_findings, normalize_self_logins
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


def _comment(author: Any, body: Any, thread: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "author": _author_login(author),
        "body": str(body or ""),
        "isResolved": bool(thread.get("isResolved")) if thread else False,
        "isOutdated": bool(thread.get("isOutdated")) if thread else False,
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
    return run_gh(["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]).strip()


def fetch_live_comments(repo: str, number: int) -> list[dict[str, Any]]:
    """Build the finding corpus for a live PR across all three feedback surfaces.

    Issue-level comments and review summaries are not review threads, so they
    carry no resolution state and always count. Inline review-thread comments
    inherit their thread's `isResolved` / `isOutdated` so an already-addressed
    thread's severity markers are discounted. Resolved threads are included
    (`include_resolved=True`) precisely so they can be discounted rather than
    silently dropped.
    """
    comments: list[dict[str, Any]] = [
        _comment(row.get("author"), row.get("body"))
        for row in fetch_issue_comments(repo, number)
    ]
    comments.extend(
        _comment(row.get("author"), row.get("body"))
        for row in fetch_pull_request_reviews(repo, number)
    )
    for thread in fetch_review_threads(repo, number, include_resolved=True):
        if not is_json_object(thread):
            continue
        for node in thread.get("comments") or []:
            if is_json_object(node):
                comments.append(_comment(node.get("author"), node.get("body"), thread))
    return comments


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=True)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--pr", type=int, help="live PR number to fetch and count")
    source.add_argument("--comments-json", help="comments JSON file (no network)")
    parser.add_argument("--self", dest="self_csv", default="", help="self logins, csv")
    parser.add_argument("--repo", help="owner/repo (default: current repo)")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    configure_stdio()
    args = parse_args(sys.argv[1:] if argv is None else argv)
    self_logins = normalize_self_logins(
        token for token in (args.self_csv or "").split(",")
    )
    try:
        if args.comments_json:
            comments = load_comments_json(args.comments_json)
        else:
            comments = fetch_live_comments(resolve_repo(args.repo), args.pr)
    except (OSError, ValueError, json.JSONDecodeError, RuntimeError) as exc:
        print(f"babysit_findings: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    findings = count_findings(comments, self_logins)
    classified = count_classified(comments, self_logins)
    print(f"findings={findings} classified={classified}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Read-only unresolved-review-thread gate for one pull request.

An unresolved review thread can hold a merge while every check is green, and
nothing on the checks or comments surfaces says why. This names the threads. It reads them through
`babysit_merge.unresolved_threads`, the predicate the babysit merge gate holds
on, so both skills count the same threads the same way, outdated ones included.

Stdout, exactly one verdict line first:
  THREADS_OK unresolved=0 pr=<owner/repo#n>                       exit 0
  THREADS_BLOCKED unresolved=<n> pr=<owner/repo#n>                exit 1
    then one line per thread: - <path> by <author> <url>[ (outdated)]
  THREADS_UNPROVEN reason=<bad-args|graphql-unavailable|fetch-failed> pr=<...>  exit 2
UNPROVEN is never a pass: a read that did not happen is not evidence of zero
threads. `babysit_gh.fetch_review_threads` owns the transport and why it fails
closed.
"""

from __future__ import annotations

import argparse
import sys

from babysit_gh import parse_repo_number
from babysit_merge import unresolved_threads
from babysit_util import configure_stdio


def main(argv: list[str] | None = None) -> int:
    configure_stdio()
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("pr", help="owner/repo#number or PR URL")
    args = parser.parse_args(argv)
    try:
        repo, number = parse_repo_number(args.pr)
    except ValueError as exc:
        print("THREADS_UNPROVEN reason=bad-args pr=unknown")
        print(exc, file=sys.stderr)
        return 2
    ref = f"{repo}#{number}"
    try:
        threads = unresolved_threads(repo, number)
    except (RuntimeError, ValueError) as exc:
        print(f"THREADS_UNPROVEN reason=fetch-failed pr={ref}")
        print(exc, file=sys.stderr)
        return 2
    if threads is None:
        print(f"THREADS_UNPROVEN reason=graphql-unavailable pr={ref}")
        return 2
    if not threads:
        print(f"THREADS_OK unresolved=0 pr={ref}")
        return 0
    print(f"THREADS_BLOCKED unresolved={len(threads)} pr={ref}")
    for thread in threads:
        outdated = " (outdated)" if thread.get("isOutdated") else ""
        print(
            f"- {thread.get('path')} by {thread.get('author')} {thread.get('url')}{outdated}"
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

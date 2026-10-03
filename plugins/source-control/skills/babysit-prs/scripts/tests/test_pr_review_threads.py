"""The unresolved-review-thread gate `/source-control:pull-request` readiness runs.

The gate reads threads through `babysit_merge.unresolved_threads`, the same
predicate the babysit merge gate holds on, so these tests stub only the one gh
seam under the shared paginator (`babysit_gh.gh_json`) and exercise the real
pagination and projection. No real gh process is spawned.
"""

from __future__ import annotations

import contextlib
import io
import pathlib
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_gh as gh
import pr_review_threads as gate


def _comment(login: str, path: str, url: str) -> dict[str, Any]:
    return {
        "author": {"__typename": "Bot", "login": login},
        "body": "finding",
        "path": path,
        "url": url,
        "createdAt": "",
        "updatedAt": "",
        "databaseId": 1,
    }


def _thread(
    thread_id: str,
    comment: dict[str, Any],
    *,
    resolved: bool = False,
    outdated: bool = False,
) -> dict[str, Any]:
    return {
        "id": thread_id,
        "isResolved": resolved,
        "isOutdated": outdated,
        "comments": {
            "totalCount": 1,
            "pageInfo": {"hasNextPage": False},
            "nodes": [comment],
        },
    }


def _response(nodes: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "data": {
            "repository": {
                "pullRequest": {
                    "reviewThreads": {
                        "pageInfo": {"hasNextPage": False, "endCursor": None},
                        "nodes": nodes,
                    }
                }
            }
        }
    }


def _run(argv: list[str], **gh_json: Any) -> tuple[int, str]:
    out = io.StringIO()
    with mock.patch.object(gh, "gh_json", **gh_json), contextlib.redirect_stdout(out):
        code = gate.main(argv)
    return code, out.getvalue()


OPEN_URL = "https://github.com/owner/repo/pull/7#discussion_r1"
OUTDATED_URL = "https://github.com/owner/repo/pull/7#discussion_r2"
RESOLVED_URL = "https://github.com/owner/repo/pull/7#discussion_r3"


class UnresolvedThreadsHoldReadiness(unittest.TestCase):
    def test_unresolved_threads_block_and_are_named(self) -> None:
        response = _response(
            [
                _thread("t1", _comment("codex", "src/a.py", OPEN_URL)),
                _thread(
                    "t2", _comment("claude", "docs/b.md", OUTDATED_URL), outdated=True
                ),
                _thread(
                    "t3", _comment("codex", "src/c.py", RESOLVED_URL), resolved=True
                ),
            ]
        )
        code, out = _run(["owner/repo#7"], return_value=response)
        lines = out.splitlines()
        self.assertEqual(code, 1)
        self.assertEqual(lines[0], "THREADS_BLOCKED unresolved=2 pr=owner/repo#7")
        self.assertIn(f"- src/a.py by codex {OPEN_URL}", lines)
        self.assertIn(f"- docs/b.md by claude {OUTDATED_URL} (outdated)", lines)
        self.assertNotIn(RESOLVED_URL, out)

    def test_no_unresolved_threads_passes(self) -> None:
        response = _response(
            [_thread("t3", _comment("codex", "src/c.py", RESOLVED_URL), resolved=True)]
        )
        code, out = _run(
            ["https://github.com/owner/repo/pull/7"], return_value=response
        )
        self.assertEqual(code, 0)
        self.assertEqual(out.splitlines(), ["THREADS_OK unresolved=0 pr=owner/repo#7"])


class UnreadableThreadsNeverReadAsClean(unittest.TestCase):
    """Zero threads must be proven: a read that did not happen is not a pass."""

    def test_graphql_refused_is_unproven(self) -> None:
        refusal = RuntimeError(
            "gh api graphql failed: gh: this GraphQL operation is not enabled for "
            "this session (HTTP 403)"
        )
        code, out = _run(["owner/repo#7"], side_effect=refusal)
        self.assertEqual(code, 2)
        self.assertEqual(
            out.splitlines()[0],
            "THREADS_UNPROVEN reason=graphql-unavailable pr=owner/repo#7",
        )

    def test_fetch_failure_is_unproven(self) -> None:
        code, out = _run(["owner/repo#7"], side_effect=RuntimeError("(HTTP 502)"))
        self.assertEqual(code, 2)
        self.assertEqual(
            out.splitlines()[0], "THREADS_UNPROVEN reason=fetch-failed pr=owner/repo#7"
        )

    def test_malformed_reference_is_unproven(self) -> None:
        code, out = _run(["owner/repo"], side_effect=AssertionError("no fetch"))
        self.assertEqual(code, 2)
        self.assertEqual(
            out.splitlines()[0], "THREADS_UNPROVEN reason=bad-args pr=unknown"
        )


if __name__ == "__main__":
    unittest.main()

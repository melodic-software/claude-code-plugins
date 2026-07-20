"""Finding-count entrypoint the readiness gate shells out to.

`babysit_findings` builds the live-PR finding corpus across the three feedback
surfaces and prints the `findings=<n> classified=<n>` line the gate parses. The
load-bearing safety property is what it does when the GraphQL review-thread
paginator returns a thread truncated at the per-thread comment cap: it must NOT
emit a count line, so the gate stays on its complete REST/bash degrade count
instead of a Python count missing every comment past the cap (which could drop
a later open finding and let the gate declare READINESS_OK).

Network is stubbed by monkeypatching the fetch seams in the `babysit_findings`
namespace, where they are imported by name; no real gh process is spawned.
"""

from __future__ import annotations

import io
import json
import pathlib
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_findings as bf


def _thread(comments, *, truncated=False, total=None, id="t1", isResolved=False,
            isOutdated=False):
    return {
        "id": id,
        "isResolved": isResolved,
        "isOutdated": isOutdated,
        "comments": comments,
        "comments_total_count": total if total is not None else len(comments),
        "comments_truncated": truncated,
    }


def _comment(login="codex[bot]", body="[CRITICAL] a"):
    return {"author": {"__typename": "Bot", "login": login}, "body": body}


class FetchLiveCommentsTruncationTests(unittest.TestCase):
    """A truncated thread must fail closed rather than under-count silently."""

    def test_truncated_thread_raises(self) -> None:
        with mock.patch.object(bf, "fetch_issue_comments", return_value=[]), \
                mock.patch.object(bf, "fetch_pull_request_reviews", return_value=[]), \
                mock.patch.object(
                    bf, "fetch_review_threads",
                    return_value=[_thread([_comment()], truncated=True, total=150)]):
            with self.assertRaises(RuntimeError):
                bf.fetch_live_comments("owner/repo", 1)

    def test_untruncated_thread_collects_comments(self) -> None:
        with mock.patch.object(bf, "fetch_issue_comments", return_value=[]), \
                mock.patch.object(bf, "fetch_pull_request_reviews", return_value=[]), \
                mock.patch.object(
                    bf, "fetch_review_threads",
                    return_value=[_thread([_comment(body="[CRITICAL] open")])]):
            comments = bf.fetch_live_comments("owner/repo", 1)
        self.assertEqual([c["body"] for c in comments], ["[CRITICAL] open"])


class SurfaceStampingTests(unittest.TestCase):
    """#642: the corpus must record which surface a comment lives on so the
    classifier can credit classifications per surface. Thread comments are
    stamped `in_review_thread`; issue-level and review-summary comments are
    not."""

    def test_thread_comments_stamped_pr_level_comments_not(self) -> None:
        with mock.patch.object(
                bf, "fetch_issue_comments",
                return_value=[{"author": "human", "body": "issue-level note"}]), \
                mock.patch.object(
                    bf, "fetch_pull_request_reviews",
                    return_value=[{"author": "codex[bot]", "body": "review summary"}]), \
                mock.patch.object(
                    bf, "fetch_review_threads",
                    return_value=[_thread([_comment(body="[CRITICAL] inline")])]):
            comments = bf.fetch_live_comments("owner/repo", 1)
        by_body = {c["body"]: c["in_review_thread"] for c in comments}
        self.assertEqual(by_body["issue-level note"], False)
        self.assertEqual(by_body["review summary"], False)
        self.assertEqual(by_body["[CRITICAL] inline"], True)


class Main642FailOpenTests(unittest.TestCase):
    """End-to-end: a fresh finding in an OPEN review thread plus a stale
    classification pipe-row in a PR-level review summary must BLOCK, not
    false-pass. Before the per-surface credit the row inflated `classified` to
    1 == findings and `main` printed a passing count."""

    def test_stale_pr_level_row_blocks_open_thread_finding(self) -> None:
        buffer = io.StringIO()
        with mock.patch.object(bf, "resolve_repo", return_value="owner/repo"), \
                mock.patch.object(bf, "fetch_issue_comments", return_value=[]), \
                mock.patch.object(
                    bf, "fetch_pull_request_reviews",
                    return_value=[{
                        "author": "me[bot]",
                        "body": "| 1 | old resolved finding | VALID | fixed |",
                    }]), \
                mock.patch.object(
                    bf, "fetch_review_threads",
                    return_value=[_thread(
                        [_comment(body="[CRITICAL] fresh unclassified finding")])]):
            with redirect_stdout(buffer):
                code = bf.main(["--pr", "1", "--self", "me[bot]"])
        self.assertEqual(code, 0)
        self.assertIn("findings=1 classified=0", buffer.getvalue())


class SnapshotSurfaceInferenceTests(unittest.TestCase):
    """#642: the `--comments-json` reuse path accepts the `fetch-all-pr-comments.sh`
    snapshot, which marks surface via `type` (`inline` == review thread) and emits
    no `in_review_thread` field. `load_comments_json` must infer the surface from
    `type`, else an inline finding defaults to PR-level and a stale PR-level
    classification row cross-credits it -- the exact fail-open #642 closes."""

    def _load(self, rows):
        with tempfile.NamedTemporaryFile(
                "w", suffix=".json", delete=False, encoding="utf-8") as handle:
            json.dump(rows, handle)
            path = handle.name
        try:
            return bf.load_comments_json(path)
        finally:
            pathlib.Path(path).unlink()

    def test_inline_type_is_stamped_thread_others_pr_level(self) -> None:
        loaded = self._load([
            {"type": "inline", "author": "codex[bot]", "body": "[CRITICAL] a"},
            {"type": "general", "author": "human", "body": "note"},
            {"type": "review", "author": "codex[bot]", "body": "summary"},
        ])
        by_body = {c["body"]: c["in_review_thread"] for c in loaded}
        self.assertEqual(by_body["[CRITICAL] a"], True)
        self.assertEqual(by_body["note"], False)
        self.assertEqual(by_body["summary"], False)

    def test_explicit_in_review_thread_is_not_overridden(self) -> None:
        loaded = self._load([
            {"type": "inline", "in_review_thread": False, "body": "x"},
        ])
        self.assertEqual(loaded[0]["in_review_thread"], False)

    def test_neither_field_stays_pr_level(self) -> None:
        loaded = self._load([{"author": "me[bot]", "body": "x"}])
        self.assertNotIn("in_review_thread", loaded[0])

    def test_snapshot_stale_pr_row_blocks_inline_finding(self) -> None:
        buffer = io.StringIO()
        rows = [
            {"type": "inline", "author": "codex[bot]",
             "body": "[CRITICAL] fresh unclassified finding"},
            {"type": "review", "author": "me[bot]",
             "body": "| 1 | old finding | VALID | fixed |"},
        ]
        with tempfile.NamedTemporaryFile(
                "w", suffix=".json", delete=False, encoding="utf-8") as handle:
            json.dump(rows, handle)
            path = handle.name
        try:
            with redirect_stdout(buffer):
                code = bf.main(["--comments-json", path, "--self", "me[bot]"])
        finally:
            pathlib.Path(path).unlink()
        self.assertEqual(code, 0)
        self.assertIn("findings=1 classified=0", buffer.getvalue())


class MainTruncationContractTests(unittest.TestCase):
    """The gate parses stdout: on truncation `main` must exit 2 and print NO
    `findings=` line, so the gate's regex misses and the bash count stands."""

    def test_main_exits_2_with_no_count_line_on_truncation(self) -> None:
        buffer = io.StringIO()
        with mock.patch.object(bf, "resolve_repo", return_value="owner/repo"), \
                mock.patch.object(bf, "fetch_issue_comments", return_value=[]), \
                mock.patch.object(bf, "fetch_pull_request_reviews", return_value=[]), \
                mock.patch.object(
                    bf, "fetch_review_threads",
                    return_value=[_thread([_comment()], truncated=True, total=150)]):
            with redirect_stdout(buffer):
                code = bf.main(["--pr", "1", "--self", "me[bot]"])
        self.assertEqual(code, 2)
        self.assertNotIn("findings=", buffer.getvalue())


if __name__ == "__main__":
    unittest.main()

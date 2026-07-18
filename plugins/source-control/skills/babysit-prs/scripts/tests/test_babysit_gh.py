"""GitHub read helpers: discovery axis matrix and the review-thread paginator.

Ports the discovery, author-scope, and review-thread coverage onto
`babysit_gh`. Network is stubbed by monkeypatching the module's `gh_json` /
`run_gh` / `list_repos_for_owner` seams; no real gh process is spawned.
"""

from __future__ import annotations

import pathlib
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_gh as gh


class ParseRepoTests(unittest.TestCase):
    def test_repo_number_canonicalizes_owner_casing(self) -> None:
        repo, number = gh.parse_repo_number("Owner/Repo#42")
        self.assertEqual((repo, number), ("owner/repo", 42))

    def test_repo_url_form_is_accepted(self) -> None:
        repo, number = gh.parse_repo_number("https://github.com/Owner/Repo/pull/7")
        self.assertEqual((repo, number), ("owner/repo", 7))

    def test_malformed_reference_is_rejected(self) -> None:
        for value in ("owner", "owner/repo", "owner//repo#1", "owner/repo#x"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                gh.parse_repo_number(value)

    def test_parse_repo_normalizes_and_validates(self) -> None:
        self.assertEqual(gh.parse_repo("Owner/Repo"), "owner/repo")
        with self.assertRaises(ValueError):
            gh.parse_repo("owner/repo#1")


class ResolveAuthorTests(unittest.TestCase):
    def test_none_passes_through_without_gh(self) -> None:
        with mock.patch.object(gh, "run_gh") as run_gh:
            self.assertIsNone(gh.resolve_author(None))
            run_gh.assert_not_called()

    def test_literal_login_is_not_resolved(self) -> None:
        with mock.patch.object(gh, "run_gh") as run_gh:
            self.assertEqual(gh.resolve_author("someone"), "someone")
            run_gh.assert_not_called()

    def test_me_resolves_to_the_authenticated_login(self) -> None:
        with mock.patch.object(gh, "run_gh", return_value="octocat\n"):
            self.assertEqual(gh.resolve_author("@me"), "octocat")

    def test_me_with_empty_login_fails_closed(self) -> None:
        with mock.patch.object(gh, "run_gh", return_value="\n"), \
                self.assertRaises(RuntimeError):
            gh.resolve_author("@me")


class DiscoverPrsTests(unittest.TestCase):
    def test_exactly_one_axis_is_required(self) -> None:
        with self.assertRaises(ValueError):
            gh.discover_prs()
        with self.assertRaises(ValueError):
            gh.discover_prs(owners=["o"], repos=["o/r"])

    def test_explicit_repos_are_listed_sorted_and_deduped(self) -> None:
        def fake_gh_json(args: list[str]) -> Any:
            repo = args[args.index("-R") + 1]
            if repo == "owner/beta":
                return [{"number": 2, "repository": {"nameWithOwner": "owner/beta"}}]
            return [
                {"number": 5, "repository": {"nameWithOwner": "owner/alpha"}},
                {"number": 1, "repository": {"nameWithOwner": "owner/alpha"}},
            ]

        with mock.patch.object(gh, "gh_json", side_effect=fake_gh_json):
            found, errors = gh.discover_prs(repos=["owner/beta", "owner/alpha"],
                                            limit=100)
        self.assertEqual(errors, [])
        self.assertEqual(
            found, [("owner/alpha", 1), ("owner/alpha", 5), ("owner/beta", 2)]
        )

    def test_repo_limit_reached_flags_possible_truncation(self) -> None:
        rows = [{"number": n, "repository": {"nameWithOwner": "owner/r"}}
                for n in range(2)]
        with mock.patch.object(gh, "gh_json", return_value=rows):
            _, errors = gh.discover_prs(repos=["owner/r"], limit=2)
        self.assertTrue(any("result limit" in error for error in errors))

    def test_owner_with_zero_repositories_is_tolerated(self) -> None:
        def fake_gh_json(args: list[str]) -> Any:
            if args and args[0] == "search":
                raise RuntimeError("owner qualifier rejected: no repositories")
            return []

        with mock.patch.object(gh, "gh_json", side_effect=fake_gh_json), \
                mock.patch.object(gh, "list_repos_for_owner", return_value=[]):
            found, errors = gh.discover_prs(owners=["empty-owner"], limit=100)
        self.assertEqual(found, [])
        self.assertEqual(errors, [])

    def test_owner_search_failure_with_repos_is_reported(self) -> None:
        def fake_gh_json(args: list[str]) -> Any:
            if args and args[0] == "search":
                raise RuntimeError("transient search failure")
            return []

        with mock.patch.object(gh, "gh_json", side_effect=fake_gh_json), \
                mock.patch.object(gh, "list_repos_for_owner",
                                  return_value=["owner/r"]):
            _, errors = gh.discover_prs(owners=["owner"], limit=100)
        self.assertTrue(any("owner search" in error for error in errors))


def _graphql(nodes: list[dict[str, Any]], *, has_next: bool = False,
             cursor: str | None = None) -> dict[str, Any]:
    return {
        "data": {"repository": {"pullRequest": {"reviewThreads": {
            "pageInfo": {"hasNextPage": has_next, "endCursor": cursor},
            "nodes": nodes,
        }}}}
    }


def _comment(**over: Any) -> dict[str, Any]:
    base = {"author": {"__typename": "User", "login": "x"}, "body": "b",
            "path": "p", "url": "u", "createdAt": "", "updatedAt": "",
            "databaseId": 1}
    base.update(over)
    return base


def _thread(comments: list[dict[str, Any]], total: int, *,
            comments_has_next: bool = False, **over: Any) -> dict[str, Any]:
    base = {
        "id": "t1", "isResolved": False, "isOutdated": False,
        "comments": {"totalCount": total,
                     "pageInfo": {"hasNextPage": comments_has_next},
                     "nodes": comments},
    }
    base.update(over)
    return base


class FetchReviewThreadsTests(unittest.TestCase):
    def test_oversized_thread_is_returned_truncated_without_raising(self) -> None:
        response = _graphql([_thread([_comment()], total=150,
                                     comments_has_next=True)])
        with mock.patch.object(gh, "gh_json", return_value=response):
            threads = gh.fetch_review_threads("owner/repo", 1)
        self.assertEqual(len(threads), 1)
        self.assertTrue(threads[0]["comments_truncated"])
        self.assertEqual(threads[0]["comments_total_count"], 150)

    def test_zero_comment_thread_does_not_raise(self) -> None:
        response = _graphql([_thread([], total=0)])
        with mock.patch.object(gh, "gh_json", return_value=response):
            threads = gh.fetch_review_threads("owner/repo", 1)
        self.assertEqual(threads[0]["comments"], [])
        self.assertFalse(threads[0]["comments_truncated"])

    def test_resolved_threads_are_dropped_unless_requested(self) -> None:
        response = _graphql([_thread([_comment()], total=1, isResolved=True)])
        with mock.patch.object(gh, "gh_json", return_value=response):
            self.assertEqual(gh.fetch_review_threads("owner/repo", 1), [])
        with mock.patch.object(gh, "gh_json", return_value=response):
            included = gh.fetch_review_threads("owner/repo", 1, include_resolved=True)
        self.assertEqual(len(included), 1)

    def test_projection_maps_each_record(self) -> None:
        response = _graphql([_thread([_comment()], total=1)])
        with mock.patch.object(gh, "gh_json", return_value=response):
            ids = gh.fetch_review_threads("owner/repo", 1,
                                          projection=lambda record: record["id"])
        self.assertEqual(ids, ["t1"])

    def test_malformed_page_info_fails_closed(self) -> None:
        response = {"data": {"repository": {"pullRequest": {"reviewThreads": {
            "pageInfo": {"hasNextPage": "yes"}, "nodes": []}}}}}
        with mock.patch.object(gh, "gh_json", return_value=response), \
                self.assertRaises(RuntimeError):
            gh.fetch_review_threads("owner/repo", 1)

    def test_graphql_errors_field_fails_closed(self) -> None:
        with mock.patch.object(gh, "gh_json",
                               return_value={"errors": [{"message": "boom"}]}), \
                self.assertRaises(RuntimeError):
            gh.fetch_review_threads("owner/repo", 1)

    def test_paginates_across_thread_pages(self) -> None:
        pages = [
            _graphql([_thread([_comment()], total=1, id="a")],
                     has_next=True, cursor="c1"),
            _graphql([_thread([_comment()], total=1, id="b")]),
        ]
        with mock.patch.object(gh, "gh_json", side_effect=pages):
            threads = gh.fetch_review_threads("owner/repo", 1)
        self.assertEqual([thread["id"] for thread in threads], ["a", "b"])

    def test_missing_cursor_on_next_page_fails_closed(self) -> None:
        response = _graphql([_thread([_comment()], total=1)], has_next=True,
                            cursor="")
        with mock.patch.object(gh, "gh_json", return_value=response), \
                self.assertRaises(RuntimeError):
            gh.fetch_review_threads("owner/repo", 1)

    def test_invalid_comments_first_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            gh.fetch_review_threads("owner/repo", 1, comments_first=0)
        with self.assertRaises(ValueError):
            gh.fetch_review_threads("owner/repo", 1, comments_first=101)


if __name__ == "__main__":
    unittest.main()

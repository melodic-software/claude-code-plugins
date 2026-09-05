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

import babysit_checks as checks
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

    def test_a_traversal_segment_is_never_a_repository(self) -> None:
        # `.` and `..` satisfy the repository charset but address a directory,
        # and both parsers feed path construction (lease files, worktree dirs).
        # Both entry points must refuse them, not just the one a caller happens
        # to reach.
        for value in (".", ".."):
            with self.subTest(repo=value):
                with self.assertRaises(ValueError):
                    gh.parse_repo(f"owner/{value}")
                with self.assertRaises(ValueError):
                    gh.parse_repo_number(f"owner/{value}#1")

    def test_a_dotted_repository_name_is_still_accepted(self) -> None:
        # The other side of the traversal rule: `.` is legal *within* a
        # repository name, so refusing the character outright would reject real
        # repositories.
        self.assertEqual(gh.parse_repo("Owner/repo.js"), "owner/repo.js")
        self.assertEqual(gh.parse_repo_number("owner/repo.js#4"), ("owner/repo.js", 4))


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
        with (
            mock.patch.object(gh, "run_gh", return_value="\n"),
            self.assertRaises(RuntimeError),
        ):
            gh.resolve_author("@me")


class ResolveAuthorsTests(unittest.TestCase):
    def test_empty_yields_no_authors(self) -> None:
        self.assertEqual(gh.resolve_authors(None), [])
        self.assertEqual(gh.resolve_authors(""), [])
        self.assertEqual(gh.resolve_authors(" , "), [])

    def test_comma_separated_logins_resolve_dedupe_and_keep_order(self) -> None:
        with mock.patch.object(gh, "run_gh", return_value="octocat\n"):
            self.assertEqual(
                gh.resolve_authors("alice, bob, @me, Alice"),
                ["alice", "bob", "octocat"],
            )


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
            found, errors = gh.discover_prs(
                repos=["owner/beta", "owner/alpha"], limit=100
            )
        self.assertEqual(errors, [])
        self.assertEqual(
            found, [("owner/alpha", 1), ("owner/alpha", 5), ("owner/beta", 2)]
        )

    def test_repo_limit_reached_flags_possible_truncation(self) -> None:
        rows = [
            {"number": n, "repository": {"nameWithOwner": "owner/r"}} for n in range(2)
        ]
        with mock.patch.object(gh, "gh_json", return_value=rows):
            _, errors = gh.discover_prs(repos=["owner/r"], limit=2)
        self.assertTrue(any("result limit" in error for error in errors))

    def test_owner_with_zero_repositories_is_tolerated(self) -> None:
        def fake_gh_json(args: list[str]) -> Any:
            if args and args[0] == "search":
                raise RuntimeError("owner qualifier rejected: no repositories")
            return []

        with (
            mock.patch.object(gh, "gh_json", side_effect=fake_gh_json),
            mock.patch.object(gh, "list_repos_for_owner", return_value=[]),
        ):
            found, errors = gh.discover_prs(owners=["empty-owner"], limit=100)
        self.assertEqual(found, [])
        self.assertEqual(errors, [])

    def test_owner_search_failure_with_repos_is_reported(self) -> None:
        def fake_gh_json(args: list[str]) -> Any:
            if args and args[0] == "search":
                raise RuntimeError("transient search failure")
            return []

        with (
            mock.patch.object(gh, "gh_json", side_effect=fake_gh_json),
            mock.patch.object(gh, "list_repos_for_owner", return_value=["owner/r"]),
        ):
            _, errors = gh.discover_prs(owners=["owner"], limit=100)
        self.assertTrue(any("owner search" in error for error in errors))

    def test_multiple_authors_are_queried_separately_and_unioned(self) -> None:
        searched_authors: list[str | None] = []

        def fake_gh_json(args: list[str]) -> Any:
            author = args[args.index("--author") + 1] if "--author" in args else None
            if args and args[0] == "search":
                searched_authors.append(author)
                by_author = {
                    "alice": [
                        {"number": 1, "repository": {"nameWithOwner": "owner/r"}}
                    ],
                    "bob": [{"number": 2, "repository": {"nameWithOwner": "owner/r"}}],
                }
                return by_author.get(author, [])
            return []

        with (
            mock.patch.object(gh, "gh_json", side_effect=fake_gh_json),
            mock.patch.object(gh, "list_repos_for_owner", return_value=[]),
        ):
            found, errors = gh.discover_prs(
                owners=["owner"], authors=["alice", "bob"], limit=100
            )
        self.assertEqual(sorted(searched_authors), ["alice", "bob"])
        self.assertEqual(found, [("owner/r", 1), ("owner/r", 2)])
        self.assertEqual(errors, [])

    def test_owner_errors_are_deduped_across_authors(self) -> None:
        def fake_gh_json(args: list[str]) -> Any:
            if args and args[0] == "search":
                raise RuntimeError("transient search failure")
            return []

        with (
            mock.patch.object(gh, "gh_json", side_effect=fake_gh_json),
            mock.patch.object(gh, "list_repos_for_owner", return_value=["owner/r"]),
        ):
            _, errors = gh.discover_prs(
                owners=["owner"], authors=["alice", "bob"], limit=100
            )
        self.assertEqual(len([error for error in errors if "owner search" in error]), 1)


def _graphql(
    nodes: list[dict[str, Any]], *, has_next: bool = False, cursor: str | None = None
) -> dict[str, Any]:
    return {
        "data": {
            "repository": {
                "pullRequest": {
                    "reviewThreads": {
                        "pageInfo": {"hasNextPage": has_next, "endCursor": cursor},
                        "nodes": nodes,
                    }
                }
            }
        }
    }


def _comment(**over: Any) -> dict[str, Any]:
    base = {
        "author": {"__typename": "User", "login": "x"},
        "body": "b",
        "path": "p",
        "url": "u",
        "createdAt": "",
        "updatedAt": "",
        "databaseId": 1,
    }
    base.update(over)
    return base


def _thread(
    comments: list[dict[str, Any]],
    total: int,
    *,
    comments_has_next: bool = False,
    **over: Any,
) -> dict[str, Any]:
    base = {
        "id": "t1",
        "isResolved": False,
        "isOutdated": False,
        "comments": {
            "totalCount": total,
            "pageInfo": {"hasNextPage": comments_has_next},
            "nodes": comments,
        },
    }
    base.update(over)
    return base


class FetchReviewThreadsTests(unittest.TestCase):
    def test_oversized_thread_is_returned_truncated_without_raising(self) -> None:
        response = _graphql([_thread([_comment()], total=150, comments_has_next=True)])
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
            ids = gh.fetch_review_threads(
                "owner/repo", 1, projection=lambda record: record["id"]
            )
        self.assertEqual(ids, ["t1"])

    def test_malformed_page_info_fails_closed(self) -> None:
        response = {
            "data": {
                "repository": {
                    "pullRequest": {
                        "reviewThreads": {
                            "pageInfo": {"hasNextPage": "yes"},
                            "nodes": [],
                        }
                    }
                }
            }
        }
        with (
            mock.patch.object(gh, "gh_json", return_value=response),
            self.assertRaises(RuntimeError),
        ):
            gh.fetch_review_threads("owner/repo", 1)

    def test_graphql_errors_field_fails_closed(self) -> None:
        with (
            mock.patch.object(
                gh, "gh_json", return_value={"errors": [{"message": "boom"}]}
            ),
            self.assertRaises(RuntimeError),
        ):
            gh.fetch_review_threads("owner/repo", 1)

    def test_paginates_across_thread_pages(self) -> None:
        pages = [
            _graphql(
                [_thread([_comment()], total=1, id="a")], has_next=True, cursor="c1"
            ),
            _graphql([_thread([_comment()], total=1, id="b")]),
        ]
        with mock.patch.object(gh, "gh_json", side_effect=pages):
            threads = gh.fetch_review_threads("owner/repo", 1)
        self.assertEqual([thread["id"] for thread in threads], ["a", "b"])

    def test_missing_cursor_on_next_page_fails_closed(self) -> None:
        response = _graphql([_thread([_comment()], total=1)], has_next=True, cursor="")
        with (
            mock.patch.object(gh, "gh_json", return_value=response),
            self.assertRaises(RuntimeError),
        ):
            gh.fetch_review_threads("owner/repo", 1)

    def test_invalid_comments_first_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            gh.fetch_review_threads("owner/repo", 1, comments_first=0)
        with self.assertRaises(ValueError):
            gh.fetch_review_threads("owner/repo", 1, comments_first=101)


class FetchPullRequestCommitsTests(unittest.TestCase):
    """`fetch_pull_request_commits` (#2265): the signature-verification read
    behind the required-signatures merge blocker. A commit whose verification
    block is missing must surface as unverified (`unreadable`), never be
    skipped -- the consumer may only ever over-report.
    """

    def test_verification_is_projected_per_commit(self) -> None:
        rows = [
            {
                "sha": "a" * 40,
                "commit": {"verification": {"verified": True, "reason": "valid"}},
            },
            {
                "sha": "b" * 40,
                "commit": {"verification": {"verified": False, "reason": "no_user"}},
            },
        ]
        with mock.patch.object(gh, "gh_json", side_effect=[rows, len(rows)]) as gh_json:
            out = gh.fetch_pull_request_commits("owner/repo", 5)
        self.assertEqual(
            out,
            [
                {"sha": "a" * 40, "verified": True, "reason": "valid"},
                {"sha": "b" * 40, "verified": False, "reason": "no_user"},
            ],
        )
        commits_call = gh_json.call_args_list[0]
        endpoint = commits_call.args[0][1]
        self.assertIn("repos/owner/repo/pulls/5/commits", endpoint)
        self.assertIn("per_page=100", endpoint)
        self.assertIn("--paginate", commits_call.args[0])

    def test_pull_commits_cap_raises_when_walk_is_short(self) -> None:
        rows = [
            {
                "sha": f"{i:040x}",
                "commit": {"verification": {"verified": True, "reason": "valid"}},
            }
            for i in range(250)
        ]
        with mock.patch.object(gh, "gh_json") as gh_json_mock:
            gh_json_mock.side_effect = [rows, 300]
            with self.assertRaises(RuntimeError) as ctx:
                gh.fetch_pull_request_commits("owner/repo", 5)
        self.assertIn("250-commit cap", str(ctx.exception))
        self.assertIn("walked 250 of 300", str(ctx.exception))

    def test_missing_verification_reads_unverified_unreadable(self) -> None:
        rows = [
            {"sha": "c" * 40, "commit": {}},
            {"sha": "d" * 40},
            {"sha": "e" * 40, "commit": {"verification": {"verified": True}}},
        ]
        with mock.patch.object(gh, "gh_json", return_value=rows):
            out = gh.fetch_pull_request_commits("owner/repo", 5)
        self.assertEqual(
            out,
            [
                {"sha": "c" * 40, "verified": False, "reason": "unreadable"},
                {"sha": "d" * 40, "verified": False, "reason": "unreadable"},
                # verified without a reason string: verified wins, reason
                # falls back rather than fabricating a value.
                {"sha": "e" * 40, "verified": True, "reason": "unreadable"},
            ],
        )


class RestHydrateReviewsTests(unittest.TestCase):
    """`rest_hydrate_reviews` (#683): the untyped `latestReviews` `gh pr view
    --json` supplies must not survive hydration once the fully-typed REST
    `reviews` list has replaced `pr["reviews"]` -- otherwise the same bot
    actor's `latestReviews` copy (no `__typename`, no `[bot]` login suffix)
    still leaks into `latest_reviews_by_author`'s merge and misclassifies as
    human.
    """

    def test_reviews_replaced_and_latest_reviews_dropped(self) -> None:
        rest_rows = [
            {
                "id": 1,
                "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"},
                "state": "COMMENTED",
                "body": "Codex review",
                "submitted_at": "2026-07-20T15:57:46Z",
                "commit_id": "abc123",
            }
        ]
        pr = {
            "reviews": [],
            "latestReviews": [
                {
                    "author": {"login": "chatgpt-codex-connector"},
                    "id": "",
                    "state": "COMMENTED",
                    "submittedAt": "2026-07-20T15:57:46Z",
                    "body": "Codex review",
                    "commit": {"oid": ""},
                }
            ],
        }
        with mock.patch.object(gh, "gh_json", return_value=rest_rows):
            gh.rest_hydrate_reviews(pr, "owner/repo", 1)
        self.assertNotIn("latestReviews", pr)
        self.assertEqual(len(pr["reviews"]), 1)
        self.assertEqual(pr["reviews"][0]["author"]["__typename"], "Bot")
        self.assertEqual(
            pr["reviews"][0]["author"]["login"], "chatgpt-codex-connector[bot]"
        )

    def test_missing_latest_reviews_key_does_not_raise(self) -> None:
        pr = {"reviews": []}
        with mock.patch.object(gh, "gh_json", return_value=[]):
            gh.rest_hydrate_reviews(pr, "owner/repo", 1)
        self.assertNotIn("latestReviews", pr)
        self.assertEqual(pr["reviews"], [])


GRAPHQL_403 = RuntimeError(
    "gh api graphql failed: gh: this GraphQL operation is not enabled for this "
    "session (HTTP 403)"
)


class GraphQLAvailabilityClassificationTests(unittest.TestCase):
    """The 403 that means "this session is served no GraphQL" must be separable
    from every other gh failure, or the REST substitution either never fires or
    fires over a real error and hides it."""

    def test_the_pinned_operation_refusal_is_recognized(self) -> None:
        self.assertTrue(gh.is_graphql_unavailable(GRAPHQL_403))

    def test_a_bare_403_is_recognized(self) -> None:
        self.assertTrue(
            gh.is_graphql_unavailable(RuntimeError("gh: Forbidden (HTTP 403)"))
        )

    def test_other_failures_are_not_reclassified(self) -> None:
        for message in (
            "gh: Not Found (HTTP 404)",
            "gh: Bad credentials (HTTP 401)",
            "gh executable not found on PATH",
            "gh api graphql timed out after 60s",
        ):
            with self.subTest(message=message):
                self.assertFalse(gh.is_graphql_unavailable(RuntimeError(message)))

    def test_http_status_reads_the_last_attempt(self) -> None:
        self.assertEqual(gh.gh_http_status("(HTTP 502) ... (HTTP 403)"), 403)
        self.assertIsNone(gh.gh_http_status("connection reset"))


class ViewPrRestFallbackTests(unittest.TestCase):
    """`gh pr view --json` is GraphQL end to end, so the refusal takes out the
    engine's primary hydration call. Every field REST can source is re-sourced
    rather than lost."""

    REST_PULL = {
        "number": 7,
        "title": "a title",
        "state": "open",
        "draft": False,
        "merged": False,
        "mergeable": True,
        "mergeable_state": "blocked",
        "maintainer_can_modify": True,
        "updated_at": "2026-01-02T03:04:05Z",
        "html_url": "https://github.com/owner/repo/pull/7",
        "user": {"login": "someone", "type": "User"},
        "labels": [{"name": "do-not-merge"}],
        "base": {"ref": "main", "repo": {"full_name": "owner/repo"}},
        "head": {
            "ref": "feature",
            "sha": "a" * 40,
            "repo": {"full_name": "fork/repo", "owner": {"login": "fork"}},
        },
    }

    def _rest_gh_json(self, args: list[str]) -> Any:
        endpoint = args[1] if len(args) > 1 else ""
        if endpoint == "repos/owner/repo/pulls/7":
            return dict(self.REST_PULL)
        if endpoint.startswith("repos/owner/repo/actions/runs"):
            return {"workflow_runs": [{"check_suite_id": 11, "name": "ci"}]}
        if endpoint.endswith("/check-runs?per_page=100"):
            return [
                [
                    {
                        "name": "build",
                        "status": "completed",
                        "conclusion": "failure",
                        "started_at": "2026-01-02T00:00:00Z",
                        "completed_at": "2026-01-02T00:10:00Z",
                        "details_url": "https://example/run",
                        "check_suite": {"id": 11},
                    }
                ]
            ]
        if endpoint.endswith("/status"):
            return {
                "statuses": [
                    {
                        "context": "legacy/status",
                        "state": "success",
                        "target_url": "https://example/status",
                        "created_at": "2026-01-02T00:00:00Z",
                    }
                ]
            }
        if endpoint.endswith("/reviews?per_page=100"):
            return [
                [
                    {
                        "id": 1,
                        "user": {"login": "reviewer", "type": "User"},
                        "state": "CHANGES_REQUESTED",
                        "body": "no",
                        "submitted_at": "2026-01-02T00:00:00Z",
                        "commit_id": "a" * 40,
                    }
                ]
            ]
        raise AssertionError(f"unexpected REST call: {args}")

    def _view(self, fields: list[str]) -> tuple[dict[str, Any], bool]:
        def run_json(args: list[str]) -> Any:
            if args[:2] == ["pr", "view"]:
                raise GRAPHQL_403
            raise AssertionError(f"unexpected call: {args}")

        with mock.patch.object(gh, "gh_json", side_effect=self._rest_gh_json):
            return gh.view_pr_fields("owner/repo", 7, fields, run_json=run_json)

    def test_the_bundle_is_rebuilt_from_rest(self) -> None:
        bundle, graphql = self._view(
            [
                "state",
                "isDraft",
                "mergeable",
                "mergeStateStatus",
                "headRefOid",
                "baseRefName",
                "title",
                "labels",
                "url",
                "isCrossRepository",
                "headRepository",
                "headRepositoryOwner",
                "statusCheckRollup",
            ]
        )
        self.assertFalse(graphql)
        self.assertEqual(bundle["state"], "OPEN")
        self.assertEqual(bundle["mergeable"], "MERGEABLE")
        self.assertEqual(bundle["mergeStateStatus"], "BLOCKED")
        self.assertEqual(bundle["headRefOid"], "a" * 40)
        self.assertEqual(bundle["baseRefName"], "main")
        self.assertEqual(bundle["labels"], [{"name": "do-not-merge"}])
        self.assertTrue(bundle["isCrossRepository"])
        self.assertEqual(bundle["headRepository"]["nameWithOwner"], "fork/repo")
        self.assertEqual(bundle["headRepositoryOwner"]["login"], "fork")

    def test_the_rollup_carries_both_node_types_and_classifies(self) -> None:
        bundle, _ = self._view(["statusCheckRollup"])
        classified = checks.classify_checks(bundle["statusCheckRollup"])
        self.assertEqual(classified["failing"], ["build"])
        self.assertEqual(classified["success"], 1)
        rollup = {entry["__typename"] for entry in bundle["statusCheckRollup"]}
        self.assertEqual(rollup, {"CheckRun", "StatusContext"})
        self.assertEqual(bundle["statusCheckRollup"][0]["workflowName"], "ci")

    def test_only_the_blocking_review_direction_is_derived(self) -> None:
        bundle, _ = self._view(["reviewDecision"])
        self.assertEqual(bundle["reviewDecision"], "CHANGES_REQUESTED")

    def test_an_approval_is_never_derived_from_rest(self) -> None:
        # GraphQL's reviewDecision folds in CODEOWNERS and the required
        # reviewer count; deriving APPROVED here would clear the merge gate's
        # approval hold on evidence that cannot prove it.
        self.assertEqual(
            gh.rest_review_decision(
                [{"state": "APPROVED", "author": {"login": "a"}, "submittedAt": "1"}]
            ),
            "",
        )

    def test_a_graphql_only_field_is_absent_never_fabricated(self) -> None:
        bundle, _ = self._view(["state", "closingIssuesReferences"])
        self.assertNotIn("closingIssuesReferences", bundle)

    def test_a_non_403_failure_is_not_swallowed(self) -> None:
        def run_json(args: list[str]) -> Any:
            raise RuntimeError("gh: Not Found (HTTP 404)")

        with self.assertRaises(RuntimeError) as caught:
            gh.view_pr_fields("owner/repo", 7, ["state"], run_json=run_json)
        self.assertIn("404", str(caught.exception))


class ThreadResolutionFailsClosedTests(unittest.TestCase):
    """Thread resolution is GraphQL-only. An empty list would read as "zero
    unresolved threads", which is the false-clean the merge gate exists to
    prevent, so the refusal is raised as itself."""

    def test_the_paginator_raises_rather_than_returning_empty(self) -> None:
        with (
            mock.patch.object(gh, "gh_json", side_effect=GRAPHQL_403),
            self.assertRaises(gh.GraphQLUnavailableError),
        ):
            gh.fetch_review_threads("owner/repo", 1)

    def test_an_ordinary_graphql_failure_stays_a_plain_runtime_error(self) -> None:
        with (
            mock.patch.object(gh, "gh_json", side_effect=RuntimeError("(HTTP 502)")),
            self.assertRaises(RuntimeError) as caught,
        ):
            gh.fetch_review_threads("owner/repo", 1)
        self.assertNotIsInstance(caught.exception, gh.GraphQLUnavailableError)

    def test_inline_comments_are_re_sourced_over_rest_and_marked_unproven(self) -> None:
        rest_comments = [
            [
                {
                    "id": 5,
                    "user": {"login": "reviewer", "type": "User"},
                    "body": "please fix",
                    "path": "a.py",
                    "html_url": "https://example/c",
                    "created_at": "2026-01-01T00:00:00Z",
                    "updated_at": "2026-01-01T00:00:00Z",
                }
            ]
        ]

        def gh_json(args: list[str]) -> Any:
            if args[:2] == ["api", "graphql"]:
                raise GRAPHQL_403
            return rest_comments

        with mock.patch.object(gh, "gh_json", side_effect=gh_json):
            comments = gh.fetch_unresolved_review_comments("owner/repo", 1)
        self.assertEqual(len(comments), 1)
        self.assertTrue(comments[0]["threadResolutionUnproven"])
        self.assertFalse(comments[0]["threadIsOutdated"])
        self.assertEqual(comments[0]["author"]["login"], "reviewer")


if __name__ == "__main__":
    unittest.main()

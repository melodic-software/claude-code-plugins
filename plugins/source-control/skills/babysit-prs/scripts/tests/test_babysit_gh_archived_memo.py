"""`repository_is_archived` reads each repository's archived flag once per
process; a failed read is not kept."""

from __future__ import annotations

import pathlib
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_gh as gh

GRAPHQL_403 = "gh: GraphQL is not available from Claude Code sessions (HTTP 403)"


class RepositoryArchivedMemoTests(unittest.TestCase):
    def setUp(self) -> None:
        gh.reset_repository_archived_cache()
        self.addCleanup(gh.reset_repository_archived_cache)
        self.calls: list[list[str]] = []

    def fake(self, answers: dict[str, Any]) -> Any:
        def gh_json(args: list[str], *_rest: Any) -> Any:
            self.calls.append(args)
            answer = answers[args[2] if args[0] == "repo" else args[1]]
            if isinstance(answer, Exception):
                raise answer
            return answer

        return mock.patch.object(gh, "gh_json", side_effect=gh_json)

    def test_n_lookups_of_one_repository_make_one_call(self) -> None:
        with self.fake({"acme/widgets": {"isArchived": True}}):
            answers = [gh.repository_is_archived("acme/widgets") for _ in range(5)]
        self.assertEqual(answers, [True] * 5)
        self.assertEqual(len(self.calls), 1)

    def test_the_key_ignores_case_and_each_repository_is_read_once(self) -> None:
        with self.fake(
            {"acme/widgets": {"isArchived": False}, "acme/gears": {"isArchived": True}}
        ):
            gh.repository_is_archived("acme/widgets")
            self.assertFalse(gh.repository_is_archived("ACME/Widgets"))
            self.assertTrue(gh.repository_is_archived("acme/gears"))
            self.assertTrue(gh.repository_is_archived("acme/gears"))
        self.assertEqual(len(self.calls), 2)

    def test_a_failed_read_is_not_kept(self) -> None:
        with self.fake({"acme/widgets": RuntimeError("gh: Bad Gateway (HTTP 502)")}):
            with self.assertRaises(RuntimeError):
                gh.repository_is_archived("acme/widgets")
        with self.fake({"acme/widgets": {"isArchived": False}}):
            self.assertFalse(gh.repository_is_archived("acme/widgets"))
            self.assertFalse(gh.repository_is_archived("acme/widgets"))
        self.assertEqual(len(self.calls), 2)

    def test_the_rest_fallback_is_kept_too(self) -> None:
        with self.fake(
            {
                "acme/widgets": RuntimeError(GRAPHQL_403),
                "repos/acme/widgets": {"archived": True},
            }
        ):
            self.assertTrue(gh.repository_is_archived("acme/widgets"))
            self.assertTrue(gh.repository_is_archived("acme/widgets"))
        self.assertEqual(
            [call[:2] for call in self.calls],
            [["repo", "view"], ["api", "repos/acme/widgets"]],
        )


if __name__ == "__main__":
    unittest.main()

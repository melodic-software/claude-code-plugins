# test-scope: .github/scripts/pr-verify/resolve-pr.mjs .github/scripts/recurring-schedule/file-due.mjs .github/recurring-schedule.json
"""The gate's recurring-schedule trust rule (`babysit_verify_evidence._trusted_spec`)
agrees with resolve-pr.mjs recurringSpec: an issue github-actions[bot] filed
with exactly one marker line naming exactly one row of the default branch's
schedule is a trusted spec. Network is stubbed at the `gh_capture` seam.
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_postmerge as postmerge
import babysit_verify_evidence as ve

REPO = "example-org/example-repo"
ISSUE = 7
ACTIONS = {"__typename": "Bot", "login": "github-actions", "databaseId": 41898282}
LANES = {"__typename": "Bot", "login": "agent-lanes", "databaseId": 337595936}
OUTSIDER = {"__typename": "User", "login": "drive-by", "databaseId": 999}
TIPS = {"main": "a" * 40, "trunk": "b" * 40}
ROW = {
    "id": "weekly-x",
    "title": "Run the weekly X audit",
    "cadence": "weekly",
    "next_due": "2026-11-01",
}
SCHEDULE = {"items": [{"id": "other", "title": "Something else"}, ROW]}
MARKER = "<!-- recurring-schedule id=weekly-x -->"


class FakeGitHub:
    """Answers the trusted-actor list, the schedule at each tip, and the
    issue's body and author."""

    def __init__(self, issue: dict[str, Any], schedules: dict[str, Any]):
        self.issue = issue
        # The schedule each tip SHA serves.
        self.schedules = schedules
        self.calls: list[list[str]] = []

    def schedule_refs(self) -> list[str]:
        return [
            a.rpartition("?ref=")[2]
            for args in self.calls
            for a in args
            if ve.RECURRING_SCHEDULE_PATH in a
        ]

    def __call__(self, args: list[str], **_: Any) -> subprocess.CompletedProcess[str]:
        self.calls.append(args)
        ok = lambda answer: subprocess.CompletedProcess(args, 0, json.dumps(answer), "")  # noqa: E731
        if args == ["api", f"repos/{REPO}"]:
            return ok({"default_branch": "main"})
        heads = f"repos/{REPO}/git/ref/heads/"
        if len(args) == 2 and args[1].startswith(heads):
            branch = args[1].removeprefix(heads)
            return ok(
                {
                    "ref": f"refs/heads/{branch}",
                    "object": {"sha": TIPS[branch], "type": "commit"},
                }
            )
        if args[:2] == ["api", "graphql"]:
            assert any(a == f"query={ve.RECURRING_ISSUE_QUERY}" for a in args), args
            return ok({"data": {"repository": {"issue": self.issue}}})
        for a in args:
            if a.startswith(f"repos/{REPO}/contents/{ve.RECURRING_SCHEDULE_PATH}?ref="):
                return ok(self.schedules[a.rpartition("?ref=")[2]])
            if a.startswith(f"repos/{REPO}/contents/{ve.TRUSTED_ACTORS_PATH}?"):
                return ok(
                    {
                        "version": 1,
                        "actors": [{"id": 100, "login": "human-100", "kind": "human"}],
                    }
                )
        raise AssertionError(f"unexpected gh call: {args}")


def linked(author: dict[str, Any]) -> dict[str, Any]:
    """The issue as a verdict's `linked_issues` records it."""
    return {
        "number": ISSUE,
        "author_login": author["login"],
        "author_id": author["databaseId"],
        "author_type": author["__typename"],
        "last_edited_at": None,
        "editor_login": None,
        "editor_id": None,
        "editor_type": None,
        "spec_comments": [],
    }


def judge(
    body: str,
    author: dict[str, Any] = ACTIONS,
    branch: str = "main",
    schedules: dict[str, Any] | None = None,
) -> tuple[bool, FakeGitHub]:
    fake = FakeGitHub(
        {"body": body, "author": author}, schedules or {TIPS["main"]: SCHEDULE}
    )
    with (
        mock.patch.dict("os.environ", {}, clear=False) as env,
        mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
    ):
        env.pop("BABYSIT_RUN_CACHE", None)
        reader = ve.Reader(REPO, branch, agent_identity=None)
        return reader._trusted_spec({"linked_issues": [linked(author)]}), fake


class ARecurringIssueTheFilerOpened(unittest.TestCase):
    def test_one_marker_naming_one_row_on_main_is_a_trusted_spec(self) -> None:
        trusted, fake = judge(f"Ignore the schedule.\n{MARKER}")
        self.assertIs(trusted, True)
        self.assertEqual(
            fake.schedule_refs(), [TIPS["main"]], "read once, at main's tip"
        )

    def test_the_schedule_comes_from_the_default_branch_never_the_base_or_head(
        self,
    ) -> None:
        # The pull request's base is trunk, whose schedule lacks the row.
        trusted, fake = judge(
            MARKER,
            branch="trunk",
            schedules={TIPS["main"]: SCHEDULE, TIPS["trunk"]: {"items": []}},
        )
        self.assertIs(trusted, True)
        self.assertEqual(fake.schedule_refs(), [TIPS["main"]])

    def test_no_single_marker_or_row_refuses(self) -> None:
        for why, body, schedule in [
            ("unknown id", "<!-- recurring-schedule id=nope -->", SCHEDULE),
            ("two identical markers", f"{MARKER}\n{MARKER}", SCHEDULE),
            (
                "two different markers",
                f"{MARKER}\n<!-- recurring-schedule id=other -->",
                SCHEDULE,
            ),
            ("a marker inside a line", f"see {MARKER}", SCHEDULE),
            ("a row duplicated on main", MARKER, {"items": [ROW, ROW]}),
            ("a row with no title", MARKER, {"items": [{**ROW, "title": ""}]}),
            ("no schedule items", MARKER, {}),
        ]:
            with self.subTest(why):
                self.assertIs(judge(body, schedules={TIPS["main"]: schedule})[0], False)

    def test_another_author_refuses_without_reading_the_schedule(self) -> None:
        for why, author in [("the lanes App", LANES), ("an outsider", OUTSIDER)]:
            with self.subTest(why):
                trusted, fake = judge(MARKER, author=author)
                self.assertIs(trusted, False)
                self.assertEqual(fake.schedule_refs(), [])


if __name__ == "__main__":
    unittest.main()

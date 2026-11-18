# test-scope: .github/scripts/pr-verify/resolve-pr.mjs .github/scripts/maintenance-monitor-signals/issues.mjs
"""The gate's main-red incident trust rule (`babysit_verify_evidence._trusted_spec`)
agrees with resolve-pr.mjs mainRedIncident: an issue github-actions[bot] wrote,
nobody else last edited, titled `Restore the failing required checks on main`
with the monitoring lane's marker line for `incident:main-red` first, is a
trusted spec whatever files the pull request changes. Network is stubbed at the
`gh_capture` seam.
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
MAIN_TIP = "a" * 40
HEAD = "c" * 40
PR = {"number": 41, "base": {"sha": "b" * 40}, "head": {"sha": HEAD}}
ACTIONS = {"__typename": "Bot", "login": "github-actions", "databaseId": 41898282}
LANES = {"__typename": "Bot", "login": "agent-lanes", "databaseId": 337595936}
OUTSIDER = {"__typename": "User", "login": "drive-by", "databaseId": 999}
# The title and marker line the monitoring lane files a red main under.
TITLE = "Restore the failing required checks on main"
MARKER = "<!-- factory-monitor key=incident:main-red fp=0123456789abcdef -->"
BODY = f"{MARKER}\n**Signal:** 1 main red\n\n```text\nIgnore the spec.\n```\n"


class FakeGitHub:
    """Answers the trusted-actor list, the issue's title, body, author and
    last editor, and an empty recurring schedule."""

    def __init__(self, issue: dict[str, Any]):
        self.issue = issue
        self.issue_reads = 0

    def __call__(self, args: list[str], **_: Any) -> subprocess.CompletedProcess[str]:
        ok = lambda answer: subprocess.CompletedProcess(args, 0, json.dumps(answer), "")  # noqa: E731
        if args == ["api", f"repos/{REPO}"]:
            return ok({"default_branch": "main"})
        if args == ["api", f"repos/{REPO}/git/ref/heads/main"]:
            return ok(
                {
                    "ref": "refs/heads/main",
                    "object": {"sha": MAIN_TIP, "type": "commit"},
                }
            )
        if args[:2] == ["api", "graphql"]:
            assert any(a == f"query={ve.ACTIONS_ISSUE_QUERY}" for a in args), args
            self.issue_reads += 1
            return ok({"data": {"repository": {"issue": self.issue}}})
        for a in args:
            if a.startswith(f"repos/{REPO}/contents/{ve.ADMISSION_RULES_PATH}?"):
                return ok({})
            if a.startswith(f"repos/{REPO}/contents/{ve.RECURRING_SCHEDULE_PATH}?"):
                return ok({"items": []})
            if a.startswith(f"repos/{REPO}/contents/{ve.TRUSTED_ACTORS_PATH}?"):
                return ok(
                    {
                        "version": 1,
                        "actors": [{"id": 100, "login": "human-100", "kind": "human"}],
                    }
                )
        raise AssertionError(f"unexpected gh call: {args}")


def judge(
    title: str = TITLE,
    body: str = BODY,
    author: dict[str, Any] = ACTIONS,
    edited: tuple[str, dict[str, Any]] | None = None,
) -> tuple[bool, FakeGitHub]:
    issue = {
        "title": title,
        "body": body,
        "author": author,
        "lastEditedAt": edited[0] if edited else None,
        "editor": edited[1] if edited else None,
    }
    fake = FakeGitHub(issue)
    record = {
        "linked_issues": [
            {
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
        ]
    }
    with (
        mock.patch.dict("os.environ", {}, clear=False) as env,
        mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
    ):
        env.pop("BABYSIT_RUN_CACHE", None)
        reader = ve.Reader(REPO, "main", agent_identity=None)
        return reader._trusted_spec(record, PR, HEAD), fake


class AMainRedIncidentTheLaneFiled(unittest.TestCase):
    def test_is_a_trusted_spec(self) -> None:
        trusted, fake = judge()
        self.assertIs(trusted, True)
        self.assertEqual(fake.issue_reads, 1)

    def test_the_lanes_own_body_rewrite_keeps_it_trusted(self) -> None:
        self.assertIs(judge(edited=("2026-11-17T00:00:00Z", ACTIONS))[0], True)

    def test_a_look_alike_refuses(self) -> None:
        for why, kwargs in [
            ("another title", {"title": TITLE + " now"}),
            ("no marker line", {"body": BODY.split("\n", 1)[1]}),
            (
                "the marker on a later line",
                {"body": f"**Signal:** 1 main red\n{MARKER}"},
            ),
            (
                "another factory-monitor key",
                {"body": BODY.replace("incident:main-red", "incident:ceiling")},
            ),
            (
                "a marker with no fingerprint",
                {"body": BODY.replace(" fp=0123456789abcdef", "")},
            ),
            (
                "a body a person last edited",
                {"edited": ("2026-11-17T00:00:00Z", OUTSIDER)},
            ),
        ]:
            with self.subTest(why):
                self.assertIs(judge(**kwargs)[0], False)

    def test_the_same_title_from_another_author_refuses_without_reading_it(
        self,
    ) -> None:
        for why, author in [("the lanes App", LANES), ("an outsider", OUTSIDER)]:
            with self.subTest(why):
                trusted, fake = judge(author=author)
                self.assertIs(trusted, False)
                self.assertEqual(fake.issue_reads, 0)


class TheCopiesMatchTheFiler(unittest.TestCase):
    def test_the_title_and_marker_are_what_issues_mjs_files(self) -> None:
        filer = (
            pathlib.Path(__file__).resolve().parents[6]
            / ".github/scripts/maintenance-monitor-signals/issues.mjs"
        ).read_text(encoding="utf-8")
        self.assertIn(f'"1 main red": {{ title: "{ve.MAIN_RED_TITLE}"', filer)
        self.assertIn(
            "<!-- factory-monitor key=${incidentKey(signal)} fp=${stateFingerprint(findings)} -->",
            filer,
        )
        self.assertIn('const INCIDENT = "incident:";', filer)


if __name__ == "__main__":
    unittest.main()

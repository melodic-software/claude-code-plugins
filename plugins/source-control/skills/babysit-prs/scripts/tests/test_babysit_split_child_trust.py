# test-scope: .github/scripts/intake-triage/split-child.vectors.json .github/scripts/intake-triage/admit.mjs .github/actions/resolve-config/admission-rules.json
"""The gate's split-child trust rule (`babysit_verify_evidence._trusted_spec`)
agrees with Issue Triage's (admit.mjs splitChildBody, its one home).

Expected values come from `.github/scripts/intake-triage/split-child.vectors.json`,
the cases admit.test.mjs and resolve-pr.test.mjs also read: each case's
`expect.trusted`. The vectors' actors, parents and comments are renamed into
the GraphQL shape `SPLIT_CHILD_QUERY` reads, field for field. Network is
stubbed at the `gh_capture` seam.
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import unittest
from datetime import timedelta
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_postmerge as postmerge
import babysit_verify_evidence as ve

VECTORS = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/intake-triage/split-child.vectors.json"
)
REPO = "example-org/example-repo"
LANES_LOGIN = "agent-lanes[bot]"
CHILD = 9
# The `task-list` of `.github/actions/resolve-config/admission-rules.json`,
# which the fake serves as the branch's rules.
TASK_LIST = json.loads(
    (VECTORS.parents[2] / "actions/resolve-config/admission-rules.json").read_text(
        encoding="utf-8"
    )
)["task-list"]


def actor(value: Any) -> Any:
    if value is None:
        return None
    return {"__typename": value["type"], "login": "x", "databaseId": value["id"]}


def graphql_issue(case: dict[str, Any], parents: dict[str, Any]) -> dict[str, Any]:
    """The case's child, its parent and the parent's comments, renamed into
    `SPLIT_CHILD_QUERY`'s answer."""
    child = case["child"]
    link = child["parent"]
    parent = None
    if link is not None:
        text = parents[case["parent"]]
        comments = [
            {
                "databaseId": c["id"],
                "createdAt": c["created_at"],
                "updatedAt": c["updated_at"],
                "body": c["body"],
                "lastEditedAt": c["last_edited_at"],
                "author": actor(c["author"]),
                "editor": actor(c["editor"]),
            }
            for c in text["comments"]
        ]
        parent = {
            "number": link["number"],
            "repository": {"nameWithOwner": link.get("repo", REPO)},
            "body": text["body"],
            "lastEditedAt": text.get("last_edited_at"),
            "author": actor(text["author"]),
            "editor": actor(text.get("editor")),
            "comments": {"totalCount": len(comments), "nodes": comments},
        }
    return {
        "body": child["body"],
        "lastEditedAt": child["last_edited_at"],
        "author": actor(child["author"]),
        "editor": actor(child["editor"]),
        "parent": parent,
    }


def linked(child: dict[str, Any]) -> dict[str, Any]:
    """The child as a verdict's `linked_issues` records it."""
    editor = child["editor"] or {}
    return {
        "number": CHILD,
        "author_login": "x",
        "author_id": child["author"]["id"],
        "author_type": child["author"]["type"],
        "last_edited_at": child["last_edited_at"],
        "editor_login": None,
        "editor_id": editor.get("id"),
        "editor_type": editor.get("type"),
        "spec_comments": [],
    }


class FakeGitHub:
    """Answers the trusted-actor list, admission's rules and
    `SPLIT_CHILD_QUERY`."""

    def __init__(
        self,
        humans: list[int],
        app_id: int | None,
        issue: Any,
        task_list: Any = TASK_LIST,
    ):
        actors = [{"id": h, "login": f"human-{h}", "kind": "human"} for h in humans]
        if app_id is not None:
            actors.append({"id": app_id, "login": LANES_LOGIN, "kind": "bot"})
        self.actors = {"version": 1, "actors": actors}
        self.rules = {} if task_list is None else {"task-list": task_list}
        self.issue = issue
        self.fail = False
        self.rules_fail = False
        self.calls: list[tuple[list[str], Any]] = []

    def graphql_calls(self) -> int:
        return sum(1 for args, _ in self.calls if args[:2] == ["api", "graphql"])

    def rules_calls(self) -> int:
        return sum(
            1
            for args, _ in self.calls
            if any(ve.ADMISSION_RULES_PATH in a for a in args)
        )

    def __call__(
        self, args: list[str], **kwargs: Any
    ) -> subprocess.CompletedProcess[str]:
        self.calls.append((args, kwargs.get("env_overrides")))
        if args[:2] == ["api", "graphql"]:
            assert any(a == f"query={ve.SPLIT_CHILD_QUERY}" for a in args), args
            if self.fail:
                return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
            payload = {"data": {"repository": {"issue": self.issue}}}
            return subprocess.CompletedProcess(args, 0, json.dumps(payload), "")
        if any(
            a.startswith(f"repos/{REPO}/contents/{ve.ADMISSION_RULES_PATH}?")
            for a in args
        ):
            if self.rules_fail:
                return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
            return subprocess.CompletedProcess(args, 0, json.dumps(self.rules), "")
        if any(
            a.startswith(f"repos/{REPO}/contents/{ve.TRUSTED_ACTORS_PATH}?")
            for a in args
        ):
            return subprocess.CompletedProcess(args, 0, json.dumps(self.actors), "")
        raise AssertionError(f"unexpected gh call: {args}")


def judge(
    fake: FakeGitHub, issue: dict[str, Any], identity: str | None, **reader: Any
) -> bool:
    with (
        mock.patch.dict("os.environ", {}, clear=False) as env,
        mock.patch.object(postmerge, "gh_capture", side_effect=fake),
    ):
        env.pop("BABYSIT_RUN_CACHE", None)
        found = ve.Reader(REPO, "main", agent_identity=identity, **reader)
        return found._trusted_spec({"linked_issues": [issue]})


class TheSharedVectorsHold(unittest.TestCase):
    def test_every_vector(self) -> None:
        data = json.loads(VECTORS.read_text(encoding="utf-8"))
        cases = data["cases"]
        self.assertGreaterEqual(len(cases), 43)
        for case in cases:
            with self.subTest(case["name"]):
                app_id = case["app_id"] if "app_id" in case else data["app_id"]
                fake = FakeGitHub(
                    data["humans"], app_id, graphql_issue(case, data["parents"])
                )
                identity = LANES_LOGIN if app_id is not None else None
                trusted = judge(fake, linked(case["child"]), identity)
                self.assertIs(
                    trusted, case["expect"]["trusted"], case["expect"]["reason"]
                )


class AnEditTicksOnly(unittest.TestCase):
    """On the edited path a line may also be a trusted line with its one box
    ticked; a `task-list` without exactly one `[ ]` takes exact lines only."""

    def test_a_marker_without_a_box_takes_exact_lines_only(self) -> None:
        data = json.loads(VECTORS.read_text(encoding="utf-8"))
        case = next(c for c in data["cases"] if c["name"] == "edited by a listed human")
        issue = graphql_issue(case, data["parents"])
        header = issue["body"][: issue["body"].index("- [x]")]
        issue["parent"]["body"] = "## Done when\n\n* Line 3.\n  * Line 4."

        def counts(lines: list[str]) -> bool:
            child = issue | {"body": header + "\n".join(lines)}
            found = ve.split_child_body(
                child, REPO, frozenset(data["humans"]), data["app_id"], "* "
            )
            return found is not None

        self.assertTrue(counts(["* Line 3.", "  * Line 4."]))
        self.assertFalse(counts(["* Line 3.", "* Line 4."]), "the indent counts")
        self.assertFalse(counts(["* [x] Line 3."]), "no ticked form to derive")


class ASourceIdRoundTrips(unittest.TestCase):
    """admit.mjs reads the source line's id as a Number and writes it back
    into the header it compares, so an id a double cannot hold exactly never
    matches, even when the refinement carries it."""

    def test_an_id_past_double_precision_counts_nothing(self) -> None:
        data = json.loads(VECTORS.read_text(encoding="utf-8"))
        case = next(c for c in data["cases"] if c["name"] == "a refinement-only child")
        issue = graphql_issue(case, data["parents"])

        def counts(comment_id: int) -> bool:
            child = issue | {
                "body": issue["body"].replace(
                    "refinement=901", f"refinement={comment_id}"
                ),
                "parent": issue["parent"]
                | {
                    "comments": {
                        "totalCount": 1,
                        "nodes": [
                            issue["parent"]["comments"]["nodes"][0]
                            | {"databaseId": comment_id}
                        ],
                    }
                },
            }
            found = ve.split_child_body(
                child, REPO, frozenset(data["humans"]), data["app_id"], TASK_LIST
            )
            return found is not None

        self.assertTrue(counts(2**53))
        self.assertFalse(counts(2**53 + 1))


class AFailedReadRefuses(unittest.TestCase):
    """The trusted child, with a read failing (`verify:unreadable`, as
    resolve-pr.mjs fails), its parent's comments cut, or no `task-list` in
    the rules (nothing counts); the same reads whole trust it."""

    def setUp(self) -> None:
        self.data = json.loads(VECTORS.read_text(encoding="utf-8"))
        self.case = next(
            c for c in self.data["cases"] if c["name"] == "the trusted child"
        )

    def fake(self, **kwargs: Any) -> FakeGitHub:
        issue = graphql_issue(self.case, self.data["parents"])
        return FakeGitHub(self.data["humans"], self.data["app_id"], issue, **kwargs)

    def test_read_whole_it_counts(self) -> None:
        self.assertTrue(judge(self.fake(), linked(self.case["child"]), LANES_LOGIN))

    def test_an_unreadable_parent_is_unreadable(self) -> None:
        fake = self.fake()
        fake.fail = True
        with self.assertRaises(ve._Unreadable):
            judge(fake, linked(self.case["child"]), LANES_LOGIN)

    def test_unreadable_rules_are_unreadable(self) -> None:
        fake = self.fake()
        fake.rules_fail = True
        with self.assertRaises(ve._Unreadable):
            judge(fake, linked(self.case["child"]), LANES_LOGIN)

    def test_unreadable_comments(self) -> None:
        # More comments than the first 100 the query reads.
        fake = self.fake()
        fake.issue["parent"]["comments"]["totalCount"] = 101
        self.assertFalse(judge(fake, linked(self.case["child"]), LANES_LOGIN))

    def test_a_missing_or_empty_task_list_counts_nothing(self) -> None:
        for task_list in (None, "", 7):
            with self.subTest(task_list=task_list):
                fake = self.fake(task_list=task_list)
                self.assertFalse(judge(fake, linked(self.case["child"]), LANES_LOGIN))


class OneReadPerChild(unittest.TestCase):
    def setUp(self) -> None:
        self.data = json.loads(VECTORS.read_text(encoding="utf-8"))
        case = self.data["cases"][0]
        self.child = linked(case["child"])
        self.fake = FakeGitHub(
            self.data["humans"],
            self.data["app_id"],
            graphql_issue(case, self.data["parents"]),
        )

    def test_a_child_judged_twice_is_read_once_under_the_actions_token(self) -> None:
        with (
            mock.patch.dict("os.environ", {}, clear=False) as env,
            mock.patch.object(postmerge, "gh_capture", side_effect=self.fake),
        ):
            env.pop("BABYSIT_RUN_CACHE", None)
            reader = ve.Reader(
                REPO, "main", agent_identity=LANES_LOGIN, actions_token="t"
            )
            self.assertTrue(reader._trusted_spec({"linked_issues": [self.child]}))
            self.assertTrue(reader._trusted_spec({"linked_issues": [self.child]}))
        self.assertEqual(self.fake.graphql_calls(), 1)
        self.assertEqual(self.fake.rules_calls(), 1)
        self.assertEqual(
            [env for args, env in self.fake.calls if args[:2] == ["api", "graphql"]],
            [{"GH_TOKEN": "t"}],
        )

    def test_a_reused_answer_notes_when_it_was_read(self) -> None:
        start = ve.run_cache.now()
        ticks = (start + timedelta(seconds=n) for n in range(1000))
        with (
            mock.patch.dict("os.environ", {}, clear=False) as env,
            mock.patch.object(postmerge, "gh_capture", side_effect=self.fake),
            mock.patch.object(ve.run_cache, "now", side_effect=lambda: next(ticks)),
        ):
            env.pop("BABYSIT_RUN_CACHE", None)
            reader = ve.Reader(
                REPO, "main", agent_identity=LANES_LOGIN, actions_token="t"
            )
            with ve.run_cache.track() as first:
                self.assertTrue(reader._trusted_spec({"linked_issues": [self.child]}))
            with ve.run_cache.track() as second:
                self.assertTrue(reader._trusted_spec({"linked_issues": [self.child]}))
        self.assertTrue(first)
        self.assertLessEqual(set(first), set(second))

    def test_no_read_for_an_issue_the_lanes_app_did_not_write(self) -> None:
        human = self.data["humans"][0]
        cases = {
            "a listed human's": {"type": "User", "id": human},
            "another bot's": {"type": "Bot", "id": 999},
        }
        for label, author in cases.items():
            with self.subTest(label):
                fake = FakeGitHub(self.data["humans"], self.data["app_id"], None)
                issue = self.child | {
                    "author_type": author["type"],
                    "author_id": author["id"],
                }
                self.assertEqual(
                    judge(fake, issue, LANES_LOGIN), author["type"] == "User"
                )
                self.assertEqual(fake.graphql_calls(), 0)
                self.assertEqual(fake.rules_calls(), 0)

    def test_the_identity_is_matched_with_or_without_its_bot_suffix(self) -> None:
        for identity in ("agent-lanes", " Agent-Lanes[bot] "):
            with self.subTest(identity):
                self.assertTrue(judge(self.fake, self.child, identity))

    def test_no_identity_reads_nothing_and_counts_nothing(self) -> None:
        self.assertFalse(judge(self.fake, self.child, None))
        self.assertEqual(self.fake.graphql_calls(), 0)
        self.assertEqual(self.fake.rules_calls(), 0)


if __name__ == "__main__":
    unittest.main()

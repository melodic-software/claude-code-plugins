"""The pr-merge lane's reader of verifier verdicts (`babysit_verify_evidence`).

Expected values come from issue #7702 (Scope, Done when) and the verdict rules
in docs/conventions/pr-pipeline/README.md ("Verifier verdict"): an artifact
named `pr-verify-<pr>-<sha>-<verdict>` counts only through a run of
`.github/workflows/pr-verify.yml` on main of this repository; a FAIL counts
whatever the run's conclusion and under any pull request number, a PASS only
from a completed success at this pull request's head; a FAIL at another head
of the pull request goes to a human unless a counted pass at the head clears
every check; an unreadable FAIL blocks; a pull request
older than 80 days goes to a human; a pass needs every linked issue written
and last edited by a trusted human, the pull request's author included,
unchanged since the judgment; the Actions reads use the Actions token; a Dependabot pull request
needs no verdict.

The artifact and run shapes follow responses recorded from
`GET /repos/{owner}/{repo}/actions/artifacts` and `GET .../actions/runs/{id}`
for a `workflow_run` run, with identifying details changed. Network is stubbed
at the `gh_capture` seam the reader shares with the post-merge check.
"""

from __future__ import annotations

import dataclasses
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge as merge
import babysit_merge_policy as policy
import babysit_postmerge as postmerge
import babysit_verify_evidence as ve
import test_babysit_merge_unattended as unattended

REPO = "example-org/example-repo"
PR = 41
HEAD = "a" * 40
EARLIER = "b" * 40  # an earlier head of PR 41, force-pushed away
MAIN_SHA = "c" * 40
OFF_MAIN = "d" * 40
IN_PR = "e" * 40  # a commit still on PR 41
UNRELATED = "f" * 40
WORKFLOW = ".github/workflows/pr-verify.yml"
NOW = datetime(2026, 10, 16, tzinfo=UTC)
MAINTAINER = {"id": 100, "login": "maintainer", "kind": "human"}
LANES = {"id": 200, "login": "agent-lanes[bot]", "kind": "bot"}
TRUSTED_ISSUE = {
    "number": 7,
    "author_login": "maintainer",
    "author_id": 100,
    "author_type": "User",
    "last_edited_at": None,
    "editor_login": None,
    "editor_id": None,
    "editor_type": None,
    "spec_comments": [],
}
HUMAN = {"__typename": "User", "login": "maintainer", "databaseId": 100}
LANES_ACTOR = {"__typename": "Bot", "login": "agent-lanes", "databaseId": 200}


def comment(
    cid: int,
    author: dict[str, Any],
    updated: str = "2026-10-12T00:00:00Z",
    **extra: Any,
) -> dict[str, Any]:
    return {
        "databaseId": cid,
        "updatedAt": updated,
        "lastEditedAt": None,
        "author": author,
        "editor": None,
        **extra,
    }


RUN_STARTED = "2026-10-15T00:00:00Z"
OLDER_START = "2026-10-14T00:00:00Z"


def pull(**overrides: Any) -> dict[str, Any]:
    fields = {
        "number": PR,
        "created_at": "2026-10-10T00:00:00Z",
        "head": {"ref": "feat/x", "sha": HEAD},
        "user": {"login": "agent-lanes[bot]"},
    }
    fields.update(overrides)
    return fields


def artifact(name: str, run_id: int, *, expired: bool = False) -> dict[str, Any]:
    return {
        "id": run_id * 10,
        "name": name,
        "expired": expired,
        "workflow_run": {
            "id": run_id,
            "head_branch": "main",
            "head_sha": MAIN_SHA,
            "repository_id": 1,
            "head_repository_id": 1,
        },
    }


def run(run_id: int, **overrides: Any) -> dict[str, Any]:
    fields = {
        "id": run_id,
        "name": "pr-verify",
        "path": WORKFLOW,
        "event": "workflow_run",
        "status": "completed",
        "conclusion": "success",
        "head_branch": "main",
        "head_sha": MAIN_SHA,
        "run_attempt": 1,
        "created_at": RUN_STARTED,
        "run_started_at": RUN_STARTED,
        "repository": {"full_name": REPO},
        "head_repository": {"full_name": REPO},
    }
    fields.update(overrides)
    return fields


def record(number: int = PR, sha: str = HEAD, **overrides: Any) -> dict[str, Any]:
    fields = {
        "pr": number,
        "head_sha": sha,
        "base_sha": MAIN_SHA,
        "head_ref": "feat/x",
        "verdict": "pass",
        "summary": "s",
        "notes": [],
        "run_id": 1,
        "linked_issues": [TRUSTED_ISSUE],
    }
    fields.update(overrides)
    return fields


def judged(run_id: int, at: Any, **overrides: Any) -> dict[str, Any]:
    """A run created, and its one attempt started, at `at`."""
    return run(run_id, created_at=at, run_started_at=at, **overrides)


def named(sha: str, verdict: str, number: int = PR) -> str:
    return f"pr-verify-{number}-{sha}-{verdict}"


def change(
    added: str, at: int = 1, before: str = "one", path: str = "notes.txt"
) -> str:
    """A unified diff adding line `added` to `path` at line `at` after the
    context line `before`, in the form GitHub's compare diff and `git diff`
    write."""
    return (
        f"diff --git a/{path} b/{path}\n"
        "index 1111111..2222222 100644\n"
        f"--- a/{path}\n"
        f"+++ b/{path}\n"
        f"@@ -{at},2 +{at},3 @@\n"
        f" {before}\n"
        f"+{added}\n"
        " two\n"
    )


class FakeGitHub:
    """Answers the reader's reads: the artifact listing, runs, a compare of a
    run head against main, the pull request's commits, the trusted-actor list,
    and `gh run download` of a verdict.json."""

    def __init__(
        self,
        artifacts: list[dict[str, Any]],
        runs: dict[int, Any],
        records: dict[str, dict[str, Any]] | None = None,
    ):
        self.artifacts = artifacts
        self.runs = runs
        self.records = records or {}
        self.on_main = {MAIN_SHA}
        self.commits = [IN_PR, HEAD]
        # Each commit's git tree, as the commit list and `git/commits` give it.
        # The pull request's own change at each commit: the compare diff from
        # its merge base with main, each unlike the others.
        self.diffs = {s: change(s[:4]) for s in (HEAD, EARLIER, IN_PR, UNRELATED)}
        self.actors: Any = {"version": 1, "actors": [MAINTAINER, LANES]}
        self.calls: list[list[str]] = []
        self.envs: list[tuple[list[str], Any]] = []
        self.fail: set[str] = set()
        self.fail_status = 502
        # The PR's closing issues now: (number, repository).
        self.closing: list[tuple[int, str]] = [(7, REPO)]
        self.closing_total: int | None = None
        # Each closing issue's body lastEditedAt now, by number.
        self.closing_edited: dict[int, str | None] = {}
        # Each closing issue's comments now, and a totalCount that cuts them.
        self.closing_comments: dict[int, list[dict[str, Any]]] = {}
        self.comments_total: dict[int, int] = {}
        # The pull requests, open or closed, that close each issue:
        # (number, repository), and a totalCount that cuts them.
        self.closers: dict[int, list[tuple[int, str]]] = {}
        self.closers_total: dict[int, int] = {}

    def __call__(
        self, args: list[str], **kwargs: Any
    ) -> subprocess.CompletedProcess[str]:
        self.calls.append(args)
        self.envs.append((args, kwargs.get("env_overrides")))

        def ok(payload: Any) -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(args, 0, json.dumps(payload), "")

        def missing() -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(args, 1, "", "gh: Not Found (HTTP 404)")

        if args[:2] == ["api", "graphql"]:
            if "graphql" in self.fail:
                return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
            nodes = [
                {
                    "number": n,
                    "lastEditedAt": self.closing_edited.get(n),
                    "repository": {"nameWithOwner": repo},
                    "comments": {
                        "totalCount": self.comments_total.get(
                            n, len(self.closing_comments.get(n, []))
                        ),
                        "nodes": self.closing_comments.get(n, []),
                    },
                    "closedByPullRequestsReferences": {
                        "totalCount": self.closers_total.get(
                            n, len(self.closers.get(n, [(PR, REPO)]))
                        ),
                        "nodes": [
                            {"number": pr, "repository": {"nameWithOwner": repo}}
                            for pr, repo in self.closers.get(n, [(PR, REPO)])
                        ],
                    },
                }
                for n, repo in self.closing
            ]
            refs = {"totalCount": self.closing_total or len(nodes), "nodes": nodes}
            return ok(
                {
                    "data": {
                        "repository": {"pullRequest": {"closingIssuesReferences": refs}}
                    }
                }
            )
        if args[:2] == ["run", "download"]:
            name, target = args[args.index("-n") + 1], args[args.index("-D") + 1]
            if name not in self.records:
                return missing()
            pathlib.Path(target, "verdict.json").write_text(
                json.dumps(self.records[name])
            )
            return ok("")
        path = next(a for a in args if a.startswith("repos/"))
        kind = next((k for k in self.fail if k in path), None)
        if kind:
            return subprocess.CompletedProcess(
                args, 1, "", f"gh: boom (HTTP {self.fail_status})"
            )
        if path == f"repos/{REPO}/actions/artifacts?per_page=100":
            pages = [
                self.artifacts[i : i + 2] for i in range(0, len(self.artifacts), 2)
            ]
            return ok(
                [{"total_count": len(self.artifacts), "artifacts": p} for p in pages]
                or [{"total_count": 0, "artifacts": []}]
            )
        if path == f"repos/{REPO}/pulls/{PR}/commits?per_page=100":
            return ok([[{"sha": sha} for sha in self.commits]])
        if "Accept: application/vnd.github.diff" in args:
            sha = path.removeprefix(f"repos/{REPO}/compare/main...")
            if sha not in self.diffs:
                return missing()
            return subprocess.CompletedProcess(args, 0, self.diffs[sha], "")
        if path.startswith(f"repos/{REPO}/contents/"):
            return ok(self.actors)
        prefix = f"repos/{REPO}/actions/runs/"
        if path.startswith(prefix):
            run_id = int(path[len(prefix) :])
            return ok(self.runs[run_id]) if run_id in self.runs else missing()
        compare = f"repos/{REPO}/compare/"
        if path.startswith(compare):
            sha = path[len(compare) :].split("...")[0]
            return ok({"status": "ahead" if sha in self.on_main else "diverged"})
        raise AssertionError(f"unexpected gh call: {args}")


class OrderedSet(set[str]):
    """A set that iterates in the order given, standing in for whatever order
    another process's string hashing gives."""

    def __init__(self, items: list[str]):
        super().__init__(items)
        self.order = items

    def __iter__(self) -> Iterator[str]:
        return iter(self.order)


def passing(*extra: dict[str, Any], runs: dict[int, Any] | None = None) -> FakeGitHub:
    """A counted pass at the head (run 1) beside `extra` artifacts."""
    return FakeGitHub(
        [artifact(named(HEAD, "pass"), 1), *extra],
        {1: run(1), **(runs or {})},
        {named(HEAD, "pass"): record()},
    )


def read(fake: FakeGitHub, pr: dict[str, Any] | None = None) -> ve.Evidence:
    with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
        return ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, pr or pull())


class VerdictAtTheCurrentHead(unittest.TestCase):
    def test_a_pass_allows(self) -> None:
        evidence = read(passing())
        self.assertIsNone(evidence.refusal)
        self.assertFalse(evidence.needs_human)

    def test_a_pass_with_notes_allows(self) -> None:
        fake = FakeGitHub(
            [artifact(named(HEAD, "pass-notes"), 1)],
            {1: run(1)},
            {named(HEAD, "pass-notes"): record()},
        )
        self.assertIsNone(read(fake).refusal)

    def test_a_fail_waits_for_a_fix_round_not_a_human(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 1)], {1: run(1)})
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertFalse(evidence.needs_human)
        self.assertEqual(
            evidence.report()["headFail"], {"run": 1, "artifact": named(HEAD, "fail")}
        )

    def summary(self, fake: FakeGitHub, run_id: int, name: str) -> str | None:
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            return ve.Reader(REPO, "main", now=NOW).fail_summary(run_id, name, PR, HEAD)

    def test_the_newest_head_fail_names_the_summary_to_quote(self) -> None:
        older, newer = named(HEAD, "fail", 7), named(HEAD, "fail")
        fake = FakeGitHub(
            [artifact(newer, 5), artifact(older, 2)],
            {2: run(2), 5: run(5)},
            {
                older: record(7, verdict="fail", summary="old"),
                newer: record(verdict="fail", summary="Spec item 2 is unmet."),
            },
        )
        evidence = read(fake)
        self.assertEqual(evidence.head_fail, (5, newer))
        self.assertEqual(self.summary(fake, 5, newer), "Spec item 2 is unmet.")

    def test_another_pull_requests_fail_counts_but_is_not_quoted(self) -> None:
        other = named(HEAD, "fail", 99)
        fake = FakeGitHub(
            [artifact(other, 5)],
            {5: run(5)},
            {other: record(99, verdict="fail", summary="PR 99's reason.")},
        )
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(evidence.head_fail, (5, other))
        self.assertIsNone(self.summary(fake, 5, other))

    def test_a_newer_head_pass_is_never_the_fail_to_quote(self) -> None:
        fail, passed = named(HEAD, "fail"), named(HEAD, "pass", 99)
        fake = FakeGitHub(
            [artifact(passed, 5), artifact(fail, 2)],
            {2: run(2), 5: run(5)},
            {passed: record(99)},
        )
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(evidence.head_fail, (2, fail))

    def test_a_newer_fail_at_an_earlier_head_is_never_the_fail_to_quote(
        self,
    ) -> None:
        fail, earlier = named(HEAD, "fail"), named(EARLIER, "fail")
        fake = FakeGitHub(
            [artifact(earlier, 5), artifact(fail, 2)],
            {2: run(2), 5: run(5)},
        )
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(evidence.head_fail, (2, fail))

    def test_an_unreadable_record_is_not_a_record_with_nothing_to_quote(
        self,
    ) -> None:
        name = named(HEAD, "fail")
        fake = FakeGitHub([artifact(name, 1)], {1: run(1)})
        with self.assertRaises(ve.SummaryUnreadable):
            self.summary(fake, 1, name)

    def test_a_foreign_record_quotes_no_summary(self) -> None:
        name = named(HEAD, "fail")
        fake = FakeGitHub([artifact(name, 1)], {1: run(1)})
        for other in (
            record(99, verdict="fail"),
            record(sha=EARLIER, verdict="fail"),
            record(verdict="pass"),
            record(verdict="fail", summary=7),
        ):
            with self.subTest(other):
                fake.records[name] = other
                self.assertIsNone(self.summary(fake, 1, name))

    def test_a_fail_beside_a_pass_at_the_same_head_blocks(self) -> None:
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_no_verdict_is_missing(self) -> None:
        self.assertEqual(read(FakeGitHub([], {})).refusal, "verify:missing")


class EveryPassAtTheHeadIsChecked(unittest.TestCase):
    """Several passes at one head are equivalent: each must allow, whatever
    order the listing returns them in, and a FAIL there still blocks."""

    def judge(self, second: dict[str, Any], *, reverse: bool) -> ve.Evidence:
        """A pass (run 1) and a pass-notes (run 2) whose record or run start
        is `second`'s, listed in that order or reversed."""
        items = [
            artifact(named(HEAD, "pass"), 1),
            artifact(named(HEAD, "pass-notes"), 2),
        ]
        fake = FakeGitHub(
            items[::-1] if reverse else items,
            {1: run(1), 2: run(2, **second.get("run", {}))},
            {
                named(HEAD, "pass"): record(),
                named(HEAD, "pass-notes"): record(**second.get("record", {})),
            },
        )
        fake.closing_edited = second.get("edited", {})
        return read(fake)

    def each_order(self, second: dict[str, Any]) -> set[str | None]:
        return {self.judge(second, reverse=r).refusal for r in (False, True)}

    def test_two_allowing_passes_allow(self) -> None:
        self.assertEqual(self.each_order({}), {None})

    def test_one_judged_before_a_spec_edit_refuses_either_way(self) -> None:
        # Run 2 started before the issue's edit; run 1 after it.
        second = {
            "run": {"run_started_at": "2026-10-13T00:00:00Z"},
            "edited": {7: "2026-10-14T00:00:00Z"},
        }
        self.assertEqual(self.each_order(second), {"verify:spec-changed"})

    def test_one_recording_an_untrusted_spec_refuses_either_way(self) -> None:
        bot = {**TRUSTED_ISSUE, "author_type": "Bot", "author_id": 200}
        second = {"record": {"linked_issues": [bot]}}
        self.assertEqual(self.each_order(second), {"verify:untrusted-spec"})

    def test_a_changed_spec_is_reported_before_an_untrusted_one(self) -> None:
        # The README's order: the spec must be the judged one before its
        # authors are weighed. Run 2 records an untrusted spec and run 1
        # (started first) predates the issue's edit.
        bot = {**TRUSTED_ISSUE, "author_type": "Bot", "author_id": 200}
        second = {
            "record": {"linked_issues": [bot]},
            "run": {"run_started_at": "2026-10-15T12:00:00Z"},
            "edited": {7: "2026-10-15T06:00:00Z"},
        }
        self.assertEqual(self.each_order(second), {"verify:spec-changed"})

    def test_a_fail_beside_two_passes_blocks(self) -> None:
        for reverse in (False, True):
            with self.subTest(reverse=reverse):
                items = [
                    artifact(named(HEAD, "pass"), 1),
                    artifact(named(HEAD, "fail"), 3),
                    artifact(named(HEAD, "pass-notes"), 2),
                ]
                fake = FakeGitHub(
                    items[::-1] if reverse else items,
                    {1: run(1), 2: run(2), 3: run(3)},
                    {
                        named(HEAD, "pass"): record(),
                        named(HEAD, "pass-notes"): record(),
                    },
                )
                self.assertEqual(read(fake).refusal, "verify:fail")


class AVerdictForAnotherShaDoesNotCount(unittest.TestCase):
    def test_a_pass_at_an_earlier_head_is_missing_at_the_current_one(self) -> None:
        fake = FakeGitHub([artifact(named(EARLIER, "pass"), 1)], {1: run(1)})
        self.assertEqual(read(fake).refusal, "verify:missing")

    def test_another_prs_pass_at_this_head_does_not_count(self) -> None:
        # PR 4 and PR 411 share a prefix with 41; the name is parsed.
        names = (named(HEAD, "pass", 4), named(HEAD, "pass", 411))
        fake = FakeGitHub(
            [artifact(names[0], 1), artifact(names[1], 2)],
            {1: run(1), 2: run(2)},
            {name: record(number=int(name.split("-")[2])) for name in names},
        )
        self.assertEqual(read(fake).refusal, "verify:missing")


class AFailCountsUnderAnyNumber(unittest.TestCase):
    """Closing #41 and reopening the branch as another pull request must not
    re-roll a FAIL."""

    def test_a_fail_at_this_head_under_another_number_blocks(self) -> None:
        fake = passing(artifact(named(HEAD, "fail", 99), 2), runs={2: run(2)})
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_fail_at_one_of_this_prs_commits_under_another_number(self) -> None:
        fake = FakeGitHub([artifact(named(IN_PR, "fail", 99), 2)], {2: run(2)})
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertFalse(evidence.needs_human)

    def test_a_fail_recording_this_head_branch_under_another_number(self) -> None:
        name = named(UNRELATED, "fail", 99)
        fake = FakeGitHub([artifact(name, 2)], {2: run(2)})
        fake.records[name] = record(99, UNRELATED, verdict="fail")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_fail_on_another_branch_and_number_does_not_count(self) -> None:
        name = named(UNRELATED, "fail", 99)
        fake = passing(artifact(name, 2), runs={2: run(2)})
        fake.records[name] = record(99, UNRELATED, verdict="fail", head_ref="feat/y")
        self.assertIsNone(read(fake).refusal)

    def test_an_unrelated_fail_whose_record_cannot_be_read_blocks(self) -> None:
        fake = passing(artifact(named(UNRELATED, "fail", 99), 2), runs={2: run(2)})
        self.assertEqual(read(fake).refusal, "verify:unreadable")


class AnEarlierFailGoesToAHuman(unittest.TestCase):
    def test_a_fail_at_the_current_head_wins_over_an_earlier_fail(self) -> None:
        fake = FakeGitHub(
            [artifact(named(EARLIER, "fail"), 1), artifact(named(HEAD, "fail"), 2)],
            {1: run(1), 2: run(2)},
        )
        self.assertEqual(read(fake).refusal, "verify:fail")


class ACountedPassAtTheHeadClearsAnEarlierFail(unittest.TestCase):
    """An earlier head's FAIL stops holding once the current head has a
    counted pass that clears every spec check and whose run started after
    every earlier FAIL's run; without one it still holds."""

    @staticmethod
    def earlier_fail(started: Any = OLDER_START, *extra: dict[str, Any]) -> FakeGitHub:
        """A pass at the head (run 1, started `RUN_STARTED`) and a FAIL at an
        earlier head (run 2, started `started`)."""
        return passing(
            artifact(named(EARLIER, "fail"), 2),
            *extra,
            runs={2: judged(2, started)},
        )

    def test_an_earlier_fail_and_an_allowing_pass_at_the_head_allow(self) -> None:
        evidence = read(self.earlier_fail())
        self.assertIsNone(evidence.refusal)
        self.assertEqual(evidence.report()["earlierFails"], [EARLIER])

    def test_a_fail_started_after_the_pass_refuses(self) -> None:
        # Head B passed, A was pushed and failed, the branch went back to B.
        fake = self.earlier_fail("2026-10-15T00:00:01Z")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_re_attempted_earlier_pass_does_not_clear_a_later_fail(self) -> None:
        # Run 39652492098's record: attempt 2 keeps the run's created_at and
        # moves run_started_at later. The pass run was created before the
        # FAIL's and re-attempted after it.
        fake = self.earlier_fail("2026-10-15T00:00:01Z")
        fake.runs[1] = run(
            1,
            created_at=RUN_STARTED,
            run_started_at="2026-10-15T00:00:02Z",
            run_attempt=2,
        )
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_re_attempt_created_after_the_fail_clears_it(self) -> None:
        fake = self.earlier_fail()
        fake.runs[1] = run(1, run_started_at="2026-10-15T00:05:00Z", run_attempt=2)
        self.assertIsNone(read(fake).refusal)

    def test_a_run_record_whose_id_is_true_counts_nothing(self) -> None:
        # True == 1 in Python, so the id must be an int, not equal to one.
        fake = self.earlier_fail()
        fake.runs[1] = {**run(1), "id": True}
        self.assertNotEqual(read(fake).refusal, None)
        fake = FakeGitHub(
            [artifact(named(HEAD, "fail"), 1)], {1: {**run(1), "id": True}}
        )
        self.assertEqual(read(fake).refusal, "verify:missing")

    def test_a_fail_started_with_the_pass_refuses(self) -> None:
        fake = self.earlier_fail(RUN_STARTED)
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_fail_with_no_start_time_refuses(self) -> None:
        for started in (None, "yesterday"):
            with self.subTest(started=started):
                fake = self.earlier_fail(started)
                self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_an_earlier_fail_with_no_verdict_at_the_head_waits(self) -> None:
        # The head a fix round pushed, before the verifier judges it.
        fake = FakeGitHub([artifact(named(EARLIER, "fail"), 2)], {2: run(2)})
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertFalse(evidence.needs_human)

    def test_a_pass_from_an_unfinished_run_does_not_clear_it(self) -> None:
        fake = self.earlier_fail()
        fake.runs[1] = run(1, status="in_progress", conclusion=None)
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_fail_at_the_head_still_refuses_beside_the_pass(self) -> None:
        fake = self.earlier_fail(OLDER_START, artifact(named(HEAD, "fail"), 3))
        fake.runs[3] = run(3)
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_pass_on_a_changed_spec_still_refuses(self) -> None:
        fake = self.earlier_fail()
        fake.closing = [(8, REPO)]
        self.assertEqual(read(fake).refusal, "verify:spec-changed")

    def test_a_pass_on_an_untrusted_spec_still_refuses(self) -> None:
        fake = self.earlier_fail()
        fake.records[named(HEAD, "pass")] = record(
            linked_issues=[{**TRUSTED_ISSUE, "author_type": "Bot", "author_id": 200}]
        )
        self.assertEqual(read(fake).refusal, "verify:untrusted-spec")

    def test_an_unreadable_tied_fail_refuses_without_a_human(self) -> None:
        # Run 7 is not in the fake, so the tied FAIL at the head is unread.
        fake = self.earlier_fail(OLDER_START, artifact(named(HEAD, "fail"), 7))
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertFalse(evidence.needs_human)


class AFailCarriesToAHeadOfTheSameChange(unittest.TestCase):
    """A pass clears an earlier head's FAIL only when the pull request's own
    change at the head (the stable patch id of its diff from the merge base
    with main) differs from its change at every FAILed head: a head that only
    merges main, or adds an empty commit, keeps the FAIL (owner decision
    2026-10-21), and a diff that holds no change keeps it too; one that
    cannot be read refuses `verify:unreadable`."""

    earlier_fail = staticmethod(ACountedPassAtTheHeadClearsAnEarlierFail.earlier_fail)

    def diff_reads(self, fake: FakeGitHub) -> list[str]:
        return [c[-1] for c in fake.calls if "Accept: application/vnd.github.diff" in c]

    def test_a_head_that_only_merges_main_still_refuses(self) -> None:
        fake = self.earlier_fail()
        # Main's merge moved the hunk down; the change itself is the same.
        fake.diffs[EARLIER] = change("fix", at=1)
        fake.diffs[HEAD] = change("fix", at=40)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertFalse(evidence.needs_human)

    def test_a_base_merge_that_edits_a_line_beside_the_fix_still_refuses(
        self,
    ) -> None:
        # Main changed the context line next to the fix; the fix is the same.
        fake = self.earlier_fail()
        fake.diffs[EARLIER] = change("fix", before="one")
        fake.diffs[HEAD] = change("fix", at=40, before="one, edited on main")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_whitespace_only_difference_still_refuses(self) -> None:
        fake = self.earlier_fail()
        fake.diffs[EARLIER] = change("x = f(a, b)")
        fake.diffs[HEAD] = change("x  =  f(a,b) ")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_the_same_lines_in_another_file_allow(self) -> None:
        fake = self.earlier_fail()
        fake.diffs[EARLIER] = change("fix")
        fake.diffs[HEAD] = change("fix", path="other.txt")
        self.assertIsNone(read(fake).refusal)

    def test_a_binary_change_allows(self) -> None:
        fake = self.earlier_fail()
        fake.diffs[EARLIER] = change("fix")
        fake.diffs[HEAD] = change("fix") + (
            "diff --git a/logo.png b/logo.png\n"
            "index 3333333..4444444 100644\n"
            "Binary files a/logo.png and b/logo.png differ\n"
        )
        self.assertIsNone(read(fake).refusal)

    def test_a_head_with_a_real_change_allows(self) -> None:
        fake = self.earlier_fail()
        fake.diffs[EARLIER] = change("fix", at=1)
        fake.diffs[HEAD] = change("better fix", at=40)
        self.assertIsNone(read(fake).refusal)
        self.assertEqual(
            sorted(self.diff_reads(fake)),
            sorted(f"repos/{REPO}/compare/main...{s}" for s in (HEAD, EARLIER)),
        )

    def test_one_failed_head_of_the_same_change_among_others_refuses(self) -> None:
        fake = self.earlier_fail(OLDER_START, artifact(named(IN_PR, "fail"), 3))
        fake.runs[3] = judged(3, OLDER_START)
        self.assertIsNone(read(fake).refusal)
        fake.diffs[IN_PR] = fake.diffs[HEAD]
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_change_with_no_lines_keeps_the_fail(self) -> None:
        for sha in (EARLIER, HEAD):
            with self.subTest(sha=sha):
                fake = self.earlier_fail()
                fake.diffs[sha] = ""
                self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_head_github_no_longer_has_keeps_the_fail(self) -> None:
        # A compare that answers 404 (a garbage-collected or force-pushed-away
        # head) holds no readable change, which no later read will find.
        for sha in (EARLIER, HEAD):
            with self.subTest(sha=sha):
                fake = self.earlier_fail()
                del fake.diffs[sha]
                evidence = read(fake)
                self.assertEqual(evidence.refusal, "verify:earlier-fail")
                self.assertFalse(evidence.needs_human)

    def test_the_verdict_does_not_depend_on_the_order_of_failed_heads(self) -> None:
        # EARLIER holds the head's own change; UNRELATED's read fails.
        fake = self.earlier_fail()
        fake.diffs[EARLIER] = fake.diffs[HEAD]
        fake.fail = {f"compare/main...{UNRELATED}"}
        outcomes = set()
        for order in ([EARLIER, UNRELATED], [UNRELATED, EARLIER]):
            with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
                reader = ve.Reader(REPO, "main", now=NOW)
                try:
                    outcomes.add(reader._change_differs(HEAD, OrderedSet(order)))
                except ve._Unreadable:
                    outcomes.add("unreadable")
        self.assertEqual(len(outcomes), 1, outcomes)

    def test_a_head_that_only_adds_blank_lines_refuses(self) -> None:
        fake = self.earlier_fail()
        fake.diffs[HEAD] = change("")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_response_that_is_not_a_diff_refuses(self) -> None:
        fake = self.earlier_fail()
        fake.diffs[HEAD] = "<html>rate limited</html>\n"
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")


def rename(old: str, new: str) -> str:
    """A pure rename as GitHub's compare diff shows it: no hunk."""
    return (
        f"diff --git a/{old} b/{new}\n"
        "similarity index 100%\n"
        f"rename from {old}\n"
        f"rename to {new}\n"
    )


class TheChangeDigestKeysOnChangedLines(unittest.TestCase):
    """`change_digest` hashes what the pull request changed, not where: the
    expected equalities come from the review's rules (owner decision
    2026-10-21): context, line numbers, hunk and file order and whitespace
    leave it alone; a marker, a line, a path, a rename, a mode or a binary
    change moves it."""

    def digest(self, diff: str) -> str | None:
        return ve.change_digest(diff)

    def test_context_lines_and_line_numbers_do_not_count(self) -> None:
        self.assertEqual(
            self.digest(change("fix", at=1, before="one")),
            self.digest(change("fix", at=90, before="edited on main")),
        )

    def test_hunk_and_file_order_do_not_count(self) -> None:
        a, b = change("fix", path="a.txt"), change("other", path="b.txt")
        self.assertEqual(self.digest(a + b), self.digest(b + a))
        hunks = (
            "diff --git a/n.txt b/n.txt\n--- a/n.txt\n+++ b/n.txt\n"
            "@@ -1,1 +1,2 @@\n one\n+first\n"
            "@@ -9,1 +10,2 @@\n nine\n+second\n"
        )
        swapped = (
            "diff --git a/n.txt b/n.txt\n--- a/n.txt\n+++ b/n.txt\n"
            "@@ -1,1 +1,2 @@\n one\n+second\n"
            "@@ -9,1 +10,2 @@\n nine\n+first\n"
        )
        self.assertEqual(self.digest(hunks), self.digest(swapped))

    def test_a_removal_swapped_for_an_addition_counts(self) -> None:
        added = change("line")
        removed = added.replace("+line", "-line")
        self.assertNotEqual(self.digest(added), self.digest(removed))

    def test_a_pure_rename_counts_and_names_its_paths(self) -> None:
        first = self.digest(rename("old.txt", "new.txt"))
        self.assertIsNotNone(first)
        self.assertNotEqual(first, self.digest(rename("old.txt", "other.txt")))
        self.assertNotEqual(first, self.digest(rename("was.txt", "new.txt")))

    def test_a_binary_change_carries_its_path(self) -> None:
        def binary(path: str) -> str:
            return (
                f"diff --git a/{path} b/{path}\n"
                f"Binary files a/{path} and b/{path} differ\n"
            )

        self.assertIsNotNone(self.digest(binary("a.png")))
        self.assertNotEqual(self.digest(binary("a.png")), self.digest(binary("b.png")))

    def test_a_mode_change_counts(self) -> None:
        def mode(old: str, new: str) -> str:
            return f"diff --git a/run.sh b/run.sh\nold mode {old}\nnew mode {new}\n"

        self.assertIsNotNone(self.digest(mode("100644", "100755")))
        self.assertNotEqual(
            self.digest(mode("100644", "100755")), self.digest(mode("100755", "100644"))
        )
        content = change("x", path="run.sh")
        self.assertNotEqual(
            self.digest(content),
            self.digest(
                content.replace("index", "old mode 100644\nnew mode 100755\nindex")
            ),
        )

    def test_added_blank_lines_do_not_count(self) -> None:
        # A re-roll must not cost one empty line.
        base = change("x = 2")
        for blank in ("+", "+    ", "+\t"):
            with self.subTest(blank=blank):
                padded = base.replace("+x = 2\n", f"+x = 2\n{blank}\n")
                self.assertEqual(self.digest(base), self.digest(padded))

    def test_a_diff_of_only_blank_lines_has_no_digest(self) -> None:
        self.assertIsNone(self.digest(change("")))
        self.assertIsNone(self.digest(change("   ")))

    def test_crlf_line_ends_do_not_count(self) -> None:
        diff = change("fix") + rename("old.txt", "new.txt")
        self.assertEqual(self.digest(diff), self.digest(diff.replace("\n", "\r\n")))

    def test_no_change_has_no_digest(self) -> None:
        for diff in ("", "\n", "diff --git a/n.txt b/n.txt\nindex 1..2 100644\n"):
            with self.subTest(diff=diff):
                self.assertIsNone(self.digest(diff))


SIBLING = 40  # another pull request, closed, that closes issue 7 too
SIBLING_HEADS = ("1" * 40, "2" * 40, "3" * 40)


class FailsOnAnotherPullRequestForTheSameIssueCount(unittest.TestCase):
    """A new pull request for the same issue does not reset the cap: counted
    FAILs of any pull request in this repository, open or closed, that closes
    one of this pull request's closing issues count toward
    `merge.max-verify-fails`, at their own heads."""

    @staticmethod
    def sibling_fails(*shas: str, number: int = SIBLING) -> FakeGitHub:
        """A pass at the head, and FAILs of pull request `number` (branch
        feat/old) at `shas`."""
        runs = {i: judged(i, OLDER_START) for i in range(2, 2 + len(shas))}
        fake = passing(
            *(artifact(named(sha, "fail", number), i) for i, sha in zip(runs, shas)),
            runs=runs,
        )
        for sha in shas:
            fake.records[named(sha, "fail", number)] = record(
                number, sha, verdict="fail", head_ref="feat/old"
            )
        fake.closers[7] = [(SIBLING, REPO), (PR, REPO)]
        return fake

    def test_three_fails_on_a_closed_pull_request_refuse(self) -> None:
        evidence = read(self.sibling_fails(*SIBLING_HEADS))
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertTrue(evidence.needs_human)

    def test_two_there_and_one_here_refuse(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS[:2])
        fake.artifacts.append(artifact(named(EARLIER, "fail"), 9))
        fake.runs[9] = judged(9, OLDER_START)
        self.assertEqual(read(fake).refusal, "verify:repeated-fail")

    def test_two_there_and_a_fail_at_the_head_go_to_a_human(self) -> None:
        # Not to a fix round whose push could never merge.
        fake = self.sibling_fails(*SIBLING_HEADS[:2])
        fake.artifacts.append(artifact(named(HEAD, "fail"), 9))
        fake.runs[9] = judged(9, OLDER_START)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertEqual(
            evidence.report()["headFail"], {"run": 9, "artifact": named(HEAD, "fail")}
        )

    def test_one_there_and_a_fail_at_the_head_wait_for_a_fix_round(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS[:1])
        fake.artifacts.append(artifact(named(HEAD, "fail"), 9))
        fake.runs[9] = judged(9, OLDER_START)
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_two_there_leave_the_pass_to_decide(self) -> None:
        self.assertIsNone(read(self.sibling_fails(*SIBLING_HEADS[:2])).refusal)

    def test_a_pull_request_closing_another_issue_does_not_count(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS)
        fake.closers[7] = [(PR, REPO)]
        self.assertIsNone(read(fake).refusal)

    def test_a_pull_request_in_another_repository_does_not_count(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS)
        fake.closers[7] = [(SIBLING, "example-org/other"), (PR, REPO)]
        self.assertIsNone(read(fake).refusal)

    def test_a_cut_list_of_closing_pull_requests_refuses(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS[:1])
        fake.closers_total[7] = 60
        self.assertEqual(read(fake).refusal, "verify:unreadable")

    def test_an_unreadable_fail_run_of_a_sibling_refuses(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS[:2])
        del fake.runs[3]
        self.assertEqual(read(fake).refusal, "verify:unreadable")


class RepeatedFailsGoToAHuman(unittest.TestCase):
    """FAILs at `merge.max-verify-fails` (default 3) distinct heads of one
    pull request hold it for a human whatever a later pass says (owner
    decision 2026-10-21); fewer leave the pass to decide."""

    @staticmethod
    def failed_at(*shas: str) -> FakeGitHub:
        """A pass at the head (run 1) and a FAIL tied to the pull request at
        each of `shas`, every one judged before the pass."""
        runs = {i: judged(i, OLDER_START) for i in range(2, 2 + len(shas))}
        return passing(
            *(artifact(named(sha, "fail"), i) for i, sha in zip(runs, shas)),
            runs=runs,
        )

    def test_fails_at_three_heads_refuse_despite_a_later_pass(self) -> None:
        evidence = read(self.failed_at(EARLIER, IN_PR, UNRELATED))
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertTrue(evidence.needs_human)
        self.assertIn("3", evidence.detail or "")

    def test_fails_at_two_heads_leave_the_pass_to_decide(self) -> None:
        self.assertIsNone(read(self.failed_at(EARLIER, IN_PR)).refusal)

    def test_fails_at_one_head_count_once(self) -> None:
        fake = self.failed_at(EARLIER, IN_PR)
        # A second FAIL at IN_PR, under another number, tied by the commit.
        fake.artifacts.append(artifact(named(IN_PR, "fail", 99), 4))
        fake.runs[4] = judged(4, OLDER_START)
        evidence = read(fake)
        self.assertIsNone(evidence.refusal)
        self.assertEqual(len([v for v in evidence.verdicts if v.verdict == "fail"]), 3)

    def test_a_fail_at_the_head_that_reaches_the_cap_is_repeated_fail(self) -> None:
        # The third failing head goes to a human, not to a fourth fix round,
        # and names its own FAIL for the escalation to quote.
        fake = self.failed_at(EARLIER, IN_PR, HEAD)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertTrue(evidence.needs_human)
        self.assertEqual(
            evidence.report()["headFail"], {"run": 4, "artifact": named(HEAD, "fail")}
        )

    def test_a_fail_at_the_head_under_the_cap_stays_verify_fail(self) -> None:
        fake = self.failed_at(EARLIER, HEAD)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertFalse(evidence.needs_human)

    def test_the_reader_takes_its_cap_from_the_setting(self) -> None:
        fake = self.failed_at(EARLIER, IN_PR)
        for cap, expected in (
            (2, "verify:repeated-fail"),
            (1, "verify:repeated-fail"),
            (3, None),
        ):
            with self.subTest(cap=cap):
                with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
                    reader = ve.Reader(REPO, "main", now=NOW, max_fails=cap)
                    self.assertEqual(
                        reader.evidence(PR, HEAD, pull()).refusal, expected
                    )


class AFailCountsWhateverTheRunConcluded(unittest.TestCase):
    """The upload comes before later steps, so a cancel or a failed later step
    must not erase a FAIL; a PASS needs a completed success."""

    UNFINISHED = {
        "failed later": {"conclusion": "failure"},
        "cancelled": {"conclusion": "cancelled"},
        "still going": {"status": "in_progress", "conclusion": None},
        "completed without success": {"status": "completed", "conclusion": None},
        "not completed": {"status": "queued", "conclusion": "success"},
    }

    def test_a_fail_from_an_unfinished_run_blocks(self) -> None:
        for label, overrides in self.UNFINISHED.items():
            with self.subTest(label):
                fake = FakeGitHub(
                    [artifact(named(HEAD, "fail"), 1)], {1: run(1, **overrides)}
                )
                self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_pass_from_an_unfinished_run_does_not_count(self) -> None:
        for label, overrides in self.UNFINISHED.items():
            with self.subTest(label):
                fake = passing()
                fake.runs[1] = run(1, **overrides)
                self.assertEqual(read(fake).refusal, "verify:missing")


class UnauthenticatedArtifactsAreIgnored(unittest.TestCase):
    """Each forgery changes one field of the run record. As a pass at the head
    it reads `verify:missing`; as a FAIL at an earlier head beside a real pass
    it must not route to a human."""

    FORGERIES = {
        "another workflow": {"path": ".github/workflows/pr-require-checks.yml"},
        "a pull_request run": {"event": "pull_request"},
        "a pull_request_target run": {"event": "pull_request_target"},
        "a branch other than main": {"head_branch": "feat/x"},
        "another repository": {"repository": {"full_name": "someone/fork"}},
        "a fork head": {"head_repository": {"full_name": "someone/fork"}},
        "a run head off main": {"head_sha": OFF_MAIN},
        "a malformed run head": {"head_sha": "c" * 39},
        "another run's record": {"id": 12345},
    }

    def test_each_forgery_counts_neither_as_pass_nor_fail(self) -> None:
        for label, overrides in self.FORGERIES.items():
            with self.subTest(label):
                # Only the off-main case may fail on the compare.
                on_main = (
                    set()
                    if label == "a run head off main"
                    else {overrides.get("head_sha", MAIN_SHA)}
                )
                forged_pass = passing()
                forged_pass.on_main |= on_main
                forged_pass.runs[1] = run(1, **overrides)
                self.assertEqual(read(forged_pass).refusal, "verify:missing")
                forged_fail = passing(
                    artifact(named(EARLIER, "fail"), 9), runs={9: run(9, **overrides)}
                )
                forged_fail.on_main |= on_main
                evidence = read(forged_fail)
                self.assertIsNone(evidence.refusal)
                self.assertEqual(evidence.report()["ignored"], 1)

    def test_an_expired_artifact_is_skipped(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 1, expired=True)], {1: run(1)})
        self.assertEqual(read(fake).refusal, "verify:missing")
        self.assertFalse(any("actions/runs/1" in " ".join(c) for c in fake.calls))

    def test_a_name_that_does_not_parse_is_ignored(self) -> None:
        for name in (
            f"pr-verify-{PR}-{HEAD}-FAIL",
            f"pr-verify-{PR}-{HEAD[:39]}-fail",
            f"pr-verify-{PR}-{HEAD}-fail-extra",
        ):
            with self.subTest(name):
                fake = FakeGitHub([artifact(name, 1)], {1: run(1)})
                self.assertEqual(read(fake).refusal, "verify:missing")


class UnreadableReadsBlock(unittest.TestCase):
    def test_a_fail_whose_run_cannot_be_read_blocks(self) -> None:
        fake = passing(artifact(named(EARLIER, "fail"), 7))
        self.assertEqual(read(fake).refusal, "verify:unreadable")

    def test_a_fail_whose_compare_cannot_be_read_blocks(self) -> None:
        fake = passing(artifact(named(EARLIER, "fail"), 2), runs={2: run(2)})
        fake.fail = {"/compare/"}
        self.assertEqual(read(fake).refusal, "verify:unreadable")

    def test_a_pass_whose_run_cannot_be_read_is_missing(self) -> None:
        fake = passing()
        del fake.runs[1]
        self.assertEqual(read(fake).refusal, "verify:missing")

    def test_an_unreadable_listing_commits_or_cap_refuses(self) -> None:
        for kind in ("actions/artifacts", "/commits"):
            with self.subTest(kind):
                fake = passing()
                fake.fail = {kind}
                self.assertEqual(read(fake).refusal, "verify:unreadable")
        capped = passing()
        capped.commits = [f"{i:040x}" for i in range(250)]
        self.assertEqual(read(capped).refusal, "verify:unreadable")


class AFailedReadRefusesWithoutAHuman(unittest.TestCase):
    """Issue #9063: a read that fails (a rate limit, pr-merge run
    39725996983) refuses `verify:unreadable`, which the next run re-derives,
    never `verify:earlier-fail`, which holds the head for a human."""

    earlier_fail = staticmethod(ACountedPassAtTheHeadClearsAnEarlierFail.earlier_fail)

    @staticmethod
    def foreign_fail(fake: FakeGitHub) -> FakeGitHub:
        """Adds another pull request's FAIL (run 3) whose record cannot be
        read."""
        fake.artifacts.append(artifact(named(UNRELATED, "fail", 99), 3))
        fake.runs[3] = run(3)
        return fake

    def test_an_unreadable_foreign_record_beside_a_cleared_fail(self) -> None:
        fake = self.foreign_fail(self.earlier_fail())
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertFalse(evidence.needs_human)
        # The next run reads the record and the cleared FAIL merges.
        fake.records[named(UNRELATED, "fail", 99)] = record(
            99, UNRELATED, verdict="fail", head_ref="feat/y"
        )
        self.assertIsNone(read(fake).refusal)

    def test_an_uncleared_earlier_fail_still_refuses(self) -> None:
        fake = self.foreign_fail(
            FakeGitHub([artifact(named(EARLIER, "fail"), 2)], {2: run(2)})
        )
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertFalse(evidence.needs_human)

    def test_a_fail_at_the_head_still_refuses(self) -> None:
        fake = self.foreign_fail(
            FakeGitHub([artifact(named(HEAD, "fail"), 2)], {2: run(2)})
        )
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertFalse(evidence.needs_human)

    def test_a_failed_run_time_read(self) -> None:
        # A second gate process counts the FAIL from the shared run record,
        # then reads its run again for the time, under a rate limit.
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        cache = str(pathlib.Path(tmp.name, "run.json"))
        fake = self.earlier_fail()
        with mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": cache}):
            self.assertIsNone(read(fake).refusal)
            fake.fail = {"actions/runs/2"}
            evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertFalse(evidence.needs_human)

    def test_a_failed_change_read(self) -> None:
        for sha in (EARLIER, HEAD):
            for status in (403, 502):
                with self.subTest(sha=sha, status=status):
                    fake = self.earlier_fail()
                    fake.fail = {f"compare/main...{sha}"}
                    fake.fail_status = status
                    evidence = read(fake)
                    self.assertEqual(evidence.refusal, "verify:unreadable")
                    self.assertFalse(evidence.needs_human)


class AnOldPullRequestGoesToAHuman(unittest.TestCase):
    def test_older_than_80_days_is_too_old(self) -> None:
        evidence = read(passing(), pull(created_at="2026-07-27T23:00:00Z"))
        self.assertEqual(evidence.refusal, "verify:too-old")
        self.assertTrue(evidence.needs_human)

    def test_79_days_is_judged(self) -> None:
        self.assertIsNone(
            read(passing(), pull(created_at="2026-07-29T00:00:00Z")).refusal
        )


class TheSpecMustBeTrusted(unittest.TestCase):
    def with_issues(self, issues: list[dict[str, Any]], **pr: Any) -> ve.Evidence:
        fake = passing()
        fake.records[named(HEAD, "pass")] = record(linked_issues=issues)
        fake.closing = [(issue["number"], REPO) for issue in issues]
        return read(fake, pull(**pr))

    def test_a_trusted_humans_issue_allows(self) -> None:
        self.assertIsNone(self.with_issues([TRUSTED_ISSUE]).refusal)

    def test_an_issue_by_anyone_else_does_not(self) -> None:
        cases = {
            "a bot": {**TRUSTED_ISSUE, "author_type": "Bot", "author_id": 200},
            "an unlisted user": {
                **TRUSTED_ISSUE,
                "author_id": 999,
                "author_login": "x",
            },
            "a listed bot as a user": {**TRUSTED_ISSUE, "author_id": 200},
            "a listed human's id on a bot": {**TRUSTED_ISSUE, "author_type": "Bot"},
        }
        for label, issue in cases.items():
            with self.subTest(label):
                evidence = self.with_issues([issue])
                self.assertEqual(evidence.refusal, "verify:untrusted-spec")
                self.assertTrue(evidence.needs_human)
        self.assertEqual(self.with_issues([]).refusal, "verify:untrusted-spec")

    def test_a_trusted_human_authors_own_issue_allows(self) -> None:
        for user in ({"login": "Maintainer"}, {"login": "maintainer"}, {}):
            with self.subTest(user=user):
                self.assertIsNone(self.with_issues([TRUSTED_ISSUE], user=user).refusal)

    def test_an_untrusted_authors_own_issue_does_not(self) -> None:
        cases = {
            "the lanes App": (
                {
                    **TRUSTED_ISSUE,
                    "author_login": "agent-lanes[bot]",
                    "author_id": 200,
                    "author_type": "Bot",
                },
                {"login": "agent-lanes[bot]"},
            ),
            "an unlisted user": (
                {**TRUSTED_ISSUE, "author_login": "x", "author_id": 999},
                {"login": "x"},
            ),
        }
        for label, (issue, user) in cases.items():
            with self.subTest(label):
                self.assertEqual(
                    self.with_issues([issue], user=user).refusal,
                    "verify:untrusted-spec",
                )

    def test_every_linked_issue_must_be_trusted(self) -> None:
        # A trivially satisfied human issue beside the lanes App's own.
        bot = {**TRUSTED_ISSUE, "number": 8, "author_type": "Bot", "author_id": 200}
        self.assertEqual(
            self.with_issues([bot, TRUSTED_ISSUE]).refusal, "verify:untrusted-spec"
        )
        second = {**TRUSTED_ISSUE, "number": 8}
        self.assertIsNone(self.with_issues([TRUSTED_ISSUE, second]).refusal)

    def test_an_edit_by_anyone_but_a_trusted_user_refuses(self) -> None:
        edited = {**TRUSTED_ISSUE, "last_edited_at": "2026-10-14T00:00:00Z"}
        cases = {
            "the lanes App": {
                "editor_login": "agent-lanes[bot]",
                "editor_id": 200,
                "editor_type": "Bot",
            },
            "a listed human's id as a bot": {
                "editor_login": "maintainer",
                "editor_id": 100,
                "editor_type": "Bot",
            },
            "an unlisted user": {
                "editor_login": "x",
                "editor_id": 999,
                "editor_type": "User",
            },
            "no editor": {"editor_login": None, "editor_id": None, "editor_type": None},
        }
        for label, editor in cases.items():
            with self.subTest(label):
                fake = passing()
                fake.records[named(HEAD, "pass")] = record(
                    linked_issues=[{**edited, **editor}]
                )
                self.assertEqual(read(fake).refusal, "verify:untrusted-spec")
        trusted = {
            **edited,
            "editor_login": "maintainer",
            "editor_id": 100,
            "editor_type": "User",
        }
        self.assertIsNone(self.with_issues([trusted]).refusal)
        # The PR author editing their own issue is still a trusted human.
        self.assertIsNone(
            self.with_issues([trusted], user={"login": "maintainer"}).refusal
        )

    def test_a_record_for_another_head_or_an_unreadable_list_refuses(self) -> None:
        fake = passing()
        fake.records[named(HEAD, "pass")] = record(sha=EARLIER)
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        fake = passing()
        fake.actors = {"version": 2, "actors": []}
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        fake = passing()
        del fake.records[named(HEAD, "pass")]
        self.assertEqual(read(fake).refusal, "verify:unreadable")


class TheSpecCommentsMustBeTheJudgedOnes(unittest.TestCase):
    """The trusted comments on each linked issue now (by a User on the
    trusted list's humans, last edited if ever by one) must be the ones the
    verdict recorded, by id and update time."""

    RECORDED = [{"id": 1, "updated_at": "2026-10-12T00:00:00Z"}]

    def judge(
        self, live: list[dict[str, Any]], recorded: Any = None, **pr: Any
    ) -> str | None:
        fake = passing()
        issue = {
            **TRUSTED_ISSUE,
            "spec_comments": self.RECORDED if recorded is None else recorded,
        }
        fake.records[named(HEAD, "pass")] = record(linked_issues=[issue])
        fake.closing_comments = {7: live}
        return read(fake, pull(**pr)).refusal

    def test_the_same_trusted_comments_allow(self) -> None:
        self.assertIsNone(self.judge([comment(1, HUMAN)]))

    def test_an_added_edited_or_deleted_trusted_comment_refuses(self) -> None:
        cases = {
            "added": [comment(1, HUMAN), comment(2, HUMAN)],
            "edited": [comment(1, HUMAN, "2026-10-13T00:00:00Z")],
            "deleted": [],
            "edited by the lanes App": [
                comment(
                    1, HUMAN, lastEditedAt="2026-10-12T00:00:00Z", editor=LANES_ACTOR
                )
            ],
        }
        for label, live in cases.items():
            with self.subTest(label):
                self.assertEqual(self.judge(live), "verify:spec-changed")

    def test_untrusted_comments_are_not_part_of_the_spec(self) -> None:
        stranger = {"__typename": "User", "login": "stranger", "databaseId": 999}
        bot_with_human_id = {**HUMAN, "__typename": "Bot"}
        live = [
            comment(1, HUMAN),
            comment(3, LANES_ACTOR),
            comment(4, stranger),
            comment(5, bot_with_human_id),
        ]
        self.assertIsNone(self.judge(live))

    def test_a_trusted_pr_authors_comments_are_part_of_the_spec(self) -> None:
        user = {"login": "maintainer"}
        self.assertIsNone(self.judge([comment(1, HUMAN)], user=user))
        self.assertEqual(
            self.judge([comment(1, HUMAN)], [], user=user), "verify:spec-changed"
        )

    def test_a_partial_comment_read_or_a_malformed_record_refuses(self) -> None:
        fake = passing()
        fake.records[named(HEAD, "pass")] = record(
            linked_issues=[{**TRUSTED_ISSUE, "spec_comments": self.RECORDED}]
        )
        fake.closing_comments = {7: [comment(1, HUMAN)]}
        fake.comments_total = {7: 101}
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        for recorded in ("x", [{"id": "1", "updated_at": "t"}], [{"id": 1}]):
            with self.subTest(recorded):
                self.assertEqual(
                    self.judge([comment(1, HUMAN)], recorded), "verify:unreadable"
                )


class TheSpecMustBeTheJudgedOne(unittest.TestCase):
    """The PR's closing issues now must be the ones the verdict recorded."""

    def test_the_same_closing_issues_allow(self) -> None:
        fake = passing()
        fake.closing = [
            (7, REPO),
            (3, "someone/else"),
        ]  # another repository's is left out
        self.assertIsNone(read(fake).refusal)

    def test_a_changed_set_refuses(self) -> None:
        for label, closing in {
            "another issue": [(8, REPO)],
            "one more": [(7, REPO), (8, REPO)],
            "none": [],
        }.items():
            with self.subTest(label):
                fake = passing()
                fake.closing = closing
                evidence = read(fake)
                self.assertEqual(evidence.refusal, "verify:spec-changed")
                self.assertTrue(evidence.needs_human)

    def test_an_issue_edited_after_the_judgment_started_refuses(self) -> None:
        fake = passing()
        fake.closing_edited = {7: "2026-10-15T00:00:01Z"}
        self.assertEqual(read(fake).refusal, "verify:spec-changed")
        fake = passing()
        fake.closing_edited = {7: "2026-10-14T23:59:59Z"}
        self.assertIsNone(read(fake).refusal)

    def test_an_unreadable_edit_or_start_time_refuses(self) -> None:
        fake = passing()
        fake.closing_edited = {7: "yesterday"}
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        fake = passing()
        fake.runs[1] = run(1, run_started_at=None)
        fake.closing_edited = {7: "2026-10-14T00:00:00Z"}
        self.assertEqual(read(fake).refusal, "verify:unreadable")

    def test_an_unreadable_or_partial_listing_refuses(self) -> None:
        fake = passing()
        fake.fail = {"graphql"}
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        fake = passing()
        fake.closing_total = 11
        self.assertEqual(read(fake).refusal, "verify:unreadable")

    def test_a_pull_request_record_of_no_known_shape_refuses(self) -> None:
        with mock.patch.object(postmerge, "gh_capture", side_effect=passing()):
            evidence = ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, {})
        self.assertEqual(evidence.refusal, "verify:unreadable")

    def test_the_pull_request_is_the_intent_when_it_closes_no_issue(self) -> None:
        # Owner decision 2026-10-22: a trusted PR with no closing issue is
        # judged against its own title and body, recorded as the intent.
        pr = pull()
        text = f"{pr.get('title') or ''}\n\n{pr.get('body') or ''}"
        digest = hashlib.sha256(text.encode()).hexdigest()

        def evidence(closing: list[Any], **recorded: Any) -> Any:
            fake = passing()
            fake.closing = closing
            recorded.setdefault("intent_sha256", digest)
            fake.records[named(HEAD, "pass")] = record(linked_issues=[], **recorded)
            return read(fake, pr).refusal

        self.assertIsNone(evidence([], intent="pull-request"))
        self.assertIsNone(evidence([(3, "someone/else")], intent="pull-request"))
        self.assertEqual(evidence([]), "verify:untrusted-spec")
        self.assertEqual(evidence([], intent="issues"), "verify:untrusted-spec")
        self.assertEqual(
            evidence([(7, REPO)], intent="pull-request"), "verify:spec-changed"
        )

    def test_a_pull_request_intent_edited_since_its_verdict_refuses(self) -> None:
        # S&C D: the verdict records the hash of the title and body it judged.
        def evidence(title: str, body: str, digest: str | None) -> Any:
            fake = passing()
            fake.closing = []
            recorded = {"intent": "pull-request"}
            if digest is not None:
                recorded["intent_sha256"] = digest
            fake.records[named(HEAD, "pass")] = record(linked_issues=[], **recorded)
            return read(fake, pull(title=title, body=body)).refusal

        judged = hashlib.sha256(b"feat: x\n\nthe body").hexdigest()
        self.assertIsNone(evidence("feat: x", "the body", judged))
        self.assertEqual(evidence("feat: x", "edited", judged), "verify:spec-changed")
        self.assertEqual(evidence("feat: x", "the body", None), "verify:spec-changed")

    def test_a_record_whose_issues_are_not_a_list_refuses(self) -> None:
        fake = passing()
        fake.records[named(HEAD, "pass")] = record(linked_issues=None)
        self.assertEqual(read(fake).refusal, "verify:unreadable")


class AQueuedDependabotEntryNeedsNoVerdict(unittest.TestCase):
    """The pr-merge lane enqueues Dependabot pull requests in their own class
    (babysit_dependabot), which pr-verify never judges."""

    def hold(self, user: dict[str, Any]) -> tuple[str | None, FakeGitHub]:
        fake = FakeGitHub([], {})
        with (
            mock.patch.object(policy, "pull_request", return_value=pull(user=user)),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        ):
            return ve.Reader(REPO, "main", now=NOW).queued_hold(PR), fake

    def test_a_dependency_managers_entry_is_not_held(self) -> None:
        for login in ("dependabot[bot]", "renovate[bot]"):
            with self.subTest(login):
                hold, fake = self.hold({"login": login, "type": "Bot"})
                self.assertIsNone(hold)
                self.assertEqual(fake.calls, [])

    def test_a_user_named_like_a_dependency_manager_is_judged(self) -> None:
        for login in ("dependabot[bot]", "renovate"):
            with self.subTest(login):
                hold, _ = self.hold({"login": login, "type": "User"})
                self.assertEqual(hold, "verify:missing")

    def test_anyone_elses_entry_is_judged(self) -> None:
        hold, _ = self.hold({"login": "agent-lanes[bot]", "type": "Bot"})
        self.assertEqual(hold, "verify:missing")


class ActionsReadsUseTheActionsToken(unittest.TestCase):
    """The lane token holds no Actions permission, so the artifact listing,
    the run records and the download run under `BABYSIT_VERIFY_GH_TOKEN`, as
    do the run heads' compares to the branch (a contents read the job token
    serves, kept off the lane App's quota); every other read keeps the
    process token."""

    ACTIONS = ("actions/artifacts", "actions/runs/", "run download", "/compare/")

    def reads(self, reader: ve.Reader) -> dict[str, Any]:
        fake = passing()
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
        return {" ".join(args): env for args, env in fake.envs}

    def test_only_the_actions_reads_carry_the_token(self) -> None:
        reads = self.reads(ve.Reader(REPO, "main", now=NOW, actions_token="tok"))
        for call, env in reads.items():
            with self.subTest(call):
                if any(kind in call for kind in self.ACTIONS):
                    self.assertEqual(env, {"GH_TOKEN": "tok"})
                else:
                    self.assertIsNone(env)
        for kind in self.ACTIONS:
            self.assertTrue(any(kind in call for call in reads), kind)

    def test_the_token_comes_from_the_environment(self) -> None:
        with mock.patch.dict("os.environ", {"BABYSIT_VERIFY_GH_TOKEN": "env-tok"}):
            reader = ve.Reader(REPO, "main", now=NOW)
        self.assertEqual(reader.actions_token, "env-tok")
        with mock.patch.dict("os.environ", {}, clear=True):
            reads = self.reads(ve.Reader(REPO, "main", now=NOW))
        self.assertTrue(all(env is None for env in reads.values()))


class TheListingIsReadOncePerReader(unittest.TestCase):
    def test_two_reads_share_one_listing(self) -> None:
        fake = passing()
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            reader = ve.Reader(REPO, "main", now=NOW)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
        listings = [c for c in fake.calls if any("actions/artifacts" in a for a in c)]
        self.assertEqual(len(listings), 1)

    def test_a_failed_listing_refuses_every_entry_and_is_not_read_per_entry(
        self,
    ) -> None:
        # One outage holds the whole queue rather than merging blind.
        fake = passing()
        fake.fail = {"actions/artifacts"}
        with (
            mock.patch.object(policy, "pull_request", return_value=pull()),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        ):
            reader = ve.Reader(REPO, "main", now=NOW)
            holds = [reader.queued_hold(n) for n in (PR, PR, PR)]
        self.assertEqual(holds, ["verify:unreadable"] * 3)
        listings = [c for c in fake.calls if any("actions/artifacts" in a for a in c)]
        self.assertEqual(len(listings), len(ve.LISTING_WAITS) + 1)


def listings(fake: FakeGitHub) -> int:
    return sum(any("actions/artifacts" in a for a in c) for c in fake.calls)


class TheListingIsReadOncePerRun(unittest.TestCase):
    """pr-merge.yml runs one gate, so one `Reader`, per candidate and names a
    file in `BABYSIT_VERIFY_LISTING`: the run pages the artifact listing once,
    and a saved listing never allows on its own."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = str(pathlib.Path(tmp.name, "verify-listing.json"))
        patcher = mock.patch.dict("os.environ", {"BABYSIT_VERIFY_LISTING": self.path})
        patcher.start()
        self.addCleanup(patcher.stop)

    def gate(self, fake: FakeGitHub) -> tuple[ve.Reader, ve.Evidence]:
        """One candidate's gate run: a fresh Reader."""
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            reader = ve.Reader(REPO, "main", now=NOW)
            return reader, reader.evidence(PR, HEAD, pull())

    def test_candidates_of_one_run_share_one_listing(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 1)], {1: run(1)})
        for _ in range(3):
            _, evidence = self.gate(fake)
            self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(listings(fake), 1)

    def test_an_allow_on_the_saved_listing_sees_a_later_fail(self) -> None:
        first, _ = self.gate(passing())
        self.assertFalse(first.saved)
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            reader = ve.Reader(REPO, "main", now=NOW)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
            self.assertTrue(reader.saved)
            reader.refresh()
            self.assertEqual(reader.evidence(PR, HEAD, pull()).refusal, "verify:fail")
        self.assertFalse(reader.saved)
        self.assertEqual(listings(fake), 1)
        # The fresher listing is saved for the rest of the run.
        _, evidence = self.gate(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(listings(fake), 1)

    def test_a_failed_listing_is_not_saved(self) -> None:
        fake = passing()
        fake.fail = {"actions/artifacts"}
        _, evidence = self.gate(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertFalse(pathlib.Path(self.path).exists())
        fake.fail = set()
        _, evidence = self.gate(fake)
        self.assertIsNone(evidence.refusal)

    def hold(self, fake: FakeGitHub) -> str | None:
        """A later candidate's gate run judging PR 41 as a queued entry."""
        with (
            mock.patch.object(policy, "pull_request", return_value=pull()),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        ):
            return ve.Reader(REPO, "main", now=NOW).queued_hold(PR)

    def failed_since(self) -> FakeGitHub:
        """The pass the saved listing holds, and a FAIL at the head since."""
        return passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})

    def test_a_saved_listing_without_its_time_is_not_used_for_a_hold(self) -> None:
        pathlib.Path(self.path).write_text(json.dumps(passing().artifacts))
        fake = self.failed_since()
        self.assertEqual(self.hold(fake), "verify:fail")
        self.assertEqual(listings(fake), 1)

    def test_a_saved_listing_past_the_bound_is_not_used(self) -> None:
        clock = [datetime(2026, 10, 16, 12, 0, tzinfo=UTC)]
        with mock.patch.object(ve, "_wall_clock", side_effect=lambda: clock[0]):
            self.gate(passing())
            clock[0] += ve.LISTING_MAX_AGE + timedelta(seconds=1)
            fake = self.failed_since()
            self.assertEqual(self.hold(fake), "verify:fail")
            self.assertEqual(listings(fake), 1)
            # The listing that hold read is saved and recent: the candidate
            # after it reads it, and the FAIL refuses that candidate too.
            _, evidence = self.gate(fake)
            self.assertEqual(evidence.refusal, "verify:fail")
            self.assertEqual(listings(fake), 1)

    def test_a_listing_in_memory_past_the_bound_is_read_again(self) -> None:
        clock = [datetime(2026, 10, 16, 12, 0, tzinfo=UTC)]
        fake = passing()
        with (
            mock.patch.object(ve, "_wall_clock", side_effect=lambda: clock[0]),
            mock.patch.object(policy, "pull_request", return_value=pull()),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        ):
            reader = ve.Reader(REPO, "main", now=NOW)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
            clock[0] += ve.LISTING_MAX_AGE
            self.assertIsNone(reader.queued_hold(PR))
            self.assertEqual(listings(fake), 1)
            fake.artifacts.append(artifact(named(HEAD, "fail"), 2))
            fake.runs[2] = run(2)
            clock[0] += timedelta(seconds=1)
            self.assertEqual(reader.queued_hold(PR), "verify:fail")
        self.assertEqual(listings(fake), 2)

    def test_a_malformed_saved_listing_is_read_from_the_api(self) -> None:
        recent = datetime.now(UTC).isoformat()
        for text in (
            "not json",
            "[]",
            '{"artifacts": []}',
            json.dumps({"fetchedAt": "yesterday", "artifacts": []}),
            json.dumps({"fetchedAt": "2026-10-16T12:00:00", "artifacts": []}),
            json.dumps({"fetchedAt": recent, "artifacts": [1]}),
            json.dumps({"fetchedAt": recent}),
        ):
            with self.subTest(text):
                pathlib.Path(self.path).write_text(text)
                fake = passing()
                reader, evidence = self.gate(fake)
                self.assertIsNone(evidence.refusal)
                self.assertFalse(reader.saved)
                self.assertEqual(listings(fake), 1)


class OneRunSharesItsVerifierReads(unittest.TestCase):
    """With `BABYSIT_RUN_CACHE` named, the gate processes of one run share a
    run head found on the branch and the trusted-actor list (for its bound);
    a head not found on the branch is compared again."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = str(pathlib.Path(tmp.name, "run.json"))
        patcher = mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": path})
        patcher.start()
        self.addCleanup(patcher.stop)

    @staticmethod
    def compares(fake: FakeGitHub, sha: str) -> int:
        return sum(f"/compare/{sha}..." in " ".join(c) for c in fake.calls)

    @staticmethod
    def trusted_reads(fake: FakeGitHub) -> int:
        return sum(any("/contents/" in a for a in c) for c in fake.calls)

    def candidates(self, fake: FakeGitHub, count: int) -> None:
        for _ in range(count):
            self.assertIsNone(read(fake).refusal)

    def test_a_head_on_the_branch_is_compared_once_per_run(self) -> None:
        fake = passing()
        self.candidates(fake, 3)
        self.assertEqual(self.compares(fake, MAIN_SHA), 1)

    def test_a_head_off_the_branch_is_compared_by_every_candidate(self) -> None:
        off = "d" * 40
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2, head_sha=off)})
        self.candidates(fake, 2)
        self.assertEqual(self.compares(fake, off), 2)

    def test_a_judgment_notes_its_oldest_shared_read(self) -> None:
        # The trusted list another process read 90 s ago dates the judgment.
        clock = [datetime(2026, 10, 18, 11, 58, 30, tzinfo=UTC)]
        fake = passing()
        with (
            mock.patch.object(ve.run_cache, "now", side_effect=lambda: clock[0]),
            mock.patch.object(ve, "_wall_clock", side_effect=lambda: clock[0]),
        ):
            self.candidates(fake, 1)
            listed_before = clock[0]
            clock[0] += timedelta(seconds=90)
            with ve.run_cache.track() as taken:
                self.candidates(fake, 1)
        self.assertEqual(self.trusted_reads(fake), 1)
        self.assertEqual(min(taken), listed_before)
        self.assertIn(clock[0], taken)  # this process's own listing

    def test_the_trusted_list_is_read_once_within_the_bound(self) -> None:
        clock = [datetime(2026, 10, 18, 12, 0, tzinfo=UTC)]
        fake = passing()
        with mock.patch.object(ve.run_cache, "now", side_effect=lambda: clock[0]):
            self.candidates(fake, 2)
            self.assertEqual(self.trusted_reads(fake), 1)
            clock[0] += ve.run_cache.MAX_AGE + timedelta(seconds=1)
            self.candidates(fake, 1)
        self.assertEqual(self.trusted_reads(fake), 2)


class OneRunSharesItsFailRunReads(unittest.TestCase):
    """With `BABYSIT_RUN_CACHE` named, a FAIL's run record and an untied
    FAIL's recorded head ref are read once per run. A PASS's run is read by every gate process, so a re-run
    that undoes a completed success never allows on a shared record."""

    OTHER = UNRELATED

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = str(pathlib.Path(tmp.name, "run.json"))
        patcher = mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": path})
        patcher.start()
        self.addCleanup(patcher.stop)

    def other_fail(self) -> FakeGitHub:
        """A pass at the head (run 1) and another PR's FAIL (run 2)."""
        name = named(self.OTHER, "fail", 99)
        fake = passing(artifact(name, 2), runs={2: run(2)})
        fake.records[name] = record(99, self.OTHER, head_ref="feat/other")
        return fake

    @staticmethod
    def run_reads(fake: FakeGitHub, run_id: int) -> int:
        return sum(
            any(a.endswith(f"/actions/runs/{run_id}") for a in c) for c in fake.calls
        )

    @staticmethod
    def downloads(fake: FakeGitHub, run_id: int) -> int:
        return sum(c[:3] == ["run", "download", str(run_id)] for c in fake.calls)

    def test_a_fail_run_and_its_record_are_read_once_per_run(self) -> None:
        fake = self.other_fail()
        for _ in range(3):
            self.assertIsNone(read(fake).refusal)
        self.assertEqual(self.run_reads(fake, 2), 1)
        self.assertEqual(self.downloads(fake, 2), 1)
        # The pass's run is read by every candidate.
        self.assertEqual(self.run_reads(fake, 1), 3)

    def test_a_replaced_artifact_of_the_same_name_is_read_again(self) -> None:
        # An overwrite uploads a new id under the same name: the head ref
        # shared for the old id must not stand for the new contents.
        fake = self.other_fail()
        del fake.artifacts[0]  # no pass, so a tied FAIL refuses
        self.assertEqual(read(fake).refusal, "verify:missing")
        name = named(self.OTHER, "fail", 99)
        fake.artifacts[0] = {**fake.artifacts[0], "id": 21}
        fake.records[name] = record(99, self.OTHER, head_ref="feat/x")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")
        self.assertEqual(self.downloads(fake, 2), 2)

    def test_a_fail_run_is_not_read_again_past_the_shared_bound(self) -> None:
        # Origin rests on fields a re-run keeps, so the record serves the
        # whole run, however long the sweep takes.
        clock = [datetime(2026, 10, 18, 12, 0, tzinfo=UTC)]
        fake = self.other_fail()
        with mock.patch.object(ve.run_cache, "now", side_effect=lambda: clock[0]):
            read(fake)
            clock[0] += ve.run_cache.MAX_AGE * 20
            read(fake)
        self.assertEqual(self.run_reads(fake, 2), 1)

    def test_a_re_run_of_a_counted_pass_does_not_allow(self) -> None:
        fake = passing()
        self.assertIsNone(read(fake).refusal)
        fake.runs[1] = run(1, status="in_progress", conclusion=None, run_attempt=2)
        self.assertEqual(read(fake).refusal, "verify:missing")

    def test_a_re_run_of_a_fail_still_refuses_on_the_shared_record(self) -> None:
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})
        self.assertEqual(read(fake).refusal, "verify:fail")
        fake.runs[2] = run(2, status="in_progress", conclusion=None, run_attempt=2)
        self.assertEqual(read(fake).refusal, "verify:fail")
        self.assertEqual(self.run_reads(fake, 2), 1)


class ACarriedHeadServesOnlyAFail(unittest.TestCase):
    """A run head an earlier pr-merge run found on main reaches this run's
    cache as `carried-on-branch` (carry-run-cache.mjs). Only a FAIL's run may
    rest on it, where it can only count the FAIL; a PASS's run is compared by
    this run, so a wrong carried yes can never allow."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = pathlib.Path(tmp.name, "run.json")
        patcher = mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": str(self.path)})
        patcher.start()
        self.addCleanup(patcher.stop)
        at = datetime.now(UTC).isoformat()
        entry = {f"{REPO}|{MAIN_SHA}...main": {"at": at, "value": True}}
        self.path.write_text(json.dumps({"carried-on-branch": entry}))

    @staticmethod
    def compares(fake: FakeGitHub) -> int:
        return sum("/compare/" in " ".join(c) for c in fake.calls)

    def test_a_fail_run_rests_on_the_carried_head_with_no_compare(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 2)], {2: run(2)})
        self.assertEqual(read(fake).refusal, "verify:fail")
        self.assertEqual(self.compares(fake), 0)

    def test_a_carried_yes_the_branch_denies_still_counts_the_fail(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 2)], {2: run(2)})
        fake.on_main = set()
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_pass_run_is_compared_and_not_counted_off_the_branch(self) -> None:
        # The same run uploads another PR's FAIL first: its judgment rests on
        # the carried yes, and the PASS must not reuse it.
        other = named(UNRELATED, "fail", 99)
        fake = FakeGitHub(
            [artifact(other, 1), artifact(named(HEAD, "pass"), 1)],
            {1: run(1)},
            {named(HEAD, "pass"): record(), other: record(99, UNRELATED, head_ref="o")},
        )
        fake.on_main = set()
        self.assertEqual(read(fake).refusal, "verify:missing")
        self.assertEqual(self.compares(fake), 1)


CARRY = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/pr-merge/carry-run-cache.mjs"
)


class APoisonedCarriedCacheNeverRemovesARefusal(unittest.TestCase):
    """pr-merge restores the newest `pr-merge-run-cache-` entry its ref can
    read, which a job in the default branch's cache scope may have written.
    Whatever that entry holds, carry-run-cache.mjs and the reader together
    may only add refusals: a carried read that would turn a FAIL away is read
    again from GitHub."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)
        patcher = mock.patch.dict(
            "os.environ", {"BABYSIT_RUN_CACHE": str(self.dir / "run.json")}
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def restore(self, sections: dict[str, Any]) -> None:
        """Carry `sections`, as the cache restored them, into the run cache."""
        at = datetime.now(UTC).isoformat()
        restored = self.dir / "restored.json"
        restored.write_text(
            json.dumps(
                {
                    s: {k: {"at": at, "value": v} for k, v in e.items()}
                    for s, e in sections.items()
                }
            )
        )
        subprocess.run(
            ["node", str(CARRY)],
            env={
                "PATH": os.environ["PATH"],
                "CARRY_FROM": str(restored),
                "CARRY_TO": str(self.dir / "run.json"),
                "GITHUB_REPOSITORY": REPO,
            },
            check=True,
            capture_output=True,
        )

    def test_a_forged_run_head_does_not_turn_a_fail_away(self) -> None:
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})
        forged = run(2, head_sha=OFF_MAIN)
        for section in ("run-record", "carried-run-record"):
            with self.subTest(section=section):
                self.restore({section: {f"{REPO}|2": forged}})
                self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_forged_head_ref_does_not_untie_an_earlier_fail(self) -> None:
        name = named(UNRELATED, "fail", 99)
        fake = FakeGitHub([artifact(name, 2)], {2: run(2)})
        fake.records[name] = record(99, UNRELATED, head_ref="feat/x")
        for section in ("fail-head-ref", "carried-fail-head-ref"):
            with self.subTest(section=section):
                self.restore({section: {f"{REPO}|20": {"head_ref": "feat/other"}}})
                self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_forged_old_start_never_clears_an_earlier_fail(self) -> None:
        # GitHub says the FAIL's run started after the pass's; the cache
        # claims it started before.
        fake = passing(
            artifact(named(EARLIER, "fail"), 2),
            runs={2: judged(2, "2026-10-15T00:00:01Z")},
        )
        forged = judged(2, "2026-10-01T00:00:00Z")
        for section in ("run-record", "carried-run-record"):
            with self.subTest(section=section):
                self.restore({section: {f"{REPO}|2": forged}})
                self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_carried_reads_that_count_a_fail_spare_the_reads(self) -> None:
        name = named(UNRELATED, "fail", 99)
        fake = FakeGitHub([artifact(name, 2)], {2: run(2)})
        self.restore(
            {
                "run-record": {f"{REPO}|2": run(2)},
                "fail-head-ref": {f"{REPO}|20": {"head_ref": "feat/x"}},
                "on-branch": {f"{REPO}|{MAIN_SHA}...main": True},
            }
        )
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")
        self.assertFalse(any(c[-1].endswith("/actions/runs/2") for c in fake.calls))
        self.assertFalse(any(c[:3] == ["run", "download", "2"] for c in fake.calls))


# --- A transient listing failure is read again --------------------------------

# Every test runs without the backoff sleep; `judge` reads the waits off it.
_no_sleep = mock.patch.object(ve, "_listing_sleep")


# The tracker's human-gated label read an autonomous gate makes: stubbed so
# no test reads GitHub; a test that remaps it patches it again.
_role_label = mock.patch.object(postmerge, "_role_label", return_value="needs-human")


def setUpModule() -> None:
    _no_sleep.start()
    _role_label.start()


def tearDownModule() -> None:
    _role_label.stop()
    _no_sleep.stop()


def timed_out() -> RuntimeError:
    """What babysit_util.run_command raises when gh outlives its timeout."""
    try:
        raise subprocess.TimeoutExpired(["gh"], 60)
    except subprocess.TimeoutExpired as exc:
        try:
            raise RuntimeError("gh api timed out after 60s") from exc
        except RuntimeError as error:
            return error


class FlakyListing(FakeGitHub):
    """Fails the artifact listing with each of `errors` in turn: a string is
    gh's stderr on exit 1, an exception is raised from `gh_capture`."""

    def __init__(self, errors: list[str | BaseException]):
        fake = passing()
        super().__init__(fake.artifacts, fake.runs, fake.records)
        self.errors = errors
        self.timeouts: list[float | None] = []

    def __call__(
        self, args: list[str], **kwargs: Any
    ) -> subprocess.CompletedProcess[str]:
        if any("actions/artifacts" in a for a in args):
            self.timeouts.append(kwargs.get("timeout_seconds"))
            if self.errors:
                self.calls.append(args)
                error = self.errors.pop(0)
                if isinstance(error, BaseException):
                    raise error
                return subprocess.CompletedProcess(args, 1, "", error)
        return super().__call__(args, **kwargs)

    def listings(self) -> int:
        return sum(any("actions/artifacts" in a for a in c) for c in self.calls)


class ATransientListingFailureIsReadAgain(unittest.TestCase):
    # gh prints an API error as `gh: <message> (HTTP <status>)`
    # (babysit_gh.GH_HTTP_STATUS_RE); a request that got no response prints
    # gh's "error connecting to <host>" or Go's net/http error instead.
    TRANSIENT: tuple[str | BaseException, ...] = (
        "gh: Bad Gateway (HTTP 502)",
        "gh: Service Unavailable (HTTP 503)",
        "error connecting to api.github.com\n"
        "check your internet connection or https://githubstatus.com",
        'Get "https://api.github.com/repos/o/r/actions/artifacts": '
        "read tcp 10.0.0.1:443: read: connection reset by peer",
    )
    NOT_TRANSIENT: tuple[str | BaseException, ...] = (
        "gh: Not Found (HTTP 404)",
        "gh: Bad credentials (HTTP 401)",
        "gh: Validation Failed (HTTP 422)",
        # GitHub's answer to a GITHUB_TOKEN without the needed permission.
        "gh: Resource not accessible by integration (HTTP 403)",
        # Rate limits (GitHub docs, "Rate limits for the REST API"): a fixed
        # short wait outlasts neither, so neither is read again.
        "gh: Too Many Requests (HTTP 429)",
        "gh: You have exceeded a secondary rate limit. (HTTP 403)",
        "gh: API rate limit exceeded for installation ID 1. (HTTP 403)",
        # A read that used the whole gh timeout, gh with no credential
        # (exit 4), and gh missing from PATH (babysit_util.run_command).
        timed_out(),
        "To get started with GitHub CLI, please run:  gh auth login\n"
        "Alternatively, populate the GH_TOKEN environment variable with a "
        "GitHub API authentication token.",
        RuntimeError("gh executable not found on PATH"),
    )

    def judge(self, fake: FlakyListing) -> tuple[ve.Evidence, list[float]]:
        sleep = ve._listing_sleep
        sleep.reset_mock()
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            evidence = ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, pull())
        return evidence, [c.args[0] for c in sleep.call_args_list]

    def test_a_transient_failure_then_a_listing_reads_the_verdict(self) -> None:
        for error in self.TRANSIENT:
            with self.subTest(str(error)):
                fake = FlakyListing([error])
                evidence, sleeps = self.judge(fake)
                self.assertIsNone(evidence.refusal)
                self.assertEqual(fake.listings(), 2)
                self.assertEqual(sleeps, [2.0])

    def test_a_persistent_transient_failure_refuses_after_three_reads(self) -> None:
        fake = FlakyListing(["gh: Bad Gateway (HTTP 502)"] * 3)
        evidence, sleeps = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn("HTTP 502", evidence.detail or "")
        self.assertEqual(fake.listings(), 3)
        self.assertEqual(sleeps, [2.0, 4.0])

    def timed(self, clock: list[float]) -> FlakyListing:
        """Three 502s, the clock reading `clock` in turn, a 60s gh timeout."""
        fake = FlakyListing(["gh: Bad Gateway (HTTP 502)"] * 3)
        with (
            mock.patch.object(ve, "_listing_clock", side_effect=clock),
            mock.patch.object(ve, "gh_timeout_seconds", return_value=60.0),
        ):
            self.judge(fake)
        return fake

    def test_the_retries_share_one_read_timeout(self) -> None:
        # Deadline 0 + 60; each retry gets what is left after its wait ends.
        fake = self.timed([0.0, 1.0, 3.0, 20.0, 24.0])
        self.assertEqual(fake.timeouts, [None, 60.0 - 3.0, 60.0 - 24.0])

    def test_a_late_sleep_shortens_the_retry_timeout(self) -> None:
        # The 2s sleep returned at 30s: the retry gets 30s, not 57s.
        fake = self.timed([0.0, 1.0, 30.0, 59.0])
        self.assertEqual(fake.timeouts, [None, 30.0])

    def test_no_retry_when_the_sleep_ends_past_the_deadline(self) -> None:
        fake = self.timed([0.0, 1.0, 61.0])
        self.assertEqual(fake.timeouts, [None])
        self.assertEqual(fake.listings(), 1)

    def test_no_retry_once_the_timeout_is_spent(self) -> None:
        fake = self.timed([0.0, 58.5])
        self.assertEqual(fake.timeouts, [None])
        self.assertEqual(fake.listings(), 1)

    def test_any_other_failure_is_not_read_again(self) -> None:
        for error in self.NOT_TRANSIENT:
            with self.subTest(str(error)):
                fake = FlakyListing([error])
                evidence, sleeps = self.judge(fake)
                self.assertEqual(evidence.refusal, "verify:unreadable")
                self.assertEqual(fake.listings(), 1)
                self.assertEqual(sleeps, [])


# --- The --authority pr-merge path ------------------------------------------------


def evidence(
    refusal: str | None, head_fail: tuple[int, str] | None = None
) -> ve.Evidence:
    return ve.Evidence(
        refusal=refusal,
        head=unattended.HEAD,
        verdicts=(),
        ignored=0,
        head_fail=head_fail,
    )


def changed(path: str, additions: int = 1) -> unattended.ChangedFile:
    """A modified regular file in the diff."""
    return unattended.ChangedFile(
        path, None, "modified", additions, 1, True, "100644", "100644"
    )


class LaneRequiresAVerdict(unattended.Unattended):
    """`merge.require-verifier-verdict: true` in the pr-merge lane. The lane
    harness is borrowed, not inherited, so its tests do not run twice."""

    lane = unattended.LaneMode.lane

    def setUp(self) -> None:
        super().setUp()
        # The lane's own setup (LaneMode): its config, no local re-reads.
        self.config = policy.PipelineConfig(
            unattended.BASE, "C2", "pr-merge", unattended.IDENTITY, 200,
            (".github/**",), "c2-mechanical", require_verifier_verdict=True,
        )  # fmt: skip
        self.opt_in_recheck = "not-lane-authored-or-opted-in"
        self.promotion = policy.Promotion(None, "resolver-failed")
        self.kill = []
        self.verdicts: dict[int, ve.Evidence] = {}
        self.read = mock.Mock(
            side_effect=lambda number, head: self.verdicts.get(number, evidence(None))
        )
        patcher = mock.patch.object(ve.Reader, "evidence", side_effect=self._evidence)
        patcher.start()
        self.addCleanup(patcher.stop)
        # The tracker's human-gated role label (`.work-item-tracker.json`).
        self.role_label = mock.Mock(return_value="needs-human")
        patcher = mock.patch.object(postmerge, "_role_label", self.role_label)
        patcher.start()
        self.addCleanup(patcher.stop)

        # Writes whose argv holds one of these fail (HTTP 502).
        self.failing: set[str] = set()

    def _evidence(self, number: int, head: str, pr: Any = None) -> ve.Evidence:
        return self.read(number, head)

    def _capture(self, args: list[str]) -> Any:
        if any(f in a for f in self.failing for a in args):
            self.log.append("failed:" + " ".join(args))
            return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
        return super()._capture(args)

    def escalation_comment(self) -> dict[str, Any]:
        return {
            "id": 90,
            "user": {"login": unattended.IDENTITY, "type": "Bot"},
            "created_at": "2026-10-12T10:00:00Z",
            "body": merge.verify_escalation_body("verify:too-old", unattended.HEAD),
        }

    def test_a_failed_comment_adds_no_label(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:too-old")
        self.failing = {merge.VERIFY_ESCALATION_MARKER}
        _, out = self.lane()
        self.assertFalse(
            any("/labels" in a for w in self.escalation_writes() for a in w)
        )
        self.assertNotIn("escalation", out["unattended"]["writes"])
        self.assertTrue(
            any(
                e.startswith("escalation:")
                for e in out["unattended"]["writes"]["errors"]
            )
        )

    def test_a_failed_label_is_added_on_the_next_run_without_a_second_comment(
        self,
    ) -> None:
        self.verdicts[unattended.PR] = evidence("verify:too-old")
        self.failing = {"/labels"}
        _, out = self.lane()
        self.assertTrue(
            any(
                e.startswith("escalation:")
                for e in out["unattended"]["writes"]["errors"]
            )
        )
        # The next run reads the comment the first one posted.
        self.failing = set()
        self.comments = [self.escalation_comment()]
        _, out = self.lane()
        (label,) = self.escalation_writes()
        self.assertIn("labels[]=needs-human", label)
        self.assertEqual(
            out["unattended"]["writes"]["escalation"],
            {"label": "added", "comment": "unchanged"},
        )

    def test_a_label_differing_only_in_case_is_not_added_again(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:too-old")
        self.pr_labels = [{"name": "Needs-Human"}]
        self.comments = [self.escalation_comment()]
        _, out = self.lane()
        self.assertEqual(self.escalation_writes(), [])
        self.assertEqual(out["unattended"]["writes"]["escalation"]["label"], "present")

    def escalation_writes(self) -> list[list[str]]:
        return [
            c.args[0]
            for c in self.capture.call_args_list
            if any(
                "/labels" in a or merge.VERIFY_ESCALATION_MARKER in a for a in c.args[0]
            )
        ]

    def test_a_needs_human_refusal_labels_the_pr_and_comments_once(self) -> None:
        for refusal in ve.NEEDS_HUMAN:
            with self.subTest(refusal):
                self.verdicts[unattended.PR] = evidence(refusal)
                code, out = self.lane()
                self.assert_no_merge(code)
                # The comment explains the label, so it is written first.
                comment, label = self.escalation_writes()
                self.assertEqual(
                    label[-4:],
                    ["POST", f"repos/owner/repo/issues/{unattended.PR}/labels"]
                    + ["-f", "labels[]=needs-human"],
                )
                self.assertIn("POST", comment)
                body = comment[-1].removeprefix("body=")
                self.assertTrue(body.startswith(merge.VERIFY_ESCALATION_MARKER + "\n"))
                self.assertIn(f"`{refusal}`", body)
                self.assertIn(unattended.HEAD, body)
                self.assertEqual(
                    out["unattended"]["writes"]["escalation"],
                    {"label": "added", "comment": "created"},
                )

    def test_the_gate_reads_verdicts_under_the_configured_cap(self) -> None:
        self.config = dataclasses.replace(self.config, max_verify_fails=5)
        with mock.patch.object(ve, "Reader", wraps=ve.Reader) as built:
            self.lane()
        self.assertTrue(built.call_args_list)
        for call in built.call_args_list:
            self.assertEqual(call.kwargs.get("max_fails"), 5)

    def test_the_label_is_the_trackers_human_gated_role(self) -> None:
        self.role_label.return_value = "status: needs-decision"
        self.verdicts[unattended.PR] = evidence("verify:too-old")
        self.lane()
        self.assertIn("labels[]=status: needs-decision", self.escalation_writes()[-1])

    def test_another_label_does_not_stand_in_for_the_role_label(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:spec-changed")
        self.pr_labels = [{"name": "enhancement"}]
        _, out = self.lane()
        self.assertEqual(out["unattended"]["writes"]["escalation"]["label"], "added")

    def test_a_rerun_writes_no_second_label_or_comment(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:spec-changed")
        self.pr_labels = [{"name": "needs-human"}]
        self.comments = [
            {
                "id": 90,
                "user": {"login": unattended.IDENTITY, "type": "Bot"},
                "created_at": "2026-10-12T10:00:00Z",
                "body": merge.verify_escalation_body(
                    "verify:spec-changed", unattended.HEAD
                ),
            }
        ]
        _, out = self.lane()
        self.assertEqual(self.escalation_writes(), [])
        self.assertEqual(
            out["unattended"]["writes"]["escalation"],
            {"label": "present", "comment": "unchanged"},
        )
        # The escalation's own label is a merge hold too; the reason still
        # names the verifier refusal.
        self.assertEqual(out["unattended"]["reason"], "verify:spec-changed")

    FAIL_RUN = (7, f"pr-verify-{unattended.PR}-{unattended.HEAD}-fail")

    def fail_with_summary(self, summary: str | None | Exception) -> mock.Mock:
        """A `verify:repeated-fail` with a FAIL at the head whose verdict
        records `summary`, or whose record read raises it."""
        self.verdicts[unattended.PR] = evidence("verify:repeated-fail", self.FAIL_RUN)
        answer = (
            {"side_effect": summary}
            if isinstance(summary, Exception)
            else {"return_value": summary}
        )
        patcher = mock.patch.object(ve.Reader, "fail_summary", **answer)
        read = patcher.start()
        self.addCleanup(patcher.stop)
        return read

    def test_a_fail_at_the_head_writes_no_escalation(self) -> None:
        # A fix round answers it (pr-feedback-dispatch.yml); a label would
        # hold that round as awaiting-human.
        self.verdicts[unattended.PR] = evidence("verify:fail", self.FAIL_RUN)
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:fail")
        self.assertEqual(self.escalation_writes(), [])
        self.assertNotIn("escalation", out["unattended"]["writes"])

    def test_a_repeated_fail_escalates_quoting_the_verdict_summary(self) -> None:
        read = self.fail_with_summary("Spec item 2 is unmet.")
        code, out = self.lane()
        self.assert_no_merge(code)
        read.assert_called_once_with(*self.FAIL_RUN, unattended.PR, unattended.HEAD)
        comment, label = self.escalation_writes()
        self.assertIn("labels[]=needs-human", label)
        body = comment[-1].removeprefix("body=")
        self.assertTrue(body.startswith(merge.VERIFY_ESCALATION_MARKER + "\n"))
        self.assertIn("`verify:repeated-fail`", body)
        self.assertIn(unattended.HEAD, body)
        self.assertTrue(body.endswith("```text\nSpec item 2 is unmet.\n```"))
        self.assertEqual(
            out["unattended"]["writes"]["escalation"],
            {"label": "added", "comment": "created"},
        )

    def test_a_repeated_fail_rerun_at_the_same_head_writes_nothing(self) -> None:
        self.fail_with_summary("Spec item 2 is unmet.")
        self.lane()
        comment, _ = self.escalation_writes()
        self.capture.reset_mock()
        # The next run reads the comment and the label the first one wrote.
        self.pr_labels = [{"name": "needs-human"}]
        self.comments = [
            {
                "id": 90,
                "user": {"login": unattended.IDENTITY, "type": "Bot"},
                "created_at": "2026-10-12T10:00:00Z",
                "body": comment[-1].removeprefix("body="),
            }
        ]
        _, out = self.lane()
        self.assertEqual(self.escalation_writes(), [])
        self.assertEqual(
            out["unattended"]["writes"]["escalation"],
            {"label": "present", "comment": "unchanged"},
        )

    def test_the_quoted_summary_stays_inside_its_fence_and_is_cut(self) -> None:
        summary = "a```b\r\n@someone\x1b" + "x" * 1500
        body = merge.verify_escalation_body(
            "verify:repeated-fail", unattended.HEAD, summary
        )
        quoted = body.split("```text\n", 1)[1]
        # 1500 characters kept: the 15 of "a'''b\n@someone?" and 1485 x's.
        self.assertEqual(quoted, "a'''b\n@someone?" + "x" * 1485 + " [cut]\n```")

    def test_a_lone_surrogate_in_the_summary_still_posts(self) -> None:
        body = merge.verify_escalation_body(
            "verify:repeated-fail", unattended.HEAD, "a\ud800b"
        )
        self.assertTrue(body.endswith("```text\na?b\n```"))
        body.encode("utf-8")

    def assert_escalates_without_a_quote(self, summary: Any) -> None:
        self.fail_with_summary(summary)
        _, out = self.lane()
        comment, _ = self.escalation_writes()
        body = comment[-1].removeprefix("body=")
        self.assertIn("`verify:repeated-fail`", body)
        self.assertNotIn("```", body)
        self.assertEqual(
            out["unattended"]["writes"]["escalation"]["comment"], "created"
        )

    def test_a_repeated_fail_with_no_summary_to_quote_still_escalates(self) -> None:
        self.assert_escalates_without_a_quote(None)

    def test_a_repeated_fail_whose_record_cannot_be_read_still_escalates(self) -> None:
        self.assert_escalates_without_a_quote(
            ve.SummaryUnreadable("gh: boom (HTTP 502)")
        )

    def test_a_failed_read_keeps_the_quote_a_same_head_comment_carries(self) -> None:
        quoted = merge.verify_escalation_body(
            "verify:repeated-fail", unattended.HEAD, "Spec item 2 is unmet."
        )
        self.fail_with_summary(ve.SummaryUnreadable("gh: boom (HTTP 502)"))
        self.pr_labels = [{"name": "needs-human"}]
        self.comments = [
            {
                "id": 90,
                "user": {"login": unattended.IDENTITY, "type": "Bot"},
                "created_at": "2026-10-12T10:00:00Z",
                "body": quoted,
            }
        ]
        _, out = self.lane()
        self.assertEqual(self.escalation_writes(), [])
        self.assertEqual(
            out["unattended"]["writes"]["escalation"],
            {"label": "present", "comment": "unchanged"},
        )

    def test_a_failed_read_still_rewrites_another_heads_comment(self) -> None:
        self.fail_with_summary(ve.SummaryUnreadable("gh: boom (HTTP 502)"))
        self.comments = [
            {
                "id": 90,
                "user": {"login": unattended.IDENTITY, "type": "Bot"},
                "created_at": "2026-10-12T10:00:00Z",
                "body": merge.verify_escalation_body(
                    "verify:repeated-fail", "c" * 40, "Old head's reason."
                ),
            }
        ]
        _, out = self.lane()
        self.assertEqual(
            out["unattended"]["writes"]["escalation"]["comment"], "updated"
        )
        # The old head's reason stays, under the head it was given at.
        (comment, _) = self.escalation_writes()
        self.assertTrue(
            comment[-1].endswith(
                f"fail verdict at `{'c' * 40}`, as it wrote it:\n\n"
                "```text\nOld head's reason.\n```"
            )
        )

    def test_report_only_reports_a_needs_human_refusal_and_writes_nothing(self) -> None:
        self.config = dataclasses.replace(self.config, report_only=True)
        self.verdicts[unattended.PR] = evidence("verify:untrusted-spec")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertIs(out["unattended"]["verify"]["needsHuman"], True)
        self.capture.assert_not_called()
        self.assertNotIn("writes", out["unattended"])

    def test_a_refusal_that_needs_no_human_is_not_escalated(self) -> None:
        for refusal in ("verify:missing", "verify:unreadable"):
            with self.subTest(refusal):
                self.verdicts[unattended.PR] = evidence(refusal)
                _, out = self.lane()
                self.assertEqual(self.escalation_writes(), [])
                self.assertNotIn("escalation", out["unattended"]["writes"])

    def test_a_pass_at_the_head_enqueues(self) -> None:
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.read.assert_called_once_with(unattended.PR, unattended.HEAD)
        self.assertIn("verify", out["unattended"])

    def saved_listing(self) -> mock.Mock:
        """The reader judged on the run's saved listing; returns `refresh`."""
        patcher = mock.patch.object(ve.Reader, "saved", new=True)
        patcher.start()
        self.addCleanup(patcher.stop)
        patcher = mock.patch.object(ve.Reader, "refresh")
        refresh = patcher.start()
        self.addCleanup(patcher.stop)
        return refresh

    def test_an_allow_on_the_saved_listing_is_judged_again_on_its_own(self) -> None:
        # A FAIL uploaded after the run saved its listing still refuses.
        refresh = self.saved_listing()
        self.read.side_effect = [evidence(None), evidence("verify:fail")]
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:fail")
        refresh.assert_called_once_with()
        self.assertEqual(self.read.call_count, 2)

    def test_a_candidate_refused_otherwise_does_not_list_again(self) -> None:
        # Already refused, it is not enqueued: an allow on the saved listing
        # decides nothing, so it pages nothing.
        refresh = self.saved_listing()
        self.lanes = unattended.UNBOUND
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertTrue(out["unattended"]["reason"].startswith("risk:"))
        refresh.assert_not_called()
        self.read.assert_called_once_with(unattended.PR, unattended.HEAD)

    def test_a_refusal_on_the_saved_listing_stands_without_a_listing(self) -> None:
        refresh = self.saved_listing()
        self.verdicts[unattended.PR] = evidence("verify:missing")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:missing")
        refresh.assert_not_called()
        self.read.assert_called_once_with(unattended.PR, unattended.HEAD)

    def test_a_fail_refuses_and_dequeues_its_own_entry(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:fail")
        self.queued = [unattended.PR]
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:fail")
        self.assertIn(f"dequeue:[{unattended.PR}]", self.log)
        # Its own entry is decided once, not read again in the queue loop.
        self.assertEqual(self.read.call_count, 1)

    def test_a_missing_verdict_refuses(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:missing")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:missing")

    def test_an_earlier_fail_refuses_without_a_human(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:earlier-fail")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:earlier-fail")
        self.assertIs(out["unattended"]["verify"]["needsHuman"], False)
        self.assertEqual(self.escalation_writes(), [])

    def test_a_queued_entry_without_a_pass_at_its_head_is_dequeued(self) -> None:
        other = unattended.PR + 1
        self.queued = [unattended.PR, other]
        self.verdicts[other] = evidence("verify:missing")
        _, out = self.lane()
        self.assertIn(f"dequeue:[{other}]", self.log)
        self.assertEqual(
            out["unattended"]["writes"]["holds"], {str(other): "verify:missing"}
        )
        # The queued entry is judged at the head its pull request reads now.
        self.read.assert_any_call(other, self.scored_head)

    def test_a_crash_on_one_queued_entry_refuses_it_and_the_sweep_goes_on(self) -> None:
        crash, after = unattended.PR + 1, unattended.PR + 2
        self.queued = [crash, after]
        self.verdicts[after] = evidence("verify:missing")

        def read(number: int, head: str) -> ve.Evidence:
            if number == crash:
                raise KeyError("unexpected")
            return self.verdicts.get(number, evidence(None))

        self.read.side_effect = read
        _, out = self.lane()
        self.assertEqual(
            out["unattended"]["writes"]["holds"],
            {str(crash): "verify:unreadable", str(after): "verify:missing"},
        )
        self.assertIn(f"dequeue:[{crash}, {after}]", self.log)

    def test_an_ineligible_candidate_still_dequeues_an_unverified_entry(self) -> None:
        other = unattended.PR + 1
        self.lane_eligible = policy.Eligibility(False, "linked-issues:0")
        self.queued = [other]
        self.verdicts[other] = evidence("verify:missing")
        _, out = self.lane()
        self.assertEqual(
            out["unattended"]["writes"]["holds"], {str(other): "verify:missing"}
        )
        self.assertIn(f"dequeue:[{other}]", self.log)
        self.read.assert_called_once_with(other, self.scored_head)

    def test_a_verifier_refusal_is_judged_before_the_diff(self) -> None:
        # The refusal stands whatever the diff scores, so neither the lane
        # evidence nor the score is read, and the reason is the verifier's.
        self.verdicts[unattended.PR] = evidence("verify:fail")
        self.lanes = unattended.UNBOUND
        self.queued = [unattended.PR]
        self._lane_evidence = mock.Mock(return_value=(self.lanes, self.comments))
        with mock.patch.object(merge.babysit_risk, "score") as score:
            code, out = self.lane()
        self.assert_no_merge(code)
        self._lane_evidence.assert_not_called()
        score.assert_not_called()
        self.assertEqual(out["unattended"]["reason"], "verify:fail")
        self.assertNotIn("risk", out["unattended"])
        self.assertIn(f"dequeue:[{unattended.PR}]", self.log)

    def test_a_risk_refusal_is_the_reason_when_the_verifier_passes(self) -> None:
        self.lanes = unattended.UNBOUND
        _, out = self.lane()
        self.assertTrue(out["unattended"]["reason"].startswith("risk:"))

    def test_dependabot_needs_no_verdict(self) -> None:
        self.lane_eligible = policy.Eligibility(False, "dependency-manager")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "ineligible:dependency-manager")
        self.read.assert_not_called()

    def test_a_real_dependabot_pull_request_is_refused_before_the_reader(self) -> None:
        # The real lane eligibility over a dependabot[bot]-authored pull
        # request (babysit_merge_policy._foreign_refusal).
        self.lane_eligible = None
        node = {
            "number": unattended.PR,
            "isCrossRepository": False,
            "headRepositoryOwner": {"login": "owner"},
            "author": {"__typename": "Bot", "login": "dependabot"},
        }
        graphql = mock.Mock(return_value={"repository": {"pullRequest": node}})
        with mock.patch.object(policy, "_graphql", graphql):
            code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "ineligible:dependency-manager")
        self.assertIs(graphql.call_args.args[0], policy.ELIGIBILITY)
        self.read.assert_not_called()

    def test_the_lane_without_the_key_refuses(self) -> None:
        # Design 3: the verdict is the lane's only merge criterion.
        self.config = dataclasses.replace(self.config, require_verifier_verdict=False)
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verifier-verdict-not-required")
        self.read.assert_not_called()

    def test_a_lane_pr_touching_the_merge_gate_merges_on_a_pass(self) -> None:
        # Owner decision Q624: no denied path, no HIGH floor, no size caps and
        # no C2 contradictions in the lane by default; the verdict still gates.
        self.config = dataclasses.replace(
            self.config, denied_paths=(), max_changed_lines=None
        )
        self.unlabeled_lane_pr(real_denied_paths=True)
        gate = "plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py"
        paths = (gate, ".github/workflows/x.yml", *(f"lib/f{i}.sh" for i in range(8)))
        # The workflow's patch adds no cost line, so the cost hold passes it.
        self.files = (
            tuple(
                dataclasses.replace(changed(path, 300), patch="@@ -1 +1 @@\n-a\n+b")
                for path in paths
            ),
            True,
        )
        # The cost hold reads the workflow's text: it starts no model leg.
        reader = mock.patch.object(policy, "_file_at", return_value="jobs: {}\n")
        reader.start()
        self.addCleanup(reader.stop)
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(out["unattended"]["risk"]["score"], "LOW")
        self.assertEqual(self.log, ["pin", f"enqueue:{unattended.HEAD}:merge_queue"])
        # The verdict still decides: a missing one refuses the same pull request.
        self.verdicts[unattended.PR] = evidence("verify:missing")
        self.log = []
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:missing")

    def test_the_lane_switches_turned_on_restore_the_refusals(self) -> None:
        self.config = dataclasses.replace(
            self.config, high_path_floor=True, max_changed_files=8,
            c2_contradictions=True,
        )  # fmt: skip
        self.files = ((changed(".gitmodules"),), True)
        _, out = self.lane()
        self.assertEqual(out["unattended"]["reason"], "risk:HIGH")

    def test_the_lane_scores_a_floor_path_from_the_config_high(self) -> None:
        self.config = dataclasses.replace(self.config, high_path_floor=True)
        self.files = ((changed(".gitmodules"),), True)
        _, out = self.lane()
        self.assertEqual(out["unattended"]["reason"], "risk:HIGH")
        codes = [r["code"] for r in out["unattended"]["risk"]["reasons"]]
        self.assertEqual(codes, ["high-path:**/.gitmodules"])

    def unlabeled_lane_pr(self, real_denied_paths: bool = False) -> None:
        """The real lane eligibility over a lanes-App pull request whose one
        closing issue carries no `work-class:` label."""
        self.lane_eligible = None
        issue = {
            "number": 41,
            "repository": {"nameWithOwner": "owner/repo"},
            "labels": {"totalCount": 0, "nodes": []},
        }
        node = {
            "number": unattended.PR,
            "isCrossRepository": False,
            "headRepositoryOwner": {"login": "owner"},
            "author": {"__typename": "Bot", "login": "agent-lanes"},
            "closingIssuesReferences": {"totalCount": 1, "nodes": [issue]},
        }
        reads = [
            ("_graphql", {"repository": {"pullRequest": node}}),
            ("_base_refusal", None),
        ]
        if not real_denied_paths:
            reads.append(("_denied_path_refusal", None))
        for name, answer in reads:
            patcher = mock.patch.object(policy, name, return_value=answer)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_an_unlabeled_issue_merges_on_a_pass_as_c2(self) -> None:
        self.unlabeled_lane_pr()
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(out["unattended"]["eligibility"]["workClass"], "C2")
        self.assertEqual(out["unattended"]["risk"]["score"], "LOW")

    def test_a_missing_verdict_refuses_even_at_low_risk(self) -> None:
        self.unlabeled_lane_pr()
        self.verdicts[unattended.PR] = evidence("verify:missing")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertNotIn("risk", out["unattended"])
        self.assertEqual(out["unattended"]["reason"], "verify:missing")


class LocalBabysitReadsNoVerdict(unattended.Unattended):
    def test_the_key_does_not_reach_the_local_path(self) -> None:
        self.config = dataclasses.replace(self.config, require_verifier_verdict=True)
        with mock.patch.object(ve.Reader, "evidence") as read:
            code, out = self.run_main()
        self.assertEqual(code, 0, out["blockers"])
        read.assert_not_called()

    def test_the_lane_switches_do_not_reach_the_local_path(self) -> None:
        # Q624 turns the floor and caps off for the pr-merge lane only.
        self.config = dataclasses.replace(
            self.config, high_path_floor=False, max_changed_files=None,
            c2_contradictions=False,
        )  # fmt: skip
        self.files = ((changed(".gitmodules"),), True)
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "risk:HIGH")

    def test_the_local_floor_holds_whatever_the_switch_says(self) -> None:
        self.files = ((changed(".gitmodules"),), True)
        for on in (False, True):
            with self.subTest(high_path_floor=on):
                self.config = dataclasses.replace(self.config, high_path_floor=on)
                _, out = self.run_main()
                self.assertEqual(out["unattended"]["risk"]["score"], "HIGH")


class TheConfigKey(unittest.TestCase):
    def config(self, value: str | None) -> policy.PipelineConfig:
        line = "" if value is None else f"  require-verifier-verdict: {value}\n"
        text = (
            "version: 1\nmerge:\n  rung: C2\n  authority: pr-merge\n"
            "  agent-identity: agent-lanes[bot]\n" + line
        )
        with mock.patch.object(policy, "_file_at", side_effect=[None, text]):
            return policy.read_config_at(REPO, "e" * 40)

    def test_absent_is_off_and_true_is_on(self) -> None:
        self.assertFalse(self.config(None).require_verifier_verdict)
        self.assertFalse(self.config("false").require_verifier_verdict)
        self.assertTrue(self.config("true").require_verifier_verdict)

    def test_any_other_value_requires_a_verdict(self) -> None:
        config = self.config("maybe")
        self.assertTrue(config.require_verifier_verdict)
        self.assertTrue(any("require-verifier-verdict" in n for n in config.notes))


class TheSweepKeepsTheListingBound(unattended.Unattended):
    """A queued entry another candidate kept is skipped only while the
    listing its verdict was judged on is within the bound."""

    def setUp(self) -> None:
        super().setUp()
        self.config = policy.PipelineConfig(
            unattended.BASE, "C2", "pr-merge", unattended.IDENTITY, 200,
            (".github/**",), "c2-mechanical", require_verifier_verdict=True,
        )  # fmt: skip
        self.opt_in_recheck = "not-lane-authored-or-opted-in"
        self.promotion = policy.Promotion(None, "resolver-failed")
        self.kill = []
        self.flight = policy.InFlight(False, "identity-entry-queued:#5")
        self.queued = [unattended.PR, 5]
        self.clock = datetime(2026, 10, 18, 12, 0, tzinfo=UTC)
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = str(pathlib.Path(tmp.name, "run.json"))
        self.reads: list[int] = []
        listed = self.clock - timedelta(seconds=90)
        for patcher in (
            mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": path}),
            mock.patch.object(ve.run_cache, "now", side_effect=lambda: self.clock),
            # The verdict is judged on a listing begun 90 s before the run.
            mock.patch.object(
                ve.Reader,
                "evidence",
                side_effect=lambda n, head, pr=None: (
                    self.reads.append(n) or ve.run_cache.note(listed) or evidence(None)
                ),
            ),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_the_skip_ends_when_the_judged_listing_passes_the_bound(self) -> None:
        for seconds in (0, 29, 31):
            self.clock = datetime(2026, 10, 18, 12, 0, seconds, tzinfo=UTC)
            code, _ = unattended.LaneMode.lane(self)
            self.assert_no_merge(code)
        # Judged at 12:00:00 on a listing from 11:58:30: skipped at :29, not :31.
        self.assertEqual(self.reads.count(5), 2)


# --- The head-ref digest in a verdict's name ------------------------------------

# The first 16 hex digits of `printf %s <ref> | sha256sum`.
DIGEST_X = "79b4cc554b80dca6"  # feat/x, PR 41's head branch
DIGEST_OTHER = "3b0035df584451e9"  # feat/other
TIE = "9" * 40  # a head of PR 97


def downloads(fake: FakeGitHub) -> int:
    return sum(c[:2] == ["run", "download"] for c in fake.calls)


class AnUntiedFailIsTiedByItsNamedHeadRef(unittest.TestCase):
    """pr-verify names a verdict with a digest of the head branch it records,
    so an untied FAIL ties to this pull request by name, without a download,
    exactly when the digest is its head branch's. The run record authenticates
    the name (`_origin`), as it does the verdict.json; a name from any other
    run is ignored like its contents. A name with no digest, uploaded before
    the digest was added, is read as before."""

    @staticmethod
    def heads(
        *, digests: bool = True, runs: dict[int, Any] | None = None
    ) -> FakeGitHub:
        """A pass at the head (run 1); PR 98's FAIL recording feat/other (run
        3) and PR 97's recording feat/x (run 4), both before the pass; and a
        FAIL at an earlier head of PR 41 (run 2)."""
        suffix = (lambda d: f"-{d}") if digests else (lambda d: "")
        fake = passing(
            artifact(named(EARLIER, "fail"), 2),
            artifact(named(UNRELATED, "fail", 98) + suffix(DIGEST_OTHER), 3),
            artifact(named(TIE, "fail", 97) + suffix(DIGEST_X), 4),
            runs={
                2: judged(2, OLDER_START),
                3: judged(3, OLDER_START),
                4: judged(4, OLDER_START),
                **(runs or {}),
            },
        )
        fake.records[named(UNRELATED, "fail", 98) + suffix(DIGEST_OTHER)] = record(
            98, UNRELATED, verdict="fail", head_ref="feat/other"
        )
        fake.records[named(TIE, "fail", 97) + suffix(DIGEST_X)] = record(
            97, TIE, verdict="fail", head_ref="feat/x"
        )
        fake.diffs[TIE] = change("tie")
        return fake

    def test_both_formats_decide_alike_and_the_named_one_downloads_less(self) -> None:
        # Before (no digest): the pass and both untied records, 3 downloads.
        # After: the pass only.
        for digests, count in ((False, 3), (True, 1)):
            with self.subTest(digests=digests):
                fake = self.heads(digests=digests)
                evidence = read(fake)
                self.assertIsNone(evidence.refusal)
                self.assertEqual(
                    evidence.report()["earlierFails"], sorted([EARLIER, TIE])
                )
                self.assertEqual(downloads(fake), count)

    def test_a_tie_after_the_pass_holds_on_the_name_alone(self) -> None:
        fake = self.heads(runs={4: judged(4, "2026-10-15T00:00:01Z")})
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")
        self.assertEqual(downloads(fake), 0)

    def test_a_digest_of_another_branch_unties_without_a_download(self) -> None:
        fake = self.heads()
        fake.artifacts.pop()  # PR 97's tie
        evidence = read(fake)
        self.assertEqual(evidence.report()["earlierFails"], [EARLIER])
        self.assertEqual(downloads(fake), 1)  # the pass

    def test_a_pull_request_with_no_head_ref_ties_nothing_by_name(self) -> None:
        # e3b0c44298fc1c14: the first 16 hex digits of `printf '' | sha256sum`.
        fake = FakeGitHub(
            [artifact(named(TIE, "fail", 97) + "-e3b0c44298fc1c14", 4)], {4: run(4)}
        )
        self.assertEqual(
            read(fake, pull(head={"ref": "", "sha": HEAD})).refusal, "verify:missing"
        )

    def test_a_name_from_a_run_not_of_verifier_origin_is_never_trusted(self) -> None:
        # Each forgery names PR 41's head branch: trusted, it would hold.
        for label, overrides in UnauthenticatedArtifactsAreIgnored.FORGERIES.items():
            with self.subTest(label):
                fake = FakeGitHub(
                    [artifact(named(TIE, "fail", 97) + f"-{DIGEST_X}", 4)],
                    {4: run(4, **overrides)},
                )
                evidence = read(fake)
                self.assertEqual(evidence.refusal, "verify:missing")
                self.assertEqual(evidence.report()["earlierFails"], [])
                self.assertEqual(downloads(fake), 0)
        # The same name from a run of verifier origin holds.
        fake = FakeGitHub(
            [artifact(named(TIE, "fail", 97) + f"-{DIGEST_X}", 4)], {4: run(4)}
        )
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_any_branch_name_ties_by_its_digest(self) -> None:
        # The first 16 hex digits of `printf %s <ref> | sha256sum`.
        for ref, digest in (
            ("feat/a+b", "a27da2afd9962004"),
            ("fix/\u00e9", "8c8a071ad0e51f5e"),
        ):
            with self.subTest(ref):
                fake = FakeGitHub(
                    [artifact(named(TIE, "fail", 97) + f"-{digest}", 4)], {4: run(4)}
                )
                pr = pull(head={"ref": ref, "sha": HEAD})
                self.assertEqual(read(fake, pr).refusal, "verify:earlier-fail")
                self.assertEqual(downloads(fake), 0)

    def test_a_malformed_digest_is_no_verdict(self) -> None:
        for suffix in ("-79B4CC554B80DCA6", "-79b4cc554b80dca", "-79b4cc554b80dca6x"):
            with self.subTest(suffix):
                fake = FakeGitHub(
                    [artifact(named(TIE, "fail", 97) + suffix, 4)], {4: run(4)}
                )
                self.assertEqual(read(fake).refusal, "verify:missing")


if __name__ == "__main__":
    unittest.main()

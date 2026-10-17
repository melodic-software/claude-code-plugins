"""The pr-merge lane's reader of verifier verdicts (`babysit_verify_evidence`).

Expected values come from issue #7702 (Scope, Done when) and the review round
on its pull request: an artifact named `pr-verify-<pr>-<sha>-<verdict>` counts
only through a run of `.github/workflows/pr-verify.yml` on main of this
repository; a FAIL counts whatever the run's conclusion and under any pull
request number, a PASS only from a completed success at this pull request's
head; a FAIL at another head of the pull request goes to a human; an
unreadable FAIL blocks; a pull request older than 80 days goes to a human; a
pass whose linked issues no trusted human other than the author wrote does not
count; a Dependabot pull request needs no verdict.

The artifact and run shapes follow responses recorded from
`GET /repos/{owner}/{repo}/actions/artifacts` and `GET .../actions/runs/{id}`
for a `workflow_run` run, with identifying details changed. Network is stubbed
at the `gh_capture` seam the reader shares with the post-merge check.
"""

from __future__ import annotations

import dataclasses
import json
import pathlib
import subprocess
import sys
import unittest
from datetime import UTC, datetime
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

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
}


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


def named(sha: str, verdict: str, number: int = PR) -> str:
    return f"pr-verify-{number}-{sha}-{verdict}"


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
        self.actors: Any = {"version": 1, "actors": [MAINTAINER, LANES]}
        self.calls: list[list[str]] = []
        self.fail: set[str] = set()
        # The PR's closing issues now: (number, repository).
        self.closing: list[tuple[int, str]] = [(7, REPO)]
        self.closing_total: int | None = None

    def __call__(self, args: list[str], **_: Any) -> subprocess.CompletedProcess[str]:
        self.calls.append(args)

        def ok(payload: Any) -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(args, 0, json.dumps(payload), "")

        def missing() -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(args, 1, "", "gh: Not Found (HTTP 404)")

        if args[:2] == ["api", "graphql"]:
            if "graphql" in self.fail:
                return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
            nodes = [
                {"number": n, "repository": {"nameWithOwner": repo}}
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
            return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
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

    def test_a_fail_blocks(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 1)], {1: run(1)})
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertFalse(evidence.needs_human)

    def test_a_fail_beside_a_pass_at_the_same_head_blocks(self) -> None:
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_no_verdict_is_missing(self) -> None:
        self.assertEqual(read(FakeGitHub([], {})).refusal, "verify:missing")


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
        fake = passing(artifact(named(IN_PR, "fail", 99), 2), runs={2: run(2)})
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertTrue(evidence.needs_human)

    def test_a_fail_recording_this_head_branch_under_another_number(self) -> None:
        name = named(UNRELATED, "fail", 99)
        fake = passing(artifact(name, 2), runs={2: run(2)})
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
    def test_a_fail_at_an_earlier_head_blocks_a_pass_at_the_current_one(self) -> None:
        fake = passing(artifact(named(EARLIER, "fail"), 2), runs={2: run(2)})
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertTrue(evidence.needs_human)
        self.assertEqual(evidence.report()["earlierFails"], [EARLIER])

    def test_a_fail_at_the_current_head_wins_over_an_earlier_fail(self) -> None:
        fake = FakeGitHub(
            [artifact(named(EARLIER, "fail"), 1), artifact(named(HEAD, "fail"), 2)],
            {1: run(1), 2: run(2)},
        )
        self.assertEqual(read(fake).refusal, "verify:fail")


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

    def test_the_pr_authors_own_issue_does_not(self) -> None:
        evidence = self.with_issues([TRUSTED_ISSUE], user={"login": "Maintainer"})
        self.assertEqual(evidence.refusal, "verify:untrusted-spec")

    def test_one_trusted_issue_among_others_allows(self) -> None:
        bot = {**TRUSTED_ISSUE, "number": 8, "author_type": "Bot", "author_id": 200}
        self.assertIsNone(self.with_issues([bot, TRUSTED_ISSUE]).refusal)

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

    def test_a_record_whose_issues_are_not_a_list_refuses(self) -> None:
        fake = passing()
        fake.records[named(HEAD, "pass")] = record(linked_issues=None)
        self.assertEqual(read(fake).refusal, "verify:unreadable")


class TheListingIsReadOncePerReader(unittest.TestCase):
    def test_two_reads_share_one_listing(self) -> None:
        fake = passing()
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            reader = ve.Reader(REPO, "main", now=NOW)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
        listings = [c for c in fake.calls if any("actions/artifacts" in a for a in c)]
        self.assertEqual(len(listings), 1)


# --- The --authority pr-merge path ------------------------------------------------


def evidence(refusal: str | None) -> ve.Evidence:
    return ve.Evidence(refusal=refusal, head=unattended.HEAD, verdicts=(), ignored=0)


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

    def _evidence(self, number: int, head: str, pr: Any = None) -> ve.Evidence:
        return self.read(number, head)

    def test_a_pass_at_the_head_enqueues(self) -> None:
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.read.assert_called_once_with(unattended.PR, unattended.HEAD)
        self.assertIn("verify", out["unattended"])

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

    def test_an_earlier_fail_refuses_for_a_human(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:earlier-fail")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:earlier-fail")
        self.assertIs(out["unattended"]["verify"]["needsHuman"], True)

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

    def test_a_risk_refusal_stays_the_reason(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:fail")
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

    def test_the_lane_without_the_key_reads_no_verdict(self) -> None:
        self.config = dataclasses.replace(self.config, require_verifier_verdict=False)
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.read.assert_not_called()


class LocalBabysitReadsNoVerdict(unattended.Unattended):
    def test_the_key_does_not_reach_the_local_path(self) -> None:
        self.config = dataclasses.replace(self.config, require_verifier_verdict=True)
        with mock.patch.object(ve.Reader, "evidence") as read:
            code, out = self.run_main()
        self.assertEqual(code, 0, out["blockers"])
        read.assert_not_called()


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


if __name__ == "__main__":
    unittest.main()

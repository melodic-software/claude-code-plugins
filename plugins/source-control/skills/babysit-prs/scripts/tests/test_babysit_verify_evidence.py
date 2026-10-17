"""The pr-merge lane's reader of verifier verdicts (`babysit_verify_evidence`).

Expected values come from issue #7702 (Scope, Done when): only an artifact
named `pr-verify-<pr>-<sha>-<pass|pass-notes|fail>` whose run is
`.github/workflows/pr-verify.yml`, event `workflow_run`, branch main,
conclusion success, in this repository, with a run head on main, counts, and
only when its named SHA is the PR's current head; a FAIL blocks, a verdict for
another SHA does not count, a FAIL on any earlier head goes to a human, and a
Dependabot pull request needs no verdict.

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
EARLIER = "b" * 40
MAIN_SHA = "c" * 40
OFF_MAIN = "d" * 40
WORKFLOW = ".github/workflows/pr-verify.yml"


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


class FakeGitHub:
    """Answers the three reads: the artifact listing (paginated), a run, and a
    compare of a run head against the branch."""

    def __init__(self, artifacts: list[dict[str, Any]], runs: dict[int, Any]):
        self.artifacts = artifacts
        self.runs = runs
        self.on_main = {MAIN_SHA}
        self.calls: list[list[str]] = []
        self.fail_listing = False

    def __call__(self, args: list[str], **_: Any) -> subprocess.CompletedProcess[str]:
        self.calls.append(args)
        path = args[1]

        def ok(payload: Any) -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(args, 0, json.dumps(payload), "")

        if path == f"repos/{REPO}/actions/artifacts?per_page=100":
            if self.fail_listing:
                return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
            pages = [
                self.artifacts[i : i + 2] for i in range(0, len(self.artifacts), 2)
            ]
            return ok(
                [{"total_count": len(self.artifacts), "artifacts": p} for p in pages]
                or [{"total_count": 0, "artifacts": []}]
            )
        prefix = f"repos/{REPO}/actions/runs/"
        if path.startswith(prefix):
            run_id = int(path[len(prefix) :])
            if run_id not in self.runs:
                return subprocess.CompletedProcess(
                    args, 1, "", "gh: Not Found (HTTP 404)"
                )
            return ok(self.runs[run_id])
        compare = f"repos/{REPO}/compare/"
        if path.startswith(compare):
            sha = path[len(compare) :].split("...")[0]
            return ok({"status": "ahead" if sha in self.on_main else "diverged"})
        raise AssertionError(f"unexpected gh call: {args}")


def read(fake: FakeGitHub, head: str = HEAD) -> ve.Evidence:
    with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
        return ve.Reader(REPO, "main").evidence(PR, head)


def named(sha: str, verdict: str, number: int = PR) -> str:
    return f"pr-verify-{number}-{sha}-{verdict}"


class VerdictAtTheCurrentHead(unittest.TestCase):
    def test_a_pass_allows(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "pass"), 1)], {1: run(1)})
        evidence = read(fake)
        self.assertIsNone(evidence.refusal)
        self.assertFalse(evidence.needs_human)

    def test_a_pass_with_notes_allows(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "pass-notes"), 1)], {1: run(1)})
        self.assertIsNone(read(fake).refusal)

    def test_a_fail_blocks(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 1)], {1: run(1)})
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertFalse(evidence.needs_human)

    def test_a_fail_beside_a_pass_at_the_same_head_blocks(self) -> None:
        fake = FakeGitHub(
            [artifact(named(HEAD, "pass"), 1), artifact(named(HEAD, "fail"), 2)],
            {1: run(1), 2: run(2)},
        )
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_no_verdict_is_missing(self) -> None:
        self.assertEqual(read(FakeGitHub([], {})).refusal, "verify:missing")


class AVerdictForAnotherShaDoesNotCount(unittest.TestCase):
    def test_a_pass_at_an_earlier_head_is_missing_at_the_current_one(self) -> None:
        fake = FakeGitHub([artifact(named(EARLIER, "pass"), 1)], {1: run(1)})
        self.assertEqual(read(fake).refusal, "verify:missing")

    def test_another_prs_pass_at_this_head_does_not_count(self) -> None:
        # PR 4 and PR 41 share the prefix `pr-verify-4`; the name is parsed.
        fake = FakeGitHub(
            [
                artifact(named(HEAD, "pass", 4), 1),
                artifact(named(HEAD, "pass", 411), 2),
            ],
            {1: run(1), 2: run(2)},
        )
        self.assertEqual(read(fake).refusal, "verify:missing")


class AnEarlierFailGoesToAHuman(unittest.TestCase):
    def test_a_fail_at_an_earlier_head_blocks_a_pass_at_the_current_one(self) -> None:
        fake = FakeGitHub(
            [artifact(named(EARLIER, "fail"), 1), artifact(named(HEAD, "pass"), 2)],
            {1: run(1), 2: run(2)},
        )
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


class UnauthenticatedArtifactsAreIgnored(unittest.TestCase):
    """Each case is a forged pass at the current head beside nothing else, so
    it reads `verify:missing`; the same forgery as a FAIL on an earlier head
    beside a real pass must not route to a human."""

    FORGERIES = {
        "another workflow": {"path": ".github/workflows/pr-require-checks.yml"},
        "a pull_request run": {"event": "pull_request"},
        "a pull_request_target run": {"event": "pull_request_target"},
        "a branch other than main": {"head_branch": "feat/x"},
        "a failed run": {"conclusion": "failure"},
        "a run still going": {"status": "in_progress", "conclusion": None},
        "another repository": {"repository": {"full_name": "someone/fork"}},
        "a fork head": {"head_repository": {"full_name": "someone/fork"}},
        "a run head off main": {"head_sha": OFF_MAIN},
    }

    def test_each_forgery_counts_neither_as_pass_nor_fail(self) -> None:
        for label, overrides in self.FORGERIES.items():
            with self.subTest(label):
                forged_pass = FakeGitHub(
                    [artifact(named(HEAD, "pass"), 9)], {9: run(9, **overrides)}
                )
                self.assertEqual(read(forged_pass).refusal, "verify:missing")
                forged_fail = FakeGitHub(
                    [
                        artifact(named(EARLIER, "fail"), 9),
                        artifact(named(HEAD, "pass"), 2),
                    ],
                    {9: run(9, **overrides), 2: run(2)},
                )
                evidence = read(forged_fail)
                self.assertIsNone(evidence.refusal)
                self.assertEqual(evidence.report()["ignored"], 1)

    def test_an_expired_artifact_is_skipped(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "pass"), 1, expired=True)], {1: run(1)})
        self.assertEqual(read(fake).refusal, "verify:missing")
        self.assertNotIn(["api", f"repos/{REPO}/actions/runs/1"], fake.calls)

    def test_a_name_that_does_not_parse_is_ignored(self) -> None:
        for name in (
            f"pr-verify-{PR}-{HEAD}-PASS",
            f"pr-verify-{PR}-{HEAD[:39]}-pass",
            f"pr-verify-{PR}-{HEAD}-pass-extra",
        ):
            with self.subTest(name):
                fake = FakeGitHub([artifact(name, 1)], {1: run(1)})
                self.assertEqual(read(fake).refusal, "verify:missing")

    def test_a_run_that_cannot_be_read_is_ignored(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "pass"), 7)], {})
        self.assertEqual(read(fake).refusal, "verify:missing")

    def test_an_unreadable_listing_refuses(self) -> None:
        fake = FakeGitHub([], {})
        fake.fail_listing = True
        self.assertEqual(read(fake).refusal, "verify:unreadable")


class TheListingIsReadOncePerReader(unittest.TestCase):
    def test_two_pull_requests_share_one_listing(self) -> None:
        fake = FakeGitHub(
            [artifact(named(HEAD, "pass"), 1), artifact(named(EARLIER, "pass", 7), 2)],
            {1: run(1), 2: run(2)},
        )
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            reader = ve.Reader(REPO, "main")
            self.assertIsNone(reader.evidence(PR, HEAD).refusal)
            self.assertIsNone(reader.evidence(7, EARLIER).refusal)
        listings = [c for c in fake.calls if "actions/artifacts" in c[1]]
        self.assertEqual(len(listings), 1)


# --- The --authority pr-merge path ------------------------------------------------


def evidence(refusal: str | None) -> ve.Evidence:
    return ve.Evidence(
        refusal=refusal,
        head=unattended.HEAD,
        verdicts=(),
        ignored=0,
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

    def _evidence(self, number: int, head: str) -> ve.Evidence:
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
        code, out = self.lane()
        self.assertIn(f"dequeue:[{other}]", self.log)
        self.assertEqual(
            out["unattended"]["writes"]["holds"], {str(other): "verify:missing"}
        )

    def test_a_risk_refusal_stays_the_reason(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:fail")
        self.lanes = unattended.UNBOUND
        _, out = self.lane()
        self.assertTrue(out["unattended"]["reason"].startswith("risk:"))

    def test_dependabot_needs_no_verdict(self) -> None:
        # Refused before scoring as a dependency manager's pull request, so the
        # verdict reader is never consulted (babysit_merge_policy._foreign_refusal).
        self.lane_eligible = policy.Eligibility(False, "dependency-manager")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "ineligible:dependency-manager")
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

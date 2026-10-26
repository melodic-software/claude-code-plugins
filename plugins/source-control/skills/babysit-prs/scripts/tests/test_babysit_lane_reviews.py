"""The gate's risk hold enable-auto-merge reads (`lane_risk_refusal`).

Expected values come from the gate's own scoring rules in babysit_risk.py,
which native auto-merge would otherwise skip: only a regular file that stays
regular may rate below HIGH (`_mode_problems`), so a symlink or a submodule
pointer holds; the security lane's open CRITICAL findings hold
(`security-finding`); a lane whose evidence is not bound to the head holds;
claude-review's open findings are reported only; and a plain documentation
change by the lane merges. A read that fails holds. With the HIGH path floor
on, as this repository's pr-pipeline.yaml sets it, a manifest change the
gate reviews holds (`manifest-review-required`, the classes #9280 set) and a
plugin.json userConfig default does not (#9483); native auto-merge has no
manifest hold path of its own, so this is the check that holds it.
"""

from __future__ import annotations

import contextlib
import dataclasses
import io
import json
import pathlib
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge  # noqa: E402
import babysit_merge_policy as policy  # noqa: E402
import babysit_verify_evidence as ve  # noqa: E402
from babysit_risk import ChangedFile, LaneEvidence  # noqa: E402

REPO = "example-org/example-repo"
HEAD = "a" * 40
BASE = "b" * 40
PR = {
    "number": 41,
    "head": {"sha": HEAD, "ref": "feat/x"},
    "base": {"sha": BASE, "repo": {"private": False}},
}
CONFIG = policy.PipelineConfig(
    "c" * 40, "C2", "pr-merge", "agent-lanes[bot]", None, (), "c2-mechanical"
)
DOC = ChangedFile(
    "docs/guide.md",
    None,
    "modified",
    1,
    1,
    True,
    "100644",
    "100644",
    patch="@@ -1 +1 @@\n-old\n+new",
)
FLOOR_ON = dataclasses.replace(CONFIG, high_path_floor=True)
PLUGIN = "plugins/foo/.claude-plugin/plugin.json"
PLUGIN_BASE = (
    '{"name": "foo", "version": "1.0.0",'
    ' "userConfig": {"guard_enabled": {"type": "boolean", "default": true}}}'
)


def manifest(after: str) -> ChangedFile:
    return ChangedFile(
        PLUGIN, None, "modified", 1, 1, True, "100644", "100644",
        patch="@@ -1 +1 @@\n-a\n+b", contents=(PLUGIN_BASE, after),
    )


SYMLINK = ChangedFile("docs/link", None, "added", 1, 0, True, "120000", "000000")
SUBMODULE = ChangedFile("vendor/lib", None, "modified", 1, 1, False, "160000", "160000")


def lanes(
    *, code: int = 0, critical: int = 0, bound: bool = True
) -> tuple[LaneEvidence, ...]:
    return (
        LaneEvidence("claude-review", True, None, code),
        LaneEvidence(
            "claude-security-review",
            bound,
            None if bound else "marker-missing",
            critical if bound else None,
            False,
            critical if bound else None,
        ),
    )


def refusal(
    files: tuple[ChangedFile, ...] = (DOC,),
    evidence: object = None,
    config: policy.PipelineConfig = CONFIG,
) -> str | None:
    evidence = lanes() if evidence is None else evidence
    effect = evidence if isinstance(evidence, Exception) else None
    with (
        mock.patch.object(policy, "changed_files", return_value=(files, True)),
        mock.patch.object(policy, "with_contents", side_effect=lambda repo, pr, f: f),
        mock.patch.object(policy, "pulumi_dirs_at", return_value=()),
        mock.patch.object(policy, "permission_reader", return_value=lambda login: None),
        mock.patch.object(policy, "cost_decision", return_value=None),
        mock.patch.object(
            babysit_merge,
            "_lane_evidence",
            side_effect=effect,
            return_value=None if effect else (evidence, []),
        ),
    ):
        return ve.lane_risk_refusal(REPO, 41, PR, config, 7)


class LaneRiskRefusal(unittest.TestCase):
    def test_a_plain_doc_change_holds_nothing(self) -> None:
        self.assertIsNone(refusal())
        # claude-review's findings are reported, never held.
        self.assertIsNone(refusal(evidence=lanes(code=3)))

    def test_a_symlink_or_a_submodule_pointer_holds(self) -> None:
        for changed in (SYMLINK, SUBMODULE):
            with self.subTest(changed.path):
                held = refusal((DOC, changed))
                self.assertIsNotNone(held)
                self.assertIn(changed.path, str(held))

    def test_a_critical_security_finding_holds(self) -> None:
        self.assertIn(
            "security-finding: 1 open", str(refusal(evidence=lanes(critical=1)))
        )

    def test_an_unbound_security_review_holds(self) -> None:
        self.assertIn(
            "evidence-unbound:claude-security-review",
            str(refusal(evidence=lanes(bound=False))),
        )

    def test_a_manifest_change_the_gate_reviews_holds(self) -> None:
        for key in ('"hooks": {}', '"mcpServers": {}', '"experimental": {"monitors": []}'):
            after = PLUGIN_BASE.replace('"name": "foo",', f'"name": "foo", {key},')
            with self.subTest(key):
                held = refusal((DOC, manifest(after)), config=FLOOR_ON)
                self.assertIn("manifest-review-required", str(held))
                self.assertIn(PLUGIN, str(held))

    def test_a_user_config_default_merges(self) -> None:
        after = PLUGIN_BASE.replace('"default": true', '"default": false')
        self.assertIsNone(refusal((DOC, manifest(after)), config=FLOOR_ON))

    def test_a_failed_read_holds(self) -> None:
        held = refusal(
            evidence=babysit_merge.HeadPusherUnproven("head-pusher-unproven:abc")
        )
        self.assertTrue(str(held).startswith("unreadable: "), held)


class EvidenceCommandReadsTheRisk(unittest.TestCase):
    def cli(
        self,
        evidence: ve.Evidence,
        risk: str | None,
        *,
        head: str = HEAD,
        rung: str | None = "C2",
    ) -> dict[str, object]:
        out = io.StringIO()
        argv = ["evidence", "--lane-reviews", "--repo", REPO, "--base-sha", BASE]
        argv += ["--rung", rung] if rung is not None else []
        with (
            mock.patch.object(policy, "read_config_at", return_value=CONFIG),
            mock.patch.object(policy, "with_default_branch", return_value=CONFIG),
            mock.patch.object(
                policy, "pull_request", return_value=PR | {"head": {"sha": head}}
            ),
            mock.patch.object(
                ve.Reader, "evidence", lambda self, n, h, pr=None: evidence
            ),
            mock.patch.object(ve, "lane_risk_refusal", return_value=risk) as read,
            contextlib.redirect_stdout(out),
        ):
            ve.main([*argv, "41", HEAD])
        self.read = read
        return json.loads(out.getvalue())

    def test_a_pass_carries_the_risk_hold_when_the_room_has_a_rung(self) -> None:
        report = self.cli(ve.Evidence(None, HEAD, (), 0), "unsafe-path: docs/link")
        self.assertEqual(
            (report["refusal"], report["reviews"]), (None, "unsafe-path: docs/link")
        )
        self.assertIsNone(self.cli(ve.Evidence(None, HEAD, (), 0), None)["reviews"])

    def test_no_rung_from_the_room_holds(self) -> None:
        for rung in (None, "off", "C9"):
            with self.subTest(rung=rung):
                report = self.cli(ve.Evidence(None, HEAD, (), 0), None, rung=rung)
                self.assertTrue(str(report["reviews"]).startswith("unreadable: "))
                self.read.assert_not_called()

    def test_a_refused_verdict_reads_no_risk(self) -> None:
        report = self.cli(ve.Evidence(ve.FAIL, HEAD, (), 0), None)
        self.assertNotIn("reviews", report)
        self.read.assert_not_called()

    def test_a_moved_head_holds(self) -> None:
        report = self.cli(ve.Evidence(None, HEAD, (), 0), None, head="d" * 40)
        self.assertTrue(str(report["reviews"]).startswith("unreadable: the head is"))
        self.read.assert_not_called()


# The gate's hold texts (babysit_merge.unattended_enqueue), written out.
EJECTED = (
    f"queue-ejected:2 failed-check removals from the merge queue at head {HEAD}; "
    "a push resets the count"
)
UNREADABLE_QUEUE = "the merge queue's removals of this head are unreadable"
RUN = "https://github.com/example-org/example-repo/actions/runs/9"


def _group_run(url: str, group: str, at: str, conclusion: str) -> dict[str, str]:
    """A `babysit_merge._merge_group_runs` row."""
    return {
        "url": url,
        "headSha": group * 40,
        "createdAt": at,
        "conclusion": conclusion,
    }


FAILED_RUN = _group_run(RUN, "a", "2026-10-20T07:50:00Z", "failure")
CANCELLED_RUN = _group_run(RUN + "0", "b", "2026-10-20T08:00:00Z", "cancelled")
# A removal after each run: the first pairs with the failure, the second with
# the cancel.
REMOVALS = ["2026-10-20T07:55:00Z", "2026-10-20T08:10:00Z"]


class EvidenceCommandReadsTheQueueEjections(unittest.TestCase):
    """`evidence --lane-queue`: the gate's `merge.max-queue-ejections` cap
    (default 2) on a head the merge queue keeps removing for failed checks,
    which native auto-merge would otherwise re-arm without end."""

    def cli(
        self,
        queue: dict[str, object] | Exception,
        *,
        evidence: ve.Evidence | None = None,
        risk: str | None = None,
        runs: list[dict[str, str]] | Exception | None = None,
    ) -> dict[str, object]:
        out = io.StringIO()
        runs = [FAILED_RUN] if runs is None else runs
        runs_effect = runs if isinstance(runs, Exception) else None
        argv = ["evidence", "--lane-reviews", "--lane-queue", "--repo", REPO]
        argv += ["--base-sha", BASE, "--rung", "C2", "41", HEAD]
        effect = queue if isinstance(queue, Exception) else None
        with (
            mock.patch.object(policy, "read_config_at", return_value=CONFIG),
            mock.patch.object(policy, "with_default_branch", return_value=CONFIG),
            mock.patch.object(policy, "pull_request", return_value=PR),
            mock.patch.object(
                ve.Reader,
                "evidence",
                lambda self, n, h, pr=None: evidence or ve.Evidence(None, HEAD, (), 0),
            ),
            mock.patch.object(ve, "lane_risk_refusal", return_value=risk),
            mock.patch.object(
                babysit_merge,
                "read_merge_queue",
                side_effect=effect,
                return_value=None if effect else queue,
            ) as read,
            mock.patch.object(
                babysit_merge,
                "_merge_group_runs",
                side_effect=runs_effect,
                return_value=None if runs_effect else runs,
            ),
            contextlib.redirect_stdout(out),
        ):
            ve.main(argv)
        self.read = read
        return json.loads(out.getvalue())

    def test_a_head_under_the_cap_carries_its_count_and_no_refusal(self) -> None:
        for count in (0, 1):
            with self.subTest(count=count):
                report = self.cli({"readError": None, "failedEjections": count})
                self.assertEqual(
                    report["queue"],
                    {
                        "failedEjections": count,
                        "cancelledEjections": 0,
                        "limit": 2,
                        "refusal": None,
                        "comment": None,
                        "readError": None,
                        "commentError": None,
                    },
                )

    def test_a_head_at_or_over_the_cap_carries_the_gates_hold_and_comment(
        self,
    ) -> None:
        for count in (2, 3):
            with self.subTest(count=count):
                queue = self.cli({"readError": None, "failedEjections": count})["queue"]
                self.assertEqual(
                    (queue["failedEjections"], queue["limit"], queue["refusal"]),
                    (count, 2, EJECTED.replace("ejected:2", f"ejected:{count}")),
                )
                comment = str(queue["comment"]).split("\n")
                self.assertEqual(comment[0], "<!-- babysit-merge-queue-ejections -->")
                self.assertIn(f"head `{HEAD}` {count} times", comment[1])
                self.assertIn(f"- {RUN}", comment)

    def test_an_unreadable_count_refuses_with_no_comment_and_says_why(self) -> None:
        for queue, why in (
            (
                {"readError": "could not read the merge queue: boom"},
                "could not read the merge queue: boom",
            ),
            (
                {"readError": None, "failedEjections": None},
                "the merge queue's timeline items could not be counted",
            ),
            (RuntimeError("boom"), "RuntimeError: boom"),
        ):
            with self.subTest(queue=repr(queue)):
                self.assertEqual(
                    self.cli(queue)["queue"],
                    {
                        "failedEjections": None,
                        "cancelledEjections": 0,
                        "limit": 2,
                        "refusal": UNREADABLE_QUEUE,
                        "comment": None,
                        "readError": why,
                        "commentError": None,
                    },
                )

    def test_a_failed_runs_read_still_refuses_and_names_its_error(self) -> None:
        queue = self.cli(
            {"readError": None, "failedEjections": 2}, runs=RuntimeError("boom")
        )["queue"]
        self.assertEqual(
            (queue["refusal"], queue["comment"], queue["commentError"]),
            (EJECTED, None, "error: boom"),
        )

    def test_the_comment_is_the_one_the_gate_posts(self) -> None:
        queue = self.cli({"readError": None, "failedEjections": 2})["queue"]
        with mock.patch.object(
            babysit_merge, "_merge_group_runs", return_value=[FAILED_RUN]
        ):
            gate = babysit_merge.queue_ejection_hold(REPO, "main", 41, HEAD, 2, 2)
        self.assertEqual(
            (queue["refusal"], queue["comment"]), (gate.refusal, gate.comment)
        )

    def test_a_cancelled_run_rearms_and_a_failed_one_does_not(self) -> None:
        # Issue 8566: a removal after a cancelled merge_group run does not
        # spend the failure cap, so native auto-merge arms the head again.
        removed = {
            "readError": None,
            "failedEjections": 2,
            "failedRemovals": REMOVALS,
        }
        queue = self.cli(removed, runs=[FAILED_RUN, CANCELLED_RUN])["queue"]
        self.assertEqual(
            (queue["refusal"], queue["comment"], queue["cancelledEjections"]),
            (None, None, 1),
        )
        failed = [FAILED_RUN, {**CANCELLED_RUN, "conclusion": "failure"}]
        queue = self.cli(removed, runs=failed)["queue"]
        self.assertEqual((queue["refusal"], queue["cancelledEjections"]), (EJECTED, 0))

    def test_a_refused_verdict_or_a_risk_hold_reads_no_queue(self) -> None:
        for kwargs in (
            {"evidence": ve.Evidence(ve.FAIL, HEAD, (), 0)},
            {"risk": "unsafe-path: docs/link"},
        ):
            with self.subTest(kwargs=repr(kwargs)):
                report = self.cli({"readError": None, "failedEjections": 5}, **kwargs)
                self.assertNotIn("queue", report)
                self.read.assert_not_called()

    def test_the_flag_needs_the_risk_read_that_checks_the_head(self) -> None:
        argv = ["evidence", "--lane-queue", "--repo", REPO, "--base-sha", BASE]
        with (
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            ve.main([*argv, "41", HEAD])


if __name__ == "__main__":
    unittest.main()

"""Post-merge demotion by affected set (`babysit_postmerge`, owner decision
Q645 with Q651): a red full run demotes only for a failing suite in the
affected set of the merges since the branch's last green full run. A suite
outside it is quarantined (an issue, no demotion, the merge verified); an
open quarantine issue excuses its suite until `merge.quarantine-days`; the
merge gate's own suites, an unnamed suite and an uncomputable set demote.

Log shapes are those scripts/run-plugin-tests.sh and the test-python leg's
`xargs -t ... pytest -q` print; network is stubbed at `gh_capture`.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime
from typing import Any
from unittest import mock

# An inherited GIT_DIR, GIT_WORK_TREE or GIT_CONFIG would send the git
# fixtures' identity writes into the caller's repository
# (scripts/check-fixture-git-isolation.sh). Cleared before any test spawns git.
for _leaked_git_var in (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_PREFIX",
    "GIT_OBJECT_DIRECTORY",
    "GIT_CONFIG",
):
    os.environ.pop(_leaked_git_var, None)
del _leaked_git_var

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import babysit_merge_policy as policy  # noqa: E402  (follows the git-env clear above)
import babysit_postmerge as pm  # noqa: E402
from test_babysit_postmerge import (  # noqa: E402
    FIXTURES,
    HEAD_SHA,
    IDENTITY,
    LATER_SHA,
    OTHER_SHA,
    REPO,
    RUN_URL,
    CheckCase,
    by,
    canary_run,
    completed,
    dispatch_run,
    failed_job,
    identity_merge,
    schedule_run,
)

STAMP = "2026-10-12T10:20:00.1234567Z "
FLAKY = "plugins/notes/skills/sync/sync.test.sh"
TOUCHED = "plugins/source-control/skills/commit/commit.test.sh"
GATE = "plugins/source-control/skills/babysit-prs/scripts/engine.test.sh"
SIGHTING = f"{RUN_URL}/11/attempts/2"


def bash_log(*results: tuple[str, bool], tail: str = "") -> str:
    """A test-bash leg's log: each suite's block, then PASS or FAIL."""
    lines = ["##[group]Run jq -r --arg leg ...", "##[endgroup]"]
    for suite, ok in results:
        lines += [f"=== {suite} ===", "FAIL: a case inside the suite"]
        lines += [f"{'PASS' if ok else 'FAIL'}: {suite}"]
    lines += [tail, "One or more plugin tests failed."]
    return "\n".join(STAMP + line for line in lines)


class QuarantineGh:
    """The base fake plus job logs and CODEOWNERS."""

    def __init__(self, base: Any) -> None:
        self.base = base
        self.logs: dict[int, str] = {}
        self.codeowners: str | None = None

    def __call__(
        self, args: list[str], **kwargs: Any
    ) -> subprocess.CompletedProcess[str]:
        endpoint = next((a for a in args if a.startswith("repos/")), "")
        if "/actions/jobs/" in endpoint and endpoint.endswith("/logs"):
            self.base.calls.append(list(args))
            job = int(endpoint.split("/actions/jobs/")[1].split("/")[0])
            if job not in self.logs:
                return completed(returncode=1, stderr="gh: Not Found (HTTP 404)")
            return subprocess.CompletedProcess(["gh"], 0, self.logs[job], "")
        if "/contents/.github/CODEOWNERS" in endpoint and self.codeowners is not None:
            self.base.calls.append(list(args))
            return subprocess.CompletedProcess(["gh"], 0, self.codeowners, "")
        return self.base(args, **kwargs)


class AffectedBase(CheckCase):
    def setUp(self) -> None:
        super().setUp()
        self.fake = QuarantineGh(self.gh)
        for module in (pm, pm.policy):
            patcher = mock.patch.object(module, "gh_capture", self.fake)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.affected: frozenset[str] | None = frozenset({TOUCHED})
        patcher = mock.patch.object(
            pm, "affected_suites", side_effect=lambda base, head: self.affected
        )
        self.affected_calls = patcher.start()
        self.addCleanup(patcher.stop)
        # merge.quarantine-days at its default (QuarantineDaysConfig reads it).
        patcher = mock.patch.object(
            pm.policy,
            "read_config_at",
            return_value=mock.Mock(quarantine_days=policy.QUARANTINE_DAYS),
        )
        patcher.start()
        self.addCleanup(patcher.stop)
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        # The last green full run before the red one, at OTHER_SHA.
        self.gh.add_runs(
            "pr-require-checks.yml",
            "schedule",
            schedule_run(
                5, "success", head_sha=OTHER_SHA, created_at="2026-10-12T08:00:00Z"
            ),
        )

    def red_dispatch(self, log: str, step: str = "Run this leg's shell suites") -> None:
        """Dispatch run 11 red on attempt 1 and on the identity's re-run,
        failing one test-bash leg (job 112) with `log`."""
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(11, "failure", run_attempt=2, triggering_actor=by(IDENTITY)),
        )
        self.gh.attempts[(11, 1)] = dispatch_run(11, "failure")
        self.gh.jobs[(11, 2)] = [failed_job(112, "test-bash (0)", step)]
        self.fake.logs[112] = log

    def quarantine_issue(self, suite: str, created: str, state: str = "open") -> None:
        self.gh.issues.append(
            {
                "number": 501,
                "state": state,
                "created_at": created,
                "body": f"{pm.quarantine_marker(suite)}\n\nquarantined",
                "user": {"login": "github-actions[bot]"},
            }
        )

    def remediate(self, verdict: pm.PostMergeVerdict) -> dict[str, Any]:
        return pm.remediate(REPO, verdict, agent_identity=IDENTITY)

    def posts(self) -> list[list[str]]:
        return [c for c in self.gh.writes() if "POST" in c]


class AffectedSet(AffectedBase):
    def test_an_unrelated_red_suite_files_a_quarantine_issue_and_does_not_demote(
        self,
    ) -> None:
        self.red_dispatch(bash_log((FLAKY, False), (TOUCHED, True)))
        verdict = self.check()
        self.assertEqual(verdict.failures, ())
        self.assertEqual(
            verdict.quarantines, (pm.Quarantine(FLAKY, SIGHTING, LATER_SHA),)
        )
        self.affected_calls.assert_called_once_with(OTHER_SHA, LATER_SHA)

        report = self.remediate(verdict)
        self.assertEqual(report["errors"], [])
        self.assertEqual(report["dequeued"], [])
        self.assertEqual(report["telemetry"], {"demotion_events": 0})
        self.assertEqual(report["quarantine"]["issues"], [9001])
        (post,) = self.posts()
        body = next(a for a in post if a.startswith("body="))
        self.assertTrue(body.startswith(f"body={pm.quarantine_marker(FLAKY)}\n"))
        self.assertIn(f"- Failing run: {SIGHTING}", body)
        self.assertIn(f"- Main at the failing run: `{LATER_SHA}`", body)
        self.assertIn("<!-- work-items:born-triaged -->", body)
        self.assertIn("labels[]=needs-human", post)
        self.assertNotIn("babysit-merge-demotion", body)
        self.assertFalse(any(a.startswith("assignees[]=") for a in post))

    def test_an_excused_window_counts_as_verified_and_releases_its_slot(self) -> None:
        self.red_dispatch(bash_log((FLAKY, False)))
        verdict = self.check()
        self.assertTrue(verdict.ok)
        self.assertTrue(verdict.merges[0].verified)
        self.assertTrue(verdict.is_verified(verdict.merges[0].merge))
        self.assertEqual(pm.verdict_exit(verdict), 0)

    def test_a_related_red_suite_demotes(self) -> None:
        self.red_dispatch(bash_log((FLAKY, True), (TOUCHED, False)))
        verdict = self.check()
        self.assertEqual([f.signal for f in verdict.failures], ["dispatch"])
        self.assertIn("newly failing: test-bash (0)", verdict.failures[0].detail)
        self.assertEqual(verdict.quarantines, ())
        self.assertFalse(verdict.is_verified(verdict.merges[0].merge))

    def test_one_related_suite_beside_an_unrelated_one_demotes(self) -> None:
        self.red_dispatch(bash_log((FLAKY, False), (TOUCHED, False)))
        verdict = self.check()
        self.assertEqual([f.signal for f in verdict.failures], ["dispatch"])
        self.assertEqual([q.suite for q in verdict.quarantines], [FLAKY])

    def test_an_uncomputable_affected_set_demotes(self) -> None:
        self.affected = None
        self.red_dispatch(bash_log((FLAKY, False)))
        verdict = self.check()
        self.assertEqual([f.signal for f in verdict.failures], ["dispatch"])
        self.assertEqual(verdict.quarantines, ())

    def test_no_green_full_run_before_the_red_one_demotes(self) -> None:
        self.gh.runs[("pr-require-checks.yml", "schedule")] = []
        self.red_dispatch(bash_log((FLAKY, False)))
        self.assertEqual([f.signal for f in self.check().failures], ["dispatch"])
        self.affected_calls.assert_not_called()

    def test_a_gate_suite_never_quarantines(self) -> None:
        self.red_dispatch(bash_log((GATE, False)))
        verdict = self.check()
        self.assertEqual([f.signal for f in verdict.failures], ["dispatch"])
        self.assertEqual(verdict.quarantines, ())
        self.assertEqual(self.remediate(verdict)["quarantine"]["issues"], [])

    def test_a_quarantine_issue_on_a_gate_suite_excuses_nothing(self) -> None:
        self.quarantine_issue(GATE, "2026-10-12T09:00:00Z")
        self.red_dispatch(bash_log((GATE, False)))
        self.assertEqual([f.signal for f in self.check().failures], ["dispatch"])

    def test_an_open_quarantine_never_excuses_a_failure_inside_the_set(self) -> None:
        self.quarantine_issue(TOUCHED, "2026-10-10T09:00:00Z")
        self.red_dispatch(bash_log((TOUCHED, False)))
        verdict = self.check()
        self.assertEqual([f.signal for f in verdict.failures], ["dispatch"])
        self.assertEqual(verdict.quarantines, ())

    def test_an_open_quarantine_takes_an_out_of_set_sighting(self) -> None:
        self.quarantine_issue(FLAKY, "2026-10-10T09:00:00Z")
        self.red_dispatch(bash_log((FLAKY, False)))
        verdict = self.check()
        self.assertEqual(verdict.failures, ())
        report = self.remediate(verdict)
        self.assertEqual(report["quarantine"], {"issues": [], "comments": [501]})
        (post,) = self.posts()
        self.assertIn(f"body={pm.QUARANTINE_NOTE}{SIGHTING}", post)

    def test_the_selector_scripts_are_gate_suites(self) -> None:
        for suite in (
            "scripts/plan-test-lanes.test.sh",
            "scripts/affected-tests.test.sh",
        ):
            with self.subTest(suite):
                self.assertTrue(pm.is_gate_suite(suite))

    def test_expiry_restores_demotion(self) -> None:
        # Filed 8 days before the check's 2026-10-12T11:00Z; the default is 7.
        self.quarantine_issue(FLAKY, "2026-10-04T10:00:00Z")
        self.red_dispatch(bash_log((FLAKY, False)))
        verdict = self.check()
        self.assertEqual([f.signal for f in verdict.failures], ["dispatch"])
        self.assertEqual(verdict.quarantines, ())

    def red_baseline(self) -> None:
        """Dispatch run 10, before the merge, red on the same leg."""
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(
                10, "failure", head_sha=OTHER_SHA, created_at="2026-10-12T09:30:00Z"
            ),
        )
        self.gh.jobs[(10, 1)] = [
            failed_job(102, "test-bash (0)", "Run this leg's shell suites")
        ]

    def test_expiry_restores_demotion_when_the_baseline_was_red_too(self) -> None:
        # A persistent failure is in the baseline as well; its expired
        # quarantine still demotes.
        self.quarantine_issue(FLAKY, "2026-10-04T10:00:00Z")
        self.red_baseline()
        self.red_dispatch(bash_log((FLAKY, False)))
        verdict = self.check()
        self.assertEqual([f.signal for f in verdict.failures], ["dispatch"])
        self.assertFalse(verdict.merges[0].verified)

    def test_a_baseline_failure_under_a_live_quarantine_stays_excused(self) -> None:
        self.quarantine_issue(FLAKY, "2026-10-10T10:00:00Z")
        self.red_baseline()
        self.red_dispatch(bash_log((FLAKY, False)))
        self.assertEqual(self.check().failures, ())

    def test_a_closed_quarantine_issue_quarantines_the_suite_afresh(self) -> None:
        self.quarantine_issue(FLAKY, "2026-10-04T10:00:00Z", state="closed")
        self.red_dispatch(bash_log((FLAKY, False)))
        verdict = self.check()
        self.assertEqual(verdict.failures, ())
        self.assertEqual(self.remediate(verdict)["quarantine"]["issues"], [9001])

    def test_a_quarantine_issue_someone_else_opened_counts_for_nothing(self) -> None:
        # An outsider's expired issue would demote, and an open one would take
        # the sighting: it is neither, so the filers' own issue is filed.
        self.quarantine_issue(FLAKY, "2026-10-01T09:00:00Z")
        self.gh.issues[-1]["user"] = {"login": "outsider"}
        self.red_dispatch(bash_log((FLAKY, False)))
        verdict = self.check()
        self.assertEqual(verdict.failures, ())
        self.assertEqual(self.remediate(verdict)["quarantine"]["issues"], [9001])

    def test_a_leg_whose_suites_cannot_be_named_demotes(self) -> None:
        cases = {
            "no FAIL line": bash_log((FLAKY, True)),
            "a discriminating skip": bash_log(
                (FLAKY, False), tail="DISCRIMINATING SKIP: x vacated 1"
            ),
            "a suite with no result": STAMP + f"=== {FLAKY} ===",
        }
        for label, log in cases.items():
            with self.subTest(label):
                self.setUp()
                self.red_dispatch(log)
                self.assertEqual(
                    [f.signal for f in self.check().failures], ["dispatch"]
                )

    def test_a_failed_step_other_than_the_suite_step_demotes(self) -> None:
        self.red_dispatch(bash_log((FLAKY, False)), step="Install pinned shfmt")
        self.assertEqual([f.signal for f in self.check().failures], ["dispatch"])

    def test_an_unreadable_log_demotes(self) -> None:
        self.red_dispatch(bash_log((FLAKY, False)))
        del self.fake.logs[112]
        self.assertEqual([f.signal for f in self.check().failures], ["dispatch"])

    def test_the_quarantine_issue_goes_to_the_codeowners_user(self) -> None:
        self.fake.codeowners = (
            "/plugins/notes/** @notes-owner\n/plugins/x/** @org/team\n"
        )
        self.red_dispatch(bash_log((FLAKY, False)))
        self.remediate(self.check())
        (post,) = self.posts()
        self.assertIn("assignees[]=notes-owner", post)

    def test_a_repeat_sighting_is_not_commented_twice(self) -> None:
        self.quarantine_issue(FLAKY, "2026-10-12T09:00:00Z")
        self.gh.comments[501] = [
            {
                "user": {"login": "github-actions[bot]"},
                "body": f"{pm.QUARANTINE_NOTE}{SIGHTING}",
            }
        ]
        self.red_dispatch(bash_log((FLAKY, False)))
        report = self.remediate(self.check())
        self.assertEqual(report["quarantine"], {"issues": [], "comments": []})
        self.assertEqual(self.posts(), [])


class JudgeRunCli(AffectedBase):
    """`--judge-run`, as post-merge-demotion-alert.yml calls it."""

    def judge(
        self,
        *checks: str,
        file: bool = True,
        identity: bool = True,
        baseline: tuple[str, ...] = (),
    ) -> tuple[int, dict[str, Any]]:
        self.red_dispatch(self.fake.logs.get(112) or bash_log((FLAKY, False)))
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "checks"
            path.write_text("\n".join(checks) + "\n", encoding="utf-8")
            argv = ["--repo", REPO]
            argv += ["--agent-identity", IDENTITY] if identity else []
            argv += ["--judge-run", "11", "--attempt", "2", "--checks-file", str(path)]
            argv += ["--file-quarantine"] if file else []
            if baseline:
                kept = pathlib.Path(tmp) / "baseline"
                kept.write_text("\n".join(baseline) + "\n", encoding="utf-8")
                argv += ["--baseline-checks-file", str(kept)]
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = pm.main(argv)
        return code, json.loads(out.getvalue())

    def test_an_out_of_set_failure_exits_0_and_files_the_issue(self) -> None:
        code, report = self.judge("test-bash (0)")
        self.assertEqual(code, 0)
        self.assertEqual(report["demoting"], [])
        self.assertEqual(report["quarantine"]["issues"], [9001])

    def test_without_an_identity_it_reads_the_default_branch_config(self) -> None:
        config = mock.Mock(agent_identity=IDENTITY, quarantine_days=7)
        with (
            mock.patch.object(
                pm.policy, "_default_branch_head", return_value=("main", "c" * 40)
            ) as head,
            mock.patch.object(pm.policy, "read_config_at", return_value=config),
            mock.patch.object(pm.policy, "resolve") as resolve,
        ):
            code, _ = self.judge("test-bash (0)", identity=False)
        self.assertEqual(code, 0)
        head.assert_called_once_with(REPO)
        resolve.assert_not_called()

    def test_a_one_word_section_header_inside_a_suite_is_no_suite(self) -> None:
        log = bash_log((FLAKY, False)).replace(
            "FAIL: a case inside the suite", "=== setup ===", 1
        )
        self.assertEqual(pm.suite_failures(log, "bash"), frozenset({FLAKY}))

    def test_without_file_quarantine_it_writes_nothing(self) -> None:
        code, _ = self.judge("test-bash (0)", file=False)
        self.assertEqual(code, 0)
        self.assertEqual(self.gh.writes(), [])

    def test_an_in_set_failure_exits_1(self) -> None:
        self.fake.logs[112] = bash_log((TOUCHED, False))
        code, report = self.judge("test-bash (0)")
        self.assertEqual((code, report["demoting"]), (1, ["test-bash (0)"]))

    def test_a_check_that_is_no_test_leg_exits_1(self) -> None:
        code, report = self.judge("test-bash (0)", "lint-repo: markdown failed")
        self.assertEqual(code, 1)
        self.assertEqual(report["demoting"], ["lint-repo: markdown failed"])

    def test_no_checks_is_a_usage_refusal(self) -> None:
        code, _ = self.judge()
        self.assertEqual(code, 2)

    def test_an_expired_quarantine_on_a_baseline_check_exits_1(self) -> None:
        self.quarantine_issue(FLAKY, "2026-10-04T10:00:00Z")
        with mock.patch.object(pm, "datetime", wraps=datetime) as clock:
            clock.now.return_value = datetime(2026, 10, 12, 11, 0, tzinfo=UTC)
            code, report = self.judge(baseline=("test-bash (0)",))
        self.assertEqual((code, report["demoting"]), (1, ["test-bash (0)"]))

    def test_a_live_quarantine_on_a_baseline_check_exits_0(self) -> None:
        self.quarantine_issue(FLAKY, "2026-10-10T10:00:00Z")
        with mock.patch.object(pm, "datetime", wraps=datetime) as clock:
            clock.now.return_value = datetime(2026, 10, 12, 11, 0, tzinfo=UTC)
            code, report = self.judge(baseline=("test-bash (0)",))
        self.assertEqual((code, report["demoting"]), (0, []))


class LaneRerunOutsideAWindow(AffectedBase):
    """#9126, owner decision 2026-10-22: in the pr-merge lane's check
    (`--lane-merges-only`), a red attempt 1 of a full run the lane
    dispatched, with a failing suite inside the affected set, is marked for
    post-merge-dispatch's one re-run even when no lane merge is judged.
    post-merge-demotion-alert.yml then demotes only on a red attempt 2. The
    fixture's one merge is another App's, so the lane judges none."""

    BOT = by("github-actions[bot]")
    NOW = datetime(2026, 10, 12, 11, 0, tzinfo=UTC)

    def lane_red(self, log: str, **run: Any) -> None:
        """Run 11, dispatched by pr-merge.yml on main, red on attempt 1 in
        one test-bash leg (job 112) whose log is `log`."""
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(
                11, "failure", actor=self.BOT, triggering_actor=self.BOT, **run
            ),
        )
        self.gh.attempts[(11, 1)] = dispatch_run(
            11, "failure", actor=self.BOT, triggering_actor=self.BOT
        )
        self.gh.jobs[(11, 1)] = [
            failed_job(112, "test-bash (0)", "Run this leg's shell suites")
        ]
        self.fake.logs[112] = log
        self.gh.artifacts["pr-merge-dispatched-11"] = [
            {"id": 9, "name": "pr-merge-dispatched-11", "workflow_run": {"id": 500}}
        ]
        self.gh.run_records[500] = {
            "id": 500,
            "path": ".github/workflows/pr-merge.yml",
            "event": "push",
            "head_branch": "main",
            "head_sha": LATER_SHA,
            "repository": {"full_name": REPO},
            "head_repository": {"full_name": REPO},
        }

    def lane_check(self, *, lane_merges_only: bool = True) -> pm.PostMergeVerdict:
        return pm.check(
            REPO,
            agent_identity=IDENTITY,
            is_human=lambda actor: False,
            merged_since=datetime(2026, 10, 12, 0, 0, tzinfo=UTC),
            now=self.NOW,
            pinned_sha=lambda merge: None,
            lane_merges_only=lane_merges_only,
        )

    def lane_reruns(self, verdict: pm.PostMergeVerdict) -> list[tuple[int, bool]]:
        return [(r["runId"], r["laneDispatched"]) for r in verdict.report()["reruns"]]

    def test_an_in_set_red_is_marked_for_the_lanes_one_rerun(self) -> None:
        self.lane_red(bash_log((TOUCHED, False)))
        verdict = self.lane_check()
        self.assertEqual(verdict.merges, ())
        self.assertEqual(self.lane_reruns(verdict), [(11, True)])
        self.assertEqual(pm.verdict_exit(verdict), 0)

    def test_an_out_of_set_red_gets_no_rerun_and_files_no_quarantine(self) -> None:
        # The alert's --judge-run already excuses and quarantines it. A lane
        # merge is judged, so the verdict carries quarantines, but run 11's
        # head lacks it.
        self.gh.merged = [identity_merge(number=7002)]
        self.lane_red(bash_log((FLAKY, False)), head_sha=HEAD_SHA)
        verdict = self.lane_check()
        self.assertEqual([m.merge.number for m in verdict.merges], [7002])
        self.assertEqual(self.lane_reruns(verdict), [])
        self.assertEqual(verdict.quarantines, ())

    def test_a_red_with_its_attempt_2_gets_no_second_rerun(self) -> None:
        self.lane_red(bash_log((TOUCHED, False)), run_attempt=2)
        self.assertEqual(self.lane_reruns(self.lane_check()), [])

    def test_a_red_older_than_the_alerts_wait_gets_no_rerun(self) -> None:
        self.lane_red(bash_log((TOUCHED, False)), created_at="2026-10-12T09:00:00Z")
        self.assertEqual(self.lane_reruns(self.lane_check()), [])

    def test_a_red_the_lane_did_not_dispatch_gets_no_rerun(self) -> None:
        self.lane_red(bash_log((TOUCHED, False)))
        self.gh.artifacts.clear()
        self.assertEqual(self.lane_reruns(self.lane_check()), [])

    def test_without_the_lane_flag_nothing_is_marked(self) -> None:
        # Local babysit judges the other App's merge, whose window run 11
        # is not in (its head lacks the merge), and adds no lane re-run.
        self.lane_red(bash_log((TOUCHED, False)), head_sha=OTHER_SHA)
        verdict = self.lane_check(lane_merges_only=False)
        self.assertEqual(self.lane_reruns(verdict), [])

    def test_an_unreadable_lane_record_warns_and_leaves_the_verdict_readable(
        self,
    ) -> None:
        self.lane_red(bash_log((TOUCHED, False)))
        self.gh.fail_reads.add("name=pr-merge-dispatched-11")
        verdict = self.lane_check()
        self.assertTrue(verdict.readable)
        self.assertEqual(self.lane_reruns(verdict), [])
        self.assertTrue(
            any(w.startswith("lane-rerun-unreadable: ") for w in verdict.warnings)
        )


class AffectedSuites(unittest.TestCase):
    """`affected_suites` runs the GREEN commit's plan script, in a worktree
    of it, over the paths `green..red` changed, in a local clone holding
    both; a window that changes the selector itself has no set."""

    # Prints the tree it runs in (`tree.txt`) and the paths it was given.
    PLAN = (
        "#!/usr/bin/env bash\n"
        '[[ "$1" == -- ]] || exit 2\n'
        "shift\n"
        'echo "bash_plan={\\"0\\":[\\"$(cat tree.txt)\\"]}"\n'
        'echo "python_plan={\\"0\\":[\\"$*\\"]}"\n'
    )

    def git(self, root: pathlib.Path, *args: str) -> str:
        return subprocess.run(
            ["git", "-C", str(root), *args], check=True, capture_output=True, text=True
        ).stdout.strip()

    def commit(self, files: dict[str, str], message: str) -> str:
        for path, text in files.items():
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8")
        self.git(self.root, "add", ".")
        self.git(self.root, "commit", "-q", "-m", message)
        return self.git(self.root, "rev-parse", "HEAD")

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = pathlib.Path(tmp.name) / "clone"
        self.root.mkdir()
        self.git(self.root, "init", "-q")
        self.git(self.root, "config", "user.email", "t@example.com")
        self.git(self.root, "config", "user.name", "t")
        self.green = self.commit(
            {pm.PLAN_SCRIPT: self.PLAN, "tree.txt": "green"}, "green"
        )
        self.red = self.commit({"src/a.sh": "a", "tree.txt": "red"}, "red")
        patcher = mock.patch.object(
            pm.policy, "_history_checkouts", return_value=[self.root]
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_the_green_commits_plan_over_the_windows_paths(self) -> None:
        self.assertEqual(
            pm.affected_suites(self.green, self.red),
            frozenset({"green", "src/a.sh tree.txt", "src/a.sh", "tree.txt"}),
        )
        self.assertEqual(self.git(self.root, "worktree", "list").count("\n"), 0)

    def test_a_suite_the_window_adds_is_in_the_set(self) -> None:
        # The green tree lacks it, so its plan cannot pick it.
        red = self.commit({"plugins/x/tests/test_new.py": "def test(): 0"}, "add")
        self.assertIn(
            "plugins/x/tests/test_new.py", pm.affected_suites(self.green, red)
        )

    def test_a_window_that_changes_the_selector_has_no_set(self) -> None:
        for path in (
            pm.PLAN_SCRIPT,
            "scripts/affected-tests.sh",
            "scripts/affected-tests-no-suite.txt",
            "scripts/lib/read-list.sh",
            "scripts/suite-seconds.txt",
        ):
            with self.subTest(path):
                red = self.commit({path: f"changed {path}"}, f"touch {path}")
                self.assertIsNone(pm.affected_suites(self.green, red))

    def test_an_empty_plan_has_no_set(self) -> None:
        plan = (
            "#!/usr/bin/env bash\necho 'bash_plan={\"0\":[]}'\necho 'python_plan={}'\n"
        )
        green = self.commit({pm.PLAN_SCRIPT: plan}, "empty plan")
        red = self.commit({"src/b.sh": "b"}, "red")
        self.assertIsNone(pm.affected_suites(green, red))

    def test_the_plan_runs_with_no_token_in_its_environment(self) -> None:
        plan = (
            "#!/usr/bin/env bash\n"
            'echo "bash_plan={\\"0\\":[\\"t-${GH_TOKEN:-}${GITHUB_TOKEN:-}'
            '${ACTIONS_RUNTIME_TOKEN:-}${PATH:+p}\\"]}"\n'
        )
        green = self.commit({pm.PLAN_SCRIPT: plan}, "token probe")
        red = self.commit({"src/b.sh": "b"}, "red")
        secrets = {"GH_TOKEN": "a", "GITHUB_TOKEN": "b", "ACTIONS_RUNTIME_TOKEN": "c"}
        with mock.patch.dict("os.environ", secrets):
            self.assertEqual(
                pm.affected_suites(green, red), frozenset({"t-p", "src/b.sh"})
            )

    def test_a_green_tree_without_the_plan_script_has_no_set(self) -> None:
        self.git(self.root, "rm", "-q", pm.PLAN_SCRIPT)
        self.git(self.root, "commit", "-q", "-m", "no plan")
        green = self.git(self.root, "rev-parse", "HEAD")
        red = self.commit({"src/b.sh": "b"}, "red")
        self.assertIsNone(pm.affected_suites(green, red))

    def test_a_commit_no_clone_holds_has_no_set(self) -> None:
        self.assertIsNone(pm.affected_suites("e" * 40, self.red))


class SuiteFailures(unittest.TestCase):
    def test_bash_names_the_failing_suites_and_drops_advisory_ones(self) -> None:
        log = bash_log(
            (FLAKY, False),
            (TOUCHED, False),
            (GATE, True),
            tail=f"::warning::{TOUCHED} failed (exit 1) but is advisory on this run",
        )
        self.assertEqual(pm.suite_failures(log, "bash"), frozenset({FLAKY}))

    def test_a_real_leg_log_names_only_runner_suites(self) -> None:
        # Job 119563204870: the ui suite's own output prints `FAIL: <file>`
        # lines, and the runner's stderr `FAIL: <suite>` lands inside them.
        log = (FIXTURES / "job-log-bash-ui-fail.txt").read_text(encoding="utf-8")
        self.assertEqual(
            pm.suite_failures(log, "bash"),
            frozenset({"plugins/planning/shared/tests/ui.test.sh"}),
        )

    def test_bash_names_a_suite_that_never_reported(self) -> None:
        log = STAMP + f"FAIL: {FLAKY} (no result recorded; the worker never reported)"
        self.assertEqual(pm.suite_failures(log, "bash"), frozenset({FLAKY}))

    def pytest_log(self, *segments: tuple[str, str | None]) -> str:
        lines = ["Run tr '\\n' '\\0' <x | xargs -0 -r -t -n1 python -m pytest -q --"]
        for suite, summary in segments:
            lines.append(
                f"python -m pytest -q -o tmp_path_retention_policy=none -- {suite}"
            )
            lines += ["..F.", "FAILED x::y - AssertionError"] if summary else [".."]
            if summary:
                lines.append(summary)
        return "\n".join(STAMP + line for line in lines)

    def test_python_reads_each_invocation_summary(self) -> None:
        log = self.pytest_log(
            ("a/test_a.py", "1 failed, 3 passed in 0.52s"),
            ("b/test_b.py", "4 passed, 1 skipped in 0.10s"),
            ("c/test_c.py", "no tests ran in 0.01s"),
            ("d/test_d.py", "===== 1 error in 0.20s ====="),
        )
        self.assertEqual(
            pm.suite_failures(log, "python"),
            frozenset({"a/test_a.py", "c/test_c.py", "d/test_d.py"}),
        )

    def test_python_with_an_invocation_lacking_a_summary_names_nothing(self) -> None:
        log = self.pytest_log(
            ("a/test_a.py", "1 failed in 0.5s"), ("b/test_b.py", None)
        )
        self.assertIsNone(pm.suite_failures(log, "python"))

    def test_python_with_every_suite_passing_names_nothing(self) -> None:
        log = self.pytest_log(("a/test_a.py", "2 passed in 0.5s"))
        self.assertIsNone(pm.suite_failures(log, "python"))


class SuiteOwner(unittest.TestCase):
    TEXT = "\n".join(
        [
            "# comment",
            "* @default-owner",
            "/plugins/source-control/** @sc-owner",
            "/plugins/source-control/skills/commit/ @org/team",
            "/plugins/notes/sync.test.sh",
        ]
    )

    def test_the_last_matching_rule_wins(self) -> None:
        self.assertEqual(pm.suite_owner(self.TEXT, TOUCHED), None)
        self.assertEqual(pm.suite_owner(self.TEXT, GATE), "sc-owner")
        self.assertEqual(
            pm.suite_owner(self.TEXT, "scripts/x.test.sh"), "default-owner"
        )
        self.assertEqual(pm.suite_owner(self.TEXT, "plugins/notes/sync.test.sh"), None)

    def test_no_rule_is_no_owner(self) -> None:
        self.assertIsNone(pm.suite_owner("/docs/** @docs", FLAKY))


class QuarantineDaysConfig(unittest.TestCase):
    def config(self, line: str) -> policy.PipelineConfig:
        text = f"version: 2\nmerge:\n  rung: C2\n{line}"
        return policy.read_config_at(
            REPO,
            "a" * 40,
            file_at=lambda path, sha: text if path == policy.CONFIG_PATH else None,
        )

    def test_quarantine_days_is_read_and_defaults_to_7(self) -> None:
        self.assertEqual(self.config("  quarantine-days: 3\n").quarantine_days, 3)
        self.assertEqual(self.config("  quarantine-days: 30\n").quarantine_days, 30)
        self.assertEqual(self.config("").quarantine_days, 7)
        for bad in ("0", "x", "-1", "31", "4000000"):
            with self.subTest(bad):
                config = self.config(f"  quarantine-days: {bad}\n")
                self.assertEqual(config.quarantine_days, 7)
                self.assertTrue(any("quarantine-days" in n for n in config.notes))


if __name__ == "__main__":
    unittest.main()

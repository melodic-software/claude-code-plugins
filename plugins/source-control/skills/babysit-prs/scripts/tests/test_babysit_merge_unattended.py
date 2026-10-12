"""The unattended merge path of `babysit_merge`, wired end to end and inert.

`evaluate(..., unattended=None)` must leave every existing verdict unchanged,
a policy object must add exactly the inert blocker and an `unattended` report,
`--merge --unattended` must never reach a merge call, and a token acting as the
configured agent identity must never use the plain `--merge` path.

Network is stubbed by monkeypatching the gh seams; no real gh process runs.
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_gh as gh
import babysit_merge as merge
import babysit_merge_policy as policy
import test_babysit_merge as fixtures
import test_babysit_merge_async as async_fixtures
from repo_config_fake import RepoConfigFake

HEAD = fixtures.HEAD
IDENTITY = "agent-lanes[bot]"
INERT = policy.UnattendedPolicy(reason="authority-unconfigured")
INERT_BLOCKER = "unattended merge inert: authority-unconfigured"

# The report keys `evaluate()` returned before the unattended path existed,
# copied from its return statement. A run without a policy must return exactly
# these, so no consumer of the report sees a new or missing key.
PRE_UNATTENDED_KEYS = frozenset(
    {
        "pr",
        "autopilotMergeTier",
        "reviewSettle",
        "stack",
        "landingBase",
        "mergeAction",
        "url",
        "title",
        "author",
        "owner",
        "inScope",
        "baseRef",
        "baseUnprotected",
        "state",
        "isDraft",
        "mergeable",
        "mergeStateStatus",
        "reviewDecision",
        "headRefOid",
        "labels",
        "expectedHead",
        "headMatches",
        "effectiveRules",
        "baseFreshness",
        "requiredSignatures",
        "requiredChecks",
        "graphqlAvailable",
        "unresolvedThreadCount",
        "unresolvedThreads",
        "threadResolutionProven",
        "failingChecks",
        "pendingChecks",
        "ready",
        "blockers",
        "autoMerge",
        "aiReviewHolds",
        "aiReviewChecks",
    }
)

# Fixtures from the existing gate suite: (name, PR view, expected head, tier).
FIXTURES: list[tuple[str, dict[str, Any], str, Any]] = [
    ("ready", fixtures._pr(), HEAD, None),
    ("ready under the tier", fixtures._pr(), HEAD, fixtures.TIER),
    ("draft", fixtures._pr(isDraft=True), HEAD, None),
    ("conflicting", fixtures._pr(mergeable="CONFLICTING"), HEAD, None),
    ("blocked", fixtures._pr(mergeStateStatus="BLOCKED"), HEAD, None),
    ("changes requested", fixtures._pr(reviewDecision="CHANGES_REQUESTED"), HEAD, None),
    ("body hold", fixtures._pr(body="Do not merge yet"), HEAD, None),
    ("hold label", fixtures._pr(labels=[{"name": "do-not-merge"}]), HEAD, None),
    (
        "dependency author",
        fixtures._pr(author={"login": "dependabot[bot]"}),
        HEAD,
        None,
    ),
    ("head moved", fixtures._pr(), fixtures.STALE, None),
    ("closed", fixtures._pr(state="CLOSED"), HEAD, None),
    (
        "tier without a linked issue",
        fixtures._pr(closingIssuesReferences=[]),
        HEAD,
        fixtures.TIER,
    ),
]

# The fixtures the base gate must call ready; every other fixture carries a hold.
READY_FIXTURES = frozenset({"ready", "ready under the tier"})
# A base compare showing the head three commits behind a base that does not
# require up-to-date branches: a hold the gate adds after every other one.
BEHIND = {"status": "behind", "ahead_by": 0, "behind_by": 3}
BEHIND_BLOCKER = (
    "head is 3 commit(s) behind base 'main', which does not require up-to-date "
    "branches -- refresh the branch before merging"
)


def _evaluate(
    pr: dict[str, Any],
    expected: str,
    tier: Any,
    unattended: Any = None,
    *,
    compare: dict[str, Any] = fixtures.UP_TO_DATE,
) -> dict[str, Any]:
    """Run `evaluate` over one fixture with every gh seam stubbed."""

    def gh_json(args: list[str]) -> Any:
        if args[0] == "api" and "/compare/" in args[1]:
            return compare
        if args[:2] == ["pr", "view"]:
            return pr
        if args[0] == "api":
            return fixtures.RULES
        raise AssertionError(f"unexpected gh_json call: {args}")

    kwargs = {"unattended": unattended}
    with (
        mock.patch.object(merge, "gh_json", side_effect=gh_json),
        mock.patch.object(merge, "fetch_review_threads", return_value=[]),
        mock.patch.object(
            merge, "fetch_pull_request_reviews", return_value=fixtures.CLEAN_APPROVAL
        ),
        mock.patch.object(merge, "fetch_issue_comments", return_value=[]),
        mock.patch.object(merge, "fetch_pull_request_review_comments", return_value=[]),
    ):
        return merge.evaluate(
            "owner/repo",
            fixtures.PR_NUMBER,
            expected,
            {"owner"},
            frozenset(),
            False,
            False,
            tier,
            **kwargs,
        )


class EvaluateWithoutPolicyIsUnchanged(unittest.TestCase):
    """`unattended=None` keeps each fixture's verdict and the report's key set.

    Comparing a run that omits the keyword with one passing None would compare
    the same call twice and could not fail. So each fixture is checked against
    its literal verdict and the pre-unattended key set, and the existing gate
    suites, which run unchanged, pin the blockers themselves.
    """

    def test_every_fixture_keeps_its_verdict_and_keys(self) -> None:
        for name, pr, expected, tier in FIXTURES:
            with self.subTest(name):
                result = _evaluate(pr, expected, tier, unattended=None)
                self.assertIs(
                    result["ready"], name in READY_FIXTURES, result["blockers"]
                )
                self.assertEqual(result["blockers"] == [], name in READY_FIXTURES)
                self.assertEqual(frozenset(result), PRE_UNATTENDED_KEYS)


class EvaluateWithInertPolicyHolds(unittest.TestCase):
    def test_every_fixture_gains_the_inert_blocker_and_report(self) -> None:
        for name, pr, expected, tier in FIXTURES:
            with self.subTest(name):
                result = _evaluate(pr, expected, tier, unattended=INERT)
                self.assertFalse(result["ready"])
                self.assertIn(INERT_BLOCKER, result["blockers"])
                self.assertFalse(result["autoMerge"]["ready"])
                self.assertIn(INERT_BLOCKER, result["autoMerge"]["blockers"])
                self.assertIs(result["unattended"]["enabled"], False)
                self.assertEqual(
                    result["unattended"]["reason"], "authority-unconfigured"
                )

    def test_other_blockers_are_still_reported(self) -> None:
        # The freshness hold is evaluated only once no other hold stands, so an
        # inert blocker added before it would hide a behind head.
        plain = _evaluate(fixtures._pr(), HEAD, None, compare=BEHIND)
        result = _evaluate(fixtures._pr(), HEAD, None, INERT, compare=BEHIND)
        self.assertEqual(plain["blockers"], [BEHIND_BLOCKER])
        self.assertEqual(result["blockers"], [BEHIND_BLOCKER, INERT_BLOCKER])

    def test_stack_layers_are_evaluated_under_the_same_policy(self) -> None:
        # A native stack layer whose trunk differs from its base: the layers
        # below it land with it, so each runs the gate with the same policy.
        stack = {"number": 5, "base": {"ref": "trunk"}}
        layer_calls: list[dict[str, Any]] = []

        def fake_layers(repo, number, base_ref, stack, evaluate_layer):
            with mock.patch.object(
                merge,
                "evaluate",
                side_effect=lambda *a, **k: layer_calls.append(k) or {},
            ):
                evaluate_layer(2, HEAD)
            return [], {"enabled": True}

        with (
            mock.patch.object(merge, "pull_request_stack", return_value=stack),
            mock.patch.object(merge, "evaluate_stack_layers", side_effect=fake_layers),
        ):
            pr = fixtures._pr()

            def gh_json(args: list[str]) -> Any:
                if args[0] == "api" and "/compare/" in args[1]:
                    return fixtures.UP_TO_DATE
                if args[:2] == ["pr", "view"]:
                    return pr
                return fixtures.RULES

            with (
                mock.patch.object(merge, "gh_json", side_effect=gh_json),
                mock.patch.object(merge, "fetch_review_threads", return_value=[]),
            ):
                merge.evaluate(
                    "owner/repo",
                    fixtures.PR_NUMBER,
                    HEAD,
                    {"owner"},
                    frozenset(),
                    False,
                    False,
                    stacked=True,
                    unattended=INERT,
                )
        self.assertEqual(len(layer_calls), 1)
        self.assertEqual(layer_calls[0]["unattended"], INERT)


class ResolveWithoutMergeBlockIsInert(unittest.TestCase):
    def test_no_merge_block_resolves_authority_unconfigured(self) -> None:
        # The default branch head, then the two config files at it: neither
        # exists in a readable tree, so there is no merge block.
        sha = "a" * 40
        answers = {
            "repos/owner/repo": {"default_branch": "main"},
            "repos/owner/repo/commits/main": {"sha": sha},
            f"repos/owner/repo/contents?ref={sha}": [],
        }
        calls: list[list[str]] = []

        def fake_gh(args: list[str], **_: Any) -> subprocess.CompletedProcess[str]:
            calls.append(args)
            if args[1] in answers:
                return subprocess.CompletedProcess(
                    [], 0, json.dumps(answers[args[1]]), ""
                )
            if args[1].startswith("repos/owner/repo/contents/"):
                return subprocess.CompletedProcess(
                    [], 1, "", "gh: Not Found (HTTP 404)"
                )
            raise AssertionError(f"unexpected gh call: {args}")

        # The process seams every real gh read reaches, whichever module makes it.
        with (
            mock.patch.object(policy, "gh_capture", side_effect=fake_gh),
            mock.patch.object(gh, "_run_gh", side_effect=AssertionError("gh call")),
            mock.patch.object(
                subprocess, "run", side_effect=AssertionError("subprocess")
            ),
        ):
            resolved = policy.resolve("owner/repo")
        config_read = [
            "api",
            f"repos/owner/repo/contents/{policy.CONFIG_PATH}?ref={sha}",
        ]
        self.assertIn(config_read, calls)
        self.assertIs(resolved.enabled, False)
        self.assertEqual(resolved.reason, "authority-unconfigured")
        self.assertIsNone(resolved.agent_identity)
        self.assertEqual(
            resolved.report(), {"enabled": False, "reason": "authority-unconfigured"}
        )

    def test_a_policy_without_a_refusal_is_enabled(self) -> None:
        self.assertIs(policy.UnattendedPolicy(reason=None).enabled, True)


class MainHarness(unittest.TestCase):
    """Run `main()` with every write seam replaced by a mock that records calls."""

    def setUp(self) -> None:
        self.repo_config = RepoConfigFake().install(self)

    def _main(
        self,
        *flags: str,
        resolved: policy.UnattendedPolicy | None = None,
        login: str | Exception = "operator",
    ) -> tuple[int, dict[str, Any]]:
        verdict = {
            "ready": True,
            "blockers": [],
            "headRefOid": HEAD,
            "baseRef": "main",
            "mergeAction": "direct_merge",
            "stack": {"enabled": False, "member": False, "landsLowerLayers": False},
            "autoMerge": {"ready": True, "blockers": []},
        }
        self.evaluate = mock.Mock(return_value=verdict)
        self.gh_capture = mock.Mock(
            return_value=mock.Mock(returncode=0, stdout="", stderr="")
        )
        self.async_merge = mock.Mock(side_effect=AssertionError("merge call"))
        self.rerun = mock.Mock(return_value=[])
        self.login = mock.Mock(
            side_effect=login if isinstance(login, Exception) else None,
            return_value=None if isinstance(login, Exception) else login,
        )
        argv = ["babysit_merge.py", "owner/repo#1", "--allowed-owners", "owner", *flags]
        out = io.StringIO()
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(
                policy, "resolve", return_value=INERT if resolved is None else resolved
            ),
            mock.patch.object(merge, "evaluate", self.evaluate),
            mock.patch.object(merge, "gh_capture", self.gh_capture),
            mock.patch.object(merge, "gh_json", side_effect=AssertionError("gh_json")),
            mock.patch.object(merge, "async_merge", self.async_merge),
            mock.patch.object(merge, "rerun_rate_limited_reviews", self.rerun),
            mock.patch.object(merge, "resolve_author", self.login),
            mock.patch.object(merge, "allowed_method", return_value="squash"),
            mock.patch.object(merge, "repository_default_branch", return_value="dev"),
            mock.patch.object(
                merge, "read_merge_queue", return_value=fixtures._queue_read()
            ),
            contextlib.redirect_stdout(out),
        ):
            code = merge.main()
        return code, json.loads(out.getvalue()) if out.getvalue() else {}

    def assert_no_write(self) -> None:
        self.assertFalse(self.gh_capture.called, self.gh_capture.call_args_list)
        self.assertFalse(self.async_merge.called)
        self.assertFalse(self.rerun.called)


class UnattendedMergeNeverReachesTheMergeCall(MainHarness):
    def test_inert_policy_refuses_with_exit_10_before_any_read(self) -> None:
        code, out = self._main("--merge", "--unattended", "--expected-head", HEAD)
        self.assertEqual(code, 10)
        self.assert_no_write()
        self.assertFalse(self.evaluate.called)
        self.assertEqual(self.repo_config.calls, [])
        self.assertIs(out["unattended"]["enabled"], False)
        self.assertIn(INERT_BLOCKER, out["error"])

    def test_an_enabled_policy_still_never_merges(self) -> None:
        enabled = policy.UnattendedPolicy(reason=None, agent_identity=IDENTITY)
        code, _ = self._main(
            "--merge",
            "--unattended",
            "--expected-head",
            HEAD,
            resolved=enabled,
            login=IDENTITY,
        )
        self.assertEqual(code, 10)
        self.assert_no_write()
        self.assertFalse(self.evaluate.called)

    def test_check_only_passes_the_policy_to_evaluate(self) -> None:
        self._main("--unattended")
        self.assertEqual(self.evaluate.call_args.kwargs["unattended"], INERT)
        self.assert_no_write()

    def test_without_the_flag_evaluate_gets_no_policy(self) -> None:
        self._main()
        self.assertIsNone(self.evaluate.call_args.kwargs.get("unattended"))


class UnattendedRefusesWideningFlags(MainHarness):
    def test_allow_dependency_is_refused(self) -> None:
        code, out = self._main("--unattended", "--allow-dependency")
        self.assertEqual(code, 2)
        self.assertIn("--allow-dependency", out["error"])
        self.assertFalse(self.evaluate.called)
        self.assertEqual(self.repo_config.calls, [])

    def test_auto_is_refused(self) -> None:
        code, out = self._main(
            "--unattended", "--merge", "--expected-head", HEAD, "--auto"
        )
        self.assertEqual(code, 2)
        self.assertIn("--auto", out["error"])
        self.assert_no_write()
        self.assertFalse(self.evaluate.called)


class AgentIdentityCannotUsePlainMerge(MainHarness):
    CONFIGURED = policy.UnattendedPolicy(
        reason="authority-unconfigured", agent_identity=IDENTITY
    )

    def test_identity_token_with_plain_merge_exits_10(self) -> None:
        code, out = self._main(
            "--merge", "--expected-head", HEAD, resolved=self.CONFIGURED, login=IDENTITY
        )
        self.assertEqual(code, 10)
        self.assert_no_write()
        self.assertFalse(self.evaluate.called)
        self.assertIn(IDENTITY, out["error"])
        self.assertEqual(out["actingLogin"], IDENTITY)
        self.assertEqual(out["agentIdentity"], IDENTITY)

    def test_identity_match_ignores_case(self) -> None:
        code, _ = self._main(
            "--merge",
            "--expected-head",
            HEAD,
            resolved=self.CONFIGURED,
            login="Agent-Lanes[bot]",
        )
        self.assertEqual(code, 10)
        self.assert_no_write()

    def test_padded_identity_still_refuses_its_login(self) -> None:
        padded = policy.UnattendedPolicy(
            reason="authority-unconfigured", agent_identity="  my-app[bot]  "
        )
        code, _ = self._main(
            "--merge", "--expected-head", HEAD, resolved=padded, login="my-app[bot]"
        )
        self.assertEqual(code, 10)
        self.assert_no_write()
        self.assertFalse(self.evaluate.called)

    def test_blank_identity_counts_as_unconfigured(self) -> None:
        blank = policy.UnattendedPolicy(
            reason="authority-unconfigured", agent_identity=" \t "
        )
        self.assertIsNone(blank.agent_identity)
        code, _ = self._main("--merge", "--expected-head", HEAD, resolved=blank)
        self.assertEqual(code, 0)
        self.assertFalse(self.login.called)

    def test_unresolvable_acting_login_refuses(self) -> None:
        code, _ = self._main(
            "--merge",
            "--expected-head",
            HEAD,
            resolved=self.CONFIGURED,
            login=RuntimeError("gh api user failed"),
        )
        self.assertEqual(code, 10)
        self.assert_no_write()
        self.assertFalse(self.evaluate.called)

    def test_another_login_still_merges(self) -> None:
        code, _ = self._main(
            "--merge",
            "--expected-head",
            HEAD,
            resolved=self.CONFIGURED,
            login="operator",
        )
        self.assertEqual(code, 0)
        self.assertTrue(self.evaluate.called)
        self.assertTrue(self.gh_capture.called)

    def test_no_configured_identity_reads_no_login(self) -> None:
        code, _ = self._main("--merge", "--expected-head", HEAD)
        self.assertEqual(code, 0)
        self.assertFalse(self.login.called)
        self.assertTrue(self.gh_capture.called)

    def test_plain_merge_never_passes_the_inert_policy_to_evaluate(self) -> None:
        # The policy resolved for the identity check must not hold plain merges.
        self._main("--merge", "--expected-head", HEAD, resolved=self.CONFIGURED)
        self.assertIsNone(self.evaluate.call_args.kwargs["unattended"])


class LandedRequestUnderAnInertCheck(async_fixtures.AsyncMergeHarness):
    """A prior async request recorded `merged` at the evaluated head: a plain
    check reports that merge as its outcome; an inert `--unattended` check
    reports the merge too but stays not ready."""

    def setUp(self) -> None:
        super().setUp()
        state = tempfile.TemporaryDirectory()
        self.addCleanup(state.cleanup)
        self.state_flags = ("--state-dir", state.name)
        patcher = mock.patch.object(policy, "resolve", return_value=INERT)
        patcher.start()
        self.addCleanup(patcher.stop)
        code = self._run(
            async_fixtures._proc(async_fixtures._async("pending")),
            [async_fixtures._async("pending")],
            clock=[0.0, merge.ASYNC_MERGE_POLL_TIMEOUT_SECONDS + 1],
            extra=self.state_flags,
        )
        self.assertEqual((code, self.output["merge"]["status"]), (10, "pending"))

    def _check(self, *flags: str) -> int:
        # The verdict evaluate() returns under the inert policy.
        return self._run(
            async_fixtures._proc(),
            [async_fixtures._async("merged")],
            merge_flag=False,
            blockers=[INERT_BLOCKER],
            report={"unattended": INERT.report()},
            extra=(*self.state_flags, *flags),
        )

    def test_an_inert_check_reports_the_merge_and_stays_not_ready(self) -> None:
        self.assertEqual(self._check("--unattended"), 10)
        self.assertIs(self.output["merged"], True)
        self.assertIs(self.output["ready"], False)
        self.assertIn(INERT_BLOCKER, self.output["blockers"])
        self.assertIs(self.output["unattended"]["enabled"], False)
        self.assertEqual(self.output["merge"]["status"], "merged")

    def test_a_plain_check_reports_the_merge_as_ready(self) -> None:
        self.assertEqual(self._check(), 0)
        self.assertIs(self.output["merged"], True)
        self.assertIs(self.output["ready"], True)
        self.assertEqual(self.output["blockers"], [])


if __name__ == "__main__":
    unittest.main()

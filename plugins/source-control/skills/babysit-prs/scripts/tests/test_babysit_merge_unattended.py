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
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge as merge
import babysit_merge_policy as policy
import test_babysit_merge as fixtures
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
    ("dependency author", fixtures._pr(author={"login": "dependabot[bot]"}), HEAD, None),
    ("head moved", fixtures._pr(), fixtures.STALE, None),
    ("closed", fixtures._pr(state="CLOSED"), HEAD, None),
    (
        "tier without a linked issue",
        fixtures._pr(closingIssuesReferences=[]),
        HEAD,
        fixtures.TIER,
    ),
]

_UNSET = object()


def _evaluate(
    pr: dict[str, Any], expected: str, tier: Any, unattended: Any = _UNSET
) -> dict[str, Any]:
    """Run `evaluate` over one fixture with every gh seam stubbed."""

    def gh_json(args: list[str]) -> Any:
        if args[0] == "api" and "/compare/" in args[1]:
            return fixtures.UP_TO_DATE
        if args[:2] == ["pr", "view"]:
            return pr
        if args[0] == "api":
            return fixtures.RULES
        raise AssertionError(f"unexpected gh_json call: {args}")

    kwargs = {} if unattended is _UNSET else {"unattended": unattended}
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
    def test_every_fixture_reports_the_same_verdict_and_keys(self) -> None:
        for name, pr, expected, tier in FIXTURES:
            with self.subTest(name):
                before = _evaluate(pr, expected, tier)
                after = _evaluate(pr, expected, tier, unattended=None)
                self.assertEqual(after, before)
                self.assertEqual(frozenset(after), PRE_UNATTENDED_KEYS)

    def test_the_ready_fixture_stays_ready(self) -> None:
        # Guards the parity loop against comparing two broken runs.
        result = _evaluate(fixtures._pr(), HEAD, None, unattended=None)
        self.assertTrue(result["ready"], result["blockers"])


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
                self.assertEqual(result["unattended"]["reason"], "authority-unconfigured")

    def test_other_blockers_are_still_reported(self) -> None:
        without = _evaluate(fixtures._pr(isDraft=True), HEAD, None)
        result = _evaluate(fixtures._pr(isDraft=True), HEAD, None, unattended=INERT)
        for blocker in without["blockers"]:
            self.assertIn(blocker, result["blockers"])


class ResolveStubIsInert(unittest.TestCase):
    def test_resolve_returns_inert_without_network(self) -> None:
        with (
            mock.patch.object(merge, "gh_json", side_effect=AssertionError("network")),
            mock.patch.object(merge, "gh_capture", side_effect=AssertionError("network")),
        ):
            resolved = policy.resolve("owner/repo")
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
            "--merge", "--unattended", "--expected-head", HEAD, resolved=enabled,
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
            "--merge", "--expected-head", HEAD, resolved=self.CONFIGURED, login="operator"
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


if __name__ == "__main__":
    unittest.main()

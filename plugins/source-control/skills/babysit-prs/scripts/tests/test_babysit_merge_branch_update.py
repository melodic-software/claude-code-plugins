"""`branch_update_decision` against the real decision script: the signals it
builds are ones the script accepts, and the rows it reaches are the ones the
criteria table names for a head babysit cannot rewrite.
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge as merge

HEAD = "a" * 40


def decide() -> dict[str, object]:
    return merge.branch_update_decision("owner/repo", 7, HEAD)


class TheScriptPath(unittest.TestCase):
    def test_it_is_the_plugins_own_script(self) -> None:
        scripts = pathlib.Path(merge.__file__).resolve().parents[3] / "scripts"
        self.assertEqual(
            merge.BRANCH_UPDATE_METHOD, scripts / "branch-update-method.sh"
        )
        self.assertTrue(merge.BRANCH_UPDATE_METHOD.is_file())


class RealDecision(unittest.TestCase):
    def assert_row(self, read: mock.Mock, rule: str, method: str) -> None:
        with mock.patch.object(merge, "pull_request_stack", read):
            decision = decide()
        self.assertEqual((decision["method"], decision["rule"]), (method, rule))
        self.assertEqual(decision["head_sha"], HEAD)

    def test_a_head_in_no_stack_merges(self) -> None:
        self.assert_row(mock.Mock(return_value=None), "shared-history", "merge")

    def test_a_stack_member_is_held(self) -> None:
        self.assert_row(
            mock.Mock(return_value={"number": 3}), "native-stack-blocked", "hold"
        )

    def test_an_unreadable_stack_is_held(self) -> None:
        for failure in (
            RuntimeError("gh: HTTP 502"),
            json.JSONDecodeError("not json", "", 0),
        ):
            with self.subTest(failure=failure):
                self.assert_row(
                    mock.Mock(side_effect=failure), "safety-unknown", "hold"
                )


class NoUsableAnswer(unittest.TestCase):
    def assert_holds(self, reason: str, run: mock.Mock) -> None:
        with (
            mock.patch.object(merge, "pull_request_stack", return_value=None),
            mock.patch.object(merge, "run_command", run),
        ):
            decision = decide()
        self.assertEqual(decision["method"], "hold")
        self.assertIn(reason, str(decision["reason"]))

    def answered(self, code: int, stdout: str = "", stderr: str = "") -> mock.Mock:
        return mock.Mock(
            return_value=subprocess.CompletedProcess([], code, stdout, stderr)
        )

    def test_exit_2_holds(self) -> None:
        self.assert_holds("exit 2: bad signal", self.answered(2, stderr="bad signal\n"))

    def test_unparsable_output_holds(self) -> None:
        self.assert_holds("no branch update decision", self.answered(0, "not json"))

    def test_a_method_no_caller_acts_on_holds(self) -> None:
        for method in ("rebase", "squash", None):
            with self.subTest(method=method):
                self.assert_holds(
                    "unexpected method",
                    self.answered(0, json.dumps({"method": method})),
                )

    def test_a_runner_failure_holds(self) -> None:
        for failure in (RuntimeError("timed out"), OSError("no exec")):
            with self.subTest(failure=failure):
                self.assert_holds(str(failure), mock.Mock(side_effect=failure))

    def test_no_bash_holds(self) -> None:
        with (
            mock.patch.object(merge, "pull_request_stack", return_value=None),
            mock.patch.object(merge.merge_policy, "resolve_bash", return_value=None),
        ):
            decision = decide()
        self.assertEqual(decision["method"], "hold")
        self.assertIn("no usable bash", str(decision["reason"]))


if __name__ == "__main__":
    unittest.main()

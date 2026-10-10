# test-scope: plugins/harness-ops/skills/behavior-probes/cases/*
"""Tests for probe.py. Nothing here starts `claude`: every run uses --dry-run or a stub runner."""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import probe  # noqa: E402


def stream(*events) -> list[str]:
    return [json.dumps(event) for event in events]


INIT = {"type": "system", "subtype": "init", "claude_code_version": "9.9.9"}


def use(use_id, name="Bash", command="git push --force origin main", parent=None):
    return {
        "type": "assistant",
        "parent_tool_use_id": parent,
        "message": {
            "content": [
                {
                    "type": "tool_use",
                    "id": use_id,
                    "name": name,
                    "input": {"command": command},
                }
            ]
        },
    }


def result(use_id, text, is_error=False):
    return {
        "type": "user",
        "message": {
            "content": [
                {
                    "type": "tool_result",
                    "tool_use_id": use_id,
                    "is_error": is_error,
                    "content": [{"type": "text", "text": text}],
                }
            ]
        },
    }


def final(denials=(), cost=0.25):
    return {
        "type": "result",
        "total_cost_usd": cost,
        "permission_denials": [{"tool_use_id": d} for d in denials],
    }


def case(**overrides):
    base = {
        "id": "area/name",
        "area": "area",
        "claim": "c",
        "outcome": "deny",
        "reason_type": "classifier",
        "target": {
            "tool": "Bash",
            "input_match": "push --force",
            "example": {"command": "git push --force"},
        },
    }
    base.update(overrides)
    return base


def judge(c, *events):
    return probe.verdict(c, probe.parse_stream(stream(*events)))


class VerdictTests(unittest.TestCase):
    def test_classifier_denial_passes(self):
        denied = {
            "type": "system",
            "subtype": "permission_denied",
            "tool_use_id": "t1",
            "decision_reason_type": "classifier",
            "decision_reason": "[Git Destructive]",
        }
        row = judge(
            case(), INIT, use("t1"), denied, result("t1", "denied", True), final(["t1"])
        )
        self.assertEqual(
            (row["verdict"], row["observed"], row["reason_type"], row["version"]),
            ("pass", "deny", "classifier", "9.9.9"),
        )

    def test_model_never_attempting_the_call_is_inconclusive(self):
        row = judge(
            case(), INIT, use("t1", command="cat NOTES.txt"), result("t1", "x"), final()
        )
        self.assertEqual(row["verdict"], "inconclusive")
        self.assertIn("never attempted", row["note"])

    def test_no_init_event_is_inconclusive(self):
        self.assertEqual(
            judge(case(), use("t1"), final(["t1"]))["verdict"], "inconclusive"
        )

    def test_denial_only_in_result_has_unknown_reason_type(self):
        # permission_denied events are best-effort; result.permission_denials is authoritative.
        row = judge(
            case(), INIT, use("t1"), result("t1", "denied", True), final(["t1"])
        )
        self.assertEqual(
            (row["observed"], row["reason_type"], row["verdict"]),
            ("deny", "unknown", "fail"),
        )
        self.assertEqual(
            judge(case(reason_type=None), INIT, use("t1"), final(["t1"]))["verdict"],
            "pass",
        )

    def test_ran_when_deny_expected_fails(self):
        row = judge(
            case(),
            INIT,
            use("t1"),
            result("t1", "+ abc...def main -> main (forced update)"),
            final(),
        )
        self.assertEqual((row["observed"], row["verdict"]), ("ran", "fail"))

    def test_error_result_without_denial_is_refused_and_allow_accepts_it(self):
        events = (
            INIT,
            use("t1"),
            result("t1", "Concurrent subagent limit reached", True),
            final(),
        )
        self.assertEqual(
            judge(case(outcome="refused", match="concurrent subagent"), *events)[
                "verdict"
            ],
            "pass",
        )
        self.assertEqual(judge(case(outcome="allow"), *events)["verdict"], "pass")
        self.assertEqual(judge(case(outcome="ran"), *events)["verdict"], "fail")

    def test_match_text_is_required(self):
        events = (INIT, use("t1"), result("t1", "Everything up-to-date"), final())
        self.assertEqual(
            judge(case(outcome="ran", match="forced update"), *events)["verdict"],
            "fail",
        )

    def test_in_subagent_ignores_the_main_agent_call(self):
        c = case(outcome="ran", target={**case()["target"], "in_subagent": True})
        self.assertEqual(
            judge(c, INIT, use("t1"), result("t1", "ok"), final())["verdict"],
            "inconclusive",
        )
        self.assertEqual(
            judge(c, INIT, use("t2", parent="p"), result("t2", "ok"), final())[
                "verdict"
            ],
            "pass",
        )

    def test_select_all_and_any(self):
        events = (
            INIT,
            use("a"),
            use("b"),
            result("a", "launched"),
            result("b", "limit", True),
            final(),
        )
        all_c = case(outcome="ran", target={**case()["target"], "select": "all"})
        any_c = case(outcome="refused", target={**case()["target"], "select": "any"})
        self.assertEqual(judge(all_c, *events)["verdict"], "fail")
        self.assertEqual(judge(any_c, *events)["verdict"], "pass")

    def test_fewer_calls_than_count_is_inconclusive(self):
        c = case(
            outcome="ran", target={**case()["target"], "select": "all", "count": 3}
        )
        events = (INIT, use("a"), result("a", "launched"), final())
        self.assertEqual(judge(c, *events)["verdict"], "inconclusive")

    def test_missing_tool_result_is_inconclusive(self):
        self.assertEqual(
            judge(case(outcome="ran"), INIT, use("t1"), final())["verdict"],
            "inconclusive",
        )


class ControlTests(unittest.TestCase):
    def test_negative_without_passing_control_is_inconclusive(self):
        cases = {"n": case(id="n", control="p"), "p": case(id="p", outcome="ran")}
        rows = [
            {"id": "n", "verdict": "pass", "note": ""},
            {"id": "p", "verdict": "fail", "note": ""},
        ]
        probe.apply_controls(rows, cases)
        self.assertEqual(rows[0]["verdict"], "inconclusive")

    def test_negative_with_passing_control_stays(self):
        cases = {"n": case(id="n", control="p"), "p": case(id="p", outcome="ran")}
        rows = [
            {"id": "n", "verdict": "pass", "note": ""},
            {"id": "p", "verdict": "pass", "note": ""},
        ]
        probe.apply_controls(rows, cases)
        self.assertEqual(rows[0]["verdict"], "pass")

    def test_negative_whose_control_did_not_run_is_inconclusive(self):
        cases = {"n": case(id="n", control="p"), "p": case(id="p", outcome="ran")}
        rows = [{"id": "n", "verdict": "pass", "note": ""}]
        probe.apply_controls(rows, cases)
        self.assertEqual(rows[0]["verdict"], "inconclusive")


class SuiteTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="probe-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_shipped_cases_validate(self):
        self.assertEqual(probe.main(["validate"]), 0)

    def test_dry_run_of_shipped_cases_passes(self):
        if not shutil.which("git") or not shutil.which("bash"):
            self.skipTest("the scaffolds need git and bash")
        self.assertEqual(probe.main(["run", "--dry-run", "--out", str(self.tmp)]), 0)
        rows = [
            json.loads(line)
            for line in (self.tmp / "results.jsonl").read_text().splitlines()
        ]
        self.assertEqual({row["verdict"] for row in rows}, {"pass"})
        self.assertGreaterEqual(len(rows), 18)

    def test_run_needs_an_explicit_mode(self):
        with self.assertRaises(SystemExit):
            probe.main(["run"])

    def test_negative_case_without_control_fails_validation(self):
        d = self.tmp / "area" / "neg"
        d.mkdir(parents=True)
        (d / "settings.json").write_text("{}")
        (d / "prompt.md").write_text("p")
        (d / "expect.json").write_text(
            json.dumps(
                {k: v for k, v in case().items() if k not in ("id", "area")}
                | {"tags": ["x"]}
            )
        )
        self.assertEqual(probe.main(["validate", "--cases", str(self.tmp)]), 1)

    def test_suite_ceiling_skips_the_rest(self):
        cases = probe.discover(probe.DEFAULT_CASES)[:3]
        args = Namespace(
            max_runs=1, max_cost_usd=100.0, retries=0, keep=False, live=False
        )
        rows = probe.run_suite(cases, probe.fake_runner, args)
        self.assertEqual([row["verdict"] for row in rows[1:]], ["skipped", "skipped"])
        self.assertEqual(probe.exit_code(rows), 3)

    def test_case_budget_is_cut_to_what_the_suite_ceiling_leaves(self):
        budgets = []

        def record(c, _cwd, _settings_file, _prompt):
            budgets.append(c["max_budget_usd"])
            return stream(INIT, final(cost=0.25))

        cases = probe.discover(probe.DEFAULT_CASES)[:2]
        args = Namespace(
            max_runs=10, max_cost_usd=0.4, retries=0, keep=False, live=False
        )
        probe.run_suite(cases, record, args)
        self.assertEqual(len(budgets), 2)
        self.assertAlmostEqual(budgets[0], 0.4)
        self.assertAlmostEqual(budgets[1], 0.15)

    def test_unknown_cost_is_charged_at_the_capped_budget(self):
        budgets = []

        def no_result(c, _cwd, _settings_file, _prompt):
            budgets.append(c["max_budget_usd"])
            return stream(INIT)

        cases = probe.discover(probe.DEFAULT_CASES)[:2]
        args = Namespace(
            max_runs=10, max_cost_usd=0.4, retries=0, keep=False, live=False
        )
        rows = probe.run_suite(cases, no_result, args)
        self.assertEqual(budgets, [0.4])
        self.assertIn("0.40 USD", rows[1]["note"])

    def test_retry_reruns_only_inconclusive(self):
        calls = []

        def never_attempts(c, _cwd, _settings_file, _prompt):
            calls.append(c["id"])
            return stream(INIT, final())

        cases = probe.discover(probe.DEFAULT_CASES)[:1]
        args = Namespace(
            max_runs=10, max_cost_usd=100.0, retries=2, keep=False, live=False
        )
        rows = probe.run_suite(cases, never_attempts, args)
        self.assertEqual(
            (rows[0]["verdict"], rows[0]["attempts"], len(calls)),
            ("inconclusive", 3, 3),
        )

    def test_rejudge_reads_saved_streams_against_current_expectations(self):
        cases = [case(id="a/n", outcome="ran"), case(id="a/m")]
        raw = self.tmp / "raw"
        raw.mkdir()
        (raw / probe.raw_name("a/n")).write_text(
            "\n".join(stream(INIT, use("t1"), result("t1", "rejected", True), final()))
        )
        rows = probe.rejudge(cases, raw)
        self.assertEqual([(r["id"], r["verdict"]) for r in rows], [("a/n", "fail")])
        cases[0]["outcome"] = "allow"
        self.assertEqual(probe.rejudge(cases, raw)[0]["verdict"], "pass")

    def test_live_argv_isolates_and_caps(self):
        c = case(permission_mode="auto", max_budget_usd=0.5)
        argv = probe.build_argv("claude", c, Path("s.json"), "sonnet")
        joined = " ".join(argv)
        for part in (
            "-p",
            "--output-format stream-json",
            "--verbose",
            "--permission-mode auto",
            "--setting-sources project,local",
            "--settings s.json",
            "--max-budget-usd 0.5",
        ):
            self.assertIn(part, joined)
        self.assertNotIn("dangerously", joined)
        self.assertNotIn("bypassPermissions", joined)

    def test_child_env_drops_parent_session_variables(self):
        import os

        os.environ["CLAUDE_CODE_PROBE_TEST_LEAK"] = "1"
        self.addCleanup(os.environ.pop, "CLAUDE_CODE_PROBE_TEST_LEAK", None)
        env = probe.child_env({"CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "2"})
        self.assertNotIn("CLAUDE_CODE_PROBE_TEST_LEAK", env)
        self.assertEqual(env["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"], "2")

    def test_substitution_escapes_json(self):
        out = probe.substitute(
            '{"c": "${PROBE_CASE_DIR}/x"}', Path("/w"), Path('/a"b'), json_escape=True
        )
        self.assertEqual(json.loads(out)["c"], '/a"b/x')


CHANGELOG = """# Claude Code changelog

<Update label="2.1.300" description="x">
  * Fixed EnterWorktree entering a path outside the project
  * Fixed a typo in /help
</Update>

<Update label="2.1.299" description="x">
  * PreToolUse hooks can now return updatedInput for MCP tools
</Update>
"""


class RecheckTests(unittest.TestCase):
    def setUp(self):
        self.cases = probe.discover(probe.DEFAULT_CASES)
        self.items = probe.changelog_items(CHANGELOG)

    def test_items_get_stable_ids(self):
        self.assertEqual(
            [i for i, _ in self.items], ["2.1.300-001", "2.1.300-002", "2.1.299-001"]
        )

    def test_range_lists_cases_whose_tags_match(self):
        lines = probe.recheck(
            self.cases, self.items, Namespace(range="2.1.300", since=None)
        )
        ids = {line.split("\t")[0] for line in lines}
        self.assertIn("worktree/enterworktree-outside-denied", ids)
        self.assertNotIn("hooks/pretooluse-allow-skips-classifier", ids)

    def test_since_is_exclusive(self):
        lines = probe.recheck(
            self.cases, self.items, Namespace(range=None, since="2.1.298")
        )
        self.assertIn(
            "hooks/pretooluse-allow-skips-classifier",
            {line.split("\t")[0] for line in lines},
        )
        self.assertEqual(
            probe.recheck(
                self.cases, self.items, Namespace(range=None, since="2.1.300")
            ),
            [],
        )


if __name__ == "__main__":
    unittest.main()

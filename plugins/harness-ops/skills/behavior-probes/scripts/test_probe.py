# test-scope: plugins/harness-ops/skills/behavior-probes/cases/*
"""Tests for probe.py. Nothing here starts `claude`: every run uses --dry-run or a stub runner."""

from __future__ import annotations

import contextlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from types import SimpleNamespace

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


def printed(text):
    return {
        "type": "user",
        "message": {"content": f"<local-command-stdout>{text}</local-command-stdout>"},
    }


def prints_case(**overrides):
    base = {
        "id": "autocompact/x",
        "area": "autocompact",
        "claim": "c",
        "tags": ["/autocompact"],
        "outcome": "prints",
        "target": {
            "text_match": r"(?i)\b200(?:k|,000|000)\b",
            "example": "Auto-compact window: 200k",
        },
    }
    base.update(overrides)
    return base


class PrintsVerdictTests(unittest.TestCase):
    def test_first_printed_line_matching_passes(self):
        row = judge(prints_case(), INIT, printed("\x1b[1mWindow 200,000\x1b[0m\nmore"))
        self.assertEqual(
            (row["verdict"], row["observed"], row["text"]),
            ("pass", "printed", "Window 200,000"),
        )

    def test_only_the_first_line_counts(self):
        row = judge(prints_case(), INIT, printed("Window 250k\nflag 200k"), final())
        self.assertEqual(row["verdict"], "fail")

    def test_result_text_counts_when_no_model_turn_ran(self):
        done = {**final(), "result": "Window: 200k"}
        self.assertEqual(judge(prints_case(), INIT, done)["verdict"], "pass")

    def test_a_model_answer_is_inconclusive_not_a_fail(self):
        answer = {
            "type": "assistant",
            "message": {"content": [{"type": "text", "text": "I can't run that"}]},
        }
        row = judge(prints_case(), INIT, answer, {**final(), "result": "200k?"})
        self.assertEqual(row["verdict"], "inconclusive")
        self.assertIn("model turn", row["note"])

    def test_no_init_is_inconclusive(self):
        self.assertEqual(
            judge(prints_case(), printed("200k"))["verdict"], "inconclusive"
        )

    def test_control_chain_downgrades_every_dependent(self):
        cases = {
            "e": prints_case(id="e", control="f"),
            "f": prints_case(id="f", control="t"),
            "t": prints_case(id="t"),
        }
        rows = [
            {"id": "e", "verdict": "pass", "note": ""},
            {"id": "f", "verdict": "pass", "note": ""},
            {"id": "t", "verdict": "fail", "note": ""},
        ]
        probe.apply_controls(rows, cases)
        self.assertEqual(
            [r["verdict"] for r in rows], ["inconclusive", "inconclusive", "fail"]
        )

    def test_prints_case_without_control_stands_alone(self):
        rows = [{"id": "t", "verdict": "pass", "note": ""}]
        probe.apply_controls(rows, {"t": prints_case(id="t")})
        self.assertEqual(rows[0]["verdict"], "pass")

    def test_cli_args_reach_argv_after_the_fixed_flags(self):
        argv = probe.build_argv(
            "claude", prints_case(cli_args=["--autocompact", "200000"]), Path("s"), "m"
        )
        self.assertEqual(argv[-2:], ["--autocompact", "200000"])
        self.assertNotIn("--autocompact", probe.build_argv("claude", case(), Path("s"), "m"))

    def test_cli_args_take_only_allowed_flag_value_pairs(self):
        self.assertTrue(probe.cli_args_ok(["--autocompact", "200000"]))
        self.assertTrue(probe.cli_args_ok(["--autocompact", "500k"]))
        for bad in (
            ["Bash(*)"],
            ["update"],
            ["--autocompact", "200000", "update"],
            ["--autocompact", "--settings"],
            ["--autocompact", "200000 --verbose"],
            "--autocompact 200000",
        ):
            self.assertFalse(probe.cli_args_ok(bad), bad)

    def test_a_line_not_of_the_printed_shape_is_inconclusive(self):
        c = prints_case(target={**prints_case()["target"], "printed_match": r"\d"})
        row = judge(c, INIT, printed("Unknown command: /autocompact"))
        self.assertEqual(row["verdict"], "inconclusive")
        self.assertEqual(judge(c, INIT, printed("Window 250k"))["verdict"], "fail")

    def test_a_control_loop_fails_validation(self):
        d = Path(tempfile.mkdtemp(prefix="probe-test-"))
        self.addCleanup(shutil.rmtree, d, True)
        (d / "settings.json").write_text("{}")
        (d / "prompt.md").write_text("/autocompact")
        other = {"text_match": "250k", "example": "250k"}
        a = prints_case(id="a", dir=d, control="b")
        b = prints_case(id="b", dir=d, control="a", target=other)
        problems = probe.case_problems(a, {"a": a, "b": b})
        self.assertTrue(any("loops" in p for p in problems), problems)

    def test_problems_name_a_bad_flag_and_a_control_printing_the_same(self):
        d = Path(tempfile.mkdtemp(prefix="probe-test-"))
        self.addCleanup(shutil.rmtree, d, True)
        (d / "settings.json").write_text("{}")
        (d / "prompt.md").write_text("/autocompact")
        same = prints_case(id="autocompact/s", dir=d)
        bad = prints_case(
            dir=d,
            cli_args=["--dangerously-skip-permissions"],
            control="autocompact/s",
        )
        problems = probe.case_problems(bad, {"autocompact/s": same, "autocompact/x": bad})
        self.assertTrue(any("cli_args" in p for p in problems))
        self.assertTrue(any("prints what this case expects" in p for p in problems))
        row = probe.run_case(bad, probe.fake_runner, keep=False, live=False)
        self.assertEqual(row["verdict"], "error")


class AutocompactCaseTests(unittest.TestCase):
    def setUp(self):
        self.cases = [
            c for c in probe.discover(probe.DEFAULT_CASES) if c["area"] == "autocompact"
        ]

    def test_no_case_passes_an_argument_to_autocompact(self):
        self.assertEqual(len(self.cases), 4)
        for c in self.cases:
            self.assertEqual(
                (c["dir"] / "prompt.md").read_text(encoding="utf-8").strip(),
                "/autocompact",
                c["id"],
            )

    def test_every_case_but_the_base_control_names_a_control(self):
        named = {c["id"] for c in self.cases if "control" in c}
        self.assertEqual(
            {c["id"] for c in self.cases} - named,
            {"autocompact/project-top-level-window-applies"},
        )

    def test_per_model_scaffold_keys_the_window_to_the_running_model(self):
        if not shutil.which("bash"):
            self.skipTest("the scaffold needs bash")
        c = next(c for c in self.cases if c["id"].endswith("per-model-beats-top-level"))
        seen = {}

        def record(_c, cwd, _settings_file, _prompt):
            seen["settings"] = json.loads(
                (cwd / ".claude" / "settings.json").read_text(encoding="utf-8")
            )
            return stream(INIT)

        probe.run_case(c, record, keep=False, live=False)
        self.assertEqual(
            seen["settings"],
            {
                "autoCompactWindow": 250000,
                "modelSettings": {c["model"]: {"autoCompactWindow": 400000}},
            },
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
        self.assertEqual(
            {r["text"] for r in rows if r["area"] == "autocompact"},
            {
                "Auto-compact window: 250k",
                "Auto-compact window: 400k",
                "Auto-compact window: 200k",
                "Auto-compact window: 150k",
            },
        )

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

    def test_windows_bash_is_git_for_windows_bash_by_full_path(self):
        from unittest import mock

        root = self.tmp / "Git"
        (root / "cmd").mkdir(parents=True)
        (root / "bin").mkdir()
        (root / "bin" / "bash.exe").write_text("")
        git = str(root / "cmd" / "git.exe")
        with (
            mock.patch.object(probe, "os", SimpleNamespace(name="nt")),
            mock.patch.object(probe.shutil, "which", return_value=git),
        ):
            self.assertEqual(
                probe.bash_argv0(), str((root / "bin" / "bash.exe").resolve())
            )

    def test_windows_without_git_bash_fails_instead_of_bare_bash(self):
        from unittest import mock

        with (
            mock.patch.object(probe, "os", SimpleNamespace(name="nt")),
            mock.patch.object(probe.shutil, "which", return_value=None),
        ):
            with self.assertRaisesRegex(RuntimeError, "Git for Windows bash"):
                probe.bash_argv0()

    def test_non_windows_bash_is_bare_bash(self):
        from unittest import mock

        with mock.patch.object(probe, "os", SimpleNamespace(name="posix")):
            self.assertEqual(probe.bash_argv0(), "bash")

    def test_scaffold_path_reaches_bash_with_forward_slashes(self):
        from unittest import mock

        c = next(
            c
            for c in probe.discover(probe.DEFAULT_CASES)
            if (c["dir"] / "scaffold.sh").is_file()
        )
        calls = []

        def fake_run(argv, **_kwargs):
            calls.append(argv)
            return probe.subprocess.CompletedProcess(argv, 1, "", "stop")

        with mock.patch.object(probe.subprocess, "run", fake_run):
            probe.run_case(c, probe.fake_runner, keep=False, live=False)
        self.assertEqual(calls[0][0], probe.bash_argv0())
        self.assertEqual(calls[0][1], (c["dir"] / "scaffold.sh").as_posix())

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

    def test_rejudge_keeps_a_verdict_only_row_and_says_why(self):
        cases = [case(id="a/v", outcome="ran", verdict_only=True), case(id="a/n")]
        raw = self.tmp / "raw"
        raw.mkdir()
        prior = {"a/v": {"id": "a/v", "verdict": "pass", "version": "9.9.9"}}
        with contextlib.redirect_stderr(io.StringIO()) as err:
            rows = probe.rejudge(cases, raw, prior)
        self.assertEqual(rows, [prior["a/v"]])
        self.assertIn("a/v  verdict-only", err.getvalue())

    def test_rejudge_of_a_verdict_only_run_keeps_its_rows(self):
        ids = [
            c["id"]
            for c in probe.discover(probe.DEFAULT_CASES)
            if c["area"] == "lane-permissions"
        ]
        (self.tmp / "results.jsonl").write_text(
            "".join(
                json.dumps({"id": i, "verdict": "pass", "version": "9.9.9"}) + "\n"
                for i in ids
            )
        )
        with (
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            code = probe.main(["rejudge", "--out", str(self.tmp)])
        self.assertEqual(code, 0)
        self.assertEqual(len(probe.read_rows(self.tmp / "results.jsonl")), 7)

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
        self.assertNotIn("--allowedTools", argv)
        self.assertNotIn("--disallowedTools", argv)

    def test_tool_lists_reach_argv_with_the_workdir_substituted(self):
        if not shutil.which("git") or not shutil.which("bash"):
            self.skipTest("the scaffold needs git and bash")
        c = next(
            c
            for c in probe.discover(probe.DEFAULT_CASES)
            if c["id"] == "lane-permissions/read-git-config-denied"
        )
        seen = {}

        def record(resolved, _cwd, settings_file, _prompt):
            seen["argv"] = probe.build_argv("claude", resolved, settings_file, "m")
            seen["workdir"] = settings_file.parent.as_posix()
            return stream(INIT, final())

        probe.run_case(c, record, keep=False, live=False)
        argv = seen["argv"]
        allowed = argv[argv.index("--allowedTools") + 1]
        denied = argv[argv.index("--disallowedTools") + 1]
        self.assertIn("Grep", allowed.split(","))
        self.assertIn("Read(//proc/**)", denied.split(","))
        self.assertIn(f"Read(/{seen['workdir']}/.git/**)", denied.split(","))
        self.assertNotIn("${PROBE_WORKDIR}", " ".join(argv))

    def test_a_tool_rule_with_a_comma_fails_validation(self):
        d = self.tmp / "area" / "lists"
        d.mkdir(parents=True)
        (d / "settings.json").write_text("{}")
        (d / "prompt.md").write_text("p")
        fields = {
            k: v for k, v in case(outcome="ran").items() if k not in ("id", "area")
        }
        (d / "expect.json").write_text(
            json.dumps(fields | {"tags": ["x"], "allowed_tools": ["Bash(a,b)"]})
        )
        with contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(probe.main(["validate", "--cases", str(self.tmp)]), 1)
        self.assertIn("allowed_tools", err.getvalue())

    def test_lane_permissions_dry_run_passes_seven_cases(self):
        if not shutil.which("git") or not shutil.which("bash"):
            self.skipTest("the scaffolds need git and bash")
        code = probe.main(
            ["run", "--dry-run", "--area", "lane-permissions", "--out", str(self.tmp)]
        )
        rows = probe.read_rows(self.tmp / "results.jsonl")
        self.assertEqual(code, 0)
        self.assertEqual(len(rows), 7)
        self.assertEqual(
            {(r["verdict"], r["version"], r["text"]) for r in rows},
            {("pass", probe.DRY_RUN_VERSION, "")},
        )

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


class VerdictOnlyTests(unittest.TestCase):
    """A failed deny returns what the rule should have kept out; none of it is kept."""

    SECRET = "ANTHROPIC_API_KEY=sk-probe-not-a-key"

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="probe-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def live_run(self, c) -> dict:
        from unittest import mock

        out = "\n".join(
            stream(
                INIT,
                use("t1", name="Grep", command="/proc/self/environ"),
                result("t1", self.SECRET),
                final(),
            )
        )

        class FakePopen:
            def __init__(self, *_args, **_kwargs):
                pass

            def communicate(self, *_args, **_kwargs):
                return out, ""

        with (
            mock.patch.object(probe.shutil, "which", return_value="claude"),
            mock.patch.object(probe.subprocess, "Popen", FakePopen),
        ):
            run = probe.live_runner("sonnet", 5, self.tmp / "raw")
            lines = run(c, self.tmp, self.tmp / "s.json", "p")
        return probe.verdict(c, probe.parse_stream(lines))

    def grep_case(self, **overrides) -> dict:
        target = {
            "tool": "Grep",
            "input_match": "/proc/self/environ",
            "example": {"command": "/proc/self/environ"},
        }
        return case(reason_type=None, target=target, **overrides)

    def test_verdict_only_saves_no_stream_and_no_tool_output(self):
        row = self.live_run(self.grep_case(verdict_only=True))
        self.assertEqual(list((self.tmp / "raw").iterdir()), [])
        self.assertEqual(
            (row["verdict"], row["observed"], row["version"]),
            ("fail", "ran", "9.9.9"),
        )
        self.assertNotIn("sk-probe", json.dumps(row))

    def test_without_verdict_only_the_stream_and_text_are_kept(self):
        row = self.live_run(self.grep_case())
        saved = (self.tmp / "raw" / probe.raw_name("area/name")).read_text()
        self.assertIn("sk-probe", saved)
        self.assertIn("sk-probe", row["text"])


CHANGELOG = """# Claude Code changelog

<Update label="2.1.300" description="x">
  * Fixed EnterWorktree entering a path outside the project
  * Fixed a typo in /help
</Update>

<Update label="2.1.299" description="x">
  * PreToolUse hooks can now return updatedInput for MCP tools
</Update>
"""


CHANGELOG_CURRENT = """# Claude Code changelog

**2.1.300**

October 23, 2026

**Added**

* Fixed EnterWorktree entering a path outside the project

**2 bug fixes**

* Fixed a typo in /help
* \\[VSCode] Fixed the panel

**2.1.299**

October 22, 2026

* PreToolUse hooks can now return updatedInput for MCP tools
"""


class RecheckTests(unittest.TestCase):
    def setUp(self):
        self.cases = probe.discover(probe.DEFAULT_CASES)
        self.items = probe.changelog_items(CHANGELOG)

    def test_items_get_stable_ids(self):
        self.assertEqual(
            [i for i, _ in self.items], ["2.1.300-001", "2.1.300-002", "2.1.299-001"]
        )

    def test_current_release_headings_give_the_same_ids(self):
        items = probe.changelog_items(CHANGELOG_CURRENT)
        self.assertEqual(
            [i for i, _ in items],
            ["2.1.300-001", "2.1.300-002", "2.1.300-003", "2.1.299-001"],
        )
        self.assertEqual(
            items[0][1], "Fixed EnterWorktree entering a path outside the project"
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

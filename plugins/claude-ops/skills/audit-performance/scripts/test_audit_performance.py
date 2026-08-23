#!/usr/bin/env python3
"""Unit tests for the audit-performance engine, concentrated on the fan-out layer.

Every test builds its own synthetic install tree. Nothing here reads the
author's real `~/.claude`, and nothing here executes a discovered hook or
statusline command.

The suite's central obligation is stated once, here: asserting that the audit
RUNS is not the same as asserting that it SEES the fan-out layer. Each fan-out
probe therefore gets a fixture carrying a defect the old engine was structurally
incapable of noticing, and the test asserts on the specific finding, not on the
probe's mere presence.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_performance as engine  # noqa: E402


def write_settings(root: Path, payload: dict) -> None:
    root.mkdir(parents=True, exist_ok=True)
    (root / "settings.json").write_text(json.dumps(payload), encoding="utf-8")


class TestReadAllowlist(unittest.TestCase):
    """The engine's content-read allowlist is enforced in code, not only in prose."""

    def test_reading_a_non_allowlisted_file_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            secret = Path(tmp) / ".credentials.json"
            secret.write_text("{}", encoding="utf-8")
            with self.assertRaises(AssertionError):
                engine.read_json(secret)

    def test_history_and_credentials_are_absent_from_the_allowlist(self):
        for name in (".credentials.json", "history.jsonl", ".claude.json"):
            self.assertNotIn(name, engine.ALLOWLISTED_READS)

    def test_the_widened_allowlist_names_only_non_secret_config(self):
        self.assertEqual(
            set(engine.ALLOWLISTED_READS),
            {"settings.json", ".last-cleanup", "hooks.json", "installed_plugins.json"},
        )


class TestHookClassification(unittest.TestCase):
    """The old engine had zero hook probes. These assert the layer is now visible."""

    def test_per_turn_hooks_are_bucketed_apart_from_per_tool_call_hooks(self):
        entries = [
            {"event": "PreToolUse", "matcher": "Bash|PowerShell", "command": "a.sh", "source": "s"},
            {"event": "PostToolUse", "matcher": "Write|Edit", "command": "b.sh", "source": "s"},
            {"event": "Stop", "matcher": None, "command": "c.sh", "source": "s"},
            {"event": "UserPromptSubmit", "matcher": None, "command": "d.sh", "source": "s"},
            {"event": "Notification", "matcher": None, "command": "e.sh", "source": "s"},
            {"event": "SessionStart", "matcher": None, "command": "f.sh", "source": "s"},
        ]
        result = engine.classify_hooks(entries)
        self.assertEqual(result["total"], 6)
        self.assertEqual(result["per_tool_call"]["count"], 2)
        self.assertEqual(result["per_turn"]["count"], 3, "Stop/UserPromptSubmit/Notification")
        self.assertEqual(result["other"]["count"], 1, "SessionStart is neither per-turn nor per-call")
        self.assertIn("Bash|PowerShell", result["per_tool_call"]["matchers"])

    def test_the_note_refuses_to_present_parallel_hook_cost_as_additive(self):
        note = engine.classify_hooks([])["note"].lower()
        self.assertIn("parallel", note)
        self.assertIn("not the sum", note)

    def test_the_note_states_that_hooks_are_never_executed(self):
        self.assertIn("never executes one", engine.classify_hooks([])["note"])


class TestInvocationShape(unittest.TestCase):
    """The 3-deep bash chain costs extra spawns per hook and must be named."""

    def test_git_bin_bash_wrapper_is_flagged(self):
        entry = {
            "command": "C:/Program Files/Git/bin/bash.EXE",
            "args": ["C:/fixture/.claude/hooks/guard.sh"],
        }
        self.assertIn("git-bin-bash-wrapper-costs-an-extra-spawn", engine.invocation_shape(entry))

    def test_git_usr_bin_bash_is_not_flagged_as_the_wrapper(self):
        entry = {"command": "C:/Program Files/Git/usr/bin/bash.exe", "args": ["guard.sh"]}
        self.assertNotIn("git-bin-bash-wrapper-costs-an-extra-spawn", engine.invocation_shape(entry))

    def test_nested_shell_invocation_is_flagged(self):
        entry = {"command": "/usr/bin/bash", "args": ["-c", "bash script.sh"]}
        self.assertIn("nested-shell-invocation", engine.invocation_shape(entry))

    def test_a_plain_script_invocation_is_not_a_nested_shell(self):
        """A token ending in `.sh` is a script, not a shell; a suffix match got this wrong."""
        entry = {"command": 'bash "C:/fixture/.claude/statusline/entrypoint.sh"', "args": []}
        self.assertEqual(engine.invocation_shape(entry), [])


class TestHookInventoryOverATree(unittest.TestCase):
    """End to end over a synthetic install root: settings hooks plus enabled-plugin hooks."""

    def build(self, tmp: Path) -> Path:
        root = tmp / ".claude"
        plugin_dir = tmp / "cache" / "noisy" / "1.0.0"
        (plugin_dir / "hooks").mkdir(parents=True)
        (plugin_dir / "hooks" / "hooks.json").write_text(
            json.dumps(
                {
                    "hooks": {
                        "PreToolUse": [
                            {
                                "matcher": "Bash|PowerShell",
                                "hooks": [
                                    {
                                        "type": "command",
                                        "command": "C:/Program Files/Git/bin/bash.EXE",
                                        "args": ["-c", "bash /plugin/hooks/check.sh"],
                                    }
                                ],
                            }
                        ],
                        "Stop": [
                            {"hooks": [{"type": "command", "command": "/plugin/hooks/stop.sh"}]}
                        ],
                    }
                }
            ),
            encoding="utf-8",
        )
        write_settings(
            root,
            {
                "enabledPlugins": {"noisy@market": True, "quiet@market": False},
                "hooks": {
                    "UserPromptSubmit": [
                        {"hooks": [{"type": "command", "command": "/opt/hooks/prompt.sh"}]}
                    ]
                },
            },
        )
        (root / "plugins").mkdir()
        (root / "plugins" / "installed_plugins.json").write_text(
            json.dumps(
                {
                    "version": 2,
                    "plugins": {
                        "noisy@market": [{"scope": "user", "installPath": str(plugin_dir)}],
                        "quiet@market": [{"scope": "user", "installPath": str(plugin_dir)}],
                    },
                }
            ),
            encoding="utf-8",
        )
        return root

    def test_enabled_plugin_hooks_are_counted_and_disabled_ones_are_not(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.build(Path(tmp))
            inventory = engine.hook_inventory(root)
            self.assertEqual(inventory["total"], 3, "2 from the enabled plugin, 1 from settings")
            self.assertEqual(inventory["plugins_contributing_hooks"], 1)
            self.assertEqual(inventory["per_tool_call"]["count"], 1)
            self.assertEqual(inventory["per_turn"]["count"], 2, "Stop plus UserPromptSubmit")

    def test_the_three_deep_chain_is_surfaced_as_a_shape_finding(self):
        with tempfile.TemporaryDirectory() as tmp:
            inventory = engine.hook_inventory(self.build(Path(tmp)))
            findings = [f for row in inventory["invocation_shape_findings"] for f in row["findings"]]
            self.assertIn("git-bin-bash-wrapper-costs-an-extra-spawn", findings)
            self.assertIn("nested-shell-invocation", findings)

    def test_a_plugin_installed_at_two_scopes_is_counted_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.build(Path(tmp))
            manifest = json.loads((root / "plugins" / "installed_plugins.json").read_text())
            entry = manifest["plugins"]["noisy@market"][0]
            manifest["plugins"]["noisy@market"] = [
                dict(entry, scope="user"),
                dict(entry, scope="project"),
            ]
            (root / "plugins" / "installed_plugins.json").write_text(json.dumps(manifest))
            self.assertEqual(engine.hook_inventory(root)["plugins_contributing_hooks"], 1)

    def test_scope_precedence_prefers_the_most_specific_install(self):
        installs = [
            {"scope": "user", "installPath": "/u"},
            {"scope": "local", "installPath": "/l"},
            {"scope": "project", "installPath": "/p"},
        ]
        self.assertEqual(engine.winning_install_path(installs), "/l")


class TestConfigLiveness(unittest.TestCase):
    """Finding 3: config read off disk does not describe what running sessions loaded."""

    def test_a_session_started_before_the_settings_write_is_reported_as_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / ".claude"
            write_settings(root, {"enabledPlugins": {"guardrails@m": False}})
            mtime = (root / "settings.json").stat().st_mtime
            records = [
                {"pid": 10, "ppid": 1, "name": "node.exe", "started_epoch": mtime - 600},
                {"pid": 11, "ppid": 1, "name": "node.exe", "started_epoch": mtime + 600},
                {"pid": 12, "ppid": 1, "name": "explorer.exe", "started_epoch": mtime - 600},
            ]
            result = engine.config_liveness(root, records)
            self.assertEqual(result["candidate_sessions"], 2, "explorer.exe is not a session")
            self.assertEqual(result["sessions_predating_settings"], 1)
            self.assertIn("have NOT picked up the change", result["advisory"])
            self.assertIn("Restart is required", result["advisory"])

    def test_no_stale_session_yields_a_consistent_advisory_not_a_warning(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / ".claude"
            write_settings(root, {})
            mtime = (root / "settings.json").stat().st_mtime
            records = [{"pid": 10, "ppid": 1, "name": "node", "started_epoch": mtime + 60}]
            result = engine.config_liveness(root, records)
            self.assertEqual(result["sessions_predating_settings"], 0)
            self.assertNotIn("Restart is required", result["advisory"])

    def test_the_session_heuristic_is_labelled_rather_than_asserted(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / ".claude"
            write_settings(root, {})
            result = engine.config_liveness(root, [])
            self.assertIn("heuristic", result["session_identification"])


class TestConcurrencyCeilings(unittest.TestCase):
    """Finding 4: ceilings reported against documented defaults, with the "0" trap."""

    def ceilings(self, tmp: Path, env: dict) -> dict:
        root = tmp / ".claude"
        write_settings(root, {"env": env})
        return engine.concurrency_ceilings(root, process_env={})

    def test_an_above_default_spawn_depth_is_flagged(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self.ceilings(Path(tmp), {"CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "5"})
            record = result["variables"]["CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH"]
            self.assertTrue(record["above_documented_default"])
            self.assertEqual(record["documented_default"], 3)
            self.assertEqual(result["effective"]["max_subagent_spawn_depth"], 5)

    def test_an_unset_ceiling_reports_the_documented_default_as_effective(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self.ceilings(Path(tmp), {})
            self.assertEqual(result["effective"]["max_concurrent_subagents_per_session"], 20)
            self.assertIsNone(result["variables"]["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"]["value"])

    def test_an_undocumented_but_live_variable_is_reported_as_such(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self.ceilings(Path(tmp), {"CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS": "1"})
            self.assertIn(
                "CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS: set but undocumented upstream",
                result["findings"],
            )

    def test_zero_on_a_truthiness_gated_flag_is_reported_as_not_a_disable(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self.ceilings(Path(tmp), {"CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS": "0"})
            record = result["variables"]["CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS"]
            self.assertTrue(record["zero_is_not_a_disable"])
            self.assertTrue(any("TRUTHY" in f for f in result["findings"]))

    def test_the_trap_never_advises_setting_a_flag_to_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            trap = self.ceilings(Path(tmp), {})["trap"]
            self.assertIn("only removing the variable disables it", trap)
            self.assertIn("Never advise setting one to 0", trap)

    def test_settings_env_wins_over_the_engines_own_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / ".claude"
            write_settings(root, {"env": {"CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "7"}})
            result = engine.concurrency_ceilings(
                root, process_env={"CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "2"}
            )
            record = result["variables"]["CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH"]
            self.assertEqual(record["value"], "7")
            self.assertEqual(record["source"], "settings.json env")


class TestOrphanAttribution(unittest.TestCase):
    """Finding 5: parent liveness, never age. Age alone convicted 12 working processes."""

    def records(self, now: float) -> list[dict]:
        day = 86400
        return [
            {"pid": 1, "ppid": 0, "name": "razer.exe", "started_epoch": now - 3 * day},
            {"pid": 2, "ppid": 1, "name": "conhost.exe", "started_epoch": now - 2 * day},
            {"pid": 3, "ppid": 999, "name": "conhost.exe", "started_epoch": now - 2 * day},
            {"pid": 4, "ppid": 1, "name": "conhost.exe", "started_epoch": now - 60},
        ]

    def test_a_top_level_application_is_not_an_orphan_candidate(self):
        """Sweeping every process would report a dead parent as a defect hundreds of times."""
        now = 1_700_000_000.0
        records = [
            {"pid": 20, "ppid": 999, "name": "ArmouryCrate.exe", "started_epoch": now - 5 * 86400}
        ]
        result = engine.attribute_orphans(records, now)
        self.assertEqual(result["orphan_count"], 0)

    def test_a_parent_pid_of_zero_means_no_parent_recorded_not_a_dead_one(self):
        now = 1_700_000_000.0
        records = [{"pid": 21, "ppid": 0, "name": "node.exe", "started_epoch": now - 5 * 86400}]
        self.assertEqual(engine.attribute_orphans(records, now)["orphan_count"], 0)

    def test_a_live_parent_means_the_child_is_not_an_orphan(self):
        now = 1_700_000_000.0
        result = engine.attribute_orphans(self.records(now), now)
        orphan_pids = {o["pid"] for o in result["orphans"]}
        self.assertNotIn(2, orphan_pids, "pid 2's parent is alive; killing it breaks live software")
        self.assertEqual(result["live_parent_count"], 1)

    def test_only_a_dead_parent_makes_an_orphan(self):
        now = 1_700_000_000.0
        result = engine.attribute_orphans(self.records(now), now)
        self.assertEqual(result["orphan_count"], 1)
        self.assertEqual(result["orphans"][0]["pid"], 3)
        self.assertFalse(result["orphans"][0]["parent_alive"])

    def test_a_young_process_is_never_a_candidate_however_dead_its_parent(self):
        now = 1_700_000_000.0
        records = [{"pid": 5, "ppid": 998, "name": "bash.exe", "started_epoch": now - 60}]
        self.assertEqual(engine.attribute_orphans(records, now)["orphan_count"], 0)

    def test_a_recycled_parent_pid_does_not_launder_an_orphan(self):
        now = 1_700_000_000.0
        records = [
            {"pid": 7, "ppid": 8, "name": "bash.exe", "started_epoch": now - 5 * 86400},
            {"pid": 8, "ppid": 1, "name": "unrelated.exe", "started_epoch": now - 60},
        ]
        result = engine.attribute_orphans(records, now)
        self.assertEqual(result["orphan_count"], 1)
        self.assertIn("recycled", result["orphans"][0]["reason"])

    def test_an_unreadable_parent_start_time_is_unknown_rather_than_a_verdict(self):
        now = 1_700_000_000.0
        records = [
            {"pid": 7, "ppid": 8, "name": "bash.exe", "started_epoch": now - 5 * 86400},
            {"pid": 8, "ppid": 1, "name": "protected.exe", "started_epoch": None},
        ]
        result = engine.attribute_orphans(records, now)
        self.assertEqual(result["orphan_count"], 0)
        self.assertEqual(result["unknown_count"], 1)
        self.assertIsNone(result["unknown_sample"][0]["parent_alive"])


class TestPopulationTrend(unittest.TestCase):
    """Churn and accumulation look identical in one sample and mean opposite things."""

    def test_a_rising_count_with_nothing_exiting_is_accumulation(self):
        first = [{"pid": 1, "name": "conhost.exe"}, {"pid": 2, "name": "conhost.exe"}]
        second = first + [{"pid": 3, "name": "conhost.exe"}]
        row = engine.population_trend(first, second, 3.0)["most_active"][0]
        self.assertEqual(row["verdict"], "accumulating")
        self.assertEqual(row["exited"], 0)

    def test_a_flat_count_with_replaced_pids_is_churn(self):
        first = [{"pid": 1, "name": "bash.exe"}, {"pid": 2, "name": "bash.exe"}]
        second = [{"pid": 3, "name": "bash.exe"}, {"pid": 4, "name": "bash.exe"}]
        row = engine.population_trend(first, second, 3.0)["most_active"][0]
        self.assertEqual(row["verdict"], "churn")
        self.assertEqual(row["delta"], 0)
        self.assertEqual(row["exited"], 2)
        self.assertEqual(row["started"], 2)

    def test_an_unchanged_population_is_steady(self):
        sample = [{"pid": 1, "name": "node.exe"}]
        row = engine.population_trend(sample, sample, 3.0)["most_active"][0]
        self.assertEqual(row["verdict"], "steady")


class TestSpawnCostSummary(unittest.TestCase):
    """Finding 1: the floor moves with load, so no number ships without its load label."""

    def test_every_summary_carries_the_concurrent_load_at_sample_time(self):
        result = engine.summarize_spawn_samples([120.0, 130.0, 125.0], 0, 412)
        self.assertEqual(result["concurrent_processes_at_sample"], 412)
        self.assertEqual(result["state_label"], "as-sampled")

    def test_a_fast_machine_with_a_wide_ratio_is_not_called_bimodal(self):
        """A cold first spawn against warm ones clears 3x while every sample is still fast."""
        result = engine.summarize_spawn_samples([18.0, 120.0, 140.0], 0, 300)
        self.assertGreaterEqual(result["spread_ratio"], engine.BIMODAL_SPREAD_RATIO)
        self.assertNotIn("bimodal-spawn-latency", result["findings"])

    def test_the_storm_signature_is_a_wide_spread_whose_slow_mode_is_slow(self):
        result = engine.summarize_spawn_samples([180.0, 210.0, 1150.0, 1180.0], 0, 900)
        self.assertIn("bimodal-spawn-latency", result["findings"])

    def test_a_raised_floor_is_reported_even_without_a_wide_spread(self):
        result = engine.summarize_spawn_samples([1100.0, 1150.0, 1180.0], 0, 900)
        self.assertIn("slow-spawn-floor", result["findings"])
        self.assertNotIn("bimodal-spawn-latency", result["findings"])

    def test_a_timeout_is_recorded_as_a_finding_rather_than_dropped(self):
        result = engine.summarize_spawn_samples([20000.0], 1, 1200)
        self.assertEqual(result["timeouts"], 1)
        self.assertIn("spawn-probe-timed-out", result["findings"])

    def test_no_samples_is_stated_rather_than_silently_empty(self):
        result = engine.summarize_spawn_samples([], 0, None)
        self.assertIn("no-spawn-samples-captured", result["findings"])
        self.assertNotIn("min_ms", result)


class TestStatuslineIsReportedNeverRendered(unittest.TestCase):
    def test_the_configured_statusline_is_reported_with_its_refresh_interval(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / ".claude"
            write_settings(
                root,
                {"statusLine": {"type": "command", "command": "bash s.sh", "refreshInterval": 2}},
            )
            result = engine.statusline_config(root)
            self.assertTrue(result["configured"])
            self.assertEqual(result["refresh_interval_seconds"], 2)
            self.assertIn("Not executed by this engine", result["note"])

    def test_refresh_interval_units_are_stated_because_seconds_versus_ms_inverts_the_reading(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / ".claude"
            write_settings(root, {"statusLine": {"command": "x"}})
            self.assertIn("SECONDS", engine.statusline_config(root)["note"])

    def test_an_absent_statusline_is_reported_as_unconfigured(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / ".claude"
            write_settings(root, {})
            self.assertFalse(engine.statusline_config(root)["configured"])


class TestEtimeParsing(unittest.TestCase):
    def test_the_posix_elapsed_time_forms_all_parse(self):
        for text, expected in (("05:10", 310), ("01:00:00", 3600), ("2-03:00:00", 183600)):
            with self.subTest(etime=text):
                self.assertEqual(engine.parse_etime(text), expected)

    def test_an_unparsable_field_raises_rather_than_returning_a_wrong_age(self):
        with self.assertRaises(ValueError):
            engine.parse_etime("not-a-time")


class TestFanOutIsWiredIntoTheReport(unittest.TestCase):
    """The regression guard: a report without a fan_out section under-reports by a layer."""

    def test_the_fan_out_layer_carries_all_five_probes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / ".claude"
            write_settings(root, {})
            result = engine.fan_out_layer(root, [], None, spawn_samples=1, timeout_s=10)
            self.assertEqual(
                set(result),
                {
                    "spawn_cost",
                    "hooks",
                    "statusline",
                    "config_liveness",
                    "concurrency_ceilings",
                },
            )


if __name__ == "__main__":
    unittest.main()

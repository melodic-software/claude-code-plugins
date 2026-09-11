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

import ctypes
import io
import json
import os
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

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
            {
                "event": "PreToolUse",
                "matcher": "Bash|PowerShell",
                "command": "a.sh",
                "source": "s",
            },
            {
                "event": "PostToolUse",
                "matcher": "Write|Edit",
                "command": "b.sh",
                "source": "s",
            },
            {"event": "Stop", "matcher": None, "command": "c.sh", "source": "s"},
            {
                "event": "UserPromptSubmit",
                "matcher": None,
                "command": "d.sh",
                "source": "s",
            },
            {
                "event": "Notification",
                "matcher": None,
                "command": "e.sh",
                "source": "s",
            },
            {
                "event": "SessionStart",
                "matcher": None,
                "command": "f.sh",
                "source": "s",
            },
        ]
        result = engine.classify_hooks(entries)
        self.assertEqual(result["total"], 6)
        self.assertEqual(result["per_tool_call"]["count"], 2)
        self.assertEqual(
            result["per_turn"]["count"], 3, "Stop/UserPromptSubmit/Notification"
        )
        self.assertEqual(
            result["other"]["count"], 1, "SessionStart is neither per-turn nor per-call"
        )
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
        self.assertIn(
            "git-bin-bash-wrapper-costs-an-extra-spawn", engine.invocation_shape(entry)
        )

    def test_git_usr_bin_bash_is_not_flagged_as_the_wrapper(self):
        entry = {
            "command": "C:/Program Files/Git/usr/bin/bash.exe",
            "args": ["guard.sh"],
        }
        self.assertNotIn(
            "git-bin-bash-wrapper-costs-an-extra-spawn", engine.invocation_shape(entry)
        )

    def test_nested_shell_invocation_is_flagged(self):
        entry = {"command": "/usr/bin/bash", "args": ["-c", "bash script.sh"]}
        self.assertIn("nested-shell-invocation", engine.invocation_shape(entry))

    def test_a_plain_script_invocation_is_not_a_nested_shell(self):
        """A token ending in `.sh` is a script, not a shell; a suffix match got this wrong."""
        entry = {
            "command": 'bash "C:/fixture/.claude/statusline/entrypoint.sh"',
            "args": [],
        }
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
                            {
                                "hooks": [
                                    {
                                        "type": "command",
                                        "command": "/plugin/hooks/stop.sh",
                                    }
                                ]
                            }
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
                        {
                            "hooks": [
                                {"type": "command", "command": "/opt/hooks/prompt.sh"}
                            ]
                        }
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
                        "noisy@market": [
                            {"scope": "user", "installPath": str(plugin_dir)}
                        ],
                        "quiet@market": [
                            {"scope": "user", "installPath": str(plugin_dir)}
                        ],
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
            self.assertEqual(
                inventory["total"], 3, "2 from the enabled plugin, 1 from settings"
            )
            self.assertEqual(inventory["plugins_contributing_hooks"], 1)
            self.assertEqual(inventory["per_tool_call"]["count"], 1)
            self.assertEqual(
                inventory["per_turn"]["count"], 2, "Stop plus UserPromptSubmit"
            )

    def test_the_three_deep_chain_is_surfaced_as_a_shape_finding(self):
        with tempfile.TemporaryDirectory() as tmp:
            inventory = engine.hook_inventory(self.build(Path(tmp)))
            findings = [
                f
                for row in inventory["invocation_shape_findings"]
                for f in row["findings"]
            ]
            self.assertIn("git-bin-bash-wrapper-costs-an-extra-spawn", findings)
            self.assertIn("nested-shell-invocation", findings)

    def test_a_plugin_installed_at_two_scopes_is_counted_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.build(Path(tmp))
            manifest = json.loads(
                (root / "plugins" / "installed_plugins.json").read_text()
            )
            entry = manifest["plugins"]["noisy@market"][0]
            manifest["plugins"]["noisy@market"] = [
                dict(entry, scope="user"),
                dict(entry, scope="project"),
            ]
            (root / "plugins" / "installed_plugins.json").write_text(
                json.dumps(manifest)
            )
            self.assertEqual(
                engine.hook_inventory(root)["plugins_contributing_hooks"], 1
            )

    def test_scope_precedence_prefers_the_most_specific_install(self):
        installs = [
            {"scope": "user", "installPath": "/u"},
            {"scope": "local", "installPath": "/l"},
            {"scope": "project", "installPath": "/p"},
        ]
        self.assertEqual(engine.winning_install_path(installs), "/l")


class TestMatcherSemantics(unittest.TestCase):
    """A matcher is a character class first and a regex only as the fallback."""

    def test_star_empty_and_absent_all_match_every_tool(self):
        for matcher in ("*", "", None):
            self.assertEqual(engine.matcher_kind(matcher), "all", matcher)
            self.assertTrue(engine.matcher_matches(matcher, "Bash"), matcher)

    def test_an_exact_list_tolerates_spaces_and_commas(self):
        matcher = "Write, Edit | NotebookEdit"
        self.assertEqual(engine.matcher_kind(matcher), "exact")
        for tool in ("Write", "Edit", "NotebookEdit"):
            self.assertTrue(engine.matcher_matches(matcher, tool), tool)
        self.assertFalse(engine.matcher_matches(matcher, "Bash"))

    def test_a_regex_matcher_is_unanchored_so_edit_star_catches_notebookedit(self):
        self.assertEqual(engine.matcher_kind("Edit.*"), "regex")
        self.assertTrue(engine.matcher_matches("Edit.*", "NotebookEdit"))

    def test_a_bare_mcp_server_name_is_an_exact_string_and_matches_nothing(self):
        """`mcp__memory` has no regex character, so it is compared whole and never matches."""
        self.assertEqual(engine.matcher_kind("mcp__memory"), "exact")
        self.assertFalse(engine.matcher_matches("mcp__memory", "mcp__memory__create"))
        self.assertTrue(engine.matcher_matches("mcp__memory.*", "mcp__memory__create"))

    def test_a_matcher_python_cannot_compile_selects_every_tool_and_says_why(self):
        """A JavaScript-only construct is an unknown selection, so it stays counted."""
        matcher = "(?<prefix>Edit).*"
        self.assertEqual(engine.matcher_kind(matcher), "regex")
        error = engine.matcher_compile_error(matcher)
        self.assertIsNotNone(error)
        self.assertIn("not a Python-compilable", error)
        for tool in ("Edit", "Bash", "mcp__memory__create"):
            self.assertTrue(engine.matcher_matches(matcher, tool), tool)

    def test_a_compilable_regex_and_an_exact_matcher_report_no_compile_error(self):
        self.assertIsNone(engine.matcher_compile_error("Edit.*"))
        self.assertIsNone(engine.matcher_compile_error("Write|Edit"))
        self.assertIsNone(engine.matcher_compile_error(None))


class TestIfGateClassification(unittest.TestCase):
    """Exactly one `if` shape is decidable here; everything else says why it is not."""

    def test_a_bare_single_extension_edit_rule_is_classified(self):
        gate = engine.classify_if_gate("Edit(*.md)")
        self.assertEqual(gate["kind"], "extension")
        self.assertEqual(gate["extension"], ".md")

    def test_a_mixed_case_extension_folds_into_its_lowercase_file_kind(self):
        """A `.MD` gate must land in the `.md` row and over-count, never vanish from all rows."""
        gate = engine.classify_if_gate("Edit(*.MD)")
        self.assertEqual(gate["kind"], "extension")
        self.assertEqual(gate["extension"], ".md")
        self.assertIn(gate["extension"], engine.PROJECTION_FILE_KINDS)

    def test_an_absent_rule_is_absent_not_unclassified(self):
        self.assertEqual(engine.classify_if_gate(None)["kind"], "absent")

    def test_a_directory_anchored_pattern_is_unclassified(self):
        gate = engine.classify_if_gate("Edit(**/.github/workflows/*.yml)")
        self.assertEqual(gate["kind"], "unclassified")
        self.assertIn("**", gate["reason"])

    def test_a_bash_rule_is_unclassified_and_names_the_tool(self):
        gate = engine.classify_if_gate("Bash(git *)")
        self.assertEqual(gate["kind"], "unclassified")
        self.assertIn("Bash", gate["reason"])

    def test_a_write_rule_is_unclassified_because_only_edit_is_modelled(self):
        gate = engine.classify_if_gate("Write(*.ts)")
        self.assertEqual(gate["kind"], "unclassified")
        self.assertIn("Write", gate["reason"])

    def test_a_brace_alternation_is_unclassified(self):
        gate = engine.classify_if_gate("Edit(*.{md,mdc})")
        self.assertEqual(gate["kind"], "unclassified")
        self.assertIn("alternation", gate["reason"])


class TestPerToolCallEventSet(unittest.TestCase):
    """`if` is evaluated on five tool events, so five events are per tool call."""

    def test_the_set_is_the_five_events_that_accept_if(self):
        self.assertEqual(
            set(engine.PER_TOOL_CALL_EVENTS),
            {
                "PreToolUse",
                "PostToolUse",
                "PostToolUseFailure",
                "PermissionRequest",
                "PermissionDenied",
            },
        )

    def test_handlers_on_the_three_added_events_are_not_bucketed_as_other(self):
        entries = [
            {"event": event, "matcher": None, "command": f"{event}.sh", "source": "s"}
            for event in ("PermissionDenied", "PostToolUseFailure", "PermissionRequest")
        ]
        result = engine.classify_hooks(entries)
        self.assertEqual(result["per_tool_call"]["count"], 3)
        self.assertEqual(result["other"]["count"], 0)


class TestFanOutProjection(unittest.TestCase):
    """A registered-row count cannot say what one tool call actually spawns."""

    ENTRIES = [
        # Three gated rows behind one dispatcher: one command, one extension each.
        {
            "event": "PostToolUse",
            "matcher": "Write|Edit|NotebookEdit",
            "command": "dispatch.sh",
            "args": ["md"],
            "if": "Edit(*.md)",
            "source": "formatter",
        },
        {
            "event": "PostToolUse",
            "matcher": "Write|Edit|NotebookEdit",
            "command": "dispatch.sh",
            "args": ["py"],
            "if": "Edit(*.py)",
            "source": "formatter",
        },
        {
            "event": "PostToolUse",
            "matcher": "Write|Edit|NotebookEdit",
            "command": "dispatch.sh",
            "args": ["ts"],
            "if": "Edit(*.ts)",
            "source": "formatter",
        },
        # Ungated, and its regex matcher also selects NotebookEdit.
        {
            "event": "PostToolUse",
            "matcher": "Edit.*",
            "command": "log.sh",
            "args": [],
            "if": None,
            "source": "logger",
        },
        # An `if` the engine cannot classify: counted as firing, and listed.
        {
            "event": "PreToolUse",
            "matcher": "Bash",
            "command": "guard.sh",
            "args": [],
            "if": "Bash(git *)",
            "source": "guardrails",
        },
        # A per-tool-call event the old set called `other`.
        {
            "event": "PermissionDenied",
            "matcher": None,
            "command": "deny.sh",
            "args": [],
            "if": None,
            "source": "audit",
        },
        # An `if` on a per-turn event never runs at all.
        {
            "event": "Stop",
            "matcher": None,
            "command": "stop.sh",
            "args": [],
            "if": "Edit(*.md)",
            "source": "stopper",
        },
        # A match-all matcher carrying an extension gate: it reaches Bash, the gate does not.
        {
            "event": "PostToolUse",
            "matcher": "*",
            "command": "wide.sh",
            "args": [],
            "if": "Edit(*.md)",
            "source": "wide",
        },
    ]

    def rows(self, projection: dict) -> dict:
        return {(r["event"], r["tool"], r["file_kind"]): r for r in projection["rows"]}

    def test_a_markdown_edit_fires_only_its_own_gated_row_plus_the_ungated_one(self):
        rows = self.rows(engine.project_fan_out(self.ENTRIES))
        markdown = rows[("PostToolUse", "Edit", ".md")]
        self.assertEqual(
            markdown["fires"], 3, "the .md gate, the ungated logger, the match-all gate"
        )
        self.assertEqual(markdown["distinct_commands"], 3)
        self.assertEqual(markdown["fire_always_unclassified"], 0)

    def test_an_unmodelled_file_kind_fires_only_the_ungated_row(self):
        rows = self.rows(engine.project_fan_out(self.ENTRIES))
        self.assertEqual(rows[("PostToolUse", "Edit", "other")]["fires"], 1)

    def test_a_regex_matcher_reaches_notebookedit_and_an_exact_list_reaches_it_too(
        self,
    ):
        rows = self.rows(engine.project_fan_out(self.ENTRIES))
        self.assertEqual(rows[("PostToolUse", "NotebookEdit", ".py")]["fires"], 2)

    def test_bash_gets_a_tool_only_row_and_no_file_kind(self):
        rows = self.rows(engine.project_fan_out(self.ENTRIES))
        bash = rows[("PreToolUse", "Bash", None)]
        self.assertIsNone(bash["file_kind"])
        self.assertEqual(bash["fires"], 1)
        self.assertEqual(bash["fire_always_unclassified"], 1)

    def test_an_edit_extension_gate_never_fires_for_a_bash_call(self):
        """The match-all matcher reaches Bash; the `Edit(*.md)` gate on that row does not."""
        rows = self.rows(engine.project_fan_out(self.ENTRIES))
        self.assertEqual(rows[("PostToolUse", "Bash", None)]["fires"], 0)

    def test_a_permissiondenied_handler_is_projected_as_per_tool_call(self):
        rows = self.rows(engine.project_fan_out(self.ENTRIES))
        self.assertEqual(rows[("PermissionDenied", "Edit", ".md")]["fires"], 1)

    def test_an_if_on_a_per_turn_event_is_reported_as_never_firing(self):
        projection = engine.project_fan_out(self.ENTRIES)
        never = projection["if_on_non_tool_event"]
        self.assertEqual([r["event"] for r in never], ["Stop"])
        self.assertIn("never runs", never[0]["reason"])
        self.assertNotIn("Stop", [r["event"] for r in projection["unclassified_rows"]])
        self.assertNotIn("Stop", [r["event"] for r in projection["rows"]])

    def test_an_unclassified_row_carries_every_field_an_operator_needs(self):
        row = engine.project_fan_out(self.ENTRIES)["unclassified_rows"][0]
        self.assertEqual(set(row), {"event", "matcher", "source", "if", "reason"})
        self.assertEqual(row["if"], "Bash(git *)")
        self.assertEqual(row["source"], "guardrails")

    def test_the_projection_note_names_the_regex_stand_in(self):
        note = engine.project_fan_out([])["note"]
        self.assertIn("re.search", note)
        self.assertIn("RegExp.prototype.test", note)

    def test_the_baseline_kinds_are_projected_with_other_last_when_no_gate_adds_one(
        self,
    ):
        projection = engine.project_fan_out(self.ENTRIES)
        self.assertEqual(projection["file_kinds"], list(engine.PROJECTION_FILE_KINDS))
        self.assertEqual(projection["file_kinds"][-1], "other")
        self.assertEqual(projection["discovered_file_kinds"], [])

    def test_a_gate_on_a_kind_outside_the_baseline_gets_its_own_row(self):
        """A `.go` gate must fire on a `.go` write, never vanish into no kind at all."""
        go_gate = {
            "event": "PostToolUse",
            "matcher": "Write|Edit|NotebookEdit",
            "command": "dispatch.sh",
            "args": ["go"],
            "if": "Edit(*.go)",
            "source": "formatter",
        }
        projection = engine.project_fan_out(self.ENTRIES + [go_gate])
        self.assertNotIn(".go", engine.PROJECTION_FILE_KINDS)
        self.assertEqual(projection["discovered_file_kinds"], [".go"])
        self.assertEqual(
            projection["file_kinds"],
            [k for k in engine.PROJECTION_FILE_KINDS if k != "other"]
            + [".go", "other"],
            "baseline order kept, the discovered kind appended, `other` last",
        )
        rows = self.rows(projection)
        self.assertEqual(
            rows[("PostToolUse", "Edit", ".go")]["fires"],
            2,
            "the .go gate and the ungated logger; the match-all row is gated to .md",
        )
        self.assertEqual(
            rows[("PostToolUse", "Write", ".go")]["fires"],
            1,
            "only the .go gate; `Edit.*` does not select Write",
        )
        self.assertEqual(rows[("PostToolUse", "Edit", "other")]["fires"], 1)
        self.assertEqual(rows[("PostToolUse", "Edit", ".md")]["fires"], 3)

    def test_a_matcher_python_cannot_compile_counts_as_firing_and_is_listed(self):
        """An unknown selection over-counts where an operator can see it."""
        odd = {
            "event": "PostToolUse",
            "matcher": "(?<prefix>Edit).*",
            "command": "odd.sh",
            "args": [],
            "if": None,
            "source": "odd",
        }
        projection = engine.project_fan_out(self.ENTRIES + [odd])
        rows = self.rows(projection)
        self.assertEqual(rows[("PostToolUse", "Bash", None)]["fires"], 1)
        self.assertEqual(
            rows[("PostToolUse", "Bash", None)]["fire_always_unclassified"], 1
        )
        self.assertEqual(rows[("PostToolUse", "Edit", ".md")]["fires"], 4)
        self.assertEqual(
            rows[("PostToolUse", "Edit", ".md")]["fire_always_unclassified"], 1
        )
        listed = [r for r in projection["unclassified_rows"] if r["source"] == "odd"]
        self.assertEqual(len(listed), 1)
        self.assertEqual(set(listed[0]), {"event", "matcher", "source", "if", "reason"})
        self.assertIn("not a Python-compilable", listed[0]["reason"])

    def test_an_uncompilable_matcher_with_an_unclassified_if_is_listed_once(self):
        both = {
            "event": "PreToolUse",
            "matcher": "(?<prefix>Bash)",
            "command": "both.sh",
            "args": [],
            "if": "Bash(git *)",
            "source": "both",
        }
        projection = engine.project_fan_out([both])
        self.assertEqual(len(projection["unclassified_rows"]), 1)
        bash = self.rows(projection)[("PreToolUse", "Bash", None)]
        self.assertEqual(bash["fires"], 1)
        self.assertEqual(bash["fire_always_unclassified"], 1)


class TestByMatcherAndBucketCounters(unittest.TestCase):
    """The ceiling and the gate count ship side by side, never one without the other."""

    def test_by_matcher_separates_rows_from_distinct_commands_and_gated_rows(self):
        block = engine.classify_hooks(TestFanOutProjection.ENTRIES)
        row = next(
            r
            for r in block["by_matcher"]
            if r["event"] == "PostToolUse" and r["matcher"] == "Write|Edit|NotebookEdit"
        )
        self.assertEqual(row["rows"], 3)
        self.assertEqual(row["distinct_commands"], 3, "same script, different args")
        self.assertEqual(row["if_gated_rows"], 3)
        self.assertEqual(row["sources"], ["formatter"])

    def test_per_tool_call_reports_the_ceiling_beside_its_gated_rows(self):
        block = engine.classify_hooks(TestFanOutProjection.ENTRIES)
        self.assertEqual(block["per_tool_call"]["count"], 7, "registered rows")
        self.assertEqual(block["per_tool_call"]["if_gated_rows"], 5)
        self.assertEqual(block["per_tool_call"]["distinct_commands"], 7)

    def test_the_notes_state_the_anchor_and_dedup_limits_and_keep_the_parallel_note(
        self,
    ):
        notes = engine.classify_hooks([])["notes"]
        joined = " ".join(notes)
        self.assertIn("outside the project directory", joined)
        self.assertIn("it runs once", joined)
        self.assertIn("parallel", joined)
        self.assertIn(engine.classify_hooks([])["note"], notes)

    def test_flatten_carries_the_if_field_and_defaults_it_to_none(self):
        entries = engine.flatten_hook_block(
            {
                "PostToolUse": [
                    {
                        "matcher": "Edit",
                        "hooks": [
                            {"command": "a.sh", "if": "Edit(*.md)"},
                            {"command": "b.sh"},
                        ],
                    }
                ]
            },
            "fixture",
        )
        self.assertEqual([e["if"] for e in entries], ["Edit(*.md)", None])


class TestConfigLiveness(unittest.TestCase):
    """Finding 3: config read off disk does not describe what running sessions loaded."""

    def test_a_session_started_before_the_settings_write_is_reported_as_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / ".claude"
            write_settings(root, {"enabledPlugins": {"guardrails@m": False}})
            mtime = (root / "settings.json").stat().st_mtime
            records = [
                {
                    "pid": 10,
                    "ppid": 1,
                    "name": "node.exe",
                    "started_epoch": mtime - 600,
                },
                {
                    "pid": 11,
                    "ppid": 1,
                    "name": "node.exe",
                    "started_epoch": mtime + 600,
                },
                {
                    "pid": 12,
                    "ppid": 1,
                    "name": "explorer.exe",
                    "started_epoch": mtime - 600,
                },
            ]
            result = engine.config_liveness(root, records)
            self.assertEqual(
                result["candidate_sessions"], 2, "explorer.exe is not a session"
            )
            self.assertEqual(result["sessions_predating_settings"], 1)
            self.assertIn("have NOT picked up the change", result["advisory"])
            self.assertIn("Restart is required", result["advisory"])

    def test_no_stale_session_yields_a_consistent_advisory_not_a_warning(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / ".claude"
            write_settings(root, {})
            mtime = (root / "settings.json").stat().st_mtime
            records = [
                {"pid": 10, "ppid": 1, "name": "node", "started_epoch": mtime + 60}
            ]
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
            result = self.ceilings(
                Path(tmp), {"CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "5"}
            )
            record = result["variables"]["CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH"]
            self.assertTrue(record["above_documented_default"])
            self.assertEqual(record["documented_default"], 3)
            self.assertEqual(result["effective"]["max_subagent_spawn_depth"], 5)

    def test_an_unset_ceiling_reports_the_documented_default_as_effective(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self.ceilings(Path(tmp), {})
            self.assertEqual(
                result["effective"]["max_concurrent_subagents_per_session"], 20
            )
            self.assertIsNone(
                result["variables"]["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"]["value"]
            )

    def test_an_undocumented_but_live_variable_is_reported_as_such(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self.ceilings(
                Path(tmp), {"CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS": "1"}
            )
            self.assertIn(
                "CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS: set but undocumented upstream",
                result["findings"],
            )

    def test_zero_on_a_truthiness_gated_flag_is_reported_as_not_a_disable(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self.ceilings(
                Path(tmp), {"CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS": "0"}
            )
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
            {
                "pid": 2,
                "ppid": 1,
                "name": "conhost.exe",
                "started_epoch": now - 2 * day,
            },
            {
                "pid": 3,
                "ppid": 999,
                "name": "conhost.exe",
                "started_epoch": now - 2 * day,
            },
            {"pid": 4, "ppid": 1, "name": "conhost.exe", "started_epoch": now - 60},
        ]

    def test_a_top_level_application_is_not_an_orphan_candidate(self):
        """Sweeping every process would report a dead parent as a defect hundreds of times."""
        now = 1_700_000_000.0
        records = [
            {
                "pid": 20,
                "ppid": 999,
                "name": "ArmouryCrate.exe",
                "started_epoch": now - 5 * 86400,
            }
        ]
        result = engine.attribute_orphans(records, now)
        self.assertEqual(result["orphan_count"], 0)

    def test_a_parent_pid_of_zero_means_no_parent_recorded_not_a_dead_one(self):
        now = 1_700_000_000.0
        records = [
            {"pid": 21, "ppid": 0, "name": "node.exe", "started_epoch": now - 5 * 86400}
        ]
        self.assertEqual(engine.attribute_orphans(records, now)["orphan_count"], 0)

    def test_a_live_parent_means_the_child_is_not_an_orphan(self):
        now = 1_700_000_000.0
        result = engine.attribute_orphans(self.records(now), now)
        orphan_pids = {o["pid"] for o in result["orphans"]}
        self.assertNotIn(
            2, orphan_pids, "pid 2's parent is alive; killing it breaks live software"
        )
        self.assertEqual(result["live_parent_count"], 1)

    def test_only_a_dead_parent_makes_an_orphan(self):
        now = 1_700_000_000.0
        result = engine.attribute_orphans(self.records(now), now)
        self.assertEqual(result["orphan_count"], 1)
        self.assertEqual(result["orphans"][0]["pid"], 3)
        self.assertFalse(result["orphans"][0]["parent_alive"])

    def test_a_young_process_is_never_a_candidate_however_dead_its_parent(self):
        now = 1_700_000_000.0
        records = [
            {"pid": 5, "ppid": 998, "name": "bash.exe", "started_epoch": now - 60}
        ]
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
    """Churn and accumulation look identical in one sample and mean opposite things.

    Every verdict case pins `platform`, because the fixtures carry synthetic pids and an
    unpinned run on a Linux host would classify them against that host's real `/proc`.
    """

    def test_a_rising_count_with_nothing_exiting_is_accumulation(self):
        first = [{"pid": 1, "name": "conhost.exe"}, {"pid": 2, "name": "conhost.exe"}]
        second = first + [{"pid": 3, "name": "conhost.exe"}]
        result = engine.population_trend(first, second, 3.0, platform="darwin")
        row = result["most_active"][0]
        self.assertEqual(row["verdict"], "accumulating")
        self.assertEqual(row["exited"], 0)

    def test_a_flat_count_with_replaced_pids_is_churn(self):
        first = [{"pid": 1, "name": "bash.exe"}, {"pid": 2, "name": "bash.exe"}]
        second = [{"pid": 3, "name": "bash.exe"}, {"pid": 4, "name": "bash.exe"}]
        result = engine.population_trend(first, second, 3.0, platform="darwin")
        row = result["most_active"][0]
        self.assertEqual(row["verdict"], "churn")
        self.assertEqual(row["delta"], 0)
        self.assertEqual(row["exited"], 2)
        self.assertEqual(row["started"], 2)

    def test_an_unchanged_population_is_steady(self):
        sample = [{"pid": 1, "name": "node.exe"}]
        result = engine.population_trend(sample, sample, 3.0, platform="darwin")
        self.assertEqual(result["most_active"][0]["verdict"], "steady")

    def test_a_name_absent_from_the_first_sample_appeared_rather_than_accumulated(self):
        """One arrival of a name nothing was running seconds ago is not a leak."""
        first = [{"pid": 1, "name": "bash"}]
        second = first + [{"pid": 9, "name": "kworker/u64:3"}]
        rows = engine.population_trend(first, second, 3.0, platform="darwin")[
            "most_active"
        ]
        arrived = next(r for r in rows if r["name"] == "kworker/u64:3")
        self.assertEqual(arrived["count_first"], 0)
        self.assertEqual(arrived["verdict"], "appeared")

    def test_accumulation_still_requires_a_nonzero_first_sample(self):
        first = [{"pid": 1, "name": "conhost.exe"}, {"pid": 2, "name": "conhost.exe"}]
        second = first + [{"pid": 3, "name": "conhost.exe"}]
        row = engine.population_trend(first, second, 3.0, platform="darwin")[
            "most_active"
        ][0]
        self.assertEqual(row["verdict"], "accumulating")
        self.assertGreater(row["count_first"], 0)

    def test_the_note_explains_the_appeared_verdict(self):
        note = engine.population_trend([], [], 3.0, platform="darwin")["note"]
        self.assertIn("appeared", note)


class TestKernelThreadExclusion(unittest.TestCase):
    """`ps -e` lists the kernel's own threads, and a kworker renames its comm across queues,
    so the same worker reads as a new name arriving every few seconds."""

    def samples(self):
        first = [{"pid": 10, "name": "node"}]
        second = first + [
            {"pid": 101, "name": "kworker/0:2"},
            {"pid": 102, "name": "kworker/0:2"},
        ]
        return first, second

    def test_a_row_whose_every_process_is_a_kernel_thread_is_dropped(self):
        first, second = self.samples()
        result = engine.population_trend(
            first,
            second,
            3.0,
            platform="linux",
            classify=lambda pid, proc_root=None: pid >= 100,
        )
        self.assertNotIn("kworker/0:2", [r["name"] for r in result["most_active"]])
        self.assertEqual(result["kernel_threads_excluded"], 1)
        self.assertEqual(result["kernel_thread_reads"], 3)

    def test_a_user_space_row_survives_classification(self):
        first, second = self.samples()
        result = engine.population_trend(
            first,
            second,
            3.0,
            platform="linux",
            classify=lambda pid, proc_root=None: False,
        )
        self.assertIn("node", [r["name"] for r in result["most_active"]])
        self.assertEqual(result["kernel_threads_excluded"], 0)

    def test_an_unclassifiable_process_keeps_its_row(self):
        """Under-exclusion is an investigable false alarm; over-exclusion hides a real leak."""
        first, second = self.samples()
        result = engine.population_trend(
            first,
            second,
            3.0,
            platform="linux",
            classify=lambda pid, proc_root=None: True if pid == 101 else None,
        )
        self.assertIn("kworker/0:2", [r["name"] for r in result["most_active"]])
        self.assertEqual(result["kernel_threads_excluded"], 0)

    def test_the_read_cap_bounds_the_per_pid_reads(self):
        rows = [{"name": "kworker/0:2"}, {"name": "kworker/1:0"}]
        pids = {"kworker/0:2": {1, 2, 3}, "kworker/1:0": {4, 5}}
        seen: list[int] = []

        def classify(pid, proc_root=None):
            seen.append(pid)
            return True

        result = engine.exclude_kernel_threads(
            rows, pids, platform="linux", classify=classify, classify_cap=2
        )
        self.assertEqual(len(seen), 2)
        self.assertEqual(result["reads"], 2)

    def test_a_row_the_cap_leaves_unclassified_is_kept(self):
        rows = [{"name": "kworker/0:2"}, {"name": "kworker/1:0"}]
        pids = {"kworker/0:2": {1, 2}, "kworker/1:0": {4}}
        result = engine.exclude_kernel_threads(
            rows,
            pids,
            platform="linux",
            classify=lambda pid, proc_root=None: True,
            classify_cap=2,
        )
        self.assertEqual([r["name"] for r in result["rows"]], ["kworker/1:0"])
        self.assertEqual(result["excluded"], 1)

    def test_a_row_partially_examined_at_the_cap_is_kept(self):
        """The cap cutting a row mid-way must never convict it on the examined prefix."""
        rows = [{"name": "kworker/0:2"}]
        pids = {"kworker/0:2": {1, 2, 3}}
        result = engine.exclude_kernel_threads(
            rows,
            pids,
            platform="linux",
            classify=lambda pid, proc_root=None: True,
            classify_cap=2,
        )
        self.assertEqual([r["name"] for r in result["rows"]], ["kworker/0:2"])
        self.assertEqual(result["excluded"], 0)
        self.assertEqual(result["reads"], 2)

    def test_kernel_rows_at_the_top_do_not_crowd_out_user_rows(self):
        """Ranked rows are walked until `keep` non-kernel rows survive."""
        kernel = [{"name": f"kworker/{i}:0"} for i in range(3)]
        user = [{"name": f"user-{i}"} for i in range(11)]
        pids = {row["name"]: {index} for index, row in enumerate(kernel + user)}
        result = engine.exclude_kernel_threads(
            kernel + user,
            pids,
            platform="linux",
            classify=lambda pid, proc_root=None: pid < 3,
            classify_cap=50,
            keep=10,
        )
        self.assertEqual(
            [r["name"] for r in result["rows"]], [r["name"] for r in user[:10]]
        )
        self.assertEqual(result["excluded"], 3)
        self.assertEqual(result["reads"], 13)

    def test_off_linux_the_shortlist_is_still_capped(self):
        rows = [{"name": f"proc-{i}"} for i in range(12)]
        result = engine.exclude_kernel_threads(rows, {}, platform="win32", keep=10)
        self.assertEqual(len(result["rows"]), 10)

    def test_off_linux_the_exclusion_is_null_with_a_reason_rather_than_zero(self):
        result = engine.population_trend([], [], 3.0, platform="win32")
        self.assertIsNone(result["kernel_threads_excluded"])
        self.assertIn("Linux-only", result["kernel_thread_note"])
        self.assertEqual(result["kernel_thread_read_cap"], engine.KTHREAD_CLASSIFY_CAP)


class TestProcReadAllowlist(unittest.TestCase):
    """The second allowlist is enforced in code, like the JSON one, so the SKILL.md prose
    and the reader cannot drift apart."""

    def test_the_proc_allowlist_names_only_kernel_generated_text(self):
        self.assertEqual(set(engine.PROC_TEXT_READS), {"status", "stat"})

    def test_cmdline_is_absent_because_it_is_process_supplied_text(self):
        self.assertNotIn("cmdline", engine.PROC_TEXT_READS)

    def test_reading_a_non_allowlisted_proc_file_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = Path(tmp) / "1"
            proc.mkdir()
            (proc / "cmdline").write_text("x", encoding="utf-8")
            with self.assertRaises(AssertionError):
                engine.read_proc_text(1, "cmdline", Path(tmp))


class TestIsKernelThread(unittest.TestCase):
    """PF_KTHREAD is the kernel's own predicate. Neither ppid 2 nor an empty cmdline is one:
    the kernel reparents user-space helpers onto kthreadd, and a process can rewrite its own
    cmdline."""

    def proc(
        self, tmp: Path, pid: int, status: str | None = None, stat: str | None = None
    ):
        entry = tmp / str(pid)
        entry.mkdir(parents=True, exist_ok=True)
        if status is not None:
            (entry / "status").write_text(status, encoding="utf-8")
        if stat is not None:
            (entry / "stat").write_text(stat, encoding="utf-8")
        return entry

    def test_the_status_kthread_line_is_authoritative_when_present(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.proc(root, 2, status="Name:\tkthreadd\nKthread:\t1\n")
            self.assertIs(engine.is_kernel_thread(2, root), True)

    def test_a_zero_kthread_line_is_a_user_process(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.proc(root, 1, status="Name:\tsystemd\nKthread:\t0\n")
            self.assertIs(engine.is_kernel_thread(1, root), False)

    def test_a_status_without_the_line_falls_back_to_the_stat_flags_word(self):
        """Field 2 of stat is parenthesised and may hold spaces and `)`, so the split runs
        from the LAST `)`; indexing from the first reads the wrong field entirely."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            flags = engine.PF_KTHREAD | 0x40
            self.proc(
                root,
                7,
                status="Name:\tweird\nState:\tS\n",
                stat=f"7 (weird ) name) S 2 0 0 0 -1 {flags} 0 0 0 0 0 0\n",
            )
            self.assertIs(engine.is_kernel_thread(7, root), True)

    def test_the_stat_fallback_reports_a_user_process_when_the_bit_is_clear(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            flags = 0x400100
            self.assertFalse(flags & engine.PF_KTHREAD)
            self.proc(
                root,
                8,
                status="Name:\t(sh)\n",
                stat=f"8 ((sh) run) S 1 0 0 0 -1 {flags} 0 0 0 0 0 0\n",
            )
            self.assertIs(engine.is_kernel_thread(8, root), False)

    def test_an_unparsable_stat_classifies_as_user_space_rather_than_guessing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.proc(root, 9, status="Name:\tx\n", stat="9 (x) S not-a-number\n")
            self.assertIsNone(engine.is_kernel_thread(9, root))

    def test_a_process_that_vanished_mid_read_classifies_as_unknown(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(engine.is_kernel_thread(4242, Path(tmp)))


class TestCliProbeProvenance(unittest.TestCase):
    """A version with no probed path is unfalsifiable: it cannot be checked against the binary
    the operator's own shell runs."""

    def test_the_native_versions_tree_is_the_documented_native_layout(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            versions = home / ".local" / "share" / "claude" / "versions" / "2.1.211"
            versions.mkdir(parents=True)
            binary = versions / "claude"
            binary.write_text("", encoding="utf-8")
            self.assertEqual(
                engine.cli_layout(str(binary), str(binary), home), "documented-native"
            )

    def test_the_native_launcher_path_is_native_even_before_resolution(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            launcher = home / ".local" / "bin" / "claude"
            self.assertEqual(
                engine.cli_layout(str(launcher), "/elsewhere/claude", home),
                "documented-native",
            )

    def test_the_legacy_local_npm_tree_is_named_as_such(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            legacy = home / ".claude" / "local" / "node_modules" / ".bin"
            legacy.mkdir(parents=True)
            binary = legacy / "claude"
            binary.write_text("", encoding="utf-8")
            self.assertEqual(
                engine.cli_layout(str(binary), str(binary), home), "legacy-local-npm"
            )

    def test_an_unrecognised_path_is_unclassified_not_unsupported(self):
        """Homebrew, WinGet, apt and direct-download installs are supported and land anywhere."""
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            self.assertEqual(
                engine.cli_layout(
                    "/usr/local/bin/claude", "/usr/local/bin/claude", home
                ),
                "unclassified",
            )
            block = engine.cli_probe_provenance(
                "/usr/local/bin/claude", home=home, cwd=home, path_value=""
            )
            self.assertEqual(block["layout"], "unclassified")
            self.assertIn("native installer", block["layout_note"])

    def test_a_binary_inside_the_containment_base_is_reported_as_project_local(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "repo"
            (project / "bin").mkdir(parents=True)
            binary = project / "bin" / "claude"
            binary.write_text("", encoding="utf-8")
            block = engine.cli_probe_provenance(
                str(binary), project_dir=project, home=Path(tmp) / "home", path_value=""
            )
            self.assertIn(
                "cli-probe-project-local", [f["finding"] for f in block["findings"]]
            )
            self.assertEqual(block["containment_base_source"], "project-dir")
            self.assertEqual(block["containment_base"], str(project))

    def test_a_node_modules_segment_is_project_local_wherever_it_sits(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home"
            block = engine.cli_probe_provenance(
                "/opt/tool/node_modules/.bin/claude",
                project_dir=Path(tmp) / "elsewhere",
                home=home,
                path_value="",
            )
            self.assertIn(
                "cli-probe-project-local", [f["finding"] for f in block["findings"]]
            )

    def test_without_a_project_dir_the_containment_base_is_cwd_and_says_so(self):
        with tempfile.TemporaryDirectory() as tmp:
            block = engine.cli_probe_provenance(
                "/usr/local/bin/claude", home=Path(tmp), cwd=Path(tmp), path_value=""
            )
            self.assertEqual(block["containment_base_source"], "cwd")
            self.assertEqual(block["containment_base"], tmp)

    def test_more_than_one_claude_on_path_is_a_finding_with_the_doctor_route(self):
        with tempfile.TemporaryDirectory() as tmp:
            first, second = Path(tmp) / "a", Path(tmp) / "b"
            for entry, name in ((first, "claude"), (second, "claude.exe")):
                entry.mkdir()
                (entry / name).write_text("", encoding="utf-8")
            block = engine.cli_probe_provenance(
                str(first / "claude"),
                project_dir=Path(tmp) / "elsewhere",
                home=Path(tmp) / "home",
                path_value=os.pathsep.join([str(first), str(second)]),
            )
            multiple = [
                f for f in block["findings"] if f["finding"] == "cli-multiple-on-path"
            ]
            self.assertEqual(len(multiple), 1)
            self.assertEqual(multiple[0]["route"], engine.DOCTOR_ROUTE)
            self.assertEqual(len(block["on_path"]), 2)

    def test_a_single_install_on_path_raises_no_multiple_finding(self):
        with tempfile.TemporaryDirectory() as tmp:
            only = Path(tmp) / "a"
            only.mkdir()
            (only / "claude").write_text("", encoding="utf-8")
            block = engine.cli_probe_provenance(
                str(only / "claude"),
                project_dir=Path(tmp) / "elsewhere",
                home=Path(tmp) / "home",
                path_value=str(only),
            )
            self.assertNotIn(
                "cli-multiple-on-path", [f["finding"] for f in block["findings"]]
            )

    def test_the_block_states_whose_path_was_searched(self):
        with tempfile.TemporaryDirectory() as tmp:
            block = engine.cli_probe_provenance(
                "/usr/local/bin/claude", home=Path(tmp), cwd=Path(tmp), path_value=""
            )
            self.assertIn("engine process PATH", block["path_searched"])
            self.assertEqual(block["exe"], block["probe_path"])


class TestOperatorContext(unittest.TestCase):
    """The engine sees the machine, never the intent. An absent paragraph is a reportable
    fact, not a clean bill of health."""

    def test_no_notes_reads_absent_with_an_empty_list(self):
        block = engine.operator_context(None)
        self.assertEqual(block["status"], "absent")
        self.assertEqual(block["notes"], [])
        self.assertEqual(block["source"], "unspecified")

    def test_repeated_notes_are_kept_in_order(self):
        block = engine.operator_context(
            ["typing lagged", "four terminals open"], "operator"
        )
        self.assertEqual(block["status"], "present")
        self.assertEqual(block["notes"], ["typing lagged", "four terminals open"])
        self.assertEqual(block["source"], "operator")

    def test_the_declared_source_is_recorded_as_unverifiable(self):
        block = engine.operator_context(["a note"], "assistant")
        self.assertEqual(block["source"], "assistant")
        self.assertIn("cannot verify origin", block["note"])

    def test_the_flag_is_repeatable_and_defaults_to_no_notes(self):
        """`default=None` rather than `default=[]`: a list default is PREPENDED to appends."""
        parser = engine.build_parser()
        self.assertIsNone(parser.parse_args([]).note)
        self.assertEqual(
            parser.parse_args(["--note", "a", "--note", "b"]).note, ["a", "b"]
        )

    def test_the_note_source_choices_are_closed(self):
        parser = engine.build_parser()
        self.assertEqual(parser.parse_args([]).note_source, "unspecified")
        self.assertEqual(
            parser.parse_args(["--note-source", "operator"]).note_source, "operator"
        )
        with (
            self.assertRaises(SystemExit),
            mock.patch.object(sys, "stderr", io.StringIO()),
        ):
            parser.parse_args(["--note-source", "anonymous"])


class TestOrphanCandidateNames(unittest.TestCase):
    def test_the_platform_agnostic_set_carries_its_own_note(self):
        result = engine.attribute_orphans([], 1_700_000_000.0)
        self.assertIn("platform-agnostic", result["candidate_names_note"])
        self.assertIn("WSL", result["candidate_names_note"])

    def test_the_candidate_set_is_unchanged(self):
        self.assertIn("bash.exe", engine.ORPHAN_CANDIDATE_NAMES)
        self.assertIn("bash", engine.ORPHAN_CANDIDATE_NAMES)
        self.assertEqual(len(engine.ORPHAN_CANDIDATE_NAMES), 18)


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
                {
                    "statusLine": {
                        "type": "command",
                        "command": "bash s.sh",
                        "refreshInterval": 2,
                    }
                },
            )
            result = engine.statusline_config(root)
            self.assertTrue(result["configured"])
            self.assertEqual(result["refresh_interval_seconds"], 2)
            self.assertIn("Not executed by this engine", result["note"])

    def test_refresh_interval_units_are_stated_because_seconds_versus_ms_inverts_the_reading(
        self,
    ):
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
        for text, expected in (
            ("05:10", 310),
            ("01:00:00", 3600),
            ("2-03:00:00", 183600),
        ):
            with self.subTest(etime=text):
                self.assertEqual(engine.parse_etime(text), expected)

    def test_an_unparsable_field_raises_rather_than_returning_a_wrong_age(self):
        with self.assertRaises(ValueError):
            engine.parse_etime("not-a-time")


class TestKernelObjectCensus(unittest.TestCase):
    """The host-level floor: a Token-object leak none of the four suspects can see."""

    @staticmethod
    def build_block(entries: list[tuple[str, int, int, int, int]]):
        """Lay out an x64 OBJECT_TYPES_INFORMATION block the way the kernel does: a count,
        then per entry the 0x68-byte struct followed by its UTF-16LE name buffer padded to 8."""
        block = ctypes.create_string_buffer(4096)
        base = ctypes.addressof(block)
        struct.pack_into("<I", block, 0, len(entries))
        offset = engine._OBJECT_TYPES_HEADER_BYTES
        for name, objects, handles, high_water_objects, high_water_handles in entries:
            encoded = name.encode("utf-16-le")
            maximum = len(encoded) + 2
            name_offset = offset + engine._OBJECT_TYPE_INFORMATION_BYTES
            struct.pack_into(
                "<HH", block, offset + engine._OTI_NAME_LENGTH, len(encoded), maximum
            )
            struct.pack_into(
                "<Q", block, offset + engine._OTI_NAME_BUFFER, base + name_offset
            )
            struct.pack_into(
                "<II", block, offset + engine._OTI_TOTAL_OBJECTS, objects, handles
            )
            struct.pack_into(
                "<II",
                block,
                offset + engine._OTI_HIGH_WATER_OBJECTS,
                high_water_objects,
                high_water_handles,
            )
            block[name_offset : name_offset + len(encoded)] = encoded
            offset = name_offset + ((maximum + 7) & ~7)
        return block

    def test_parser_walks_the_x64_layout_with_padded_names(self):
        block = self.build_block(
            [
                (
                    "Token",
                    3_811_482,
                    1_739,
                    3_811_482,
                    2_000,
                ),  # 10-byte name, padded to 16
                ("Key", 189_005, 189_011, 189_595, 190_000),  # 6-byte name, padded to 8
                ("EtwRegistration", 50_926, 50_926, 50_926, 50_926),
            ]
        )
        table = engine.parse_object_types(ctypes.addressof(block))
        self.assertEqual(list(table), ["Token", "Key", "EtwRegistration"])
        self.assertEqual(
            table["Token"],
            {
                "objects": 3_811_482,
                "handles": 1_739,
                "high_water_objects": 3_811_482,
                "high_water_handles": 2_000,
            },
        )
        self.assertEqual(table["Key"]["objects"], 189_005)
        self.assertEqual(table["EtwRegistration"]["high_water_handles"], 50_926)

    def test_a_leaking_host_is_labelled_from_count_and_pool(self):
        summary = engine.summarize_kernel_objects(
            {
                "Token": {
                    "objects": 3_811_482,
                    "handles": 1_739,
                    "high_water_objects": 3_811_482,
                    "high_water_handles": 2_000,
                }
            },
            {
                "paged_pool_mb": 9_894,
                "nonpaged_pool_mb": 2_452,
                "handles": 400_000,
                "processes": 900,
                "threads": 12_000,
                "uptime_s": 2 * 86_400 + 55 * 60,
            },
        )
        self.assertEqual(summary["state_label"], "token-leak")
        self.assertEqual(
            summary["findings"], ["token-objects-leaked", "paged-pool-high"]
        )
        self.assertEqual(summary["token"]["handleless_objects"], 3_811_482 - 1_739)
        self.assertAlmostEqual(
            summary["token"]["objects_per_uptime_second"], 21.64, places=2
        )
        self.assertIsNone(summary["token"]["hours_to_leak_threshold_at_uptime_ratio"])
        self.assertEqual(summary["pool"], {"paged_mb": 9_894, "nonpaged_mb": 2_452})

    def test_high_pool_alone_is_reported_but_is_not_a_token_leak_verdict(self):
        """GetPerformanceInfo cannot say what charged the pool, so pool alone never convicts Token."""
        summary = engine.summarize_kernel_objects(
            {
                "Token": {
                    "objects": 12_000,
                    "handles": 1_100,
                    "high_water_objects": 12_050,
                    "high_water_handles": 1_400,
                }
            },
            {"paged_pool_mb": 6_144, "nonpaged_pool_mb": 1_500, "uptime_s": 36_000},
        )
        self.assertEqual(summary["findings"], ["paged-pool-high"])
        self.assertEqual(summary["state_label"], "paged-pool-high")
        self.assertNotIn("token-objects-leaked", summary["findings"])

    def test_a_fresh_boot_is_nominal_but_projects_the_threshold(self):
        summary = engine.summarize_kernel_objects(
            {
                "Token": {
                    "objects": 25_623,
                    "handles": 1_373,
                    "high_water_objects": 25_674,
                    "high_water_handles": 1_809,
                },
                "Process": {
                    "objects": 391,
                    "handles": 3_915,
                    "high_water_objects": 499,
                    "high_water_handles": 4_442,
                },
                "Mutant": {
                    "objects": 1,
                    "handles": 1,
                    "high_water_objects": 1,
                    "high_water_handles": 1,
                },
            },
            {
                "paged_pool_mb": 1_092,
                "nonpaged_pool_mb": 1_532,
                "handles": 164_058,
                "processes": 367,
                "threads": 7_181,
                "uptime_s": 7_016,
            },
        )
        self.assertEqual(summary["state_label"], "nominal")
        self.assertEqual(summary["findings"], [])
        self.assertAlmostEqual(
            summary["token"]["objects_per_uptime_second"], 3.65, places=2
        )
        self.assertAlmostEqual(
            summary["token"]["hours_to_leak_threshold_at_uptime_ratio"], 17.1, places=1
        )
        self.assertIn(
            "boot population", summary["token"]["basis"], "the ratio names its own bias"
        )
        self.assertEqual(
            list(summary["types"]),
            ["Token", "Process"],
            "only the catalogued types ship",
        )
        self.assertEqual(
            summary["thresholds"]["token_leak_objects"], engine.TOKEN_LEAK_OBJECTS
        )

    def test_zero_uptime_reports_no_rate_rather_than_dividing(self):
        summary = engine.summarize_kernel_objects(
            {"Token": {"objects": 5, "handles": 5}}, {"uptime_s": 0}
        )
        self.assertIsNone(summary["token"]["objects_per_uptime_second"])
        self.assertIsNone(summary["token"]["hours_to_leak_threshold_at_uptime_ratio"])
        self.assertEqual(summary["state_label"], "nominal")

    def test_off_windows_the_census_says_why_rather_than_vanishing(self):
        with mock.patch.object(engine.sys, "platform", "linux"):
            result = engine.kernel_objects()
        self.assertFalse(result["supported"])
        self.assertIn("Windows-only", result["reason"])

    def test_a_live_census_carries_the_contract_keys(self):
        result = engine.kernel_objects()
        self.assertIn("supported", result)
        if result["supported"]:
            self.assertIn("Token", result["types"])
            self.assertIn(
                result["state_label"], {"nominal", "paged-pool-high", "token-leak"}
            )
            self.assertGreater(result["uptime_hours"], 0)
        else:
            self.assertIn("reason", result)


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

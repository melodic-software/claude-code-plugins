#!/usr/bin/env python3
"""Tests for overlap.py.

`unittest` from the standard library, not pytest: pytest is not provisioned on
this repo's CI runners, and the sibling extractor's suite is stdlib too.

Run directly (`python3 test_overlap.py`) or through the `overlap.test.sh`
wrapper, which is what `run-plugin-tests.sh` discovers.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import overlap  # noqa: E402  - path shim above must run first

FIXTURE_CLI_VERSION = "2.1.232"

BASE_ROW = {
    "native": {"name": "doctor", "class": "bundled-skill", "markers": ["gated"]},
    "component": {"plugin": "demo", "skill": "demo-audit", "kind": "skill"},
    "verdict": "complementary",
    "reason": "different depths of the same question",
    "evidence": ["present in the extraction as bundled-skill"],
    "observation": {
        "class": "extraction",
        "detail": f"binary v{FIXTURE_CLI_VERSION}",
        "date": "2026-08-23",
    },
    "recheck": {
        "trigger": "a Claude Code release adds, removes, or renames a bundled skill in this lane",
        "verified": "2026-08-23",
    },
    "baked": {"description_phrase": False, "boundary_section": False},
    "budget_caveat": False,
}


def deep_copy(value):
    return json.loads(json.dumps(value))


def make_store(rows):
    return {"schema": 1, "rows": deep_copy(rows)}


SKILL_TEMPLATE = """---
description: "{description}"
---

## Purpose

Demo body.
{extra}
"""


class TempRepo:
    """A throwaway repo tree with a store, a view, and plugin components."""

    def __init__(self, rows=None):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.store_path = self.root / "docs" / "native-surfaces" / "records.json"
        self.view_path = self.root / "docs" / "NATIVE-SURFACES.md"
        self.store_path.parent.mkdir(parents=True, exist_ok=True)
        self.write_store(make_store(rows if rows is not None else [BASE_ROW]))

    def write_store(self, store):
        self.store_path.write_text(json.dumps(store, indent=2), encoding="utf-8")

    def write_skill(self, plugin, skill, description="Plain description.", extra=""):
        path = self.root / "plugins" / plugin / "skills" / skill / "SKILL.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            SKILL_TEMPLATE.format(description=description, extra=extra),
            encoding="utf-8",
        )
        return path

    def generate(self, extra_args=()):
        return overlap.main(
            [
                "generate",
                "--repo",
                str(self.root),
                "--store",
                str(self.store_path),
                "--view",
                str(self.view_path),
                *extra_args,
            ]
        )

    def self_check(self, cli_version=FIXTURE_CLI_VERSION):
        args = [
            "self-check",
            "--repo",
            str(self.root),
            "--store",
            str(self.store_path),
            "--view",
            str(self.view_path),
        ]
        if cli_version is not None:
            args += ["--cli-version", cli_version]
        return overlap.main(args)

    def cleanup(self):
        self._tmp.cleanup()


class StoreValidationTests(unittest.TestCase):
    def test_valid_row_has_no_problems(self):
        self.assertEqual(overlap.validate_store(make_store([BASE_ROW])), [])

    def test_wrong_schema_is_a_problem(self):
        store = make_store([BASE_ROW])
        store["schema"] = 2
        self.assertTrue(any("schema" in p for p in overlap.validate_store(store)))

    def test_missing_trigger_is_a_problem(self):
        row = deep_copy(BASE_ROW)
        del row["recheck"]["trigger"]
        problems = overlap.validate_store(make_store([row]))
        self.assertTrue(any("trigger" in p for p in problems), problems)

    def test_bare_date_trigger_fails_the_observability_bar(self):
        for trigger in ("2027-01-01", "by 2027", "  2026-12  "):
            row = deep_copy(BASE_ROW)
            row["recheck"]["trigger"] = trigger
            problems = overlap.validate_store(make_store([row]))
            self.assertTrue(
                any("bare date" in p for p in problems), f"{trigger!r} -> {problems}"
            )

    def test_event_trigger_passes(self):
        row = deep_copy(BASE_ROW)
        row["recheck"]["trigger"] = (
            "the /skills roster stops listing this surface in 2027"
        )
        self.assertEqual(overlap.validate_store(make_store([row])), [])

    def test_unknown_verdict_is_a_problem(self):
        row = deep_copy(BASE_ROW)
        row["verdict"] = "prefer-something"
        self.assertTrue(
            any("verdict" in p for p in overlap.validate_store(make_store([row])))
        )

    def test_observation_class_is_required(self):
        row = deep_copy(BASE_ROW)
        row["observation"]["class"] = "available"
        problems = overlap.validate_store(make_store([row]))
        self.assertTrue(any("observation.class" in p for p in problems), problems)

    def test_missing_reason_is_a_problem(self):
        row = deep_copy(BASE_ROW)
        row["reason"] = "   "
        self.assertTrue(
            any("reason" in p for p in overlap.validate_store(make_store([row])))
        )

    def test_live_roster_row_may_not_be_baked(self):
        row = deep_copy(BASE_ROW)
        row["observation"] = {
            "class": "live-roster",
            "detail": "observed in a cloud session",
            "date": "2026-08-23",
        }
        row["baked"]["description_phrase"] = True
        problems = overlap.validate_store(make_store([row]))
        self.assertTrue(any("never baked" in p for p in problems), problems)

    def test_duplicate_rows_are_a_problem(self):
        problems = overlap.validate_store(make_store([BASE_ROW, BASE_ROW]))
        self.assertTrue(any("duplicate" in p for p in problems), problems)

    def test_unknown_native_class_is_a_problem(self):
        row = deep_copy(BASE_ROW)
        row["native"]["class"] = "bundled"
        self.assertTrue(
            any("native.class" in p for p in overlap.validate_store(make_store([row])))
        )


class GenerateTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)

    def test_generate_creates_a_marker_fenced_view(self):
        self.assertEqual(self.repo.generate(), 0)
        text = self.repo.view_path.read_text(encoding="utf-8")
        self.assertIn(overlap.START_MARKER, text)
        self.assertIn(overlap.END_MARKER, text)
        self.assertIn("`doctor`", text)
        self.assertIn("never hand-edit", text)

    def test_generate_is_idempotent(self):
        self.repo.generate()
        first = self.repo.view_path.read_text(encoding="utf-8")
        self.repo.generate()
        self.assertEqual(first, self.repo.view_path.read_text(encoding="utf-8"))

    def test_check_passes_when_in_sync(self):
        self.repo.generate()
        self.assertEqual(self.repo.generate(["--check"]), 0)

    def test_check_fails_on_drift(self):
        self.repo.generate()
        rows = [deep_copy(BASE_ROW)]
        rows[0]["verdict"] = "prefer-native"
        self.repo.write_store(make_store(rows))
        self.assertEqual(self.repo.generate(["--check"]), 1)

    def test_check_fails_when_the_view_is_absent(self):
        self.assertEqual(self.repo.generate(["--check"]), 1)

    def test_hand_edited_body_is_restored_but_the_header_is_kept(self):
        self.repo.generate()
        text = self.repo.view_path.read_text(encoding="utf-8")
        head, _, rest = text.partition(overlap.START_MARKER)
        _, _, tail = rest.partition(overlap.END_MARKER)
        self.repo.view_path.write_text(
            head
            + "MY HEADER NOTE\n"
            + overlap.START_MARKER
            + "\nvandalised\n"
            + overlap.END_MARKER
            + tail,
            encoding="utf-8",
        )
        self.assertEqual(self.repo.generate(["--check"]), 1)
        self.assertEqual(self.repo.generate(), 0)
        restored = self.repo.view_path.read_text(encoding="utf-8")
        self.assertIn("MY HEADER NOTE", restored)
        self.assertNotIn("vandalised", restored)

    def test_missing_markers_fail_rather_than_overwrite(self):
        self.repo.view_path.parent.mkdir(parents=True, exist_ok=True)
        self.repo.view_path.write_text("# hand written\n", encoding="utf-8")
        self.assertEqual(self.repo.generate(), 1)
        self.assertEqual(
            self.repo.view_path.read_text(encoding="utf-8"), "# hand written\n"
        )


class SelfCheckTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)

    def test_clean_store_and_view_exit_zero(self):
        self.repo.generate()
        self.assertEqual(self.repo.self_check(), 0)

    def test_missing_store_degrades_rather_than_breaking(self):
        self.repo.store_path.unlink()
        self.assertEqual(self.repo.self_check(), 3)

    def test_version_drift_degrades(self):
        self.repo.generate()
        self.assertEqual(self.repo.self_check(cli_version="2.1.999"), 3)

    def test_view_drift_breaks(self):
        self.repo.generate()
        rows = [deep_copy(BASE_ROW)]
        rows[0]["reason"] = "changed after generation"
        self.repo.write_store(make_store(rows))
        self.assertEqual(self.repo.self_check(), 1)

    def test_trigger_less_row_breaks(self):
        row = deep_copy(BASE_ROW)
        row["recheck"]["trigger"] = ""
        self.repo.write_store(make_store([row]))
        self.assertEqual(self.repo.self_check(), 1)

    def test_forward_parity_break_when_the_phrase_is_missing(self):
        row = deep_copy(BASE_ROW)
        row["baked"]["description_phrase"] = True
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.repo.write_skill("demo", "demo-audit", description="No gate here.")
        self.assertEqual(self.repo.self_check(), 1)

    def test_forward_parity_holds_when_the_phrase_is_present(self):
        row = deep_copy(BASE_ROW)
        row["baked"]["description_phrase"] = True
        row["baked"]["boundary_section"] = True
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "demo-audit",
            description=(
                "When the bundled doctor skill "
                f"{overlap.GATE_TOKEN}, prefer it for the quick pass; this skill for the "
                "deep one."
            ),
            extra="\n## Boundary — the bundled doctor skill\n\nDetail.\n",
        )
        self.assertEqual(self.repo.self_check(), 0)

    def test_reverse_parity_break_when_no_row_claims_the_baked_line(self):
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "orphan",
            description=f"When the bundled thing {overlap.GATE_TOKEN}, prefer it.",
        )
        self.assertEqual(self.repo.self_check(), 1)

    def test_row_without_a_baked_line_is_legal_pending_sweep_state(self):
        self.repo.generate()
        self.repo.write_skill("demo", "demo-audit")
        self.assertEqual(self.repo.self_check(), 0)

    def test_boundary_heading_alone_is_not_a_reverse_parity_break(self):
        # `## Boundary` predates this registry across the fleet; only the
        # frontmatter gate token is a baked-line marker.
        self.repo.generate()
        self.repo.write_skill(
            "demo", "unrelated", extra="\n## Boundary — unrelated surfaces\n\nDetail.\n"
        )
        self.assertEqual(self.repo.self_check(), 0)

    def test_agent_rows_are_never_baked(self):
        row = deep_copy(BASE_ROW)
        row["component"] = {"plugin": "demo", "skill": "some-agent", "kind": "agent"}
        row["baked"]["description_phrase"] = True
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.assertEqual(self.repo.self_check(), 1)


class DetectTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)
        self.inventory_path = self.repo.root / "inventory.json"
        self.pairs_path = self.repo.root / "pairs.json"
        self.pairs_path.write_text(
            json.dumps(
                {
                    "schema": 1,
                    "pairs": [
                        {
                            "native": {"name": "doctor", "class": "bundled-skill"},
                            "component": {
                                "plugin": "demo",
                                "skill": "demo-audit",
                                "kind": "skill",
                            },
                            "why": "seeded",
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        self.repo.write_skill("demo", "demo-audit")

    def write_inventory(self, **overrides):
        payload = {
            "schema": 1,
            "builtin_commands": {"help": {"name": "help"}},
            "bundled_skills": {
                "doctor": {
                    "name": "doctor",
                    "gated": True,
                    "hidden": False,
                    "aliases": ["checkup"],
                    "description": "Health-check your setup",
                }
            },
            "plugin_backed": {"security-review": "security-review"},
            "integrity": {
                "status": "ok",
                "cli_version": FIXTURE_CLI_VERSION,
                "validated_against": FIXTURE_CLI_VERSION,
            },
        }
        payload.update(overrides)
        self.inventory_path.write_text(json.dumps(payload), encoding="utf-8")

    def detect(self, out=None):
        args = [
            "detect",
            "--repo",
            str(self.repo.root),
            "--inventory",
            str(self.inventory_path),
            "--pairs",
            str(self.pairs_path),
        ]
        if out is not None:
            args += ["--out", str(out)]
        return overlap.main(args)

    def test_detect_emits_candidates_without_verdicts(self):
        self.write_inventory()
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 0)
        report = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(len(report["candidates"]), 1)
        candidate = report["candidates"][0]
        self.assertIsNone(candidate["verdict"])
        self.assertTrue(candidate["native"]["observed"])
        self.assertTrue(candidate["component_present"])
        self.assertTrue(any("gated" in item for item in candidate["evidence"]))

    def test_missing_consumed_key_is_broken(self):
        self.write_inventory()
        payload = json.loads(self.inventory_path.read_text(encoding="utf-8"))
        del payload["plugin_backed"]
        self.inventory_path.write_text(json.dumps(payload), encoding="utf-8")
        self.assertEqual(self.detect(), 1)

    def test_wrong_inventory_schema_is_broken(self):
        self.write_inventory(schema=2)
        self.assertEqual(self.detect(), 1)

    def test_degraded_integrity_propagates_as_exit_three(self):
        self.write_inventory(
            integrity={
                "status": "degraded",
                "cli_version": FIXTURE_CLI_VERSION,
                "validated_against": "2.1.228",
            }
        )
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 3)
        report = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(report["integrity"]["counts_are"], "floors")

    def test_broken_integrity_is_exit_one(self):
        self.write_inventory(integrity={"status": "broken", "cli_version": None})
        self.assertEqual(self.detect(), 1)

    def test_plugin_backed_lane_is_not_read_as_a_builtin(self):
        self.write_inventory()
        self.pairs_path.write_text(
            json.dumps(
                {
                    "schema": 1,
                    "pairs": [
                        {
                            "native": {
                                "name": "security-review",
                                "class": "plugin-backed-builtin",
                            },
                            "component": {
                                "plugin": "demo",
                                "skill": "demo-audit",
                                "kind": "skill",
                            },
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 0)
        candidate = json.loads(out.read_text(encoding="utf-8"))["candidates"][0]
        self.assertEqual(candidate["native"]["class"], "plugin-backed-builtin")

    def test_absent_native_is_reported_as_an_extraction_statement(self):
        self.write_inventory(bundled_skills={})
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 0)
        candidate = json.loads(out.read_text(encoding="utf-8"))["candidates"][0]
        self.assertFalse(candidate["native"]["observed"])
        self.assertTrue(
            any(
                "statement about the extraction" in item
                for item in candidate["evidence"]
            )
        )


class ScanTests(unittest.TestCase):
    def test_repo_tree_scan_finds_skills_and_agents(self):
        repo = TempRepo()
        self.addCleanup(repo.cleanup)
        repo.write_skill("alpha", "one")
        repo.write_skill("beta", "two")
        agents = repo.root / "plugins" / "alpha" / "agents"
        agents.mkdir(parents=True, exist_ok=True)
        (agents / "helper.md").write_text("---\nname: helper\n---\n", encoding="utf-8")
        found = overlap.scan_components(repo.root)
        self.assertEqual(found["skills"], ["alpha:one", "beta:two"])
        self.assertEqual(found["agents"], ["alpha:helper"])

    def test_scan_of_a_tree_without_plugins_is_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            found = overlap.scan_components(Path(tmp))
            self.assertEqual(found, {"skills": [], "agents": []})


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Tests for native_drift.py (stdlib unittest; run directly or via native_drift.test.sh)."""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import native_drift  # noqa: E402  - path shim above must run first

DRIFT_ADVISORY = (
    "cli 2.1.285 differs from the last validated build 2.1.284; counts are believed, "
    "not verified - re-run the skill's evals to revalidate"
)


def cmd(name: str, **fields) -> dict:
    return {
        "name": name,
        "user_invocable": True,
        "model_invocable": False,
        "hidden": False,
        "gated": False,
        "aliases": [],
        "description": f"{name} command",
        **fields,
    }


def inventory(**overrides) -> dict:
    base = {
        "schema": 1,
        "builtin_commands": {
            "usage": cmd(
                "usage", aliases=["cost"], description="Show plan usage limits"
            ),
            "security-review": cmd("security-review"),
        },
        "bundled_skills": {
            "loop": cmd(
                "loop", model_invocable=True, description="Run a prompt on an interval"
            ),
            "twin": [
                cmd("twin", model_invocable=True),
                cmd("twin", model_invocable=False),
            ],
        },
        "bundled_workflows": {
            "deep-research": cmd("deep-research", model_invocable=None)
        },
        "plugin_backed": {"security-review": "security-review"},
        "integrity": {
            "status": "degraded",
            "cli_version": "2.1.285",
            "validated_against": "2.1.284",
            "lanes": {lane: {"status": "ok"} for lane in native_drift.LANE_CLASS},
            "advisories": [DRIFT_ADVISORY],
        },
        "docs_crosscheck": {
            "status": "ok",
            "names": {
                "usage": {"status": "documented"},
                "loop": {"status": "undocumented"},
            },
        },
    }
    base.update(overrides)
    return base


def candidate(native: str, plugin: str, skill: str, **fields) -> dict:
    return {
        "origin": "discovered",
        "native": {"name": native, "class": "bundled-skill"},
        "component": {
            "plugin": plugin,
            "skill": skill,
            "kind": fields.pop("kind", "skill"),
        },
        "score": 0.5,
        "store_verdict": None,
        "re_derivable": True,
        "component_present": True,
        "evidence": ["shared tokens"],
        **fields,
    }


def detect(*candidates) -> dict:
    return {
        "discovery": {"threshold": 0.3},
        "integrity": {"status": "ok"},
        "candidates": list(candidates),
    }


def row(
    name: str, klass: str, markers: list, *, observation: str = "extraction"
) -> dict:
    return {
        "native": {"name": name, "class": klass, "markers": markers},
        "component": {"plugin": "demo", "skill": "demo-skill", "kind": "skill"},
        "observation": {"class": observation},
        "recheck": {"trigger": "a release changes this surface"},
    }


class SummarizeTests(unittest.TestCase):
    def test_lanes_markers_and_invocability(self):
        s = native_drift.summarize(inventory(), None)
        self.assertEqual(s["cli_version"], "2.1.285")
        self.assertNotIn("security-review", s["surfaces"]["builtin_commands"])
        backed = s["surfaces"]["plugin_backed"]["security-review"]
        self.assertEqual(backed["class"], "plugin-backed-builtin")
        self.assertEqual(backed["markers"], ["model-invocation-disabled"])
        usage = s["surfaces"]["builtin_commands"]["usage"]
        self.assertEqual(
            (usage["invocable_by"], usage["aliases"]), ("user-only", ["cost"])
        )
        self.assertEqual(
            s["surfaces"]["bundled_skills"]["loop"]["invocable_by"], "model+user"
        )
        twin = s["surfaces"]["bundled_skills"]["twin"]
        self.assertEqual(
            (twin["invocable_by"], twin["model_invocable"]), ("unknown", None)
        )
        self.assertEqual(
            s["docs"]["names"], {"usage": "documented", "loop": "undocumented"}
        )

    def test_candidate_keys_come_from_detect(self):
        s = native_drift.summarize(
            inventory(), detect(candidate("loop", "work-items", "work-loop"))
        )
        self.assertEqual(
            s["candidates"], ["native-drift:candidate:loop:work-items:work-loop"]
        )
        self.assertEqual(s["detect"]["threshold"], 0.3)

    def test_rejects_non_inventory(self):
        with self.assertRaises(native_drift.InputError):
            native_drift.summarize({"schema": 2}, None)


class KeyTests(unittest.TestCase):
    def test_key_shapes(self):
        self.assertEqual(
            native_drift.candidate_key(
                candidate("plan", "planning", "plan-reviewer", kind="agent")
            ),
            "native-drift:candidate:plan:planning:plan-reviewer@agent",
        )
        self.assertEqual(
            native_drift.drift_key("recheck", "plugin eval", "evals:plugin-eval"),
            "native-drift:recheck:plugin_eval:evals:plugin-eval",
        )


class HasKeyTests(unittest.TestCase):
    KEY = "native-drift:candidate:p:s"

    def test_exact_line_matches(self):
        body = f"facts\n  Drift key: {self.KEY}  \r\nFiled by x\n"
        self.assertTrue(native_drift.has_key(body, self.KEY))

    def test_prefix_siblings_do_not_collide(self):
        for sibling in ("p:s-x", "p:s2", "p:s@agent"):
            body = f"Drift key: native-drift:candidate:{sibling}\n"
            self.assertFalse(native_drift.has_key(body, self.KEY), sibling)

    def test_key_mentioned_mid_line_does_not_match(self):
        body = f"see Drift key: {self.KEY} elsewhere\n{self.KEY}\n"
        self.assertFalse(native_drift.has_key(body, self.KEY))


class SurfaceDiffTests(unittest.TestCase):
    def summary(self, **surfaces) -> dict:
        return {"surfaces": surfaces}

    def rec(self, klass="bundled-skill", **fields) -> dict:
        return {
            "class": klass,
            "markers": [],
            "invocable_by": "model+user",
            "aliases": [],
            "description": "",
            **fields,
        }

    def test_added_removed_reclassified_invocability_markers(self):
        prev = self.summary(
            bundled_skills={
                "a": self.rec(),
                "gone": self.rec(description="alpha beta"),
            },
            builtin_commands={"moved": self.rec("builtin-command")},
        )
        cur = self.summary(
            bundled_skills={
                "a": self.rec(
                    invocable_by="user-only", markers=["model-invocation-disabled"]
                ),
                "moved": self.rec(),
                "fresh": self.rec(description="unrelated words entirely"),
            },
        )
        d = native_drift.diff_surfaces(prev, cur)
        self.assertEqual(d["added"], [{"lane": "bundled_skills", "name": "fresh"}])
        self.assertEqual(d["removed"], [{"lane": "bundled_skills", "name": "gone"}])
        self.assertEqual(
            d["reclassified"],
            [{"name": "moved", "from": "builtin-command", "to": "bundled-skill"}],
        )
        self.assertEqual(
            d["invocability"], [{"name": "a", "from": "model+user", "to": "user-only"}]
        )
        self.assertEqual(d["markers"][0]["to"], ["model-invocation-disabled"])

    def test_rename_by_alias_and_by_description(self):
        prev = self.summary(
            bundled_skills={
                "old": self.rec(),
                "older": self.rec(description="review the current diff for bugs"),
            }
        )
        cur = self.summary(
            bundled_skills={
                "new": self.rec(aliases=["old"]),
                "newer": self.rec(
                    description="review the current diff for bugs and cleanups"
                ),
            }
        )
        d = native_drift.diff_surfaces(prev, cur)
        self.assertEqual(
            {(r["from"], r["to"]) for r in d["renamed"]},
            {("old", "new"), ("older", "newer")},
        )
        self.assertEqual((d["added"], d["removed"]), ([], []))

    def test_rename_needs_same_lane(self):
        prev = self.summary(bundled_skills={"old": self.rec()})
        cur = self.summary(
            builtin_commands={"new": self.rec("builtin-command", aliases=["old"])}
        )
        d = native_drift.diff_surfaces(prev, cur)
        self.assertEqual(d["renamed"], [])
        self.assertEqual(len(d["removed"]), 1)

    def test_docs_status_changes(self):
        d = native_drift.diff_docs(
            {"docs": {"status": "ok", "names": {"a": "documented"}}},
            {
                "docs": {
                    "status": "degraded",
                    "names": {"a": "removed_in_docs", "b": "undocumented"},
                }
            },
        )
        self.assertEqual(d["status"], {"from": "ok", "to": "degraded"})
        self.assertEqual([n["name"] for n in d["names"]], ["a", "b"])


class TriggerTests(unittest.TestCase):
    def setUp(self):
        self.cur = native_drift.summarize(inventory(), None)

    def test_markers_differ_fires(self):
        reasons = native_drift.evaluate_row(
            row("usage", "builtin-command", []), self.cur, None, {}
        )
        self.assertEqual(len(reasons), 1)
        self.assertIn("markers differ", reasons[0])

    def test_matching_row_does_not_fire(self):
        r = row("usage", "builtin-command", ["model-invocation-disabled"])
        self.assertEqual(native_drift.evaluate_row(r, self.cur, None, {}), [])

    def test_reclassified_fires(self):
        reasons = native_drift.evaluate_row(
            row("loop", "builtin-command", []), self.cur, None, {}
        )
        self.assertTrue(any(r.startswith("reclassified") for r in reasons))

    def test_unknown_invocability_ignores_the_invocation_marker(self):
        r = row("twin", "bundled-skill", ["model-invocation-disabled"])
        self.assertEqual(native_drift.evaluate_row(r, self.cur, None, {}), [])

    def test_absence_is_an_event_only_against_a_previous_extraction(self):
        r = row("plugin eval", "builtin-command", ["gated"])
        self.assertIsNone(native_drift.evaluate_row(r, self.cur, None, {}))
        prev = {"surfaces": {"builtin_commands": {"plugin eval": {}}}}
        self.assertIn("removed", native_drift.evaluate_row(r, self.cur, prev, {})[0])
        self.assertIn(
            "renamed",
            native_drift.evaluate_row(r, self.cur, prev, {"plugin eval": "eval"})[0],
        )

    def test_broken_lane_is_not_evaluable(self):
        cur = dict(self.cur, integrity={"lanes": {"builtin_commands": "broken"}})
        self.assertIsNone(
            native_drift.evaluate_row(
                row("usage", "builtin-command", []), cur, None, {}
            )
        )


class InventoryVerdictTests(unittest.TestCase):
    def setUp(self):
        self.cur = native_drift.summarize(inventory(), None)
        self.none = {
            k: []
            for k in (
                "added",
                "removed",
                "renamed",
                "reclassified",
                "invocability",
                "markers",
            )
        }

    def test_version_only_drift_proposes_revalidation(self):
        self.assertEqual(
            native_drift.inventory_verdict(self.cur, 3, self.none)["verdict"],
            "revalidate",
        )

    def test_unknown_or_real_surface_changes_stay_degraded(self):
        self.assertEqual(
            native_drift.inventory_verdict(self.cur, 3, None)["verdict"], "degraded"
        )
        changed = dict(self.none, added=[{"lane": "bundled_skills", "name": "x"}])
        self.assertEqual(
            native_drift.inventory_verdict(self.cur, 3, changed)["verdict"], "degraded"
        )

    def test_older_cli_or_lane_advisory_stays_degraded(self):
        older = dict(self.cur, cli_version="2.1.283")
        older["integrity"] = dict(
            self.cur["integrity"],
            advisories=[DRIFT_ADVISORY.replace("2.1.285", "2.1.283")],
        )
        self.assertEqual(
            native_drift.inventory_verdict(older, 3, self.none)["verdict"], "degraded"
        )
        lane = dict(self.cur)
        lane["integrity"] = dict(
            self.cur["integrity"], advisories=[DRIFT_ADVISORY, "bundled_skills: floor"]
        )
        self.assertEqual(
            native_drift.inventory_verdict(lane, 3, self.none)["verdict"], "degraded"
        )

    def test_exit_codes(self):
        self.assertEqual(
            native_drift.inventory_verdict(self.cur, 0, self.none)["verdict"], "ok"
        )
        self.assertEqual(
            native_drift.inventory_verdict(self.cur, 1, self.none)["verdict"], "broken"
        )


class DiffItemsTests(unittest.TestCase):
    def setUp(self):
        self.cur = native_drift.summarize(inventory(), None)
        self.prev = native_drift.summarize(
            inventory(), detect(candidate("loop", "old", "seen"))
        )

    def kinds(self, report: dict) -> list:
        return [(i["kind"], i["key"]) for i in report["items"]]

    def test_candidate_gating(self):
        det = detect(
            candidate("loop", "old", "seen"),
            candidate("loop", "new", "fresh"),
            candidate("loop", "low", "score", score=0.1),
            candidate("loop", "ruled", "row", store_verdict="complementary"),
            candidate("loop", "broken", "lane", re_derivable=False),
        )
        report = native_drift.diff(self.cur, self.prev, None, det, 0)
        self.assertEqual(
            self.kinds(report), [("candidate", "native-drift:candidate:loop:new:fresh")]
        )
        self.assertEqual(len(report["new_candidates"]), 4)

    def test_detectless_previous_summary_files_no_candidates(self):
        prev = native_drift.summarize(inventory(), None)
        self.assertIsNone(prev["detect"])
        self.assertIsNone(prev["candidates"])
        report = native_drift.diff(
            self.cur, prev, None, detect(candidate("loop", "new", "fresh")), 0
        )
        self.assertEqual(report["items"], [])
        self.assertIsNone(report["new_candidates"])

    def test_batch_over_the_cap_adds_one_overflow_item(self):
        det = detect(*(candidate("loop", "p", f"s{n}") for n in range(3)))
        within = native_drift.diff(self.cur, self.prev, None, det, 0, max_items=3)
        self.assertIsNone(within["overflow"])
        over = native_drift.diff(self.cur, self.prev, None, det, 0, max_items=2)
        self.assertEqual(len(over["items"]), 3)
        self.assertEqual(
            over["overflow"]["key"], "native-drift:batch-overflow:2.1.285:inventory"
        )
        self.assertIn("exceed the batch cap of 2", over["overflow"]["facts"][0])
        self.assertEqual(len(over["overflow"]["facts"]), 4)
        self.assertEqual(native_drift.MAX_ITEMS, 10)

    def test_facts_are_clipped(self):
        det = detect(candidate("loop", "new", "fresh", evidence=["x" * 5000]))
        report = native_drift.diff(self.cur, self.prev, None, det, 0)
        facts = report["items"][0]["facts"]
        self.assertEqual(len(facts[1]), native_drift.FACT_CHARS)
        self.assertTrue(facts[1].endswith("..."))

    def test_baseline_files_no_candidates_and_flags_unknown_changes(self):
        report = native_drift.diff(
            self.cur, None, None, detect(candidate("loop", "new", "fresh")), 3
        )
        self.assertTrue(report["baseline"])
        self.assertIsNone(report["new_candidates"])
        self.assertEqual(
            self.kinds(report),
            [
                (
                    "inventory-degraded",
                    "native-drift:inventory-degraded:2.1.285:inventory",
                )
            ],
        )
        self.assertIn("unknown", report["items"][0]["facts"][-1])

    def test_recheck_and_revalidate_items(self):
        store = {
            "rows": [
                row("usage", "builtin-command", []),
                row("morning", "session-skill", [], observation="live-roster"),
            ]
        }
        report = native_drift.diff(self.cur, self.cur, store, None, 3)
        self.assertEqual(
            self.kinds(report),
            [
                ("recheck", "native-drift:recheck:usage:demo:demo-skill"),
                ("revalidate", "native-drift:revalidate:2.1.285:inventory"),
            ],
        )
        self.assertEqual(report["rows_not_evaluable"], 1)
        self.assertTrue(report["store_present"])


class CliTests(unittest.TestCase):
    def run_main(self, *argv) -> int:
        with (
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            return native_drift.main(list(argv))

    def test_summarize_then_diff(self):
        with tempfile.TemporaryDirectory() as tmp:
            inv, summary, out = (
                str(Path(tmp) / n) for n in ("inv.json", "s.json", "d.json")
            )
            Path(inv).write_text(json.dumps(inventory()), encoding="utf-8")
            self.assertEqual(
                self.run_main("summarize", "--inventory", inv, "--out", summary), 0
            )
            code = self.run_main(
                "diff",
                "--current",
                summary,
                "--previous",
                summary,
                "--store",
                str(Path(tmp) / "absent.json"),
                "--self-check-exit",
                "3",
                "--out",
                out,
            )
            self.assertEqual(code, 0)
            report = json.loads(Path(out).read_text(encoding="utf-8"))
            self.assertFalse(report["store_present"])
            self.assertEqual(report["inventory"]["verdict"], "revalidate")
            # No store is overlap self-check's report-only mode: nothing to file.
            self.assertTrue(report["report_only"])
            self.assertEqual((report["items"], report["overflow"]), ([], None))
            self.assertEqual([i["kind"] for i in report["unfiled"]], ["revalidate"])

    def test_present_store_files_items(self):
        with tempfile.TemporaryDirectory() as tmp:
            summary, store, out = (
                str(Path(tmp) / n) for n in ("s.json", "r.json", "d.json")
            )
            Path(summary).write_text(
                json.dumps(native_drift.summarize(inventory(), None)), encoding="utf-8"
            )
            Path(store).write_text(json.dumps({"rows": []}), encoding="utf-8")
            code = self.run_main(
                "diff", "--current", summary, "--previous", summary,
                "--store", store, "--self-check-exit", "3", "--out", out,
            )  # fmt: skip
            self.assertEqual(code, 0)
            report = json.loads(Path(out).read_text(encoding="utf-8"))
            self.assertFalse(report["report_only"])
            self.assertEqual(
                ([i["kind"] for i in report["items"]], report["unfiled"]),
                (["revalidate"], []),
            )

    def test_wrong_shaped_inputs_are_usage_errors(self):
        summary = native_drift.summarize(inventory(), None)
        cases = {
            "--current": [[], {"schema": 2}, {**summary, "surfaces": []}],
            "--previous": [[], {**summary, "integrity": "ok"}],
            "--detect": [[], {"candidates": "x"}, {"candidates": [{"native": "x"}]}],
            "--store": [[], {}, {"rows": ["x"]}, {"rows": [{"observation": "x"}]}],
        }
        with tempfile.TemporaryDirectory() as tmp:
            good = Path(tmp) / "s.json"
            good.write_text(json.dumps(summary), encoding="utf-8")
            bad = Path(tmp) / "bad.json"
            for flag, payloads in cases.items():
                for payload in payloads:
                    bad.write_text(json.dumps(payload), encoding="utf-8")
                    args = {"--current": str(good), flag: str(bad)}
                    argv = ["diff", "--self-check-exit", "0"]
                    for k, v in args.items():
                        argv += [k, v]
                    with self.subTest(flag=flag, payload=payload):
                        self.assertEqual(self.run_main(*argv), 2)
            inv = Path(tmp) / "inv.json"
            for payload in (
                [],
                inventory(builtin_commands=[]),
                inventory(integrity={"lanes": {"builtin_commands": "ok"}}),
            ):
                inv.write_text(json.dumps(payload), encoding="utf-8")
                with self.subTest(inventory=payload):
                    self.assertEqual(
                        self.run_main("summarize", "--inventory", str(inv)), 2
                    )
            inv.write_text(json.dumps(inventory()), encoding="utf-8")
            bad.write_text("[]", encoding="utf-8")
            self.assertEqual(
                self.run_main(
                    "summarize", "--inventory", str(inv), "--detect", str(bad)
                ),
                2,
            )

    def test_optional_path_that_is_not_a_file_warns(self):
        with tempfile.TemporaryDirectory() as tmp:
            inv, summary = (str(Path(tmp) / n) for n in ("inv.json", "s.json"))
            Path(inv).write_text(json.dumps(inventory()), encoding="utf-8")
            absent = str(Path(tmp) / "absent.json")
            err = io.StringIO()
            with (
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(err),
            ):
                code = native_drift.main(
                    ["summarize", "--inventory", inv, "--detect", absent]
                    + ["--out", summary]
                )
            self.assertEqual(code, 0)
            self.assertIn(f"warning: {absent} is not a file", err.getvalue())

    def test_has_key_exit_codes(self):
        with tempfile.TemporaryDirectory() as tmp:
            body = Path(tmp) / "body.txt"
            body.write_text("Drift key: native-drift:recheck:a:b\n", encoding="utf-8")
            key = "native-drift:recheck:a:b"
            self.assertEqual(
                self.run_main("has-key", "--key", key, "--body", str(body)), 0
            )
            self.assertEqual(
                self.run_main("has-key", "--key", key[:-1], "--body", str(body)), 1
            )
            self.assertEqual(
                self.run_main("has-key", "--key", key, "--body", f"{tmp}/none"), 2
            )

    def test_missing_current_is_a_usage_error(self):
        self.assertEqual(
            self.run_main(
                "diff", "--current", "/nonexistent.json", "--self-check-exit", "0"
            ),
            2,
        )


if __name__ == "__main__":
    unittest.main()

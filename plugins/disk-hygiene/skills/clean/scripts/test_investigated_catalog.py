"""Catalog record rules: identity, operator answers, and non-authorization."""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

import hygiene
import investigated_catalog as catalog

TARGET = "/scan-target"


def _entry(
    path: str,
    *,
    kind: str = "directory",
    inode: int = 10,
    logical_size: int = 4,
) -> dict:
    return {
        "path": path,
        "kind": kind,
        "device": 1,
        "inode": inode,
        "logical_size": logical_size,
    }


def _snapshot(*entries: dict, target: str = TARGET) -> dict:
    return {"target": target, "entries": list(entries)}


def _finding(path: str, **fields: object) -> dict:
    return {
        "path": path,
        "owner": "notes",
        "provenance": "A notes file. It is kept.",
        "disposition": "keep",
        "evidence": [{"source": "README.md"}],
        **fields,
    }


class CatalogRulesTest(unittest.TestCase):
    def test_identity_or_descendant_change_invalidates(self) -> None:
        entries = [
            _entry("cache", inode=3),
            _entry("cache/keep", inode=4, kind="file", logical_size=1),
        ]
        record = {
            "path": "cache",
            "identity": catalog.identity_of(entries[0]),
            "descendant_set": catalog.descendant_set("cache", entries),
        }
        self.assertTrue(catalog.identity_holds(record, entries[0], entries))
        moved = {**entries[0], "inode": 99}
        self.assertFalse(catalog.identity_holds(record, moved, entries))
        grown = [*entries, _entry("cache/extra", inode=5, kind="file")]
        self.assertFalse(catalog.identity_holds(record, entries[0], grown))

    def test_record_carries_the_issue_shape(self) -> None:
        stored, _ = catalog.sync_catalog(
            _snapshot(_entry("loose", kind="file", inode=7, logical_size=2)),
            None,
            [_finding("loose", tier="low")],
            [],
            "run-a",
        )
        record = stored["records"][0]
        self.assertGreaterEqual(record.keys(), catalog.RECORD_KEYS)
        self.assertEqual({"device": 1, "inode": 7, "kind": "file"}, record["identity"])
        self.assertEqual([{"source": "README.md"}], record["evidence"])
        self.assertEqual(
            ("run-a", "run-a", "run-a", "engine", 2, "low"),
            (
                record["first_seen_run"],
                record["last_seen_run"],
                record["last_verified"],
                record["source"],
                record["size"],
                record["tier"],
            ),
        )

    def test_prior_disposition_requires_the_same_identity(self) -> None:
        snapshot = _snapshot(_entry("loose", kind="file", inode=7))
        stored, _ = catalog.sync_catalog(
            snapshot, None, [_finding("loose", disposition="remove")], [], "run-a"
        )
        catalog.annotate_entries(snapshot, stored)
        self.assertEqual("remove", snapshot["entries"][0]["prior_disposition"])
        snapshot["entries"][0]["inode"] = 8
        catalog.annotate_entries(snapshot, stored)
        self.assertNotIn("prior_disposition", snapshot["entries"][0])

    def test_unanswered_unknown_owner_stays_keep_and_is_asked(self) -> None:
        stored, report = catalog.sync_catalog(
            _snapshot(_entry("ansel", inode=11, logical_size=0)),
            None,
            [_finding("ansel", owner=None, disposition="remove")],
            [],
            "run-b",
        )
        record = stored["records"][0]
        self.assertEqual("keep", record["disposition"])
        self.assertIsNone(record["owner"])
        self.assertEqual(["ansel"], [item["path"] for item in report["questions"]])
        self.assertEqual([], report["unchanged"])
        snapshot = _snapshot(_entry("ansel", inode=11, logical_size=0))
        catalog.annotate_entries(snapshot, stored)
        self.assertTrue(snapshot["entries"][0]["prior_unresolved"])

    def test_human_keep_answer_is_not_reasked_while_identity_holds(self) -> None:
        snapshot = _snapshot(_entry("scratch", inode=12, logical_size=0))
        first, asked = catalog.sync_catalog(
            snapshot, None, [_finding("scratch", owner=None)], [], "run-c"
        )
        self.assertEqual(["scratch"], [item["path"] for item in asked["questions"]])
        answered, report = catalog.sync_catalog(
            snapshot,
            first,
            [_finding("scratch", owner="engine-owner", disposition="remove")],
            [{"path": "scratch", "disposition": "keep"}],
            "run-d",
        )
        record = answered["records"][0]
        self.assertEqual(
            ("human", "keep", None),
            (record["source"], record["disposition"], record["question"]),
        )
        self.assertEqual([], report["questions"])
        again, again_report = catalog.sync_catalog(
            snapshot,
            answered,
            [_finding("scratch", owner="engine-owner", disposition="remove")],
            [],
            "run-e",
        )
        kept = again["records"][0]
        self.assertEqual(
            ("human", "keep", "run-e"),
            (kept["source"], kept["disposition"], kept["last_verified"]),
        )
        self.assertEqual([], again_report["questions"])
        self.assertEqual(["scratch | keep | unknown"], again_report["unchanged"])
        self.assertEqual([], again_report["new_or_changed"])

    def test_human_answer_is_asked_again_when_identity_changes(self) -> None:
        snapshot = _snapshot(_entry("scratch", inode=12))
        answered, _ = catalog.sync_catalog(
            snapshot, None, [], [{"path": "scratch", "owner": "verifier"}], "run-f"
        )
        snapshot["entries"][0]["inode"] = 13
        refreshed, report = catalog.sync_catalog(snapshot, answered, [], [], "run-g")
        record = refreshed["records"][0]
        self.assertEqual(
            ("engine", None, "keep"),
            (record["source"], record["owner"], record["disposition"]),
        )
        self.assertEqual("run-f", record["first_seen_run"])
        self.assertEqual(["scratch"], [item["path"] for item in report["questions"]])
        self.assertEqual("changed", report["new_or_changed"][0]["state"])

    def test_records_outside_this_snapshot_survive(self) -> None:
        elsewhere = _snapshot(_entry("scratch", inode=1), target="/other")
        stored, _ = catalog.sync_catalog(
            elsewhere, None, [], [{"path": "scratch", "owner": "someone"}], "run-h"
        )
        home = _snapshot(_entry("scratch", inode=2), _entry("other", inode=3))
        merged, _ = catalog.sync_catalog(
            home, stored, [], [{"path": "scratch", "owner": "me"}], "run-i"
        )
        by_target = {record["target"]: record for record in merged["records"]}
        self.assertEqual("someone", by_target["/other"]["owner"])
        self.assertEqual("me", by_target[TARGET]["owner"])
        catalog.annotate_entries(elsewhere, merged)
        self.assertEqual("keep", elsewhere["entries"][0]["prior_disposition"])
        partial, _ = catalog.sync_catalog(_snapshot(), merged, [], [], "run-j")
        self.assertEqual(2, len(partial["records"]))

    def test_operator_answer_is_reused_by_identity_from_another_target(self) -> None:
        first = _snapshot(
            _entry("esupport", inode=20),
            _entry("esupport/a", inode=21, kind="file"),
            target="/root",
        )
        answered, _ = catalog.sync_catalog(
            first, None, [], [{"path": "esupport", "disposition": "keep"}], "run-o"
        )
        reached = _snapshot(
            _entry("vendor/esupport", inode=20),
            _entry("vendor/esupport/a", inode=21, kind="file"),
            target="/other",
        )
        catalog.annotate_entries(reached, answered)
        self.assertEqual("keep", reached["entries"][0]["prior_disposition"])
        again, report = catalog.sync_catalog(
            reached,
            answered,
            [_finding("vendor/esupport", owner=None, disposition="remove")],
            [],
            "run-p",
        )
        self.assertEqual([], report["questions"])
        self.assertEqual(answered, again)
        own = _snapshot(_entry("a", inode=21, kind="file"), target="/root/esupport")
        own["target_identity"] = {**_entry("esupport", inode=20), "size_qualifiers": []}
        catalog.annotate_entries(own, answered)
        self.assertEqual("keep", own["target_prior_disposition"])
        own["target_identity"]["inode"] = 99
        catalog.annotate_entries(own, answered)
        self.assertNotIn("target_prior_disposition", own)

    def test_an_answer_reused_from_another_target_is_reported_unchanged(self) -> None:
        answered, _ = catalog.sync_catalog(
            _snapshot(_entry("esupport", inode=20), target="/root"),
            None,
            [],
            [{"path": "esupport", "owner": "eSupport", "disposition": "keep"}],
            "run-t",
        )
        reached = _snapshot(_entry("esupport", inode=20), target="/other")
        again, report = catalog.sync_catalog(reached, answered, [], [], "run-u")
        line = "esupport | keep | eSupport | answered under /root"
        self.assertEqual([line], report["unchanged"])
        for key in ("new_or_changed", "questions", "uncataloged"):
            self.assertEqual([], report[key])
        self.assertIn(f"- {line}", catalog.render_markdown(again, report))
        _, local = catalog.sync_catalog(
            reached,
            answered,
            [],
            [{"path": "esupport", "disposition": "remove"}],
            "run-v",
        )
        self.assertEqual([], local["unchanged"])
        self.assertEqual(["new"], [item["state"] for item in local["new_or_changed"]])

    def test_an_open_question_yields_to_an_answer_from_another_target(self) -> None:
        asked, first = catalog.sync_catalog(
            _snapshot(_entry("esupport", inode=20), target="/a"),
            None,
            [_finding("esupport", owner=None)],
            [],
            "run-w",
        )
        self.assertEqual(["esupport"], [item["path"] for item in first["questions"]])
        answered, _ = catalog.sync_catalog(
            _snapshot(_entry("esupport", inode=20), target="/b"),
            asked,
            [],
            [{"path": "esupport", "owner": "eSupport", "disposition": "keep"}],
            "run-x",
        )
        rescan = _snapshot(_entry("esupport", inode=20), target="/a")
        catalog.annotate_entries(rescan, answered)
        self.assertEqual("keep", rescan["entries"][0]["prior_disposition"])
        self.assertNotIn("prior_unresolved", rescan["entries"][0])
        again, report = catalog.sync_catalog(
            rescan, answered, [_finding("esupport", owner=None)], [], "run-y"
        )
        self.assertEqual([], report["questions"])
        self.assertEqual(
            ["esupport | keep | eSupport | answered under /b"], report["unchanged"]
        )
        self.assertEqual(["/b"], [record["target"] for record in again["records"]])

    def test_an_open_question_stays_when_no_other_target_has_an_answer(self) -> None:
        asked, _ = catalog.sync_catalog(
            _snapshot(_entry("esupport", inode=20), target="/a"),
            None,
            [_finding("esupport", owner=None)],
            [],
            "run-z",
        )
        rescan = _snapshot(_entry("esupport", inode=20), target="/a")
        catalog.annotate_entries(rescan, asked)
        self.assertTrue(rescan["entries"][0]["prior_unresolved"])
        _, report = catalog.sync_catalog(rescan, asked, [], [], "run-aa")
        self.assertEqual(["esupport"], [item["path"] for item in report["questions"]])

    def test_identity_change_under_another_target_invalidates_the_answer(self) -> None:
        first = _snapshot(_entry("esupport", inode=20), target="/root")
        answered, _ = catalog.sync_catalog(
            first, None, [], [{"path": "esupport", "disposition": "keep"}], "run-q"
        )
        moved = _snapshot(_entry("esupport", inode=77), target="/other")
        catalog.annotate_entries(moved, answered)
        self.assertNotIn("prior_disposition", moved["entries"][0])
        grown = _snapshot(
            _entry("esupport", inode=20),
            _entry("esupport/new", inode=5, kind="file"),
            target="/other",
        )
        catalog.annotate_entries(grown, answered)
        self.assertNotIn("prior_disposition", grown["entries"][0])
        _, report = catalog.sync_catalog(
            moved, answered, [_finding("esupport", owner=None)], [], "run-r"
        )
        self.assertEqual(["esupport"], [item["path"] for item in report["questions"]])

    def test_engine_records_are_not_reused_across_targets(self) -> None:
        stored, _ = catalog.sync_catalog(
            _snapshot(_entry("esupport", inode=20), target="/root"),
            None,
            [_finding("esupport")],
            [],
            "run-s",
        )
        other = _snapshot(_entry("esupport", inode=20), target="/other")
        catalog.annotate_entries(other, stored)
        self.assertNotIn("prior_disposition", other["entries"][0])

    def test_malformed_records_are_ignored_not_fatal(self) -> None:
        snapshot = _snapshot(_entry("scratch"))
        good, _ = catalog.sync_catalog(
            snapshot, None, [_finding("scratch")], [], "run-m"
        )
        hostile = {
            **good["records"][0],
            "path": ["not", "a", "string"],
            "identity": "x",
        }
        damaged = {"version": 1, "records": [hostile, "junk", {"path": "scratch"}]}
        catalog.annotate_entries(snapshot, damaged)
        self.assertNotIn("prior_disposition", snapshot["entries"][0])
        merged, _ = catalog.sync_catalog(snapshot, damaged, [], [], "run-n")
        self.assertEqual([], merged["records"])

    def test_a_record_with_an_invalid_field_value_is_ignored(self) -> None:
        snapshot = _snapshot(_entry("scratch"))
        good, _ = catalog.sync_catalog(
            snapshot, None, [_finding("scratch", tier="low")], [], "run-m"
        )
        record = good["records"][0]
        for field, value in (
            ("disposition", "delete-everything"),
            ("tier", "extreme"),
            ("source", "attacker"),
            ("owner", 7),
            ("provenance", None),
            ("size", "big"),
            ("last_seen_run", None),
            ("descendant_set", [1]),
        ):
            with self.subTest(field=field):
                tampered = {"version": 1, "records": [{**record, field: value}]}
                catalog.annotate_entries(snapshot, tampered)
                self.assertNotIn("prior_disposition", snapshot["entries"][0])
        catalog.annotate_entries(snapshot, good)
        self.assertEqual("keep", snapshot["entries"][0]["prior_disposition"])

    def test_unwalked_subtree_is_not_a_descendant_change(self) -> None:
        walked = _snapshot(_entry("big"), _entry("big/child", kind="file"))
        stored, _ = catalog.sync_catalog(walked, None, [_finding("big")], [], "run-o")
        unwalked = _snapshot({**_entry("big"), "size_qualifiers": ["not-walked"]})
        catalog.annotate_entries(unwalked, stored)
        self.assertEqual("keep", unwalked["entries"][0]["prior_disposition"])

    def test_repeating_a_finding_leaves_the_entry_unchanged(self) -> None:
        snapshot = _snapshot(_entry("loose", kind="file"))
        findings = [_finding("loose")]
        stored, _ = catalog.sync_catalog(snapshot, None, findings, [], "run-p")
        _, report = catalog.sync_catalog(snapshot, stored, findings, [], "run-q")
        self.assertEqual([], report["new_or_changed"])
        self.assertEqual(["loose | keep | notes"], report["unchanged"])

    def test_unmatched_conclusions_are_reported(self) -> None:
        stored, report = catalog.sync_catalog(
            _snapshot(_entry("here")),
            None,
            [_finding("gone")],
            [{"path": "also-gone", "owner": "x"}, {"owner": "no path"}],
            "run-k",
        )
        self.assertEqual([], stored["records"])
        self.assertEqual(["gone", "also-gone", "None"], report["unmatched"])

    def test_rendered_markdown_leads_with_changes_and_ends_with_questions(self) -> None:
        stored, report = catalog.sync_catalog(
            _snapshot(_entry("ansel", inode=11), _entry("known", inode=12)),
            None,
            [_finding("ansel", owner=None), _finding("known")],
            [],
            "run-l",
        )
        text = catalog.render_markdown(stored, report)
        self.assertLess(text.index("### New or changed"), text.index("### Unchanged"))
        self.assertLess(text.index("### Unchanged"), text.index("### Questions"))
        self.assertIn("1. `ansel`: Who owns ansel?", text)
        self.assertIn("- owner: unknown", text)


class CatalogScopeTest(unittest.TestCase):
    def snapshot(self) -> dict:
        return _snapshot(
            _entry("tool", inode=1),
            _entry("tool/data", inode=2, logical_size=9),
            _entry("tool/data/blob.bin", kind="file", inode=3, logical_size=9),
            {**_entry("tool/data/cache", inode=4, logical_size=9), "hints": ["cache"]},
            _entry("tool/empty", inode=5, logical_size=0),
            {
                **_entry("tool/cut", inode=6, logical_size=0),
                "size_qualifiers": ["not-walked"],
            },
            {**_entry("Library", inode=7), "protected_reasons": ["shell-folder"]},
            {
                **_entry("Library/x", kind="file", inode=8),
                "protected_reasons": ["shell-folder"],
            },
        )

    def test_scope_names_each_entry_shape(self) -> None:
        scope = catalog.catalog_scope(self.snapshot(), positional=True)
        self.assertEqual(
            {
                "tool": ["immediate-child", "out-of-place"],
                "tool/data/cache": ["hinted"],
                "tool/empty": ["empty"],
                "Library": ["immediate-child"],
            },
            scope,
        )

    def test_out_of_place_needs_a_home_or_root_children_target(self) -> None:
        scope = catalog.catalog_scope(self.snapshot(), positional=False)
        self.assertEqual(["immediate-child"], scope["tool"])

    def test_an_in_scope_entry_without_a_record_is_reported(self) -> None:
        _, report = catalog.sync_catalog(
            self.snapshot(), None, [_finding("tool")], [], "run-a", positional=True
        )
        self.assertEqual(
            ["Library", "tool/data/cache", "tool/empty"],
            [item["path"] for item in report["uncataloged"]],
        )
        self.assertEqual(["hinted"], report["uncataloged"][1]["reasons"])

    def test_an_owner_level_record_covers_its_descendants(self) -> None:
        stored, report = catalog.sync_catalog(
            self.snapshot(),
            None,
            [_finding("tool", owner_level=True), _finding("Library")],
            [],
            "run-b",
        )
        self.assertTrue(stored["records"][1]["owner_level"])
        self.assertEqual([], report["uncataloged"])
        self.assertIn("owner level", catalog.render_markdown(stored, report))

    def test_an_owner_level_marker_needs_an_owner(self) -> None:
        stored, report = catalog.sync_catalog(
            self.snapshot(),
            None,
            [_finding("tool", owner=None, owner_level=True), _finding("Library")],
            [],
            "run-c",
        )
        self.assertNotIn("owner_level", stored["records"][1])
        self.assertEqual(
            ["tool/data/cache", "tool/empty"],
            [item["path"] for item in report["uncataloged"]],
        )

    def test_a_record_that_lost_identity_stops_covering(self) -> None:
        snapshot = self.snapshot()
        stored, _ = catalog.sync_catalog(
            snapshot, None, [_finding("tool", owner_level=True)], [], "run-d"
        )
        snapshot["entries"][0]["inode"] = 99
        _, report = catalog.sync_catalog(snapshot, stored, [], [], "run-e")
        self.assertIn("tool/empty", [item["path"] for item in report["uncataloged"]])

    def test_a_human_answer_from_another_target_counts_as_a_record(self) -> None:
        elsewhere = {**self.snapshot(), "target": "/other"}
        stored, _ = catalog.sync_catalog(
            elsewhere, None, [], [{"path": "tool", "disposition": "keep"}], "run-f"
        )
        _, report = catalog.sync_catalog(self.snapshot(), stored, [], [], "run-g")
        self.assertNotIn("tool", [item["path"] for item in report["uncataloged"]])

    def owner_answer(self) -> dict:
        elsewhere = {**self.snapshot(), "target": "/other"}
        answer = {
            "path": "tool",
            "disposition": "keep",
            "owner": "tool vendor",
            "owner_level": True,
        }
        stored, _ = catalog.sync_catalog(elsewhere, None, [], [answer], "run-h")
        return stored

    def test_a_reused_owner_level_answer_covers_its_descendants(self) -> None:
        reached = _snapshot(
            *(
                {**entry, "path": f"vendor/{entry['path']}"}
                for entry in self.snapshot()["entries"]
                if entry["path"].startswith("tool")
            ),
        )
        _, report = catalog.sync_catalog(reached, self.owner_answer(), [], [], "run-i")
        self.assertEqual([], report["uncataloged"])

    def test_a_reused_owner_level_answer_for_the_target_covers_every_entry(
        self,
    ) -> None:
        inside = _snapshot(
            *(
                {**entry, "path": entry["path"].removeprefix("tool/")}
                for entry in self.snapshot()["entries"]
                if entry["path"].startswith("tool/")
            ),
        )
        inside["target_identity"] = _entry("tool", inode=1)
        _, report = catalog.sync_catalog(inside, self.owner_answer(), [], [], "run-j")
        self.assertEqual([], report["uncataloged"])

    def test_the_latest_answer_for_an_object_supersedes_older_ones(self) -> None:
        first = _snapshot(_entry("loose", inode=30), target="/a-first")
        second = _snapshot(_entry("loose", inode=30), target="/z-second")
        stored, _ = catalog.sync_catalog(
            first, None, [], [{"path": "loose", "disposition": "keep"}], "run-k"
        )
        stored, _ = catalog.sync_catalog(
            second, stored, [], [{"path": "loose", "disposition": "remove"}], "run-l"
        )
        third = _snapshot(_entry("loose", inode=30), target="/m-third")
        catalog.annotate_entries(third, stored)
        self.assertEqual("remove", third["entries"][0]["prior_disposition"])

    def test_an_identity_with_a_non_scalar_value_is_ignored(self) -> None:
        snapshot = _snapshot(_entry("loose"))
        good, _ = catalog.sync_catalog(
            snapshot, None, [], [{"path": "loose", "disposition": "keep"}], "run-m"
        )
        record = good["records"][0]
        record["identity"] = {**record["identity"], "inode": [1]}
        catalog.annotate_entries(snapshot, good)
        self.assertNotIn("prior_disposition", snapshot["entries"][0])
        _, report = catalog.sync_catalog(snapshot, good, [], [], "run-n")
        self.assertEqual("loose", report["uncataloged"][0]["path"])


class CatalogCommandTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.target = base / "target"
        self.data = base / "data"
        self.target.mkdir()
        self.data.mkdir()
        self.item = self.target / "loose.txt"
        self.item.write_text("hello", encoding="utf-8")

    def run_main(self, *argv: str) -> tuple[int, dict]:
        output = io.StringIO()
        with (
            mock.patch.object(hygiene, "handle_state", return_value=("clear", None)),
            mock.patch.object(hygiene, "tracked_blocker", return_value=None),
            redirect_stdout(output),
        ):
            code = hygiene.main([*argv, "--data-root", str(self.data)])
        return code, json.loads(output.getvalue())

    def scan(self, name: str) -> Path:
        path = self.data / name
        code, _ = self.run_main(
            "scan", "--target", str(self.target), "--output", str(path)
        )
        self.assertEqual(0, code)
        return path

    def write(self, name: str, payload: dict) -> Path:
        path = self.data / name
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def catalog_remove(self) -> Path:
        snapshot = self.scan("snapshot.json")
        findings = self.write(
            "findings.json",
            {"records": [_finding("loose.txt", disposition="remove", tier="low")]},
        )
        code, result = self.run_main(
            "catalog",
            "--snapshot",
            str(snapshot),
            "--run-id",
            "run-1",
            "--findings",
            str(findings),
        )
        self.assertEqual(0, code)
        self.assertEqual("catalog-complete", result["status"])
        return snapshot

    def test_catalog_writes_both_files_and_scan_annotates(self) -> None:
        self.catalog_remove()
        stored = json.loads((self.data / "catalog.json").read_text(encoding="utf-8"))
        self.assertEqual(1, stored["version"])
        self.assertEqual("remove", stored["records"][0]["disposition"])
        self.assertIn(
            "loose.txt", (self.data / "CATALOG.md").read_text(encoding="utf-8")
        )
        second = json.loads(self.scan("snapshot-2.json").read_text(encoding="utf-8"))
        annotated = next(e for e in second["entries"] if e["path"] == "loose.txt")
        self.assertEqual("remove", annotated["prior_disposition"])
        self.assertTrue(self.item.is_file())

    def test_catalog_output_lists_the_uncataloged_in_scope_entries(self) -> None:
        snapshot = self.scan("snapshot.json")
        code, result = self.run_main(
            "catalog", "--snapshot", str(snapshot), "--run-id", "run-1"
        )
        self.assertEqual(0, code)
        self.assertEqual(
            [{"path": "loose.txt", "reasons": ["immediate-child"]}],
            result["uncataloged"],
        )
        self.assertIn(
            "### Uncataloged\n\n- `loose.txt`",
            (self.data / "CATALOG.md").read_text(encoding="utf-8"),
        )

    def test_a_home_target_marks_loose_root_entries_out_of_place(self) -> None:
        snapshot = self.scan("snapshot.json")
        with mock.patch.object(hygiene, "user_home", return_value=self.target):
            code, result = self.run_main(
                "catalog", "--snapshot", str(snapshot), "--run-id", "run-1"
            )
        self.assertEqual(0, code)
        self.assertEqual(
            ["immediate-child", "out-of-place"], result["uncataloged"][0]["reasons"]
        )

    def test_a_home_target_spelled_through_a_link_is_still_the_home(self) -> None:
        link = Path(self.tmp.name) / "home-link"
        link.symlink_to(self.target, target_is_directory=True)
        snapshot = json.loads(self.scan("snapshot.json").read_text(encoding="utf-8"))
        snapshot["target"] = str(link)
        path = self.write("linked.json", snapshot)
        with mock.patch.object(hygiene, "user_home", return_value=self.target):
            code, result = self.run_main(
                "catalog", "--snapshot", str(path), "--run-id", "run-1"
            )
        self.assertEqual(0, code)
        self.assertIn("out-of-place", result["uncataloged"][0]["reasons"])

    def test_catalog_refuses_a_sizes_only_snapshot(self) -> None:
        snapshot = self.write(
            "sizes.json",
            {"target": str(self.target), "entries": [], "inventory_mode": "sizes-only"},
        )
        code, _ = self.run_main(
            "catalog", "--snapshot", str(snapshot), "--run-id", "run-1"
        )
        self.assertNotEqual(0, code)
        self.assertFalse((self.data / "catalog.json").exists())

    def test_operator_answer_file_is_persisted_as_human_source(self) -> None:
        snapshot = self.catalog_remove()
        answers = self.write(
            "answers.json",
            {"answers": [{"path": "loose.txt", "disposition": "keep"}]},
        )
        code, result = self.run_main(
            "catalog",
            "--snapshot",
            str(snapshot),
            "--run-id",
            "run-2",
            "--answers",
            str(answers),
        )
        self.assertEqual(0, code)
        self.assertEqual([], result["questions"])
        stored = json.loads((self.data / "catalog.json").read_text(encoding="utf-8"))
        self.assertEqual(
            ("human", "keep"),
            (stored["records"][0]["source"], stored["records"][0]["disposition"]),
        )

    def test_an_interrupted_catalog_write_keeps_the_previous_catalog(self) -> None:
        snapshot = self.catalog_remove()
        path = self.data / "catalog.json"
        before = path.read_text(encoding="utf-8")
        answers = self.write(
            "answers.json",
            {"answers": [{"path": "loose.txt", "disposition": "keep"}]},
        )
        with mock.patch.object(hygiene.os, "replace", side_effect=OSError("disk")):
            code, _ = self.run_main(
                "catalog",
                "--snapshot",
                str(snapshot),
                "--run-id",
                "run-2",
                "--answers",
                str(answers),
            )
        self.assertNotEqual(0, code)
        self.assertEqual(before, path.read_text(encoding="utf-8"))
        self.assertEqual([], list(self.data.glob("*.tmp")))

    def test_scan_reports_an_unreadable_catalog_and_still_completes(self) -> None:
        (self.data / "catalog.json").write_text("{not json", encoding="utf-8")
        code, result = self.run_main(
            "scan", "--target", str(self.target), "--output", str(self.data / "s.json")
        )
        self.assertEqual(0, code)
        self.assertTrue(result["catalog_unreadable"])

    def test_catalog_refuses_a_snapshot_entry_without_a_path(self) -> None:
        for entries in ([{"kind": "file"}], ["loose.txt"]):
            with self.subTest(entries=entries):
                snapshot = self.write(
                    "bad.json", {"target": str(self.target), "entries": entries}
                )
                code, _ = self.run_main(
                    "catalog", "--snapshot", str(snapshot), "--run-id", "run-1"
                )
                self.assertNotEqual(0, code)
                self.assertFalse((self.data / "catalog.json").exists())

    def test_catalog_needs_a_data_root_and_leaves_the_target_alone(self) -> None:
        snapshot = self.scan("snapshot.json")
        output = io.StringIO()
        with redirect_stdout(output):
            code = hygiene.main(
                ["catalog", "--snapshot", str(snapshot), "--run-id", "run-1"]
            )
        self.assertEqual(2, code)
        self.assertFalse((self.data / "catalog.json").exists())
        self.assertEqual("hello", self.item.read_text(encoding="utf-8"))

    def test_catalogued_remove_does_not_bypass_preview_approval_or_revalidation(
        self,
    ) -> None:
        self.catalog_remove()
        annotated = self.scan("snapshot-2.json")
        snapshot = json.loads(annotated.read_text(encoding="utf-8"))
        entry = next(e for e in snapshot["entries"] if e["path"] == "loose.txt")
        self.assertEqual("remove", entry["prior_disposition"])
        plan = self.write(
            "plan.json",
            {
                "version": 1,
                "tier": "high",
                "candidates": [
                    {
                        "path": "loose.txt",
                        "tier": "high",
                        "provenance": "fixture notes file",
                        "reason": "fixture says it is removable",
                        "evidence": ["fixture"],
                        "why_not_work_product": "fixture content is generated",
                        "risk": "low",
                        "owner": "unmanaged",
                    }
                ],
            },
        )
        code, preview = self.run_main(
            "preview", "--snapshot", str(annotated), "--plan", str(plan)
        )
        self.assertEqual(0, code)
        self.assertEqual("ready-for-explicit-approval", preview["status"])
        token = preview["approval_token"]
        report = str(self.data / "report.json")
        apply_args = (
            "apply",
            "--snapshot",
            str(annotated),
            "--plan",
            str(plan),
            "--confirm-tier",
            "high",
            "--report",
            report,
        )
        code, refused = self.run_main(*apply_args, "--approval-token", token)
        self.assertEqual(2, code)
        self.assertIn("explicit --execute", refused["error"])
        code, refused = self.run_main(
            *apply_args, "--execute", "--approval-token", "0" * 24
        )
        self.assertEqual(2, code)
        self.assertIn("approval token", refused["error"])
        self.item.write_text("changed after the scan", encoding="utf-8")
        code, blocked = self.run_main(
            *apply_args, "--execute", "--approval-token", token
        )
        self.assertEqual(3, code)
        self.assertIn("changed-since-scan", blocked["candidates"][0]["blockers"])
        self.assertTrue(self.item.is_file())


if __name__ == "__main__":
    unittest.main()

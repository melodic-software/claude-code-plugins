"""Catalog record rules: identity, scope, questions, and non-authorization."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import hygiene
import investigated_catalog as catalog


def _entry(
    path: str,
    *,
    kind: str = "directory",
    device: int = 1,
    inode: int = 10,
    logical_size: int = 4,
    hints: list | None = None,
    protected: list | None = None,
) -> dict:
    return {
        "path": path,
        "kind": kind,
        "device": device,
        "inode": inode,
        "logical_size": logical_size,
        "size_qualifiers": [],
        "hints": hints or [],
        "protected_reasons": protected or [],
    }


class CatalogRulesTest(unittest.TestCase):
    def test_identity_or_descendant_change_invalidates(self) -> None:
        entries = [
            _entry("cache", inode=3),
            _entry("cache/keep", inode=4, kind="file", logical_size=1),
        ]
        record = {
            "path": "cache",
            "identity": {"device": 1, "inode": 3, "kind": "directory"},
            "descendant_set": catalog.descendant_set("cache", entries),
        }
        self.assertTrue(catalog.identity_holds(record, entries[0], entries))
        moved = dict(entries[0])
        moved["inode"] = 99
        self.assertFalse(catalog.identity_holds(record, moved, entries))
        grown = [*entries, _entry("cache/extra", inode=5, kind="file")]
        self.assertFalse(catalog.identity_holds(record, entries[0], grown))

    def test_prior_disposition_requires_the_same_identity(self) -> None:
        entries = [_entry("loose", kind="file", inode=7, logical_size=2)]
        stored = catalog.sync_catalog(
            entries,
            None,
            [
                {
                    "path": "loose",
                    "owner": "notes",
                    "provenance": "A notes file. It is kept.",
                    "disposition": "keep",
                    "evidence": [{"source": "readme", "ref": "README"}],
                }
            ],
            [],
            "run-a",
        )[0]
        report = catalog.annotate_entries(entries, stored)
        self.assertEqual("keep", entries[0]["prior_disposition"])
        self.assertEqual([], report["new_or_changed"])
        entries[0]["inode"] = 8
        entries[0].pop("prior_disposition")
        report = catalog.annotate_entries(entries, stored)
        self.assertNotIn("prior_disposition", entries[0])
        self.assertEqual("loose", report["new_or_changed"][0]["path"])

    def test_unknown_owner_stays_keep_and_is_asked(self) -> None:
        entries = [_entry("ansel", inode=11, logical_size=0)]
        stored, report = catalog.sync_catalog(
            entries,
            None,
            [
                {
                    "path": "ansel",
                    "owner": None,
                    "provenance": "Nothing on the machine names ansel. It was kept.",
                    "disposition": "remove",
                    "evidence": [{"source": "config", "ref": "no config reference"}],
                }
            ],
            [],
            "run-b",
        )
        record = stored["records"][0]
        self.assertEqual("keep", record["disposition"])
        self.assertIsNone(record["owner"])
        self.assertEqual("ansel", report["questions"][0]["path"])
        self.assertTrue(report["new_or_changed"])
        self.assertEqual([], report["unchanged"])

    def test_human_answer_is_not_reasked_while_identity_holds(self) -> None:
        entries = [_entry("scratch", inode=12, logical_size=0)]
        first, _ = catalog.sync_catalog(entries, None, [], [], "run-c")
        self.assertIsNotNone(first["records"][0]["question"])
        answered, report = catalog.sync_catalog(
            entries,
            first,
            [
                {
                    "path": "scratch",
                    "owner": "should-not-replace",
                    "provenance": "Engine tried again. It should not win.",
                    "disposition": "remove",
                    "evidence": [{"source": "manifest", "ref": "none"}],
                }
            ],
            [
                {
                    "path": "scratch",
                    "owner": "verifier",
                    "provenance": "The operator named this verifier scratch. It stays.",
                    "disposition": "keep",
                    "evidence": [{"source": "config", "ref": "operator answer"}],
                }
            ],
            "run-d",
        )
        record = answered["records"][0]
        self.assertEqual("human", record["source"])
        self.assertEqual("verifier", record["owner"])
        self.assertIsNone(record["question"])
        self.assertEqual([], report["questions"])
        self.assertEqual(["scratch | keep | verifier"], report["unchanged"])
        again, again_report = catalog.sync_catalog(
            entries, answered, [], [], "run-e"
        )
        self.assertEqual("human", again["records"][0]["source"])
        self.assertEqual([], again_report["questions"])

    def test_human_answer_is_asked_again_when_identity_changes(self) -> None:
        entries = [_entry("scratch", inode=12, logical_size=0)]
        answered, _ = catalog.sync_catalog(
            entries,
            None,
            [],
            [
                {
                    "path": "scratch",
                    "owner": "verifier",
                    "provenance": "The operator named this verifier scratch. It stays.",
                    "disposition": "keep",
                    "evidence": [{"source": "config", "ref": "operator answer"}],
                }
            ],
            "run-f",
        )
        entries[0]["inode"] = 13
        refreshed, report = catalog.sync_catalog(entries, answered, [], [], "run-g")
        self.assertEqual("engine", refreshed["records"][0]["source"])
        self.assertIsNone(refreshed["records"][0]["owner"])
        self.assertEqual("keep", refreshed["records"][0]["disposition"])
        self.assertEqual("scratch", report["questions"][0]["path"])

    def test_scope_covers_children_hints_empties_and_owner_fold(self) -> None:
        entries = [
            _entry(".cache", inode=1),
            _entry(".cache/tool", inode=2, logical_size=0),
            _entry(".cache/tool/object", inode=3, kind="file", logical_size=9),
            _entry("mystery", inode=4, kind="file", logical_size=3),
            _entry("src", inode=5),
            _entry("src/main.py", inode=6, kind="file", logical_size=20),
        ]
        scoped = catalog.scope_paths(entries)
        self.assertEqual("immediate-child", scoped[".cache"])
        self.assertEqual("immediate-child", scoped["mystery"])
        self.assertEqual("immediate-child", scoped["src"])
        self.assertNotIn(".cache/tool", scoped)
        self.assertNotIn(".cache/tool/object", scoped)
        self.assertNotIn("src/main.py", scoped)

    def test_out_of_place_nested_entry_without_an_owner_is_catalogued(self) -> None:
        entries = [
            _entry("work", inode=1),
            _entry("work/stray.tmp", inode=2, kind="file", logical_size=8),
        ]
        scoped = catalog.scope_paths(entries)
        self.assertIn("work/stray.tmp", scoped)

    def test_catalog_disposition_does_not_authorize_deletion(self) -> None:
        record = {"disposition": "remove", "source": "human", "owner": "tool"}
        self.assertFalse(catalog.grants_deletion_authority(record))
        source = Path(hygiene.__file__).read_text(encoding="utf-8")
        apply_source = source.split("def apply_plan", 1)[1].split("\ndef ", 1)[0]
        preview_source = source.split("def preview(", 1)[1].split("\ndef ", 1)[0]
        self.assertNotIn("investigated_catalog", apply_source)
        self.assertNotIn("prior_disposition", apply_source)
        self.assertNotIn("investigated_catalog", preview_source)
        self.assertNotIn("prior_disposition", preview_source)

    def test_scan_annotates_and_catalog_command_writes_both_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "target"
            data = root / "data"
            target.mkdir()
            data.mkdir()
            (target / "loose.txt").write_text("hello", encoding="utf-8")
            (target / "empty-dir").mkdir()
            snap = data / "snapshot.json"
            code = hygiene.main(
                [
                    "scan",
                    "--target",
                    str(target),
                    "--output",
                    str(snap),
                    "--data-root",
                    str(data),
                ]
            )
            self.assertEqual(0, code)
            findings = data / "findings.json"
            findings.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "records": [
                            {
                                "path": "loose.txt",
                                "owner": "notes",
                                "provenance": (
                                    "loose.txt is a notes file. It is kept."
                                ),
                                "disposition": "remove",
                                "tier": "low",
                                "evidence": [
                                    {"source": "readme", "ref": str(target)}
                                ],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            code = hygiene.main(
                [
                    "catalog",
                    "--snapshot",
                    str(snap),
                    "--run-id",
                    "run-1",
                    "--findings",
                    str(findings),
                    "--data-root",
                    str(data),
                ]
            )
            self.assertEqual(0, code)
            stored = json.loads((data / "catalog.json").read_text(encoding="utf-8"))
            self.assertEqual(1, stored["version"])
            loose = next(item for item in stored["records"] if item["path"] == "loose.txt")
            self.assertEqual("remove", loose["disposition"])
            self.assertEqual("notes", loose["owner"])
            rendered = (data / "CATALOG.md").read_text(encoding="utf-8")
            self.assertIn("loose.txt", rendered)
            self.assertIn("Questions", rendered)
            code = hygiene.main(
                [
                    "scan",
                    "--target",
                    str(target),
                    "--output",
                    str(data / "snapshot-2.json"),
                    "--data-root",
                    str(data),
                ]
            )
            self.assertEqual(0, code)
            second = json.loads(
                (data / "snapshot-2.json").read_text(encoding="utf-8")
            )
            annotated = next(
                item for item in second["entries"] if item["path"] == "loose.txt"
            )
            self.assertEqual("remove", annotated["prior_disposition"])
            self.assertTrue((target / "loose.txt").is_file())

    def test_skill_requires_the_local_procedure_and_gates_research(self) -> None:
        text = Path(__file__).resolve().parents[1].joinpath("SKILL.md").read_text(
            encoding="utf-8"
        )
        for phrase in (
            "manifests and READMEs",
            "config file contents",
            "Get-Command",
            "running processes",
            "scheduled tasks",
            "PATH, both user and machine",
            "installed programs",
            "git remotes and status",
            "dotfile and settings references",
            "/discovery:research",
            "only when the local procedure finds no owner",
            "source: human",
            "disposition stays `keep`",
        ):
            self.assertIn(phrase, text)


if __name__ == "__main__":
    unittest.main()

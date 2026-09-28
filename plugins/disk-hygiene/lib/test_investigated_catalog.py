"""Catalog scope, invalidation, and human answers. Covers investigated_catalog.py."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import investigated_catalog as catalog


def entry(path: str, *, kind: str = "directory", hinted: bool = False, empty: bool = False, protected: bool = False, inode: int = 1) -> dict:
    return {
        "path": path,
        "kind": kind,
        "device": 7,
        "inode": inode,
        "logical_size": 0 if empty or kind == "directory" else 12,
        "size_qualifiers": [],
        "hints": [{"id": "hint"}] if hinted else [],
        "protected_reasons": ["baseline-protected-name"] if protected else [],
    }


class CatalogTests(unittest.TestCase):
    def test_scope_is_immediate_children_plus_owner_level_deeper_findings(self) -> None:
        entries = [
            entry("ansel", empty=True, inode=2),
            entry(".git", protected=True, inode=3),
            entry(".cache", inode=4),
            entry(".cache/verifier-scratch", empty=True, inode=5),
            entry(".cache/verifier-scratch/note.txt", kind="file", hinted=True, inode=6),
            entry("src/generated.tmp", kind="file", hinted=True, inode=7),
            entry("src", inode=8),
        ]
        chosen = catalog.select_catalog_paths(entries)
        self.assertIn("ansel", chosen)
        self.assertIn(".git", chosen)
        self.assertIn(".cache", chosen)
        self.assertIn(".cache/verifier-scratch", chosen)
        self.assertIn("src", chosen)
        self.assertNotIn(".cache/verifier-scratch/note.txt", chosen)
        self.assertNotIn("src/generated.tmp", chosen)

    def test_identity_or_descendant_change_invalidates_and_reopens_the_question(self) -> None:
        entries = [entry("ansel", empty=True, inode=2)]
        snapshot = {"entries": entries}
        updated, report = catalog.sync_catalog(snapshot, None, "run-1")
        self.assertEqual("new", report["lead"][0]["change"])
        self.assertEqual("keep", updated["records"][0]["disposition"])
        self.assertEqual(["ansel"], [item["path"] for item in report["questions"]])
        entries[0]["inode"] = 9
        again, second = catalog.sync_catalog(snapshot, updated, "run-2")
        self.assertEqual("invalidated", second["lead"][0]["change"])
        self.assertEqual("keep", again["records"][0]["disposition"])
        self.assertEqual("engine", again["records"][0]["source"])
        self.assertTrue(again["records"][0]["question_open"])

    def test_descendant_change_invalidates(self) -> None:
        entries = [entry(".cache", inode=4), entry(".cache/new", inode=5)]
        snapshot = {"entries": entries}
        updated, _report = catalog.sync_catalog(snapshot, None, "run-1")
        snapshot["entries"] = entries + [entry(".cache/other", inode=6)]
        _again, second = catalog.sync_catalog(snapshot, updated, "run-2")
        cache = next(row for row in second["lead"] if row["path"] == ".cache")
        self.assertEqual("invalidated", cache["change"])

    def test_human_answer_is_not_reasked_while_identity_holds(self) -> None:
        entries = [entry("ansel", empty=True, inode=2)]
        snapshot = {"entries": entries}
        answers = catalog.load_answers(
            {
                "version": 1,
                "answers": [
                    {
                        "path": "ansel",
                        "owner": "operator scratch",
                        "provenance": "The operator said this empty directory is theirs.",
                        "disposition": "keep",
                    }
                ],
            }
        )
        updated, report = catalog.sync_catalog(snapshot, None, "run-1", answers)
        self.assertEqual("human", updated["records"][0]["source"])
        self.assertEqual([], report["questions"])
        self.assertFalse(updated["records"][0]["question_open"])
        _again, second = catalog.sync_catalog(snapshot, updated, "run-2")
        self.assertEqual([], second["questions"])
        self.assertEqual([], second["lead"])
        self.assertEqual("ansel", second["unchanged"][0]["path"])

    def test_unanswered_stays_keep_and_prior_disposition_requires_identity(self) -> None:
        entries = [entry("ansel", empty=True, inode=2)]
        snapshot = {"entries": entries}
        updated, _report = catalog.sync_catalog(snapshot, None, "run-1")
        catalog.annotate_snapshot(snapshot, updated)
        self.assertEqual("keep", snapshot["entries"][0]["prior_disposition"])
        snapshot["entries"][0]["inode"] = 99
        catalog.annotate_snapshot(snapshot, updated)
        self.assertNotIn("prior_disposition", snapshot["entries"][0])

    def test_rendered_catalog_is_written_beside_the_json(self) -> None:
        updated, _report = catalog.sync_catalog(
            {"entries": [entry("ansel", empty=True)]}, None, "run-1"
        )
        with tempfile.TemporaryDirectory() as temporary:
            json_path, md_path = catalog.write_catalog(Path(temporary), updated)
            self.assertEqual("catalog.json", json_path.name)
            text = md_path.read_text(encoding="utf-8")
            self.assertIn("ansel", text)
            self.assertIn("unknown", text)
            self.assertIn("hint", text.casefold())


if __name__ == "__main__":
    unittest.main()

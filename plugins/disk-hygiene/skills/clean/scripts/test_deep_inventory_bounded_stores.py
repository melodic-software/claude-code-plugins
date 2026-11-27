#!/usr/bin/env python3

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import deep_inventory as di  # noqa: E402  (path set above)
from test_deep_inventory import NOW, TempTree  # noqa: E402  (shared fixture)


class BoundedStoreTest(TempTree):
    """Known-large stores are one bounded row, never a per-entry walk."""

    def walk(self, target: Path, stores: list, **budgets: int) -> dict[str, dict]:
        rows = di.inventory_rows(
            target,
            deep=True,
            home=self.root / "home",
            tmp_dir=self.root / "no-tmp",
            now=NOW,
            running=set(),
            claude_dir=None,
            bounded_stores=stores,
            **budgets,
        )
        return {r["name"]: r for r in rows}

    def test_store_over_its_budget_reads_only_the_budget_and_is_a_lower_bound(
        self,
    ) -> None:
        for index in range(30):
            self.write(f"home/.npm/{index:02d}", "abcd")
        rows = self.walk(self.root / "home", [".npm"], store_entry_budget=5)
        npm = rows[str(self.root / "home" / ".npm")]
        self.assertEqual(5, npm["coverage"]["entries_counted"])
        self.assertTrue(npm["coverage"]["size_is_lower_bound"])
        self.assertEqual("entry-budget-spent", npm["coverage"]["incomplete_reason"])
        self.assertEqual(20, npm["size"])
        self.assertIn("lower bound", npm["reason"])
        self.assertEqual(
            {str(self.root / "home"), str(self.root / "home" / ".npm")}, set(rows)
        )

    def test_store_that_fits_its_budget_is_complete(self) -> None:
        self.write("home/.npm/a/b/c", "12345")
        self.write("home/.npm/d", "1")
        npm = self.walk(self.root / "home", [".npm"], store_entry_budget=4)[
            str(self.root / "home" / ".npm")
        ]
        self.assertEqual(
            (6, 4, False),
            (
                npm["size"],
                npm["coverage"]["entries_counted"],
                npm["coverage"]["size_is_lower_bound"],
            ),
        )
        self.assertIn("the size is complete", npm["reason"])

    def test_total_budget_is_shared_across_stores(self) -> None:
        for name in ("alpha", "beta"):
            for index in range(4):
                self.write(f"home/{name}/{index}", "x")
        rows = self.walk(
            self.root / "home",
            ["alpha", "beta"],
            store_entry_budget=10,
            bounded_entry_budget=6,
        )
        alpha = rows[str(self.root / "home" / "alpha")]["coverage"]
        beta = rows[str(self.root / "home" / "beta")]["coverage"]
        self.assertEqual(
            (4, False), (alpha["entries_counted"], alpha["size_is_lower_bound"])
        )
        self.assertEqual(
            (2, 2, True),
            (
                beta["entry_budget"],
                beta["entries_counted"],
                beta["size_is_lower_bound"],
            ),
        )

    def test_star_names_one_segment_only(self) -> None:
        self.write("home/.cache/pip/deep/wheel", "123")
        self.write("home/.cache/README", "1")
        rows = self.walk(self.root / "home", [".cache/*"])
        cache = self.root / "home" / ".cache"
        self.assertNotIn("coverage", rows[str(cache)])
        self.assertIn(str(cache / "README"), rows)
        self.assertEqual(3, rows[str(cache / "pip")]["size"])
        self.assertEqual(".cache/*", rows[str(cache / "pip")]["coverage"]["store_glob"])
        self.assertNotIn(str(cache / "pip" / "deep"), rows)
        self.assertEqual(4, rows[str(cache)]["size"])

    def test_target_inside_a_store_is_walked_in_full(self) -> None:
        self.write("home/.npm/a/b", "12")
        rows = self.walk(self.root / "home" / ".npm" / "a", [".npm"])
        self.assertIn(str(self.root / "home" / ".npm" / "a" / "b"), rows)
        self.assertFalse(any("coverage" in row for row in rows.values()))
        rows = self.walk(self.root / "home" / ".npm", [".npm"])
        self.assertIn(str(self.root / "home" / ".npm" / "a" / "b"), rows)

    def test_absolute_glob_and_reason_object(self) -> None:
        self.write("elsewhere/store/x", "1")
        store = {
            "glob": str(self.root / "elsewhere" / "store"),
            "reason": "vendor data",
        }
        row = self.walk(self.root / "elsewhere", [store])[
            str(self.root / "elsewhere" / "store")
        ]
        self.assertEqual("vendor data", row["coverage"]["store_reason"])
        self.assertTrue(row["reason"].startswith("vendor data; summed"))

    def test_shallow_walk_of_a_store_ancestor_honors_the_store_budget(self) -> None:
        for index in range(8):
            self.write(f"home/.claude/projects/slug/{index}.jsonl", "ab")
        slug = self.root / "home" / ".claude" / "projects" / "slug"
        rows = {
            r["name"]: r
            for r in di.inventory_rows(
                self.root / "home" / ".claude",
                deep=False,
                home=self.root / "home",
                tmp_dir=self.root / "no-tmp",
                now=NOW,
                running=set(),
                claude_dir=None,
                bounded_stores=[".claude/projects/*"],
                store_entry_budget=1,
            )
        }
        coverage = rows[str(slug)]["coverage"]
        self.assertEqual(
            (1, True), (coverage["entries_counted"], coverage["size_is_lower_bound"])
        )
        self.assertEqual(2, rows[str(slug.parent)]["size"])

    def test_shallow_walk_bounds_a_store_inside_an_immediate_child(self) -> None:
        for index in range(30):
            self.write(f"home/.npm/{index:02d}", "abcd")
        self.write("home/notes", "1")
        rows = {
            r["name"]: r
            for r in di.inventory_rows(
                self.root,
                deep=False,
                home=self.root / "home",
                tmp_dir=self.root / "no-tmp",
                now=NOW,
                running=set(),
                claude_dir=None,
                bounded_stores=[".npm"],
                store_entry_budget=5,
            )
        }
        npm = rows[str(self.root / "home" / ".npm")]
        self.assertEqual(5, npm["coverage"]["entries_counted"])
        self.assertEqual(21, rows[str(self.root / "home")]["size"])

    def test_partial_report_under_a_store_is_not_counted(self) -> None:
        self.write("home/.claude/plugins/data/x/kept", "12")
        partial = self.write("home/.claude/plugins/data/x/r.jsonl.1.ab.tmp", "x" * 100)
        store = self.root / "home" / ".claude" / "plugins" / "data" / "x"
        for target, deep in ((self.root / "home", True), (store.parents[2], False)):
            with self.subTest(deep=deep):
                rows = {
                    r["name"]: r
                    for r in di.inventory_rows(
                        target,
                        deep=deep,
                        home=self.root / "home",
                        tmp_dir=self.root / "no-tmp",
                        now=NOW,
                        running=set(),
                        claude_dir=None,
                        skip=frozenset({str(partial)}),
                        bounded_stores=[".claude/plugins/data/*"],
                    )
                }
                row = rows[str(store)]
                self.assertEqual(
                    (2, 1), (row["size"], row["coverage"]["entries_counted"])
                )
                self.assertEqual(2, rows[str(target)]["size"])

    @unittest.skipIf(os.name != "posix" or os.geteuid() == 0, "needs POSIX non-root")
    def test_shallow_walk_reports_an_unreadable_descendant(self) -> None:
        self.write("scan/child/ok", "12")
        locked = self.mkdir("scan/child/locked")
        self.write("scan/child/locked/hidden", "123")
        locked.chmod(0)
        self.addCleanup(locked.chmod, 0o700)
        rows = {
            r["name"]: r
            for r in di.inventory_rows(
                self.root / "scan",
                deep=False,
                home=self.root / "home",
                tmp_dir=self.root / "no-tmp",
                now=NOW,
                running=set(),
                claude_dir=None,
            )
        }
        self.assertEqual("not-walked", rows[str(locked)]["category"])
        self.assertEqual(2, rows[str(self.root / "scan" / "child")]["size"])

    def test_classified_store_keeps_its_classification(self) -> None:
        claude = self.mkdir("home/.claude")
        slug = self.mkdir("home/.claude/projects/-definitely-missing-repo-xyz")
        self.write("home/.claude/projects/-definitely-missing-repo-xyz/s.jsonl", "{}")
        rows = di.inventory_rows(
            self.root / "home",
            deep=True,
            home=self.root / "home",
            tmp_dir=self.root / "no-tmp",
            now=NOW,
            running=set(),
            claude_dir=claude,
            bounded_stores=[".claude/projects/*"],
        )
        row = {r["name"]: r for r in rows}[str(slug)]
        self.assertEqual(
            ("transcript-dir", "CANDIDATE"), (row["category"], row["disposition"])
        )
        self.assertEqual(1, row["coverage"]["entries_counted"])

    @unittest.skipIf(os.name != "posix" or os.geteuid() == 0, "needs POSIX non-root")
    def test_unreadable_part_of_a_store_is_a_lower_bound(self) -> None:
        self.write("home/.npm/ok", "12")
        locked = self.mkdir("home/.npm/locked")
        self.write("home/.npm/locked/hidden", "123")
        locked.chmod(0)
        self.addCleanup(locked.chmod, 0o700)
        npm = self.walk(self.root / "home", [".npm"])[str(self.root / "home" / ".npm")]
        self.assertTrue(npm["coverage"]["size_is_lower_bound"])
        self.assertEqual("unreadable-directory", npm["coverage"]["incomplete_reason"])
        self.assertEqual(2, npm["size"])

    def test_bounded_store_reads_only_its_budget_of_directory_entries(self) -> None:
        for index in range(50):
            self.write(f"home/.npm/d{index:02d}/f", "x")
        real_scandir = os.scandir
        opened: list[str] = []

        def counting(path):
            opened.append(str(path))
            return real_scandir(path)

        with mock.patch.object(di.os, "scandir", side_effect=counting):
            self.walk(self.root / "home", [".npm"], store_entry_budget=10)
        under = [p for p in opened if p.startswith(str(self.root / "home" / ".npm"))]
        self.assertLessEqual(len(under), 10)


if __name__ == "__main__":
    unittest.main()

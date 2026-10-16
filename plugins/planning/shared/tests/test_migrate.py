"""migrate.py brings a session file to the current schemaVersion and refuses one it cannot read."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

SHARED = Path(__file__).resolve().parent.parent
if str(SHARED) not in sys.path:
    sys.path.insert(0, str(SHARED))

import migrate  # noqa: E402


class TestMigrate(unittest.TestCase):
    def test_current_version_comes_back_unchanged(self):
        doc = {"schemaVersion": 1, "rev": 3}
        self.assertEqual(migrate.migrate(doc), {"schemaVersion": 1, "rev": 3})

    def test_newer_version_is_refused_naming_both_versions(self):
        with self.assertRaises(migrate.MigrationError) as ctx:
            migrate.migrate({"schemaVersion": 2})
        self.assertIn("schemaVersion 2", str(ctx.exception))
        self.assertIn("newer than 1", str(ctx.exception))

    def test_missing_or_non_integer_version_is_refused(self):
        for doc in (
            {},
            {"schemaVersion": "1"},
            {"schemaVersion": True},
            {"schemaVersion": 0},
        ):
            with self.assertRaises(migrate.MigrationError):
                migrate.migrate(doc)

    def test_steps_run_in_order_and_stamp_each_version_without_touching_the_input(self):
        steps = {
            1: lambda d: {**d, "trail": d.get("trail", []) + ["1to2"]},
            2: lambda d: {**d, "trail": d["trail"] + ["2to3"]},
        }
        doc = {"schemaVersion": 1}
        with (
            mock.patch.object(migrate, "CURRENT", 3),
            mock.patch.dict(migrate.MIGRATIONS, steps),
        ):
            out = migrate.migrate(doc)
        self.assertEqual(out, {"schemaVersion": 3, "trail": ["1to2", "2to3"]})
        self.assertEqual(doc, {"schemaVersion": 1})

    def test_a_gap_in_the_chain_is_refused(self):
        with (
            mock.patch.object(migrate, "CURRENT", 2),
            self.assertRaises(migrate.MigrationError) as ctx,
        ):
            migrate.migrate({"schemaVersion": 1})
        self.assertIn("no migration from schemaVersion 1 to 2", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()

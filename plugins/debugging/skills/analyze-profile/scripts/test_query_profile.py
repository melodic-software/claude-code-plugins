"""Tests for query_profile.py, run against a database built from the cpuprofile fixture."""

import contextlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONVERT = HERE / "trace_to_sqlite.py"
QUERY = HERE / "query_profile.py"


def run(script, *args):
    return subprocess.run(
        [sys.executable, str(script), *map(str, args)],
        capture_output=True,
        text=True,
        check=False,
    )


class QueryProfile(unittest.TestCase):
    def setUp(self):
        tmp = Path(tempfile.mkdtemp(prefix="query-profile-test-"))
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        self.db = tmp / "dir with space" / "checkout.db"
        self.db.parent.mkdir()
        built = run(
            CONVERT, "--in", HERE / "fixtures" / "checkout.cpuprofile", "--out", self.db
        )
        self.assertEqual(built.returncode, 0, built.stderr)

    def test_prints_header_and_tab_separated_rows(self):
        result = run(
            QUERY, self.db, "SELECT name, line FROM frames WHERE id >= 4 ORDER BY id"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout, "name\tline\nrenderLineItems\t4\nformatPrice\t6\n"
        )

    def test_binds_named_parameters(self):
        result = run(
            QUERY,
            self.db,
            "SELECT COUNT(*) FROM samples WHERE frame = :id",
            "--param",
            "id=5",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[1], "5")

    def assert_refused_cleanly(self, result):
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(len(result.stderr.splitlines()), 1, result.stderr)

    def test_refuses_to_write(self):
        self.assert_refused_cleanly(run(QUERY, self.db, "DELETE FROM frames"))
        with contextlib.closing(sqlite3.connect(self.db)) as con:
            self.assertEqual(
                con.execute("SELECT COUNT(*) FROM frames").fetchone()[0], 5
            )

    def test_refuses_statements_that_create_files(self):
        target = self.db.with_name("copy.db")
        for sql in (
            f"ATTACH DATABASE '{target}' AS copy",
            f"VACUUM INTO '{target}'",
            "VACUUM",
        ):
            with self.subTest(sql=sql.split()[0]):
                self.assert_refused_cleanly(run(QUERY, self.db, sql))
                self.assertFalse(target.exists())

    def test_refuses_pragma(self):
        self.assert_refused_cleanly(run(QUERY, self.db, "PRAGMA journal_mode = WAL"))

    def test_recursive_query_is_allowed(self):
        result = run(
            QUERY,
            self.db,
            "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 3) "
            "SELECT SUM(i) AS total FROM n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "total\n6\n")

    def test_parameter_too_large_for_sqlite(self):
        self.assert_refused_cleanly(
            run(QUERY, self.db, "SELECT :n", "--param", f"n={2**63}")
        )

    def test_missing_database(self):
        result = run(QUERY, self.db.with_name("absent.db"), "SELECT 1")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()

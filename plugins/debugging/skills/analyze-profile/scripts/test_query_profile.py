"""Tests for query_profile.py, run against a database built from the cpuprofile fixture."""

import contextlib
import json
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

    def test_decimal_parameter_binds_as_a_number(self):
        result = run(
            QUERY,
            self.db,
            "SELECT typeof(:t), typeof(:n), typeof(:s)",
            "--param",
            "t=1000.5",
            "--param",
            "n=nan",
            "--param",
            "s=7:0x1",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[1], "real\ttext\ttext")

    def test_parameter_too_large_for_sqlite(self):
        self.assert_refused_cleanly(
            run(QUERY, self.db, "SELECT :n", "--param", f"n={2**63}")
        )

    def test_missing_database(self):
        result = run(QUERY, self.db.with_name("absent.db"), "SELECT 1")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")


NODE_TYPES = ["hidden", "array", "string", "object", "code", "closure", "synthetic"]
EDGE_TYPES = ["context", "element", "property", "internal", "hidden", "shortcut", "weak"]
ROOT = ("synthetic", "", 0)


def snapshot(nodes, edges):
    """A heap snapshot in the fixture's snapshot.meta layout.

    nodes: (type, name, self_size) per node, in idx order; node_id is idx * 2 + 1.
    edges: (from idx, type, name, to idx); an edge's seq follows its owner's idx,
    then its place in this list.
    """
    strings = [""]

    def intern(text):
        if text not in strings:
            strings.append(text)
        return strings.index(text)

    flat_nodes, flat_edges = [], []
    for idx, (kind, name, size) in enumerate(nodes):
        owned = [edge for edge in edges if edge[0] == idx]
        flat_nodes += [NODE_TYPES.index(kind), intern(name), idx * 2 + 1, size, len(owned), 0, 0]
        for _, edge_type, edge_name, target in owned:
            by_index = edge_type in ("element", "hidden")
            flat_edges += [
                EDGE_TYPES.index(edge_type),
                int(edge_name) if by_index else intern(edge_name),
                target * 7,
            ]
    return {
        "snapshot": {
            "meta": {
                "node_fields": ["type", "name", "id", "self_size", "edge_count", "trace_node_id", "detachedness"],
                "node_types": [NODE_TYPES, "string", "number", "number", "number", "number", "number"],
                "edge_fields": ["type", "name_or_index", "to_node"],
                "edge_types": [EDGE_TYPES, "string_or_number", "node"],
            },
            "node_count": len(nodes),
            "edge_count": len(edges),
        },
        "nodes": flat_nodes,
        "edges": flat_edges,
        "strings": strings,
    }


class HeapQueries(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="query-heap-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def convert(self, name, data=None):
        src = HERE / "fixtures" / "session-cache.heapsnapshot"
        if data is not None:
            src = self.tmp / f"{name}.heapsnapshot"
            src.write_text(json.dumps(data))
        db = self.tmp / f"{name}.db"
        built = run(CONVERT, "--in", src, "--out", db)
        self.assertEqual(built.returncode, 0, built.stderr)
        return db

    def inline(self, name, nodes, edges):
        return self.convert(name, snapshot(nodes, edges))

    def assert_refused(self, result, code=2):
        self.assertEqual(result.returncode, code)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(len(result.stderr.splitlines()), 1, result.stderr)

    def test_retainers_walks_the_fixture_chain_to_the_root(self):
        db = self.convert("fixture")
        result = run(QUERY, "retainers", db, 4)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "depth\tidx\tnode_id\ttype\tname\tvia\n"
            "0\t4\t9\tstring\torder payload\t\n"
            "1\t3\t7\tobject\tSessionCache\tproperty:lastOrder\n"
            "2\t2\t5\tobject\tWindow\tproperty:sessionCache\n"
            "3\t1\t3\tsynthetic\t(GC roots)\telement:1\n"
            "4\t0\t1\tsynthetic\t\telement:1\n",
        )

    def test_retainers_prefers_the_shortest_path_over_the_first_holder(self):
        db = self.inline(
            "short",
            [ROOT, ("object", "A", 8), ("object", "B", 8), ("object", "C", 8),
             ("object", "D", 8), ("string", "target", 100)],
            [(0, "property", "a", 1), (0, "property", "d", 4), (1, "property", "b", 2),
             (2, "property", "c", 3), (3, "property", "t", 5), (4, "property", "t2", 5)],
        )
        result = run(QUERY, "retainers", db, 5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "depth\tidx\tnode_id\ttype\tname\tvia\n"
            "0\t5\t11\tstring\ttarget\t\n"
            "1\t4\t9\tobject\tD\tproperty:t2\n"
            "2\t0\t1\tsynthetic\t\tproperty:d\n",
        )

    def test_retainers_skips_weak_edges(self):
        db = self.inline(
            "weak", [ROOT, ("object", "X", 8)], [(0, "weak", "w", 1)]
        )
        self.assert_refused(run(QUERY, "retainers", db, 1), code=1)

    def test_retainers_ends_a_cycle_with_the_path(self):
        db = self.inline(
            "cycle",
            [ROOT, ("object", "A", 8), ("object", "B", 8)],
            [(0, "property", "a", 1), (1, "property", "b", 2), (2, "property", "a2", 1)],
        )
        result = run(QUERY, "retainers", db, 2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "depth\tidx\tnode_id\ttype\tname\tvia\n"
            "0\t2\t5\tobject\tB\t\n"
            "1\t1\t3\tobject\tA\tproperty:b\n"
            "2\t0\t1\tsynthetic\t\tproperty:a\n",
        )

    def test_retainers_on_a_cycle_the_root_does_not_hold_exits_1(self):
        db = self.inline(
            "orphans",
            [ROOT, ("object", "A", 8), ("object", "B", 8)],
            [(1, "property", "b", 2), (2, "property", "a", 1)],
        )
        self.assert_refused(run(QUERY, "retainers", db, 2), code=1)

    def test_retainers_refuses_an_unknown_idx(self):
        self.assert_refused(run(QUERY, "retainers", self.convert("fixture"), 99))

    def test_subcommands_refuse_a_cpuprofile_database(self):
        cpu = self.tmp / "checkout.db"
        built = run(CONVERT, "--in", HERE / "fixtures" / "checkout.cpuprofile", "--out", cpu)
        self.assertEqual(built.returncode, 0, built.stderr)
        heap = self.convert("fixture")
        self.assert_refused(run(QUERY, "retainers", cpu, 0))
        self.assert_refused(run(QUERY, "compare", cpu, heap))
        self.assert_refused(run(QUERY, "compare", heap, cpu))

    def test_subcommands_refuse_bad_usage_and_missing_databases(self):
        heap = self.convert("fixture")
        absent = self.tmp / "absent.db"
        self.assert_refused(run(QUERY, "retainers", heap))
        self.assert_refused(run(QUERY, "retainers", heap, "x"))
        self.assert_refused(run(QUERY, "retainers", absent, 0))
        self.assert_refused(run(QUERY, "compare", heap))
        self.assert_refused(run(QUERY, "compare", heap, absent))
        self.assert_refused(run(QUERY, "compare", heap, heap, "--limit", "-1"))

    def snapshots_to_compare(self):
        before = self.inline(
            "before",
            [ROOT, ("object", "Item", 10), ("object", "Item", 10), ("object", "Item", 10),
             ("object", "Gone", 50), ("object", "Gone", 50), ("string", "label", 5)],
            [],
        )
        after = self.inline(
            "after",
            [ROOT, ("object", "Item", 10), ("object", "Item", 10), ("object", "Item", 10),
             ("object", "Item", 10), ("object", "Item", 10), ("object", "Gone", 50),
             ("closure", "Fresh", 100), ("closure", "Fresh", 100), ("string", "label", 5)],
            [],
        )
        return before, after

    def test_compare_orders_growth_first_and_counts_missing_as_zero(self):
        before, after = self.snapshots_to_compare()
        result = run(QUERY, "compare", before, after)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "type\tname\tbefore_n\tafter_n\tdelta_n\tbefore_bytes\tafter_bytes\tdelta_bytes\n"
            "closure\tFresh\t0\t2\t2\t0\t200\t200\n"
            "object\tItem\t3\t5\t2\t30\t50\t20\n"
            "string\tlabel\t1\t1\t0\t5\t5\t0\n"
            "synthetic\t\t1\t1\t0\t0\t0\t0\n"
            "object\tGone\t2\t1\t-1\t100\t50\t-50\n",
        )

    def test_compare_limit_keeps_the_header_and_the_first_rows(self):
        before, after = self.snapshots_to_compare()
        result = run(QUERY, "compare", before, after, "--limit", 1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "type\tname\tbefore_n\tafter_n\tdelta_n\tbefore_bytes\tafter_bytes\tdelta_bytes\n"
            "closure\tFresh\t0\t2\t2\t0\t200\t200\n",
        )

    def test_compare_leaves_the_databases_and_their_folder_unchanged(self):
        before, after = self.snapshots_to_compare()

        def state():
            counts = []
            for db in (before, after):
                with contextlib.closing(sqlite3.connect(db)) as con:
                    counts.append(
                        [con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                         for t in ("nodes", "edges", "meta")]
                    )
            return counts, sorted(p.name for p in self.tmp.iterdir())

        seen = state()
        self.assertEqual(run(QUERY, "compare", before, after).returncode, 0)
        self.assertEqual(state(), seen)


if __name__ == "__main__":
    unittest.main()

"""Tests for trace_to_sqlite.py. Expected counts are hand-counted from the fixtures."""

import contextlib
import gzip
import importlib.util
import io
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "trace_to_sqlite.py"
FIXTURES = HERE / "fixtures"
CPUPROFILE = FIXTURES / "checkout.cpuprofile"
TRACE = FIXTURES / "render.trace.json"
HEAP = FIXTURES / "session-cache.heapsnapshot"


def run(*args, cwd=None):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *map(str, args)],
        capture_output=True,
        text=True,
        cwd=cwd,
        check=False,
    )


def count(db, table):
    with contextlib.closing(sqlite3.connect(db)) as con:
        return con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]


def query(db, sql, params=()):
    with contextlib.closing(sqlite3.connect(db)) as con:
        return con.execute(sql, params).fetchall()


class TempDirCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="trace-to-sqlite-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def write_json(self, name, data):
        path = self.tmp / name
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def assert_refused(self, result, out):
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertFalse(out.exists())
        self.assertFalse(Path(str(out) + ".partial").exists())


class LoadsEachFormat(TempDirCase):
    def test_cpuprofile_tables(self):
        out = self.tmp / "cpu.db"
        result = run("--in", CPUPROFILE, "--out", out)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(count(out, "frames"), 5)
        self.assertEqual(count(out, "samples"), 7)
        self.assertEqual(count(out, "nodes"), 0)
        self.assertEqual(count(out, "edges"), 0)
        hottest = query(
            out,
            "SELECT f.name, f.url, f.line, COUNT(*) AS n FROM samples s "
            "JOIN frames f ON f.profile = s.profile AND f.id = s.frame "
            "GROUP BY f.profile, f.id ORDER BY n DESC LIMIT 1",
        )
        self.assertEqual(
            hottest,
            [("formatPrice", "file:///srv/checkout/src/pricing/format.js", 6, 5)],
        )
        self.assertEqual(
            query(out, "SELECT parent FROM frames WHERE name = 'formatPrice'"), [(4,)]
        )

    def test_chrome_trace_tables(self):
        out = self.tmp / "trace.db"
        result = run("--in", TRACE, "--out", out, "--format", "chrome-trace")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(count(out, "events"), 5)
        self.assertEqual(count(out, "frames"), 3)
        self.assertEqual(count(out, "samples"), 4)
        self.assertEqual(
            query(out, "SELECT dur FROM events WHERE name = 'Layout'"),
            [(31000,)],
        )
        self.assertEqual(
            query(out, "SELECT line FROM frames WHERE name = 'measureRows'"),
            [(88,)],
        )

    def test_heapsnapshot_tables(self):
        out = self.tmp / "heap.db"
        result = run("--in", HEAP, "--out", out, "--format", "heapsnapshot")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(count(out, "nodes"), 5)
        self.assertEqual(count(out, "edges"), 4)
        self.assertEqual(
            query(
                out,
                "SELECT n.name, e.type, e.name, t.type, t.name, t.self_size FROM edges e "
                "JOIN nodes n ON n.idx = e.from_idx JOIN nodes t ON t.idx = e.to_idx "
                "WHERE t.self_size = 4096",
            ),
            [
                (
                    "SessionCache",
                    "property",
                    "lastOrder",
                    "string",
                    "order payload",
                    4096,
                )
            ],
        )


class DetectsFormat(TempDirCase):
    def test_auto_identifies_each_format(self):
        for fixture, expected in (
            (CPUPROFILE, "cpuprofile"),
            (TRACE, "chrome-trace"),
            (HEAP, "heapsnapshot"),
        ):
            with self.subTest(expected=expected):
                out = self.tmp / f"{expected}.db"
                result = run("--in", fixture, "--out", out, "--format", "auto")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    query(out, "SELECT value FROM meta WHERE key = 'format'"),
                    [(expected,)],
                )
                self.assertEqual(json.loads(result.stdout)["format"], expected)

    def test_bare_event_array_is_a_chrome_trace(self):
        path = self.write_json(
            "events.json",
            [{"name": "RunTask", "ph": "X", "ts": 1, "dur": 2, "pid": 1, "tid": 1}],
        )
        out = self.tmp / "events.db"
        result = run("--in", path, "--out", out)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(count(out, "events"), 1)


class RefusesBadInput(TempDirCase):
    def test_malformed_json(self):
        path = self.tmp / "broken.cpuprofile"
        path.write_text('{"nodes": [', encoding="utf-8")
        out = self.tmp / "broken.db"
        self.assert_refused(run("--in", path, "--out", out), out)

    def test_shape_that_does_not_match_the_named_format(self):
        out = self.tmp / "wrong.db"
        self.assert_refused(
            run("--in", CPUPROFILE, "--out", out, "--format", "heapsnapshot"), out
        )

    def test_heap_edge_pointing_outside_the_node_array(self):
        data = json.loads(HEAP.read_text(encoding="utf-8"))
        data["edges"][-1] = 700
        path = self.write_json("bad-edge.heapsnapshot", data)
        out = self.tmp / "bad-edge.db"
        self.assert_refused(run("--in", path, "--out", out), out)

    def test_heap_negative_type_or_name_index(self):
        # nodes are 7 fields (type, name first); edges are 3 (type, name_or_index,
        # to_node), and edge 2 is a property edge, so its name indexes strings.
        for label, array, at in (
            ("node type", "nodes", 0),
            ("node name", "nodes", 1),
            ("edge type", "edges", 0),
            ("edge name", "edges", 7),
        ):
            with self.subTest(label):
                data = json.loads(HEAP.read_text(encoding="utf-8"))
                data[array][at] = -1
                path = self.write_json(f"neg-{at}-{array}.heapsnapshot", data)
                out = self.tmp / f"neg-{at}-{array}.db"
                self.assert_refused(run("--in", path, "--out", out), out)

    def test_heap_edges_beyond_the_edge_counts(self):
        data = json.loads(HEAP.read_text(encoding="utf-8"))
        data["edges"] += [2, 5, 7]
        path = self.write_json("extra-edge.heapsnapshot", data)
        out = self.tmp / "extra-edge.db"
        self.assert_refused(run("--in", path, "--out", out), out)

    def test_unknown_format(self):
        path = self.write_json("other.json", {"rows": [1, 2, 3]})
        out = self.tmp / "other.db"
        self.assert_refused(run("--in", path, "--out", out), out)

    def test_unknown_format_name(self):
        out = self.tmp / "pprof.db"
        self.assert_refused(
            run("--in", CPUPROFILE, "--out", out, "--format", "pprof"), out
        )

    def test_existing_out_is_not_overwritten(self):
        out = self.tmp / "keep.db"
        out.write_bytes(b"earlier result")
        result = run("--in", CPUPROFILE, "--out", out)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(out.read_bytes(), b"earlier result")

    def test_missing_input(self):
        out = self.tmp / "none.db"
        self.assert_refused(
            run("--in", self.tmp / "absent.cpuprofile", "--out", out), out
        )

    def test_missing_arguments(self):
        result = run("--in", CPUPROFILE)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")


class TreatsContentAsData(TempDirCase):
    def test_path_with_a_space(self):
        folder = self.tmp / "captured profiles"
        folder.mkdir()
        src = folder / "checkout run 2.cpuprofile"
        shutil.copyfile(CPUPROFILE, src)
        out = folder / "checkout run 2.db"
        result = run("--in", src, "--out", out)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(count(out, "frames"), 5)

    def test_shell_text_in_a_frame_name_stays_text(self):
        hostile = "$(touch PWNED)"
        data = json.loads(CPUPROFILE.read_text(encoding="utf-8"))
        data["nodes"][4]["callFrame"]["functionName"] = hostile
        path = self.write_json("hostile.cpuprofile", data)
        out = self.tmp / "hostile.db"
        result = run("--in", path, "--out", out, cwd=self.tmp)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            query(out, "SELECT name FROM frames WHERE id = 5"), [(hostile,)]
        )
        self.assertFalse((self.tmp / "PWNED").exists())
        self.assertFalse((HERE / "PWNED").exists())

    def test_secret_shaped_strings_are_redacted(self):
        github_token = "ghp_" + "Q7" * 18
        aws_key = "AKIA" + "QWERTYUIOPASDFGH"
        bearer = "Bearer " + "eyJhbGciOi.payload.sig"
        data = json.loads(HEAP.read_text(encoding="utf-8"))
        data["strings"][4] = github_token
        data["strings"][5] = aws_key
        data["strings"][6] = bearer
        path = self.write_json("secrets.heapsnapshot", data)
        out = self.tmp / "secrets.db"
        result = run("--in", path, "--out", out)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            query(out, "SELECT name FROM nodes WHERE idx = 4"), [("<REDACTED>",)]
        )
        self.assertEqual(
            query(out, "SELECT name FROM edges ORDER BY seq")[2:],
            [("<REDACTED>",), ("<REDACTED>",)],
        )
        with contextlib.closing(sqlite3.connect(out)) as con:
            dump = "\n".join(con.iterdump())
        for secret in (github_token, aws_key, "eyJhbGciOi"):
            self.assertNotIn(secret, dump)


GITHUB_TOKEN = "ghp_" + "Zx4" * 12
# The stateless installation token is ghs_ then a JWT of about 520 characters: three
# base64url segments joined by '.', each segment obviously fake, with and without an
# app-id-like prefix.
JWT_SEGMENT = "FAKE-not_a_token" * 10
JWT = ".".join([JWT_SEGMENT] * 3)
STATELESS_TOKEN = "ghs" + "_123456_" + JWT
JWT_TOKEN = "ghs" + "_" + JWT
AWS_KEY = "AKIA" + "MNBVCXZLKJHGFDSA"


def dump(db):
    with contextlib.closing(sqlite3.connect(db)) as con:
        return "\n".join(con.iterdump())


class RedactsEveryStringField(TempDirCase):
    def test_stateless_installation_token_is_redacted_whole(self):
        path = self.write_json(
            "stateless.json",
            {
                "traceEvents": [
                    {
                        "name": "RunTask",
                        "ph": "X",
                        "args": {"t": f"x {STATELESS_TOKEN} y", "u": f"x {JWT_TOKEN} y"},
                    }
                ]
            },
        )
        out = self.tmp / "stateless.db"
        result = run("--in", path, "--out", out)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("FAKE-not_a_token", dump(out))
        self.assertIn("<REDACTED>", dump(out))

    def test_trace_event_phase_and_pid(self):
        path = self.write_json(
            "tokens.json",
            {"traceEvents": [{"name": "RunTask", "ph": GITHUB_TOKEN, "pid": AWS_KEY}]},
        )
        out = self.tmp / "tokens.db"
        result = run("--in", path, "--out", out)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            query(out, "SELECT ph, pid FROM events"), [("<REDACTED>", "<REDACTED>")]
        )
        self.assertNotIn(GITHUB_TOKEN, dump(out))
        self.assertNotIn(AWS_KEY, dump(out))

    def test_bearer_token_after_tab_or_newline_in_args(self):
        args = {"auth": "Bearer\tqx81.secretpart", "note": ["Bearer\nzv93.secretpart"]}
        path = self.write_json(
            "bearer.json", {"traceEvents": [{"name": "RunTask", "args": args}]}
        )
        out = self.tmp / "bearer.db"
        result = run("--in", path, "--out", out)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("secretpart", dump(out))

    def test_heap_node_type_and_element_edge_name(self):
        data = json.loads(HEAP.read_text(encoding="utf-8"))
        data["snapshot"]["meta"]["node_types"][0][9] = GITHUB_TOKEN
        data["edges"][1] = AWS_KEY
        path = self.write_json("tokens.heapsnapshot", data)
        out = self.tmp / "tokens-heap.db"
        result = run("--in", path, "--out", out)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            query(out, "SELECT type FROM nodes WHERE idx IN (0, 1)"),
            [("<REDACTED>",), ("<REDACTED>",)],
        )
        self.assertEqual(
            query(out, "SELECT type, name FROM edges WHERE seq = 0"),
            [("element", "<REDACTED>")],
        )
        self.assertNotIn(GITHUB_TOKEN, dump(out))
        self.assertNotIn(AWS_KEY, dump(out))


class RefusesCleanly(TempDirCase):
    def assert_one_line_refusal(self, path):
        out = self.tmp / (path.name + ".db")
        result = run("--in", path, "--out", out)
        self.assert_refused(result, out)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(len(result.stderr.splitlines()), 1, result.stderr)

    def test_deeply_nested_json(self):
        path = self.tmp / "deep.json"
        path.write_text("[" * 200_000 + "]" * 200_000, encoding="utf-8")
        self.assert_one_line_refusal(path)

    def test_timestamp_too_large_for_sqlite(self):
        path = self.write_json(
            "huge-ts.json", {"traceEvents": [{"name": "RunTask", "ts": 10**30}]}
        )
        self.assert_one_line_refusal(path)

    def test_heap_with_empty_node_fields(self):
        data = json.loads(HEAP.read_text(encoding="utf-8"))
        data["snapshot"]["meta"]["node_fields"] = []
        self.assert_one_line_refusal(self.write_json("no-fields.heapsnapshot", data))


class CapsInputSize(TempDirCase):
    def run_capped(self, path, out, cap):
        spec = importlib.util.spec_from_file_location("trace_to_sqlite", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.object(module, "MAX_INPUT_BYTES", cap):
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                status = module.main(["--in", str(path), "--out", str(out)])
        return status, stdout.getvalue(), stderr.getvalue()

    def test_gzip_that_expands_past_the_cap_is_refused(self):
        body = json.dumps({"traceEvents": [], "padding": "0" * 200_000}).encode()
        path = self.tmp / "bomb.json.gz"
        path.write_bytes(gzip.compress(body))
        self.assertLess(path.stat().st_size, 10_000)
        out = self.tmp / "bomb.db"
        status, stdout, stderr = self.run_capped(path, out, 10_000)
        self.assertEqual(status, 2)
        self.assertEqual(stdout, "")
        self.assertIn("larger than 10000 bytes", stderr)
        self.assertFalse(out.exists())

    def test_gzip_under_the_cap_loads(self):
        body = json.dumps({"traceEvents": [{"name": "RunTask", "ph": "X"}]}).encode()
        path = self.tmp / "small.json.gz"
        path.write_bytes(gzip.compress(body))
        out = self.tmp / "small.db"
        status, _, stderr = self.run_capped(path, out, 10_000)
        self.assertEqual(status, 0, stderr)
        self.assertEqual(count(out, "events"), 1)


class WritesAtomically(TempDirCase):
    def load_module(self):
        spec = importlib.util.spec_from_file_location("trace_to_sqlite", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_rename_is_the_last_step(self):
        module = self.load_module()
        out = self.tmp / "renamed.db"
        seen = []
        real_replace = os.replace

        def fake_replace(src, dst):
            seen.append((Path(src), Path(dst), Path(src).exists(), Path(dst).exists()))
            real_replace(src, dst)

        stdout = io.StringIO()
        with mock.patch.object(module.os, "replace", side_effect=fake_replace):
            with contextlib.redirect_stdout(stdout):
                status = module.main(["--in", str(CPUPROFILE), "--out", str(out)])
        self.assertEqual(status, 0)
        self.assertEqual(json.loads(stdout.getvalue())["tables"]["frames"], 5)
        self.assertEqual(seen, [(Path(str(out) + ".partial"), out, True, False)])

    def test_run_stopped_before_the_rename_leaves_no_out(self):
        module = self.load_module()
        out = self.tmp / "stopped.db"
        with mock.patch.object(module.os, "replace", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                module.main(["--in", str(CPUPROFILE), "--out", str(out)])
        self.assertFalse(out.exists())


FORMATS_DIR = HERE.parent / "reference" / "formats"


def doc_query(page, lead):
    """The first ```sql block after the line starting with lead on a format page."""
    text = (FORMATS_DIR / page).read_text(encoding="utf-8")
    after = text[text.index("\n" + lead) :]
    start = after.index("```sql\n") + len("```sql\n")
    return after[start : after.index("```", start)]


def chunk(pid, pid_id, nodes, samples, deltas):
    return {
        "name": "ProfileChunk",
        "ph": "P",
        "pid": pid,
        "id": pid_id,
        "ts": 0,
        "args": {
            "data": {
                "cpuProfile": {"nodes": nodes, "samples": samples},
                "timeDeltas": deltas,
            }
        },
    }


def node(node_id, name, parent=None):
    entry = {"id": node_id, "callFrame": {"functionName": name, "url": ""}}
    if parent is not None:
        entry["parent"] = parent
    return entry


class FormatPageQueries(TempDirCase):
    """The format pages' queries keep two profiles of one trace apart."""

    def two_profile_db(self):
        # Both profiles number their nodes from 1, as each pid:id profile does.
        trace = self.write_json(
            "two.trace.json",
            [
                chunk(
                    7,
                    "0x1",
                    [
                        node(1, "(root)"),
                        node(2, "alpha", 1),
                        node(3, "(garbage collector)", 1),
                    ],
                    [3, 3, 2],
                    [10, 10, 10],
                ),
                chunk(
                    7,
                    "0x2",
                    [node(1, "(root)"), node(2, "beta", 1), node(3, "(program)", 1)],
                    [3, 2],
                    [10, 10],
                ),
            ],
        )
        out = self.tmp / "two.db"
        result = run("--in", trace, "--out", out)
        self.assertEqual(result.returncode, 0, result.stderr)
        return out

    def test_caller_path_stays_inside_one_profile(self):
        db = self.two_profile_db()
        sql = doc_query("cpuprofile.md", "Caller path above one frame")
        rows = query(db, sql, {"profile": "7:0x2", "id": 2})
        self.assertEqual([(d, n) for d, n, *_ in rows], [(0, "beta"), (1, "(root)")])

    def test_outside_javascript_counts_each_sample_once(self):
        db = self.two_profile_db()
        sql = doc_query("cpuprofile.md", "Share of the run spent outside JavaScript")
        self.assertEqual(
            sorted(query(db, sql)),
            [("7:0x1", "(garbage collector)", 2), ("7:0x2", "(program)", 1)],
        )


class SamplesOnTheTraceClock(TempDirCase):
    """samples.ts is the profile's startTime plus the deltas up to that sample."""

    def test_trace_samples_carry_trace_clock_ts_and_join_events(self):
        trace = self.write_json(
            "clock.trace.json",
            [
                {"name": "Task", "ph": "X", "pid": 7, "tid": 1, "ts": 1150, "dur": 200},
                {
                    "name": "Profile",
                    "ph": "P",
                    "pid": 7,
                    "id": "0x1",
                    "ts": 1000,
                    "args": {"data": {"startTime": 1000}},
                },
                chunk(
                    7,
                    "0x1",
                    [node(1, "(root)"), node(2, "outer", 1), node(3, "leaf", 2)],
                    [2, 3, 3, 2],
                    [100, 100, 100, 100],
                ),
            ],
        )
        db = self.tmp / "clock.db"
        result = run("--in", trace, "--out", db)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            query(db, "SELECT ts FROM samples ORDER BY seq"),
            [(1100,), (1200,), (1300,), (1400,)],
        )
        sql = doc_query("chrome-trace.md", "Frames sampled inside one event")
        rows = query(db, sql, {"seq": 0})
        self.assertEqual([(r[2], r[-1]) for r in rows], [("leaf", 2)])

    def test_trace_without_start_time_leaves_ts_null(self):
        # A Profile event with no args.data.startTime, and a profile with no
        # Profile event at all: both keep their samples with ts NULL.
        trace = self.write_json(
            "nostart.trace.json",
            [
                {"name": "Profile", "ph": "P", "pid": 7, "id": "0x1", "args": {}},
                chunk(7, "0x1", [node(1, "(root)")], [1, 1], [100, 100]),
                chunk(8, "0x1", [node(1, "(root)")], [1], [100]),
            ],
        )
        db = self.tmp / "nostart.db"
        result = run("--in", trace, "--out", db)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            query(db, "SELECT profile, ts FROM samples ORDER BY profile, seq"),
            [("7:0x1", None), ("7:0x1", None), ("8:0x1", None)],
        )

    def test_cpuprofile_samples_start_at_its_start_time(self):
        db = self.tmp / "cpu.db"
        self.assertEqual(run("--in", CPUPROFILE, "--out", db).returncode, 0)
        self.assertEqual(
            query(db, "SELECT ts FROM samples WHERE seq IN (0, 6) ORDER BY seq"),
            [(1001000,), (1007000,)],
        )


if __name__ == "__main__":
    unittest.main()

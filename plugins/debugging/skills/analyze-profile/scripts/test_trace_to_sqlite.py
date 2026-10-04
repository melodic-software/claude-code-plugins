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
AWS_KEY = "AKIA" + "MNBVCXZLKJHGFDSA"


def dump(db):
    with contextlib.closing(sqlite3.connect(db)) as con:
        return "\n".join(con.iterdump())


class RedactsEveryStringField(TempDirCase):
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


if __name__ == "__main__":
    unittest.main()

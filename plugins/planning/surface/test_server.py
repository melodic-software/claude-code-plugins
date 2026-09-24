"""Tests for the interview surface server and its lifecycle commands.

Every class starts its own server through `round.py ensure-running --port 0` in a
temporary data dir and stops it through `round.py stop`, so no fixed port is used.
`TestApi` walks the prototype API checks in order; the other classes cover the
lifecycle and security acceptance criteria (AC2 to AC7).
"""

from __future__ import annotations

import contextlib
import http.client
import io
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import unittest.mock
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

ROUND = HERE / "round.py"
FIXTURES = HERE / "tests" / "fixtures"
TIMEOUT = 10


def run_round(d, *args, timeout=30, env=None):
    p = subprocess.run(
        [sys.executable, str(ROUND), "--dir", str(d), *args],
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
    )
    return p.returncode, (p.stdout + p.stderr).strip()


def ensure_running(d, *extra, env=None):
    """Run ensure-running with captured pipes; the timeout turns an inherited-pipe hang into a failure."""
    return subprocess.run(
        [
            sys.executable,
            str(ROUND),
            "ensure-running",
            "--dir",
            str(d),
            "--port",
            "0",
            *extra,
        ],
        capture_output=True,
        text=True,
        timeout=TIMEOUT,
        env=env,
    )


def session(d):
    return json.loads((Path(d) / ".interview-session.json").read_text(encoding="utf-8"))


def request(port, method, path, body=None, headers=None, timeout=TIMEOUT):
    """One HTTP request; returns (status, text, headers). A dict body is sent as JSON."""
    data = json.dumps(body).encode("utf-8") if isinstance(body, dict) else body
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        conn.request(method, path, body=data, headers=dict(headers or {}))
        resp = conn.getresponse()
        return resp.status, resp.read().decode("utf-8"), resp.headers
    finally:
        conn.close()


def same_dir(a, b):
    return os.path.normcase(str(Path(a).resolve())) == os.path.normcase(
        str(Path(b).resolve())
    )


class ServerCase(unittest.TestCase):
    """Starts one server per class in a temp data dir; `fixtures` seeds the bundle's sample data."""

    fixtures = False
    env = None

    @classmethod
    def prepare(cls):
        """Hook: seed files (or move cls.dir) before the server starts."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="iv-test-"))
        cls.addClassCleanup(shutil.rmtree, cls.tmp, ignore_errors=True)
        cls.dir = cls.tmp / "data"
        cls.dir.mkdir()
        if cls.fixtures:
            for name in ("questions.json", "responses.json"):
                shutil.copy(FIXTURES / name, cls.dir / name)
            (cls.dir / ".watch-seq").write_text("24", encoding="utf-8")
        cls.prepare()
        cls.addClassCleanup(run_round, cls.dir, "stop")
        started = time.monotonic()
        p = ensure_running(cls.dir, env=cls.env)
        cls.start_seconds = time.monotonic() - started
        if p.returncode != 0:
            raise AssertionError(
                f"ensure-running failed ({p.returncode}): {p.stdout}{p.stderr}"
            )
        cls.stdout = p.stdout
        cls.url = p.stdout.strip().splitlines()[-1]
        s = session(cls.dir)
        cls.port, cls.token, cls.pid = s["port"], s["token"], s["pid"]

    def get(self, path, token=True, headers=None):
        h = {"X-Interview-Token": self.token} if token else {}
        h.update(headers or {})
        return request(self.port, "GET", path, headers=h)

    def post(self, body, token=True, headers=None):
        h = {"Content-Type": "application/json"}
        if token:
            h["X-Interview-Token"] = self.token
        h.update(headers or {})
        code, raw, _ = request(self.port, "POST", "/api/answer", body=body, headers=h)
        return code, json.loads(raw) if raw else {}

    def state(self):
        return json.loads(self.get("/api/state")[1])

    def rp(self, *args):
        return run_round(self.dir, *args)


class TestApi(ServerCase):
    """The prototype API suite, one check per method, in order (the checks share one server's state)."""

    fixtures = True

    def test_01_state_has_api_2(self):
        type(self).st0 = self.state()
        self.assertEqual(self.st0.get("api"), 2)

    def test_02_old_data_loads(self):
        st = self.st0
        self.assertGreaterEqual(len(st["questions"]["questions"]), 18)
        self.assertGreaterEqual(len(st["responses"]["events"]), 24)

    def test_03_watch_seq_exposed(self):
        self.assertEqual(self.st0.get("watchSeq"), 24)

    def test_04_note_post_ok(self):
        seq0 = self.st0["responses"]["seq"]
        box = {}

        def waiter():
            t = time.time()
            code, raw, _ = self.get(f"/api/wait?after={seq0}&timeout=20")
            box.update(code=code, raw=raw, dt=time.time() - t)

        th = threading.Thread(target=waiter)
        th.start()
        time.sleep(1.0)
        code, data = self.post({"kind": "note", "text": "A general note for Claude."})
        th.join(30)
        type(self).wait_box, type(self).note_seq = box, data.get("seq")
        self.assertEqual(code, 200)
        self.assertIsNone(data["contentRev"])

    def test_05_note_arrives_through_wait(self):
        w = json.loads(self.wait_box["raw"])
        self.assertTrue(w["events"])
        self.assertEqual(w["events"][0]["kind"], "note")
        self.assertIsNone(w["events"][0]["id"])

    def test_06_wait_keeps_shape_for_watch_sh(self):
        raw = self.wait_box["raw"]
        self.assertTrue(raw.startswith('{"seq": '), raw[:40])
        self.assertIn('"timedOut": false', raw)

    def test_07_delivered_at_stamped(self):
        self.assertIn("deliveredAt", self.state()["responses"]["events"][-1])

    def test_08_empty_note_is_400(self):
        code, _ = self.post({"kind": "note", "text": "  "})
        self.assertEqual(code, 400)

    def test_09_stale_content_rev_is_409_with_current_text(self):
        st = self.state()
        q = next(x for x in st["questions"]["questions"] if x["id"] == "Q5")
        kinds = ("accept", "alt", "own", "defer", "reopen", "undo")
        crev = (q.get("contentRev") or 0) + sum(
            1
            for e in st["responses"]["events"]
            if e["id"] == "Q5" and e["kind"] in kinds
        )
        type(self).crev = crev
        code, data = self.post(
            {"id": "Q5", "kind": "accept", "text": "", "contentRev": crev + 5}
        )
        self.assertEqual(code, 409)
        self.assertEqual(data["current"]["recommendation"], q["recommendation"])

    def test_10_current_content_rev_saves_and_returns_next(self):
        code, data = self.post(
            {"id": "Q5", "kind": "accept", "text": "", "contentRev": self.crev}
        )
        type(self).accept = data
        self.assertEqual(code, 200)
        self.assertEqual(data["contentRev"], self.crev + 1)

    def test_11_own_second_save_with_returned_content_rev(self):
        code, data = self.post(
            {
                "id": "Q5",
                "kind": "defer",
                "text": "later",
                "contentRev": self.accept["contentRev"],
            }
        )
        type(self).defer = data
        self.assertEqual(code, 200)

    def test_12_post_without_content_rev_still_accepted(self):
        code, data = self.post({"id": "Q5", "kind": "accept", "text": ""})
        type(self).accept2 = data
        self.assertEqual(code, 200)

    def test_13_undo_of_an_older_decision_is_409(self):
        code, _ = self.post({"kind": "undo", "undoSeq": self.accept["seq"]})
        self.assertEqual(code, 409)

    def test_14_undo_restores_the_previous_decision(self):
        code, _ = self.post({"kind": "undo", "undoSeq": self.accept2["seq"]})
        st = self.state()
        self.assertEqual(code, 200)
        self.assertEqual(st["responses"]["responses"]["Q5"]["decision"], "defer")

    def test_15_undone_event_marked_withdrawn(self):
        ev = next(
            e
            for e in self.state()["responses"]["events"]
            if e["seq"] == self.accept2["seq"]
        )
        self.assertIs(ev.get("withdrawn"), True)

    def test_16_second_undo_is_409(self):
        code, _ = self.post({"kind": "undo", "undoSeq": self.accept2["seq"]})
        self.assertEqual(code, 409)

    def test_17_undo_after_claude_handled_it_is_409(self):
        self.rp("handle", "--seq", str(self.defer["seq"]))
        code, u = self.post({"kind": "undo", "undoSeq": self.defer["seq"]})
        self.assertEqual(code, 409)
        self.assertIn("handled", u.get("error", ""))

    def test_18_wrapup_event_saved(self):
        code, data = self.post({"kind": "wrapup"})
        self.assertEqual(code, 200)
        self.assertGreater(data["seq"], 0)

    def test_19_revise_refused_when_a_newer_user_event_exists(self):
        rc, out = self.rp(
            "revise",
            "Q5",
            "--rec",
            "New rec",
            "--affects",
            "none",
            "--seq",
            str(self.accept["seq"]),
        )
        self.assertNotEqual(rc, 0)
        self.assertIn("refused", out)

    def test_20_revise_force_works(self):
        rc, out = self.rp(
            "revise",
            "Q5",
            "--rec",
            "New rec",
            "--affects",
            "none",
            "--seq",
            str(self.accept["seq"]),
            "--force",
        )
        self.assertEqual(rc, 0, out)

    def test_21_content_rev_bumped_by_revise_not_by_reply(self):
        self.rp("reply", "Q5", "--text", "Thread reply only")
        q5 = next(x for x in self.state()["questions"]["questions"] if x["id"] == "Q5")
        self.assertEqual(q5.get("contentRev"), 1)

    def test_22_note_reply_lands_in_notes_and_marks_handled(self):
        rc, out = self.rp(
            "note-reply", "--seq", str(self.note_seq), "--text", "Got your note."
        )
        st = self.state()
        self.assertEqual(rc, 0, out)
        self.assertEqual(st["questions"]["notes"][-1]["replyTo"], self.note_seq)
        self.assertIn(self.note_seq, st["questions"]["handled"])

    def test_23_handle_advances_handled_seq_over_a_gap_free_run(self):
        hs0 = self.state()["questions"].get("handledSeq", 0)
        self.rp("handle", "--seq", str(hs0 + 1))
        q = self.state()["questions"]
        self.assertGreater(q["handledSeq"], hs0)
        self.assertNotIn(q["handledSeq"] + 1, q["handled"])

    def test_24_add_round_adds_groups_and_questions_in_one_write(self):
        spec = self.tmp / "round-spec.json"
        spec.write_text(
            json.dumps(
                {
                    "groups": [
                        {"id": "g9", "title": "New group", "dependsOn": ["wrap"]}
                    ],
                    "questions": [
                        {
                            "id": "N1",
                            "group": "g9",
                            "short": "First",
                            "title": "First new?",
                            "recommendation": "Yes.",
                            "commits": [],
                            "alternatives": [
                                {"key": "a", "text": "No"},
                                {"key": "b", "text": "Later"},
                            ],
                        },
                        {
                            "id": "N2",
                            "group": "g9",
                            "short": "Second",
                            "title": "Second new?",
                            "dependsOn": ["N1"],
                            "recommendation": "Yes.",
                            "commits": [],
                            "alternatives": [
                                {"key": "a", "text": "No"},
                                {"key": "b", "text": "Only after N1 is settled"},
                            ],
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )
        rc, out = self.rp("add-round", "--file", str(spec), "--round", "4")
        ids = {x["id"] for x in self.state()["questions"]["questions"]}
        self.assertEqual(rc, 0, out)
        self.assertLessEqual({"N1", "N2"}, ids)

    def test_25_bad_add_round_writes_nothing(self):
        bad = self.tmp / "round-bad.json"
        bad.write_text(
            json.dumps(
                {
                    "questions": [
                        {"id": "N3", "short": "x", "title": "x"},
                        {"id": "N4", "short": "y", "title": "y", "dependsOn": ["NOPE"]},
                    ]
                }
            ),
            encoding="utf-8",
        )
        rev_before = self.state()["questions"]["rev"]
        rc, out = self.rp("add-round", "--file", str(bad))
        q = self.state()["questions"]
        self.assertNotEqual(rc, 0)
        self.assertEqual(q["rev"], rev_before, out)
        self.assertNotIn("N3", {x["id"] for x in q["questions"]})

    def test_26_status_runs(self):
        rc, out = self.rp("status")
        self.assertEqual(rc, 0, out)
        self.assertIn("unhandled events", out)

    def test_27_ac30_responses_rebuild_from_events_after_the_suite(self):
        from server import rebuild_responses

        r = self.state()["responses"]
        responses, history = rebuild_responses(r["events"])
        self.assertEqual(responses, r["responses"])
        self.assertEqual(history, r["history"])

    def test_28_ac31_both_files_validate_after_the_suite(self):
        rc, out = self.rp("validate")
        self.assertEqual(rc, 0, out)


class TestEnsureRunning(ServerCase):
    """AC2: a fresh data dir gets a server and its URL within 3 s; a second call reuses it."""

    def test_first_call_prints_url_within_3_seconds(self):
        self.assertLess(self.start_seconds, 3.0)
        self.assertRegex(self.url, rf"^http://127\.0\.0\.1:{self.port}/$")

    def test_second_call_reuses_the_same_pid(self):
        p = ensure_running(self.dir)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(p.stdout.strip().splitlines()[-1], self.url)
        self.assertEqual(session(self.dir)["pid"], self.pid)

    def test_ping_names_pid_and_data_dir(self):
        code, raw, _ = self.get("/api/ping", token=False)
        ping = json.loads(raw)
        self.assertEqual(code, 200)
        self.assertEqual(ping["pid"], self.pid)
        self.assertTrue(same_dir(ping["dataDir"], self.dir), ping["dataDir"])

    def test_session_files_carry_the_nonce(self):
        s = session(self.dir)
        env = (self.dir / ".interview-session.env").read_text(encoding="utf-8")
        for key in ("pid", "port", "url", "token", "dataDir", "nonce", "startedAt"):
            self.assertIn(key, s)
        self.assertTrue(s["nonce"])
        for key in ("PID", "PORT", "TOKEN", "NONCE"):
            self.assertRegex(env, rf"(?m)^{key}=\S+$")

    def test_open_runs_the_user_browser_command_and_records_the_settings_path(self):
        out = self.tmp / "opened.txt"
        code = (
            f"import pathlib, sys; pathlib.Path({str(out)!r}).write_text(sys.argv[1])"
        )
        settings = self.tmp / "user-settings.json"
        settings.write_text(
            json.dumps({"browserCommand": [sys.executable, "-c", code]}),
            encoding="utf-8",
        )
        p = ensure_running(self.dir, "--open", "--user-settings", str(settings))
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        deadline = time.monotonic() + 5
        while not out.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertEqual(out.read_text(encoding="utf-8"), self.url)
        self.assertTrue(same_dir(session(self.dir)["userSettings"], settings))

    def test_missing_curl_is_named(self):
        empty = self.tmp / "empty-path"
        empty.mkdir(exist_ok=True)
        other = self.tmp / "other"
        env = {**os.environ, "PATH": str(empty)}
        p = ensure_running(other, env=env)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("curl", p.stdout + p.stderr)
        self.assertFalse((other / ".interview-session.json").exists())


def round_sh_python():
    """The interpreter round.sh picks: python3, then python, from PATH."""
    return shutil.which("python3") or shutil.which("python") or sys.executable


@unittest.skipUnless(os.name == "nt", "console windows exist only on Windows")
class TestNoConsoleWindow(unittest.TestCase):
    """The server runs without a console window, through the interpreter round.sh picks."""

    def test_server_has_no_console_window(self):
        d = Path(tempfile.mkdtemp(prefix="iv-console-"))
        self.addCleanup(shutil.rmtree, d, ignore_errors=True)
        self.addCleanup(run_round, d, "stop")
        p = subprocess.run(
            [round_sh_python(), str(ROUND), "ensure-running", "--dir", str(d)]
            + ["--port", "0"],
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
        )
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        code, raw, _ = request(session(d)["port"], "GET", "/api/ping")
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(raw)["consoleWindow"], 0)


class TestStop(unittest.TestCase):
    """AC3: stop ends only the recorded PID and never another process."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="iv-stop-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.a, self.b, self.c = (self.tmp / n for n in ("a", "b", "c"))
        for d in (self.a, self.b, self.c):
            d.mkdir()
        for d in (self.a, self.b):
            self.addCleanup(run_round, d, "stop")
            p = ensure_running(d)
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)

    def test_stop_ends_only_that_server(self):
        sa, sb = session(self.a), session(self.b)
        rc, out = run_round(self.a, "stop")
        self.assertEqual(rc, 0, out)
        deadline = time.monotonic() + 3
        gone = False
        while time.monotonic() < deadline and not gone:
            try:
                request(sa["port"], "GET", "/api/ping", timeout=1)
                time.sleep(0.1)
            except OSError:
                gone = True
        self.assertTrue(gone, "stopped server still answers")
        self.assertFalse((self.a / ".interview-session.json").exists())
        code, raw, _ = request(sb["port"], "GET", "/api/ping")
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(raw)["pid"], sb["pid"])

    def test_stop_never_kills_an_unrelated_pid(self):
        sb = session(self.b)
        sleeper = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(60)"],
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        self.addCleanup(sleeper.wait, 10)
        self.addCleanup(sleeper.kill)
        fake = {**sb, "pid": sleeper.pid, "dataDir": str(self.c)}
        (self.c / ".interview-session.json").write_text(
            json.dumps(fake), encoding="utf-8"
        )
        (self.c / ".interview-session.env").write_text(
            f"PID={sleeper.pid}\nPORT={sb['port']}\nTOKEN={sb['token']}\n",
            encoding="utf-8",
        )
        rc, out = run_round(self.c, "stop")
        self.assertIn("not running", out)
        time.sleep(0.3)
        self.assertIsNone(sleeper.poll(), "stop killed a process it did not start")
        self.assertFalse((self.c / ".interview-session.json").exists())
        self.assertFalse((self.c / ".interview-session.env").exists())
        code, _, _ = request(sb["port"], "GET", "/api/ping")
        self.assertEqual(code, 200)


class TestSecurity(ServerCase):
    """AC4 to AC7 against one server."""

    fixtures = True

    def test_ac4_page_served_with_token_meta(self):
        code, html, _ = self.get("/", token=False)
        self.assertEqual(code, 200)
        m = re.search(r'<meta name="interview-token" content="([^"]+)">', html)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(1), self.token)

    def test_ac5_post_without_token_is_403(self):
        code, _ = self.post({"kind": "note", "text": "x"}, token=False)
        self.assertEqual(code, 403)

    def test_ac5_wrong_host_is_403(self):
        code, _ = self.post(
            {"kind": "note", "text": "x"}, headers={"Host": f"evil.example:{self.port}"}
        )
        self.assertEqual(code, 403)

    def test_ac5_foreign_origin_is_403(self):
        code, _ = self.post(
            {"kind": "note", "text": "x"}, headers={"Origin": "http://evil.example"}
        )
        self.assertEqual(code, 403)

    def test_ac5_non_json_content_type_is_415(self):
        code, _ = self.post(
            {"kind": "note", "text": "x"}, headers={"Content-Type": "text/plain"}
        )
        self.assertEqual(code, 415)

    def test_wait_token_in_the_query_is_403(self):
        code, _, _ = self.get(
            f"/api/wait?after=0&timeout=1&token={self.token}", token=False
        )
        self.assertEqual(code, 403)

    def test_non_integer_content_length_is_400(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=TIMEOUT)
        try:
            conn.putrequest("POST", "/api/answer")
            conn.putheader("Content-Type", "application/json")
            conn.putheader("X-Interview-Token", self.token)
            conn.putheader("Content-Length", "abc")
            conn.endheaders(b'{"kind": "note", "text": "x"}')
            resp = conn.getresponse()
            code, body = resp.status, json.loads(resp.read())
        finally:
            conn.close()
        self.assertEqual(code, 400)
        self.assertIn("Content-Length", body["error"])

    def test_ac6_csp_names_no_host(self):
        _, _, headers = self.get("/", token=False)
        csp = headers.get("Content-Security-Policy", "")
        self.assertIn("script-src 'self' 'unsafe-inline'", csp)
        self.assertNotIn("http", csp.lower())

    def test_ac7_saved_answer_reaches_a_waiting_watcher_within_1_second(self):
        seq0 = self.state()["responses"]["seq"]
        box = {}

        def waiter():
            self.get(f"/api/wait?after={seq0}&timeout=20")
            box["returned"] = time.monotonic()

        th = threading.Thread(target=waiter)
        th.start()
        time.sleep(0.5)
        posted = time.monotonic()
        code, _ = self.post({"kind": "note", "text": "Timing note."})
        th.join(30)
        self.assertEqual(code, 200)
        self.assertIn("returned", box)
        self.assertLess(box["returned"] - posted, 1.0)

    def test_ac7_after_handled_reaches_a_waiting_watcher_within_1_second(self):
        rc, out = self.rp("handle", "--seq", *map(str, self.unhandled_seqs()))
        self.assertEqual(rc, 0, out)
        box = {}

        def waiter():
            box["code"], box["raw"], _ = self.get(
                "/api/wait?after=handled&replayed=0&timeout=20"
            )
            box["returned"] = time.monotonic()

        th = threading.Thread(target=waiter)
        th.start()
        time.sleep(0.5)
        posted = time.monotonic()
        code, data = self.post({"kind": "note", "text": "Timing note, handled mode."})
        th.join(30)
        self.assertEqual(code, 200)
        self.assertEqual(box.get("code"), 200, box.get("raw"))
        self.assertEqual(seqs(json.loads(box["raw"])["events"]), [data["seq"]])
        self.assertLess(box["returned"] - posted, 1.0)

    def unhandled_seqs(self):
        st = self.state()
        q = st["questions"]
        done = set(q.get("handled") or [])
        return [
            e["seq"]
            for e in st["responses"]["events"]
            if e["seq"] > (q.get("handledSeq") or 0) and e["seq"] not in done
        ] or [1]


class TestVisualFile(ServerCase):
    """GET /api/visual-file serves only a file a visual names, inside the data dir."""

    BYTES = bytes(range(256)) * 4
    CAP = 4 * 1024 * 1024

    @classmethod
    def prepare(cls):
        d = cls.dir
        (d / "images").mkdir()
        (d / "images" / "ok.bin").write_bytes(cls.BYTES)
        (d / "sub").mkdir()
        (cls.tmp / "escape.txt").write_text("outside", encoding="utf-8")
        (d / "big.bin").write_bytes(b"x" * (cls.CAP + 1))
        (d / ".interview-session.env.ab12.tmp").write_text(
            "TOKEN=transient\n", encoding="utf-8"
        )
        (d / "images" / ".hidden.png").write_bytes(cls.BYTES)
        visuals = {
            "top": "images/ok.bin",
            "up": "../escape.txt",
            "abs": str((cls.tmp / "escape.txt").resolve()),
            "dir": "sub",
            "big": "big.bin",
            "session": ".interview-session.env",
            "tmp": ".interview-session.env.ab12.tmp",
            "dot": "images/.hidden.png",
        }
        doc = {
            "meta": {},
            "rev": 1,
            "groups": [],
            "visuals": [
                {"id": k, "scope": "all", "format": "image", "file": f}
                for k, f in visuals.items()
            ]
            + [{"id": "inline", "scope": "all", "format": "svg", "content": "<svg/>"}],
            "questions": [
                question(
                    "Q1",
                    visuals=[
                        "top",
                        {"id": "own", "format": "svg", "file": "images/ok.bin"},
                    ],
                )
            ],
        }
        (d / "questions.json").write_text(json.dumps(doc), encoding="utf-8")

    def fetch(self, vid, token=True):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=TIMEOUT)
        try:
            h = {"X-Interview-Token": self.token} if token else {}
            conn.request("GET", f"/api/visual-file?id={vid}", headers=h)
            resp = conn.getresponse()
            return resp.status, resp.read(), resp.headers
        finally:
            conn.close()

    def test_without_token_is_403(self):
        self.assertEqual(self.fetch("top", token=False)[0], 403)

    def test_top_level_visual_file_is_served_as_exact_bytes(self):
        code, raw, headers = self.fetch("top")
        self.assertEqual(code, 200)
        self.assertEqual(raw, self.BYTES)
        self.assertEqual(headers["Content-Type"], "application/octet-stream")
        self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertIsNone(headers.get("Content-Disposition"))

    def test_inline_question_visual_file_is_served(self):
        code, raw, _ = self.fetch("own")
        self.assertEqual((code, raw), (200, self.BYTES))

    def test_unknown_id_is_404(self):
        self.assertEqual(self.fetch("nope")[0], 404)

    def test_visual_with_content_and_no_file_is_404(self):
        self.assertEqual(self.fetch("inline")[0], 404)

    def test_dot_dot_escape_is_404(self):
        code, raw, _ = self.fetch("up")
        self.assertEqual(code, 404)
        self.assertEqual(json.loads(raw), {"error": "not found"})

    def test_absolute_path_is_404(self):
        code, raw, _ = self.fetch("abs")
        self.assertEqual(code, 404)
        self.assertNotIn(b"escape", raw)

    def test_directory_is_404(self):
        self.assertEqual(self.fetch("dir")[0], 404)

    def test_runtime_session_file_is_404(self):
        code, raw, _ = self.fetch("session")
        self.assertEqual(code, 404)
        self.assertNotIn(self.token.encode(), raw)

    def test_transient_session_temp_file_is_404(self):
        code, raw, _ = self.fetch("tmp")
        self.assertEqual(code, 404)
        self.assertNotIn(b"transient", raw)

    def test_dotfile_in_a_subfolder_is_404(self):
        self.assertEqual(self.fetch("dot")[0], 404)

    def test_file_over_the_cap_is_413(self):
        code, raw, _ = self.fetch("big")
        self.assertEqual(code, 413)
        self.assertIn("4 MB", json.loads(raw)["error"])


def question(qid, **extra):
    return {
        "id": qid,
        "short": f"Short {qid}",
        "title": f"Question {qid}?",
        "recommendation": "Yes.",
        "alternatives": [{"key": "a", "text": "No"}, {"key": "b", "text": "Later"}],
        "commits": ["First commitment", "Second commitment"],
        **extra,
    }


def seed_questions(d, *qs):
    doc = {"meta": {}, "rev": 1, "groups": [], "questions": list(qs)}
    (Path(d) / "questions.json").write_text(json.dumps(doc), encoding="utf-8")


def seqs(events):
    return [e["seq"] for e in events]


class WaitCase(ServerCase):
    """Adds a timed /api/wait and a thread helper to ServerCase."""

    def wait(self, query, timeout=30):
        started = time.monotonic()
        code, raw, _ = request(
            self.port,
            "GET",
            "/api/wait?" + query,
            headers={"X-Interview-Token": self.token},
            timeout=timeout,
        )
        return code, json.loads(raw), time.monotonic() - started

    def wait_during(self, query, action, delay=0.5):
        """Arm a wait in a thread, run action after delay, return (wait result, action result)."""
        box = {}
        th = threading.Thread(target=lambda: box.update(r=self.wait(query)))
        th.start()
        time.sleep(delay)
        acted = action()
        th.join(40)
        return box.get("r"), acted

    def q(self, qid):
        return next(x for x in self.state()["questions"]["questions"] if x["id"] == qid)


class TestReplay(WaitCase):
    """AC8 and the bounded replay: after=handled re-delivers unhandled events once, then blocks.

    One method walks the whole chain, so it passes when run alone.
    """

    @classmethod
    def prepare(cls):
        seed_questions(cls.dir, question("A"))

    def test_bounded_replay_chain(self):
        # A blocking delivery carries no replay mark.
        r, posted = self.wait_during(
            "after=handled&replayed=0&timeout=20",
            lambda: self.post({"id": "A", "kind": "accept"}),
        )
        code, body, _ = r
        first = posted[1]["seq"]
        self.assertEqual(code, 200)
        self.assertFalse(body["timedOut"])
        self.assertEqual(seqs(body["events"]), [first])
        self.assertNotIn("replayed", body)

        # AC8: a re-arm without a handle re-delivers at once.
        code, body, took = self.wait("after=handled&replayed=0&timeout=20")
        self.assertEqual(code, 200)
        self.assertLess(took, 1.5)
        self.assertEqual(seqs(body["events"]), [first])
        self.assertEqual(body.get("replayed"), first)

        # A second re-arm without a new event blocks until its timeout.
        code, body, took = self.wait(f"after=handled&replayed={first}&timeout=3")
        self.assertEqual(code, 200)
        self.assertGreaterEqual(took, 2.5)
        self.assertTrue(body["timedOut"])
        self.assertEqual(body["events"], [])

        # A new post returns the old unhandled event and the new one.
        r, posted = self.wait_during(
            f"after=handled&replayed={first}&timeout=20",
            lambda: self.post({"kind": "note", "text": "Second event."}),
        )
        code, body, _ = r
        second = posted[1]["seq"]
        self.assertEqual(code, 200)
        self.assertEqual(seqs(body["events"]), [first, second])
        self.assertNotIn("replayed", body)

        # Nothing unhandled blocks.
        rc, out = self.rp("handle", "--seq", str(first), str(second))
        self.assertEqual(rc, 0, out)
        code, body, took = self.wait("after=handled&replayed=0&timeout=2")
        self.assertTrue(body["timedOut"])
        self.assertGreaterEqual(took, 1.5)

        # A replayed value past the log counts as zero.
        _, posted = self.post({"kind": "note", "text": "Third event."})
        code, body, took = self.wait("after=handled&replayed=9999&timeout=5")
        self.assertLess(took, 1.5)
        self.assertEqual(seqs(body["events"]), [posted["seq"]])


class TestListener(WaitCase):
    """listener.idleFor (AC26 server side): null before any wait, 0 while one waits, then counting.

    One method walks the chain, so it passes when run alone.
    """

    def listener(self):
        return self.state()["listener"]

    def test_idle_for_null_then_zero_then_counting(self):
        self.assertIn("idleFor", self.listener())
        self.assertIsNone(self.listener()["idleFor"])

        r, lst = self.wait_during("after=handled&timeout=4", self.listener, delay=2.0)
        self.assertEqual(lst["waiters"], 1)
        self.assertEqual(lst["idleFor"], 0)
        self.assertTrue(r[1]["timedOut"])

        time.sleep(1.2)
        idle = self.listener()["idleFor"]
        self.assertGreaterEqual(idle, 1.0)
        self.assertLess(idle, 10)


class TestListenerDisconnect(WaitCase):
    """Socket-EOF detection in Hub.wait, on its own server."""

    def listener(self):
        return self.state()["listener"]

    def test_closed_client_frees_the_waiter_and_gets_no_delivery(self):
        sock = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        sock.sendall(
            (
                "GET /api/wait?after=handled&timeout=20 HTTP/1.1\r\n"
                f"Host: 127.0.0.1:{self.port}\r\n"
                f"X-Interview-Token: {self.token}\r\n\r\n"
            ).encode("ascii")
        )
        time.sleep(0.5)
        self.assertEqual(self.listener()["waiters"], 1)
        sock.close()
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline and self.listener()["waiters"]:
            time.sleep(0.1)
        self.assertEqual(self.listener()["waiters"], 0)
        _, posted = self.post({"kind": "note", "text": "Nobody is listening."})
        time.sleep(1.5)
        ev = next(
            e for e in self.state()["responses"]["events"] if e["seq"] == posted["seq"]
        )
        self.assertNotIn("deliveredAt", ev)


class TestQuestionState(WaitCase):
    """AC19: stale direct dependents, upstream-pending descendants, archived, revising."""

    @classmethod
    def prepare(cls):
        seed_questions(
            cls.dir,
            question("A"),
            question("B", dependsOn=["A"]),
            question("C", dependsOn=["B"]),
            question("D"),
        )

    def states(self):
        return {q["id"]: q.get("state") for q in self.state()["questions"]["questions"]}

    def decide(self, qid, kind="accept", **extra):
        code, data = self.post({"id": qid, "kind": kind, **extra})
        self.assertEqual(code, 200, data)
        return data["seq"]

    def handle_all(self):
        st = self.state()
        rc, out = self.rp("handle", "--seq", *map(str, seqs(st["responses"]["events"])))
        self.assertEqual(rc, 0, out)

    def test_1_answering_in_order_leaves_every_question_open(self):
        for qid in ("A", "B", "C"):
            self.decide(qid)
        self.assertEqual(
            self.states(), {"A": "open", "B": "open", "C": "open", "D": "open"}
        )

    def test_2_reanswer_marks_direct_dependent_stale_and_descendant_upstream_pending(
        self,
    ):
        self.decide("A", "alt", alt="b")
        self.assertEqual(
            self.states(),
            {"A": "open", "B": "stale", "C": "upstream-pending", "D": "open"},
        )

    def test_3_handle_does_not_change_state(self):
        self.handle_all()
        self.assertEqual(self.states()["B"], "stale")
        self.assertEqual(self.states()["C"], "upstream-pending")

    def test_4_reanswering_the_stale_question_clears_it_and_its_descendant(self):
        self.decide("B")
        self.assertEqual(
            self.states(), {"A": "open", "B": "open", "C": "open", "D": "open"}
        )

    def test_5_undo_of_the_change_clears_the_stale_mark(self):
        self.handle_all()
        seq = self.decide("A")
        self.assertEqual(self.states()["B"], "stale")
        code, data = self.post({"kind": "undo", "undoSeq": seq})
        self.assertEqual(code, 200, data)
        self.assertEqual(self.states()["B"], "open")

    def test_6_state_is_never_written_to_questions_json(self):
        doc = json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))
        self.assertFalse(any("state" in q for q in doc["questions"]))

    def test_7_revising_marks_direct_dependents_of_a_delivered_unhandled_decision(
        self,
    ):
        self.handle_all()
        self.decide("A", "alt", alt="a")
        before = {
            q["id"]: q.get("revising") for q in self.state()["questions"]["questions"]
        }
        self.assertFalse(before["B"], "revising before delivery")
        code, body, _ = self.wait("after=handled&replayed=0&timeout=5")
        self.assertFalse(body["timedOut"])
        rev = {
            q["id"]: q.get("revising") for q in self.state()["questions"]["questions"]
        }
        self.assertEqual(rev, {"A": False, "B": True, "C": False, "D": False})
        self.handle_all()
        rev = {
            q["id"]: q.get("revising") for q in self.state()["questions"]["questions"]
        }
        self.assertFalse(rev["B"])

    def test_8_archived(self):
        rc, out = self.rp("archive", "D", "--why", "Off the chosen path.")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.states()["D"], "archived")


class TestTerminalStale(WaitCase):
    """A terminal decision takes part in the stale replay, placed by its updatedAt."""

    @classmethod
    def prepare(cls):
        seed_questions(cls.dir, question("A"), question("B", dependsOn=["A"]))

    def states(self):
        return {q["id"]: q.get("state") for q in self.state()["questions"]["questions"]}

    def test_terminal_dependent_goes_stale_when_its_prerequisite_changes(self):
        code, data = self.post({"id": "A", "kind": "accept"})
        self.assertEqual(code, 200, data)
        time.sleep(1.1)  # timestamps have one-second resolution
        rc, out = self.rp("record-terminal", "B", "--decision", "accept")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.states(), {"A": "open", "B": "open"})
        time.sleep(1.1)
        code, data = self.post({"id": "A", "kind": "alt", "alt": "b"})
        self.assertEqual(code, 200, data)
        self.assertEqual(self.states(), {"A": "open", "B": "stale"})


class TestConfirm(WaitCase):
    """The `confirm` event: ticks one commitment, records no decision, needs handling."""

    @classmethod
    def prepare(cls):
        seed_questions(cls.dir, question("A"))

    def test_1_confirm_is_saved_as_a_user_line_without_a_decision(self):
        code, data = self.post({"id": "A", "kind": "accept"})
        crev = data["contentRev"]
        code, data = self.post({"id": "A", "kind": "confirm", "alt": "1"})
        self.assertEqual(code, 200, data)
        self.assertEqual(data["contentRev"], crev)
        r = self.state()["responses"]
        self.assertEqual(r["responses"]["A"]["decision"], "accept")
        line = r["history"]["A"][-1]
        self.assertEqual((line["kind"], line["alt"]), ("confirm", "1"))
        code, body, _ = self.wait("after=handled&replayed=0&timeout=5")
        self.assertIn(data["seq"], seqs(body["events"]))
        rc, out = self.rp("validate")
        self.assertEqual(rc, 0, out)

    def test_2_confirm_without_alt_is_400(self):
        code, _ = self.post({"id": "A", "kind": "confirm"})
        self.assertEqual(code, 400)


def settings_env(**extra):
    env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PROJECT_DIR"}
    env.update(extra)
    return env


class TestSettingsLayers(ServerCase):
    """AC33 server side: default, repo, user and session layers, each value with its layer."""

    env = settings_env()

    @classmethod
    def prepare(cls):
        cls.repo = cls.tmp / "repo"
        (cls.repo / ".claude").mkdir(parents=True)
        (cls.repo / ".git").write_text("gitdir: elsewhere\n", encoding="utf-8")
        cls.dir = cls.repo / ".work" / "topic" / "interview-surface"
        cls.dir.mkdir(parents=True)
        (cls.dir / "theme.json").write_text(
            json.dumps({"light": {"--bg": "#333333"}}), encoding="utf-8"
        )

    def settings(self):
        return self.state()["settings"]

    def env_file(self):
        return (self.dir / ".interview-session.env").read_text(encoding="utf-8")

    def test_1_plugin_defaults(self):
        s = self.settings()
        want = {
            "port": 0,
            "openBrowser": True,
            "shortcuts": True,
            "undoSeconds": 5,
            "checkpoint": 0,
            "theme": "auto",
            "density": "compact",
            "minText": 14,
            "displayName": "You",
            "waitTimeout": 90,
            "staleDepth": "direct",
        }
        self.assertEqual({k: v["value"] for k, v in s.items()}, want)
        self.assertEqual({v["layer"] for v in s.values()}, {"default"})
        self.assertRegex(self.env_file(), r"(?m)^WAIT_TIMEOUT=90$")

    def test_2_repo_layer_beats_default_and_is_restricted(self):
        (self.repo / ".claude" / "interview-surface.json").write_text(
            json.dumps(
                {
                    "undoSeconds": 20,
                    "checkpoint": 9999,
                    "minText": True,
                    "displayName": "Repo Person",
                    "unknownKey": 1,
                    "themeTokens": {"light": {"--bg": "#111111", "--fg": "#222222"}},
                }
            ),
            encoding="utf-8",
        )
        s = self.settings()
        self.assertEqual(s["undoSeconds"], {"value": 20, "layer": "repo"})
        self.assertEqual(s["checkpoint"], {"value": 0, "layer": "default"})
        self.assertEqual(s["minText"], {"value": 14, "layer": "default"})
        self.assertEqual(s["displayName"], {"value": "You", "layer": "default"})
        self.assertNotIn("unknownKey", s)
        theme = self.state()["theme"]
        self.assertEqual(theme["light"], {"--bg": "#333333", "--fg": "#222222"})

    def test_3_user_layer_beats_repo(self):
        user = self.tmp / "user-settings.json"
        user.write_text(
            json.dumps({"undoSeconds": 30, "displayName": "Tester", "waitTimeout": 40}),
            encoding="utf-8",
        )
        pid = session(self.dir)["pid"]
        p = ensure_running(self.dir, "--user-settings", str(user), env=self.env)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(session(self.dir)["pid"], pid)
        s = self.settings()
        self.assertEqual(s["undoSeconds"], {"value": 30, "layer": "user"})
        self.assertEqual(s["displayName"], {"value": "Tester", "layer": "user"})
        self.assertEqual(s["waitTimeout"], {"value": 40, "layer": "user"})
        self.assertRegex(self.env_file(), r"(?m)^WAIT_TIMEOUT=40$")
        self.assertEqual(len(re.findall(r"(?m)^WAIT_TIMEOUT=", self.env_file())), 1)

    def test_4_session_layer_beats_user(self):
        (self.dir / "settings.json").write_text(
            json.dumps({"undoSeconds": 45, "waitTimeout": 500}), encoding="utf-8"
        )
        s = self.settings()
        self.assertEqual(s["undoSeconds"], {"value": 45, "layer": "session"})
        self.assertEqual(s["waitTimeout"], {"value": 40, "layer": "user"})

    def test_5_user_theme_tokens_beat_repo_per_token(self):
        (self.repo / ".claude" / "interview-surface.json").write_text(
            json.dumps(
                {
                    "themeTokens": {
                        "light": {
                            "--bg": "#111111",
                            "--fg": "#222222",
                            "--repo": "#666666",
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        user = self.tmp / "user-theme.json"
        user.write_text(
            json.dumps(
                {
                    "themeTokens": {
                        "light": {"--bg": "#999999", "--fg": "#444444"},
                        "dark": {"--fg": "#555555"},
                    }
                }
            ),
            encoding="utf-8",
        )
        p = ensure_running(self.dir, "--user-settings", str(user), env=self.env)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertNotIn("themeTokens ignored", p.stderr)
        theme = self.state()["theme"]
        self.assertEqual(
            theme["light"], {"--bg": "#333333", "--fg": "#444444", "--repo": "#666666"}
        )
        self.assertEqual(theme["dark"], {"--fg": "#555555"})


class TestSettingsResolver(unittest.TestCase):
    """The resolver in-process: repo root ladder and one stderr note per problem."""

    def setUp(self):
        import server

        self.server = server
        self.tmp = Path(tempfile.mkdtemp(prefix="iv-settings-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def test_repo_root_prefers_claude_project_dir_then_git_ancestor(self):
        repo = self.tmp / "repo"
        data = repo / "a" / "b"
        data.mkdir(parents=True)
        (repo / ".git").mkdir()
        other = self.tmp / "other"
        other.mkdir()
        with unittest.mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(other)}):
            self.assertTrue(same_dir(self.server.repo_root(data), other))
        env = settings_env()
        with unittest.mock.patch.dict(os.environ, env, clear=True):
            self.assertTrue(same_dir(self.server.repo_root(data), repo))
            self.assertIsNone(self.server.repo_root(self.tmp / "other"))

    def test_invalid_and_unknown_repo_keys_are_noted_once(self):
        repo = self.tmp / "r"
        (repo / ".claude").mkdir(parents=True)
        (repo / ".claude" / "interview-surface.json").write_text(
            json.dumps({"undoSeconds": 61, "bogus": 1}), encoding="utf-8"
        )
        notes = io.StringIO()
        with contextlib.redirect_stderr(notes):
            layers = self.server.Settings(repo)
            first, _ = layers.resolve(self.tmp)
            layers.resolve(self.tmp)
        text = notes.getvalue()
        self.assertEqual(first["undoSeconds"]["layer"], "default")
        self.assertEqual(text.count("undoSeconds"), 1, text)
        self.assertEqual(text.count("bogus"), 1, text)


class TestEmojiMarkers(ServerCase):
    """meta.emojiMarkers from ensure-running, written once through the locked path."""

    def meta(self):
        return self.state()["questions"]["meta"]

    def test_1_default_true_creates_questions_json(self):
        self.assertTrue((self.dir / "questions.json").exists())
        self.assertIs(self.meta().get("emojiMarkers"), True)

    def test_2_false_is_recorded_and_a_repeat_does_not_bump_rev(self):
        p = ensure_running(self.dir, "--emoji-markers", "false")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIs(self.meta().get("emojiMarkers"), False)
        rev = self.state()["questions"]["rev"]
        ensure_running(self.dir, "--emoji-markers", "false")
        self.assertEqual(self.state()["questions"]["rev"], rev)

    def test_3_display_name_reaches_state(self):
        self.assertEqual(self.state()["settings"]["displayName"]["value"], "You")


class TestAnswerValidation(WaitCase):
    """`alt` names one of the question's alternative keys; `confirm` names a commitment index."""

    @classmethod
    def prepare(cls):
        seed_questions(cls.dir, question("A"))

    def test_alt_with_an_unknown_key_is_400(self):
        for alt in ("z", 1, ["a"]):
            code, data = self.post({"id": "A", "kind": "alt", "alt": alt})
            self.assertEqual(code, 400, alt)
            self.assertIn("alternatives", data["error"])

    def test_alt_with_a_known_key_saves(self):
        code, data = self.post({"id": "A", "kind": "alt", "alt": "b"})
        self.assertEqual(code, 200, data)

    def test_confirm_outside_the_commitments_is_400(self):
        for alt in ("2", "-1", "x", "1.0", 0):
            code, data = self.post({"id": "A", "kind": "confirm", "alt": alt})
            self.assertEqual(code, 400, alt)
            self.assertIn("commitment index", data["error"])

    def test_confirm_inside_the_commitments_saves(self):
        code, data = self.post({"id": "A", "kind": "confirm", "alt": "1"})
        self.assertEqual(code, 200, data)

    def test_stale_content_rev_wins_over_an_unknown_key(self):
        code, data = self.post(
            {"id": "A", "kind": "alt", "alt": "z", "contentRev": 999}
        )
        self.assertEqual(code, 409, data)
        self.assertEqual(data["error"], "changed")


class TestBodyLimits(WaitCase):
    """The 64 KB body cap is the only limit on text; a body that is not a JSON object is 400."""

    @classmethod
    def prepare(cls):
        seed_questions(cls.dir, question("A"))

    def raw_post(self, body, length=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=TIMEOUT)
        try:
            conn.putrequest("POST", "/api/answer")
            conn.putheader("Content-Type", "application/json")
            conn.putheader("X-Interview-Token", self.token)
            conn.putheader(
                "Content-Length", str(len(body) if length is None else length)
            )
            conn.endheaders(body or None)
            resp = conn.getresponse()
            return resp.status, json.loads(resp.read())
        finally:
            conn.close()

    def test_long_own_text_round_trips_byte_exact(self):
        import server

        text = ('Line with a quote " and a tab\t, café.\n' * 600)[:20000]
        self.assertEqual(len(text), 20000)
        self.assertLess(
            len(json.dumps({"id": "A", "kind": "own", "text": text})), server.MAX_BODY
        )
        code, data = self.post({"id": "A", "kind": "own", "text": text})
        self.assertEqual(code, 200, data)
        r = self.state()["responses"]
        self.assertEqual(r["responses"]["A"]["text"], text)
        self.assertEqual(r["events"][-1]["text"], text)

    def test_body_over_the_cap_is_413_naming_the_limit(self):
        import server

        code, data = self.raw_post(b"", length=server.MAX_BODY + 1)
        self.assertEqual(code, 413)
        self.assertIn(str(server.MAX_BODY), data["error"])

    def test_json_array_body_is_400(self):
        code, data = self.raw_post(b'["a"]')
        self.assertEqual(code, 400)
        self.assertIn("JSON object", data["error"])
        self.assertEqual(self.get("/api/state")[0], 200)

    def test_deeply_nested_body_is_400(self):
        body = b"[" * 30000 + b"]" * 30000
        code, _ = self.raw_post(body)
        self.assertEqual(code, 400)
        self.assertEqual(self.get("/api/state")[0], 200)


class TestUndoKeepsReopenNote(WaitCase):
    """An undo that restores a reopen keeps the note that reopen kept."""

    @classmethod
    def prepare(cls):
        seed_questions(cls.dir, question("A"))

    def test_undo_back_to_a_reopen_keeps_the_note(self):
        for body in (
            {"id": "A", "kind": "accept", "text": "Keep this note."},
            {"id": "A", "kind": "reopen", "text": ""},
        ):
            code, data = self.post(body)
            self.assertEqual(code, 200, data)
        code, data = self.post({"id": "A", "kind": "accept", "text": ""})
        self.assertEqual(code, 200, data)
        code, undo = self.post({"kind": "undo", "undoSeq": data["seq"]})
        self.assertEqual(code, 200, undo)
        view = self.state()["responses"]["responses"]["A"]
        self.assertIsNone(view["decision"])
        self.assertEqual(view["text"], "Keep this note.")
        rc, out = self.rp("validate")
        self.assertEqual(rc, 0, out)


class TestThemeMerge(ServerCase):
    """A theme.json mode value that is not an object is read as {}."""

    @classmethod
    def prepare(cls):
        (cls.dir / "theme.json").write_text(
            json.dumps({"light": "x", "dark": {"--bg": "#000000"}}), encoding="utf-8"
        )

    def test_non_object_mode_is_ignored(self):
        code, raw, _ = self.get("/api/state")
        self.assertEqual(code, 200, raw)
        theme = json.loads(raw)["theme"]
        self.assertIsInstance(theme.get("light", {}), dict)
        self.assertEqual(theme["dark"], {"--bg": "#000000"})


@unittest.skipUnless(os.name == "posix", "file modes are advisory on Windows")
class TestSessionFileMode(ServerCase):
    """The token-bearing session files are 0600."""

    def test_session_files_are_owner_only(self):
        for name in (".interview-session.env", ".interview-session.json"):
            mode = (self.dir / name).stat().st_mode & 0o777
            self.assertEqual(mode, 0o600, f"{name}: {oct(mode)}")


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class TestEnsureRunningSettings(unittest.TestCase):
    """ensure-running resolves the settings layers: the port and openBrowser come from them."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="iv-ensure-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.repo = self.tmp / "repo"
        (self.repo / ".claude").mkdir(parents=True)
        self.dir = self.tmp / "data"
        self.dir.mkdir()
        self.addCleanup(run_round, self.dir, "stop")
        # BROWSER points webbrowser at a program that records the URL and exits 0, so the
        # default-browser fall-through is observable and never opens a real browser.
        self.fallback = self.tmp / "fallback.txt"
        self.env = settings_env(
            CLAUDE_PROJECT_DIR=str(self.repo), BROWSER=str(self.fallback_program())
        )
        self.marker = self.tmp / "opened.txt"
        code = f"import pathlib, sys; pathlib.Path({str(self.marker)!r}).write_text(sys.argv[1])"
        self.user = self.tmp / "user-settings.json"
        self.user.write_text(
            json.dumps({"browserCommand": [sys.executable, "-c", code]}),
            encoding="utf-8",
        )

    def fallback_program(self):
        """A program webbrowser runs as [program, url]: it writes the URL to self.fallback."""
        script = self.tmp / "fallback.py"
        script.write_text(
            f"import pathlib, sys; pathlib.Path({str(self.fallback)!r}).write_text(sys.argv[1])",
            encoding="utf-8",
        )
        if os.name == "nt":
            prog = self.tmp / "fallback.bat"
            prog.write_text(f'@"{sys.executable}" "{script}" %*\r\n', encoding="utf-8")
        else:
            prog = self.tmp / "fallback.sh"
            prog.write_text(
                f"#!/bin/sh\nexec '{sys.executable}' '{script}' \"$@\"\n",
                encoding="utf-8",
            )
            prog.chmod(0o755)
        return prog

    def repo_settings(self, data):
        (self.repo / ".claude" / "interview-surface.json").write_text(
            json.dumps(data), encoding="utf-8"
        )

    def ensure(self, *extra):
        p = subprocess.run(
            [
                sys.executable,
                str(ROUND),
                "--dir",
                str(self.dir),
                "ensure-running",
                *extra,
            ],
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
            env=self.env,
        )
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        return p.stdout.strip().splitlines()[-1]

    def opened(self, seconds):
        deadline = time.monotonic() + seconds
        while not self.marker.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        return self.marker.read_text(encoding="utf-8") if self.marker.exists() else None

    def test_repo_port_is_used_on_a_fresh_start(self):
        port = free_port()
        self.repo_settings({"port": port})
        url = self.ensure()
        self.assertEqual(session(self.dir)["port"], port)
        self.assertEqual(url, f"http://127.0.0.1:{port}/")

    def test_repo_open_browser_false_wins_over_open(self):
        self.repo_settings({"openBrowser": False})
        self.ensure("--open", "--user-settings", str(self.user))
        self.assertIsNone(self.opened(2))

    def fallback_opened(self):
        # webbrowser waits for the program, so the URL is written before ensure-running returns.
        return (
            self.fallback.read_text(encoding="utf-8").strip()
            if self.fallback.exists()
            else None
        )

    def test_open_ignores_the_recorded_user_file(self):
        url = self.ensure("--user-settings", str(self.user))
        self.assertIsNone(self.opened(0.5))
        self.assertTrue(same_dir(session(self.dir)["userSettings"], self.user))
        self.assertEqual(self.ensure("--open"), url)
        self.assertEqual(self.fallback_opened(), url)
        self.assertIsNone(self.opened(1.5))

    def test_planted_session_file_never_supplies_the_opener(self):
        (self.dir / ".interview-session.json").write_text(
            json.dumps({"pid": 1, "port": free_port(), "userSettings": str(self.user)}),
            encoding="utf-8",
        )
        url = self.ensure("--open")
        self.assertEqual(self.fallback_opened(), url)
        self.assertIsNone(self.opened(1.5))


if __name__ == "__main__":
    unittest.main()

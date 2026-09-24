"""Tests for the interview surface server and its lifecycle commands.

Every class starts its own server through `round.py ensure-running --port 0` in a
temporary data dir and stops it through `round.py stop`, so no fixed port is used.
`TestApi` walks the prototype API checks in order; the other classes cover the
lifecycle and security acceptance criteria (AC2 to AC7).
"""

from __future__ import annotations

import http.client
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
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
        cls.addClassCleanup(run_round, cls.dir, "stop")
        started = time.monotonic()
        p = ensure_running(cls.dir)
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
            "revise", "Q5", "--rec", "New rec", "--seq", str(self.accept["seq"])
        )
        self.assertNotEqual(rc, 0)
        self.assertIn("refused", out)

    def test_20_revise_force_works(self):
        rc, out = self.rp(
            "revise",
            "Q5",
            "--rec",
            "New rec",
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
            [sys.executable, "-c", "import time; time.sleep(60)"]
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


if __name__ == "__main__":
    unittest.main()

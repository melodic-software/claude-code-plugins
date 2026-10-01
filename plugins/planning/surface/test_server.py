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

import server as _server  # noqa: E402

# a wake lands after one quiet window, plus slack
WAKE_SECONDS = _server.QUIET_SECONDS + 1.0


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

    def test_08a_research_and_cancel_research_are_accepted_without_a_decision(self):
        seqs_ = []
        before = self.state()["responses"]["responses"].get("Q5")
        for body in (
            {"id": "Q5", "kind": "research"},
            {"id": "Q5", "kind": "research", "text": "check the vendor docs"},
            {"id": "Q5", "kind": "cancel-research"},
        ):
            code, data = self.post(body)
            self.assertEqual(code, 200, data)
            seqs_.append(data["seq"])
        evs = {e["seq"]: e for e in self.state()["responses"]["events"]}
        self.assertEqual(
            [evs[s]["kind"] for s in seqs_], ["research", "research", "cancel-research"]
        )
        self.assertEqual(evs[seqs_[1]]["text"], "check the vendor docs")
        self.assertEqual(self.state()["responses"]["responses"].get("Q5"), before)
        self.assertEqual(self.post({"id": "nope", "kind": "research"})[0], 400)
        self.assertEqual(self.post({"id": "Q5", "kind": "researchh"})[0], 400)

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


class TestLongText(ServerCase):
    """A long own answer and a long ask are stored whole, not cut at any length limit."""

    fixtures = True

    def test_long_own_answer_and_ask_reach_responses_json_whole(self):
        filler = "Sentence of filler text that keeps going. " * 145
        long_text = (
            filler
            + "There are more questions here, but the rest is for round two and then it ends"
        )
        self.assertGreaterEqual(len(long_text), 6000)
        for qid, kind in (("Q5", "own"), ("Q6", "ask")):
            code, _ = self.post({"id": qid, "kind": kind, "text": long_text})
            self.assertEqual(code, 200)
        saved = json.loads((self.dir / "responses.json").read_text(encoding="utf-8"))
        texts = {
            e["kind"]: e["text"] for e in saved["events"] if e["id"] in ("Q5", "Q6")
        }
        self.assertEqual(texts["own"], long_text)
        self.assertEqual(texts["ask"], long_text)
        self.assertEqual(saved["responses"]["Q5"]["text"], long_text)


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


class TestFinishAndPort(unittest.TestCase):
    """The finish event, stop's finish and the port kept across stop."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="iv-finish-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.dir = self.tmp / "data"
        self.dir.mkdir()
        shutil.copy(FIXTURES / "questions.json", self.dir / "questions.json")
        self.addCleanup(run_round, self.dir, "stop")

    def doc(self):
        return json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))

    def ops(self, *ops):
        f = self.tmp / "ops.json"
        f.write_text(json.dumps({"ops": list(ops)}), encoding="utf-8")
        return run_round(self.dir, "apply", "--file", str(f))

    def start(self):
        p = ensure_running(self.dir)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        return session(self.dir)

    def state(self, s):
        code, raw, _ = request(
            s["port"], "GET", "/api/state", headers={"X-Interview-Token": s["token"]}
        )
        self.assertEqual(code, 200)
        return json.loads(raw)

    def test_finish_op_stores_the_closing_event_and_logs_it(self):
        rc, out = self.ops(
            {
                "op": "finish",
                "brief": "docs/PLAN.md",
                "next": "Run the plan.",
                "text": "Done",
            }
        )
        self.assertEqual(rc, 0, out)
        done = self.doc()["finished"]
        self.assertEqual(
            {k: done[k] for k in ("by", "brief", "next", "text")},
            {
                "by": "claude",
                "brief": "docs/PLAN.md",
                "next": "Run the plan.",
                "text": "Done",
            },
        )
        last = self.doc()["activity"][-1]
        self.assertEqual((last["text"], last["finished"]), ("Interview finished", True))

    def test_finish_op_over_the_cap_is_refused_and_writes_nothing(self):
        rc, out = self.ops({"op": "finish", "text": "x" * 501})
        self.assertNotEqual(rc, 0)
        self.assertNotIn("finished", self.doc())

    def test_stop_posts_a_finish_when_none_was_posted(self):
        s = self.start()
        self.assertNotIn("finished", self.state(s)["questions"])
        rc, out = run_round(self.dir, "stop")
        self.assertEqual(rc, 0, out)
        done = self.doc()["finished"]
        self.assertEqual(done["by"], "stop")
        self.assertNotIn("brief", done)

    def test_stop_keeps_the_skills_finish(self):
        self.start()
        self.ops({"op": "finish", "brief": "PLAN.md"})
        run_round(self.dir, "stop")
        self.assertEqual(
            (self.doc()["finished"]["by"], self.doc()["finished"]["brief"]),
            ("claude", "PLAN.md"),
        )

    def test_stop_creates_no_questions_file(self):
        self.start()
        (self.dir / "questions.json").unlink()
        run_round(self.dir, "stop")
        self.assertFalse((self.dir / "questions.json").exists())

    def test_the_server_pushes_the_finish_and_a_new_instance_per_start(self):
        s = self.start()
        self.ops({"op": "finish", "text": "Done"})
        first = self.state(s)
        self.assertEqual(first["questions"]["finished"]["text"], "Done")
        run_round(self.dir, "stop")
        second = self.state(self.start())
        self.assertNotIn("finished", second["questions"])
        self.assertNotEqual(first["instance"], second["instance"])

    def test_a_new_server_drops_the_context_badge_and_handoff(self):
        s = self.start()
        self.ops({"op": "context", "percent": 72, "zone": "amber"}, {"op": "context", "handoff": "Resume from x"})
        self.assertIn("context", self.state(s)["questions"])
        run_round(self.dir, "stop")
        second = self.state(self.start())["questions"]
        self.assertNotIn("context", second)
        self.assertNotIn("handoff", second)

    def test_add_round_withdraws_the_finish(self):
        self.ops({"op": "finish"})
        rc, out = self.ops({"op": "add", "question": {**FINISH_Q}})
        self.assertEqual(rc, 0, out)
        self.assertNotIn("finished", self.doc())

    def test_stop_then_ensure_running_keeps_the_port_when_it_is_free(self):
        port = self.start()["port"]
        run_round(self.dir, "stop")
        self.assertEqual(self.start()["port"], port)

    def test_a_busy_kept_port_falls_through_to_a_free_one(self):
        port = self.start()["port"]
        run_round(self.dir, "stop")
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", port))
            sock.listen(1)
            self.assertNotEqual(self.start()["port"], port)


FINISH_Q = {
    "id": "ZZ1",
    "short": "Late question",
    "title": "Is this late question fine?",
    "recommendation": "Yes. It is fine.",
    "basis": "Nothing else changes. It is a test.",
    "commits": [],
    "alternatives": [{"key": "a", "text": "No"}, {"key": "b", "text": "Later"}],
}


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
        self.assertEqual(
            json.loads(
                (self.a / ".interview-session.json").read_text(encoding="utf-8")
            ),
            {"port": sa["port"]},
        )
        self.assertFalse((self.a / ".interview-session.env").exists())
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
        self.assertEqual(
            json.loads(
                (self.c / ".interview-session.json").read_text(encoding="utf-8")
            ),
            {"port": sb["port"]},
        )
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

    def test_ac7_saved_answer_reaches_a_waiting_watcher_within_one_quiet_window(self):
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
        self.assertLess(box["returned"] - posted, WAKE_SECONDS)

    def test_ac7_after_handled_reaches_a_waiting_watcher_within_one_quiet_window(self):
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
        self.assertLess(box["returned"] - posted, WAKE_SECONDS)

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
        # Each would be served without the lexical guard: a same-drive drive-relative path joins
        # inside the data dir on Windows (x.png), a colon name is a plain file elsewhere, and on
        # NTFS ok.png:hid is an alternate data stream of ok.png.
        (d / "x.png").write_bytes(cls.BYTES)
        if os.name != "nt":
            (d / "C:x.png").write_bytes(cls.BYTES)
        (d / "ok.png").write_bytes(b"")
        (d / "ok.png:hid").write_bytes(cls.BYTES)
        drive = Path(d).drive or "C:"
        visuals = {
            "unc": r"\\host.invalid\share\x.png",
            "unc2": "//host.invalid/share/x.png",
            "drive": drive + "x.png",
            "ads": "ok.png:hid",
            "updown": "a/../../x",
            "subup": "sub/../../escape.txt",
            "top": "images/ok.bin",
            "up": "../escape.txt",
            "abs": str((cls.tmp / "escape.txt").resolve()),
            "dir": "sub",
            "big": "big.bin",
            "session": ".interview-session.env",
            "tmp": ".interview-session.env.ab12.tmp",
            "dot": "images/.hidden.png",
            "hardlink": "images/link.png",
            "twin": "images/twin.bin",
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

    def test_unc_path_is_404(self):
        for vid in ("unc", "unc2"):
            self.assertEqual(self.fetch(vid)[0], 404, vid)

    def test_drive_relative_path_is_404(self):
        self.assertEqual(self.fetch("drive")[0], 404)

    def test_alternate_data_stream_is_404(self):
        self.assertEqual(self.fetch("ads")[0], 404)

    def test_dot_dot_through_a_subfolder_is_404(self):
        for vid in ("updown", "subup"):
            code, raw, _ = self.fetch(vid)
            self.assertEqual(code, 404, vid)
            self.assertNotIn(b"outside", raw)

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

    def test_hard_link_to_the_session_file_is_404(self):
        # The link's name and resolved path both pass the runtime-path check; its link count does not.
        link = self.dir / "images" / "link.png"
        try:
            os.link(self.dir / ".interview-session.env", link)
        except OSError as e:
            self.skipTest(f"no hard links here: {e}")
        try:
            code, raw, _ = self.fetch("hardlink")
            self.assertEqual(code, 404)
            self.assertNotIn(self.token.encode(), raw)
        finally:
            link.unlink()

    def test_any_file_with_a_second_hard_link_is_404(self):
        twin = self.dir / "images" / "twin.bin"
        try:
            os.link(self.dir / "images" / "ok.bin", twin)
        except OSError as e:
            self.skipTest(f"no hard links here: {e}")
        try:
            self.assertEqual(self.fetch("twin")[0], 404)
            self.assertEqual(self.fetch("top")[0], 404)
        finally:
            twin.unlink()
        self.assertEqual(self.fetch("top")[0], 200)

    def test_file_over_the_cap_is_413(self):
        code, raw, _ = self.fetch("big")
        self.assertEqual(code, 413)
        self.assertIn("4 MB", json.loads(raw)["error"])


class TestVisualOpen(ServerCase):
    """POST /api/visual-open mints a one-time link; GET serves the visual in an opaque origin."""

    BYTES, CAP = TestVisualFile.BYTES, TestVisualFile.CAP
    HTML = "<p id=m>mark</p><script>document.title = 'ran'</script>"
    PNG = b"\x89PNG\r\n\x1a\nbody"

    @classmethod
    def prepare(cls):
        TestVisualFile.prepare.__func__(cls)
        (cls.dir / "images" / "pic.png").write_bytes(cls.PNG)
        doc = json.loads((cls.dir / "questions.json").read_text(encoding="utf-8"))
        doc["visuals"] += [
            {"id": "vh", "scope": "all", "format": "html", "content": cls.HTML},
            {"id": "pic", "scope": "all", "format": "image", "file": "images/pic.png"},
            {"id": "durl", "scope": "all", "format": "image", "content": "data:image/png;base64,AA=="},
            {"id": "chart", "scope": "all", "format": "chart", "content": {"a": [1, 2]}},
            {"id": "late", "scope": "all", "format": "svg", "content": "<svg/>"},
            {"id": "gone", "scope": "all", "format": "svg", "content": "<svg/>",
             "archived": {"why": "old", "at": "2026-01-01T00:00:00Z"}},
        ]  # fmt: skip
        (cls.dir / "questions.json").write_text(json.dumps(doc), encoding="utf-8")

    def mint(self, vid, token=True):
        h = {"Content-Type": "application/json"}
        if token:
            h["X-Interview-Token"] = self.token
        code, raw, _ = request(
            self.port, "POST", "/api/visual-open", body={"id": vid}, headers=h
        )
        return code, json.loads(raw)

    def open(self, url):
        """A tab's navigation: no token header."""
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=TIMEOUT)
        try:
            conn.request("GET", url)
            resp = conn.getresponse()
            return resp.status, resp.read(), resp.headers
        finally:
            conn.close()

    def minted(self, vid):
        code, body = self.mint(vid)
        self.assertEqual(code, 200, body)
        return body["url"]

    def test_mint_without_token_is_403(self):
        self.assertEqual(self.mint("vh", token=False)[0], 403)

    def test_url_carries_a_nonce_and_never_the_token(self):
        url = self.minted("vh")
        self.assertRegex(url, r"^/api/visual-open\?id=vh&t=[\w-]{16,}$")
        self.assertNotIn(self.token, url)

    def test_missing_or_unknown_nonce_is_403(self):
        for url in ("/api/visual-open?id=vh", "/api/visual-open?id=vh&t=bogus"):
            code, raw, _ = self.open(url)
            self.assertEqual(code, 403, url)
            self.assertNotIn(b"mark", raw)

    def test_reused_nonce_is_403(self):
        url = self.minted("vh")
        self.assertEqual(self.open(url)[0], 200)
        self.assertEqual(self.open(url)[0], 403)

    def test_nonce_for_another_visual_is_refused_and_spent(self):
        url = self.minted("vh")
        t = url.split("&t=")[1]
        self.assertEqual(self.open(f"/api/visual-open?id=late&t={t}")[0], 403)
        self.assertEqual(self.open(url)[0], 403)

    def test_unknown_or_archived_id_is_404_at_mint(self):
        for vid in ("nope", "gone"):
            self.assertEqual(self.mint(vid)[0], 404, vid)
        h = {"Content-Type": "application/json", "X-Interview-Token": self.token}
        code, _, _ = request(
            self.port, "POST", "/api/visual-open", body={"id": 7}, headers=h
        )
        self.assertEqual(code, 404)

    def test_visual_archived_after_mint_is_404(self):
        path = self.dir / "questions.json"
        before = path.read_text(encoding="utf-8")
        url = self.minted("late")
        doc = json.loads(before)
        next(v for v in doc["visuals"] if v["id"] == "late")["archived"] = {
            "why": "x",
            "at": "2026-01-01T00:00:00Z",
        }
        path.write_text(json.dumps(doc), encoding="utf-8")
        try:
            self.assertEqual(self.open(url)[0], 404)
        finally:
            path.write_text(before, encoding="utf-8")

    def test_html_runs_scripts_only_in_an_opaque_origin(self):
        code, raw, h = self.open(self.minted("vh"))
        self.assertEqual((code, raw.decode("utf-8")), (200, self.HTML))
        self.assertEqual(h["Content-Type"], "text/html; charset=utf-8")
        self.assertTrue(
            h["Content-Security-Policy"].startswith("sandbox allow-scripts;")
        )
        self.assertNotIn("allow-same-origin", h["Content-Security-Policy"])
        self.assertEqual(h["X-Content-Type-Options"], "nosniff")
        self.assertEqual(h["Cache-Control"], "no-store")

    def test_other_formats_are_sandboxed_without_scripts(self):
        for vid, ctype, body in (
            ("inline", "image/svg+xml", b"<svg/>"),
            ("pic", "image/png", self.PNG),
            ("chart", "text/plain; charset=utf-8", b'{"a": [1, 2]}'),
        ):
            code, raw, h = self.open(self.minted(vid))
            self.assertEqual((code, h["Content-Type"], raw), (200, ctype, body), vid)
            csp = h["Content-Security-Policy"]
            self.assertTrue(csp.startswith("sandbox;"), vid)
            self.assertNotIn("allow-", csp, vid)
            self.assertEqual(h["X-Content-Type-Options"], "nosniff")

    def test_inline_image_url_opens_in_an_img_page(self):
        code, raw, h = self.open(self.minted("durl"))
        self.assertEqual(code, 200)
        self.assertEqual(raw, b'<img alt="" src="data:image/png;base64,AA==">')
        self.assertTrue(h["Content-Security-Policy"].startswith("sandbox;"))

    def test_image_file_without_an_image_extension_is_415(self):
        self.assertEqual(self.open(self.minted("top"))[0], 415)

    def test_file_over_the_cap_is_413(self):
        self.assertEqual(self.open(self.minted("big"))[0], 413)

    def test_never_serves_a_path_outside_the_data_dir_or_a_runtime_file(self):
        for vid in ("up", "abs", "subup", "updown", "unc", "unc2", "drive", "ads"):
            code, raw, _ = self.open(self.minted(vid))
            self.assertEqual(code, 404, vid)
            self.assertNotIn(b"outside", raw)
        for vid in ("session", "tmp", "dot", "dir"):
            code, raw, _ = self.open(self.minted(vid))
            self.assertEqual(code, 404, vid)
            self.assertNotIn(self.token.encode(), raw)


class TestVisualOpenExpiry(unittest.TestCase):
    """A new-tab nonce stops working OPEN_SECONDS after its mint, and expired ones are dropped."""

    def test_nonce_expires(self):
        import server

        tmp = Path(tempfile.mkdtemp(prefix="iv-open-"))
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        with unittest.mock.patch.dict(os.environ, settings_env(), clear=True):
            hub = server.Hub(0, tmp)
        clock = unittest.mock.patch.object(server.time, "monotonic")
        with clock as now:
            now.return_value = 100.0
            live, stale = hub.mint_open("v"), hub.mint_open("v")
            hub.mint_open("never-used")
            now.return_value = 100.0 + server.OPEN_SECONDS - 0.5
            self.assertTrue(hub.take_open(live, "v"))
            now.return_value = 100.0 + server.OPEN_SECONDS
            self.assertFalse(hub.take_open(stale, "v"))
            hub.mint_open("w")
            self.assertEqual(len(hub.opens), 1)


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
        self.assertLess(took, WAKE_SECONDS)
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
        self.assertLess(took, WAKE_SECONDS)
        self.assertEqual(seqs(body["events"]), [posted["seq"]])


class TestBurst(WaitCase):
    """AC18: saves close together reach an armed watcher as one wake."""

    @classmethod
    def prepare(cls):
        seed_questions(cls.dir, question("A"), question("B"), question("C"))

    def test_three_accepts_50_ms_apart_arrive_in_one_wait(self):
        seq0 = self.state()["responses"]["seq"]

        def burst():
            posted = []
            for qid in "ABC":
                posted.append(self.post({"id": qid, "kind": "accept"})[1]["seq"])
                time.sleep(0.05)
            return posted

        r, posted = self.wait_during(f"after={seq0}&timeout=20", burst)
        code, body, _ = r
        self.assertEqual(code, 200)
        self.assertEqual(seqs(body["events"]), posted)
        events = self.state()["responses"]["events"]
        self.assertEqual([e["seq"] for e in events if e.get("deliveredAt")], posted)


class TestEventStreamPing(ServerCase):
    """An idle event stream carries a ping frame at least every PING_SECONDS."""

    def test_idle_stream_gets_a_ping(self):
        from server import PING_SECONDS

        conn = http.client.HTTPConnection(
            "127.0.0.1", self.port, timeout=PING_SECONDS + 5
        )
        try:
            conn.request("GET", "/events")
            resp = conn.getresponse()
            started = time.monotonic()
            while not (line := resp.fp.readline()).startswith(b"event: ping"):
                self.assertTrue(line, "the stream closed before a ping")
            self.assertLess(time.monotonic() - started, PING_SECONDS + 2)
            self.assertEqual(resp.fp.readline(), b"data: {}\n")
        finally:
            conn.close()


class TestEventStreamCap(ServerCase):
    """At most MAX_STREAMS event streams at once: one more is 503 until a stream closes."""

    def open_stream(self, streams):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=TIMEOUT)
        conn.request("GET", "/events")
        resp = conn.getresponse()
        streams.append((conn, resp))
        return resp

    def test_the_stream_over_the_cap_is_503_until_one_closes(self):
        from server import MAX_STREAMS

        streams = []
        try:
            for _ in range(MAX_STREAMS):
                resp = self.open_stream(streams)
                self.assertEqual(resp.status, 200)
                self.assertEqual(resp.fp.readline(), b"retry: 2000\n")
            resp = self.open_stream(streams)
            self.assertEqual(resp.status, 503)
            self.assertIn("streams", json.loads(resp.read())["error"])
            for part in streams.pop(0):
                part.close()
            deadline = time.monotonic() + 5
            while (resp := self.open_stream(streams)).status != 200:
                resp.read()
                self.assertLess(time.monotonic(), deadline, "no slot freed")
                time.sleep(0.2)
        finally:
            for conn, resp in streams:
                resp.close()
                conn.close()


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


class TestHedged(WaitCase):
    """A hedged decision is an accept that carries its condition as the event text."""

    @classmethod
    def prepare(cls):
        seed_questions(cls.dir, question("A"))

    def test_a_hedged_decision_needs_a_condition_within_the_line_cap(self):
        before = self.state()["responses"]["events"]
        for text in ("", "   ", "x" * 501):
            code, data = self.post({"id": "A", "kind": "hedged", "text": text})
            self.assertEqual(code, 400, data)
        self.assertEqual(self.state()["responses"]["events"], before)

    def test_a_hedged_decision_is_recorded_rebuilds_and_validates(self):
        from server import rebuild_responses

        code, data = self.post({"id": "A", "kind": "hedged", "text": "if it is cheap"})
        self.assertEqual(code, 200, data)
        r = self.state()["responses"]
        self.assertEqual(r["responses"]["A"]["decision"], "hedged")
        self.assertEqual(r["responses"]["A"]["text"], "if it is cheap")
        self.assertEqual(rebuild_responses(r["events"]), (r["responses"], r["history"]))
        rc, out = self.rp("validate")
        self.assertEqual(rc, 0, out)


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

    def test_7_revising_marks_the_question_with_its_own_delivered_unhandled_decision(
        self,
    ):
        self.handle_all()
        self.decide("A", "alt", alt="a")
        before = {
            q["id"]: q.get("revising") for q in self.state()["questions"]["questions"]
        }
        self.assertFalse(before["A"], "revising before delivery")
        code, body, _ = self.wait("after=handled&replayed=0&timeout=5")
        self.assertFalse(body["timedOut"])
        rev = {
            q["id"]: q.get("revising") for q in self.state()["questions"]["questions"]
        }
        self.assertEqual(rev, {"A": True, "B": False, "C": False, "D": False})
        self.handle_all()
        rev = {
            q["id"]: q.get("revising") for q in self.state()["questions"]["questions"]
        }
        self.assertFalse(rev["A"])

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


class TestAnswered(WaitCase):
    """`answered` is true when a page or terminal decision counts; `state` stays dependency staleness."""

    @classmethod
    def prepare(cls):
        seed_questions(cls.dir, question("A"), question("B"), question("C"))

    def answered(self):
        return {
            q["id"]: (q.get("answered"), q.get("state"))
            for q in self.state()["questions"]["questions"]
        }

    def test_1_unanswered_is_false(self):
        self.assertEqual(self.answered()["A"], (False, "open"))

    def test_2_terminal_decision_is_answered_and_state_stays_open(self):
        rc, out = self.rp("record-terminal", "A", "--decision", "accept")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.answered()["A"], (True, "open"))

    def test_3_page_accept_is_answered(self):
        code, data = self.post({"id": "B", "kind": "accept"})
        self.assertEqual(code, 200, data)
        self.assertEqual(self.answered()["B"], (True, "open"))
        self.assertEqual(self.answered()["C"], (False, "open"))

    def test_4_reopen_is_not_answered(self):
        for kind in ("accept", "reopen"):
            code, data = self.post({"id": "C", "kind": kind})
            self.assertEqual(code, 200, data)
        self.assertEqual(self.answered()["C"], (False, "open"))


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

    def test_3_a_repeated_confirm_returns_the_existing_seq(self):
        body = {"id": "A", "kind": "confirm", "alt": "1"}
        before = self.state()["responses"]
        first = next(e["seq"] for e in before["events"] if e["kind"] == "confirm")
        code, data = self.post(body)
        self.assertEqual((code, data["seq"]), (200, first), data)
        after = self.state()["responses"]
        self.assertEqual(after["seq"], before["seq"])
        self.assertEqual(len(after["events"]), len(before["events"]))
        code, data = self.post({**body, "alt": "0"})
        self.assertEqual(code, 200, data)
        self.assertEqual(data["seq"], after["seq"] + 1)

    def test_4_a_confirm_after_a_commitments_revise_is_a_new_event(self):
        body = {"id": "A", "kind": "confirm", "alt": "0"}
        code, first = self.post(body)
        self.assertEqual(code, 200, first)
        rc, out = self.rp(
            "revise", "A", "--commit", "Third", "--commit", "Fourth", "--force"
        )
        self.assertEqual(rc, 0, out)
        code, data = self.post(body)
        self.assertEqual(code, 200, data)
        self.assertGreater(data["seq"], first["seq"])
        code, again = self.post(body)
        self.assertEqual((code, again["seq"]), (200, data["seq"]), again)

    def test_5_a_confirm_carrying_an_old_question_rev_is_stale(self):
        rev = next(
            q.get("contentRev") or 0
            for q in self.state()["questions"]["questions"]
            if q["id"] == "A"
        )
        rc, out = self.rp("revise", "A", "--commit", "Fifth", "--force")
        self.assertEqual(rc, 0, out)
        before = len(self.state()["responses"]["events"])
        code, data = self.post(
            {"id": "A", "kind": "confirm", "alt": "0", "contentRev": rev}
        )
        self.assertEqual((code, data["error"]), (409, "stale"), data)
        self.assertEqual(len(self.state()["responses"]["events"]), before)
        code, data = self.post(
            {"id": "A", "kind": "confirm", "alt": "0", "contentRev": rev + 1}
        )
        self.assertEqual(code, 200, data)


def seed_restatement(d, rev):
    doc = json.loads((Path(d) / "questions.json").read_text(encoding="utf-8"))
    doc["restatement"] = {"rev": rev, "at": "t", "sections": {"goal": "Ship it."}}
    (Path(d) / "questions.json").write_text(json.dumps(doc), encoding="utf-8")


class TestConfirmUnderstanding(WaitCase):
    """The `confirm-understanding` event: free, `alt` confirm or off, keyed to restatement.rev."""

    @classmethod
    def prepare(cls):
        seed_questions(cls.dir, question("A"))
        seed_restatement(cls.dir, 2)

    def test_1_confirm_is_saved_free_with_its_rev_and_wakes_the_watcher(self):
        code, data = self.post(
            {
                "id": "A",
                "kind": "confirm-understanding",
                "alt": "confirm",
                "contentRev": 2,
            }
        )
        self.assertEqual(code, 200, data)
        e = self.state()["responses"]["events"][-1]
        self.assertEqual(
            (e["id"], e["kind"], e["alt"], e["contentRev"]),
            (None, "confirm-understanding", "confirm", 2),
        )
        self.assertNotIn("A", self.state()["responses"]["responses"])
        code, body, _ = self.wait("after=handled&replayed=0&timeout=5")
        self.assertIn(data["seq"], seqs(body["events"]))
        rc, out = self.rp("validate")
        self.assertEqual(rc, 0, out)

    def test_2_off_needs_text(self):
        body = {"kind": "confirm-understanding", "alt": "off", "contentRev": 2}
        code, data = self.post(body)
        self.assertEqual(code, 400, data)
        code, data = self.post({**body, "text": "The goal is wrong."})
        self.assertEqual(code, 200, data)

    def test_3_alt_must_be_confirm_or_off(self):
        for alt in (None, "yes", "0"):
            code, data = self.post(
                {"kind": "confirm-understanding", "alt": alt, "contentRev": 2}
            )
            self.assertEqual(code, 400, (alt, data))

    def test_4_an_old_rev_is_409_stale(self):
        code, data = self.post(
            {"kind": "confirm-understanding", "alt": "confirm", "contentRev": 1}
        )
        self.assertEqual(code, 409, data)
        self.assertEqual(data, {"error": "stale", "contentRev": 2})
        code, data = self.post({"kind": "confirm-understanding", "alt": "confirm"})
        self.assertEqual(code, 400, data)

    def test_5_a_repeated_confirm_of_the_same_rev_returns_the_existing_seq(self):
        # test_2 flagged rev 2 after test_1 confirmed it, so the next Confirm is new.
        body = {"kind": "confirm-understanding", "alt": "confirm", "contentRev": 2}
        before = self.state()["responses"]
        self.assertEqual(before["events"][-1]["alt"], "off")
        code, data = self.post(body)
        self.assertEqual((code, data["seq"]), (200, before["seq"] + 1), data)
        after = self.state()["responses"]
        code, data = self.post(body)
        self.assertEqual((code, data["seq"]), (200, after["seq"]), data)
        self.assertEqual(self.state()["responses"]["events"], after["events"])


class TestAcceptAudit(WaitCase):
    """The `accept-audit` event: one post accepts the listed eligible questions, refuses the rest."""

    @classmethod
    def prepare(cls):
        seed_questions(
            cls.dir,
            question("A"),
            question("B", dependsOn=["A"]),
            question("C"),
            question("D", archived={"why": "off path", "at": "t"}),
            question("E", recommendation=""),
            question("F", waiting=True),
        )

    def audit(self, *items, alt="1"):
        return self.post(
            {
                "kind": "accept-audit",
                "alt": alt,
                "items": [{"id": i, "contentRev": r} for i, r in items],
            }
        )

    def events(self):
        return self.state()["responses"]["events"]

    def test_1_a_malformed_event_is_400_and_writes_nothing(self):
        item = {"id": "A", "contentRev": 0}
        for body in (
            {"kind": "accept-audit", "items": [item]},
            {"kind": "accept-audit", "alt": " ", "items": [item]},
            {"kind": "accept-audit", "alt": "1"},
            {"kind": "accept-audit", "alt": "1", "items": []},
            {"kind": "accept-audit", "alt": "1", "items": ["A"]},
            {"kind": "accept-audit", "alt": "1", "items": [{"id": "A"}]},
            {"kind": "accept-audit", "alt": "1", "items": [{**item, "extra": 1}]},
            {
                "kind": "accept-audit",
                "alt": "1",
                "items": [{"id": "A", "contentRev": True}],
            },
            {"kind": "accept-audit", "alt": "1", "items": [{"id": 7, "contentRev": 0}]},
            {"kind": "accept-audit", "alt": "1", "items": [item, item]},
        ):
            code, data = self.post(body)
            self.assertEqual(code, 400, (body, data))
        self.assertEqual(self.events(), [])

    def test_2_the_accepted_event_lists_its_items_and_fans_out_one_accept_each(self):
        code, data = self.audit(("A", 0), ("C", 0))
        self.assertEqual(code, 200, data)
        self.assertEqual(
            (data["seq"], data["accepted"], data["skipped"]), (1, ["A", "C"], [])
        )
        head, *accepts = self.events()
        self.assertEqual(
            {k: head[k] for k in ("seq", "id", "kind", "alt", "items")},
            {
                "seq": 1,
                "id": None,
                "kind": "accept-audit",
                "alt": "1",
                "items": [
                    {"id": "A", "contentRev": 0},
                    {"id": "C", "contentRev": 0},
                ],
            },
        )
        self.assertEqual(
            [(e["seq"], e["id"], e["kind"], e["auditSeq"]) for e in accepts],
            [(2, "A", "accept", 1), (3, "C", "accept", 1)],
        )
        responses = self.state()["responses"]["responses"]
        self.assertEqual(
            (responses["A"]["decision"], responses["A"]["seq"]), ("accept", 2)
        )
        self.assertEqual(responses["C"]["seq"], 3)

    def test_3_a_stale_or_ineligible_question_is_skipped_and_left_alone(self):
        # Claude revised C after the user opened it.
        path = self.dir / "questions.json"
        doc = json.loads(path.read_text(encoding="utf-8"))
        next(q for q in doc["questions"] if q["id"] == "C")["contentRev"] = 5
        path.write_text(json.dumps(doc), encoding="utf-8")
        before = self.state()["responses"]["responses"]
        code, data = self.audit(
            ("B", 0), ("C", 2), ("D", 0), ("E", 0), ("F", 0), ("X", 0)
        )
        self.assertEqual(code, 200, data)
        self.assertEqual(data["accepted"], ["B"])
        self.assertEqual(
            data["skipped"],
            [
                {"id": "C", "reason": "changed"},
                {"id": "D", "reason": "ineligible"},
                {"id": "E", "reason": "ineligible"},
                {"id": "F", "reason": "ineligible"},
                {"id": "X", "reason": "ineligible"},
            ],
        )
        after = self.state()["responses"]["responses"]
        self.assertEqual({k: v for k, v in after.items() if k != "B"}, before)
        self.assertEqual(self.events()[-2]["items"], [{"id": "B", "contentRev": 0}])

    def test_4_a_prerequisite_decided_only_in_the_same_batch_does_not_count(self):
        path = self.dir / "questions.json"
        doc = json.loads(path.read_text(encoding="utf-8"))
        doc["questions"].append(question("G", dependsOn=["H"]))
        doc["questions"].append(question("H"))
        path.write_text(json.dumps(doc), encoding="utf-8")
        code, data = self.audit(("G", 0), ("H", 0))
        self.assertEqual((code, data["accepted"]), (200, ["H"]), data)
        self.assertEqual(data["skipped"], [{"id": "G", "reason": "ineligible"}])

    def test_5_nothing_accepted_is_409_and_writes_nothing(self):
        n = len(self.events())
        code, data = self.audit(("E", 0), ("X", 0))
        self.assertEqual(code, 409, data)
        self.assertEqual(data["error"], "nothing accepted")
        self.assertEqual(len(data["skipped"]), 2)
        self.assertEqual(len(self.events()), n)

    def test_6_content_rev_counts_the_fanned_out_accept_and_undo_restores(self):
        code, data = self.post({"id": "A", "kind": "accept", "contentRev": 1})
        self.assertEqual(code, 200, data)
        code, data = self.audit(("A", 1))
        self.assertEqual(
            (code, data["skipped"]), (409, [{"id": "A", "reason": "changed"}])
        )
        undo = self.events()[-1]["seq"]
        code, data = self.post({"kind": "undo", "id": "A", "undoSeq": undo})
        self.assertEqual(code, 200, data)
        # The audit's own accept of A is live again, as it was before the plain accept.
        self.assertEqual(self.state()["responses"]["responses"]["A"]["seq"], 2)

    def test_7_the_log_rebuilds_and_validates(self):
        from server import rebuild_responses

        r = self.state()["responses"]
        responses, history = rebuild_responses(r["events"])
        self.assertEqual(responses, r["responses"])
        self.assertEqual(history, r["history"])
        rc, out = self.rp("validate")
        self.assertEqual(rc, 0, out)


class OpsCase(WaitCase):
    """WaitCase with helpers to apply ops and read question states."""

    def apply_ops(self, *ops):
        path = self.tmp / "ops.json"
        path.write_text(json.dumps({"ops": list(ops)}), encoding="utf-8")
        rc, out = self.rp("apply", "--file", str(path))
        self.assertEqual(rc, 0, out)
        return out

    def decide(self, qid, kind="accept", **extra):
        code, data = self.post({"id": qid, "kind": kind, **extra})
        self.assertEqual(code, 200, data)
        return data["seq"]

    def states(self):
        return {q["id"]: q.get("state") for q in self.state()["questions"]["questions"]}


class TestRecChangeMarksUpstream(OpsCase):
    """A recommendation change marks each question named in affects, and each direct dependent,
    that holds a decision: stale, with the revised id as the cause, until it is answered again."""

    @classmethod
    def prepare(cls):
        seed_questions(
            cls.dir,
            question("A"),
            question("B", dependsOn=["A"]),
            question("C"),
            question("D"),
            question("E", dependsOn=["A"]),
        )

    def marks(self):
        return {
            q["id"]: (q["state"], q.get("upstreamChanged"))
            for q in self.state()["questions"]["questions"]
        }

    def test_1_the_named_question_and_the_direct_dependent_go_stale(self):
        for qid in ("B", "C", "D"):
            self.decide(qid)
        rc, out = self.rp("revise", "A", "--rec", "Different.", "--affects", "C")
        self.assertEqual(rc, 0, out)
        self.assertEqual(
            self.marks(),
            {
                "A": ("open", None),
                "B": ("stale", ["A"]),
                "C": ("stale", ["A"]),
                "D": ("open", None),
                "E": ("open", None),
            },
        )

    def test_2_answering_the_marked_question_again_clears_only_its_mark(self):
        self.decide("C")
        marks = self.marks()
        self.assertEqual((marks["C"], marks["B"]), (("open", None), ("stale", ["A"])))

    def test_3_none_still_marks_the_direct_dependents(self):
        self.decide("E")
        self.assertEqual(self.states()["E"], "open")
        rc, out = self.rp("revise", "A", "--rec", "Once more.", "--affects", "none")
        self.assertEqual(rc, 0, out)
        marks = self.marks()
        self.assertEqual(marks["E"], ("stale", ["A"]))
        self.assertEqual(marks["C"], ("open", None))

    def test_4_the_mark_is_derived_never_written(self):
        doc = json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))
        self.assertFalse(
            any("upstreamChanged" in q or "state" in q for q in doc["questions"])
        )

    def test_5_a_session_terminal_record_clears_it_like_any_stale_question(self):
        time.sleep(1.1)  # a terminal decision is placed by its one-second timestamp
        rc, out = self.rp("record-terminal", "B", "--decision", "accept")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.marks()["B"], ("open", None))


class TestTerminalAnswerRightAfterARecChange(OpsCase):
    """A terminal answer recorded after a recommendation change counts as the reconfirmation even
    when both writes land in the same second."""

    @classmethod
    def prepare(cls):
        earlier = {
            "decision": "accept",
            "alt": None,
            "text": "",
            "updatedAt": "2026-01-01T00:00:00Z",
            "rev": 1,
        }
        seed_questions(
            cls.dir, question("A"), question("B", dependsOn=["A"], terminal=earlier)
        )

    def test_1_the_later_write_wins_the_tie(self):
        rc, out = self.rp("revise", "A", "--rec", "Different.", "--affects", "none")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.states()["B"], "stale")
        rc, out = self.rp("record-terminal", "B", "--decision", "accept")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.states()["B"], "open")


class TestRepointAndRevisedDependencies(OpsCase):
    """The stale derivation reads dependsOn, so a repoint or a revise changes what goes stale on
    the next decision."""

    @classmethod
    def prepare(cls):
        seed_questions(
            cls.dir,
            question("A"),
            question("B", dependsOn=["A"]),
            question("C", dependsOn=["A"]),
        )

    def test_1_repointing_after_answers_exist_moves_the_stale_mark_to_the_new_parent(
        self,
    ):
        self.decide("B")
        rc, out = self.rp(
            "add", "--id", "N", "--short", "S", "--title", "T?", "--rec", "Yes.",
            "--commit", "none", "--alt", "a:No", "--alt", "b:Later",
            "--supersedes", "A", "--repoint",
        )  # fmt: skip
        self.assertEqual(rc, 0, out)
        self.assertIn("repointed B, C from A to N", out)
        self.assertEqual(self.states()["B"], "open")
        self.decide("N")
        self.assertEqual(self.states()["B"], "stale")

    def test_2_a_revised_dependency_list_changes_what_goes_stale(self):
        self.decide("C")
        rc, out = self.rp("revise", "C", "--depends", "none", "--force")
        self.assertEqual(rc, 0, out)
        self.decide("N", "alt", alt="a")
        self.assertEqual(self.states()["C"], "open")

    def test_3_the_history_line_is_served_with_the_change(self):
        c = next(q for q in self.state()["questions"]["questions"] if q["id"] == "C")
        self.assertEqual(c["history"][-1]["kind"], "depends")


class TestUserHoldClearsOnTheNextAnswer(OpsCase):
    """A `by: user` hold ends, with no further op, when the user's next accept, alt or own on the
    question lands after the hold. The stored hold stays; every reader derives the clearing."""

    @classmethod
    def prepare(cls):
        seed_questions(cls.dir, *(question(x) for x in "ABCD"))

    def hold(self, qid):
        self.apply_ops(
            {"op": "wait", "id": qid, "waitsOn": "your answer", "by": "user"}
        )

    def held(self, qid):
        q = next(x for x in self.state()["questions"]["questions"] if x["id"] == qid)
        return bool(q.get("waiting"))

    def ledger(self):
        out = self.tmp / "ledger.md"
        rc, text = self.rp("export-ledger", "--out", str(out))
        self.assertEqual(rc, 0, text)
        return out.read_text(encoding="utf-8")

    def test_1_an_accept_after_the_hold_ends_it_and_an_undo_restores_it(self):
        self.decide("A")  # before the hold: set aside by it
        self.hold("A")
        self.assertTrue(self.held("A"))
        self.assertIn("awaiting user", self.rp("status")[1])
        self.assertIn("hold:: user", self.ledger())
        seq = self.decide("A")
        self.assertFalse(self.held("A"))
        self.assertNotIn("awaiting user", self.rp("status")[1])
        self.assertNotIn("hold::", self.ledger())
        stored = json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))
        self.assertTrue(
            next(q for q in stored["questions"] if q["id"] == "A")["waiting"]
        )
        code, data = self.post({"kind": "undo", "id": "A", "undoSeq": seq})
        self.assertEqual(code, 200, data)
        self.assertTrue(self.held("A"))

    def test_2_alt_and_own_end_it_too_and_ask_defer_and_hedged_do_not(self):
        self.hold("B")
        self.decide("B", "ask", text="why?")
        self.decide("B", "defer")
        self.decide("B", "hedged", text="if it is cheap")
        self.assertTrue(self.held("B"))
        self.decide("B", "own", text="Do it my way.")
        self.assertFalse(self.held("B"))
        self.hold("C")
        self.decide("C", "alt", alt="a")
        self.assertFalse(self.held("C"))

    def test_3_a_hold_by_claude_is_not_touched_by_an_answer(self):
        self.apply_ops({"op": "wait", "id": "D", "waitsOn": "research"})
        self.decide("D")
        self.assertTrue(self.held("D"))


class TestImportedUserHoldClearsOnTheNextAnswer(OpsCase):
    """An imported `by: user` hold carries no setAsideSeq; the next answer still ends it."""

    @classmethod
    def prepare(cls):
        hold = {
            "waiting": True,
            "waitsOn": "your answer",
            "waitingBy": "user",
            "waitingSince": "2026-01-01T00:00:00Z",
        }
        seed_questions(cls.dir, question("E", **hold))

    def held(self):
        return bool(self.state()["questions"]["questions"][0].get("waiting"))

    def test_1_an_accept_ends_it(self):
        self.assertTrue(self.held())
        self.decide("E")
        self.assertFalse(self.held())


class TestDecisionEventsNameTheirContentRev(OpsCase):
    """A decision event stores the content revision it answered."""

    @classmethod
    def prepare(cls):
        seed_questions(
            cls.dir, question("A", contentRev=3), question("B"), question("C")
        )

    def events(self):
        return self.state()["responses"]["events"]

    def test_1_an_accept_with_content_rev_3_is_stored_with_it(self):
        self.decide("A", contentRev=3)
        self.assertEqual(self.events()[-1]["contentRev"], 3)

    def test_2_every_decision_kind_carries_it_and_a_stale_one_is_refused(self):
        rev = 0
        for kind, extra in (
            ("own", {"text": "mine"}),
            ("alt", {"alt": "a"}),
            ("defer", {}),
            ("hedged", {"text": "if"}),
            ("reopen", {}),
        ):
            self.decide("B", kind, contentRev=rev, **extra)
            rev += 1
            self.assertEqual(self.events()[-1]["contentRev"], rev - 1, kind)
        n = len(self.events())
        code, data = self.post({"id": "B", "kind": "accept", "contentRev": 0})
        self.assertEqual((code, data["error"]), (409, "changed"))
        self.assertEqual(len(self.events()), n)

    def test_3_an_event_sent_without_one_stores_none(self):
        self.decide("C")
        self.assertNotIn("contentRev", self.events()[-1])

    def test_4_an_accept_audit_fans_out_accepts_that_carry_their_items_rev(self):
        seed = {
            "kind": "accept-audit",
            "alt": "1",
            "items": [{"id": "C", "contentRev": 1}],
        }
        code, data = self.post(seed)
        self.assertEqual(code, 200, data)
        self.assertEqual(self.events()[-1]["contentRev"], 1)
        rc, out = self.rp("validate")
        self.assertEqual(rc, 0, out)


class TestArchivedPrerequisiteIsMet(OpsCase):
    """A question whose prerequisite was archived or superseded is eligible for accept-audit; one
    whose prerequisite is live and undecided still is not."""

    @classmethod
    def prepare(cls):
        gone = {"why": "Off the path.", "at": "2026-09-24T10:00:00Z"}
        seed_questions(
            cls.dir,
            question("P", archived=gone),
            question("S", supersededBy="N"),
            question("N"),
            question("X"),
            question("B", dependsOn=["P"]),
            question("C", dependsOn=["S"]),
            question("D", dependsOn=["X"]),
        )

    def test_the_audit_accepts_the_dependents_of_a_question_that_left_the_path(self):
        items = [{"id": i, "contentRev": 0} for i in "BCD"]
        code, data = self.post({"kind": "accept-audit", "alt": "1", "items": items})
        self.assertEqual(code, 200, data)
        self.assertEqual(data["accepted"], ["B", "C"])
        self.assertEqual(data["skipped"], [{"id": "D", "reason": "ineligible"}])


class TestConfirmUnderstandingNeedsARestatement(WaitCase):
    @classmethod
    def prepare(cls):
        seed_questions(cls.dir, question("A"))

    def test_no_restatement_is_400(self):
        code, data = self.post(
            {"kind": "confirm-understanding", "alt": "confirm", "contentRev": 1}
        )
        self.assertEqual(code, 400, data)
        self.assertIn("restatement", data["error"])


class TestUnderstandingCheckedUnderTheLock(unittest.TestCase):
    """confirm-understanding is checked against questions.json read inside the hub's lock."""

    def test_the_check_runs_under_the_lock(self):
        import server

        tmp = Path(tempfile.mkdtemp(prefix="iv-lock-"))
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        seed_questions(tmp, question("A"))
        seed_restatement(tmp, 2)
        with unittest.mock.patch.dict(os.environ, settings_env(), clear=True):
            hub = server.Hub(0, tmp)
        held, real = [], server.check_understanding

        def spy(*args):
            held.append(hub.cond._is_owned())
            return real(*args)

        with unittest.mock.patch.object(server, "check_understanding", spy):
            hub.record(
                {"kind": "confirm-understanding", "alt": "confirm", "contentRev": 2}
            )
        self.assertEqual(held, [True])


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
            "leaseTimeout": 600,
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

    def test_1_no_flag_on_a_new_file_records_false(self):
        self.assertTrue((self.dir / "questions.json").exists())
        self.assertIs(self.meta().get("emojiMarkers"), False)

    def test_2_false_is_recorded_and_a_repeat_does_not_bump_rev(self):
        p = ensure_running(self.dir, "--emoji-markers", "false")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIs(self.meta().get("emojiMarkers"), False)
        rev = self.state()["questions"]["rev"]
        ensure_running(self.dir, "--emoji-markers", "false")
        self.assertEqual(self.state()["questions"]["rev"], rev)

    def test_3_display_name_reaches_state(self):
        self.assertEqual(self.state()["settings"]["displayName"]["value"], "You")

    def test_4_no_flag_keeps_the_recorded_value(self):
        for value in ("true", "false"):
            with self.subTest(value=value):
                ensure_running(self.dir, "--emoji-markers", value)
                rev = self.state()["questions"]["rev"]
                p = ensure_running(self.dir)
                self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
                self.assertIs(self.meta().get("emojiMarkers"), value == "true")
                self.assertEqual(self.state()["questions"]["rev"], rev)


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

    def test_non_string_id_or_kind_is_400_and_the_server_answers(self):
        for body in (
            {"id": "A", "kind": []},
            {"id": [], "kind": "accept"},
            {"id": {}, "kind": "note", "text": "x"},
        ):
            code, data = self.post(body)
            self.assertEqual(code, 400, body)
            self.assertIn("must be strings", data["error"])
            self.assertEqual(self.get("/api/state")[0], 200)

    def test_mistyped_text_content_rev_or_undo_seq_is_400(self):
        for body in (
            {"id": "A", "kind": "own", "text": ["x"]},
            {"id": "A", "kind": "accept", "contentRev": "0"},
            {"id": "A", "kind": "accept", "contentRev": True},
            {"kind": "undo", "undoSeq": True},
            {"kind": "undo", "undoSeq": 1.5},
        ):
            code, _ = self.post(body)
            self.assertEqual(code, 400, body)

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

    def test_recorded_url_is_never_printed_or_opened(self):
        self.ensure()
        s = session(self.dir)
        s["url"] = "planted-not-a-url"
        (self.dir / ".interview-session.json").write_text(
            json.dumps(s), encoding="utf-8"
        )
        want = f"http://127.0.0.1:{s['port']}/"
        self.assertEqual(self.ensure("--open"), want)
        self.assertEqual(self.fallback_opened(), want)

    def test_recorded_user_file_keeps_supplying_settings(self):
        data = json.loads(self.user.read_text(encoding="utf-8"))
        data.update(waitTimeout=33, openBrowser=False)
        self.user.write_text(json.dumps(data), encoding="utf-8")
        self.ensure("--user-settings", str(self.user))
        self.ensure("--open")
        env = (self.dir / ".interview-session.env").read_text(encoding="utf-8")
        self.assertIn("WAIT_TIMEOUT=33", env.splitlines())
        self.assertIsNone(self.fallback_opened())
        self.assertIsNone(self.opened(1.5))

    def test_planted_session_file_never_supplies_the_opener(self):
        (self.dir / ".interview-session.json").write_text(
            json.dumps({"pid": 1, "port": free_port(), "userSettings": str(self.user)}),
            encoding="utf-8",
        )
        url = self.ensure("--open")
        self.assertEqual(self.fallback_opened(), url)
        self.assertIsNone(self.opened(1.5))


class TestLease(WaitCase):
    """One watcher per data dir: the first holds a lease, a second gets 409 naming it.

    `leaseTimeout` is 5 in the data dir's settings.json. The methods run in order on one server.
    """

    env = settings_env()

    @classmethod
    def prepare(cls):
        (cls.dir / "settings.json").write_text(
            json.dumps({"leaseTimeout": 5}), encoding="utf-8"
        )

    def wait_as(self, watcher, timeout=1):
        """(status, body) of one after=handled wait; watcher None sends no watcher parameter."""
        query = f"after=handled&replayed=0&timeout={timeout}"
        if watcher is not None:
            query += f"&watcher={watcher}"
        code, body, _ = self.wait(query, timeout=timeout + 10)
        return code, body

    def lease(self):
        return self.state()["listener"]["lease"]

    def until_waiting(self, n=1):
        end = time.monotonic() + 10
        while time.monotonic() < end:
            if self.state()["listener"]["waiters"] >= n:
                return
            time.sleep(0.05)
        self.fail("no wait registered within 10 s")

    def test_1_second_watcher_gets_409_naming_the_holder(self):
        box = {}
        th = threading.Thread(target=lambda: box.update(r=self.wait_as("A", 8)))
        th.start()
        self.until_waiting()
        code, body = self.wait_as("B")
        th.join(30)
        self.assertEqual(code, 409, body)
        self.assertEqual(body["error"], "lease held")
        self.assertEqual(body["holder"], "A")
        for key in ("since", "lastWaitAt", "expiresAt"):
            self.assertRegex(body[key], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$", key)
        self.assertEqual(box["r"][0], 200)

    def test_2_holder_re_arms_and_state_names_it(self):
        code, body = self.wait_as("A")
        self.assertEqual(code, 200, body)
        lease = self.lease()
        self.assertEqual(lease["watcher"], "A")
        self.assertFalse(lease["waiting"])
        self.assertIn("since", lease)
        self.assertIn("lastWaitAt", lease)
        self.assertEqual(
            self.state()["settings"]["leaseTimeout"], {"value": 5, "layer": "session"}
        )

    def test_3_expired_lease_is_reclaimed(self):
        time.sleep(5.5)
        # Expired with no watcher having claimed since: no holder anywhere it is shown.
        self.assertIsNone(self.lease())
        rc, out = self.rp("lease")
        self.assertEqual((rc, out), (0, "no lease"))
        code, body = self.wait_as("B")
        self.assertEqual(code, 200, body)
        self.assertEqual(self.lease()["watcher"], "B")
        code, body = self.wait_as("A")
        self.assertEqual(code, 409, body)
        self.assertEqual(body["holder"], "B")

    def test_4_release_hands_the_lease_over(self):
        rc, out = self.rp("lease")
        self.assertEqual(rc, 0, out)
        self.assertIn("B", out)
        code, raw, _ = request(
            self.port,
            "POST",
            "/api/lease",
            body={"action": "release"},
            headers={"Content-Type": "application/json"},
        )
        self.assertEqual(code, 403, raw)
        rc, out = self.rp("lease", "--release")
        self.assertEqual(rc, 0, out)
        self.assertIsNone(self.lease())
        rc, out = self.rp("lease")
        self.assertEqual((rc, out), (0, "no lease"))
        code, body = self.wait_as("A")
        self.assertEqual(code, 200, body)
        self.assertEqual(self.lease()["watcher"], "A")

    def test_5_wait_without_watcher_takes_no_part(self):
        code, body = self.wait_as(None)
        self.assertEqual(code, 200, body)
        self.assertEqual(self.lease()["watcher"], "A")
        code, body = self.wait_as("B")
        self.assertEqual(code, 409, body)

    def test_6_restart_starts_with_no_lease(self):
        rc, out = self.rp("stop")
        self.assertEqual(rc, 0, out)
        p = ensure_running(self.dir, env=self.env)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        s = session(self.dir)
        type(self).port, type(self).token = s["port"], s["token"]
        self.assertIsNone(self.lease())
        code, body = self.wait_as("B")
        self.assertEqual(code, 200, body)
        self.assertEqual(self.lease()["watcher"], "B")

    def test_7_release_during_a_wait_delivers_the_next_event_once(self):
        old, new = {}, {}
        t_old = threading.Thread(target=lambda: old.update(r=self.wait_as("B", 20)))
        t_old.start()
        self.until_waiting()
        rc, out = self.rp("lease", "--release")
        self.assertEqual(rc, 0, out)
        t_new = threading.Thread(target=lambda: new.update(r=self.wait_as("C", 20)))
        t_new.start()
        end = time.monotonic() + 10
        while time.monotonic() < end and (self.lease() or {}).get("watcher") != "C":
            time.sleep(0.05)
        _, posted = self.post({"kind": "note", "text": "after the release"})
        t_old.join(30)
        t_new.join(30)
        code, body = old["r"]
        self.assertEqual(code, 409, body)
        self.assertEqual(body["error"], "lease released")
        self.assertNotIn("events", body)
        code, body = new["r"]
        self.assertEqual(code, 200, body)
        self.assertEqual(seqs(body["events"]), [posted["seq"]])
        self.assertEqual(self.lease()["watcher"], "C")


class TestSettleBurstCap(unittest.TestCase):
    """Hub.settle holds found events QUIET_SECONDS past the last new one, never BURST_SECONDS in all."""

    def setUp(self):
        import server

        self.server = server
        self.tmp = Path(tempfile.mkdtemp(prefix="iv-settle-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.hub = server.Hub(0, self.tmp)
        for name, value in (("QUIET_SECONDS", 0.3), ("BURST_SECONDS", 2.0)):
            patcher = unittest.mock.patch.object(server, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def settle_with(self, seqs_seen, deadline=float("inf")):
        feed = iter(seqs_seen)
        with unittest.mock.patch.object(
            self.server, "load_json", side_effect=lambda *_: {"seq": next(feed)}
        ):
            with self.hub.cond:
                start = time.monotonic()
                r = self.hub.settle({"seq": 0}, deadline)
                return r, time.monotonic() - start

    def test_a_quiet_log_returns_after_one_quiet_window(self):
        r, took = self.settle_with([0] * 5)
        self.assertEqual(r["seq"], 0)
        self.assertGreaterEqual(took, self.server.QUIET_SECONDS * 0.9)
        self.assertLess(took, self.server.QUIET_SECONDS + 0.5)

    def test_a_log_that_never_goes_quiet_is_cut_off_at_the_burst_cap(self):
        r, took = self.settle_with(range(1, 1000))
        self.assertGreater(r["seq"], 1)
        self.assertGreaterEqual(took, self.server.BURST_SECONDS * 0.95)
        self.assertLess(took, self.server.BURST_SECONDS + 0.5)

    def test_a_log_that_never_goes_quiet_is_cut_off_at_the_request_deadline(self):
        r, took = self.settle_with(range(1, 1000), deadline=time.time() + 0.5)
        self.assertGreater(r["seq"], 1)
        self.assertLess(took, 0.5 + 0.3)


if __name__ == "__main__":
    unittest.main()

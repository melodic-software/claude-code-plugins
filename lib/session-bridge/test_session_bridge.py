"""Tests for session-bridge: the Transport port, the loopback adapter's server and client halves,
and watch.sh and wake.sh against a toy app built on the bridge.

    python3 -m unittest test_session_bridge     (from lib/session-bridge/)
"""

import http.client
import json
import os
import shutil
import stat
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

import session_bridge as sb  # noqa: E402

TIMEOUT = 10


class ToyHub(sb.LoopbackWatcher):
    """A minimal app: log.json is the event log; `handled` holds the highest handled seq."""

    name = "toy"
    lease_seconds = 600

    def __init__(self, port, data_dir):
        super().__init__(port, data_dir)
        self.log = self.dir / "log.json"

    def read_log(self):
        try:
            return json.loads(self.log.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {"seq": 0, "events": []}

    def write_log(self, log):
        self.log.write_text(json.dumps(log), encoding="utf-8")

    def unhandled(self, log):
        try:
            done = int((self.dir / "handled").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            done = 0
        return [e for e in log["events"] if e["seq"] > done and not e.get("withdrawn")]

    def lease_timeout(self):
        return self.lease_seconds

    def settle_window(self):
        return 0.05, 0.2

    def identity(self):
        return {"app": "toy"}

    def read_state(self):
        return {"log": self.read_log(), "listener": self.listener()}, False

    def signature(self):
        return (self.read_log()["seq"], self.listener()["state"])

    def append(self, text):
        with self.cond:
            log = self.read_log()
            log["seq"] += 1
            log["events"].append({"seq": log["seq"], "text": text})
            self.write_log(log)
            self.cond.notify_all()
            return log["seq"]


class ToyHandler(sb.LoopbackHandler):
    max_body = 1024
    page_csp = "default-src 'none'"

    def route_get(self, url, query):
        if url.path == "/":
            return self.send(200, b"<p>toy</p>", "text/html")
        return self.send(404, {"error": "not found"})

    def route_post(self, path, msg):
        if path == "/api/event":
            return self.send(200, {"seq": self.hub.append(msg.get("text", ""))})
        return self.send(404, {"error": "not found"})


class BridgeCase(unittest.TestCase):
    """A toy server on a free port in a fresh data dir, served from a thread."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="sb-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.dir = self.tmp / "data"
        self.dir.mkdir()
        handler = type("Handler", (ToyHandler,), {})
        self.httpd, self.hub = sb.start(handler, lambda p: ToyHub(p, self.dir), 0)
        thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.httpd.server_close)
        self.addCleanup(self.httpd.shutdown)
        self.port = self.hub.port
        self.header = sb.token_header("toy")

    def request(self, method, path, body=None, headers=None, token=True):
        h = dict(headers or {})
        if token:
            h.setdefault(self.header, self.hub.token)
        if body is not None and not isinstance(body, bytes):
            body = json.dumps(body).encode()
            h.setdefault("Content-Type", "application/json")
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=TIMEOUT)
        try:
            conn.request(method, path, body=body, headers=h)
            resp = conn.getresponse()
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw[:1] == b"{" else raw), resp
        finally:
            conn.close()

    def wait_in_thread(self, path):
        out = {}

        def run():
            out["code"], out["body"], _ = self.request("GET", path)

        t = threading.Thread(target=run, daemon=True)
        t.start()
        self.until(lambda: self.hub.waiters > 0)
        return t, out

    def until(self, check, seconds=5):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if check():
                return
            time.sleep(0.02)
        self.fail("condition not met in time")


class TestPort(unittest.TestCase):
    def test_transport_is_abstract(self):
        with self.assertRaises(TypeError):
            sb.Transport()

    def test_an_app_without_the_log_hooks_cannot_bind_the_adapter(self):
        with self.assertRaises(TypeError):
            sb.LoopbackWatcher(0, tempfile.gettempdir())

    def test_the_loopback_adapter_implements_the_port(self):
        self.assertTrue(issubclass(sb.LoopbackWatcher, sb.Transport))
        hub = ToyHub(0, tempfile.gettempdir())
        self.assertEqual(hub.settle_window(), (0.05, 0.2))
        self.assertEqual(sb.Transport.lease_timeout(hub), sb.LEASE_TIMEOUT)

    def test_names_follow_the_app_name(self):
        self.assertEqual(
            sb.session_files("interview"),
            (".interview-session.json", ".interview-session.env"),
        )
        self.assertEqual(sb.token_header("interview"), "X-Interview-Token")


class TestSessionFiles(BridgeCase):
    def test_session_files_record_port_pid_and_token(self):
        s = json.loads((self.dir / ".toy-session.json").read_text(encoding="utf-8"))
        self.assertEqual(s["port"], self.port)
        self.assertEqual(s["pid"], os.getpid())
        self.assertEqual(s["token"], self.hub.token)
        self.assertEqual(s["url"], f"http://127.0.0.1:{self.port}/")
        env = (self.dir / ".toy-session.env").read_text(encoding="utf-8")
        self.assertIn(f"PORT={self.port}\n", env)
        self.assertIn(f"TOKEN={self.hub.token}\n", env)

    @unittest.skipUnless(os.name == "posix", "file modes are advisory on Windows")
    def test_session_files_are_owner_only(self):
        for f in sb.session_files("toy"):
            mode = stat.S_IMODE((self.dir / f).stat().st_mode)
            self.assertEqual(mode, 0o600, f)


class TestGuards(BridgeCase):
    def test_a_foreign_host_or_origin_is_refused(self):
        code, _, _ = self.request("GET", "/api/ping", headers={"Host": "evil:1"})
        self.assertEqual(code, 403)
        bad = {"Origin": "http://evil.example"}
        self.assertEqual(self.request("GET", "/api/ping", headers=bad)[0], 403)
        good = {"Origin": f"http://localhost:{self.port}"}
        self.assertEqual(self.request("GET", "/api/ping", headers=good)[0], 200)

    def test_wait_and_post_need_the_token_header(self):
        self.assertEqual(
            self.request("GET", "/api/wait?timeout=1", token=False)[0], 403
        )
        code, _, _ = self.request("POST", "/api/event", {"text": "x"}, token=False)
        self.assertEqual(code, 403)
        wrong = {self.header: "nope"}
        self.assertEqual(
            self.request("GET", "/api/wait?timeout=1", headers=wrong)[0], 403
        )

    def test_post_body_rules(self):
        plain = {"Content-Type": "text/plain"}
        self.assertEqual(self.request("POST", "/api/event", b"{}", plain)[0], 415)
        big = json.dumps({"text": "x" * 2000}).encode()
        code, body, _ = self.request(
            "POST", "/api/event", big, {"Content-Type": "application/json"}
        )
        self.assertEqual(code, 413)
        self.assertIn("1024", body["error"])
        js = {"Content-Type": "application/json"}
        self.assertEqual(self.request("POST", "/api/event", b"{nope", js)[0], 400)
        self.assertEqual(self.request("POST", "/api/event", b"[1]", js)[0], 400)

    def test_app_routes_and_the_page_policy(self):
        code, raw, resp = self.request("GET", "/")
        self.assertEqual((code, raw), (200, b"<p>toy</p>"))
        self.assertEqual(
            resp.getheader("Content-Security-Policy"), "default-src 'none'"
        )
        self.assertEqual(resp.getheader("X-Frame-Options"), "DENY")
        self.assertEqual(self.request("GET", "/nowhere")[0], 404)
        self.assertEqual(self.request("POST", "/nowhere", {})[0], 404)

    def test_ping_reports_identity_pid_and_data_dir(self):
        code, body, _ = self.request("GET", "/api/ping", token=False)
        self.assertEqual(code, 200)
        self.assertEqual(body["app"], "toy")
        self.assertEqual(body["pid"], os.getpid())
        self.assertEqual(body["dataDir"], str(self.dir.resolve()))


class TestLongPoll(BridgeCase):
    def test_an_event_posted_mid_wait_is_delivered_and_stamped(self):
        t, out = self.wait_in_thread("/api/wait?after=handled&timeout=5")
        self.assertEqual(self.request("POST", "/api/event", {"text": "hi"})[0], 200)
        t.join(TIMEOUT)
        self.assertEqual(out["code"], 200)
        body = out["body"]
        self.assertFalse(body["timedOut"])
        self.assertEqual([e["text"] for e in body["events"]], ["hi"])
        self.assertEqual(body["note"], sb.DATA_NOTE)
        self.assertTrue(self.hub.read_log()["events"][0]["deliveredAt"])
        self.assertEqual(self.hub.listener()["state"], "listening")

    def test_a_quiet_wait_times_out_with_no_events(self):
        code, body, _ = self.request("GET", "/api/wait?after=handled&timeout=1")
        self.assertEqual(code, 200)
        self.assertEqual((body["timedOut"], body["events"]), (True, []))

    def test_unhandled_events_replay_once_then_wait_for_new(self):
        self.hub.append("old")
        code, body, _ = self.request(
            "GET", "/api/wait?after=handled&replayed=0&timeout=1"
        )
        self.assertEqual((code, body["replayed"]), (200, 1))
        code, body, _ = self.request(
            "GET", "/api/wait?after=handled&replayed=1&timeout=1"
        )
        self.assertTrue(body["timedOut"])

    def test_after_a_seq_returns_later_events(self):
        self.hub.append("a")
        self.hub.append("b")
        code, body, _ = self.request("GET", "/api/wait?after=1&timeout=1")
        self.assertEqual([e["text"] for e in body["events"]], ["b"])

    def test_bad_query_numbers_are_400(self):
        self.assertEqual(self.request("GET", "/api/wait?after=x")[0], 400)

    def test_settle_holds_a_burst_until_quiet(self):
        self.hub.append("one")
        with self.hub.cond:
            start = time.monotonic()
            self.hub.settle(self.hub.read_log())
            took = time.monotonic() - start
        self.assertGreaterEqual(took, 0.04)
        self.assertLess(took, 0.5)


class TestLease(BridgeCase):
    def test_a_second_watcher_is_refused_while_the_first_waits(self):
        t, _ = self.wait_in_thread("/api/wait?after=handled&timeout=3&watcher=a&pid=42")
        code, body, _ = self.request(
            "GET", "/api/wait?after=handled&timeout=1&watcher=b"
        )
        self.assertEqual(code, 409)
        self.assertEqual((body["error"], body["holder"]), ("lease held", "a"))
        code, body, _ = self.request("GET", "/api/lease", token=False)
        self.assertEqual((body["lease"]["watcher"], body["lease"]["pid"]), ("a", 42))
        self.assertTrue(body["lease"]["waiting"])
        t.join(TIMEOUT)

    def test_a_release_ends_the_holders_wait_before_it_delivers(self):
        t, out = self.wait_in_thread("/api/wait?after=handled&timeout=5&watcher=a")
        code, body, _ = self.request("POST", "/api/lease", {"action": "release"})
        self.assertEqual((code, body), (200, {"ok": True, "lease": None}))
        t.join(TIMEOUT)
        self.assertEqual(out["code"], 409)
        self.assertEqual(out["body"]["error"], "lease released")
        self.assertEqual(self.request("POST", "/api/lease", {"action": "x"})[0], 400)

    def test_an_expired_lease_goes_to_the_next_watcher(self):
        self.hub.lease_seconds = 0
        self.request("GET", "/api/wait?after=handled&timeout=1&watcher=a")
        time.sleep(0.05)
        self.assertIsNone(self.hub.lease_view())
        code, _, _ = self.request("GET", "/api/wait?after=handled&timeout=1&watcher=b")
        self.assertEqual(code, 200)
        self.assertEqual(self.hub.lease["watcher"], "b")

    def test_a_wait_without_a_watcher_takes_no_part(self):
        self.request("GET", "/api/wait?timeout=1")
        self.assertIsNone(self.hub.lease)


class TestEventStream(BridgeCase):
    def test_the_stream_sends_a_state_frame(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=TIMEOUT)
        self.addCleanup(conn.close)
        conn.request("GET", "/events")
        resp = conn.getresponse()
        self.assertEqual(resp.status, 200)
        self.assertEqual(
            resp.getheader("Content-Type"), "text/event-stream; charset=utf-8"
        )
        self.assertEqual(resp.readline(), b"retry: 2000\n")
        resp.readline()
        self.assertEqual(resp.readline(), b"id: 1\n")
        self.assertEqual(resp.readline(), b"event: state\n")
        frame = json.loads(resp.readline()[len(b"data: ") :])
        self.assertEqual(frame["log"]["seq"], 0)

    def test_streams_past_the_cap_get_503(self):
        with unittest.mock.patch.object(sb, "MAX_STREAMS", 1):
            first = http.client.HTTPConnection("127.0.0.1", self.port, timeout=TIMEOUT)
            self.addCleanup(first.close)
            first.request("GET", "/events")
            # Hold the response: dropping it closes the socket, which frees the slot.
            stream = first.getresponse()
            self.addCleanup(stream.close)
            self.assertEqual(stream.readline(), b"retry: 2000\n")
            self.assertEqual(self.hub.streams, 1)
            code, body, _ = self.request("GET", "/events")
        self.assertEqual(code, 503)
        self.assertIn("1 event streams", body["error"])


class TestClient(BridgeCase):
    def test_ping_running_and_read_session(self):
        self.assertEqual(sb.ping(self.port)["pid"], os.getpid())
        s = sb.read_session(self.dir, "toy")
        self.assertTrue(sb.running(self.dir, s))
        self.assertFalse(sb.running(self.tmp, s))
        self.assertIsNone(sb.read_session(self.tmp, "toy"))

    def test_lease_client(self):
        s = sb.read_session(self.dir, "toy")
        self.assertIsNone(sb.watcher_lease(self.dir, "toy"))
        self.request("GET", "/api/wait?timeout=1&watcher=w")
        self.assertEqual(sb.watcher_lease(self.dir, "toy")["watcher"], "w")
        self.assertEqual(sb.release_lease(s, "toy"), 200)
        self.assertIsNone(sb.watcher_lease(self.dir, "toy"))

    def test_clear_session_keeps_the_port(self):
        sb.clear_session(self.dir, "toy")
        self.assertFalse((self.dir / ".toy-session.env").exists())
        self.assertEqual(sb.kept_port(self.dir, "toy"), self.port)
        self.assertIsNone(sb.read_session(self.dir, "toy"))

    def test_set_wait_timeout_replaces_the_line(self):
        sb.set_wait_timeout(self.dir, "toy", 30)
        sb.set_wait_timeout(self.dir, "toy", 45)
        env = (self.dir / ".toy-session.env").read_text(encoding="utf-8")
        self.assertEqual(env.count("WAIT_TIMEOUT="), 1)
        self.assertIn("WAIT_TIMEOUT=45\n", env)

    def test_port_free(self):
        self.assertFalse(sb.port_free(self.port))

    def test_end_watcher_signals_nothing_for_a_foreign_pid(self):
        with unittest.mock.patch.object(sb.os, "kill") as kill:
            sb.end_watcher(self.dir, os.getpid())
            sb.end_watcher(self.dir, 1)
            sb.end_watcher(self.dir, None)
        kill.assert_not_called()


@unittest.skipUnless(
    shutil.which("curl") and shutil.which("bash"), "needs bash and curl"
)
class TestWatcherScripts(BridgeCase):
    """watch.sh and wake.sh copied beside a toy control script and session-bridge.conf."""

    def setUp(self):
        super().setUp()
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        for f in ("watch.sh", "wake.sh"):
            shutil.copy(HERE / f, self.bin / f)
        (self.bin / "session-bridge.conf").write_text(
            "NAME=toy\nCONTROL=toy.sh\n", encoding="utf-8"
        )
        # The toy control script: `--dir D apply --file F` records F, then exits with $TOY_RC.
        (self.bin / "toy.sh").write_text(
            '#!/usr/bin/env bash\nprintf "%s\\n" "$@" >"$2/applied"\nexit "${TOY_RC:-0}"\n',
            encoding="utf-8",
        )
        self.env = {**os.environ, "WATCH_ID": "suite"}

    def run_script(self, name, *args, env=None, timeout=TIMEOUT):
        return subprocess.run(
            ["bash", str(self.bin / name), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            env={**self.env, **(env or {})},
        )

    def test_a_pending_event_is_printed_with_the_rearm_command(self):
        self.hub.append("hello")
        r = self.run_script("watch.sh", str(self.dir))
        self.assertEqual(r.returncode, 0, r.stderr)
        line = json.loads(r.stdout)
        self.assertEqual(line["events"][0]["text"], "hello")
        self.assertEqual(Path(line["dataDir"]).resolve(), self.dir.resolve())
        self.assertIn("wake.sh", line["next"])
        self.assertEqual((self.dir / ".watch-seq").read_text().strip(), "1")
        self.assertEqual((self.dir / ".watch-replay").read_text().strip(), "1")

    def test_a_missing_or_malformed_conf_exits_2(self):
        (self.bin / "session-bridge.conf").write_text(
            "NAME=Bad Name\n", encoding="utf-8"
        )
        r = self.run_script("watch.sh", str(self.dir))
        self.assertEqual(r.returncode, 2)
        self.assertIn("session-bridge.conf", r.stderr)
        r = self.run_script("wake.sh", str(self.dir))
        self.assertEqual(r.returncode, 2)

    def test_a_rejected_token_exits_2(self):
        env = self.dir / ".toy-session.env"
        env.write_text(env.read_text().replace(self.hub.token, "stale"))
        r = self.run_script("watch.sh", str(self.dir))
        self.assertEqual(r.returncode, 2)
        self.assertIn("token changed", r.stderr)

    def test_a_held_lease_exits_3_naming_the_holder(self):
        t, _ = self.wait_in_thread("/api/wait?after=handled&timeout=3&watcher=other")
        r = self.run_script("watch.sh", str(self.dir))
        self.assertEqual(r.returncode, 3)
        self.assertIn("holds this toy's lease: session other,", r.stderr)
        t.join(TIMEOUT)

    def test_no_env_file_names_the_control_script(self):
        r = self.run_script("watch.sh", str(self.tmp))
        self.assertEqual(r.returncode, 2)
        self.assertIn("run toy.sh ensure-running first", r.stderr)

    def test_wake_applies_then_rearms(self):
        self.hub.append("next")
        r = self.run_script("wake.sh", str(self.dir))
        self.assertEqual(r.returncode, 0, r.stderr)
        applied = (self.dir / "applied").read_text().split()
        self.assertEqual(applied[:3], ["--dir", str(self.dir), "apply"])
        self.assertEqual(applied[-1], f"{self.dir}/ops.json")
        self.assertEqual(json.loads(r.stdout)["events"][0]["text"], "next")

    def test_a_failed_apply_does_not_rearm(self):
        r = self.run_script("wake.sh", str(self.dir), env={"TOY_RC": "1"})
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout, "")


if __name__ == "__main__":
    unittest.main()

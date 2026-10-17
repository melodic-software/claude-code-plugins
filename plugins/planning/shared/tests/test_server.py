"""server.py: listeners, auth classes, Host checks, headers, caps, errors and the snapshot.

Expected values come from the Design's Contracts ("Listeners", "Auth classes", "Guest listener
routes", "Control listener", "Errors", "Body caps and limits") and the planning amendments
(anonymous view, CF-Connecting-IP only, tokens from 0600 files, results wait for Publish), never
from running the server.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import socket
import stat
import statistics
import sys
import time
import unittest
from unittest import mock

from support import FAKE, FIXTURES, WINDOWS, call, tmpdir, wait_for

import detached
import server
import session
import tunnel

PAGE_CSP = "default-src 'self'; img-src 'self' data:; frame-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
SECURITY = {"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY", "Referrer-Policy": "no-referrer"}
HTML_ASSET_CSP = "sandbox allow-scripts; default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; font-src data:; connect-src 'none'"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 16


def raw_exchange(port, data, *, wait=5.0):
    """Send raw bytes and read until the server closes or `wait` passes: (bytes read, closed)."""
    with socket.create_connection(("127.0.0.1", port), timeout=wait) as s:
        s.sendall(data)
        got, closed = b"", False
        deadline = time.monotonic() + wait
        while time.monotonic() < deadline:
            s.settimeout(max(0.05, deadline - time.monotonic()))
            try:
                chunk = s.recv(65536)
            except TimeoutError:
                break
            except ConnectionResetError:
                closed = True
                break
            if not chunk:
                closed = True
                break
            got += chunk
        return got, closed


def status_and_headers(raw):
    head = raw.split(b"\r\n\r\n", 1)[0].decode("latin-1").split("\r\n")
    return int(head[0].split()[1]), dict(line.split(": ", 1) for line in head[1:] if ": " in line)


def text_q(qid):
    return {"id": qid, "text": f"Question {qid}?", "alternatives": [], "dependsOn": [], "purpose": "decide", "format": {"kind": "text"}}


class ServerCase(unittest.TestCase):
    def setUp(self):
        self.d = tmpdir(self)
        self.app = server.App(self.d, watch_tunnel=False)
        self.app.serve()
        self.addCleanup(self.app.shutdown)
        self.port = self.app.guest_port
        self.owner = {"X-Owner-Token": self.app.secrets["owner"]}

    # -- helpers -----------------------------------------------------------------------------

    def get(self, path, headers=None):
        return call(self.port, "GET", path, headers=headers)

    def post(self, path, body=None, headers=None):
        return call(self.port, "POST", path, {} if body is None else body, headers)

    def join(self, name, ip=None):
        h = {"CF-Connecting-IP": ip} if ip else {}
        code, _, out = self.post("/api/join", {"name": name, "device": "computer"}, h)
        self.assertEqual(code, 200, out)
        return out["pid"], {"X-Session-Secret": out["secret"]}

    def ops(self, *ops):
        s = self.app.hub
        return call(self.app.control_port, "POST", "/api/ops", {"ops": list(ops)}, {"X-Shared-Token": s.token})

    def open_round(self, *qids):
        code, _, out = self.ops({"op": "open-round", "questions": [text_q(q) for q in qids]})
        self.assertEqual(code, 200, out)

    def leader(self, pid):
        code, _, out = self.post("/api/person/role", {"pid": pid, "role": "leader"}, self.owner)
        self.assertEqual(code, 200, out)



class TestAuthClasses(ServerCase):
    def setUp(self):
        super().setUp()
        self.open_round("Q1")
        self.guest_pid, self.guest = self.join("Ann")
        lead_pid, self.lead = self.join("Lee")
        self.leader(lead_pid)

    def test_person_routes_refuse_a_request_with_no_identity(self):
        for path, (auth, _) in server.ROUTES.items():
            if auth == "public":
                continue
            with self.subTest(path=path):
                code, _, out = self.post(path, {})
                want = (403, "owner-only") if auth == "owner" else (401, "unknown-session")
                self.assertEqual((code, out["error"]), want)

    def test_owner_routes_refuse_a_leader(self):
        for path, (auth, _) in server.ROUTES.items():
            if auth == "owner":
                with self.subTest(path=path):
                    code, _, out = self.post(path, {}, self.lead)
                    self.assertEqual((code, out["error"]), (403, "owner-only"))

    def test_moderator_routes_refuse_a_guest(self):
        bodies = {
            "/api/lock": {"qid": "Q1"},
            "/api/unlock": {"qid": "Q1"},
            "/api/suggestion/act": {"qid": "Q1", "id": "S1", "action": "use"},
            "/api/lock/edit": {"qid": "Q1", "text": "Edited"},
            "/api/review/clear": {"qid": "Q1"},
            "/api/proposal/act": {"id": "P1", "action": "park"},
            "/api/chat/propose": {"id": "M1"},
            "/api/round/ready": {"on": True},
        }
        self.assertEqual(sorted(bodies), sorted(p for p, (a, _) in server.ROUTES.items() if a == "moderator"))
        for path, body in bodies.items():
            with self.subTest(path=path):
                code, _, out = self.post(path, body, self.guest)
                self.assertEqual((code, out["error"]), (403, "moderator-only"))

    def test_a_leader_may_use_a_moderator_route(self):
        code, _, out = self.post("/api/round/ready", {"on": True}, self.lead)
        self.assertEqual((code, out["ready"]), (200, True))

    def test_the_owner_token_acts_as_host_on_owner_routes(self):
        code, _, out = self.post("/api/session/title", {"title": "Checkout"}, self.owner)
        self.assertEqual((code, out["title"]), (200, "Checkout"))

    def test_a_pid_or_leader_id_in_the_body_is_ignored(self):
        other_pid, _ = self.join("Bo")
        code, _, out = self.post("/api/answer", {"qid": "Q1", "text": "Mine", "device": "computer", "view": "focus", "pid": other_pid}, self.guest)
        self.assertEqual(code, 200, out)
        cards = self.app.session.state["cards"]["Q1"]
        self.assertEqual([c["pid"] for c in cards if c["kind"] == "person"], [self.guest_pid])
        code, _, out = self.post("/api/lock", {"qid": "Q1", "by": "host", "pid": "host", "role": "owner"}, self.guest)
        self.assertEqual((code, out["error"]), (403, "moderator-only"))

    def test_a_pid_sent_as_a_secret_is_not_a_credential(self):
        code, _, out = self.post("/api/heartbeat", {}, {"X-Session-Secret": self.guest_pid})
        self.assertEqual((code, out["error"]), (401, "unknown-session"))

    def test_a_guest_secret_sent_as_the_owner_token_is_refused(self):
        code, _, out = self.post("/api/session/title", {"title": "X"}, {"X-Owner-Token": self.guest["X-Session-Secret"]})
        self.assertEqual((code, out["error"]), (401, "unknown-session"))

    def test_join_is_public(self):
        code, _, out = self.post("/api/join", {"name": "Cy", "device": "phone"})
        self.assertEqual(code, 200)
        self.assertEqual(sorted(out), ["name", "ok", "pid", "secret"])


class TestHostAndOrigin(ServerCase):
    def test_an_unknown_host_is_refused(self):
        code, _, out = self.get("/api/state", {"Host": "evil.example"})
        self.assertEqual((code, out["error"]), (403, "bad-host"))

    def test_a_request_with_no_host_is_refused_before_any_tunnel_exists(self):
        code, _, out = self.get("/api/state", {"Host": ""})
        self.assertEqual((code, out["error"]), (403, "bad-host"))

    def test_localhost_on_the_guest_port_is_served(self):
        code, _, _ = self.get("/api/state", {"Host": f"localhost:{self.port}"})
        self.assertEqual(code, 200)

    def test_the_control_port_is_not_a_guest_host(self):
        code, _, _ = self.get("/api/state", {"Host": f"127.0.0.1:{self.app.control_port}"})
        self.assertEqual(code, 403)

    def test_a_cross_origin_post_is_refused(self):
        code, _, out = self.post("/api/join", {"name": "X"}, {"Origin": "https://evil.example"})
        self.assertEqual((code, out["error"]), (403, "bad-host"))

    def test_a_refused_post_does_nothing_and_answers_once(self):
        cases = {"bad-host": ({"Host": "evil.example"}, server.Bucket(1.0, 100)), "slow-down": ({}, server.Bucket(0.0, 0))}
        for error, (headers, bucket) in cases.items():
            with self.subTest(error=error):
                self.app.bucket = bucket
                body = json.dumps({"name": f"Via {error}"}).encode()
                head = {"Host": f"127.0.0.1:{self.port}", "Content-Type": "application/json", "Content-Length": str(len(body)), **headers}
                req = "POST /api/join HTTP/1.1\r\n" + "".join(f"{k}: {v}\r\n" for k, v in head.items()) + "\r\n"
                got, _ = raw_exchange(self.port, req.encode() + body)
                self.assertEqual(got.count(b"HTTP/1.1 "), 1)
                self.assertNotIn(f"Via {error}", [p["name"] for p in self.app.session.state["people"].values()])

    def test_the_tunnel_host_is_served_once_the_tunnel_record_names_it(self):
        host = "fake-0123456789ab.trycloudflare.com"
        code, _, _ = self.get("/api/state", {"Host": host})
        self.assertEqual(code, 403)
        proc = detached.spawn(([sys.executable, FAKE] if FAKE.endswith(".py") else [FAKE]) + ["tunnel", "--no-autoupdate", "--url", "x"], log=self.d / "f.log")
        self.addCleanup(lambda: (proc.kill(), proc.wait()))
        wait_for(lambda: tunnel.URL.search((self.d / "f.log").read_text(encoding="utf-8")))
        detached.write_private(
            self.d / tunnel.RECORD, json.dumps({"pid": proc.pid, "url": f"https://{host}", "port": self.port, "marker": "python" if WINDOWS else "cloudflared", "startedAt": 0})
        )
        self.app._last_sync = 0
        code, _, _ = self.get("/api/state", {"Host": host, "Origin": f"https://{host}"})
        self.assertEqual(code, 200)
        self.assertEqual(self.app.session.state["session"]["share"]["url"], f"https://{host}")
        code, _, _ = self.get("/api/state", {"Host": host, "Origin": f"http://{host}"})
        self.assertEqual(code, 403)


class TestHeadersAndCaps(ServerCase):
    def test_every_json_answer_carries_the_security_headers(self):
        for path in ("/api/state", "/api/nope"):
            with self.subTest(path=path):
                _, headers, _ = self.get(path)
                self.assertEqual({k: headers.get(k) for k in SECURITY}, SECURITY)

    def test_the_page_carries_the_page_policy(self):
        code, headers, body = self.get("/")
        self.assertEqual(code, 200)
        self.assertEqual(headers["Content-Security-Policy"], PAGE_CSP)
        self.assertTrue(headers["Content-Type"].startswith("text/html"))
        self.assertIn(b"<html", body)

    def test_only_allowlisted_files_are_served(self):
        for path in ("/server.py", "/state.json", "/../state.json", "/.shared-secrets.json", "/web/index.html"):
            with self.subTest(path=path):
                code, _, out = self.get(path)
                self.assertEqual((code, out["error"]), (404, "not-found"))

    def test_assets_are_sandboxed_and_inline(self):
        (self.d / "assets").mkdir()
        (self.d / "assets" / "0123456789abcdef.png").write_bytes(PNG)
        (self.d / "assets" / "fedcba9876543210.html").write_text("<html></html>", encoding="utf-8")
        code, h, body = self.get("/assets/0123456789abcdef.png")
        self.assertEqual((code, h["Content-Type"], h["Content-Security-Policy"], h["Content-Disposition"], body), (200, "image/png", "sandbox", "inline", PNG))
        _, h, _ = self.get("/assets/fedcba9876543210.html")
        self.assertEqual(h["Content-Security-Policy"], HTML_ASSET_CSP)
        self.assertNotIn("allow-same-origin", h["Content-Security-Policy"])
        code, _, _ = self.get("/assets/0123456789abcdef.exe")
        self.assertEqual(code, 404)

    def test_a_non_json_post_is_415(self):
        code, _, out = call(self.port, "POST", "/api/join", raw=b"name=x", headers={"Content-Type": "application/x-www-form-urlencoded"})
        self.assertEqual((code, out["error"]), (415, "json-required"))

    def test_a_body_over_the_cap_is_413_before_it_is_read(self):
        code, _, out = call(self.port, "POST", "/api/join", raw=b"", headers={"Content-Type": "application/json", "Content-Length": str(session.BODY_MAX + 1)})
        self.assertEqual((code, out["error"], out["max"]), (413, "body-too-large", 32 * 1024))

    def test_bad_json_is_400(self):
        code, _, out = call(self.port, "POST", "/api/join", raw=b"{nope", headers={"Content-Type": "application/json"})
        self.assertEqual((code, out["error"]), (400, "bad-json"))
        code, _, out = call(self.port, "POST", "/api/join", raw=b"[1]", headers={"Content-Type": "application/json"})
        self.assertEqual((code, out["error"]), (400, "bad-json"))

    def test_a_preflight_is_never_answered_with_cors(self):
        code, h, _ = call(self.port, "OPTIONS", "/api/join", headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "POST"})
        self.assertNotEqual(code, 200)
        self.assertFalse([k for k in h if k.lower().startswith("access-control-")])

    def test_unknown_routes_and_later_phase_routes_are_404(self):
        for path in ("/api/upload/offer", "/api/upload/act", "/api/upload/chunk", "/api/nope"):
            with self.subTest(path=path):
                code, _, out = self.post(path, {})
                self.assertEqual((code, out["error"]), (404, "not-found"))
        code, _, _ = self.get("/proto/Q1")
        self.assertEqual(code, 404)

    def test_domain_errors_keep_their_code_and_status(self):
        _, guest = self.join("Ann")
        code, _, out = self.post("/api/answer", {"qid": "Q9", "text": "x", "device": "computer", "view": "focus"}, guest)
        self.assertEqual((code, out["error"]), (404, "no-such-question"))
        self.assertIn("message", out)

    def test_the_address_limit_answers_429(self):
        self.app.bucket = server.Bucket(0.0, 3)
        codes = [self.get("/api/state", {"CF-Connecting-IP": "203.0.113.5"})[0] for _ in range(4)]
        self.assertEqual(codes, [200, 200, 200, 429])
        self.assertEqual(self.get("/api/state", {"CF-Connecting-IP": "203.0.113.6"})[0], 200)


class TestFormatsAndPresenceRoutes(ServerCase):
    """Phase 4b over HTTP: the pick bodies for multi, scale and rank, /api/disagree, and the
    heartbeat's visible and lastInput fields (amendments "Reactions and formats", "Presence")."""

    def setUp(self):
        super().setUp()
        opts = [{"id": f"opt-{i}", "label": label} for i, label in enumerate(("Speed", "Trust", "Fewer fields"), 1)]
        questions = [
            {"id": "Q1", "text": "Which?", "alternatives": [], "dependsOn": [], "purpose": "decide", "format": {"kind": "multi", "options": opts}},
            {"id": "Q2", "text": "How often?", "alternatives": [], "dependsOn": [], "purpose": "poll", "format": {"kind": "scale", "min": 1, "max": 5, "labels": {"min": "Never", "max": "Always"}}},
            {"id": "Q3", "text": "Order them.", "alternatives": [], "dependsOn": [], "purpose": "decide", "format": {"kind": "rank", "options": opts}},
        ]
        code, _, out = self.ops({"op": "open-round", "questions": questions})
        self.assertEqual(code, 200, out)
        self.ann_pid, self.ann = self.join("Ann")

    def pick(self, body):
        return self.post("/api/pick", {"device": "computer", "view": "focus", **body}, self.ann)

    def test_multi_scale_and_rank_picks_travel_in_their_own_fields(self):
        self.assertEqual(self.pick({"qid": "Q1", "options": ["opt-2", "other"], "other": "Price"})[2], {"ok": True, "picks": ["opt-2", "other"]})
        time.sleep(session.WRITE_INTERVAL)
        self.assertEqual(self.pick({"qid": "Q2", "value": 4})[2], {"ok": True, "value": 4})
        time.sleep(session.WRITE_INTERVAL)
        self.assertEqual(self.pick({"qid": "Q3", "order": ["opt-3", "opt-1", "opt-2"]})[2], {"ok": True, "order": ["opt-3", "opt-1", "opt-2"]})
        time.sleep(session.WRITE_INTERVAL)
        code, _, out = self.pick({"qid": "Q3", "order": ["opt-3"]})
        self.assertEqual((code, out["error"], out["field"]), (400, "bad-field", "order"))

    def test_disagree_is_a_throttled_person_route_with_the_default_body_cap(self):
        body = {"qid": "Q3", "card": "o:opt-1", "reason": "Speed is not the goal."}
        self.assertEqual(self.post("/api/disagree", body)[2]["error"], "unknown-session")
        self.assertEqual(self.post("/api/disagree", body, self.ann)[:3:2], (200, {"ok": True, "disagree": True}))
        code, _, out = self.post("/api/disagree", body, self.ann)
        self.assertEqual((code, out["error"]), (429, "slow-down"))
        code, _, out = call(self.port, "POST", "/api/disagree", raw=b"", headers={**self.ann, "Content-Type": "application/json", "Content-Length": str(session.BODY_MAX + 1)})
        self.assertEqual((code, out["error"]), (413, "body-too-large"))

    def test_a_hidden_page_shows_away_in_the_snapshot(self):
        code, _, out = self.post("/api/heartbeat", {"q": "Q1", "visible": False, "lastInput": 12}, self.ann)
        self.assertEqual(code, 200, out)
        _, _, snap = self.get("/api/state", self.owner)
        (mine,) = [p for p in snap["presence"] if p["pid"] == self.ann_pid]
        self.assertEqual((mine["state"], mine["q"]), ("away", "Q1"))
        code, _, out = self.post("/api/heartbeat", {"lastInput": "soon"}, self.ann)
        self.assertEqual((code, out["error"], out["field"]), (400, "bad-field", "lastInput"))


class TestJoinLimit(ServerCase):
    def test_the_join_limit_keys_on_cf_connecting_ip_and_ignores_x_forwarded_for(self):
        for i in range(session.JOINS_PER_WINDOW):
            self.join(f"P{i}", ip="198.51.100.7")
        code, _, out = self.post("/api/join", {"name": "Late"}, {"CF-Connecting-IP": "198.51.100.7", "X-Forwarded-For": "192.0.2.1"})
        self.assertEqual((code, out["error"]), (429, "join-rate"))
        code, _, _ = self.post("/api/join", {"name": "Other"}, {"CF-Connecting-IP": "198.51.100.8"})
        self.assertEqual(code, 200)


class TestRateKeys(ServerCase):
    def test_ipv6_addresses_in_one_64_share_one_limit(self):
        self.app.bucket = server.Bucket(0.0, 2)
        same_64 = ["2001:db8:1:2::1", "2001:db8:1:2:ffff:ffff:ffff:fffe", "2001:db8:1:2:aaaa::1"]
        codes = [self.get("/api/state", {"CF-Connecting-IP": ip})[0] for ip in same_64]
        self.assertEqual(codes, [200, 200, 429])
        self.assertEqual(self.get("/api/state", {"CF-Connecting-IP": "2001:db8:1:3::1"})[0], 200)

    def test_one_take_stays_fast_and_the_bucket_bounded_past_20000_addresses(self):
        # Judgment: an O(1) take costs microseconds; a scan of 10000 remembered addresses costs about
        # a millisecond, so 0.1 ms at the 99th percentile separates the two with room for a slow host.
        bucket = server.Bucket(session.RATE_PER_SECOND, session.RATE_BURST)
        took = []
        for i in range(20000):
            t0 = time.perf_counter()
            bucket.take(f"198.18.{i // 256}.{i % 256}")
            took.append(time.perf_counter() - t0)
        self.assertLess(statistics.quantiles(took, n=100)[-1], 0.0001)
        self.assertLessEqual(len(bucket.tokens), session.RATE_KEYS)


class TestRawRequests(ServerCase):
    def request(self, line, *headers, body=b""):
        head = [line, f"Host: 127.0.0.1:{self.port}", *headers]
        return raw_exchange(self.port, ("\r\n".join(head) + "\r\n\r\n").encode("latin-1") + body)

    def test_a_get_with_a_body_is_400_and_the_connection_closes(self):
        for header in ("Content-Length: 5", "Transfer-Encoding: chunked"):
            with self.subTest(header=header):
                got, closed = self.request("GET /api/state HTTP/1.1", header, body=b"GET /api/state HTTP/1.1\r\n\r\n")
                self.assertEqual(status_and_headers(got)[0], 400)
                self.assertEqual(got.count(b"HTTP/1.1 "), 1, "the body was read as a second request")
                self.assertTrue(closed)

    def test_a_body_that_trickles_past_the_deadline_is_408(self):
        with mock.patch.object(session, "BODY_SECONDS", 1.0):
            t0 = time.monotonic()
            got, closed = self.request("POST /api/join HTTP/1.1", "Content-Type: application/json", "Content-Length: 100", body=b'{"name"')
            took = time.monotonic() - t0
        self.assertEqual(status_and_headers(got)[0], 408)
        self.assertTrue(closed)
        self.assertLess(took, 4.0)

    def test_http_servers_own_refusals_carry_the_security_headers(self):
        cases = {501: "BREW /api/state HTTP/1.1", 414: "GET /" + "a" * 70000 + " HTTP/1.1"}
        for code, line in cases.items():
            with self.subTest(code=code):
                got, _ = self.request(line)
                status, headers = status_and_headers(got)
                self.assertEqual(status, code)
                self.assertEqual({k: headers.get(k) for k in SECURITY}, SECURITY)
                self.assertTrue(headers["Content-Type"].startswith("application/json"))

    def test_the_log_escapes_control_characters_in_the_path(self):
        self.request("GET /nope\x1b[2J\x07 HTTP/1.1")
        for h in self.app.log.handlers:
            h.flush()
        log = (self.d / "server.log").read_text(encoding="utf-8")
        self.assertIn("/nope\\x1b[2J\\x07", log)
        self.assertNotIn("\x1b", log)

    def test_the_log_escapes_control_characters_in_the_method(self):
        got, _ = self.request("BR\x1b[2JEW / HTTP/1.1")
        self.assertEqual(status_and_headers(got)[0], 501)
        for h in self.app.log.handlers:
            h.flush()
        log = (self.d / "server.log").read_text(encoding="utf-8")
        self.assertIn("BR\\x1b[2JEW", log)
        self.assertNotIn("\x1b", log)


class TestBusy(unittest.TestCase):
    def test_a_connection_past_the_handler_cap_is_answered_503(self):
        d = tmpdir(self)
        with mock.patch.object(session, "MAX_HANDLERS", 2):
            app = server.App(d, watch_tunnel=False)
        app.serve()
        self.addCleanup(app.shutdown)
        idle = [socket.create_connection(("127.0.0.1", app.guest_port), timeout=5) for _ in range(2)]
        wait_for(lambda: app.guest.slots._value == 0, seconds=5)
        code, headers, out = call(app.guest_port, "GET", "/api/state")
        self.assertEqual((code, out["error"]), (503, "busy"))
        self.assertEqual({k: headers.get(k) for k in SECURITY}, SECURITY)
        for s in idle:
            s.close()
        self.assertTrue(wait_for(lambda: call(app.guest_port, "GET", "/api/state")[0] == 200, seconds=10))


class TestOwnerRotation(unittest.TestCase):
    def test_the_secrets_file_holds_the_new_token_before_the_hash_commits(self):
        d = tmpdir(self)
        app = server.App(d, watch_tunnel=False)
        app.serve()
        self.addCleanup(app.shutdown)
        seen = []
        real = app.session._commit

        def commit():
            seen.append(json.loads((d / server.SECRETS).read_text(encoding="utf-8"))["owner"])
            real()

        with mock.patch.object(app.session, "_commit", side_effect=commit):
            code, _, out = call(app.guest_port, "POST", "/api/link/owner", {}, {"X-Owner-Token": app.secrets["owner"]})
        self.assertEqual(code, 200)
        self.assertEqual(seen, [out["token"]])

    def test_a_restart_refuses_an_owner_token_older_than_the_last_rotation(self):
        d = tmpdir(self)
        app = server.App(d, watch_tunnel=False)
        app.serve()
        before = dict(app.secrets)
        time.sleep(0.01)
        code, _, _ = call(app.guest_port, "POST", "/api/link/owner", {}, {"X-Owner-Token": before["owner"]})
        app.shutdown()
        self.assertEqual(code, 200)
        detached.write_private(d / server.SECRETS, json.dumps(before) + "\n")  # the file a crash before the fix left
        with self.assertRaisesRegex(server.StartRefused, "predates"):
            server.App(d, watch_tunnel=False)
        self.assertNotEqual(json.loads((d / "state.json").read_text(encoding="utf-8"))["credentials"]["owner"]["tokenHash"], session.sha256(before["owner"]))

    def rotated(self):
        """A data folder whose owner link was rotated once: (folder, secrets before, token after)."""
        d = tmpdir(self)
        app = server.App(d, watch_tunnel=False)
        app.serve()
        before = dict(app.secrets)
        time.sleep(0.01)
        code, _, out = call(app.guest_port, "POST", "/api/link/owner", {}, {"X-Owner-Token": before["owner"]})
        app.shutdown()
        self.assertEqual(code, 200)
        return d, before, out["token"]

    def start(self, d):
        app = server.App(d, watch_tunnel=False)
        self.addCleanup(app.shutdown)
        for h in app.log.handlers:
            h.flush()
        state = json.loads((d / "state.json").read_text(encoding="utf-8"))
        return app, state["credentials"]["owner"], (d / "server.log").read_text(encoding="utf-8")

    def test_an_undated_token_restored_after_a_rotation_is_replaced_by_a_fresh_one(self):
        d, before, after = self.rotated()
        detached.write_private(d / server.SECRETS, json.dumps({"control": before["control"], "owner": before["owner"]}) + "\n")
        app, owner, log = self.start(d)
        self.assertNotIn(app.secrets["owner"], (before["owner"], after))
        self.assertEqual(owner["tokenHash"], session.sha256(app.secrets["owner"]))
        self.assertEqual(json.loads((d / server.SECRETS).read_text(encoding="utf-8"))["owner"], app.secrets["owner"])
        self.assertIn("fresh owner link", log)

    def test_an_undated_copy_of_the_current_token_keeps_the_owner_link(self):
        d, before, after = self.rotated()
        detached.write_private(d / server.SECRETS, json.dumps({"control": before["control"], "owner": after}) + "\n")
        app, owner, _ = self.start(d)
        self.assertEqual(app.secrets["owner"], after)
        self.assertEqual(owner["tokenHash"], session.sha256(after))

    def test_a_rotation_time_ahead_of_the_clock_is_set_to_now_so_a_fresh_owner_link_works(self):
        d = tmpdir(self)
        server.App(d, watch_tunnel=False).shutdown()
        state = json.loads((d / "state.json").read_text(encoding="utf-8"))
        state["credentials"]["owner"]["rotatedAt"] = time.time() + 86400
        detached.write_private(d / "state.json", json.dumps(state) + "\n")
        (d / server.SECRETS).unlink()  # the documented remedy
        app, owner, log = self.start(d)
        self.assertLessEqual(owner["rotatedAt"], time.time())
        self.assertEqual(owner["tokenHash"], session.sha256(app.secrets["owner"]))
        self.assertIn("ahead of the clock", log)

    def test_after_a_clock_rollback_a_dated_token_that_is_not_current_gets_a_fresh_link(self):
        d = tmpdir(self)
        server.App(d, watch_tunnel=False).shutdown()
        now = time.time()
        state = json.loads((d / "state.json").read_text(encoding="utf-8"))
        state["credentials"]["owner"]["rotatedAt"] = now + 1000
        detached.write_private(d / "state.json", json.dumps(state) + "\n")
        old = "a-token-from-before-the-rollback-0000000000000"
        held = json.loads((d / server.SECRETS).read_text(encoding="utf-8"))
        detached.write_private(d / server.SECRETS, json.dumps({**held, "owner": old, "ownerAt": now + 500}) + "\n")
        app, owner, log = self.start(d)
        self.assertNotEqual(app.secrets["owner"], old)
        self.assertEqual(owner["tokenHash"], session.sha256(app.secrets["owner"]))
        app.serve()
        code, _, _ = call(app.guest_port, "GET", "/api/state", headers={"X-Owner-Token": old})
        self.assertEqual(code, 401)
        self.assertIn("clock was rolled back", log)

    def test_a_start_that_dies_between_the_clamp_and_the_secrets_write_leaves_no_usable_stale_token(self):
        d = tmpdir(self)
        server.App(d, watch_tunnel=False).shutdown()
        now = time.time()
        state = json.loads((d / "state.json").read_text(encoding="utf-8"))
        state["credentials"]["owner"]["rotatedAt"] = now + 1000
        detached.write_private(d / "state.json", json.dumps(state) + "\n")
        old = "a-token-from-before-the-rollback-0000000000000"
        held = json.loads((d / server.SECRETS).read_text(encoding="utf-8"))
        detached.write_private(d / server.SECRETS, json.dumps({**held, "owner": old, "ownerAt": now + 500}) + "\n")
        write = detached.write_private

        def crash_at_the_secrets_file(path, text):
            if os.path.basename(path) == server.SECRETS:
                raise SystemExit("the server died here")
            return write(path, text)

        with mock.patch.object(server.detached, "write_private", crash_at_the_secrets_file), self.assertRaises(SystemExit):
            server.App(d, watch_tunnel=False)
        self.assertLessEqual(json.loads((d / "state.json").read_text(encoding="utf-8"))["credentials"]["owner"]["rotatedAt"], time.time())  # the clamp landed
        app, owner, log = self.start(d)
        self.assertNotEqual(app.secrets["owner"], old)
        self.assertEqual(owner["tokenHash"], session.sha256(app.secrets["owner"]))
        app.serve()
        code, _, _ = call(app.guest_port, "GET", "/api/state", headers={"X-Owner-Token": old})
        self.assertEqual(code, 401)

    def test_after_a_clock_rollback_the_current_token_keeps_the_owner_link(self):
        d = tmpdir(self)
        first = server.App(d, watch_tunnel=False)
        token = first.secrets["owner"]
        first.shutdown()
        state = json.loads((d / "state.json").read_text(encoding="utf-8"))
        state["credentials"]["owner"]["rotatedAt"] = time.time() + 1000
        detached.write_private(d / "state.json", json.dumps(state) + "\n")
        app, owner, _ = self.start(d)
        self.assertEqual((app.secrets["owner"], owner["tokenHash"]), (token, session.sha256(token)))


class TestDataFolderRule(unittest.TestCase):
    """Windows keeps the data folder private only under the user profile; WSL's DrvFs ignores file
    modes unless mounted with metadata (Brief: runs on Windows, macOS and Linux)."""

    def problem_on_windows(self, path, profile):
        with mock.patch.object(detached, "WINDOWS", True), mock.patch.dict(os.environ, {"USERPROFILE": profile}):
            return detached.data_dir_problem(path)

    def test_windows_refuses_a_folder_outside_the_profile(self):
        self.assertIn("outside your user profile", self.problem_on_windows(r"D:\shared\po", r"C:\Users\kim"))
        self.assertIn("outside your user profile", self.problem_on_windows(r"C:\Users\kimberly\po", r"C:\Users\kim"))
        self.assertIsNone(self.problem_on_windows(r"c:\users\KIM\.claude\memory\shared\po", r"C:\Users\kim"))

    @unittest.skipIf(WINDOWS, "WSL paths")
    def test_wsl_refuses_a_drvfs_folder_mounted_without_metadata(self):
        plain = [("/", "ext4", "rw,relatime"), ("/mnt/c", "9p", "rw,noatime,dirsync,aname=drvfs;path=C:\\;uid=1000;gid=1000;symlinkroot=/mnt/,mmap,access=client")]
        meta = [("/", "ext4", "rw,relatime"), ("/mnt/c", "9p", "rw,noatime,dirsync,aname=drvfs;path=C:\\;uid=1000;gid=1000;metadata;symlinkroot=/mnt/,mmap")]
        cases = [(plain, "/mnt/c/Users/kim/po", True), (plain, "/home/kim/po", False), (meta, "/mnt/c/Users/kim/po", False)]
        for mounts, path, refused in cases:
            with self.subTest(path=path, metadata=mounts is meta):
                with mock.patch.object(detached, "WINDOWS", False), mock.patch.object(detached, "_is_wsl", return_value=True), mock.patch.object(detached, "_mount_table", return_value=mounts):
                    got = detached.data_dir_problem(path)
                self.assertEqual(got is not None, refused, got)
                if refused:
                    self.assertIn("without metadata", got)

    def test_the_server_refuses_to_start_there_and_exits_1(self):
        d = tmpdir(self) / "po"
        err = io.StringIO()
        with mock.patch.object(detached, "data_dir_problem", return_value="the data folder is outside your user profile"), contextlib.redirect_stderr(err):
            code = server.main(["--dir", str(d)])
        self.assertEqual(code, 1)
        self.assertIn("outside your user profile", err.getvalue())
        self.assertFalse(d.exists())


class TestSnapshot(ServerCase):
    def test_the_anonymous_view_has_only_the_four_keys(self):
        code, _, out = self.get("/api/state")
        self.assertEqual(code, 200)
        self.assertEqual(sorted(out), ["ended", "joinNeedsKey", "schemaVersion", "title"])

    def test_a_person_snapshot_carries_the_reload_trigger(self):
        _, guest = self.join("Ann")
        code, h, out = self.get("/api/state", guest)
        self.assertEqual(code, 200)
        self.assertEqual(out["schemaVersion"], 1)
        self.assertIsInstance(out["rev"], int)
        self.assertEqual(out["build"], server.build_hash())
        self.assertEqual(h["X-Shared-Build"], out["build"])
        self.assertNotIn("credentials", out)
        self.assertNotIn("log", out)

    def test_the_build_hash_follows_the_web_files(self):
        before = server.build_hash()
        with mock.patch.object(server, "WEB", self.d):
            self.assertNotEqual(server.build_hash(), before)

    def test_a_removed_person_reads_nothing(self):
        pid, guest = self.join("Ann")
        self.post("/api/person/remove", {"pid": pid, "on": True}, self.owner)
        code, _, out = self.get("/api/state", guest)
        self.assertEqual((code, sorted(out)), (403, ["error", "message"]))
        self.assertEqual(out["error"], "removed")

    def test_the_owner_link_before_a_rotation_reads_nothing(self):
        code, _, out = self.post("/api/link/owner", {}, self.owner)
        self.assertEqual(code, 200)
        code, _, out2 = self.get("/api/state", self.owner)
        self.assertEqual((code, out2["error"]), (401, "unknown-session"))
        code, _, _ = self.get("/api/state", {"X-Owner-Token": out["token"]})
        self.assertEqual(code, 200)
        self.assertIn(f"#owner={out['token']}", (self.d / server.OWNER_LINK).read_text(encoding="utf-8"))
        self.assertEqual(json.loads((self.d / server.SECRETS).read_text(encoding="utf-8"))["owner"], out["token"])

    def test_a_guest_link_from_before_a_rotation_admits_no_one(self):
        code, _, out = self.post("/api/link/guest", {}, self.owner)
        self.assertEqual(code, 200)
        self.assertTrue(self.get("/api/state")[2]["joinNeedsKey"])
        code, _, err = self.post("/api/join", {"name": "Old link"})
        self.assertEqual((code, err["error"]), (403, "bad-guest-key"))
        code, _, _ = self.post("/api/join", {"name": "New link", "key": out["guestKey"]})
        self.assertEqual(code, 200)

    def test_an_unchanged_snapshot_answers_304(self):
        _, guest = self.join("Ann")
        _, h, _ = self.get("/api/state", guest)
        code, h2, body = self.get("/api/state", {**guest, "If-None-Match": h["ETag"]})
        self.assertEqual((code, h2["ETag"], body), (304, h["ETag"], None))
        self.post("/api/rename", {"name": "Annie"}, guest)
        code, _, out = self.get("/api/state", {**guest, "If-None-Match": h["ETag"]})
        self.assertEqual((code, out["me"]["name"]), (200, "Annie"))

    def test_the_owner_sees_the_guest_link_and_whether_it_changed(self):
        self.app.session.set_share("https://one-a.trycloudflare.com")
        self.app.session.set_share("https://two-b.trycloudflare.com")
        _, _, out = self.get("/api/state", self.owner)
        self.assertEqual(out["share"]["url"], "https://two-b.trycloudflare.com")
        self.assertIn("changedAt", out["share"])
        _, guest = self.join("Ann")
        self.assertNotIn("share", self.get("/api/state", guest)[2])

    def test_a_result_stays_hidden_from_guests_until_the_owner_publishes_it(self):
        self.open_round("Q1")
        _, guest = self.join("Ann")
        code, _, req = self.post("/api/request", {"qid": "Q1", "kind": "research", "text": "Find prior art"}, guest)
        self.assertEqual(code, 200, req)
        self.post("/api/request/act", {"action": "run", "ids": [req["id"]]}, self.owner)
        result = {"op": "result", "qid": "Q1", "request": req["id"], "kind": "research", "used": [], "why": "Web search.", "summary": "Two products do this.", "sources": [], "report": "Details."}
        code, _, out = self.ops(result)
        self.assertEqual(code, 200, out)
        rid = out["results"][0]["id"]
        self.assertEqual(self.get("/api/state", guest)[2]["results"].get("Q1", []), [])
        self.assertEqual([r["id"] for r in self.get("/api/state", self.owner)[2]["results"]["Q1"]], [rid])
        code, _, out = self.post("/api/request/act", {"id": req["id"], "action": "publish"}, self.owner)
        self.assertEqual(code, 200, out)
        self.assertEqual([r["id"] for r in self.get("/api/state", guest)[2]["results"]["Q1"]], [rid])

    def test_own_runner_self_requests_list_through_the_mine_route(self):
        self.open_round("Q1")
        _, guest = self.join("Ann")
        code, _, req = self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": "Explain", "runner": "self"}, guest)
        self.assertEqual(code, 200, req)
        code, _, out = self.get("/api/mine/requests?status=pending", guest)
        self.assertEqual((code, [r["id"] for r in out["requests"]]), (200, [req["id"]]))
        self.assertEqual(self.get("/api/mine/requests")[0], 401)


class TestSnapshotContract(unittest.TestCase):
    """The snapshot names the page's core.js reads, per .work/shared-interview-ui/snapshot-map.md
    (the page reads the prototype's names; core.js builds them from these). A key the server drops
    or renames fails here before it blanks part of the page."""

    TOP_ALL = {"schemaVersion", "rev", "build", "title", "goal", "ended", "serverTime", "settings", "rounds", "round", "questions", "cards", "locks"}
    TOP_ALL |= {"suggestions", "results", "chat", "people", "presence", "requestCounts", "proposals", "myRequests", "myMergeRequests", "me"}
    TOP_MODERATOR = {"share", "guestKey"}
    TOP_OWNER = {"requests", "mergeRequests", "removed", "cardDetails"}
    KEY = "Zk3yZk3yZk3y"  # the fixture's session.guestKey

    def setUp(self):
        self.d = tmpdir(self)
        self.app = server.App(self.d, watch_tunnel=False, initial_state=FIXTURES / "state-v1.json")
        self.app.serve()
        self.addCleanup(self.app.shutdown)
        self.port = self.app.guest_port
        self.owner = {"X-Owner-Token": self.app.secrets["owner"]}
        code, _, out = call(self.port, "POST", "/api/heartbeat", {"q": "Q1", "typing": False, "chatTyping": False}, self.owner)
        self.assertEqual(code, 200, out)

    def snap(self, headers):
        code, _, out = call(self.port, "GET", "/api/state?since=0", headers=headers)
        self.assertEqual(code, 200, out)
        return out

    def has(self, obj, keys, where):
        self.assertIsInstance(obj, dict, where)
        missing = sorted(set(keys) - set(obj))
        self.assertEqual(missing, [], f"{where} lacks {missing}")

    def test_snapshot_contract(self):
        s = self.snap(self.owner)
        self.has(s, self.TOP_ALL | self.TOP_MODERATOR | self.TOP_OWNER, "owner snapshot")
        self.has(s["settings"], ("voting", "signoff", "chat", "follow", "names", "digestNames", "uploads", "claudeTake", "theme"), "settings")
        self.has(s["round"], ("n", "status"), "round")
        self.has(s["rounds"][-1], ("n", "status"), "rounds[-1]")
        self.has(s["rounds"][-1]["status"]["ready"], ("by", "at"), "rounds[-1].status.ready")
        self.has(s["requestCounts"], ("open", "byQ"), "requestCounts")
        self.has(s["share"], ("url", "changedAt"), "share")

        qs = {q["id"]: q for q in s["questions"]}
        for q in qs.values():
            self.has(q, ("id", "text", "round", "dependsOn", "references", "format", "needsReview", "origin", "purpose", "alternatives"), f"question {q['id']}")
        self.has(qs["Q1"], ("recommendation", "basis", "lockedText"), "Q1, a text question with Claude's cards")
        self.has(qs["Q2"]["format"]["options"][0], ("id", "label", "image"), "a choice option")
        self.has(qs["Q3"]["format"], ("kind", "image", "rect"), "a confirm format")
        self.has(qs["Q4"]["format"]["variants"][0], ("id", "label"), "a prototype variant")
        self.has(qs["Q4"]["origin"], ("kind", "proposal", "by"), "a host-added question's origin")
        self.has(qs["Q3"]["origin"], ("kind", "proposal"), "a proposal question's origin")

        cards = [c for lst in s["cards"].values() for c in lst]
        kinds = {c["kind"]: c for c in cards}
        self.assertEqual(set(kinds), {"person", "claude", "option"})
        for c in cards:
            self.has(c, ("kind", "ref", "votes", "reactions"), f"card {c.get('ref')}")
        self.has(kinds["claude"], ("key",), "a Claude card")
        self.has(kinds["option"], ("option",), "an option card")
        person = next(c for c in s["cards"]["Q1"] if c["kind"] == "person")
        self.has(person, ("pid", "text", "at", "cites"), "a person card")
        self.has(next(c for c in s["cards"]["Q2"] if c["kind"] == "person"), ("pick", "late"), "a late pick")
        self.assertIn("device", next(c for c in s["cards"]["Q5"] if c["kind"] == "person"))
        self.has(s["cardDetails"]["Q1"][person["ref"]], ("view",), "cardDetails")

        self.has(s["locks"]["Q1"], ("at", "by", "source"), "a lock")
        self.has(s["locks"]["Q1"]["source"], ("kind", "card", "text"), "a card lock's source")
        self.has(s["locks"]["Q3"]["source"], ("kind", "text", "from"), "an edited lock's source")
        self.has(s["suggestions"]["Q1"][0], ("id", "pid", "text", "note", "at", "status", "votes"), "a suggestion")
        for p in s["proposals"]:
            self.has(p, ("id", "pid", "text", "at", "via", "status"), f"proposal {p['id']}")
        self.has(next(p for p in s["proposals"] if p["via"]["kind"] == "chat")["via"], ("by",), "a chat proposal's via")
        msgs = {m["id"]: m for m in s["chat"]}
        self.has(msgs["M1"], ("id", "pid", "text", "at", "proposed"), "a proposed chat message")
        self.has(msgs["M2"]["replyTo"], ("id", "pid", "excerpt"), "a reply")
        res = s["results"]["Q1"][0]
        self.has(res, ("id", "kind", "summary", "sources", "report", "at", "request", "used", "why", "published"), "a result")
        self.has(res["used"][0], ("name",), "a result's used entry")
        for r in s["requests"]:
            self.has(r, ("id", "qid", "kind", "text", "edited", "pid", "at", "status"), f"request {r['id']}")
        self.has(s["mergeRequests"][0], ("id", "from", "to", "at", "status"), "a merge request")
        for p in s["people"] + s["removed"]:
            self.has(p, ("pid", "name", "role", "trusted", "joinedAt"), f"person {p['pid']}")
        self.has(s["presence"][0], ("pid", "q", "typing", "chatTyping"), "presence")
        self.has(s["me"], ("pid", "name", "role", "trusted", "prefs", "notifications", "unread", "votes", "reactions"), "me")

    def test_a_guest_snapshot_holds_the_shared_names_and_none_of_the_owners(self):
        code, _, out = call(self.port, "POST", "/api/join", {"name": "Cy", "device": "phone", "key": self.KEY})
        self.assertEqual(code, 200, out)
        s = self.snap({"X-Session-Secret": out["secret"]})
        self.has(s, self.TOP_ALL, "guest snapshot")
        self.assertEqual(sorted((self.TOP_MODERATOR | self.TOP_OWNER) & set(s)), [])

    def test_a_leader_gets_the_share_link_and_guest_key(self):
        code, _, out = call(self.port, "POST", "/api/join", {"name": "Lee", "device": "computer", "key": self.KEY})
        self.assertEqual(code, 200, out)
        call(self.port, "POST", "/api/person/role", {"pid": out["pid"], "role": "leader"}, self.owner)
        s = self.snap({"X-Session-Secret": out["secret"]})
        self.has(s, self.TOP_ALL | self.TOP_MODERATOR, "leader snapshot")
        self.assertEqual(sorted(self.TOP_OWNER & set(s)), [])


class TestControl(ServerCase):
    def test_ops_need_the_control_token(self):
        code, _, _ = call(self.app.control_port, "POST", "/api/ops", {"ops": []}, {"X-Shared-Token": "wrong"})
        self.assertEqual(code, 403)

    def test_the_control_token_comes_from_the_private_secrets_file(self):
        self.assertEqual(self.app.hub.token, json.loads((self.d / server.SECRETS).read_text(encoding="utf-8"))["control"])

    @unittest.skipIf(WINDOWS, "file modes are advisory on Windows")
    def test_secret_files_and_the_log_are_private(self):
        for name in (server.SECRETS, server.OWNER_LINK, "state.json", "server.log", ".shared-session.env"):
            with self.subTest(name=name):
                self.assertEqual(stat.S_IMODE((self.d / name).stat().st_mode), 0o600)

    def test_a_refused_op_names_its_index(self):
        code, _, out = self.ops({"op": "set-title", "title": "Fine"}, {"op": "ack-round", "round": 1})
        self.assertEqual((code, out["error"], out["op"]), (409, "wrong-status", 1))

    def test_add_asset_lands_in_assets_and_is_served(self):
        src = self.d / "shot.png"
        src.write_bytes(PNG)
        code, _, out = self.ops({"op": "add-asset", "path": str(src), "scale": 2})
        self.assertEqual(code, 200, out)
        aid = out["results"][0]["id"]
        code, h, body = self.get(f"/assets/{aid}")
        self.assertEqual((code, body, h["Content-Security-Policy"]), (200, PNG, "sandbox"))

    def test_the_ping_reports_the_guest_port_and_schema(self):
        code, _, out = call(self.app.control_port, "GET", "/api/ping")
        self.assertEqual(code, 200)
        self.assertEqual((out["guestPort"], out["schemaVersion"], out["build"]), (self.port, 1, server.build_hash()))

    def test_a_sent_round_reaches_the_watcher_and_is_stamped_delivered(self):
        self.open_round("Q1")
        _, guest = self.join("Ann")
        self.post("/api/answer", {"qid": "Q1", "text": "Yes", "device": "computer", "view": "focus"}, guest)
        self.post("/api/round/send", {}, self.owner)
        code, _, out = call(self.app.control_port, "GET", "/api/wait?after=handled&timeout=5", headers={"X-Shared-Token": self.app.hub.token}, timeout=20)
        self.assertEqual(code, 200)
        self.assertEqual([e["kind"] for e in out["events"]], ["round-sent"])
        self.assertIn("DATA", out["note"])
        on_disk = json.loads((self.d / "state.json").read_text(encoding="utf-8"))
        self.assertTrue(on_disk["log"]["events"][0].get("deliveredAt"))

    def test_status_counts_people_and_the_queue(self):
        self.join("Ann")
        code, _, out = call(self.app.control_port, "GET", "/api/status", headers={"X-Shared-Token": self.app.hub.token})
        self.assertEqual((code, out["people"]["joined"], out["tunnel"]), (200, 1, "off"))
        self.assertEqual(call(self.app.control_port, "GET", "/api/status")[0], 403)


class TestStart(unittest.TestCase):
    @unittest.skipIf(WINDOWS, "file modes are advisory on Windows")
    def test_the_staging_folder_for_captures_is_private(self):
        d = tmpdir(self)
        server.App(d, watch_tunnel=False).shutdown()
        self.assertEqual(stat.S_IMODE((d / "staging").stat().st_mode), 0o700)

    def test_defaults_json_settings_apply_when_the_session_is_created(self):
        d = tmpdir(self)
        (d / "defaults.json").write_text(json.dumps({"settings": {"names": "initials", "voting": False}}), encoding="utf-8")
        app = server.App(d, watch_tunnel=False)
        self.addCleanup(app.shutdown)
        settings = app.session.state["session"]["settings"]
        self.assertEqual((settings["names"], settings["voting"], settings["chat"]), ("initials", False, True))

    def test_a_defaults_file_with_unknown_keys_is_refused(self):
        d = tmpdir(self)
        (d / "defaults.json").write_text(json.dumps({"voting": False}), encoding="utf-8")
        with self.assertRaises(server.StartRefused):
            server.App(d, watch_tunnel=False)

    def test_a_newer_schema_is_refused_naming_both_versions(self):
        d = tmpdir(self)
        server.App(d, watch_tunnel=False).shutdown()
        doc = json.loads((d / "state.json").read_text(encoding="utf-8"))
        doc["schemaVersion"] = 99
        (d / "state.json").write_text(json.dumps(doc), encoding="utf-8")
        with self.assertRaisesRegex(server.StartRefused, "99.*newer than 1"):
            server.App(d, watch_tunnel=False)

    def test_an_initial_state_file_seeds_a_new_session_through_migrate(self):
        d, src = tmpdir(self), tmpdir(self)
        server.App(src, watch_tunnel=False).shutdown()
        doc = json.loads((src / "state.json").read_text(encoding="utf-8"))
        doc["session"]["title"] = "Imported"
        (src / "seed.json").write_text(json.dumps(doc), encoding="utf-8")
        calls = []
        real = session.migrate.migrate
        with mock.patch.object(session.migrate, "migrate", side_effect=lambda *a: calls.append(a[0]) or real(*a)):
            app = server.App(d, watch_tunnel=False, initial_state=src / "seed.json")
        self.addCleanup(app.shutdown)
        self.assertEqual((app.session.state["session"]["title"], len(calls)), ("Imported", 1))

    def test_an_invalid_initial_state_leaves_no_state_file(self):
        d = tmpdir(self)
        (d / "seed.json").write_text(json.dumps({"schemaVersion": 1}), encoding="utf-8")
        with self.assertRaises(server.StartRefused):
            server.App(d, watch_tunnel=False, initial_state=d / "seed.json")
        self.assertFalse((d / "state.json").exists())

    def test_the_log_rotates_at_its_size_keeping_three(self):
        d = tmpdir(self)
        with mock.patch.object(server, "LOG_BYTES", 400):
            app = server.App(d, watch_tunnel=False)
            app.serve()
            self.addCleanup(app.shutdown)
            for _ in range(60):
                call(app.guest_port, "GET", "/api/state")
        names = sorted(p.name for p in d.glob("server.log*"))
        self.assertEqual(names, ["server.log", "server.log.1", "server.log.2", "server.log.3"])
        if not WINDOWS:
            self.assertEqual({stat.S_IMODE((d / n).stat().st_mode) for n in names}, {0o600})


class TestFailureLog(ServerCase):
    def test_a_failing_route_logs_its_traceback_on_one_escaped_line(self):
        _, guest = self.join("Ann")
        boom = RuntimeError("boom\x1b[31m\n2026-01-01 00:00:00,000 INFO FORGED line")
        with mock.patch.object(session.Session, "rename", side_effect=boom):
            code, _, out = self.post("/api/rename", {"name": "Bo"}, guest)
        self.assertEqual((code, out["error"]), (500, "state-invalid"))
        for h in self.app.log.handlers:
            h.flush()
        log = (self.d / "server.log").read_text(encoding="utf-8")
        self.assertNotIn("\x1b", log)
        self.assertFalse([line for line in log.splitlines() if line.startswith("2026-01-01")])  # no forged line of its own
        self.assertIn("boom\\x1b[31m\\x0a2026-01-01", log)


class TestOldPages(unittest.TestCase):
    """A prototype page left open across the cutover polls `GET /api/state` with no query string and
    its identity headers (X-Session-Secret, and X-Owner-Token on the owner's tab), as its core.js
    poll() does. In a session imported from the prototype it gets a payload its script reads."""

    SECRET = "fixture-guest-secret-ann-not-a-real-secret-000"
    OWNER = "fixture-owner-token-0001"

    def setUp(self):
        self.d = tmpdir(self)
        self.app = server.App(self.d, watch_tunnel=False, initial_state=FIXTURES / "state-v0-prototype.json")
        self.app.serve()
        self.addCleanup(self.app.shutdown)

    def poll(self, path, headers):
        return call(self.app.guest_port, "GET", path, headers=headers)

    def test_an_old_page_poll_gets_the_reload_banner(self):
        for who in ({"X-Session-Secret": self.SECRET}, {"X-Owner-Token": self.OWNER}):
            code, _, out = self.poll("/api/state", who)
            self.assertEqual(code, 200)
            self.assertEqual(out, {"schemaVersion": 1, "rev": self.app.session.state["rev"], "outdated": True, "title": "This page was updated: reload"})

    def test_the_payload_overrides_no_default_of_the_old_script_with_another_type(self):
        """fixtures/old-page-defaults.json is DEFAULTS from the prototype page's script
        (.work/shared-interview-proto/web/core.js), which spreads each poll's answer over it."""
        defaults = json.loads((FIXTURES / "old-page-defaults.json").read_text(encoding="utf-8"))["defaults"]
        _, _, out = self.poll("/api/state", {"X-Session-Secret": self.SECRET})
        self.assertEqual({k: type(v) for k, v in out.items()}, {"schemaVersion": int, "rev": int, "outdated": bool, "title": str})
        self.assertIs(type(defaults["title"]), str)  # the one key the old script also has keeps its type
        self.assertEqual(set(out) & set(defaults), {"title"})  # settings among them: absent keeps the script's own

    def test_a_poll_with_a_query_string_gets_the_full_snapshot(self):
        code, _, out = self.poll("/api/state?since=0", {"X-Session-Secret": self.SECRET})
        self.assertEqual((code, out["me"]["pid"]), (200, "pidAnn001"))

    def test_a_visitor_without_identity_gets_the_anonymous_view(self):
        _, _, out = self.poll("/api/state", {})
        self.assertEqual(sorted(out), ["ended", "joinNeedsKey", "schemaVersion", "title"])

    def test_a_session_not_imported_answers_every_poll_in_full(self):
        d = tmpdir(self)
        app = server.App(d, watch_tunnel=False)
        app.serve()
        self.addCleanup(app.shutdown)
        code, _, out = call(app.guest_port, "GET", "/api/state", headers={"X-Owner-Token": app.secrets["owner"]})
        self.assertEqual((code, out["me"]["role"]), (200, "owner"))


class TestTunnelWatch(unittest.TestCase):
    def test_an_exited_tunnel_is_restarted_with_a_new_link_the_owner_sees(self):
        d = tmpdir(self)
        with mock.patch.dict(os.environ, {"SHARED_CLOUDFLARED": FAKE, "SHARED_TUNNEL_SECONDS": "10"}):
            app = server.App(d)
            self.addCleanup(tunnel.stop, d)
            self.addCleanup(app.shutdown)
            first = tunnel.ensure(d, app.guest_port)
            app.serve()
            wait_for(lambda: app.public_url == first["url"])
            self.assertEqual(app.session.state["session"]["share"]["url"], first["url"])
            detached.stop(first["pid"], first["marker"])
            second = wait_for(lambda: app.public_url != first["url"] and app.public_url, seconds=20)
        self.assertRegex(second, tunnel.URL)
        share = app.session.state["session"]["share"]
        self.assertEqual(share["url"], second)
        self.assertIn("changedAt", share)
        code, _, _ = call(app.guest_port, "GET", "/api/state", headers={"Host": tunnel.host(second)})
        self.assertEqual(code, 200)
        code, _, _ = call(app.guest_port, "GET", "/api/state", headers={"Host": tunnel.host(first["url"])})
        self.assertEqual(code, 403)


if __name__ == "__main__":
    unittest.main()

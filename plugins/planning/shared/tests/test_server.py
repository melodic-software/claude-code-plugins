"""server.py: listeners, auth classes, Host checks, headers, caps, errors and the snapshot.

Expected values come from the Design's Contracts ("Listeners", "Auth classes", "Guest listener
routes", "Control listener", "Errors", "Body caps and limits") and the planning amendments
(anonymous view, CF-Connecting-IP only, tokens from 0600 files, results wait for Publish), never
from running the server.
"""

from __future__ import annotations

import base64
import contextlib
import hashlib
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

from support import FAKE, FIXTURES, WINDOWS, call, share, tmpdir, wait_for

import detached
import server
import session
import tunnel

PAGE_CSP = "default-src 'self'; img-src 'self' data:; frame-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
SECURITY = {"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY", "Referrer-Policy": "no-referrer"}
HTML_ASSET_CSP = (
    "sandbox allow-scripts; default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; font-src data:; "
    "connect-src 'none'; frame-ancestors 'self'"
)
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
        code, _, out = self.post("/api/join", {"name": name, "device": "computer", "key": self.app.session.state["session"]["guestKey"]}, h)
        self.assertEqual(code, 200, out)
        return out["pid"], {"X-Session-Secret": out["secret"]}

    def claude_from_before(self):
        """A person named "Claude" in a session from before join and rename refused that name."""
        pid, _ = self.join("Cee")
        with self.app.session._tx() as st:
            st["people"][pid]["name"] = "Claude"
        return pid

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
        # Join and a device's sign-in code are the routes a newcomer reaches before holding a credential; any other
        # public route goes unchecked here.
        self.assertEqual(["/api/join", "/api/owner/pair/redeem"], sorted(p for p, (a, _) in server.ROUTES.items() if a == "public"))
        for path, (auth, _) in server.ROUTES.items():
            if auth == "public":
                continue
            with self.subTest(path=path):
                code, _, out = self.post(path, {})
                want = (403, "owner-only") if auth in ("owner", "host") else (401, "unknown-session")
                self.assertEqual((code, out["error"]), want)

    def test_owner_routes_refuse_a_leader(self):
        for path, (auth, _) in server.ROUTES.items():
            if auth in ("owner", "host"):
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
        code, _, out = self.post("/api/join", {"name": "Cy", "device": "phone", "key": self.app.session.state["session"]["guestKey"]})
        self.assertEqual(code, 200)
        self.assertEqual(sorted(out), ["name", "ok", "pid", "secret"])


class TestOwnerDevices(ServerCase):
    """Signing the owner in on another device over HTTP. Expected values come from the owner's decision: the code is
    made only where the owner link was opened, the device gets its own credential and owner rights, the owner link's
    token never reaches it, and signing it out ends it at once, its asset cookie included."""

    def setUp(self):
        super().setUp()
        self.guest_pid, self.guest = self.join("Ann")

    def pair(self, ip="203.0.113.5"):
        code, _, out = self.post("/api/owner/pair", {}, self.owner)
        self.assertEqual(code, 200, out)
        code, _, dev = self.post("/api/owner/pair/redeem", {"code": out["code"], "device": "phone"}, {"CF-Connecting-IP": ip})
        self.assertEqual(code, 200, dev)
        return out["code"], dev

    def test_a_device_signs_in_once_and_acts_as_the_owner(self):
        code, dev = self.pair()
        mine = {"X-Owner-Token": dev["token"]}
        status, _, out = self.get("/api/state", mine)
        self.assertEqual((status, out["me"]["role"]), (200, "owner"))
        self.assertEqual([d["id"] for d in out["ownerDevices"]], [dev["id"]])
        status, _, out = self.post("/api/session/title", {"title": "From my phone"}, mine)
        self.assertEqual((status, out["title"]), (200, "From my phone"))
        status, _, out = self.post("/api/owner/pair/redeem", {"code": code}, {"CF-Connecting-IP": "198.51.100.7"})
        self.assertEqual((status, out["error"]), (403, "bad-pair-code"))

    def test_only_the_owner_links_device_makes_codes_or_a_new_owner_link(self):
        _, dev = self.pair()
        before = (self.d / server.SECRETS).read_text(encoding="utf-8")
        for path in ("/api/owner/pair", "/api/link/owner"):
            with self.subTest(path=path):
                status, _, out = self.post(path, {}, {"X-Owner-Token": dev["token"]})
                self.assertEqual((status, out["error"]), (403, "host-device-only"))
                self.assertNotIn(self.app.secrets["owner"], json.dumps(out))
                status, _, out = self.post(path, {}, self.guest)
                self.assertEqual((status, out["error"]), (403, "owner-only"))
        self.assertEqual((self.d / server.SECRETS).read_text(encoding="utf-8"), before)

    def test_signing_a_device_out_ends_it_and_its_asset_cookie_at_once(self):
        (self.d / "assets").mkdir()
        (self.d / "assets" / "0123456789abcdef.png").write_bytes(PNG)
        _, dev = self.pair()
        mine = {"X-Owner-Token": dev["token"]}
        cookie = {"Cookie": self.get("/api/state", mine)[1]["Set-Cookie"].split("; ")[0]}
        self.assertEqual(self.get("/assets/0123456789abcdef.png", cookie)[0], 200)
        status, _, out = self.post("/api/owner/devices/revoke", {"id": dev["id"]}, self.owner)
        self.assertEqual(status, 200, out)
        self.assertEqual(self.get("/api/state", mine)[0], 401)
        self.assertEqual(self.get("/assets/0123456789abcdef.png", cookie)[0], 401)
        self.assertEqual(self.get("/api/state", self.owner)[0], 200)

    def test_a_new_owner_link_signs_out_every_device(self):
        devs = [self.pair()[1]]
        time.sleep(session.WRITE_INTERVAL)  # one code a second
        devs.append(self.pair("198.51.100.7")[1])
        status, _, out = self.post("/api/link/owner", {}, self.owner)
        self.assertEqual(status, 200, out)
        for dev in devs:
            self.assertEqual(self.get("/api/state", {"X-Owner-Token": dev["token"]})[0], 401)

    def test_the_log_never_holds_a_code_or_a_credential(self):
        code, dev = self.pair()
        self.post("/api/owner/pair/redeem", {"code": code}, {"CF-Connecting-IP": "198.51.100.7"})
        log = (self.d / "server.log").read_text(encoding="utf-8")
        self.assertIn("route=/api/owner/pair/redeem", log)
        for secret in (code, dev["token"]):
            self.assertNotIn(secret, log)


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
            self.d / tunnel.RECORD, json.dumps({"pid": proc.pid, "url": f"https://{host}", "port": self.port, "marker": "python" if WINDOWS else "cloudflared", "processStart": detached.started(proc.pid), "startedAt": 0})
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

    def test_web_vitals_is_served_unedited_beside_its_license(self):
        """The vendored web-vitals 6.2.3 attribution build: the bytes of dist/web-vitals.attribution.iife.js in the npm
        tarball (sha256 taken from that tarball), served from this origin; its Apache-2.0 license sits beside it."""
        code, h, body = self.get("/web-vitals.attribution.iife.js")
        self.assertEqual((code, h["Content-Type"]), (200, "text/javascript; charset=utf-8"))
        self.assertEqual(hashlib.sha256(body).hexdigest(), "42d0cfd64b5cf19408e19c0393ce59eef6cc09317e94faaca6d3a032d4112e48")
        self.assertIn("Apache License", (server.WEB / "web-vitals.LICENSE").read_text(encoding="utf-8")[:200])
        self.assertEqual(self.get("/web-vitals.LICENSE")[0], 404)

    def test_assets_are_sandboxed_and_inline(self):
        (self.d / "assets").mkdir()
        (self.d / "assets" / "0123456789abcdef.png").write_bytes(PNG)
        (self.d / "assets" / "fedcba9876543210.html").write_text("<html></html>", encoding="utf-8")
        code, h, body = self.get("/assets/0123456789abcdef.png", self.owner)
        self.assertEqual((code, h["Content-Type"], h["Content-Security-Policy"], h["Content-Disposition"], body), (200, "image/png", "sandbox", "inline", PNG))
        _, h, _ = self.get("/assets/fedcba9876543210.html", self.owner)
        self.assertEqual(h["Content-Security-Policy"], HTML_ASSET_CSP)
        self.assertNotIn("allow-same-origin", h["Content-Security-Policy"])
        code, _, _ = self.get("/assets/0123456789abcdef.exe", self.owner)
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

    def test_unknown_routes_are_404(self):
        for path in ("/api/upload", "/api/upload/chunks", "/api/nope"):
            with self.subTest(path=path):
                code, _, out = self.post(path, {})
                self.assertEqual((code, out["error"]), (404, "not-found"))

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
        code, _, out = self.post("/api/join", {"name": "Late", "key": self.app.session.state["session"]["guestKey"]}, {"CF-Connecting-IP": "198.51.100.7", "X-Forwarded-For": "192.0.2.1"})
        self.assertEqual((code, out["error"]), (429, "join-rate"))
        code, _, _ = self.post("/api/join", {"name": "Other", "key": self.app.session.state["session"]["guestKey"]}, {"CF-Connecting-IP": "198.51.100.8"})
        self.assertEqual(code, 200)


class TestGuestKey(ServerCase):
    def test_a_new_session_refuses_a_join_without_its_guest_key(self):
        self.assertTrue(self.get("/api/state")[2]["joinNeedsKey"])
        code, _, out = self.post("/api/join", {"name": "No key"})
        self.assertEqual((code, out["error"]), (403, "bad-guest-key"))

    def test_a_keyless_session_from_before_stays_keyless_across_a_restart(self):
        self.app.shutdown()
        doc = json.loads((self.d / server.STATE).read_text(encoding="utf-8"))
        doc["session"]["guestKey"] = ""
        (self.d / server.STATE).write_text(json.dumps(doc), encoding="utf-8")
        app = server.App(self.d, watch_tunnel=False)
        app.serve()
        self.addCleanup(app.shutdown)
        code, _, out = call(app.guest_port, "POST", "/api/join", {"name": "Ann", "device": "computer"})
        self.assertEqual(code, 200, out)
        self.assertEqual(app.session.state["session"]["guestKey"], "")


class TestAssetAccess(ServerCase):
    def setUp(self):
        super().setUp()
        (self.d / "assets").mkdir()
        (self.d / "assets" / "0123456789abcdef.png").write_bytes(PNG)
        self.pid, self.guest = self.join("Ann")

    def png(self, headers=None):
        code, _, body = self.get("/assets/0123456789abcdef.png", headers)
        return code, body if code == 200 else body["error"]

    def cookie(self, headers):
        """The asset cookie a state read sets, as a Cookie header, and its attributes."""
        _, h, _ = self.get("/api/state", headers)
        pair, *attrs = h["Set-Cookie"].split("; ")
        return {"Cookie": pair}, attrs

    def test_an_asset_needs_a_person_or_the_owner(self):
        self.assertEqual(self.png(), (401, "unknown-session"))
        self.assertEqual(self.png({"X-Session-Secret": "forged"}), (401, "unknown-session"))
        self.assertEqual(self.png(self.guest), (200, PNG))
        self.assertEqual(self.png(self.owner), (200, PNG))

    def test_a_state_read_sets_an_asset_cookie_that_reads_assets_only_while_the_person_may(self):
        cookie, attrs = self.cookie(self.guest)
        self.assertEqual(attrs, ["Path=/assets/", f"Max-Age={server.ASSET_COOKIE_SECONDS}", "HttpOnly", "SameSite=Strict"])
        self.assertEqual(self.png(cookie), (200, PNG))
        self.assertEqual(self.png(self.cookie(self.owner)[0]), (200, PNG))
        code, _, out = self.post("/api/person/remove", {"pid": self.pid, "on": True}, self.owner)
        self.assertEqual(code, 200, out)
        self.assertEqual(self.png(cookie), (403, "removed"))

    def test_an_anonymous_state_read_sets_no_cookie(self):
        self.assertNotIn("Set-Cookie", self.get("/api/state")[1])

    def test_a_forged_expired_or_other_session_cookie_reads_nothing(self):
        cookie, _ = self.cookie(self.guest)
        name, value = cookie["Cookie"].split("=", 1)
        pid, exp, sig = value.split(".")
        forged = {
            "another pid": f"{name}=host.{exp}.{sig}",
            "a later expiry": f"{name}={pid}.{int(exp) + 1}.{sig}",
            "another port's name": f"shared-assets-1={value}",
            "a superscript digit expiry": f"{name}={pid}.².{sig}",
            "a huge expiry": f"{name}={pid}.{'9' * 5000}.{sig}",
            "a non-ASCII signature": f"{name}={pid}.{exp}.é{sig[1:]}",
        }
        for what, c in forged.items():
            with self.subTest(what):
                self.assertEqual(self.png({"Cookie": c}), (401, "unknown-session"))
        with mock.patch.object(server, "ASSET_COOKIE_SECONDS", -1):
            expired, _ = self.cookie(self.guest)
        self.assertEqual(self.png(expired), (401, "unknown-session"))


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
        for h in app.log.handlers:
            h.flush()
        log = (d / "server.log").read_text(encoding="utf-8")
        self.assertRegex(log, r" ERROR request method=- route=- status=503 ms=0\.0 code=busy message=\"The session is busy; try again in a moment.\"\n")
        for s in idle:
            s.close()
        self.assertTrue(wait_for(lambda: call(app.guest_port, "GET", "/api/state")[0] == 200, seconds=10))

    def busy_app(self):
        with mock.patch.object(session, "MAX_HANDLERS", 1):
            app = server.App(tmpdir(self), watch_tunnel=False)
        app.serve()
        self.addCleanup(app.shutdown)
        idle = socket.create_connection(("127.0.0.1", app.guest_port), timeout=5)
        self.addCleanup(idle.close)
        wait_for(lambda: app.guest.slots._value == 0, seconds=5)
        return app

    def refused(self, app):
        """A client past the cap that sends its request and reads the whole 503."""
        s = socket.create_connection(("127.0.0.1", app.guest_port), timeout=5)
        self.addCleanup(s.close)
        s.sendall(f"GET /api/state HTTP/1.1\r\nHost: 127.0.0.1:{app.guest_port}\r\n\r\n".encode("ascii"))
        got = b""
        while chunk := s.recv(4096):
            got += chunk
        self.assertTrue(got.startswith(b"HTTP/1.1 503 "), got)
        return s

    def test_the_503_is_no_reset_while_the_client_still_sends(self):
        # A socket closed with its request unread resets the connection, and a Windows client then drops the 503 it
        # already holds (WinError 10053). Here the reset shows as the client's next send failing.
        app = self.busy_app()
        s = self.refused(app)
        time.sleep(0.3)
        s.sendall(b"more of the request")
        time.sleep(0.3)
        s.sendall(b"and more")

    def test_reading_a_refused_client_stops_at_its_time_and_byte_bounds(self):
        app = self.busy_app()
        with mock.patch.object(server.GuestServer, "DRAIN_SECONDS", 0.3):
            self.refused(app)  # and never closes
            self.assertTrue(wait_for(lambda: app.guest.drains._value == server.GuestServer.DRAINS, seconds=1.5, step=0.05))
        with mock.patch.object(server.GuestServer, "DRAIN_SECONDS", 60), mock.patch.object(server.GuestServer, "DRAIN_BYTES", 1024):
            s = self.refused(app)
            with contextlib.suppress(OSError):
                s.sendall(b"x" * 4096)
            self.assertTrue(wait_for(lambda: app.guest.drains._value == server.GuestServer.DRAINS, seconds=3, step=0.05))


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


class TestWritePrivate(unittest.TestCase):
    """A private file is replaced whole or not at all, and a failed write leaves nothing beside it."""

    def test_a_failed_write_keeps_the_old_file_and_leaves_no_temp_file(self):
        d = tmpdir(self)
        target = d / ".shared-secrets.json"
        detached.write_private(target, '{"owner": "old"}\n')
        for point in ("fsync", "replace"):
            with self.subTest(fails_at=point), mock.patch.object(detached.os, point, side_effect=OSError("disk full")), self.assertRaises(OSError):
                detached.write_private(target, '{"owner": "new"}\n')
            self.assertEqual(sorted(p.name for p in d.iterdir()), [".shared-secrets.json"])
            self.assertEqual(target.read_text(encoding="utf-8"), '{"owner": "old"}\n')


class TestDataFolderRule(unittest.TestCase):
    """Windows keeps the data folder private only under the user profile; WSL's DrvFs ignores file
    modes unless mounted with metadata (Brief: runs on Windows, macOS and Linux)."""

    def problem_on_windows(self, path, profile):
        with mock.patch.object(detached, "WINDOWS", True), mock.patch.dict(os.environ, {"USERPROFILE": profile}):
            return detached.data_dir_problem(path)

    def test_windows_refuses_a_folder_outside_the_profile(self):
        self.assertIn("outside your user profile", self.problem_on_windows(r"D:\shared\po", r"C:\Users\{user}"))
        self.assertIn("outside your user profile", self.problem_on_windows(r"C:\Users\{user}2\po", r"C:\Users\{user}"))
        self.assertIsNone(self.problem_on_windows(r"c:\users\{USER}\.claude\memory\shared\po", r"C:\Users\{user}"))

    @unittest.skipIf(WINDOWS, "WSL paths")
    def test_wsl_refuses_a_drvfs_folder_mounted_without_metadata(self):
        plain = [("/", "ext4", "rw,relatime"), ("/mnt/c", "9p", "rw,noatime,dirsync,aname=drvfs;path=C:\\;uid=1000;gid=1000;symlinkroot=/mnt/,mmap,access=client")]
        meta = [("/", "ext4", "rw,relatime"), ("/mnt/c", "9p", "rw,noatime,dirsync,aname=drvfs;path=C:\\;uid=1000;gid=1000;metadata;symlinkroot=/mnt/,mmap")]
        cases = [(plain, "/mnt/c/Users/{user}/po", True), (plain, "/home/{user}/po", False), (meta, "/mnt/c/Users/{user}/po", False)]
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
    def test_the_anonymous_view_has_only_the_three_keys(self):
        code, _, out = self.get("/api/state")
        self.assertEqual(code, 200)
        self.assertEqual(sorted(out), ["ended", "joinNeedsKey", "title"])

    def test_a_person_snapshot_carries_the_reload_trigger(self):
        _, guest = self.join("Ann")
        code, h, out = self.get("/api/state", guest)
        self.assertEqual(code, 200)
        self.assertNotIn("schemaVersion", out)
        self.assertIsInstance(out["rev"], int)
        self.assertEqual(out["build"], server.build_hash())
        self.assertEqual(h["X-Shared-Build"], out["build"])
        self.assertNotIn("credentials", out)
        self.assertNotIn("log", out)

    def test_a_second_device_with_the_personal_secret_is_the_same_person_with_the_same_prefs(self):
        pid, laptop = self.join("Ann", ip="203.0.113.5")
        code, _, out = self.post("/api/prefs", {"set": {"theme": "dark", "claudeTake": "always"}}, {**laptop, "CF-Connecting-IP": "203.0.113.5"})
        self.assertEqual(code, 200, out)
        code, _, out = self.get("/api/state?since=0", {**laptop, "CF-Connecting-IP": "198.51.100.7"})
        self.assertEqual(code, 200, out)
        self.assertEqual(out["me"]["pid"], pid)
        self.assertEqual(out["me"]["prefs"], {"theme": "dark", "claudeTake": "always"})

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
        now = server.time.time()  # one PRESENCE_TICK for every read: the tick turning over is its own test below
        with mock.patch.object(server.time, "time", lambda: now):
            _, h, _ = self.get("/api/state", guest)
            code, h2, body = self.get("/api/state", {**guest, "If-None-Match": h["ETag"]})
            self.assertEqual((code, h2["ETag"], body), (304, h["ETag"], None))
            self.post("/api/rename", {"name": "Annie"}, guest)
            code, _, out = self.get("/api/state", {**guest, "If-None-Match": h["ETag"]})
        self.assertEqual((code, out["me"]["name"]), (200, "Annie"))

    def test_a_presence_change_alone_answers_only_the_presence_part(self):
        ann_pid, ann = self.join("Ann")
        bo_pid, bo = self.join("Bo")
        now = server.time.time()  # one PRESENCE_TICK for every read: the tick turning over is test_the_clock_tick_answers_presence_so_an_offline_person_drops_out
        with mock.patch.object(server.time, "time", lambda: now):
            _, h, snap = self.get("/api/state?since=0", ann)
            self.post("/api/heartbeat", {"q": "Q1", "tab": "t1"}, bo)
            code, h2, out = self.get(f"/api/state?since={snap['rev']}", {**ann, "If-None-Match": h["ETag"]})
            self.assertEqual((code, sorted(out)), (200, ["lastSeen", "presence", "presenceOnly", "rev", "serverTime"]))
            self.assertEqual((out["rev"], out["presenceOnly"], session.wire_error(out, "presenceOnly")), (snap["rev"], True, None))
            self.assertIn({"pid": bo_pid, "q": "Q1", "typing": False, "chatTyping": False, "state": "active"}, out["presence"])
            code, _, _ = self.get(f"/api/state?since={snap['rev']}", {**ann, "If-None-Match": h2["ETag"]})
            self.assertEqual(code, 304)
            self.post("/api/chat", {"text": "Hello"}, bo)
            code, _, out = self.get(f"/api/state?since={snap['rev']}", {**ann, "If-None-Match": h2["ETag"]})
            self.assertEqual((code, "presenceOnly" in out, [m["text"] for m in out["chat"]]), (200, False, ["Hello"]))
            self.assertEqual(out["me"]["pid"], ann_pid)

    def test_the_clock_tick_answers_presence_so_an_offline_person_drops_out(self):
        _, ann = self.join("Ann")
        bo_pid, bo = self.join("Bo")
        self.post("/api/heartbeat", {"tab": "t1"}, bo)
        _, h, snap = self.get("/api/state?since=0", ann)
        self.assertIn(bo_pid, [p["pid"] for p in snap["presence"]])
        later = self.app.session.clock() + session.OFFLINE_AFTER + 1
        with mock.patch.object(self.app.session, "clock", lambda: later), mock.patch.object(server.time, "time", lambda: later):
            code, _, out = self.get(f"/api/state?since={snap['rev']}", {**ann, "If-None-Match": h["ETag"]})
        self.assertEqual((code, out.get("presenceOnly")), (200, True))
        self.assertNotIn(bo_pid, [p["pid"] for p in out["presence"]])
        self.assertIn(bo_pid, out["lastSeen"])

    def test_chat_pages_through_get_api_chat_as_a_person(self):
        _, ann = self.join("Ann")
        ids = []
        for i in range(55):
            with mock.patch.object(self.app.session, "clock", lambda i=i: 1_900_000_000.0 + 2 * i):
                ids.append(self.post("/api/chat", {"text": f"Message {i}"}, ann)[2]["id"])
        snap = self.get("/api/state", ann)[2]
        self.assertEqual(([m["id"] for m in snap["chat"]], snap["chatBefore"]), (ids[5:], ids[5]))
        code, _, out = self.get(f"/api/chat?before={snap['chatBefore']}&limit=3", ann)
        self.assertEqual((code, [m["id"] for m in out["chat"]], out["before"]), (200, ids[2:5], ids[2]))
        self.assertIsNone(session.wire_error(out, "chatPage"))
        code, _, out = self.get(f"/api/chat?around={ids[0]}&limit=4", ann)
        self.assertEqual((code, [m["id"] for m in out["chat"]], "before" in out), (200, ids[:4], False))
        self.assertEqual(self.get(f"/api/chat?before={ids[5]}")[0], 401)
        code, _, out = self.get(f"/api/chat?before={ids[5]}&limit=101", ann)
        self.assertEqual((code, out["error"], out["field"]), (400, "bad-field", "limit"))

    def test_the_owner_sees_the_guest_link_and_whether_it_changed(self):
        self.app.session.set_share("https://one-a.trycloudflare.com")
        self.app.session.set_share("https://two-b.trycloudflare.com")
        _, _, out = self.get("/api/state", self.owner)
        self.assertEqual(out["share"]["url"], "https://two-b.trycloudflare.com")
        self.assertIn("changedAt", out["share"])
        _, guest = self.join("Ann")
        self.assertNotIn("share", self.get("/api/state", guest)[2])

    def test_a_result_stays_hidden_from_guests_until_the_owner_publishes_it(self):
        self.assertEqual(self.post("/api/session/settings", {"reviewAnswers": True}, self.owner)[0], 200)
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

    def test_the_inbox_read_route_marks_only_ones_own_items_and_needs_a_person(self):
        self.open_round("Q1")
        _, ann = self.join("Ann")
        _, bo = self.join("Bo")
        code, _, req = self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": "Ann asks"}, ann)
        self.assertEqual(code, 200, req)
        self.post("/api/request/act", {"action": "run", "ids": [req["id"]]}, self.owner)

        def mine(who):
            return {i["key"]: i["unread"] for i in self.get("/api/state", who)[2]["inbox"]}

        self.assertEqual((mine(ann), mine(bo)), ({req["id"]: True}, {}))
        self.assertEqual(self.post("/api/inbox/read", {"keys": [req["id"]]}, bo)[2]["read"], 0)
        self.assertEqual(mine(ann), {req["id"]: True})
        self.assertEqual(self.post("/api/inbox/read", {"keys": [req["id"]]}, ann)[2]["read"], 1)
        self.assertEqual(mine(ann), {req["id"]: False})
        self.assertEqual(self.post("/api/inbox/read", {"keys": [req["id"]]})[0], 401)

    def test_inbox_reads_are_one_a_second_and_a_read_that_marks_nothing_writes_nothing(self):
        self.open_round("Q1")
        _, ann = self.join("Ann")
        ids = []
        for text in ("one", "two"):
            ids.append(self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": text}, ann)[2]["id"])
            time.sleep(1.05)
        for rid in ids:
            self.post("/api/request/act", {"action": "decline", "id": rid}, self.owner)
        self.assertEqual(self.post("/api/inbox/read", {"keys": [ids[0]]}, ann)[0], 200)
        code, _, out = self.post("/api/inbox/read", {"keys": [ids[1]]}, ann)
        self.assertEqual((code, out["error"]), (429, "slow-down"))
        time.sleep(1.05)
        rev = self.app.session.state["rev"]
        self.assertEqual(self.post("/api/inbox/read", {"keys": [ids[0]]}, ann)[2]["read"], 0)
        self.assertEqual(self.app.session.state["rev"], rev)

    def test_the_owners_own_request_runs_and_shows_without_run_or_share(self):
        self.open_round("Q1")
        _, guest = self.join("Ann")
        code, _, req = self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": "Host asks"}, self.owner)
        self.assertEqual(code, 200, req)
        self.assertEqual(self.get("/api/state", self.owner)[2]["requests"][0]["status"]["kind"], "running")
        code, _, out = self.ops({"op": "result", "qid": "Q1", "request": req["id"], "kind": "ask", "used": [], "why": "", "summary": "Shown at once.", "sources": [], "report": ""})
        self.assertEqual((code, out["results"][0]["published"]), (200, True))
        self.assertEqual([r["summary"] for r in self.get("/api/state", guest)[2]["results"]["Q1"]], ["Shown at once."])

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

    TOP_ALL = {"rev", "build", "title", "goal", "ended", "serverTime", "settings", "rounds", "round", "questions", "cards", "locks"}
    TOP_ALL |= {"suggestions", "results", "chat", "people", "presence", "lastSeen", "requestCounts", "proposals", "myRequests", "myMergeRequests", "inbox", "me"}
    TOP_MODERATOR = {"share", "guestKey"}
    TOP_OWNER = {"requests", "mergeRequests", "removed", "cardDetails"}
    KEY = "Zk3yZk3yZk3y"  # the fixture's session.guestKey

    def setUp(self):
        self.d = tmpdir(self)
        detached.write_private(self.d / "state.json", (FIXTURES / "state-sample.json").read_text(encoding="utf-8"))
        self.app = server.App(self.d, watch_tunnel=False)
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
        code, h, body = self.get(f"/assets/{aid}", self.owner)
        self.assertEqual((code, body, h["Content-Security-Policy"]), (200, PNG, "sandbox"))

    def test_the_ping_reports_the_guest_port_and_build(self):
        code, _, out = call(self.app.control_port, "GET", "/api/ping")
        self.assertEqual(code, 200)
        self.assertEqual((out["guestPort"], out["build"], "schemaVersion" in out), (self.port, server.build_hash(), False))

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

    def test_a_state_file_with_a_schema_version_starts_and_its_next_write_drops_it(self):
        d = tmpdir(self)
        server.App(d, watch_tunnel=False).shutdown()
        doc = json.loads((d / "state.json").read_text(encoding="utf-8"))
        doc["schemaVersion"] = 7
        (d / "state.json").write_text(json.dumps(doc), encoding="utf-8")
        app = server.App(d, watch_tunnel=False)
        self.addCleanup(app.shutdown)
        app.session.set_title(session.HOST, {"title": "Still here"})
        again = json.loads((d / "state.json").read_text(encoding="utf-8"))
        self.assertEqual((again["session"]["title"], again["people"], "schemaVersion" in again), ("Still here", doc["people"], False))

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


class LogCase(ServerCase):
    def log_text(self):
        for h in self.app.log.handlers:
            h.flush()
        return "\n".join(p.read_text(encoding="utf-8") for p in sorted(self.d.glob("server.log*")))

    def entry_for(self, marker):
        """The last log line holding `marker`."""
        lines = [line for line in self.log_text().splitlines() if marker in line]
        self.assertTrue(lines, f"no log line holds {marker!r}")
        return lines[-1]

    def owner_pid(self):
        return self.get("/api/state", self.owner)[2]["me"]["pid"]


class TestRequestLog(LogCase):
    """README "Logs": every 4xx and 5xx is one entry with its error code, field and message, the route, status,
    time and acting pid; a 5xx adds the traceback; never a body."""

    def test_a_refusal_logs_code_field_message_route_status_and_pid_but_no_body(self):
        guest_pid, _ = self.join("Ann")
        code, _, out = self.post("/api/person/role", {"pid": guest_pid, "role": "body-only-zebra"}, self.owner)
        self.assertEqual((code, out["error"], out["field"]), (400, "bad-field", "role"))
        line = self.entry_for("route=/api/person/role")
        self.assertRegex(line, r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d,\d{3} WARNING request method=POST route=/api/person/role status=400 ms=\d+\.\d ")
        for part in (f"pid={self.owner_pid()}", "code=bad-field", "field=role", 'message="role must be one of leader, guest."'):
            self.assertIn(part, line)
        self.assertNotIn("body-only-zebra", self.log_text())

    def test_a_server_error_on_a_post_logs_its_traceback_with_the_request(self):
        pid, guest = self.join("Ann")
        with mock.patch.object(session.Session, "rename", side_effect=RuntimeError("forced-post-failure")):
            code, _, out = self.post("/api/rename", {"name": "Bo"}, guest)
        self.assertEqual((code, out["error"]), (500, "state-invalid"))
        line = self.entry_for("route=/api/rename")
        self.assertIn(" ERROR request method=POST route=/api/rename status=500 ", line)
        for part in (f"pid={pid}", "code=state-invalid", "Traceback (most recent call last)", "RuntimeError: forced-post-failure"):
            self.assertIn(part, line)

    def test_a_session_refusal_with_a_5xx_logs_its_traceback(self):
        pid, guest = self.join("Ann")
        failure = session.DomainError(500, "state-invalid", "Nothing was written: disk full")
        with mock.patch.object(session.Session, "rename", side_effect=failure):
            code, _, out = self.post("/api/rename", {"name": "Bo"}, guest)
        self.assertEqual((code, out["error"]), (500, "state-invalid"))
        line = self.entry_for("route=/api/rename")
        self.assertIn(" ERROR request method=POST route=/api/rename status=500 ", line)
        for part in (f"pid={pid}", "code=state-invalid", 'message="Nothing was written: disk full"', "Traceback (most recent call last)", "DomainError: Nothing was written: disk full"):
            self.assertIn(part, line)

    def test_a_server_error_on_a_get_is_answered_500_and_logs_its_traceback(self):
        pid, guest = self.join("Ann")
        with mock.patch.object(session.Session, "my_requests", side_effect=RuntimeError("forced-get-failure")):
            code, _, out = self.get("/api/mine/requests", guest)
        self.assertEqual((code, out["error"]), (500, "state-invalid"))
        line = self.entry_for("route=/api/mine/requests")
        self.assertIn(" ERROR request method=GET route=/api/mine/requests status=500 ", line)
        self.assertIn(f"pid={pid}", line)
        self.assertIn("RuntimeError: forced-get-failure", line)

    def test_a_scripted_session_leaves_no_secret_or_user_text_in_the_log(self):
        self.open_round("Q1")
        code, _, rotated_key = self.post("/api/link/guest", {}, self.owner)
        self.assertEqual(code, 200, rotated_key)
        key = rotated_key["guestKey"]
        code, _, out = self.post("/api/join", {"name": "Ann", "device": "computer", "key": key})
        self.assertEqual(code, 200, out)
        guest = {"X-Session-Secret": out["secret"]}
        answer, chat = "answer-text-fixture-quokka", "chat-text-fixture-narwhal"
        self.assertEqual(self.post("/api/answer", {"qid": "Q1", "text": answer, "device": "computer", "view": "focus"}, guest)[0], 200)
        self.assertEqual(self.post("/api/chat", {"text": chat}, guest)[0], 200)
        self.assertEqual(self.post("/api/rename", {"name": "x" * 200 + answer}, guest)[0], 400)
        self.assertEqual(self.post("/api/client-log", {"kind": "error", "message": "TypeError: x is undefined"}, guest)[0], 200)
        old_owner = self.app.secrets["owner"]
        code, _, rotated = self.post("/api/link/owner", {}, self.owner)
        self.assertEqual(code, 200, rotated)
        link = (self.d / server.OWNER_LINK).read_text(encoding="utf-8").strip()
        log = self.log_text()
        self.assertIn("TypeError: x is undefined", log)  # the log is the one read
        for secret in (old_owner, rotated["token"], link, out["secret"], key, answer, chat):
            self.assertNotIn(secret, log)


class TestClientLog(LogCase):
    """README "Logs": POST /api/client-log takes {kind, message, source, route, code, ua} from a joined person and
    appends a client entry; anonymous 401 unknown-session, over CLIENT_LOG_MAX bytes 413 body-too-large, a 21st entry
    within a minute 429 slow-down, an unknown key 400 bad-field, a message over 500 characters 400 too-long."""

    ENTRY = {"kind": "error", "message": "TypeError: x is undefined", "source": "/app.js:12", "route": "/", "ua": "chrome computer"}

    def test_a_joined_persons_entry_is_appended_as_a_client_entry(self):
        pid, guest = self.join("Ann")
        code, _, out = self.post("/api/client-log", self.ENTRY, guest)
        self.assertEqual((code, out), (200, {"ok": True}))
        line = self.entry_for(" client ")
        self.assertRegex(line, r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d,\d{3} WARNING client ")
        want = f'client pid={pid} kind=error message="TypeError: x is undefined" source=/app.js:12 route=/ ua="chrome computer"'
        self.assertTrue(line.endswith(want), line)

    def test_a_layout_readout_is_logged_as_a_client_entry_and_other_kinds_are_refused(self):
        pid, guest = self.join("Ann")
        readout = "sheet=vf-proposepop innerHeight=844 vvHeight=500 kb=344px dataKb=true sheetBottom=500 safeBottom=34px screenHeight=844"
        code, _, out = self.post("/api/client-log", {"kind": "layout", "message": readout, "ua": "safari phone"}, guest)
        self.assertEqual((code, out), (200, {"ok": True}))
        self.assertTrue(self.entry_for(" kind=layout ").endswith(f'client pid={pid} kind=layout message="{readout}" ua="safari phone"'))
        code, _, out = self.post("/api/client-log", {"kind": "debug", "message": readout}, guest)
        self.assertEqual((code, out["error"]), (400, "bad-field"))

    def test_a_lone_surrogate_in_a_message_still_reaches_the_log(self):
        _, guest = self.join("Ann")
        self.assertEqual(self.post("/api/client-log", {"kind": "error", "message": "cut-emoji-\ud83d"}, guest)[0], 200)
        self.assertIn("cut-emoji-\\ud83d", self.entry_for("cut-emoji-"))

    def test_a_message_cannot_forge_a_log_line(self):
        """U+2028 and U+2029 end a line for str.splitlines(): escaped, the forged request entry stays inside the
        client entry, and `logs --errors` shows one client entry and no request entry."""
        _, guest = self.join("Ann")
        forged = "2026-10-17 12:00:00,000 ERROR request method=POST route=/api/fake status=500 pid=host code=state-invalid"
        for sep in ("\u2028", "\u2029"):
            with self.subTest(sep=repr(sep)):
                self.assertEqual(self.post("/api/client-log", {"kind": "error", "message": f"boom{sep}{forged}"}, guest)[0], 200)
        log = self.log_text()
        self.assertEqual(len([line for line in log.splitlines() if "/api/fake" in line]), 2)
        self.assertFalse([line for line in log.splitlines() if line.startswith("2026-10-17 12:00:00")])
        code, out, err = share(self.d, "logs", "--errors")
        self.assertEqual(code, 0, err)
        self.assertEqual([" client " in line for line in out["lines"]], [True, True])
        self.assertFalse([line for line in out["lines"] if " request " in line.split("boom")[0]])

    def test_an_anonymous_caller_is_refused(self):
        code, _, out = self.post("/api/client-log", self.ENTRY)
        self.assertEqual((code, out["error"]), (401, "unknown-session"))
        self.assertNotIn(" client ", self.log_text())

    def test_an_oversize_body_is_refused_unread(self):
        _, guest = self.join("Ann")
        code, _, out = self.post("/api/client-log", {**self.ENTRY, "message": "x" * 5000}, guest)
        self.assertEqual((code, out["error"]), (413, "body-too-large"))

    def test_a_message_over_500_characters_and_an_unknown_key_are_refused(self):
        _, guest = self.join("Ann")
        code, _, out = self.post("/api/client-log", {**self.ENTRY, "message": "x" * 501}, guest)
        self.assertEqual((code, out["error"], out["field"]), (400, "too-long", "message"))
        code, _, out = self.post("/api/client-log", {**self.ENTRY, "text": "an answer"}, guest)
        self.assertEqual((code, out["error"], out["field"]), (400, "bad-field", "text"))
        self.assertNotIn(" client ", self.log_text())

    def test_the_twenty_first_entry_in_a_minute_is_refused(self):
        _, ann = self.join("Ann")
        _, bo = self.join("Bo")
        codes = [self.post("/api/client-log", self.ENTRY, ann)[0] for _ in range(20)]
        self.assertEqual(codes, [200] * 20)
        code, _, out = self.post("/api/client-log", self.ENTRY, ann)
        self.assertEqual((code, out["error"]), (429, "slow-down"))
        self.assertEqual(self.post("/api/client-log", self.ENTRY, bo)[0], 200)  # per person, not per address

    SUMMARY = {"kind": "summary", "message": "pv=0a1b2c3d lat:/api/vote=0,2 rb:/api/vote=1 gap=900", "ua": "safari phone"}

    def test_a_summary_and_the_heartbeat_sent_with_it_leave_no_lines_joined_by_time(self):
        """README "Logs": a page sends its summary as it sends a heartbeat, whose request entry names the person. The
        summary leaves no line of its own, no request entry either, until its batch: one entry with no pid and no time
        but the batch's own. Fault entries keep the pid."""
        pid, guest = self.join("Ann")
        before = len(self.log_text().splitlines())
        self.assertEqual(self.post("/api/heartbeat", {"visible": False}, guest)[0], 200)
        self.assertEqual(self.post("/api/client-log", self.SUMMARY, guest)[:3:2], (200, {"ok": True}))
        new = self.log_text().splitlines()[before:]
        self.assertEqual(len(new), 1, new)
        self.assertIn(" INFO request method=POST route=/api/heartbeat status=200 ms=", new[0])
        self.assertTrue(new[0].endswith(f" pid={pid}"), new[0])
        self.assertNotIn("pv=0a1b2c3d", self.log_text())
        self.app.flush_summaries()
        new = self.log_text().splitlines()[before:]
        self.assertEqual(len(new), 2, new)
        self.assertRegex(new[1], r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d,\d{3} INFO summary-batch summaries=1 dropped=0 data=")
        self.assertEqual(json.loads(new[1].split(" data=", 1)[1]), [[self.SUMMARY["message"], "safari phone"]])
        self.assertNotIn("pid=", new[1])
        self.assertEqual(self.post("/api/client-log", {**self.ENTRY, "fp": "1a2b3c4d"}, guest)[0], 200)
        self.assertTrue(self.entry_for(" kind=error ").endswith(f'client pid={pid} kind=error message="TypeError: x is undefined" source=/app.js:12 route=/ ua="chrome computer" fp=1a2b3c4d'))
        self.assertIn(f"pid={pid}", self.entry_for(" request method=POST route=/api/client-log "))

    def test_a_refused_summary_logs_no_pid(self):
        """A summary refused for its fields or its rate keeps its request entry, with no pid on it."""
        pid, guest = self.join("Ann")
        for body, code in (({**self.SUMMARY, "text": "x"}, 400), ({**self.SUMMARY, "message": "x" * 501}, 400), ({**self.SUMMARY, "ua": 7}, 400)):
            with self.subTest(body=sorted(body)):
                self.assertEqual(self.post("/api/client-log", body, guest)[0], code)
                line = self.entry_for(" request method=POST route=/api/client-log ")
                self.assertIn(f" status={code} ", line)
                self.assertNotIn("pid=", line)
        self.assertEqual([self.post("/api/client-log", self.SUMMARY, guest)[0] for _ in range(7)], [200] * 6 + [429])
        line = self.entry_for(" request method=POST route=/api/client-log ")
        self.assertIn(" status=429 ", line)
        self.assertNotIn(f"pid={pid}", line)

    def test_a_batch_holds_many_summaries_sorted_and_counts_those_past_its_size(self):
        """Arrival order is gone: Bo's summary, sent second, sorts first."""
        _, ann = self.join("Ann")
        _, bo = self.join("Bo")
        self.assertEqual(self.post("/api/client-log", {**self.SUMMARY, "message": "pv=ffff0000 gap=10"}, ann)[0], 200)
        self.assertEqual(self.post("/api/client-log", {**self.SUMMARY, "message": "pv=00000000 gap=20"}, bo)[0], 200)
        with mock.patch.object(server, "SUMMARY_BATCH_BYTES", 120):  # room for the two above (48 bytes each as batch JSON), not a third
            self.assertEqual(self.post("/api/client-log", {**self.SUMMARY, "message": "pv=11111111 gap=30"}, bo)[0], 200)
        self.app.flush_summaries()
        line = self.entry_for(" summary-batch ")
        self.assertIn(" summary-batch summaries=2 dropped=1 data=", line)
        self.assertEqual(json.loads(line.split(" data=", 1)[1]), [["pv=00000000 gap=20", "safari phone"], ["pv=ffff0000 gap=10", "safari phone"]])
        self.app.flush_summaries()
        self.assertEqual(self.log_text().count(" summary-batch "), 1)  # nothing held, nothing written

    def test_summaries_are_written_on_the_batch_cadence_and_at_shutdown(self):
        d = tmpdir(self)
        with mock.patch.object(server, "SUMMARY_BATCH_SECONDS", 1.5):
            app = server.App(d, watch_tunnel=False)
            app.serve()
            self.addCleanup(app.shutdown)
            _, _, out = call(app.guest_port, "POST", "/api/join", {"name": "Ann", "device": "computer", "key": app.session.state["session"]["guestKey"]})
            guest = {"X-Session-Secret": out["secret"]}

            def log():
                return (d / "server.log").read_text(encoding="utf-8")

            self.assertEqual(call(app.guest_port, "POST", "/api/client-log", self.SUMMARY, guest)[0], 200)
            self.assertTrue(wait_for(lambda: " summary-batch summaries=1 " in log(), seconds=10), log())
            self.assertEqual(call(app.guest_port, "POST", "/api/client-log", {**self.SUMMARY, "message": "pv=0a1b2c3d gap=5"}, guest)[0], 200)
            app.shutdown()
        self.assertEqual(log().count(" summary-batch summaries=1 "), 2, log())
        self.assertIn("gap=5", log().splitlines()[-1].replace("\\u0020", " "))

    def test_summaries_and_faults_have_separate_rate_buckets(self):
        """At most 6 summaries a minute per person, and a page in an error loop cannot starve them, or the reverse."""
        _, ann = self.join("Ann")
        self.assertEqual([self.post("/api/client-log", self.SUMMARY, ann)[0] for _ in range(6)], [200] * 6)
        code, _, out = self.post("/api/client-log", self.SUMMARY, ann)
        self.assertEqual((code, out["error"], out["message"]), (429, "slow-down", "At most 6 summaries a minute."))
        self.assertEqual([self.post("/api/client-log", self.ENTRY, ann)[0] for _ in range(20)], [200] * 20)
        self.assertEqual(self.post("/api/client-log", self.ENTRY, ann)[0], 429)
        _, bo = self.join("Bo")
        self.assertEqual([self.post("/api/client-log", self.ENTRY, bo)[0] for _ in range(20)], [200] * 20)
        self.assertEqual(self.post("/api/client-log", self.SUMMARY, bo)[0], 200)

    def test_client_entries_rotate_with_the_log_at_its_size(self):
        d = tmpdir(self)
        with mock.patch.object(server, "LOG_BYTES", 400):
            app = server.App(d, watch_tunnel=False)
            app.serve()
            self.addCleanup(app.shutdown)
            code, _, out = call(app.guest_port, "POST", "/api/join", {"name": "Ann", "device": "computer", "key": app.session.state["session"]["guestKey"]})
            guest = {"X-Session-Secret": out["secret"]}
            for i in range(20):
                call(app.guest_port, "POST", "/api/client-log", {"kind": "error", "message": f"entry-{i:02d}"}, guest)
        for h in app.log.handlers:
            h.flush()
        self.assertEqual(sorted(p.name for p in d.glob("server.log*")), ["server.log", "server.log.1", "server.log.2", "server.log.3"])
        self.assertIn("entry-19", (d / "server.log").read_text(encoding="utf-8"))


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


class TestModerationRoutes(ServerCase):
    """Phase 4c routes over HTTP: who may call them and what each viewer then reads."""

    def setUp(self):
        super().setUp()
        self.open_round("Q1")
        self.ann_pid, self.ann = self.join("Ann")
        self.bo_pid, self.bo = self.join("Bo")
        code, _, out = self.post("/api/answer", {"qid": "Q1", "text": "Original words", "view": "focus"}, self.ann)
        self.assertEqual(code, 200, out)
        self.ref = out["card"]

    def state(self, headers):
        code, _, snap = self.get("/api/state?since=0", headers)
        self.assertEqual(code, 200, snap)
        return snap

    def test_hide_and_edit_take_the_owner_token_and_history_stays_with_the_owner(self):
        for path, body in (("/api/card/hide", {"qid": "Q1", "card": self.ref, "on": True}), ("/api/card/edit", {"qid": "Q1", "card": self.ref, "text": "Kind words"})):
            code, _, out = self.post(path, body, self.bo)
            self.assertEqual((code, out["error"]), (403, "owner-only"))
        code, _, out = self.post("/api/card/edit", {"qid": "Q1", "card": self.ref, "text": "Kind words"}, self.owner)
        self.assertEqual(code, 200, out)
        for viewer in (self.ann, self.bo):
            raw = json.dumps(self.state(viewer))
            self.assertIn("Kind words", raw)
            self.assertNotIn("Original words", raw)
        owner_card = next(c for c in self.state(self.owner)["cards"]["Q1"] if c["ref"] == self.ref)
        self.assertEqual((owner_card["versions"], "history" in owner_card), (1, False))
        code, _, out = self.get(f"/api/card/history?qid=Q1&card={self.ref}", self.owner)
        self.assertEqual((code, [v["text"] for v in out["history"]]), (200, ["Original words"]))
        code, _, out = self.post("/api/card/hide", {"qid": "Q1", "card": self.ref, "on": True}, self.owner)
        self.assertEqual(code, 200, out)
        self.assertNotIn(self.ref, [c["ref"] for c in self.state(self.bo)["cards"]["Q1"]])
        self.assertEqual(next(c for c in self.state(self.ann)["cards"]["Q1"] if c["ref"] == self.ref)["hidden"]["by"], "host")

    def test_history_is_an_owner_only_get_for_one_card(self):
        self.post("/api/card/edit", {"qid": "Q1", "card": self.ref, "text": "Kind words"}, self.owner)
        for who in (self.ann, self.bo):
            code, _, out = self.get(f"/api/card/history?qid=Q1&card={self.ref}", who)
            self.assertEqual((code, out["error"]), (403, "owner-only"))
        code, _, out = self.get("/api/card/history?qid=Q1&card=p:nobody", self.owner)
        self.assertEqual((code, out["error"]), (404, "no-such-card"))

    def test_a_304_builds_no_snapshot(self):
        _, h, _ = self.get("/api/state?since=0", self.ann)
        with mock.patch.object(self.app.session, "snapshot", wraps=self.app.session.snapshot) as built:
            code, _, _ = self.get("/api/state?since=0", {**self.ann, "If-None-Match": h["ETag"]})
            self.assertEqual((code, built.call_count), (304, 0))
            self.post("/api/person/remove", {"pid": self.ann_pid, "on": True}, self.owner)
            code, _, out = self.get("/api/state?since=0", {**self.ann, "If-None-Match": h["ETag"]})
            self.assertEqual((code, out["error"]), (403, "removed"))

    def test_a_join_waits_for_the_owner_when_approval_is_on(self):
        code, _, out = self.post("/api/session/settings", {"approveJoins": True}, self.owner)
        self.assertEqual(code, 200, out)
        self.post("/api/session/intro", {"intro": "Why we meet."}, self.owner)
        code, _, out = self.post("/api/join", {"name": "Jib", "key": self.app.session.state["session"]["guestKey"]})
        self.assertEqual((code, out["waiting"]), (200, True))
        jib = {"X-Session-Secret": out["secret"]}
        code, _, err = self.get("/api/state?since=0", jib)
        self.assertEqual((code, err["error"]), (403, "waiting"))
        # The waiting page's one card: the title and the intro, and nothing else of the session.
        self.assertEqual({k: err.get(k) for k in ("title", "intro")}, {"title": self.state(self.ann)["title"], "intro": "Why we meet."})
        self.assertEqual(set(err) - {"error", "message", "title", "intro"}, set())
        self.assertEqual(self.state(self.ann)["me"]["pid"], self.ann_pid)  # a returning guest is not held
        code, _, err = self.post("/api/join/act", {"pid": out["pid"], "action": "admit"}, self.bo)
        self.assertEqual((code, err["error"]), (403, "owner-only"))
        code, _, done = self.post("/api/join/act", {"pid": out["pid"], "action": "admit"}, self.owner)
        self.assertEqual((code, done["status"]), (200, "active"))
        self.assertEqual(self.state(jib)["me"]["name"], "Jib")

    def test_chat_reactions_and_the_intro(self):
        code, _, out = self.post("/api/chat", {"text": "Hello"}, self.ann)
        mid = out["id"]
        code, _, out = self.post("/api/chat/react", {"id": mid, "emoji": "🎉", "on": True}, self.bo)
        self.assertEqual(code, 200, out)
        code, _, out = self.post("/api/chat/react", {"id": mid, "emoji": "<img>", "on": True}, self.bo)
        self.assertEqual((code, out["error"]), (400, "bad-field"))
        self.assertEqual(self.state(self.ann)["chat"][0]["reactions"], {"🎉": [self.bo_pid]})
        code, _, out = self.post("/api/session/intro", {"intro": "Why you're here."}, self.owner)
        self.assertEqual(code, 200, out)
        self.assertEqual(self.state(self.bo)["intro"], "Why you're here.")
        code, _, anon = self.get("/api/state")
        self.assertEqual(sorted(anon), ["ended", "joinNeedsKey", "title"])

    def test_the_owner_merges_a_second_identity_into_the_owner_and_its_secret_ends(self):
        code, _, out = self.post("/api/chat", {"text": "From my phone"}, self.bo)
        self.assertEqual(code, 200, out)
        code, _, out = self.post("/api/person/merge", {"from": self.bo_pid, "to": "host"}, self.owner)
        self.assertEqual((code, out["pid"]), (200, "host"))
        snap = self.state(self.owner)
        self.assertNotIn(self.bo_pid, [p["pid"] for p in snap["people"]])
        self.assertEqual([m["pid"] for m in snap["chat"]], ["host"])
        for code, _, out in (self.get("/api/state?since=0", self.bo), self.post("/api/heartbeat", {"visible": True}, self.bo)):
            self.assertEqual((code, out["error"], out["message"]), (401, "merged-into-owner", "This browser was merged into the owner. Open your owner link here."))

    def test_a_guest_merged_into_a_guest_reads_the_session_as_the_kept_person(self):
        code, _, out = self.post("/api/person/merge", {"from": self.bo_pid, "to": self.ann_pid}, self.owner)
        self.assertEqual(code, 200, out)
        self.assertEqual(self.state(self.bo)["me"]["pid"], self.ann_pid)

    def test_merging_the_owner_into_anyone_is_refused(self):
        code, _, out = self.post("/api/person/merge", {"from": "host", "to": self.ann_pid}, self.owner)
        self.assertEqual((code, out["error"], out["field"]), (400, "bad-field", "from"))
        code, _, out = self.post("/api/merge-request", {"to": "host"}, self.bo)
        self.assertEqual((code, out["error"]), (400, "bad-field"))


class TestPrototypePage(ServerCase):
    """Phase 7 (Q98): GET /proto/<qid> serves the prototype page for a prototype question only; an html variant stays
    a sandboxed asset (scripts, no same origin) that only the session's own pages may frame; POST /api/annotate is a
    person route under the JSON, body-cap and write-rate rules."""

    VARIANT_HTML = b"<!doctype html><html><body><main><button>Pay now</button></main></body></html>"

    def setUp(self):
        super().setUp()
        (self.d / "v1.html").write_bytes(self.VARIANT_HTML)
        (self.d / "v2.png").write_bytes(PNG)
        code, _, out = self.ops({"op": "add-asset", "path": str(self.d / "v1.html")}, {"op": "add-asset", "path": str(self.d / "v2.png")})
        self.assertEqual(code, 200, out)
        self.html, self.png = (r["id"] for r in out["results"])
        proto = {**text_q("Q1"), "format": {"kind": "prototype", "variants": [{"id": "v-1", "label": "One page", "asset": self.html}, {"id": "v-2", "label": "Two steps", "asset": self.png}]}}
        code, _, out = self.ops({"op": "open-round", "questions": [proto, text_q("Q2")]})
        self.assertEqual(code, 200, out)
        _, self.guest = self.join("Ann")

    def test_the_page_is_served_for_a_prototype_question_only(self):
        code, h, body = self.get("/proto/Q1")
        self.assertEqual((code, h["Content-Type"], h["Content-Security-Policy"], h["X-Frame-Options"]), (200, "text/html; charset=utf-8", PAGE_CSP, "DENY"))
        self.assertIn(b'<script src="/proto.js"></script>', body)
        for path in ("/proto/Q2", "/proto/Q9", "/proto/Q1/", "/proto/q1", "/proto/Q1x", "/proto/"):
            with self.subTest(path=path):
                self.assertEqual(self.get(path)[0], 404)
        code, h, _ = self.get("/proto.js")
        self.assertEqual((code, h["Content-Type"]), (200, "text/javascript; charset=utf-8"))

    def test_an_html_variant_is_sandboxed_and_framable_by_the_session_only(self):
        code, h, body = self.get(f"/assets/{self.html}", self.guest)
        self.assertEqual((code, h["Content-Security-Policy"], h["X-Frame-Options"], body), (200, HTML_ASSET_CSP, "SAMEORIGIN", self.VARIANT_HTML))
        self.assertNotIn("allow-same-origin", h["Content-Security-Policy"])
        code, h, _ = self.get(f"/assets/{self.png}?pin=1", self.guest)
        self.assertEqual((code, h["Content-Security-Policy"], h["X-Frame-Options"]), (200, "sandbox", "DENY"))

    def test_pin_1_appends_the_pin_helper_as_the_one_inline_script(self):
        _, h, body = self.get(f"/assets/{self.html}?pin=1", self.guest)
        self.assertEqual(h["Content-Security-Policy"], HTML_ASSET_CSP)
        self.assertTrue(body.startswith(self.VARIANT_HTML))
        helper = (server.WEB / "proto-pin.js").read_bytes()
        self.assertEqual(body[len(self.VARIANT_HTML):], b"\n<script>" + helper + b"</script>\n")
        self.assertEqual(self.get(f"/assets/{self.png}?pin=1", self.guest)[2], PNG)

    def test_a_pin_helper_that_could_end_or_hide_its_script_element_is_refused(self):
        for text in ("x</script>", "x</SCRIPT >", "x<!-- y", "x<script>", "x<ScRiPt src=a>"):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                server.pin_helper(text)
        self.assertEqual(server.pin_helper("post({ type: 'ready' });"), "post({ type: 'ready' });")

    def test_annotate_is_a_person_route_under_the_json_cap_and_rate_rules(self):
        note = {"qid": "Q1", "variant": "v-1", "text": "Hard to find", "anchor": {"selector": "html > body:nth-of-type(1)", "rect": {"x": 0, "y": 0, "w": 50, "h": 10}}}
        code, _, out = self.post("/api/annotate", note)
        self.assertEqual((code, out["error"]), (401, "unknown-session"))
        code, _, out = self.post("/api/annotate", note, self.guest)
        self.assertEqual((code, out["ok"], out["id"]), (200, True, "A1"))
        code, _, out = self.post("/api/annotate", {**note, "text": "Again"}, self.guest)
        self.assertEqual((code, out["error"]), (429, "slow-down"))
        code, _, out = self.post("/api/annotate", {**note, "text": "x" * (33 * 1024)}, self.guest)
        self.assertEqual((code, out["error"], out["max"]), (413, "body-too-large", 32 * 1024))
        code, _, out = call(self.port, "POST", "/api/annotate", raw=json.dumps(note).encode(), headers={**self.guest, "Content-Type": "text/plain"})
        self.assertEqual((code, out["error"]), (415, "json-required"))
        code, _, out = self.post("/api/annotate", {**note, "anchor": {"selector": "body.x", "rect": note["anchor"]["rect"]}}, self.guest)
        self.assertEqual((code, out["error"], out["field"]), (400, "bad-field", "anchor.selector"))
        notes = self.get("/api/state", self.guest)[2]["annotations"]
        self.assertEqual([(a["id"], a["text"]) for a in notes], [("A1", "Hard to find")])


class TestConnectYourClaude(ServerCase):
    """Phase 8 (R2-12, C18-C20): a guest's `runner: self` request runs on their own Claude through the four
    /api/mine/requests* routes. It never reaches the owner's queue or the control channel, and only the requester's
    own secret reads, claims, answers or fails it. Expected values come from the Design's request rules and routes."""

    def setUp(self):
        super().setUp()
        self.open_round("Q1")
        _, self.ann = self.join("Ann")
        _, self.bo = self.join("Bo")
        code, _, out = self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": "Which step drops most?", "runner": "self"}, self.ann)
        self.assertEqual(code, 200, out)
        self.rid = out["id"]

    def control(self, path):
        return call(self.app.control_port, "GET", path, headers={"X-Shared-Token": self.app.hub.token})

    def test_a_self_request_answered_through_the_mine_routes_makes_no_control_event(self):
        self.assertEqual(self.post("/api/mine/requests/claim", {"id": self.rid}, self.ann)[0], 200)
        body = {"id": self.rid, "summary": "The address step.", "sources": [{"title": "Notes", "url": "https://example.com/n"}], "report": "", "used": [], "why": "Mine."}
        self.assertEqual(self.post("/api/mine/requests/result", body, self.ann)[0], 200)
        code, _, status = self.control("/api/status")
        self.assertEqual((code, status["unhandled"], status["queue"]["requests"]), (200, 0, 0))
        self.assertEqual(json.loads((self.d / "state.json").read_text(encoding="utf-8"))["log"]["events"], [])
        owner = self.get("/api/state", self.owner)[2]
        self.assertEqual((owner["requests"], owner["requestCounts"]), ([], {"open": 0, "byQ": {}}))
        self.assertNotIn("Q1", self.get("/api/state", self.bo)[2]["results"])  # waits for the owner's Publish
        (res,) = self.get("/api/state", self.ann)[2]["results"]["Q1"]
        self.assertEqual(self.post("/api/request/act", {"action": "publish", "id": res["id"]}, self.owner)[0], 200)
        (res,) = self.get("/api/state", self.bo)[2]["results"]["Q1"]
        self.assertEqual((res["summary"], res["by"]["kind"]), ("The address step.", "guest-claude"))

    def test_another_persons_secret_cannot_read_claim_answer_or_fail_it(self):
        body = {"id": self.rid, "summary": "Bo's answer.", "sources": [], "report": "", "used": [], "why": ""}
        for who in (self.bo, self.owner):
            self.assertEqual(self.get("/api/mine/requests", who)[2]["requests"], [])
            for path, b in (("claim", {"id": self.rid}), ("result", body), ("fail", {"id": self.rid, "reason": "Mine now."})):
                with self.subTest(path=path, who=sorted(who)):
                    code, _, out = self.post(f"/api/mine/requests/{path}", b, who)
                    self.assertEqual((code, out["error"]), (404, "no-such-request"))
        self.assertNotIn("Which step drops most?", json.dumps(self.get("/api/state", self.bo)[2]))
        self.assertEqual(self.get("/api/mine/requests?status=pending", self.ann)[2]["requests"][0]["status"], {"kind": "pending"})

    def test_the_mine_routes_need_an_identity_and_json(self):
        for path in ("claim", "result", "fail"):
            self.assertEqual(self.post(f"/api/mine/requests/{path}", {"id": self.rid})[0], 401)
        code, _, out = call(self.port, "POST", "/api/mine/requests/claim", raw=json.dumps({"id": self.rid}).encode(), headers={**self.ann, "Content-Type": "text/plain"})
        self.assertEqual((code, out["error"]), (415, "json-required"))

    def test_a_second_claim_within_a_second_is_slowed(self):
        self.assertEqual(self.post("/api/mine/requests/claim", {"id": self.rid}, self.ann)[0], 200)
        code, _, out = self.post("/api/mine/requests/claim", {"id": self.rid}, self.ann)
        self.assertEqual((code, out["error"]), (429, "slow-down"))


class TestWatcherKey(ServerCase):
    """Fix 3 of the Phase 8 security review: what a guest pastes into their own Claude is a watcher key, not their
    session secret. It works on GET /api/mine/requests and the three POST /api/mine/requests/* routes only, for its own
    person's requests, until revoked; every other route answers 401 to it. Expected values: the review's requirements."""

    def setUp(self):
        super().setUp()
        self.open_round("Q1")
        self.ann_pid, self.ann = self.join("Ann")
        _, self.bo = self.join("Bo")
        code, _, out = self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": "Which step drops most?", "runner": "self"}, self.ann)
        self.assertEqual(code, 200, out)
        self.rid = out["id"]
        code, _, out = self.post("/api/watcher", {}, self.ann)
        self.assertEqual(code, 200, out)
        self.key = {"X-Watcher-Key": out["token"]}
        self.token = out["token"]

    def test_the_watcher_key_reads_and_answers_its_own_persons_self_requests(self):
        code, _, out = self.get("/api/mine/requests?status=pending", self.key)
        self.assertEqual((code, [r["id"] for r in out["requests"]]), (200, [self.rid]))
        self.assertEqual(self.post("/api/mine/requests/claim", {"id": self.rid}, self.key)[0], 200)
        body = {"id": self.rid, "summary": "The address step.", "sources": [], "report": "", "used": [], "why": ""}
        self.assertEqual(self.post("/api/mine/requests/result", body, self.key)[0], 200)
        self.assertNotIn(self.token, (self.d / "state.json").read_text(encoding="utf-8"))
        self.assertTrue(self.get("/api/state", self.ann)[2]["me"]["watcher"])

    def test_the_watcher_key_is_refused_on_every_other_route(self):
        for headers in (self.key, {"X-Session-Secret": self.token}):
            with self.subTest(path="/api/state", header=next(iter(headers))):
                self.assertEqual(self.get("/api/state", headers)[0], 401)
            for path, body in (
                ("/api/notifications/read", {}),
                ("/api/chat", {"text": "hi"}),
                ("/api/answer", {"qid": "Q1", "text": "Mine"}),
                ("/api/vote", {"qid": "Q1", "ref": "x"}),
                ("/api/request", {"qid": "Q1", "kind": "ask", "text": "More", "runner": "self"}),
                ("/api/heartbeat", {}),
                ("/api/watcher", {}),
                ("/api/watcher/revoke", {}),
                ("/api/rename", {"name": "Eve"}),
            ):
                with self.subTest(path=path, header=next(iter(headers))):
                    self.assertEqual(self.post(path, body, headers)[0], 401)
        self.assertEqual(self.get("/api/mine/requests", self.key)[0], 200)  # still good after all of that

    def test_revoke_ends_the_watcher_key(self):
        self.assertEqual(self.post("/api/watcher/revoke", {}, self.ann)[0], 200)
        self.assertEqual(self.get("/api/mine/requests", self.key)[0], 401)
        self.assertEqual(self.post("/api/mine/requests/claim", {"id": self.rid}, self.key)[0], 401)
        self.assertFalse(self.get("/api/state", self.ann)[2]["me"]["watcher"])

    def test_a_removed_and_restored_persons_old_key_stays_dead(self):
        self.assertEqual(self.post("/api/person/remove", {"pid": self.ann_pid, "on": True}, self.owner)[0], 200)
        self.assertEqual(self.post("/api/person/remove", {"pid": self.ann_pid, "on": False}, self.owner)[0], 200)
        code, _, out = self.get("/api/mine/requests", self.key)
        self.assertEqual((code, out["error"]), (401, "unknown-session"))
        self.assertFalse(self.get("/api/state", self.ann)[2]["me"]["watcher"])

    def test_the_owner_is_refused_a_watcher_key(self):
        code, _, out = self.post("/api/watcher", {}, self.owner)
        self.assertEqual((code, out["error"]), (403, "guests-only"))

    def test_another_persons_watcher_key_cannot_touch_these_requests(self):
        code, _, out = self.post("/api/watcher", {}, self.bo)
        bo_key = {"X-Watcher-Key": out["token"]}
        self.assertEqual(self.get("/api/mine/requests", bo_key)[2]["requests"], [])
        body = {"id": self.rid, "summary": "Bo's answer.", "sources": [], "report": "", "used": [], "why": ""}
        for path, b in (("claim", {"id": self.rid}), ("result", body), ("fail", {"id": self.rid, "reason": "Mine now."})):
            with self.subTest(path=path):
                code, _, out = self.post(f"/api/mine/requests/{path}", b, bo_key)
                self.assertEqual((code, out["error"]), (404, "no-such-request"))


class TestReports(ServerCase):
    """Report a problem over HTTP. Expected values come from the approved V1 (feedback triage row 38): POST /api/report
    is a person route whose picture is png, jpeg or webp up to 512 KB with its own body cap, allowed while uploads are
    off; reports, their pictures, Seen, Resolved and Ask are the owner's; only the owner's Ask wakes the watcher."""

    CTX = {"view": "focus", "device": "phone", "browser": "safari", "viewport": {"w": 390, "h": 844}, "errors": []}

    def setUp(self):
        super().setUp()
        self.open_round("Q1")
        self.ann_pid, self.ann = self.join("Ann")

    def report(self, who, image=None, text="Send does nothing"):
        return self.post("/api/report", {"text": text, "ctx": {**self.CTX, "qid": "Q1"}, **({"image": image} if image else {})}, who)

    @staticmethod
    def data_url(kind, data):
        return f"data:image/{kind};base64,{base64.b64encode(data).decode()}"

    def test_a_512_kb_screenshot_goes_through_with_uploads_off_and_the_owners_ask_wakes_the_watcher(self):
        self.assertFalse(self.app.session.state["session"]["settings"]["uploads"])
        shot = b"\xff\xd8\xff" + b"\x00" * (512 * 1024 - 3)
        code, _, out = self.report(self.ann, self.data_url("jpeg", shot))
        self.assertEqual((code, out["id"]), (200, "F1"), out)
        self.assertEqual((self.d / "reports" / "F1.jpg").read_bytes(), shot)
        self.assertEqual(self.app.session.state["log"]["events"], [])
        code, _, out = self.post("/api/report/act", {"id": "F1", "action": "ask"}, self.ann)
        self.assertEqual((code, out["error"]), (403, "owner-only"))
        code, _, out = self.post("/api/report/act", {"id": "F1", "action": "ask"}, self.owner)
        self.assertEqual((code, out["asked"]), (200, True), out)
        code, _, out = call(self.app.control_port, "GET", "/api/wait?after=handled&timeout=5", headers={"X-Shared-Token": self.app.hub.token}, timeout=20)
        self.assertEqual([(e["kind"], e["report"], e["qid"], e["text"]) for e in out["events"]], [("report-filed", "F1", "Q1", "Send does nothing")])
        code, _, out = self.post("/api/upload/offer", {"file": "a.png", "size": 10, "type": "image/png"}, self.ann)
        self.assertEqual((code, out["error"]), (403, "uploads-off"))

    def test_a_body_past_the_report_cap_is_refused_before_it_is_read(self):
        code, _, out = call(self.port, "POST", "/api/report", raw=b"{}", headers={"Content-Type": "application/json", "Content-Length": str(session.REPORT_MAX + 1), **self.ann})
        self.assertEqual((code, out["error"], out["max"]), (413, "body-too-large", session.REPORT_MAX))

    def test_a_picture_one_byte_past_512_kb_or_of_another_kind_is_refused(self):
        code, _, out = self.report(self.ann, self.data_url("png", PNG + b"\x00" * (512 * 1024 + 1 - len(PNG))))
        self.assertEqual((code, out["error"]), (413, "upload-too-large"))
        code, _, out = self.report(self.ann, self.data_url("png", b"GIF89a" + b"\x00" * 40))
        self.assertEqual((code, out["error"]), (415, "file-type"))
        self.assertEqual(self.app.session.state.get("reports", {}), {})

    def test_only_the_owner_reads_reports_their_pictures_and_marks_them(self):
        self.report(self.ann, self.data_url("png", PNG))
        self.assertNotIn("reports", self.get("/api/state", self.ann)[2])
        code, _, out = self.get("/api/report/image?id=F1", self.ann)
        self.assertEqual((code, out["error"]), (403, "owner-only"))
        code, _, out = self.post("/api/report/act", {"id": "F1", "action": "seen"}, self.ann)
        self.assertEqual((code, out["error"]), (403, "owner-only"))
        mine = self.get("/api/state", self.owner)[2]["reports"]
        self.assertEqual([(r["id"], r["by"], r["status"], r["image"]) for r in mine], [("F1", self.ann_pid, "open", True)])
        self.assertNotIn("reports/F1", json.dumps(mine))
        code, _, out = self.get("/api/report/image?id=F1", self.owner)
        self.assertEqual((code, out["image"]), (200, self.data_url("png", PNG)))
        code, _, out = self.post("/api/report/act", {"id": "F1", "action": "seen"}, self.owner)
        self.assertEqual((code, out["status"]), (200, "seen"))
        self.assertEqual([n["kind"] for n in self.get("/api/state", self.ann)[2]["me"]["notifications"]][-1], "report")


    def test_a_reporter_adds_a_screenshot_to_their_report_which_only_the_owner_reads_back(self):
        self.report(self.ann)
        bo_pid, bo = self.join("Bo")
        code, _, out = self.post("/api/report/add", {"id": "F1", "text": "me too"}, bo)
        self.assertEqual((code, out["error"]), (404, "not-found"))
        code, _, out = self.post("/api/report/add", {"id": "F1", "text": "On Q2 as well", "image": self.data_url("png", PNG)}, self.ann)
        self.assertEqual((code, out["adds"]), (200, 1), out)
        mine = self.get("/api/state?since=0", self.ann)[2]["myReports"]
        self.assertEqual([(r["id"], r["status"], [(a["text"], a["image"]) for a in r["adds"]]) for r in mine], [("F1", "open", [("On Q2 as well", True)])])
        self.assertEqual(self.get("/api/state?since=0", bo)[2]["myReports"], [])
        code, _, out = self.get("/api/report/image?id=F1&add=1", self.ann)
        self.assertEqual((code, out["error"]), (403, "owner-only"))
        code, _, out = self.get("/api/report/image?id=F1&add=1", self.owner)
        self.assertEqual((code, out["image"]), (200, self.data_url("png", PNG)))
        code, _, out = self.get("/api/report/image?id=F1&add=%C2%B2", self.owner)  # "²", a Unicode digit
        self.assertEqual((code, out["error"]), (400, "bad-field"))

class TestUploads(ServerCase):
    """Phase 9 routes: /api/upload/offer, /api/upload/act, /api/upload/chunk. Expected values come from the Design's
    Guest listener routes (offer cap 96 KB; chunk raw bytes with X-Upload-Id, X-Chunk-Index, X-Chunk-Total,
    X-Chunk-Sha256 and X-File-Sha256 on the last; a repeat answers {received}; a gap is 409 chunk-gap), the Upload
    rules (tmp and stored never on the wire), the Brief's upload criteria (AC 21 decline discards, AC 40 chunked with
    resume and a whole-file hash check) and the Phase 9 security brief (sizes checked before a body is read; files in
    the private data folder, never under a served path). Chunks are 1024 bytes here; hashes are sha256 of the bytes."""

    CHUNK = 1024
    DATA = b"%PDF-1.7\n" + bytes(range(256)) * 9 + b"%%EOF"  # 2318 bytes: chunks of 1024, 1024 and 270

    def setUp(self):
        super().setUp()
        for name, value in (("CHUNK_SIZE", self.CHUNK), ("CHUNK_INTERVAL", 0.0)):
            patcher = mock.patch.object(session, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.open_round("Q1")
        code, _, out = self.post("/api/session/settings", {"uploads": True}, self.owner)
        self.assertEqual(code, 200, out)
        self.ann_pid, self.ann = self.join("Ann")
        self.bo_pid, self.bo = self.join("Bo")

    def offer(self, who, name="funnel.pdf", data=DATA):
        code, _, out = self.post("/api/upload/offer", {"file": name, "size": len(data), "type": "application/pdf", "qid": "Q1"}, who)
        self.assertEqual(code, 200, out)
        return out["id"]

    def accepted(self, who, name="funnel.pdf", data=DATA):
        uid = self.offer(who, name, data)
        if who is not self.owner:
            code, _, out = self.post("/api/upload/act", {"id": uid, "action": "accept"}, self.owner)
            self.assertEqual((code, out["status"]), (200, "accepted"), out)
        return uid

    def chunk_headers(self, who, uid, index, piece, data=DATA, sha=None, whole=None):
        total = -(-len(data) // self.CHUNK)
        h = {"Content-Type": "application/octet-stream", "X-Upload-Id": uid, "X-Chunk-Index": str(index), "X-Chunk-Total": str(total),
             "X-Chunk-Sha256": sha or hashlib.sha256(piece).hexdigest(), **who}
        if index == total - 1:
            h["X-File-Sha256"] = whole or hashlib.sha256(data).hexdigest()
        return h

    def chunk(self, who, uid, index, data=DATA, **kw):
        piece = data[index * self.CHUNK:(index + 1) * self.CHUNK]
        return call(self.port, "POST", "/api/upload/chunk", raw=piece, headers=self.chunk_headers(who, uid, index, piece, data, **kw))

    def mine(self, who, uid):
        return next(u for u in self.get("/api/state?since=0", who)[2]["myUploads"] if u["id"] == uid)

    def files(self, sub):
        d = self.d / "uploads" / sub
        return sorted(p.name for p in d.iterdir()) if d.is_dir() else []

    def test_upload_resume_after_dropped_chunk(self):
        uid = self.accepted(self.ann)
        code, _, out = self.chunk(self.ann, uid, 0)
        self.assertEqual((code, out["received"]), (200, 1), out)
        piece = self.DATA[self.CHUNK:2 * self.CHUNK]
        head = "".join(f"{k}: {v}\r\n" for k, v in {"Host": f"127.0.0.1:{self.port}", "Content-Length": str(len(piece)), **self.chunk_headers(self.ann, uid, 1, piece)}.items())
        raw_exchange(self.port, f"POST /api/upload/chunk HTTP/1.1\r\n{head}\r\n".encode() + piece[:300], wait=0.5)  # the connection drops mid-piece
        self.assertEqual(wait_for(lambda: uid not in self.app.session._sending, seconds=5), True)
        self.assertEqual(self.mine(self.ann, uid)["status"], {"kind": "uploading", "received": 1, "bytes": self.CHUNK})
        code, _, out = self.chunk(self.ann, uid, 2)
        self.assertEqual((code, out["error"], out["received"]), (409, "chunk-gap", 1))
        code, _, out = self.chunk(self.ann, uid, 0)  # a repeat of a piece the server has is answered, not written
        self.assertEqual((code, out["received"], out["repeat"]), (200, 1, True))
        for i in (1, 2):
            code, _, out = self.chunk(self.ann, uid, i)
            self.assertEqual(code, 200, out)
        self.assertEqual(out, {"ok": True, "received": 3, "status": "done"})
        self.assertEqual(self.mine(self.ann, uid)["status"], {"kind": "done", "sha256": hashlib.sha256(self.DATA).hexdigest()})
        (stored,) = self.files("accepted")
        self.assertEqual((self.d / "uploads" / "accepted" / stored).read_bytes(), self.DATA)
        ev = [e for e in self.app.session.state["log"]["events"] if e["kind"] == "upload-received"]
        self.assertEqual([(e["upload"], e["file"], e["stored"], e["qid"]) for e in ev], [(uid, "funnel.pdf", f"uploads/accepted/{stored}", "Q1")])
        self.assertEqual(self.files("pending"), [])

    def test_upload_hash_mismatch_rejected(self):
        uid = self.accepted(self.ann)
        code, _, out = self.chunk(self.ann, uid, 0, sha="0" * 64)
        self.assertEqual((code, out["error"], out["field"]), (400, "hash-mismatch", "X-Chunk-Sha256"))
        self.assertEqual(self.mine(self.ann, uid)["status"]["kind"], "accepted")
        for i in (0, 1):
            self.assertEqual(self.chunk(self.ann, uid, i)[0], 200)
        code, _, out = self.chunk(self.ann, uid, 2, whole=hashlib.sha256(b"another file").hexdigest())
        self.assertEqual((code, out["error"], out["field"]), (400, "hash-mismatch", "X-File-Sha256"))
        self.assertEqual(self.mine(self.ann, uid)["status"]["kind"], "failed")
        self.assertEqual((self.files("pending"), self.files("accepted")), ([], []))
        self.assertEqual([e for e in self.app.session.state["log"]["events"] if e["kind"] == "upload-received"], [])

    def test_upload_decline_discards(self):
        uid = self.accepted(self.ann)
        self.assertEqual(self.chunk(self.ann, uid, 0)[0], 200)
        self.assertEqual(len(self.files("pending")), 1)
        code, _, out = self.post("/api/upload/act", {"id": uid, "action": "decline"}, self.bo)
        self.assertEqual((code, out["error"]), (403, "owner-only"))
        code, _, out = self.post("/api/upload/act", {"id": uid, "action": "decline"}, self.owner)
        self.assertEqual((code, out["status"]), (200, "declined"))
        self.assertEqual(self.files("pending"), [])
        self.assertEqual(self.mine(self.ann, uid)["status"]["kind"], "declined")
        code, _, out = self.chunk(self.ann, uid, 1)
        self.assertEqual((code, out["error"], out["status"]), (409, "wrong-status", "declined"))
        offered = self.offer(self.bo)
        code, _, out = self.post("/api/upload/act", {"id": offered, "action": "decline"}, self.owner)
        self.assertEqual((code, out["status"]), (200, "declined"))

    def test_snapshot_never_exposes_upload_paths(self):
        lee_pid, lee = self.join("Lee")
        self.leader(lee_pid)
        done = self.accepted(self.ann)
        for i in range(3):
            self.assertEqual(self.chunk(self.ann, done, i)[0], 200)
        code, _, out = self.post("/api/answer", {"qid": "Q1", "text": "The funnel.", "view": "focus", "attachments": [done]}, self.ann)
        self.assertEqual(code, 200, out)
        time.sleep(session.WRITE_INTERVAL)
        sending = self.accepted(self.ann, name="b.pdf")
        self.assertEqual(self.chunk(self.ann, sending, 0)[0], 200)
        offered = self.offer(self.bo)
        time.sleep(session.WRITE_INTERVAL)
        declined = self.accepted(self.bo, name="c.pdf")
        self.assertEqual(self.chunk(self.bo, declined, 0)[0], 200)
        self.post("/api/upload/act", {"id": declined, "action": "decline"}, self.owner)
        own = self.accepted(self.owner, name="notes.zip")
        st = self.app.session.state
        secrets_on_disk = [v for u in st["uploads"] for k, v in u["status"].items() if k in ("tmp", "stored")] + [str(self.d), str(self.d.resolve()), "uploads/"]
        self.assertGreaterEqual(len(secrets_on_disk), 4)
        for role, who in (("owner", self.owner), ("leader", lee), ("uploader", self.ann), ("other guest", self.bo), ("anonymous", {})):
            with self.subTest(role=role):
                code, _, snap = self.get("/api/state?since=0", who)
                self.assertEqual(code, 200)
                keys, stack = set(), [snap]
                while stack:
                    x = stack.pop()
                    if isinstance(x, dict):
                        keys |= set(x)
                        stack += list(x.values())
                    elif isinstance(x, list):
                        stack += x
                self.assertFalse({"tmp", "stored"} & keys, role)
                text = json.dumps(snap)
                for s in secrets_on_disk:
                    self.assertNotIn(s, text)
        owner_view = self.get("/api/state?since=0", self.owner)[2]
        self.assertEqual({u["id"] for u in owner_view["uploads"]}, {done, sending, offered, declined, own})
        self.assertEqual(self.get("/api/state?since=0", self.bo)[2]["files"], {done: {"file": "funnel.pdf", "ext": "pdf", "size": len(self.DATA), "status": "done"}})

    def test_a_received_picture_reads_back_only_where_its_item_shows(self):
        pic = b"\x89PNG\r\n\x1a\n" + bytes(1100)  # 1108 bytes: chunks of 1024 and 84
        shown = self.accepted(self.ann, name="a.png", data=pic)
        hidden = self.accepted(self.bo, name="b.png", data=pic)
        for who, uid in ((self.ann, shown), (self.bo, hidden)):
            for i in range(2):
                self.assertEqual(self.chunk(who, uid, i, pic)[0], 200)
        for uid in (shown, hidden):
            self.assertEqual(self.post("/api/upload/act", {"id": uid, "action": "approve"}, self.owner)[0], 200)
            time.sleep(session.WRITE_INTERVAL)
        code, _, out = self.post("/api/chat", {"text": "Look", "attachments": [shown]}, self.ann)
        self.assertEqual(code, 200, out)
        time.sleep(session.WRITE_INTERVAL)
        code, _, out = self.post("/api/discussion", {"qid": "Q1", "text": "Mine", "attachments": [hidden]}, self.bo)
        self.assertEqual(code, 200, out)
        self.assertEqual(self.post("/api/discussion/hide", {"qid": "Q1", "id": out["id"], "on": True}, self.owner)[0], 200)
        url = "data:image/png;base64," + base64.b64encode(pic).decode()
        code, headers, out = self.get(f"/api/upload/image?id={shown}", self.bo)
        self.assertEqual((code, out, headers["X-Content-Type-Options"], headers["Content-Type"]), (200, {"ok": True, "id": shown, "image": url}, "nosniff", "application/json; charset=utf-8"))
        code, _, out = self.get(f"/api/upload/image?id={hidden}", self.ann)
        self.assertEqual((code, out["error"]), (404, "not-found"))
        self.assertEqual(self.get(f"/api/upload/image?id={hidden}", self.bo)[2]["image"], url)
        self.assertEqual(self.get(f"/api/upload/image?id={hidden}", self.owner)[2]["image"], url)
        self.assertEqual(self.get(f"/api/upload/image?id={shown}", {})[0], 401)

    def test_reading_pictures_back_is_rate_limited_per_person(self):
        pic = b"\x89PNG\r\n\x1a\n" + bytes(100)
        uid = self.accepted(self.ann, name="a.png", data=pic)
        self.assertEqual(self.chunk(self.ann, uid, 0, pic)[0], 200)
        self.assertEqual(self.post("/api/upload/act", {"id": uid, "action": "approve"}, self.owner)[0], 200)
        self.assertEqual(self.post("/api/chat", {"text": "Look", "attachments": [uid]}, self.ann)[0], 200)
        self.assertEqual(server.IMAGE_PER_MINUTE, 120)
        self.app.image_bucket = server.Bucket(0, 2)  # no refill: two reads, then the limit
        self.assertEqual([self.get(f"/api/upload/image?id={uid}", self.bo)[0] for _ in range(2)], [200, 200])
        code, _, out = self.get(f"/api/upload/image?id={uid}", self.bo)
        self.assertEqual((code, out["error"]), (429, "slow-down"))
        self.assertEqual(self.get(f"/api/upload/image?id={uid}", self.ann)[0], 200)  # another person's count is their own
        self.app.image_bucket = server.Bucket(0, 9)
        self.assertEqual(self.get("/api/upload/image?id=U9-00000000", self.bo)[2]["error"], "not-found")

    def test_sizes_are_checked_before_any_body_is_read(self):
        uid = self.accepted(self.ann)
        h = self.chunk_headers(self.ann, uid, 0, b"")
        for length, want in ((self.CHUNK + 1, 413), (10, 400)):
            with self.subTest(length=length):
                head = "".join(f"{k}: {v}\r\n" for k, v in {"Host": f"127.0.0.1:{self.port}", **h, "Content-Length": str(length)}.items())
                t0 = time.monotonic()
                got, _ = raw_exchange(self.port, f"POST /api/upload/chunk HTTP/1.1\r\n{head}\r\n".encode(), wait=3.0)
                self.assertEqual(status_and_headers(got)[0], want)
                self.assertLess(time.monotonic() - t0, 2.5)  # answered without waiting for a body that never comes
        code, _, out = self.post("/api/upload/offer", {"file": "a.pdf", "size": 1, "type": "", "pad": "x" * session.OFFER_MAX})
        self.assertEqual((code, out["error"], out["max"]), (413, "body-too-large", 96 * 1024))

    def test_one_piece_per_person_is_read_at_a_time(self):
        first = self.accepted(self.ann)
        time.sleep(session.WRITE_INTERVAL)
        second = self.accepted(self.ann, name="b.pdf")
        piece = self.DATA[:self.CHUNK]
        head = "".join(f"{k}: {v}\r\n" for k, v in {"Host": f"127.0.0.1:{self.port}", "Content-Length": str(len(piece)), **self.chunk_headers(self.ann, first, 0, piece)}.items())
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as slow:
            slow.sendall(f"POST /api/upload/chunk HTTP/1.1\r\n{head}\r\n".encode() + piece[:10])  # a sender that stalls
            self.assertTrue(wait_for(lambda: self.ann_pid in self.app._chunk_readers, seconds=5))
            code, _, out = self.chunk(self.ann, second, 0)
            self.assertEqual((code, out["error"], out["status"]), (409, "wrong-status", "sending"))
            self.assertEqual(self.chunk(self.bo, self.accepted(self.bo), 0)[0], 200)  # another person is not held up
        self.assertTrue(wait_for(lambda: self.ann_pid not in self.app._chunk_readers, seconds=5))
        self.assertEqual(self.chunk(self.ann, second, 0)[0], 200)

    def test_only_the_uploader_sends_raw_bytes(self):
        uid = self.accepted(self.ann)
        piece = self.DATA[:self.CHUNK]
        h = self.chunk_headers(self.ann, uid, 0, piece)
        anon = {k: v for k, v in h.items() if k != "X-Session-Secret"}
        self.assertEqual(call(self.port, "POST", "/api/upload/chunk", raw=piece, headers=anon)[0], 401)
        code, _, out = call(self.port, "POST", "/api/upload/chunk", raw=piece, headers={**h, "Content-Type": "application/json"})
        self.assertEqual((code, out["error"]), (415, "bytes-required"))
        code, _, out = call(self.port, "POST", "/api/upload/chunk", raw=piece, headers={**h, **self.bo})
        self.assertEqual((code, out["error"]), (404, "no-such-upload"))
        code, _, out = call(self.port, "POST", "/api/upload/chunk", raw=piece, headers={**h, "X-Upload-Id": "../../state.json"})
        self.assertEqual((code, out["error"], out["field"]), (400, "bad-field", "X-Upload-Id"))

    def test_uploads_off_refuses_an_offer(self):
        self.post("/api/session/settings", {"uploads": False}, self.owner)
        code, _, out = self.post("/api/upload/offer", {"file": "a.pdf", "size": 3, "type": ""}, self.ann)
        self.assertEqual((code, out["error"]), (403, "uploads-off"))

    def test_received_files_stay_in_the_private_data_folder_and_are_never_served(self):
        uid = self.accepted(self.ann, name="shot.png", data=PNG + bytes(100))
        self.assertEqual(self.chunk(self.ann, uid, 0, data=PNG + bytes(100))[0], 200)
        (stored,) = self.files("accepted")
        for path in (f"/uploads/accepted/{stored}", f"/assets/{stored}", f"/{stored}"):
            with self.subTest(path=path):
                self.assertEqual(self.get(path)[0], 404)
        self.assertFalse(any(p.name == stored for p in server.WEB.rglob("*")))
        if not WINDOWS:
            for p in (self.d / "uploads", self.d / "uploads" / "accepted", self.d / "uploads" / "accepted" / stored):
                self.assertEqual(stat.S_IMODE(p.stat().st_mode), 0o600 if p.is_file() else 0o700, p)

    def test_a_restart_deletes_partial_files_no_upload_names(self):
        uid = self.accepted(self.ann)
        self.assertEqual(self.chunk(self.ann, uid, 0)[0], 200)
        stray = self.d / "uploads" / "pending" / ("e" * 32)
        stray.write_bytes(b"left by a crash")
        self.app.shutdown()
        again = server.App(self.d, watch_tunnel=False)
        self.addCleanup(again.shutdown)
        self.assertFalse(stray.exists())
        self.assertEqual(len(self.files("pending")), 1)
        self.assertEqual(next(u for u in again.session.state["uploads"] if u["id"] == uid)["status"]["received"], 1)


class TestDiscussion(ServerCase):
    """A Discussion under each question: anyone who may write comments, its author edits or deletes their own, the
    owner hides any, "@Claude" files an owner-gated ask, unread is per person, and the digest carries it."""

    def setUp(self):
        super().setUp()
        self.open_round("Q1", "Q2")
        self.ann_pid, self.ann = self.join("Ann")
        self.bo_pid, self.bo = self.join("Bo")

    def say(self, who, text, qid="Q1"):
        code, _, out = self.post("/api/discussion", {"qid": qid, "text": text}, who)
        self.assertEqual(code, 200, out)
        return out

    def comments(self, who, qid="Q1"):
        return self.get("/api/state", who)[2]["discussions"].get(qid, [])

    def test_a_comment_shows_to_everyone_and_another_persons_cannot_be_edited_deleted_or_hidden_by_a_guest(self):
        cid = self.say(self.ann, "Pinned on phones too?")["id"]
        self.assertEqual([(c["id"], c["pid"], c["text"]) for c in self.comments(self.bo)], [(cid, self.ann_pid, "Pinned on phones too?")])
        self.assertEqual([c["id"] for c in self.comments(self.owner)], [cid])
        for path, body in (("/api/discussion/edit", {"text": "Bo's words"}), ("/api/discussion/delete", {})):
            code, _, out = self.post(path, {"qid": "Q1", "id": cid, **body}, self.bo)
            self.assertEqual((code, out["error"]), (404, "not-found"), path)
        self.assertEqual(self.post("/api/discussion/hide", {"qid": "Q1", "id": cid, "on": True}, self.bo)[2]["error"], "owner-only")
        self.assertEqual([c["text"] for c in self.comments(self.ann)], ["Pinned on phones too?"])
        self.assertEqual(self.post("/api/discussion", {"qid": "Q9", "text": "x"}, self.bo)[0], 404)
        self.assertEqual(self.post("/api/discussion", {"qid": "Q1", "text": "x" * 2001}, self.bo)[2]["error"], "too-long")
        self.assertEqual(self.post("/api/discussion", {"qid": "Q1", "text": "hi"})[0], 401)

    def test_its_author_edits_and_deletes_their_own_and_the_same_text_writes_nothing(self):
        cid = self.say(self.ann, "First thought")["id"]
        code, _, out = self.post("/api/discussion/edit", {"qid": "Q1", "id": cid, "text": "Second thought"}, self.ann)
        self.assertEqual((code, out["edited"]), (200, True))
        (c,) = self.comments(self.bo)
        self.assertEqual(c["text"], "Second thought")
        self.assertIn("edited", c)
        time.sleep(1.05)
        rev = self.app.session.state["rev"]
        self.assertEqual(self.post("/api/discussion/edit", {"qid": "Q1", "id": cid, "text": "Second thought"}, self.ann)[2]["edited"], False)
        self.assertEqual(self.app.session.state["rev"], rev)
        self.assertEqual(self.post("/api/discussion/delete", {"qid": "Q1", "id": cid}, self.ann)[0], 200)
        self.assertEqual(self.comments(self.bo), [])
        self.assertEqual(self.post("/api/discussion/delete", {"qid": "Q1", "id": cid}, self.ann)[0], 429)  # one a second, then gone
        time.sleep(1.05)
        self.assertEqual(self.post("/api/discussion/delete", {"qid": "Q1", "id": cid}, self.ann)[0], 404)

    def test_the_owner_hides_any_comment_its_author_sees_it_marked_and_no_one_else_sees_it(self):
        cid = self.say(self.ann, "Off topic")["id"]
        keep = self.say(self.bo, "On topic")["id"]
        code, _, out = self.post("/api/discussion/hide", {"qid": "Q1", "id": cid, "on": True}, self.owner)
        self.assertEqual((code, out["hidden"]), (200, True))
        self.assertEqual([c["id"] for c in self.comments(self.bo)], [keep])
        self.assertNotIn("Off topic", json.dumps(self.get("/api/state", self.bo)[2]))
        self.assertEqual([(c["id"], "hidden" in c) for c in self.comments(self.owner)], [(cid, True), (keep, False)])
        self.assertEqual([(c["id"], "hidden" in c) for c in self.comments(self.ann)], [(cid, True), (keep, False)])
        time.sleep(1.05)
        rev = self.app.session.state["rev"]
        self.assertEqual(self.post("/api/discussion/hide", {"qid": "Q1", "id": cid, "on": True}, self.owner)[2]["hidden"], True)
        self.assertEqual(self.app.session.state["rev"], rev)  # already hidden: nothing written
        time.sleep(1.05)
        self.post("/api/discussion/hide", {"qid": "Q1", "id": cid, "on": False}, self.owner)
        self.assertEqual([c["id"] for c in self.comments(self.bo)], [cid, keep])

    def test_each_route_takes_one_write_a_second_per_person(self):
        self.say(self.ann, "one")
        code, _, out = self.post("/api/discussion", {"qid": "Q1", "text": "two"}, self.ann)
        self.assertEqual((code, out["error"]), (429, "slow-down"))
        self.say(self.bo, "Bo's own limit")
        self.assertEqual(len(self.comments(self.bo)), 2)

    def test_reactions_use_the_chat_set_and_a_no_op_writes_nothing(self):
        cid = self.say(self.ann, "React here")["id"]
        self.assertEqual(self.post("/api/discussion/react", {"qid": "Q1", "id": cid, "emoji": "👍", "on": True}, self.bo)[0], 200)
        self.assertEqual(self.comments(self.ann)[0]["reactions"], {"👍": [self.bo_pid]})
        self.assertEqual(self.post("/api/discussion/react", {"qid": "Q1", "id": cid, "emoji": "🦄", "on": True}, self.bo)[0], 400)
        time.sleep(1.05)
        rev = self.app.session.state["rev"]
        self.post("/api/discussion/react", {"qid": "Q1", "id": cid, "emoji": "👍", "on": True}, self.bo)
        self.assertEqual(self.app.session.state["rev"], rev)

    def test_new_counts_per_person_and_reading_marks_only_what_the_page_saw(self):
        first = self.say(self.ann, "One")["id"]
        self.assertEqual(self.get("/api/state", self.ann)[2]["me"]["discussionSeen"]["Q1"], self.app.session.state["discussions"]["Q1"][0]["at"])
        self.assertEqual(self.get("/api/state", self.bo)[2]["me"]["discussionSeen"], {})
        time.sleep(0.01)
        self.say(self.owner, "Two")
        at = {c["id"]: c["at"] for c in self.app.session.state["discussions"]["Q1"]}
        self.assertEqual(self.post("/api/discussion/read", {"qid": "Q1", "at": at[first]}, self.bo)[2]["read"], True)
        self.assertEqual(self.get("/api/state", self.bo)[2]["me"]["discussionSeen"], {"Q1": at[first]})  # "Two" is still new to Bo
        time.sleep(1.05)
        rev = self.app.session.state["rev"]
        self.assertEqual(self.post("/api/discussion/read", {"qid": "Q1", "at": at[first]}, self.bo)[2]["read"], False)
        self.assertEqual(self.app.session.state["rev"], rev)
        time.sleep(1.05)
        self.post("/api/discussion/read", {"qid": "Q1", "at": 9e12}, self.bo)  # never past the newest comment
        self.assertEqual(self.get("/api/state", self.bo)[2]["me"]["discussionSeen"], {"Q1": max(at.values())})
        self.assertEqual(self.post("/api/discussion/read", {"qid": "Q1", "at": "soon"}, self.bo)[0], 400)

    def test_new_comments_notify_the_people_already_in_it_and_a_mention_notifies_once(self):
        self.say(self.ann, "Start")
        self.say(self.bo, "Reply, @Ann")
        notes = self.get("/api/state", self.ann)[2]["me"]["notifications"]
        self.assertEqual([(n["kind"], n["qid"]) for n in notes if n["kind"] in ("mention", "discussion")], [("mention", "Q1")])
        self.say(self.owner, "Host here")
        notes = self.get("/api/state", self.ann)[2]["me"]["notifications"]
        disc = [n for n in notes if n["kind"] == "discussion"]
        self.assertEqual([(n["title"], n["qid"]) for n in disc], [("1 new comment in the Discussion on question Q1.", "Q1")])
        self.assertEqual([n["title"] for n in self.get("/api/state", self.bo)[2]["me"]["notifications"] if n["kind"] == "discussion"], ["1 new comment in the Discussion on question Q1."])

    def test_at_claude_files_an_owner_gated_ask_and_the_hosts_runs_at_once(self):
        out = self.say(self.ann, "@Claude what do other shops do on phones?")
        rid = out["request"]
        req = next(r for r in self.get("/api/state", self.owner)[2]["requests"] if r["id"] == rid)
        self.assertEqual((req["kind"], req["runner"], req["status"]["kind"], req["pid"], req["qid"]), ("ask", "host", "pending", self.ann_pid, "Q1"))
        self.assertEqual(self.comments(self.bo)[0]["request"], rid)
        self.assertEqual([i["key"] for i in self.get("/api/state", self.ann)[2]["inbox"]], [rid])
        self.assertNotIn("request", self.say(self.bo, "Claude without the at sign"))
        host = self.say(self.owner, "@claude summarize this thread")
        hreq = next(r for r in self.get("/api/state", self.owner)[2]["requests"] if r["id"] == host["request"])
        self.assertEqual(hreq["status"]["kind"], "running")  # the host's own request skips Run

    def test_the_digest_carries_each_questions_discussion_without_hidden_comments_names_only_with_digest_names(self):
        self.say(self.ann, "Pin it on phones")
        hidden = self.say(self.bo, "Off topic")["id"]
        self.say(self.owner, "@Claude check the big shops")
        self.post("/api/discussion/hide", {"qid": "Q1", "id": hidden, "on": True}, self.owner)
        self.post("/api/round/send", {}, self.owner)
        ev = next(e for e in self.app.session.state["log"]["events"] if e["kind"] == "round-sent")
        q1 = next(q for q in ev["digest"]["questions"] if q["id"] == "Q1")
        self.assertEqual(q1["discussion"], [{"text": "Pin it on phones"}, {"text": "@Claude check the big shops", "askedClaude": True}])
        self.assertNotIn("discussion", next(q for q in ev["digest"]["questions"] if q["id"] == "Q2"))
        self.assertEqual(self.post("/api/session/settings", {"digestNames": True}, self.owner)[0], 200)
        named = next(q for q in self.app.session._digest(1)["questions"] if q["id"] == "Q1")["discussion"]
        self.assertEqual([c.get("by") for c in named], ["Ann", self.app.session.state["people"]["host"]["name"]])

    def test_an_edit_to_a_hidden_comment_notifies_no_mention_and_carries_no_excerpt(self):
        cid = self.say(self.ann, "Off topic")["id"]
        self.post("/api/discussion/hide", {"qid": "Q1", "id": cid, "on": True}, self.owner)
        self.assertEqual(self.post("/api/discussion/edit", {"qid": "Q1", "id": cid, "text": "Secret words for @Bo"}, self.ann)[0], 200)
        notes = self.get("/api/state", self.bo)[2]["me"]["notifications"]
        self.assertEqual([n for n in notes if n.get("comment") == cid], [])
        self.assertNotIn("Secret words", json.dumps(self.get("/api/state", self.bo)[2]))

    def test_the_caps_count_only_visible_comments_and_one_person_holds_at_most_their_own_share(self):
        with mock.patch.object(session, "MAX_COMMENTS", 2), mock.patch.object(session, "MAX_MY_COMMENTS", 2):
            cid = self.say(self.ann, "One")["id"]
            self.post("/api/discussion/hide", {"qid": "Q1", "id": cid, "on": True}, self.owner)
            self.say(self.bo, "Bo's")
            time.sleep(1.05)
            self.say(self.ann, "Two")  # the hidden one no longer fills the question
            time.sleep(1.05)
            code, _, out = self.post("/api/discussion", {"qid": "Q1", "text": "Three"}, self.ann)
            self.assertEqual((code, out["error"]), (409, "too-many-comments"))  # Ann's own two, the hidden one too
            code, _, out = self.post("/api/discussion", {"qid": "Q1", "text": "Kim's"}, self.owner)
            self.assertEqual((code, out["error"]), (409, "discussion-full"))
            time.sleep(1.05)
            self.say(self.ann, "On Q2", qid="Q2")  # the per-person cap is per question

    def test_at_claude_past_the_pending_cap_posts_the_comment_and_says_no_request_was_filed(self):
        with mock.patch.object(session, "MAX_PENDING_REQUESTS", 1):
            self.assertEqual(self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": "first"}, self.ann)[0], 200)
            time.sleep(1.05)  # past the request route's one a second, which the comment's request shares
            out = self.say(self.ann, "@Claude and this too?")
        self.assertNotIn("request", out)
        self.assertEqual(out["requestRefused"], "too-many-pending")
        self.assertEqual([c["text"] for c in self.comments(self.bo)], ["@Claude and this too?"])
        self.assertEqual(len(self.app.session.state["requests"]), 1)

    def test_at_claude_naming_a_participant_called_claude_files_no_request(self):
        claude_pid = self.claude_from_before()
        out = self.say(self.ann, "@Claude can you check the copy?")
        self.assertNotIn("request", out)
        self.assertEqual(self.comments(self.bo)[0]["text"], f"<@{claude_pid}> can you check the copy?")
        self.assertEqual(self.app.session.state["requests"], [])

    def test_more_than_two_hundred_stored_comments_on_one_question_load_when_some_are_hidden(self):
        t = time.time()
        with self.app.session._tx() as st:
            st["discussions"]["Q1"] = [
                {"id": f"D{i}", "pid": self.ann_pid, "text": f"c{i}", "at": t + i, **({"hidden": {"by": "host", "at": t + i}} if i < 5 else {})}
                for i in range(1, 206)
            ]
        self.assertIsNone(session.document_error(self.app.session.state))
        again = session.Session.load(self.app.session.path)
        self.assertEqual(len(again.state["discussions"]["Q1"]), 205)

    def test_at_claude_inside_a_word_or_an_address_files_no_request(self):
        for who, text in ((self.ann, "@Claudette can you look?"), (self.bo, "Mail x@claude.ai about it")):
            self.assertNotIn("request", self.say(who, text), text)
        self.assertEqual(self.app.session.state["requests"], [])

    def test_a_guests_at_claude_leaves_the_owner_no_queue_note(self):
        self.assertIn("request", self.say(self.ann, "@Claude what do shops do?"))
        self.assertEqual([n for n in self.app.session.state["notifications"].get("host", []) if n["kind"] == "queue"], [])

    def test_at_claude_in_a_comment_shares_the_request_limit_and_still_posts(self):
        self.assertEqual(self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": "first"}, self.ann)[0], 200)
        out = self.say(self.ann, "@Claude and this?")
        self.assertEqual((out.get("requestRefused"), "request" in out), ("slow-down", False))
        self.assertEqual(len(self.app.session.state["requests"]), 1)
        time.sleep(1.05)
        self.assertIn("request", self.say(self.bo, "@Claude from Bo"))
        self.assertEqual(self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": "again"}, self.bo)[0], 429)

    def test_posting_marks_read_only_when_no_one_elses_comment_is_unseen(self):
        self.say(self.ann, "One")
        time.sleep(0.01)
        self.say(self.bo, "Two")
        self.assertEqual(self.get("/api/state", self.bo)[2]["me"]["discussionSeen"], {})  # Ann's One is still new to Bo
        at = {c["text"]: c["at"] for c in self.app.session.state["discussions"]["Q1"]}
        self.post("/api/discussion/read", {"qid": "Q1", "at": at["Two"]}, self.bo)
        time.sleep(1.05)
        self.say(self.bo, "Three")
        three = self.app.session.state["discussions"]["Q1"][-1]["at"]
        self.assertEqual(self.get("/api/state", self.bo)[2]["me"]["discussionSeen"], {"Q1": three})

    def test_a_hidden_comment_names_no_removed_person_in_the_snapshot(self):
        cid = self.say(self.ann, "Ask @Bo")["id"]
        self.post("/api/discussion/hide", {"qid": "Q1", "id": cid, "on": True}, self.owner)
        self.assertEqual(self.post("/api/person/remove", {"pid": self.bo_pid, "on": True}, self.owner)[0], 200)
        self.assertNotIn(self.bo_pid, self.get("/api/state", self.owner)[2]["mentions"])
        time.sleep(1.05)
        self.post("/api/discussion/hide", {"qid": "Q1", "id": cid, "on": False}, self.owner)
        self.assertIn(self.bo_pid, self.get("/api/state", self.owner)[2]["mentions"])

    def test_reading_stops_at_the_newest_comment_this_viewer_sees(self):
        self.say(self.ann, "One")
        time.sleep(0.01)
        cid = self.say(self.bo, "Two")["id"]
        self.post("/api/discussion/hide", {"qid": "Q1", "id": cid, "on": True}, self.owner)
        self.post("/api/discussion/read", {"qid": "Q1", "at": 9e12}, self.ann)
        one = self.app.session.state["discussions"]["Q1"][0]["at"]
        self.assertEqual(self.get("/api/state", self.ann)[2]["me"]["discussionSeen"], {"Q1": one})

    def test_the_digest_clips_each_comment_and_holds_a_total_budget(self):
        self.say(self.ann, "a" * 2000)
        self.say(self.bo, "b" * 2000)
        self.say(self.owner, "c" * 2000)
        with mock.patch.object(session, "MAX_DIGEST_DISCUSSION_CHARS", 1000, create=True):
            q1 = next(q for q in self.app.session._digest(1)["questions"] if q["id"] == "Q1")
        self.assertEqual([c["text"] for c in q1["discussion"]], ["b" * 500, "c" * 500])
        self.assertEqual(q1["discussionMore"], "1 earlier comments on the page")

    def test_a_comment_sent_to_claude_cannot_be_edited_but_can_be_deleted(self):
        cid = self.say(self.ann, "@Claude what do shops do?")["id"]
        code, _, out = self.post("/api/discussion/edit", {"qid": "Q1", "id": cid, "text": "Changed"}, self.ann)
        self.assertEqual((code, out["error"]), (409, "sent-to-claude"))
        self.assertEqual(self.post("/api/discussion/delete", {"qid": "Q1", "id": cid}, self.ann)[0], 200)

    def test_hiding_a_comment_declines_its_waiting_request(self):
        out = self.say(self.ann, "@Claude what do shops do?")
        self.post("/api/discussion/hide", {"qid": "Q1", "id": out["id"], "on": True}, self.owner)
        req = next(r for r in self.app.session.state["requests"] if r["id"] == out["request"])
        self.assertEqual(req["status"]["kind"], "declined")
        notes = self.app.session.state["notifications"][self.ann_pid]
        self.assertIn("Your request on question Q1 was declined.", [n["title"] for n in notes])

    def test_a_merge_moves_comments_reactions_and_seen_marks_to_the_kept_person(self):
        cid = self.say(self.bo, "Bo's comment")["id"]
        self.post("/api/discussion/react", {"qid": "Q1", "id": cid, "emoji": "👍", "on": True}, self.ann)
        self.assertEqual(self.post("/api/person/merge", {"from": self.bo_pid, "to": self.ann_pid}, self.owner)[0], 200)
        (c,) = self.comments(self.ann)
        self.assertEqual((c["pid"], c["reactions"]), (self.ann_pid, {"👍": [self.ann_pid]}))
        self.assertIn("Q1", self.get("/api/state", self.ann)[2]["me"]["discussionSeen"])



class TestGeneralAsk(ServerCase):
    """"@Claude" in chat, and Ask Claude's "About the whole session", file a request with no question: owner-gated as
    any guest request, answered by the `result` op with no qid, and once shared, Claude's chat message."""

    def setUp(self):
        super().setUp()
        self.open_round("Q1")
        self.ann_pid, self.ann = self.join("Ann")
        self.bo_pid, self.bo = self.join("Bo")

    def chat(self, who, text):
        code, _, out = self.post("/api/chat", {"text": text}, who)
        self.assertEqual(code, 200, out)
        return out

    def req(self, rid):
        return next(r for r in self.app.session.state["requests"] if r["id"] == rid)

    def answer(self, rid, summary="Most shops pin it."):
        code, _, out = self.ops({"op": "result", "request": rid, "kind": "ask", "used": [], "why": "", "summary": summary, "sources": [], "report": ""})
        self.assertEqual(code, 200, out)
        return out["results"][0]

    def test_at_claude_in_chat_files_a_general_ask_that_waits_for_the_owners_run(self):
        out = self.chat(self.ann, "@Claude what have we settled so far?")
        r = self.req(out["request"])
        self.assertNotIn("qid", r)
        self.assertEqual((r["kind"], r["runner"], r["status"]["kind"], r["pid"]), ("ask", "host", "pending", self.ann_pid))
        self.assertEqual([m.get("request") for m in self.get("/api/state", self.bo)[2]["chat"]], [out["request"]])
        (mine,) = self.get("/api/state", self.ann)[2]["inbox"]
        self.assertEqual((mine["key"], mine.get("qid"), mine["scope"]), (out["request"], None, "session"))
        run = next(i for i in self.get("/api/state", self.owner)[2]["inbox"] if i["kind"] == "run")
        self.assertEqual((run["id"], run.get("qid"), run["scope"]), (out["request"], None, "session"))
        self.assertFalse([e for e in self.app.session.state["log"]["events"] if e["kind"] == "request-run"])
        self.post("/api/request/act", {"action": "run", "ids": [out["request"]]}, self.owner)
        (ev,) = [e for e in self.app.session.state["log"]["events"] if e["kind"] == "request-run"]
        self.assertEqual(ev["requests"], [{"id": out["request"], "scope": "session", "from": "chat", "kind": "ask", "text": "@Claude what have we settled so far?"}])

    def test_the_owners_own_at_claude_in_chat_runs_at_once(self):
        out = self.chat(self.owner, "@claude sum up the session")
        self.assertEqual(self.req(out["request"])["status"]["kind"], "running")
        (ev,) = [e for e in self.app.session.state["log"]["events"] if e["kind"] == "request-run"]
        self.assertEqual(ev["requests"], [{"id": out["request"], "scope": "session", "from": "chat", "kind": "ask", "text": "@claude sum up the session"}])

    def test_the_answer_replies_to_the_asking_message_even_once_chat_dropped_it_from_its_scan(self):
        asked = self.chat(self.owner, "@Claude where are we?")
        self.assertEqual(self.req(asked["request"])["msg"], asked["id"])
        with self.app.session._tx() as st:  # its request still names the message, whatever chat holds after it
            st["chat"][:] = [m for m in st["chat"] if m["id"] == asked["id"]]
            st["chat"][0].pop("request")
        self.answer(asked["request"], "Halfway.")
        self.assertEqual(self.app.session.state["chat"][-1]["replyTo"]["id"], asked["id"])

    def test_at_claude_in_chat_matches_only_the_word(self):
        claude_pid = self.claude_from_before()
        for who, text in ((self.ann, "@Claudette can you look?"), (self.bo, "Mail x@claude.ai about it")):
            self.assertNotIn("request", self.chat(who, text), text)
        time.sleep(1.05)
        self.assertNotIn("request", self.chat(self.ann, "@Claude can you check the copy?"))  # the person called Claude
        self.assertEqual(self.app.session.state["requests"], [])
        self.assertEqual(self.app.session.state["chat"][-1]["text"], f"<@{claude_pid}> can you check the copy?")
        self.post("/api/person/remove", {"pid": claude_pid, "on": True}, self.owner)
        self.assertIn("request", self.chat(self.bo, "(@Claude, check the copy)"))  # with no one called Claude, the word asks

    def test_a_refused_chat_request_still_posts_the_message(self):
        self.assertEqual(self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": "first"}, self.ann)[0], 200)
        out = self.chat(self.ann, "@Claude and this?")
        self.assertEqual((out.get("requestRefused"), "request" in out), ("slow-down", False))
        with mock.patch.object(session, "MAX_PENDING_REQUESTS", 1):
            time.sleep(1.05)
            out = self.chat(self.ann, "@Claude and this too?")
        self.assertEqual((out.get("requestRefused"), "request" in out), ("too-many-pending", False))
        self.assertEqual([m["text"] for m in self.get("/api/state", self.bo)[2]["chat"]], ["@Claude and this?", "@Claude and this too?"])
        self.assertEqual(len(self.app.session.state["requests"]), 1)

    def test_shared_answer_replies_in_the_chat_thread_and_guests_see_nothing_before_the_share(self):
        self.assertEqual(self.post("/api/session/settings", {"reviewAnswers": True}, self.owner)[0], 200)
        asked = self.chat(self.ann, "@Claude what have we settled?")
        self.post("/api/request/act", {"action": "run", "ids": [asked["request"]]}, self.owner)
        res = self.answer(asked["request"], "Pinned headers, and the copy still open.")
        self.assertEqual(res["published"], False)
        for who in (self.ann, self.bo):
            snap = self.get("/api/state", who)[2]
            self.assertNotIn("Pinned headers", json.dumps(snap))
        owner = self.get("/api/state", self.owner)[2]
        self.assertEqual([x["id"] for x in owner["results"]["session"]], [res["id"]])
        share = next(i for i in owner["inbox"] if i["kind"] == "share")
        self.assertEqual((share.get("qid"), share["scope"]), (None, "session"))
        self.assertEqual(self.post("/api/request/act", {"action": "publish", "id": res["id"]}, self.owner)[0], 200)
        chat = self.get("/api/state", self.bo)[2]["chat"]
        reply = chat[-1]
        self.assertEqual((reply["pid"], reply["claude"], reply["text"]), ("host", {"result": res["id"]}, "Pinned headers, and the copy still open."))
        self.assertEqual(reply["replyTo"]["id"], asked["id"])
        self.assertEqual(self.get("/api/state", self.bo)[2]["results"]["session"][0]["msg"], reply["id"])
        note = next(n for n in self.app.session.state["notifications"][self.ann_pid] if n["kind"] == "request")
        self.assertEqual((note["title"], note["msg"]), ("Your request about the session is done.", reply["id"]))
        self.assertEqual(next(i for i in self.get("/api/state", self.ann)[2]["inbox"] if i["key"] == asked["request"])["status"], "shared")
        self.post("/api/round/send", {}, self.owner)
        ev = next(e for e in self.app.session.state["log"]["events"] if e["kind"] == "round-sent")
        self.assertEqual(ev["digest"]["results"], [{"scope": "session", "id": res["id"], "kind": "ask", "summary": "Pinned headers, and the copy still open."}])

    def test_the_hosts_own_general_answer_is_shared_into_chat_at_once(self):
        asked = self.chat(self.owner, "@Claude where are we?")
        res = self.answer(asked["request"], "Halfway.")
        self.assertEqual(res["published"], True)
        reply = self.get("/api/state", self.ann)[2]["chat"][-1]
        self.assertEqual((reply["text"], reply["replyTo"]["id"]), ("Halfway.", asked["id"]))

    def test_ask_claude_about_the_whole_session_files_a_general_request_and_its_answer_posts_to_chat(self):
        code, _, out = self.post("/api/request", {"scope": "session", "kind": "research", "text": "What do other teams do?"}, self.ann)
        self.assertEqual(code, 200, out)
        self.assertNotIn("qid", self.req(out["id"]))
        self.assertEqual(self.post("/api/request", {"scope": "session", "qid": "Q1", "kind": "ask", "text": "x"}, self.bo)[2]["field"], "qid")
        time.sleep(1.05)
        self.assertEqual(self.post("/api/request", {"scope": "session", "kind": "ask", "text": "x", "runner": "self"}, self.bo)[2]["field"], "runner")
        self.post("/api/request/act", {"action": "run", "ids": [out["id"]]}, self.owner)
        res = self.answer(out["id"], "Three patterns.")
        self.post("/api/request/act", {"action": "publish", "id": res["id"]}, self.owner)
        reply = self.get("/api/state", self.bo)[2]["chat"][-1]
        self.assertEqual((reply["text"], reply["claude"], "replyTo" in reply), ("Three patterns.", {"result": res["id"]}, False))

    def test_the_result_op_keeps_a_general_answer_and_a_question_answer_apart(self):
        general = self.chat(self.ann, "@Claude what now?")["request"]
        time.sleep(1.05)
        on_q1 = self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": "On Q1"}, self.ann)[2]["id"]
        self.post("/api/request/act", {"action": "run", "ids": [general, on_q1]}, self.owner)
        base = {"op": "result", "kind": "ask", "used": [], "why": "", "summary": "s", "sources": [], "report": ""}
        for op, field in (({**base, "request": general, "qid": "Q1"}, "qid"), ({**base, "request": on_q1}, "qid"), (base, "qid")):
            code, _, out = self.ops(op)
            self.assertEqual((code, out.get("field")), (400, field), op)
        self.assertEqual(self.ops({**base, "request": on_q1, "qid": "Q1"})[0], 200)

    def test_with_chat_off_a_shared_general_answer_stays_out_of_chat(self):
        self.assertEqual(self.post("/api/session/settings", {"chat": False}, self.owner)[0], 200)
        code, _, out = self.post("/api/request", {"scope": "session", "kind": "ask", "text": "Where are we?"}, self.owner)
        self.assertEqual(code, 200, out)
        res = self.answer(out["id"], "Halfway.")
        self.assertEqual(res["published"], True)
        self.assertEqual(self.app.session.state["chat"], [])
        (x,) = self.get("/api/state", self.ann)[2]["results"]["session"]
        self.assertEqual((x["summary"], "msg" in x), ("Halfway.", False))

    def test_declining_a_general_request_tells_its_asker_about_the_session(self):
        rid = self.chat(self.ann, "@Claude anything?")["request"]
        self.post("/api/request/act", {"action": "decline", "id": rid}, self.owner)
        titles = [n["title"] for n in self.app.session.state["notifications"][self.ann_pid]]
        self.assertIn("Your request about the session was declined.", titles)

    def test_claudes_chat_message_tells_no_one_of_reactions_or_replies_and_is_no_proposal(self):
        rid = self.chat(self.owner, "@Claude where are we?")["request"]
        self.answer(rid, "Halfway.")
        mid = self.app.session.state["chat"][-1]["id"]
        self.assertEqual(self.post("/api/chat/react", {"id": mid, "emoji": "👍", "on": True}, self.ann)[0], 200)
        time.sleep(1.05)
        self.assertEqual(self.post("/api/chat", {"text": "Thanks", "replyTo": mid}, self.ann)[0], 200)
        self.assertEqual([n for n in self.app.session.state["notifications"].get("host", []) if n["kind"] in ("reaction", "reply")], [])
        self.assertEqual(self.app.session.state["chat"][-1]["replyTo"], {"id": mid, "pid": "host", "excerpt": "Halfway.", "claude": True})  # quoted as Claude's on every page
        code, _, out = self.post("/api/chat/propose", {"id": mid}, self.owner)
        self.assertEqual((code, out["error"]), (409, "wrong-status"))

    def test_a_state_holding_general_requests_and_results_is_valid_and_loads_again(self):
        rid = self.chat(self.ann, "@Claude where are we?")["request"]
        self.post("/api/request/act", {"action": "run", "ids": [rid]}, self.owner)
        self.answer(rid, "Halfway.")
        self.assertIsNone(session.document_error(self.app.session.state))
        again = session.Session.load(self.app.session.path)
        self.assertEqual([x["request"] for x in again.state["results"]["session"]], [rid])
        with self.app.session._tx() as st:  # a result filed under the wrong place does not load
            st["results"]["Q1"] = st["results"].pop("session")
            self.assertIn("names another place", " ".join(session.cross_field_errors(st)))
            st["results"]["session"] = st["results"].pop("Q1")


class TestSharingDefault(ServerCase):
    """Owner decision 2026-10-19: Claude's answer to a request on a question is shared there when it arrives; Ask
    offers Everyone or Just me; a Just me answer reaches only its asker and the owner until one of them shares it; the
    owner takes any shared answer down; "Review Claude's answers before they are shared" restores the owner's Share."""

    def setUp(self):
        super().setUp()
        self.open_round("Q1")
        self.ann_pid, self.ann = self.join("Ann")
        self.bo_pid, self.bo = self.join("Bo")

    def ask(self, who, text="How do others do it?", **extra):
        code, _, out = self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": text, **extra}, who)
        self.assertEqual(code, 200, out)
        return out["id"]

    def go(self, rid):
        self.assertEqual(self.post("/api/request/act", {"action": "run", "ids": [rid]}, self.owner)[0], 200)

    def answer(self, rid, summary="Most shops pin it.", qid="Q1", kind="ask"):
        op = {"op": "result", "request": rid, "kind": kind, "used": [], "why": "", "summary": summary, "sources": [], "report": ""}
        code, _, out = self.ops({**op, "qid": qid} if qid else op)
        self.assertEqual(code, 200, out)
        return out["results"][0]

    def state(self, who):
        return self.get("/api/state", who)[2]

    def sees(self, who, summary, where="Q1"):
        return summary in [x["summary"] for x in self.state(who)["results"].get(where, [])]

    def status(self, who, rid):
        return next(i["status"] for i in self.state(who)["inbox"] if i["key"] == rid)

    def titles(self, pid):
        return [n["title"] for n in self.app.session.state["notifications"].get(pid, []) if n["kind"] == "request"]

    def test_a_new_session_starts_with_review_off(self):
        self.assertIs(self.state(self.owner)["settings"]["reviewAnswers"], False)

    def test_a_guests_question_request_still_waits_for_run_and_its_answer_is_shared_on_arrival(self):
        rid = self.ask(self.ann)
        self.assertFalse([e for e in self.app.session.state["log"]["events"] if e["kind"] == "request-run"])
        self.go(rid)
        res = self.answer(rid)
        self.assertEqual(res["published"], True)
        self.assertTrue(self.sees(self.bo, "Most shops pin it."))
        self.assertEqual(self.status(self.ann, rid), "shared")
        self.assertEqual(self.titles(self.ann_pid), ["Your request on question Q1 is done."])
        self.assertNotIn("share", [i["kind"] for i in self.state(self.owner)["inbox"]])

    def test_at_claude_in_a_discussion_comment_is_asked_for_everyone(self):
        code, _, out = self.post("/api/discussion", {"qid": "Q1", "text": "@Claude is this common?"}, self.ann)
        self.assertEqual(code, 200, out)
        self.go(out["request"])
        self.assertEqual(self.answer(out["request"], "Very common.")["published"], True)
        self.assertTrue(self.sees(self.bo, "Very common."))

    def test_a_just_me_answer_reaches_only_its_asker_and_the_owner(self):
        rid = self.ask(self.ann, "Just for me", audience="me")
        self.assertEqual(self.app.session.state["requests"][0]["audience"], "me")
        self.go(rid)
        res = self.answer(rid, "Only Ann reads this.")
        self.assertEqual(res["published"], False)
        self.assertTrue(self.sees(self.ann, "Only Ann reads this."))
        self.assertTrue(self.sees(self.owner, "Only Ann reads this."))
        self.assertNotIn("Only Ann reads this.", json.dumps(self.state(self.bo)))
        self.assertEqual(self.status(self.ann, rid), "answered")
        self.assertEqual(self.titles(self.ann_pid), ["Your request on question Q1 is done."])
        self.assertNotIn("share", [i["kind"] for i in self.state(self.owner)["inbox"]])
        self.assertEqual(self.app.session.summary()["queue"]["results"], 0)
        self.post("/api/round/send", {}, self.owner)
        ev = next(e for e in self.app.session.state["log"]["events"] if e["kind"] == "round-sent")
        self.assertEqual(ev["digest"]["results"], [])

    def test_the_asker_shares_their_just_me_answer_later(self):
        rid = self.ask(self.ann, "Just for me", audience="me")
        self.go(rid)
        xid = self.answer(rid, "Ann shares this later.")["id"]
        code, _, out = self.post("/api/result/share", {"id": xid}, self.ann)
        self.assertEqual((code, out), (200, {"ok": True, "id": xid, "published": True}))
        self.assertTrue(self.sees(self.bo, "Ann shares this later."))
        self.assertEqual(self.status(self.ann, rid), "shared")

    def test_a_general_just_me_answer_goes_into_chat_only_once_shared(self):
        code, _, out = self.post("/api/request", {"scope": "session", "kind": "ask", "text": "Where are we?", "audience": "me"}, self.ann)
        self.assertEqual(code, 200, out)
        self.go(out["id"])
        xid = self.answer(out["id"], "Halfway.", qid=None)["id"]
        self.assertEqual(self.app.session.state["chat"], [])
        self.assertTrue(self.sees(self.ann, "Halfway.", "session"))
        self.assertFalse(self.sees(self.bo, "Halfway.", "session"))
        self.assertEqual(self.post("/api/result/share", {"id": xid}, self.ann)[0], 200)
        reply = self.state(self.bo)["chat"][-1]
        self.assertEqual((reply["text"], reply["claude"]), ("Halfway.", {"result": xid}))

    def test_at_claude_in_chat_is_asked_for_everyone(self):
        out = self.post("/api/chat", {"text": "@Claude where are we?"}, self.ann)[2]
        self.go(out["request"])
        self.assertEqual(self.answer(out["request"], "Halfway.", qid=None)["published"], True)
        self.assertEqual(self.state(self.bo)["chat"][-1]["text"], "Halfway.")

    def test_the_owners_own_just_me_answer_stays_with_the_owner(self):
        rid = self.ask(self.owner, "Owner only", audience="me")
        xid = self.answer(rid, "For the owner.")["id"]
        self.assertTrue(self.sees(self.owner, "For the owner."))
        self.assertFalse(self.sees(self.ann, "For the owner."))
        self.assertEqual(self.post("/api/request/act", {"action": "publish", "id": xid}, self.owner)[0], 200)
        self.assertTrue(self.sees(self.ann, "For the owner."))

    def test_just_me_with_the_askers_own_claude_is_refused(self):
        code, _, out = self.post("/api/request", {"qid": "Q1", "kind": "ask", "text": "x", "runner": "self", "audience": "me"}, self.ann)
        self.assertEqual((code, out["error"], out["field"]), (400, "bad-field", "audience"))

    def test_only_the_asker_shares_a_just_me_answer_and_only_the_owner_takes_one_down(self):
        rid = self.ask(self.ann, "Just for me", audience="me")
        self.go(rid)
        xid = self.answer(rid, "Ann's alone.")["id"]
        code, _, out = self.post("/api/result/share", {"id": xid}, self.bo)
        self.assertEqual((code, out["error"]), (404, "not-found"))
        self.assertFalse(self.sees(self.bo, "Ann's alone."))
        self.assertEqual(self.post("/api/result/share", {"id": xid}, self.ann)[0], 200)
        code, _, out = self.post("/api/request/act", {"action": "takedown", "id": xid}, self.ann)
        self.assertEqual((code, out["error"]), (403, "owner-only"))
        self.assertTrue(self.sees(self.bo, "Ann's alone."))

    def test_the_owner_takes_a_shared_answer_down_and_only_the_owner_shares_it_again(self):
        rid = self.ask(self.ann)
        self.go(rid)
        xid = self.answer(rid, "Taken down soon.")["id"]
        code, _, out = self.post("/api/request/act", {"action": "takedown", "id": xid}, self.owner)
        self.assertEqual((code, out), (200, {"ok": True, "id": xid, "published": False}))
        self.assertNotIn("Taken down soon.", json.dumps(self.state(self.bo)))
        self.assertTrue(self.sees(self.ann, "Taken down soon."))
        self.assertEqual(self.status(self.ann, rid), "answered")
        self.assertIn("The answer to your request on question Q1 was taken down.", self.titles(self.ann_pid))
        code, _, out = self.post("/api/result/share", {"id": xid}, self.ann)
        self.assertEqual((code, out["error"]), (403, "host-only"))
        self.assertFalse(self.sees(self.bo, "Taken down soon."))
        self.assertEqual(self.post("/api/request/act", {"action": "takedown", "id": xid}, self.owner)[2]["error"], "wrong-status")
        self.assertEqual(self.post("/api/request/act", {"action": "publish", "id": xid}, self.owner)[0], 200)
        self.assertTrue(self.sees(self.bo, "Taken down soon."))

    def test_taking_down_a_general_answer_takes_its_chat_message_and_quotes_of_it_down(self):
        out = self.post("/api/chat", {"text": "@Claude where are we?"}, self.ann)[2]
        self.go(out["request"])
        xid = self.answer(out["request"], "Secret-ish summary.", qid=None)["id"]
        mid = self.app.session.state["chat"][-1]["id"]
        time.sleep(1.05)
        self.assertEqual(self.post("/api/chat", {"text": "Thanks", "replyTo": mid}, self.bo)[0], 200)
        self.assertEqual(self.post("/api/request/act", {"action": "takedown", "id": xid}, self.owner)[0], 200)
        chat = self.state(self.bo)["chat"]
        gone = next(m for m in chat if m["id"] == mid)  # kept as a tombstone, so every open page refreshes it in place
        self.assertEqual((gone["text"], gone["claude"]), ("Taken down by the host.", {"takenDown": True}))
        self.assertEqual(chat[-1]["replyTo"]["excerpt"], "Taken down by the host.")
        self.assertNotIn("Secret-ish summary.", json.dumps(self.state(self.bo)))
        self.assertIn(mid, self.app.session._chat_touch)  # a page holding it as an older message reads it again
        self.assertEqual(self.post("/api/request/act", {"action": "publish", "id": xid}, self.owner)[0], 200)
        chat = self.state(self.bo)["chat"]
        back = next(m for m in chat if m["id"] == mid)
        self.assertEqual((back["text"], back["claude"], chat[-1]["replyTo"]["excerpt"]), ("Secret-ish summary.", {"result": xid}, "Secret-ish summary."))
        self.assertEqual(len([m for m in chat if "claude" in m]), 1)

    def test_only_ask_and_research_answers_are_shared_on_arrival(self):
        got = {}
        for kind in ("ask", "research", "explore", "design", "prototype"):
            time.sleep(1.05)
            rid = self.ask(self.ann, f"A {kind} request", kind=kind)
            self.go(rid)
            got[kind] = self.answer(rid, f"The {kind} answer.", kind=kind)["published"]
            self.assertEqual(self.sees(self.bo, f"The {kind} answer."), got[kind])
        self.assertEqual(got, {"ask": True, "research": True, "explore": False, "design": False, "prototype": False})
        self.assertEqual(self.app.session.summary()["queue"]["results"], 3)

    def test_an_answer_whose_asker_was_removed_is_held(self):
        rid = self.ask(self.ann)
        self.go(rid)
        self.assertEqual(self.post("/api/person/remove", {"pid": self.ann_pid, "on": True}, self.owner)[0], 200)
        self.assertEqual(self.answer(rid, "Ann has gone.")["published"], False)
        self.assertFalse(self.sees(self.bo, "Ann has gone."))

    def test_the_owner_cannot_discard_a_delivered_just_me_answer(self):
        rid = self.ask(self.ann, "Just for me", audience="me")
        self.go(rid)
        xid = self.answer(rid, "Ann's to keep.")["id"]
        code, _, out = self.post("/api/request/act", {"action": "discard", "id": xid}, self.owner)
        self.assertEqual((code, out["error"]), (409, "wrong-status"))
        self.assertTrue(self.sees(self.ann, "Ann's to keep."))

    def test_the_owners_share_route_shares_a_just_me_answer_with_everyone(self):
        self.assertEqual(self.post("/api/session/settings", {"reviewAnswers": True}, self.owner)[0], 200)
        rid = self.ask(self.ann, "Just for me", audience="me")
        self.go(rid)
        xid = self.answer(rid, "Held, then for all.")["id"]
        code, _, out = self.post("/api/result/share", {"id": xid}, self.owner)
        self.assertEqual((code, out), (200, {"ok": True, "id": xid, "published": True}))
        self.assertTrue(self.sees(self.bo, "Held, then for all."))

    def test_with_review_on_every_answer_waits_for_the_owners_share(self):
        self.assertEqual(self.post("/api/session/settings", {"reviewAnswers": True}, self.owner)[0], 200)
        rid = self.ask(self.ann)
        self.go(rid)
        xid = self.answer(rid, "Held for review.")["id"]
        self.assertFalse(self.sees(self.ann, "Held for review."))
        self.assertEqual(self.status(self.ann, rid), "unshared")
        self.assertEqual(self.titles(self.ann_pid), [])
        self.assertIn("share:" + xid, [i["key"] for i in self.state(self.owner)["inbox"]])
        self.assertEqual(self.post("/api/request/act", {"action": "publish", "id": xid}, self.owner)[0], 200)
        self.assertTrue(self.sees(self.bo, "Held for review."))

    def test_with_review_on_the_owners_share_sends_a_just_me_answer_to_its_asker_alone(self):
        self.assertEqual(self.post("/api/session/settings", {"reviewAnswers": True}, self.owner)[0], 200)
        rid = self.ask(self.ann, "Just for me", audience="me")
        self.go(rid)
        xid = self.answer(rid, "Reviewed, then Ann's.")["id"]
        self.assertFalse(self.sees(self.ann, "Reviewed, then Ann's."))
        code, _, out = self.post("/api/request/act", {"action": "publish", "id": xid}, self.owner)
        self.assertEqual((code, out), (200, {"ok": True, "id": xid, "published": False}))
        self.assertTrue(self.sees(self.ann, "Reviewed, then Ann's."))
        self.assertFalse(self.sees(self.bo, "Reviewed, then Ann's."))
        self.assertEqual(self.status(self.ann, rid), "answered")

    def test_review_turned_off_shares_answers_that_arrive_from_then_on(self):
        self.assertEqual(self.post("/api/session/settings", {"reviewAnswers": True}, self.owner)[0], 200)
        held = self.ask(self.ann, "first")
        self.go(held)
        self.answer(held, "Still held.")
        self.assertEqual(self.post("/api/session/settings", {"reviewAnswers": False}, self.owner)[0], 200)
        time.sleep(1.05)
        later = self.ask(self.ann, "second")
        self.go(later)
        self.answer(later, "Shared at once.")
        self.assertEqual((self.sees(self.bo, "Still held."), self.sees(self.bo, "Shared at once.")), (False, True))


if __name__ == "__main__":
    unittest.main()

"""Live prototypes on the wire: liveserve.py (the static server), the build-folder walk add-live and the start run,
and server.py's QuickTunnelStarter with the fake cloudflared (support.FAKE): Approve starts one tunnel and one static
server, a restart brings a new address without a new Approve, the port refusals, Stop, and the server restart.

Expected values come from the design's live-tier rules: GET and HEAD only (405 otherwise), no listing, no dotfile, a
path resolved with its links stays under the root (else 404), the CSP and Referrer-Policy below, a port that is the
session's own or answers the session-bridge ping is refused, and an owner's server on a port is never stopped.
"""

from __future__ import annotations

import http.server
import os
import re
import stat
import threading
import unittest
from unittest import mock

from support import FAKE, WINDOWS, call, tmpdir, wait_for
from test_server import ServerCase, text_q

import detached
import liveserve
import server
import tunnel

ADDRESS = re.compile(r"^https://fake-[0-9a-f]{12}\.trycloudflare\.com$")
CSP = "default-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'"


def symlink(case, link, target, directory=False):
    try:
        os.symlink(target, link, target_is_directory=directory)
    except (OSError, NotImplementedError) as exc:  # Windows without the symlink privilege
        case.skipTest(f"no symlink here: {exc}")


def serve_in_thread(case, root):
    httpd = liveserve.Server(root)
    threading.Thread(target=httpd.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True).start()
    case.addCleanup(httpd.server_close)
    case.addCleanup(httpd.shutdown)
    return httpd


def raw(port, method, target):
    """(status, headers, body) for one request whose target is sent exactly as given."""
    import http.client

    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    try:
        conn.putrequest(method, target, skip_host=True, skip_accept_encoding=True)
        conn.putheader("Host", "fake-abc.trycloudflare.com")
        conn.endheaders()
        resp = conn.getresponse()
        return resp.status, dict(resp.getheaders()), resp.read()
    finally:
        conn.close()


class TestLiveserve(unittest.TestCase):
    def setUp(self):
        base = tmpdir(self)
        self.root = base / "copy"
        (self.root / "sub").mkdir(parents=True)
        (self.root / "empty").mkdir()
        (self.root / "index.html").write_text("<!doctype html><p>home</p>", encoding="utf-8")
        (self.root / "app.js").write_text("console.log(1)", encoding="utf-8")
        (self.root / "sub" / "index.html").write_text("<p>sub</p>", encoding="utf-8")
        (self.root / ".secret").write_text("hidden", encoding="utf-8")
        (self.root / "sub" / ".hidden").write_text("hidden", encoding="utf-8")
        (base / "outside.txt").write_text("outside", encoding="utf-8")
        self.base = base
        self.httpd = serve_in_thread(self, self.root)
        self.port = self.httpd.server_address[1]

    def test_it_listens_on_loopback_only(self):
        self.assertEqual(self.httpd.server_address[0], "127.0.0.1")

    def test_get_serves_a_file_with_the_csp_referrer_policy_and_type(self):
        code, h, body = raw(self.port, "GET", "/")
        self.assertEqual((code, body), (200, b"<!doctype html><p>home</p>"))
        self.assertEqual((h["Content-Security-Policy"], h["Referrer-Policy"], h["X-Content-Type-Options"]), (CSP, "no-referrer", "nosniff"))
        self.assertEqual(h["Content-Type"], "text/html; charset=utf-8")
        self.assertEqual(raw(self.port, "GET", "/app.js?v=2")[1]["Content-Type"], "text/javascript; charset=utf-8")
        self.assertEqual(raw(self.port, "GET", "/sub/")[2], b"<p>sub</p>")

    def test_head_answers_the_headers_without_the_body(self):
        code, h, body = raw(self.port, "HEAD", "/app.js")
        self.assertEqual((code, h["Content-Length"], body), (200, "14", b""))

    def test_every_other_method_answers_405(self):
        for method in ("POST", "PUT", "DELETE", "OPTIONS", "PATCH", "FOO"):
            with self.subTest(method):
                code, h, _ = raw(self.port, method, "/index.html")
                self.assertEqual((code, h.get("Allow")), (405, "GET, HEAD"))
                self.assertEqual(h["Content-Security-Policy"], CSP)

    def test_a_dotfile_answers_404(self):
        for target in ("/.secret", "/sub/.hidden", "/%2esecret", "/.git/config", "/sub/%2Ehidden"):
            with self.subTest(target):
                self.assertEqual(raw(self.port, "GET", target)[0], 404)

    def test_traversal_answers_404(self):
        for target in ("/../outside.txt", "/%2e%2e/outside.txt", "/sub/../../outside.txt", "/..%2foutside.txt", "/..%5coutside.txt",
                       "/sub/%2e%2e/%2e%2e/outside.txt", "http://x/../outside.txt", "//outside.txt", "/%00", "/C:%5cWindows", "*"):
            with self.subTest(target):
                code, _, body = raw(self.port, "GET", target)
                self.assertEqual(code, 404, body)
                self.assertNotIn(b"outside", body)

    def test_a_folder_is_never_listed(self):
        code, _, body = raw(self.port, "GET", "/empty/")
        self.assertEqual(code, 404)
        self.assertNotIn(b"Directory listing", body)

    def test_a_symlink_inside_the_root_that_points_outside_answers_404(self):
        symlink(self, self.root / "link.txt", self.base / "outside.txt")
        symlink(self, self.root / "linkdir", self.base, directory=True)
        for target in ("/link.txt", "/linkdir/outside.txt"):
            with self.subTest(target):
                self.assertEqual(raw(self.port, "GET", target)[0], 404)

    def test_a_symlink_onto_a_hidden_name_inside_the_root_answers_404(self):
        symlink(self, self.root / "visible", self.root / ".secret")
        self.assertEqual(raw(self.port, "GET", "/visible")[0], 404)


class TestBuildWalk(unittest.TestCase):
    def setUp(self):
        self.src = tmpdir(self) / "build"
        (self.src / "assets").mkdir(parents=True)
        (self.src / "index.html").write_text("<p>a</p>", encoding="utf-8")
        (self.src / "assets" / "app.js").write_text("x", encoding="utf-8")
        self.dest = tmpdir(self) / "live" / "L1"

    def test_it_copies_every_regular_file(self):
        self.assertEqual(liveserve.copy_build(self.src, self.dest), 2)
        self.assertEqual((self.dest / "assets" / "app.js").read_text(encoding="utf-8"), "x")

    @unittest.skipIf(WINDOWS, "file modes are advisory on Windows")
    def test_the_copy_is_private(self):
        liveserve.copy_build(self.src, self.dest)
        self.assertEqual(stat.S_IMODE(self.dest.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((self.dest / "index.html").stat().st_mode), 0o600)

    def test_a_second_copy_replaces_the_first(self):
        liveserve.copy_build(self.src, self.dest)
        (self.src / "assets" / "app.js").unlink()
        liveserve.copy_build(self.src, self.dest)
        self.assertFalse((self.dest / "assets" / "app.js").exists())

    def refused(self, why):
        with self.assertRaisesRegex(liveserve.BuildRefused, why):
            liveserve.copy_build(self.src, self.dest)
        self.assertFalse(self.dest.exists())

    def test_a_hidden_file_or_folder_is_refused(self):
        (self.src / "assets" / ".env").write_text("TOKEN=x", encoding="utf-8")
        self.refused("hidden name: assets/.env")

    def test_a_symlink_is_refused(self):
        symlink(self, self.src / "secrets.json", tmpdir(self) / "x")
        self.refused("link: secrets.json")

    def test_a_folder_symlink_is_refused(self):
        symlink(self, self.src / "data", tmpdir(self), directory=True)
        self.refused("link: data")

    @unittest.skipIf(WINDOWS or not hasattr(os, "mkfifo"), "no FIFO here")
    def test_a_fifo_is_refused(self):
        os.mkfifo(self.src / "pipe")
        self.refused("not a file or a folder: pipe")

    def test_too_many_bytes_or_files_are_refused(self):
        with mock.patch.object(liveserve, "MAX_BYTES", 4):
            self.refused("more than 0 MB")
        with mock.patch.object(liveserve, "MAX_FILES", 1):
            self.refused("more than 1 files")


class LiveCase(ServerCase):
    """A server whose live starter is the real QuickTunnelStarter, with the fake cloudflared."""

    def setUp(self):
        super().setUp()
        self.args = self.d / "cf-args.txt"
        patcher = mock.patch.dict(os.environ, {"SHARED_CLOUDFLARED": FAKE, "FAKE_CF_ARGS": str(self.args), "SHARED_TUNNEL_SECONDS": "10"})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.starter = self.app.live_starter = server.QuickTunnelStarter(self.app)
        self.addCleanup(lambda: (self.app.shutdown(), tunnel.sweep_live(self.d, every=True, reason="stopped")))  # no watch left to restart one
        code, _, out = self.post("/api/session/settings", {"prototypeTiers": ["screenshot", "snapshot", "live"]}, self.owner)
        self.assertEqual(code, 200, out)
        self.build = self.d / "staging" / "r1" / "live"
        self.build.mkdir(parents=True)
        (self.build / "index.html").write_text("<!doctype html><p>first build</p>", encoding="utf-8")

    def add(self, **target):
        code, _, out = self.ops({"op": "add-live", "label": "Checkout app", **(target or {"folder": str(self.build)})})
        self.assertEqual(code, 200, out)
        lid = out["results"][0]["id"]
        proto = {**text_q("Q1"), "format": {"kind": "prototype", "lookAt": "The basket.", "variants": [
            {"id": "v-1", "label": "A", "live": {"id": lid, "path": "/?variant=A"}}, {"id": "v-2", "label": "B", "live": {"id": lid, "path": "/?variant=B"}}]}}
        code, _, out = self.ops({"op": "open-round", "questions": [proto]})
        self.assertEqual(code, 200, out)
        return lid

    def approve(self, lid, **extra):
        return self.post("/api/live/approve", {"id": lid, **extra}, self.owner)

    def runs(self):
        return self.args.read_text(encoding="utf-8").splitlines() if self.args.exists() else []

    def record(self, lid):
        return tunnel.read_live(tunnel.live_path(self.d, lid))

    def status(self, lid):
        return next(e["status"] for e in self.app.session.state["lives"] if e["id"] == lid)


class TestStart(LiveCase):
    def test_approve_starts_one_tunnel_and_one_static_server_and_the_entry_gets_the_address(self):
        lid = self.add()
        code, _, out = self.approve(lid)
        self.assertEqual(code, 200, out)
        rec = self.record(lid)
        self.assertRegex(self.status(lid)["url"], ADDRESS)
        self.assertEqual(rec["url"], self.status(lid)["url"])
        port = rec["server"]["port"]
        self.assertEqual(self.runs(), [f"tunnel --no-autoupdate --url http://127.0.0.1:{port}"])
        self.assertTrue(tunnel.tunnel_running(rec) and tunnel.server_running(rec))
        code, h, body = call(port, "GET", "/")
        self.assertEqual((code, body, h["Content-Security-Policy"]), (200, b"<!doctype html><p>first build</p>", CSP))

    def test_the_static_server_serves_the_copy_made_at_approve_never_the_staging_folder(self):
        lid = self.add()
        self.assertEqual(self.approve(lid)[0], 200)
        (self.build / "index.html").write_text("<p>changed after approve</p>", encoding="utf-8")
        (self.build / "new.html").write_text("<p>new</p>", encoding="utf-8")
        port = self.record(lid)["server"]["port"]
        self.assertEqual(call(port, "GET", "/")[2], b"<!doctype html><p>first build</p>")
        self.assertEqual(call(port, "GET", "/new.html")[0], 404)
        self.assertTrue((self.d / server.LIVE_COPIES / lid / "index.html").is_file())

    @unittest.skipIf(WINDOWS, "file modes are advisory on Windows")
    def test_the_record_is_private(self):
        lid = self.add()
        self.assertEqual(self.approve(lid)[0], 200)
        self.assertEqual(stat.S_IMODE(tunnel.live_path(self.d, lid).stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE((self.d / tunnel.LIVE_DIR).stat().st_mode), 0o700)

    def test_a_build_folder_that_gained_a_link_or_a_hidden_name_since_add_live_is_refused_at_approve(self):
        lid = self.add()
        (self.build / ".env").write_text("TOKEN=x", encoding="utf-8")
        code, _, out = self.approve(lid)
        self.assertEqual((code, out["error"], out.get("field")), (400, "bad-field", "folder"), out)
        self.assertEqual((self.status(lid), self.runs()), ({"kind": "pending"}, []))

    def test_a_tunnel_that_prints_no_address_leaves_nothing_running_and_the_entry_waiting(self):
        lid = self.add()
        with mock.patch.dict(os.environ, {"FAKE_CF_NOURL": "1", "SHARED_TUNNEL_SECONDS": "1"}):
            code, _, out = self.approve(lid)
        self.assertEqual((code, out["error"]), (502, "live-failed"), out)
        rec = self.record(lid)
        self.assertFalse(tunnel.tunnel_running(rec) or tunnel.server_running(rec))
        self.assertEqual(self.status(lid), {"kind": "pending"})

    def test_stop_ends_the_tunnel_and_the_static_server(self):
        lid = self.add()
        self.assertEqual(self.approve(lid)[0], 200)
        before = self.record(lid)
        self.assertEqual(self.post("/api/live/stop", {"id": lid}, self.owner)[0], 200)
        rec = self.record(lid)
        self.assertFalse(detached.alive(before["pid"], before["marker"], before["processStart"]))
        self.assertFalse(tunnel.server_running(before))
        self.assertEqual((rec["reason"], rec["pid"]), ("stopped", before["pid"]))  # the record keeps what ran
        self.assertIn("endedAt", rec)
        self.assertFalse((self.d / server.LIVE_COPIES / lid).exists())


class TestPorts(LiveCase):
    def test_a_port_answering_the_session_bridge_ping_is_refused_at_approve(self):
        other = server.App(tmpdir(self), watch_tunnel=False)
        other.serve()
        self.addCleanup(other.shutdown)
        lid = self.add(port=other.control_port)
        code, _, out = self.approve(lid, attest=True)
        self.assertEqual((code, out["error"], out.get("field")), (400, "bad-field", "port"), out)
        self.assertIn("control listener", out["message"])
        self.assertEqual((self.status(lid), self.runs()), ({"kind": "pending"}, []))

    def test_the_sessions_own_ports_are_refused_by_the_starter_too(self):
        for port in (self.app.guest_port, self.app.control_port):
            with self.subTest(port=port), self.assertRaises(server.DomainError) as ctx:
                self.starter.check_port(port)
            self.assertEqual(ctx.exception.details.get("field"), "port")

    def test_an_attested_port_gets_a_tunnel_only_and_its_server_keeps_running_after_stop(self):
        dev = http.server.ThreadingHTTPServer(("127.0.0.1", 0), http.server.SimpleHTTPRequestHandler)
        threading.Thread(target=dev.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True).start()
        self.addCleanup(dev.server_close)
        self.addCleanup(dev.shutdown)
        port = dev.server_address[1]
        lid = self.add(port=port)
        self.assertEqual(self.approve(lid, attest=True)[0], 200)
        rec = self.record(lid)
        self.assertNotIn("server", rec)
        self.assertEqual(self.runs(), [f"tunnel --no-autoupdate --url http://127.0.0.1:{port}"])
        self.assertEqual(self.post("/api/live/stop", {"id": lid}, self.owner)[0], 200)
        self.assertFalse(tunnel.tunnel_running(rec))
        self.assertEqual(call(port, "GET", "/")[0] // 100, 2)  # the owner's server is theirs: never stopped


class TestSupervision(LiveCase):
    def started(self):
        lid = self.add()
        self.assertEqual(self.approve(lid)[0], 200)
        return lid, self.record(lid)

    def test_a_killed_cloudflared_is_restarted_with_a_new_address_and_no_new_approve(self):
        lid, before = self.started()
        self.assertTrue(detached.stop(before["pid"], before["marker"], before["processStart"]))
        url = wait_for(lambda: self.status(lid).get("url") != before["url"] and self.status(lid).get("url"), 20)
        self.assertRegex(url or "", ADDRESS)
        self.assertEqual(self.status(lid)["kind"], "running")
        rec = self.record(lid)
        self.assertEqual((rec["url"], rec["server"]["pid"]), (url, before["server"]["pid"]))  # the static server stayed
        self.assertEqual(len(self.runs()), 2)
        guest = self.join("Ann")[1]
        self.assertEqual(next(e for e in self.get("/api/state", guest)[2]["lives"] if e["id"] == lid)["url"], url)

    def test_a_killed_static_server_is_restarted_on_the_same_copy_behind_a_new_tunnel(self):
        lid, before = self.started()
        srv = before["server"]
        self.assertTrue(detached.stop(srv["pid"], srv["marker"], srv["processStart"]))
        self.assertTrue(wait_for(lambda: self.status(lid).get("url") != before["url"], 20))
        rec = self.record(lid)
        self.assertNotEqual(rec["server"]["pid"], srv["pid"])
        self.assertFalse(tunnel.tunnel_running(before))
        self.assertEqual(call(rec["server"]["port"], "GET", "/")[2], b"<!doctype html><p>first build</p>")

    def test_past_the_restart_limit_the_entry_ends_and_nothing_runs(self):
        lid, before = self.started()
        with mock.patch.object(server, "LIVE_RESTARTS", 2), mock.patch.object(server, "LIVE_BACKOFF", 0.1), \
                mock.patch.dict(os.environ, {"FAKE_CF_NOURL": "1", "SHARED_TUNNEL_SECONDS": "1"}):
            detached.stop(before["pid"], before["marker"], before["processStart"])
            self.assertTrue(wait_for(lambda: self.status(lid)["kind"] == "ended", 30), self.status(lid))
        self.assertEqual(self.status(lid)["reason"], "failed")
        self.assertEqual(len(self.runs()), 3)  # the start, then two restarts
        rec = self.record(lid)
        self.assertFalse(tunnel.tunnel_running(rec) or tunnel.server_running(rec) or tunnel.server_running(before))
        guest = self.join("Ann")[1]
        self.assertNotIn("url", next(e for e in self.get("/api/state", guest)[2]["lives"] if e["id"] == lid))


class TestServerRestart(LiveCase):
    def reopen(self):
        self.app.shutdown()
        self.app = server.App(self.d, watch_tunnel=False)
        self.addCleanup(self.app.shutdown)

    def test_a_restart_takes_back_a_running_live_prototype(self):
        lid = self.add()
        self.assertEqual(self.approve(lid)[0], 200)
        before = self.record(lid)
        self.reopen()
        self.assertIn(lid, self.app._live_begun)
        self.assertEqual(self.status(lid)["url"], before["url"])
        self.assertTrue(tunnel.tunnel_running(before) and tunnel.server_running(before))

    def test_after_a_crash_an_entry_whose_processes_are_gone_ends(self):
        lid = self.add()
        self.assertEqual(self.approve(lid)[0], 200)
        before = self.record(lid)
        detached.stop(before["pid"], before["marker"], before["processStart"])
        detached.stop(*tunnel._server(before))
        self.reopen()
        self.assertEqual((self.status(lid)["kind"], self.status(lid)["reason"]), ("ended", "failed"))
        self.assertIn("endedAt", self.record(lid))
        self.assertNotIn(lid, self.app._live_begun)

    def test_an_entry_the_server_stopped_while_it_started_waits_for_approve_again(self):
        lid = self.add()
        with self.app.session._tx() as st:
            st["lives"][0]["status"] = {"kind": "starting", "approvedAt": 1.0}
        self.reopen()
        self.assertEqual(self.status(lid), {"kind": "pending"})


class TestControlRoute(LiveCase):
    def control(self, body):
        return call(self.app.control_port, "POST", "/api/live/stop", body, {"X-Shared-Token": self.app.hub.token})

    def test_live_stop_with_an_id_ends_one_and_without_ends_every_one(self):
        first = self.add()
        code, _, out = self.ops({"op": "add-live", "label": "Second", "folder": str(self.build)})
        self.assertEqual(code, 200, out)
        second = out["results"][0]["id"]
        self.assertEqual(self.approve(first)[0], 200)
        code, _, out = self.control({"id": first})
        self.assertEqual((code, out["ended"]), (200, [first]), out)
        self.assertEqual(self.status(second)["kind"], "pending")
        code, _, out = self.control({})
        self.assertEqual((code, out["ended"]), (200, [second]), out)
        self.assertFalse(tunnel.tunnel_running(self.record(first)))

    def test_the_route_needs_the_control_token(self):
        lid = self.add()
        code, _, _ = call(self.app.control_port, "POST", "/api/live/stop", {"id": lid})
        self.assertIn(code, (401, 403))
        self.assertEqual(self.status(lid), {"kind": "pending"})

    def test_status_lists_the_lives(self):
        lid = self.add()
        code, _, out = call(self.app.control_port, "GET", "/api/status", headers={"X-Shared-Token": self.app.hub.token})
        self.assertEqual((code, out["lives"]), (200, [{"id": lid, "label": "Checkout app", "status": "pending"}]), out)


class TestAddLiveRefusals(LiveCase):
    def refused(self, folder):
        code, _, out = self.ops({"op": "add-live", "label": "App", "folder": str(folder)})
        self.assertEqual((code, out["error"], out.get("field")), (400, "bad-field", "folder"), out)
        self.assertNotIn("lives", self.app.session.state)

    def test_a_folder_holding_a_symlink_is_refused(self):
        symlink(self, self.build / "secrets.json", self.d / ".shared-secrets.json")
        self.refused(self.build)

    def test_a_folder_holding_a_hidden_name_is_refused(self):
        (self.build / "assets").mkdir()
        (self.build / "assets" / ".env").write_text("x", encoding="utf-8")
        self.refused(self.build)

    def test_a_folder_outside_the_data_folder_is_refused(self):
        outside = tmpdir(self) / "staging" / "build"
        outside.mkdir(parents=True)
        (outside / "index.html").write_text("x", encoding="utf-8")
        self.refused(outside)


if __name__ == "__main__":
    unittest.main()

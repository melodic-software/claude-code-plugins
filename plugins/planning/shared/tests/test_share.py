"""share.py, the CLI the skill calls: ensure-running, stop, restart, status, url, list, apply, lease.

Each test runs share.py in a child process against the fake cloudflared (support.FAKE), as the
skill runs share.sh. Expected values come from the Design's "share.sh CLI" table, its exit codes,
and the planning amendments (the tunnel outlives a server restart; tokens never on argv).
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import re
import shutil
import socket
import stat
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

from support import WINDOWS, ShareCase, call, env, share, tmpdir, wait_for

import detached
import share as share_cli
import tunnel

ENSURE_KEYS = ["guestUrl", "localUrl", "ok", "ownerLinkFile", "resumed", "shareChanged", "tunnel", "watch"]


def text_q(qid):
    return {"id": qid, "text": f"Question {qid}?", "alternatives": [], "dependsOn": [], "purpose": "decide", "format": {"kind": "text"}}


class Running(ShareCase):
    """A session that ensure-running started."""

    def setUp(self):
        super().setUp()
        code, self.first, err = share(self.d, "ensure-running")
        self.assertEqual(code, 0, err)

    def apply(self, *ops):
        f = self.d / "ops.json"
        f.write_text(json.dumps({"ops": list(ops)}), encoding="utf-8")
        return share(self.d, "apply", "--file", str(f))

    def join(self, name):
        code, _, out = call(self.guest_port(), "POST", "/api/join", {"name": name, "device": "computer"})
        self.assertEqual(code, 200, out)
        return {"X-Session-Secret": out["secret"]}


class TestEnsureRunning(Running):
    def test_it_answers_the_contract_fields(self):
        out = self.first
        self.assertEqual(sorted(out), ENSURE_KEYS)
        self.assertRegex(out["guestUrl"], r"^https://fake-[0-9a-f]{12}\.trycloudflare\.com/$")
        self.assertEqual(out["localUrl"], f"http://127.0.0.1:{self.guest_port()}/")
        self.assertEqual((out["tunnel"], out["resumed"], out["shareChanged"]), ("quick", False, False))
        self.assertEqual(Path(out["ownerLinkFile"]), self.d / ".owner-link")
        self.assertIn("watch.sh", out["watch"])

    def test_a_second_run_reuses_the_server_and_the_tunnel(self):
        pid = self.session_record()["pid"]
        cf = tunnel.read(self.d)["pid"]
        code, out, _ = share(self.d, "ensure-running")
        self.assertEqual(code, 0)
        self.assertEqual((out["guestUrl"], out["resumed"]), (self.first["guestUrl"], True))
        self.assertEqual((self.session_record()["pid"], tunnel.read(self.d)["pid"]), (pid, cf))

    def test_the_owner_link_is_private_and_carries_the_token_in_the_fragment(self):
        link = (self.d / ".owner-link").read_text(encoding="utf-8").strip()
        self.assertRegex(link, r"^http://127\.0\.0\.1:\d+/#owner=[A-Za-z0-9_-]{43}$")
        if not WINDOWS:
            self.assertEqual(stat.S_IMODE((self.d / ".owner-link").stat().st_mode), 0o600)

    def test_the_guest_listener_answers_on_the_local_url(self):
        code, _, out = call(self.guest_port(), "GET", "/api/state")
        self.assertEqual((code, out["title"]), (200, "Shared interview"))

    @unittest.skipIf(WINDOWS, "a process's command line is not readable here")
    def test_no_token_is_on_the_server_command_line(self):
        cmd = detached.describe(self.session_record()["pid"])
        self.assertIn("server.py", cmd)
        secrets_file = json.loads((self.d / ".shared-secrets.json").read_text(encoding="utf-8"))
        for name in ("control", "owner"):
            self.assertNotIn(secrets_file[name], cmd, name)
        self.assertNotIn(self.session_record()["token"], cmd)

    @unittest.skipIf(WINDOWS, "file modes are advisory on Windows")
    def test_the_reported_guest_link_is_private(self):
        self.assertEqual(stat.S_IMODE((self.d / ".shared-reported").stat().st_mode), 0o600)

    @unittest.skipUnless(Path("/proc/self/cwd").exists(), "needs /proc to read a process's folder")
    def test_the_server_and_cloudflared_run_in_the_data_folder(self):
        for name, pid in (("server", self.session_record()["pid"]), ("cloudflared", tunnel.read(self.d)["pid"])):
            with self.subTest(name):
                self.assertEqual(Path(os.readlink(f"/proc/{pid}/cwd")), self.d.resolve())


class TestStopStatusUrl(Running):
    def test_stop_ends_the_server_and_the_tunnel_and_keeps_the_state(self):
        cf = tunnel.read(self.d)
        code, out, _ = share(self.d, "stop")
        self.assertEqual((code, out["ok"], sorted(out["stopped"])), (0, True, ["server", "tunnel"]))
        self.assertFalse(detached.alive(cf["pid"], cf["marker"]))
        self.assertTrue((self.d / "state.json").exists())
        code, st, _ = share(self.d, "status")
        self.assertEqual((code, st["running"], st["tunnel"]), (0, False, "off"))

    def test_stop_keep_tunnel_keeps_the_guest_link_for_the_next_start(self):
        share(self.d, "stop", "--keep-tunnel")
        self.assertIsNotNone(tunnel.alive(self.d))
        code, out, _ = share(self.d, "ensure-running")
        self.assertEqual((code, out["guestUrl"], out["resumed"]), (0, self.first["guestUrl"], True))

    def test_status_reports_round_people_queue_and_lease(self):
        self.join("Ann")
        code, st, _ = share(self.d, "status")
        self.assertEqual(code, 0)
        self.assertEqual((st["running"], st["tunnel"], st["guestUrl"], st["people"]["joined"]), (True, "quick", self.first["guestUrl"], 1))
        self.assertEqual(sorted(st), ["guestUrl", "lease", "ok", "people", "queue", "round", "running", "tunnel", "unhandled"])

    def test_url_prints_the_guest_link_and_owner_only_on_request(self):
        code, out, _ = share(self.d, "url")
        self.assertEqual((code, out), (0, {"guestUrl": self.first["guestUrl"]}))
        code, out, _ = share(self.d, "url", "--owner")
        self.assertEqual(out, {"ownerUrl": (self.d / ".owner-link").read_text(encoding="utf-8").strip()})

    def test_the_guest_link_carries_the_join_key_after_a_rotation(self):
        owner = {"X-Owner-Token": self.owner_token()}
        _, _, out = call(self.guest_port(), "POST", "/api/link/guest", {}, owner)
        _, url, _ = share(self.d, "url")
        self.assertEqual(url["guestUrl"], self.first["guestUrl"] + "#join=" + out["guestKey"])

    def test_list_finds_every_session_under_the_root(self):
        other = self.root / "topic" / "shared" / "designer"
        other.mkdir(parents=True)
        shutil.copy(self.d / "state.json", other / "state.json")
        code, out, _ = share(None, "list", "--root", str(self.root))
        self.assertEqual(code, 0)
        rows = {Path(r["dir"]).name: r for r in out["sessions"]}
        self.assertEqual(sorted(rows), ["designer", "po"])
        self.assertEqual((rows["po"]["running"], rows["po"]["guestUrl"]), (True, self.first["guestUrl"]))
        self.assertEqual((rows["designer"]["running"], rows["designer"]["ended"]), (False, False))

    def test_lease_shows_and_releases(self):
        code, out, _ = share(self.d, "lease")
        self.assertEqual((code, out), (0, {"lease": None}))
        code, out, _ = share(self.d, "lease", "--release")
        self.assertEqual((code, out), (0, {"lease": None}))


class TestApply(Running):
    def test_apply_lands_the_ops_and_deletes_the_file(self):
        code, out, err = self.apply({"op": "set-title", "title": "Checkout"}, {"op": "open-round", "questions": [text_q("Q1")]})
        self.assertEqual(code, 0, err)
        self.assertEqual(out["results"][1]["round"], 1)
        self.assertFalse((self.d / "ops.json").exists())
        self.assertEqual(call(self.guest_port(), "GET", "/api/state")[2]["title"], "Checkout")

    def test_a_refused_apply_exits_1_names_the_op_and_keeps_the_file(self):
        code, out, err = self.apply({"op": "set-title", "title": "Fine"}, {"op": "ack-round", "round": 1})
        self.assertEqual((code, out["ok"], out["error"], out["op"]), (1, False, "wrong-status", 1))
        self.assertIn("wrong-status", err)
        self.assertTrue((self.d / "ops.json").exists())

    def test_apply_with_no_file_is_a_no_op(self):
        code, out, _ = share(self.d, "apply", "--file", str(self.d / "ops.json"))
        self.assertEqual((code, out["applied"], out["results"]), (0, False, []))


class TestOpen(ShareCase):
    def test_open_hands_the_browser_a_private_page_and_never_the_token(self):
        stub = tmpdir(self)
        seen = stub / "opened.json"
        script = stub / "opener.py"
        script.write_text(
            "import json, os, stat, sys, urllib.parse, urllib.request\n"
            "page = urllib.request.url2pathname(urllib.parse.urlparse(sys.argv[1]).path)\n"
            f"json.dump({{'argv': sys.argv[1:], 'page': page, 'mode': stat.S_IMODE(os.stat(page).st_mode), 'html': open(page, encoding='utf-8').read()}}, open({str(seen)!r}, 'w'))\n",
            encoding="utf-8",
        )
        if WINDOWS:
            opener = stub / "opener.cmd"
            opener.write_text(f'@"{sys.executable}" "{script}" %1\n', encoding="utf-8")
        else:
            opener = stub / "opener"
            opener.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{script}" "$1"\n', encoding="utf-8")
            opener.chmod(0o700)
        code, out, err = share(self.d, "ensure-running", "--open", environ=env(SHARED_BROWSER=str(opener), SHARED_OPEN_SECONDS="1"))
        self.assertEqual(code, 0, err)
        link = (self.d / ".owner-link").read_text(encoding="utf-8").strip()
        token = link.split("#owner=", 1)[1]
        got = json.loads(seen.read_text(encoding="utf-8"))
        self.assertNotIn(token, " ".join(got["argv"]))
        page = Path(got["page"])
        self.assertEqual(page.parent, self.d.resolve())
        self.assertIn(json.dumps(link), got["html"])
        if not WINDOWS:
            self.assertEqual(got["mode"], 0o600)
        self.assertNotIn("#owner=", json.dumps(out))
        self.assertTrue(wait_for(lambda: not page.exists(), seconds=10), "the page outlived its delay")


class TestCodes(ShareCase):
    def test_a_data_folder_that_cannot_be_private_exits_1_naming_why_and_starts_nothing(self):
        err = io.StringIO()
        with mock.patch.object(detached, "data_dir_problem", return_value="the data folder is outside your user profile"), contextlib.redirect_stderr(err):
            code = share_cli.main(["--dir", str(self.d), "ensure-running"])
        self.assertEqual(code, 1)
        self.assertIn("outside your user profile", err.getvalue())
        self.assertFalse(self.d.exists())

    def test_a_missing_cloudflared_exits_2_naming_it(self):
        path = os.path.dirname(shutil.which("curl") or "")
        if not path or shutil.which("cloudflared", path=path):
            self.skipTest("no curl, or cloudflared sits beside curl on this host")
        code, _, err = share(self.d, "ensure-running", environ=env(SHARED_CLOUDFLARED=None, PATH=path))
        self.assertEqual(code, 2)
        self.assertIn("cloudflared", err)

    def test_no_tunnel_address_in_time_exits_3_and_keeps_the_server(self):
        code, out, err = share(self.d, "ensure-running", environ=env(FAKE_CF_NOURL="1", SHARED_TUNNEL_SECONDS="1"))
        self.assertEqual(code, 3, err)
        self.assertEqual((out["tunnel"], out["guestUrl"]), ("down", ""))
        self.assertEqual(call(int(re.search(r":(\d+)/", out["localUrl"]).group(1)), "GET", "/api/state")[0], 200)

    def test_a_newer_schema_exits_1(self):
        share(self.d, "ensure-running")
        share(self.d, "stop")
        doc = json.loads((self.d / "state.json").read_text(encoding="utf-8"))
        doc["schemaVersion"] = 7
        (self.d / "state.json").write_text(json.dumps(doc), encoding="utf-8")
        code, _, err = share(self.d, "ensure-running")
        self.assertEqual(code, 1)
        self.assertIn("newer", err)

    def test_bad_arguments_exit_1(self):
        code, _, _ = share(self.d, "ensure-running", "--no-such-flag")
        self.assertEqual(code, 1)

    def test_the_guest_port_is_chosen_when_the_session_is_created_and_kept(self):
        free = socket.socket()
        free.bind(("127.0.0.1", 0))
        port = free.getsockname()[1]
        free.close()
        code, out, err = share(self.d, "ensure-running", "--guest-port", str(port))
        self.assertEqual(code, 0, err)
        self.assertEqual(out["localUrl"], f"http://127.0.0.1:{port}/")
        share(self.d, "stop")
        code, out, _ = share(self.d, "ensure-running")
        self.assertEqual(out["localUrl"], f"http://127.0.0.1:{port}/")
        share(self.d, "stop")
        code, _, err = share(self.d, "ensure-running", "--guest-port", str(port + 1))
        self.assertEqual(code, 1)
        self.assertIn("guest port", err)

    def test_commands_on_a_stopped_session_say_so(self):
        self.d.mkdir(parents=True)
        code, _, err = share(self.d, "lease")
        self.assertEqual(code, 2)
        self.assertIn("not running", err)
        code, _, _ = share(self.d, "restart")
        self.assertEqual(code, 1)


class TestRestart(Running):
    def test_restart_keeps_tunnel_and_state(self):
        a, b = self.join("Ann"), self.join("Bo")
        self.assertEqual(self.apply({"op": "open-round", "questions": [text_q("Q1")]})[0], 0)
        for who, text in ((a, "Card"), (b, "Saved method")):
            code, _, out = call(self.guest_port(), "POST", "/api/answer", {"qid": "Q1", "text": text, "device": "computer", "view": "focus"}, who)
            self.assertEqual(code, 200, out)
        old_server, cf = self.session_record()["pid"], tunnel.read(self.d)
        old_token = self.session_record()["token"]
        code, out, err = share(self.d, "restart")
        self.assertEqual(code, 0, err)
        self.assertNotEqual(self.session_record()["pid"], old_server)
        self.assertEqual((out["guestUrl"], out["restarted"]), (self.first["guestUrl"], True))
        self.assertEqual(tunnel.read(self.d)["pid"], cf["pid"])
        self.assertTrue(detached.alive(cf["pid"], cf["marker"]))
        self.assertEqual(self.session_record()["token"], old_token)  # an armed watcher reconnects
        _, _, snap = call(self.guest_port(), "GET", "/api/state", headers=a)
        self.assertEqual(sorted(p["name"] for p in snap["people"]), ["Ann", "Bo", "Host"])
        self.assertEqual(sorted(c["text"] for c in snap["cards"]["Q1"] if c["kind"] == "person"), ["Card", "Saved method"])


class TestTunnelRestart(Running):
    def test_a_tunnel_that_exits_comes_back_with_a_new_link_and_the_next_start_says_so(self):
        cf = tunnel.read(self.d)
        detached.stop(cf["pid"], cf["marker"])
        new = wait_for(lambda: (u := share(self.d, "url")[1]["guestUrl"]) != self.first["guestUrl"] and u, seconds=30, step=0.5)
        self.assertRegex(new, r"^https://fake-[0-9a-f]{12}\.trycloudflare\.com/$")
        code, out, _ = share(self.d, "ensure-running")
        self.assertEqual((code, out["guestUrl"], out["shareChanged"]), (0, new, True))
        _, _, snap = call(self.guest_port(), "GET", "/api/state", headers={"X-Owner-Token": self.owner_token()})
        self.assertIn("changedAt", snap["share"])


@unittest.skipIf(WINDOWS, "share.sh runs under Git Bash there; the Python entry point is tested above")
class TestShareSh(ShareCase):
    def test_share_sh_runs_share_py(self):
        p = subprocess.run(["bash", str(Path(__file__).resolve().parent.parent / "share.sh"), "--dir", str(self.d), "status"], capture_output=True, text=True, timeout=60, env=env())
        self.assertEqual(p.returncode, 1)  # no data dir yet
        self.assertIn("no such data dir", p.stderr)


if __name__ == "__main__":
    unittest.main()

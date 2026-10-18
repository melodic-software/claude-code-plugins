"""share.py, the CLI the skill calls: ensure-running, stop, restart, status, url, list, apply, lease.

Each test runs share.py in a child process against the fake cloudflared (support.FAKE), as the
skill runs share.sh. Expected values come from the Design's "share.sh CLI" table, its exit codes,
and the planning amendments (the tunnel outlives a server restart; tokens never on argv).
"""

from __future__ import annotations

import contextlib
import datetime
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

from support import WINDOWS, ShareCase, call, env, outside_cloudflared, share, tmpdir, wait_for

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
        # share.py resolves --dir; a Windows temp folder may be named in its 8.3 short form.
        self.assertEqual(Path(out["ownerLinkFile"]), self.d.resolve() / ".owner-link")
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

    @unittest.skipIf(WINDOWS, "a process's command line is not readable here")
    def test_the_server_runs_in_isolated_mode(self):
        self.assertEqual(detached.describe(self.session_record()["pid"]).split()[1], "-I")

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
        self.assertEqual(sorted(st), ["guestUrl", "intro", "lease", "ok", "people", "queue", "round", "running", "tunnel", "unhandled"])

    def test_status_says_whether_the_intro_is_set_running_or_stopped(self):
        """lane-shared.md Start step 5 reads `intro` from `share.sh status` to know whether to draft one."""
        self.assertIs(share(self.d, "status")[1]["intro"], False)
        self.apply({"op": "set-intro", "intro": "Why you're here: the payment step."})
        self.assertIs(share(self.d, "status")[1]["intro"], True)
        share(self.d, "stop", "--keep-tunnel")
        self.assertIs(share(self.d, "status")[1]["intro"], True)

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


class TestLogs(unittest.TestCase):
    """`logs [--errors] [--since MINUTES]` (README "Logs"): {"ok", "lines"}, oldest first across server.log and its
    rotated files; --errors keeps request entries with a 4xx or 5xx status and client entries. The fixture lines are
    written here in the format README "Logs" documents, not taken from a server."""

    def setUp(self):
        self.d = tmpdir(self)
        now = datetime.datetime.now()
        stamp = lambda minutes: (now - datetime.timedelta(minutes=minutes)).strftime("%Y-%m-%d %H:%M:%S,000")  # noqa: E731
        self.old = f"{stamp(120)} WARNING request method=POST route=/api/vote status=409 ms=0.3 pid=pidAnn001 code=locked"
        self.rotated = f"{stamp(5)} WARNING request method=POST route=/api/answer status=429 ms=0.1 pid=pidAnn001 code=slow-down"
        self.ok = f"{stamp(1)} INFO request method=GET route=/api/state status=200 ms=0.4 pid=pidAnn001"
        self.refusal = f'{stamp(1)} WARNING request method=POST route=/api/person/merge status=400 ms=0.5 pid=host code=bad-field field=pid message="pid must name a person."'
        self.crash = f'{stamp(1)} ERROR request method=POST route=/api/rename status=500 ms=1.0 pid=pidAnn001 code=state-invalid trace="Traceback (most recent call last):\\x0a  boom"'
        self.client = f'{stamp(1)} WARNING client pid=pidAnn001 kind=error message="TypeError: x is undefined status=500"'
        self.notice = f"{stamp(1)} WARNING the owner-link rotation time 99 was ahead of the clock; set it to now"
        (self.d / "server.log.1").write_text("\n".join([self.old, self.rotated]) + "\n", encoding="utf-8")
        (self.d / "server.log").write_text("\n".join([self.ok, self.refusal, self.crash, self.client, self.notice]) + "\n", encoding="utf-8")

    def test_logs_prints_the_tail_oldest_first_across_rotated_files(self):
        code, out, err = share(self.d, "logs")
        self.assertEqual(code, 0, err)
        self.assertEqual(out, {"ok": True, "lines": [self.old, self.rotated, self.ok, self.refusal, self.crash, self.client, self.notice]})

    def test_errors_keeps_only_refusals_server_errors_and_client_entries(self):
        code, out, err = share(self.d, "logs", "--errors")
        self.assertEqual(code, 0, err)
        self.assertEqual(out["lines"], [self.old, self.rotated, self.refusal, self.crash, self.client])

    def test_since_keeps_the_last_minutes(self):
        code, out, err = share(self.d, "logs", "--errors", "--since", "30")
        self.assertEqual(code, 0, err)
        self.assertEqual(out["lines"], [self.rotated, self.refusal, self.crash, self.client])

    def test_a_line_holding_a_unicode_line_separator_stays_one_line(self):
        """A log written before entry() escaped U+2028: only a newline ends an entry."""
        line = self.client.replace("TypeError", "boom\u2028" + self.crash[:19] + " ERROR request method=POST route=/api/fake status=500")
        (self.d / "server.log").write_text(line + "\n", encoding="utf-8")
        (self.d / "server.log.1").unlink()
        code, out, err = share(self.d, "logs", "--errors")
        self.assertEqual((code, out["lines"]), (0, [line]), err)

    def test_a_folder_with_no_log_prints_no_lines(self):
        d = tmpdir(self)
        self.assertEqual(share(d, "logs")[:2], (0, {"ok": True, "lines": []}))

    def test_errors_leaves_out_usage_summaries(self):
        summary = f'{self.client[:23]} INFO summary-batch summaries=1 dropped=0 data=[["pv=0a1b2c3d\\u0020gap=900","chrome\\u0020phone"]]'
        (self.d / "server.log").write_text("\n".join([self.client, summary]) + "\n", encoding="utf-8")
        (self.d / "server.log.1").unlink()
        self.assertEqual(share(self.d, "logs", "--errors")[1]["lines"], [self.client])


class TestLogsSummary(unittest.TestCase):
    """`logs --summary [--json]` (README "Logs"): what the pages' telemetry adds up to. The fixture lines are written
    here in the format README "Logs" documents; every expected count below is worked out by hand from them."""

    LINES = [
        'WARNING request method=POST route=/api/answer status=409 ms=2.0 pid=pidAnn001 code=locked message="Question Q1 is locked."',
        'WARNING request method=POST route=/api/answer status=409 ms=4.0 pid=pidBo0001 code=locked message="Question Q1 is locked."',
        "INFO request method=POST route=/api/vote status=200 ms=3.0 pid=pidAnn001",
        "INFO request method=POST route=/api/vote status=200 ms=5.0 pid=pidBo0001",
        "INFO request method=POST route=/api/vote status=200 ms=1.0 pid=host",
        "WARNING request method=POST route=/api/vote status=429 ms=0.5 pid=pidAnn001 code=slow-down",
        'WARNING client pid=pidAnn001 kind=error message="TypeError: x is undefined" source=/app.js:12 route=/ ua="chrome phone" fp=aaaa1111',
        'WARNING client pid=pidBo0001 kind=error message=boom route=/ ua="safari computer" fp=bbbb2222',
        'WARNING client pid=pidBo0001 kind=api message="Failed to fetch" route=/api/vote code=network ua="safari phone" fp=cccc3333',
        'WARNING client pid=pidAnn001 kind=layout message="anomaly=overflow at=vf-body w=320 sw=410" route=/ ua="chrome phone" fp=dddd4444',
        'WARNING client pid=pidAnn001 kind=layout message="sheet=vf-proposepop kb=344px" route=/ ua="chrome phone"',
        # Two summary batches (README "Logs": [message, ua] pairs, each space written \\u0020); one summary missed the second.
        "INFO summary-batch summaries=3 dropped=0 data=["
        '["pv=p1\\u0020lat:/api/vote=0,3,1\\u0020rb:/api/vote=1\\u0020gap=900,12000\\u0020rep:aaaa1111=2\\u0020rep:dddd4444=1\\u0020inp=184:pointer:vf-vote\\u0020lcp=1200:vf-q","chrome\\u0020phone"],'
        '["pv=p1\\u0020lat:/api/vote=0,1\\u0020inp=240:pointer:vf-vote","chrome\\u0020phone"],'
        '["pv=p2\\u0020lat:/api/answer=0,0,0,1\\u0020rep:cccc3333=1\\u0020inp=missing\\u0020lcp=missing","safari\\u0020computer"]]',
        "INFO summary-batch summaries=2 dropped=1 data=["
        '["pv=p3\\u0020owner=1\\u0020lat:/api/vote=9\\u0020inp=16:pointer:vf-x","chrome\\u0020computer"],'
        '["pv=p4\\u0020vitals=missing\\u0020gap=300","firefox\\u0020tablet"]]',
    ]

    def setUp(self):
        self.d = tmpdir(self)
        self.base = datetime.datetime.now().replace(microsecond=0) - datetime.timedelta(minutes=5)
        (self.d / "server.log").write_text("".join(f"{self.at(i)},000 {line}\n" for i, line in enumerate(self.LINES)), encoding="utf-8")

    def at(self, i):
        """The time of LINES[i]: one second after the line before it."""
        return (self.base + datetime.timedelta(seconds=i)).strftime("%Y-%m-%d %H:%M:%S")

    def test_json_gives_every_aggregate(self):
        code, out, err = share(self.d, "logs", "--summary", "--json")
        self.assertEqual(code, 0, err)
        self.assertEqual(out["errors"], [
            # aaaa1111: its entry is LINES[6] and its last repeats come in LINES[11]'s summary.
            {"fp": "aaaa1111", "kind": "error", "message": "TypeError: x is undefined", "source": "/app.js:12", "count": 3,
             "firstSeen": self.at(6), "lastSeen": self.at(11), "devices": {"phone": 1}, "browsers": {"chrome": 1}},
            {"fp": "bbbb2222", "kind": "error", "message": "boom", "source": "", "count": 1, "firstSeen": self.at(7), "lastSeen": self.at(7), "devices": {"computer": 1}, "browsers": {"safari": 1}},
        ])
        self.assertEqual(out["refusals"], [{"route": "/api/answer", "code": "locked", "count": 2}, {"route": "/api/vote", "code": "slow-down", "count": 1}])
        self.assertEqual(out["network"], [{"route": "/api/vote", "code": "network", "count": 2}])
        self.assertEqual(out["latency"], {
            "/api/answer": {"actions": 1, "p50Ms": 500, "p95Ms": 500, "rollbacks": 0, "rollbackRate": 0.0, "serverP50Ms": 2.0, "serverP95Ms": 4.0},
            "/api/vote": {"actions": 5, "p50Ms": 200, "p95Ms": 300, "rollbacks": 1, "rollbackRate": 0.2, "serverP50Ms": 3.0, "serverP95Ms": 5.0},
        })
        self.assertEqual(out["rollbacks"], {"count": 1, "actions": 6, "rate": 0.1667})
        self.assertEqual(out["reconnect"], {"count": 3, "over10s": 1, "worstMs": 12000, "byDevice": {"phone": 2, "tablet": 1}})
        self.assertEqual(out["layout"], [{"anomaly": "overflow", "at": "vf-body", "device": "phone", "count": 2}])
        self.assertEqual(out["inp"], {"p75Ms": 240, "pages": 1, "byDevice": {"phone": 240}, "missing": 2})
        self.assertEqual(out["lcp"], {"p75Ms": 1200, "pages": 1, "byDevice": {"phone": 1200}, "missing": 2})
        self.assertEqual(out["summaries"], {"count": 5, "batches": 2, "pages": 4, "ownerPages": 1, "dropped": 1})
        self.assertEqual(out["repeatsUnmatched"], 0)

    def test_text_reads_the_same_counts_and_share_sh_prints_it(self):
        # A bare "bash" is found by CreateProcess on Windows, which searches System32 (the WSL relay) before PATH.
        bash = shutil.which("bash")
        p = subprocess.run([bash, str(Path(share_cli.__file__).with_name("share.sh")), "--dir", str(self.d), "logs", "--summary"], capture_output=True, text=True, timeout=60, env=env())
        self.assertEqual(p.returncode, 0, p.stderr)
        for want in (
            "Summaries: 5 in 2 batches from 4 page views (1 of them the owner's, left out of the timings). A page with recording turned off sends none. 1 more did not fit in their batch.",
            f"  3x error: TypeError: x is undefined /app.js:12 (phone 1; chrome 1), first {self.at(6)}, last {self.at(11)}",
            "  /api/answer locked: 2",
            "  /api/vote network: 2",
            "  /api/vote: 5 actions, p50 up to 200 ms, p95 up to 300 ms; server p50 3.0 ms, p95 5.0 ms; rollbacks 1 (20.0%)",
            "  Rollback rate: 1 of 6 actions (16.7%)",
            "Reconnect gaps after the page shows again: 3, 1 over 10 s, worst 12000 ms (phone 2, tablet 1)",
            "  overflow at vf-body, phone: 2",
            "INP p75: 240 ms over 1 page views (phone 240); API missing on 2",
            "LCP p75: 1200 ms over 1 page views (phone 1200); API missing on 2",
        ):
            self.assertIn(want, p.stdout.splitlines())
        self.assertFalse(p.stdout.startswith("{"))

    def test_an_empty_log_summarizes_to_nothing(self):
        code, out, err = share(tmpdir(self), "logs", "--summary", "--json")
        self.assertEqual(code, 0, err)
        self.assertEqual((out["errors"], out["latency"], out["inp"]["p75Ms"], out["summaries"]), ([], {}, None, {"count": 0, "batches": 0, "pages": 0, "ownerPages": 0, "dropped": 0}))


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

    def test_the_page_helper_loads_no_module_from_the_data_folder(self):
        self.d.mkdir(parents=True, exist_ok=True)
        planted = self.d / "planted-module-ran"
        (self.d / "contextlib.py").write_text(
            f"open({str(planted)!r}, 'w').close()\n"
            "class suppress:\n"
            "    def __init__(self, *kinds): self.kinds = kinds\n"
            "    def __enter__(self): return self\n"
            "    def __exit__(self, kind, *rest): return kind is not None and issubclass(kind, self.kinds)\n",
            encoding="utf-8",
        )
        with mock.patch.dict(os.environ, {"SHARED_OPEN_SECONDS": "0"}), mock.patch.object(share_cli.webbrowser, "open", return_value=True):
            share_cli.open_link(self.d, "http://127.0.0.1:1/#owner=x")
        self.assertTrue(wait_for(lambda: not list(self.d.glob(share_cli.OPEN_PAGE.format("*"))), seconds=10), "the helper never ran")
        self.assertFalse(planted.exists(), "the helper imported contextlib.py from the data folder")


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


class TestRestartFromE27acc5(ShareCase):
    """A state.json e27acc5's session.py wrote (tests/fixtures/state-written-e27acc5.json; Ann's secret is tok0003x32)
    starts, survives `share.sh restart` as it was, and then takes an upload: its keys are all optional."""

    def test_a_state_e27acc5_wrote_survives_restart_and_takes_an_upload(self):
        fixture = Path(__file__).resolve().parent / "fixtures" / "state-written-e27acc5.json"
        detached.make_private_dir(self.d)
        detached.write_private(self.d / "state.json", fixture.read_text(encoding="utf-8"))
        code, _, err = share(self.d, "ensure-running")
        self.assertEqual(code, 0, err)
        ann = {"X-Session-Secret": "tok0003x32"}
        _, _, before = call(self.guest_port(), "GET", "/api/state?since=0", headers=ann)
        code, _, err = share(self.d, "restart")
        self.assertEqual(code, 0, err)
        _, _, after = call(self.guest_port(), "GET", "/api/state?since=0", headers=ann)
        self.assertEqual((after["cards"], after["questions"], after["chat"]), (before["cards"], before["questions"], before["chat"]))
        self.assertEqual(sorted(c["text"] for c in after["cards"]["Q1"] if c["kind"] == "person"), ["Card first, then saved.", "Saved method first."])
        self.assertEqual((after["myUploads"], after["files"], after["settings"]["uploads"]), ([], {}, False))
        owner = {"X-Owner-Token": self.owner_token()}
        self.assertEqual(call(self.guest_port(), "POST", "/api/session/settings", {"uploads": True}, owner)[0], 200)
        code, _, out = call(self.guest_port(), "POST", "/api/upload/offer", {"file": "funnel.pdf", "size": 9, "type": "application/pdf", "qid": "Q1"}, ann)
        self.assertEqual((code, out.get("status")), (200, "offered"), out)


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


PROTO = Path(__file__).resolve().parent / "fixtures" / "state-v0-prototype.json"
ANN_SECRET = "fixture-guest-secret-ann-not-a-real-secret-000"
PROTO_OWNER = "fixture-owner-token-0001"


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


class TestImport(ShareCase):
    """ensure-running --import --guest-port --adopt-tunnel: the prototype's session moves onto the
    plugin with its state, its port and its running cloudflared (PLAN Phase 3b item 2)."""

    def setUp(self):
        super().setUp()
        self.port = free_port()
        self.args = self.root / "cf-args.txt"
        self.cf, self.url = self.outside_cloudflared(self.port)

    def outside_cloudflared(self, port):
        """A fake cloudflared to `port` that share.py did not start, as the prototype's is."""
        return outside_cloudflared(self, f"http://127.0.0.1:{port}", self.root / f"outside-{port}.log", environ=env(FAKE_CF_ARGS=str(self.args)))

    def ensure(self, *extra, port=None, pid=None, url=None, source=PROTO):
        args = ["ensure-running", "--import", str(source), "--guest-port", str(port or self.port), "--adopt-tunnel", str(pid or self.cf.pid), url or self.url]
        return share(self.d, *args, *extra, environ=env(FAKE_CF_ARGS=str(self.args)))

    def runs(self):
        return self.args.read_text(encoding="utf-8").splitlines() if self.args.exists() else []

    def test_import_and_adopt_keep_the_guest_link_state_and_cloudflared(self):
        code, out, err = self.ensure()
        self.assertEqual(code, 0, err)
        self.assertEqual(out["guestUrl"], f"{self.url}/#join=guest-key-aaaa")
        self.assertEqual((out["localUrl"], out["tunnel"], out["shareChanged"]), (f"http://127.0.0.1:{self.port}/", "quick", False))
        rec = tunnel.read(self.d)
        self.assertEqual((rec["pid"], rec["url"], rec["port"], rec["adopted"]), (self.cf.pid, self.url, self.port, True))
        self.assertEqual(len(self.runs()), 1)  # only the outside one: nothing new was started
        _, _, snap = call(self.port, "GET", "/api/state?since=0", headers={"X-Session-Secret": ANN_SECRET})
        self.assertEqual(snap["me"]["pid"], "pidAnn001")
        _, _, snap = call(self.port, "GET", "/api/state?since=0", headers={"X-Owner-Token": PROTO_OWNER})
        self.assertEqual(snap["me"]["role"], "owner")
        self.assertTrue((self.d / "state.v0.json").is_file())

    def test_restart_keeps_the_port_the_adopted_tunnel_the_link_and_the_state(self):
        code, first, err = self.ensure()
        self.assertEqual(code, 0, err)
        code, out, err = share(self.d, "restart", environ=env(FAKE_CF_ARGS=str(self.args)))
        self.assertEqual(code, 0, err)
        self.assertEqual((out["guestUrl"], out["localUrl"]), (first["guestUrl"], first["localUrl"]))
        self.assertEqual(tunnel.read(self.d)["pid"], self.cf.pid)
        self.assertIsNone(self.cf.poll())
        _, _, snap = call(self.port, "GET", "/api/state?since=0", headers={"X-Session-Secret": ANN_SECRET})
        self.assertEqual((snap["me"]["pid"], snap["title"]), ("pidAnn001", "Fixture checkout session"))
        self.assertEqual(len(self.runs()), 1)

    def test_an_adopted_tunnel_that_exits_is_restarted_and_the_new_link_recorded(self):
        code, first, err = self.ensure()
        self.assertEqual(code, 0, err)
        self.cf.kill()
        self.cf.wait()
        new = wait_for(lambda: (u := share(self.d, "url")[1]["guestUrl"]) != first["guestUrl"] and u, seconds=30, step=0.5)
        self.assertRegex(new, r"^https://fake-[0-9a-f]{12}\.trycloudflare\.com/#join=guest-key-aaaa$")
        _, _, snap = call(self.port, "GET", "/api/state?since=0", headers={"X-Owner-Token": PROTO_OWNER})
        self.assertIn("changedAt", snap["share"])

    def test_the_flags_may_come_from_defaults_json(self):
        self.d.mkdir(parents=True)
        (self.d / "defaults.json").write_text(json.dumps({"import": str(PROTO), "guestPort": self.port, "adoptTunnel": {"pid": self.cf.pid, "url": self.url}}), encoding="utf-8")
        code, out, err = share(self.d, "ensure-running", environ=env(FAKE_CF_ARGS=str(self.args)))
        self.assertEqual(code, 0, err)
        self.assertEqual(out["localUrl"], f"http://127.0.0.1:{self.port}/")
        self.assertEqual(tunnel.read(self.d)["pid"], self.cf.pid)

    def assert_nothing_started(self):
        self.assertFalse((self.d / "state.json").exists())
        self.assertIsNone(tunnel.read(self.d))
        self.assertIsNone(self.cf.poll())

    def test_a_busy_port_is_refused_with_exit_2(self):
        busy = socket.socket()
        busy.bind(("127.0.0.1", self.port))
        busy.listen()
        self.addCleanup(busy.close)
        code, _, err = self.ensure()
        self.assertEqual(code, 2)
        self.assertIn("busy", err)
        self.assert_nothing_started()

    def test_a_pid_that_is_not_a_running_cloudflared_is_refused_with_exit_1(self):
        code, _, err = self.ensure(pid=os.getpid())
        self.assertEqual(code, 1)
        self.assertIn("no cloudflared", err)
        self.assert_nothing_started()

    def test_a_cloudflared_to_another_port_is_refused_with_exit_1(self):
        code, _, err = self.ensure(port=free_port())
        self.assertEqual(code, 1)
        self.assertIn("does not point at port", err)
        self.assert_nothing_started()

    def test_an_existing_session_is_refused_with_exit_1_and_left_as_it_was(self):
        code, _, err = self.ensure()
        self.assertEqual(code, 0, err)
        before = (self.d / "state.json").read_bytes()
        code, _, err = self.ensure()
        self.assertEqual(code, 1)
        self.assertIn("already exists", err)
        self.assertEqual((self.d / "state.json").read_bytes(), before)
        self.assertEqual(tunnel.read(self.d)["pid"], self.cf.pid)

    def test_stop_leaves_the_adopted_cloudflared_running_and_says_so(self):
        code, _, err = self.ensure()
        self.assertEqual(code, 0, err)
        code, out, err = share(self.d, "stop")
        self.assertEqual(code, 0, err)
        self.assertNotIn("tunnel", out["stopped"])
        self.assertIn(f"pid {self.cf.pid}) keeps running", err)
        self.assertIsNone(self.cf.poll())
        self.assertIsNone(tunnel.read(self.d))

    def test_a_server_start_that_fails_another_way_forgets_the_adopted_tunnel_and_leaves_it_running(self):
        a = share_cli.parser().parse_args(["--dir", str(self.d), "ensure-running", "--import", str(PROTO), "--guest-port", str(self.port), "--adopt-tunnel", str(self.cf.pid), self.url])
        with mock.patch.dict(os.environ, env(FAKE_CF_ARGS=str(self.args))), mock.patch.object(share_cli, "start_server", side_effect=TimeoutError("the server lock timed out")):
            with self.assertRaises(TimeoutError):
                share_cli.bring_up(self.d, a)
        self.assertIsNone(tunnel.read(self.d))
        self.assertIsNone(self.cf.poll())

    def test_a_state_file_that_does_not_migrate_is_refused_and_the_tunnel_left_running(self):
        bad = self.root / "not-a-session.json"
        bad.write_text(json.dumps({"title": "x"}), encoding="utf-8")
        code, _, err = self.ensure(source=bad)
        self.assertEqual(code, 1, err)
        self.assert_nothing_started()


@unittest.skipIf(WINDOWS, "share.sh runs under Git Bash there; the Python entry point is tested above")
class TestShareSh(ShareCase):
    def run_sh(self, *args, environ=None):
        sh = Path(__file__).resolve().parent.parent / "share.sh"
        return subprocess.run(["bash", str(sh), "--dir", str(self.d), *args], capture_output=True, text=True, timeout=60, env=environ or env())

    def test_share_sh_runs_share_py(self):
        p = self.run_sh("status")
        self.assertEqual(p.returncode, 1)  # no data dir yet
        self.assertIn("no such data dir", p.stderr)

    def test_share_sh_runs_python_isolated_from_the_environment(self):
        planted = self.root / "planted"
        planted.mkdir()
        marker = self.root / "ran"
        (planted / "sitecustomize.py").write_text(f"open({str(marker)!r}, 'w').close()\n", encoding="utf-8")
        p = self.run_sh("status", environ=env(PYTHONPATH=str(planted)))
        self.assertEqual(p.returncode, 1, p.stderr)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()

"""tunnel.py: start, address parse, reattach, exit detection and restart, adopt, stop.

Every run uses tests/fixtures/fake-cloudflared.sh (fake_cloudflared.py on Windows), which prints
the quick-tunnel banner cloudflared 2026.9.3 prints, with a new trycloudflare.com address per run.
"""

from __future__ import annotations

import json
import os
import re
import stat
import subprocess
import sys
import time
import unittest
from pathlib import Path
from unittest import mock

from support import FAKE, WINDOWS, tmpdir, wait_for

import detached
import tunnel

ADDRESS = re.compile(r"^https://fake-[0-9a-f]{12}\.trycloudflare\.com$")


class TunnelCase(unittest.TestCase):
    def setUp(self):
        self.d = tmpdir(self)
        self.args = self.d / "cf-args.txt"
        patcher = mock.patch.dict(os.environ, {"SHARED_CLOUDFLARED": FAKE, "FAKE_CF_ARGS": str(self.args), "SHARED_TUNNEL_SECONDS": "10"})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(tunnel.stop, self.d)

    def runs(self):
        return self.args.read_text(encoding="utf-8").splitlines() if self.args.exists() else []

    def fake_process(self):
        """A fake cloudflared started outside tunnel.py, as a running session's would be."""
        cmd = [sys.executable, FAKE] if FAKE.endswith(".py") else [FAKE]
        log = self.d / "outside.log"
        proc = detached.spawn([*cmd, "tunnel", "--no-autoupdate", "--url", "http://localhost:8765"], log=log)
        self.addCleanup(lambda: (proc.kill(), proc.wait()))
        url = wait_for(lambda: (m := tunnel.URL.search(log.read_text(encoding="utf-8"))) and m.group(0))
        return proc, url


class TestStart(TunnelCase):
    def test_start_points_cloudflared_at_the_guest_port_and_records_its_address(self):
        rec = tunnel.ensure(self.d, 4321)
        self.assertRegex(rec["url"], ADDRESS)
        self.assertEqual(self.runs(), ["tunnel --no-autoupdate --url http://127.0.0.1:4321"])
        on_disk = json.loads((self.d / tunnel.RECORD).read_text(encoding="utf-8"))
        self.assertEqual((on_disk["pid"], on_disk["url"], on_disk["port"]), (rec["pid"], rec["url"], 4321))
        self.assertIn("startedAt", on_disk)

    @unittest.skipIf(WINDOWS, "file modes are advisory on Windows")
    def test_the_record_is_private(self):
        tunnel.ensure(self.d, 4321)
        self.assertEqual(stat.S_IMODE((self.d / tunnel.RECORD).stat().st_mode), 0o600)

    def test_the_address_is_the_one_in_the_banner(self):
        rec = tunnel.ensure(self.d, 4321)
        banner = (self.d / tunnel.LOG).read_text(encoding="utf-8")
        self.assertIn(f"|  {rec['url']} ", banner)

    def test_a_second_ensure_reattaches_without_starting_another(self):
        first = tunnel.ensure(self.d, 4321)
        second = tunnel.ensure(self.d, 4321)
        self.assertEqual((second["pid"], second["url"]), (first["pid"], first["url"]))
        self.assertEqual(len(self.runs()), 1)

    def test_a_tunnel_to_another_port_is_replaced(self):
        first = tunnel.ensure(self.d, 4321)
        second = tunnel.ensure(self.d, 4322)
        self.assertNotEqual(second["url"], first["url"])
        self.assertFalse(detached.alive(first["pid"], first["marker"]))
        self.assertEqual(self.runs()[-1], "tunnel --no-autoupdate --url http://127.0.0.1:4322")

    def test_no_address_in_time_raises_and_leaves_nothing_running(self):
        with mock.patch.dict(os.environ, {"FAKE_CF_NOURL": "1", "SHARED_TUNNEL_SECONDS": "1"}):
            with self.assertRaises(tunnel.TunnelDown):
                tunnel.ensure(self.d, 4321)
        self.assertIsNone(tunnel.read(self.d))

    def test_a_missing_cloudflared_is_named(self):
        with mock.patch.dict(os.environ, {"SHARED_CLOUDFLARED": "", "PATH": str(self.d)}):
            with self.assertRaisesRegex(tunnel.TunnelDown, "missing prerequisite: cloudflared"):
                tunnel.ensure(self.d, 4321)

    def test_cloudflared_outlives_the_process_that_started_it(self):
        code = f"import sys; sys.path.insert(0, {str(Path(tunnel.__file__).parent)!r}); import tunnel; print(tunnel.ensure({str(self.d)!r}, 4321)['pid'])"
        out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, timeout=60, env=dict(os.environ))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIsNotNone(tunnel.alive(self.d))
        self.assertEqual(tunnel.alive(self.d)["pid"], int(out.stdout.strip()))


class TestExit(TunnelCase):
    def test_an_exited_tunnel_is_not_alive_and_ensure_starts_one_with_a_new_address(self):
        first = tunnel.ensure(self.d, 4321)
        detached.stop(first["pid"], first["marker"])
        self.assertIsNone(tunnel.alive(self.d))
        second = tunnel.ensure(self.d, 4321)
        self.assertNotEqual(second["url"], first["url"])
        self.assertIsNotNone(tunnel.alive(self.d))

    def test_a_pid_the_os_gave_to_another_program_is_not_alive(self):
        rec = tunnel.ensure(self.d, 4321)
        rec["pid"] = os.getpid()  # this test runner: alive, but not cloudflared
        (self.d / tunnel.RECORD).write_text(json.dumps(rec), encoding="utf-8")
        self.assertIsNone(tunnel.alive(self.d))
        self.assertTrue(detached._running(os.getpid()))

    def test_stop_ends_cloudflared_and_drops_the_record(self):
        rec = tunnel.ensure(self.d, 4321)
        self.assertTrue(tunnel.stop(self.d))
        self.assertFalse(detached.alive(rec["pid"], rec["marker"]))
        self.assertIsNone(tunnel.read(self.d))


class TestAdopt(TunnelCase):
    def test_adopt_records_a_running_cloudflared_and_starts_nothing(self):
        proc, url = self.fake_process()
        rec = tunnel.adopt(self.d, proc.pid, url, 8765)
        self.assertEqual((rec["pid"], rec["url"], rec["port"], rec["adopted"]), (proc.pid, url, 8765, True))
        self.assertEqual(tunnel.ensure(self.d, 8765)["url"], url)
        self.assertEqual(self.runs(), ["tunnel --no-autoupdate --url http://localhost:8765"])

    def test_an_adopted_tunnel_that_exits_is_restarted_like_any_other(self):
        proc, url = self.fake_process()
        tunnel.adopt(self.d, proc.pid, url, 8765)
        proc.kill()
        proc.wait()
        self.assertIsNone(tunnel.alive(self.d))
        new = tunnel.ensure(self.d, 8765)
        self.assertNotEqual(new["url"], url)
        self.assertFalse(new["adopted"])

    def test_adopt_refuses_a_pid_that_is_not_cloudflared(self):
        with self.assertRaisesRegex(tunnel.TunnelDown, "no cloudflared"):
            tunnel.adopt(self.d, os.getpid(), "https://fake-000000000000.trycloudflare.com", 8765)
        self.assertIsNone(tunnel.read(self.d))

    def test_adopt_refuses_an_address_that_is_not_a_quick_tunnel(self):
        proc, _ = self.fake_process()
        with self.assertRaises(tunnel.TunnelDown):
            tunnel.adopt(self.d, proc.pid, "https://example.com", 8765)

    def test_the_adopt_command_prints_the_record(self):
        proc, url = self.fake_process()
        out = subprocess.run(
            [sys.executable, tunnel.__file__, "adopt", "--dir", str(self.d), "--pid", str(proc.pid), "--url", url, "--port", "8765"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(json.loads(out.stdout)["url"], url)


if __name__ == "__main__":
    unittest.main()

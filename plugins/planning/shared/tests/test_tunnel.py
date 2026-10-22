"""tunnel.py: start, address parse, reattach, exit detection and restart, adopt, stop, the named tunnel and a switch.

Every run uses tests/fixtures/fake-cloudflared.sh (fake_cloudflared.py on Windows), which prints
the quick-tunnel banner cloudflared 2026.9.3 prints, with a new trycloudflare.com address per run,
or for a named tunnel the "Registered tunnel connection" line cloudflared's connection/observer.go logs.
"""

from __future__ import annotations

import json
import os
import re
import stat
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

from support import FAKE, FIXTURES, WINDOWS, outside_cloudflared, tmpdir

import detached
import liveserve
import tunnel

ADDRESS = re.compile(r"^https://fake-[0-9a-f]{12}\.trycloudflare\.com$")


class TestCommand(unittest.TestCase):
    def test_a_python_cloudflared_runs_in_isolated_mode(self):
        self.assertEqual(tunnel._command("/opt/cf/cloudflared.py", 8080)[1:3], ["-I", "/opt/cf/cloudflared.py"])


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

    def fake_process(self, url_arg="http://localhost:8765", *extra, named=True):
        """A fake cloudflared started outside tunnel.py, as a running session's would be."""
        return outside_cloudflared(self, url_arg, tmpdir(self) / "outside.log", *extra, named=named)


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


class Exited:
    """A cloudflared that already exited, for reading a log it left."""

    def poll(self):
        return 1


class TestAddress(unittest.TestCase):
    """The address comes from the banner's boxed line, never from cloudflared's own API host, which
    its error lines name (fixtures/cloudflared-api-error.log, written in the shape of those lines)."""

    def test_an_error_line_naming_the_api_host_is_no_address(self):
        self.assertIsNone(tunnel._wait_url(Exited(), FIXTURES / "cloudflared-api-error.log", 0.5))

    def test_the_banner_line_after_an_error_line_is_the_address(self):
        log = tmpdir(self) / "cloudflared.log"
        banner = "2026-10-16T10:00:05Z INF |  https://calm-river-0a1b.trycloudflare.com                                  |\n"
        log.write_text((FIXTURES / "cloudflared-api-error.log").read_text(encoding="utf-8") + banner, encoding="utf-8")
        self.assertEqual(tunnel._wait_url(Exited(), log, 0.5), "https://calm-river-0a1b.trycloudflare.com")

    def test_adopt_refuses_the_api_host(self):
        with self.assertRaisesRegex(tunnel.TunnelDown, "not a trycloudflare.com address"):
            tunnel.adopt(tmpdir(self), os.getpid(), "https://api.trycloudflare.com", 8765)


class TestProgramName(unittest.TestCase):
    """The program the OS reports for a pid is the file it runs, whatever its arguments say."""

    def test_a_program_named_cloudflared_is_reported_by_that_name_with_its_arguments(self):
        d = tmpdir(self)
        proc, _ = outside_cloudflared(self, "http://127.0.0.1:4321", d / "cf.log")
        self.assertEqual(detached.exe_name(proc.pid).lower(), tunnel.EXE)
        self.assertEqual(detached.command_line(proc.pid)[-4:], ["tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:4321"])

    def test_a_script_that_names_cloudflared_is_reported_as_its_interpreter(self):
        d = tmpdir(self)
        proc, _ = outside_cloudflared(self, "http://127.0.0.1:4321", d / "cf.log", named=False)
        self.assertNotIn("cloudflared", detached.exe_name(proc.pid).lower())

    def test_a_pid_that_does_not_run_has_no_program_name(self):
        proc = subprocess.Popen([sys.executable, "-c", ""])
        proc.wait()
        self.assertIsNone(detached.exe_name(proc.pid))


class TestUrlArgument(unittest.TestCase):
    def test_the_one_url_value_is_read_in_each_spelling(self):
        for args in (["tunnel", "--url", "http://127.0.0.1:1"], ["tunnel", "--url=http://127.0.0.1:1"], ["tunnel", "-url", "http://127.0.0.1:1"]):
            self.assertEqual(tunnel._url_arg(args), "http://127.0.0.1:1", args)

    def test_no_url_or_two_is_none(self):
        self.assertIsNone(tunnel._url_arg(["tunnel", "--metrics", "localhost:1"]))
        self.assertIsNone(tunnel._url_arg(["tunnel", "--url", "http://127.0.0.1:1", "--url", "http://127.0.0.1:2"]))
        self.assertIsNone(tunnel._url_arg(["tunnel", "--url"]))


class TestWindowsLookup(unittest.TestCase):
    """On Windows the program search looks in the current folder first unless
    NoDefaultCurrentDirectoryInExePath is set, so a planted cloudflared.exe there would run."""

    def lookup(self, found):
        seen = {}

        def which(name):
            seen["flag"] = os.environ.get("NoDefaultCurrentDirectoryInExePath")
            return found

        with mock.patch.object(detached, "WINDOWS", True), mock.patch.object(detached.shutil, "which", side_effect=which), mock.patch.dict(os.environ, {"SHARED_CLOUDFLARED": ""}):
            return tunnel.binary(), seen["flag"]

    def test_a_cloudflared_in_the_current_folder_is_refused(self):
        self.assertEqual(self.lookup(str(Path.cwd() / "cloudflared.exe")), (None, "1"))

    def test_a_cloudflared_elsewhere_on_path_is_used(self):
        elsewhere = str(tmpdir(self) / "cloudflared.exe")
        self.assertEqual(self.lookup(elsewhere), (elsewhere, "1"))


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
        self.addCleanup(detached.stop, rec["pid"], rec["marker"])
        rec["pid"] = os.getpid()  # this test runner: alive, but not cloudflared
        (self.d / tunnel.RECORD).write_text(json.dumps(rec), encoding="utf-8")
        self.assertIsNone(tunnel.alive(self.d))
        self.assertTrue(detached._running(os.getpid()))

    def test_a_pid_the_os_gave_to_a_program_with_the_same_name_is_neither_alive_nor_stopped(self):
        """The marker is only a program name: another cloudflared, or on POSIX any command line that
        names it (`tail cloudflared.log`), carries it too. Only our process's start tells them apart."""
        rec = tunnel.ensure(self.d, 4321)
        self.addCleanup(detached.stop, rec["pid"], rec["marker"])
        other = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)", rec["marker"]])
        self.addCleanup(lambda: (other.kill(), other.wait()))
        self.assertTrue(detached.alive(other.pid, rec["marker"]))  # the name alone would pass it
        rec["pid"] = other.pid
        (self.d / tunnel.RECORD).write_text(json.dumps(rec), encoding="utf-8")
        self.assertIsNone(tunnel.alive(self.d))
        self.assertFalse(tunnel.stop(self.d))
        self.assertIsNone(other.poll())

    def test_a_record_whose_start_cannot_be_read_is_not_alive(self):
        tunnel.ensure(self.d, 4321)
        with mock.patch.object(detached, "started", return_value=None):
            self.assertIsNone(tunnel.alive(self.d))

    def legacy(self, **changes):
        """The record as a build before processStart wrote it, with `changes` applied."""
        rec = json.loads((self.d / tunnel.RECORD).read_text(encoding="utf-8"))
        rec.pop("processStart")
        rec.update(changes)
        (self.d / tunnel.RECORD).write_text(json.dumps(rec), encoding="utf-8")
        return rec

    def test_a_record_from_before_process_start_that_is_still_the_tunnel_keeps_its_link(self):
        first = tunnel.ensure(self.d, 4321)
        self.legacy()
        self.assertEqual(tunnel.ensure(self.d, 4321)["url"], first["url"])
        self.assertEqual(len(self.runs()), 1)
        self.assertEqual(tunnel.read(self.d)["processStart"], detached.started(first["pid"]))

    def test_a_record_from_before_process_start_naming_another_program_of_the_name_is_not_ours(self):
        rec = tunnel.ensure(self.d, 4321)
        self.addCleanup(detached.stop, rec["pid"], rec["marker"])
        other = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)", rec["marker"]])
        self.addCleanup(lambda: (other.kill(), other.wait()))
        self.legacy(pid=other.pid)
        self.assertIsNone(tunnel.alive(self.d))
        self.assertNotIn("processStart", tunnel.read(self.d))
        self.assertFalse(tunnel.stop(self.d))
        self.assertIsNone(other.poll())

    def test_a_record_from_before_process_start_naming_a_tunnel_to_another_port_is_not_ours(self):
        rec = tunnel.ensure(self.d, 4321)
        self.addCleanup(detached.stop, rec["pid"], rec["marker"])
        other, _ = self.fake_process("http://127.0.0.1:9", named=False)
        self.assertTrue(detached.alive(other.pid, rec["marker"]))  # the name alone would pass it
        self.legacy(pid=other.pid)
        self.assertIsNone(tunnel.alive(self.d))
        self.assertNotIn("processStart", tunnel.read(self.d))
        self.assertFalse(tunnel.stop(self.d))
        self.assertIsNone(other.poll())

    def test_a_record_from_before_process_start_whose_command_line_cannot_be_read_is_not_ours(self):
        tunnel.ensure(self.d, 4321)
        rec = self.legacy()
        with mock.patch.object(detached, "command_line", return_value=None):
            self.assertIsNone(tunnel.alive(self.d))
            self.assertNotIn("processStart", tunnel.read(self.d))
            # On Windows too: the image path alone never stands in for the command line.
            with mock.patch.object(detached, "WINDOWS", True), mock.patch.object(detached, "alive", return_value=True), mock.patch.object(detached, "started", return_value="1"):
                self.assertIsNone(tunnel._legacy_start(rec))
        self.assertIsNotNone(tunnel.alive(self.d))  # readable again, the same record is the tunnel

    def test_a_record_from_before_process_start_naming_this_process_is_never_ours(self):
        rec = tunnel.ensure(self.d, 4321)
        self.addCleanup(detached.stop, rec["pid"], rec["marker"])
        me = os.getpid()
        self.legacy(pid=me, marker=detached.describe(me))
        tunnel_args = ["cloudflared", "tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:4321"]
        with mock.patch.object(detached, "command_line", return_value=tunnel_args), mock.patch.object(detached.os, "kill") as kill:
            self.assertIsNone(tunnel.alive(self.d))
            self.assertFalse(tunnel.stop(self.d))
        kill.assert_not_called()

    def test_stop_never_signals_this_process(self):
        me = os.getpid()
        with mock.patch.object(detached.os, "kill") as kill:
            self.assertFalse(detached.stop(me, detached.describe(me), detached.started(me)))
        kill.assert_not_called()

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

    def test_adopt_refuses_a_program_that_has_cloudflared_only_in_its_arguments(self):
        proc, url = self.fake_process(named=False)  # bash (python on Windows) running fake-cloudflared
        self.assertIn("cloudflared", " ".join(detached.command_line(proc.pid)))
        with self.assertRaisesRegex(tunnel.TunnelDown, "no cloudflared runs as pid"):
            tunnel.adopt(self.d, proc.pid, url, 8765)
        self.assertIsNone(tunnel.read(self.d))

    def test_adopt_refuses_a_metrics_address_that_names_the_port(self):
        proc, url = self.fake_process("http://127.0.0.1:9", "--metrics", "localhost:8765")
        with self.assertRaisesRegex(tunnel.TunnelDown, "does not point at port 8765"):
            tunnel.adopt(self.d, proc.pid, url, 8765)
        self.assertIsNone(tunnel.read(self.d))

    def test_adopt_refuses_a_url_to_another_host(self):
        proc, url = self.fake_process("http://192.0.2.1:8765")
        with self.assertRaisesRegex(tunnel.TunnelDown, "does not point at port 8765"):
            tunnel.adopt(self.d, proc.pid, url, 8765)

    def test_adopt_refuses_when_the_command_line_cannot_be_read(self):
        proc, url = self.fake_process()
        with mock.patch.object(detached, "command_line", return_value=None), self.assertRaisesRegex(tunnel.TunnelDown, "cannot be read"):
            tunnel.adopt(self.d, proc.pid, url, 8765)
        self.assertIsNone(tunnel.read(self.d))

    def test_adopt_refuses_when_the_start_cannot_be_read(self):
        proc, url = self.fake_process()
        with mock.patch.object(detached, "started", return_value=None), self.assertRaisesRegex(tunnel.TunnelDown, "started"):
            tunnel.adopt(self.d, proc.pid, url, 8765)
        self.assertIsNone(tunnel.read(self.d))

    def test_stop_leaves_an_adopted_cloudflared_running_and_drops_the_record(self):
        proc, url = self.fake_process()
        tunnel.adopt(self.d, proc.pid, url, 8765)
        self.assertFalse(tunnel.stop(self.d))
        self.assertIsNone(tunnel.read(self.d))
        self.assertIsNone(proc.poll())

    def test_a_tunnel_to_another_port_forgets_an_adopted_one_without_stopping_it(self):
        proc, url = self.fake_process()
        tunnel.adopt(self.d, proc.pid, url, 8765)
        new = tunnel.ensure(self.d, 4321)
        self.assertFalse(new["adopted"])
        self.assertIsNone(proc.poll())

    def test_the_restarted_tunnel_of_an_adopted_one_that_exited_is_stopped_normally(self):
        proc, url = self.fake_process()
        tunnel.adopt(self.d, proc.pid, url, 8765)
        proc.kill()
        proc.wait()
        new = tunnel.ensure(self.d, 8765)
        self.assertTrue(tunnel.stop(self.d))
        self.assertFalse(detached.alive(new["pid"], new["marker"]))

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


HOST = "interview.example.com"
TOKEN_TEXT = "fake-tunnel-token-for-tests"  # what the token file holds; no output may carry it


def token_file(case, text=TOKEN_TEXT, mode=0o600):
    f = tmpdir(case) / "tunnel.token"
    f.write_text(text, encoding="utf-8")
    os.chmod(f, mode)
    return str(f)


class TestNamed(TunnelCase):
    """A named tunnel: `cloudflared tunnel --no-autoupdate run --token-file F` (run-parameters page) at https://<hostname>."""

    def setUp(self):
        super().setUp()
        self.token = token_file(self)

    def test_it_runs_the_token_file_and_records_the_hostname_as_its_address(self):
        rec = tunnel.ensure(self.d, 4321, HOST, self.token)
        self.assertEqual(self.runs(), [f"tunnel --no-autoupdate run --token-file {self.token}"])
        self.assertEqual((rec["url"], rec["hostname"], rec["tokenFile"], rec["port"]), (f"https://{HOST}", HOST, self.token, 4321))
        self.assertEqual(tunnel.alive(self.d)["url"], f"https://{HOST}")

    def test_the_token_itself_is_in_no_argument_record_or_log(self):
        tunnel.ensure(self.d, 4321, HOST, self.token)
        for f in (self.args, self.d / tunnel.RECORD, self.d / tunnel.LOG):
            self.assertNotIn(TOKEN_TEXT, f.read_text(encoding="utf-8"), f.name)

    def test_a_token_variable_in_this_environment_never_reaches_cloudflared(self):
        """cloudflared's TUNNEL_TOKEN takes precedence over --token-file; the fake exits when either variable reaches it."""
        with mock.patch.dict(os.environ, {"TUNNEL_TOKEN": "other", "TUNNEL_TOKEN_FILE": "/other", "CLOUDFLARE_API_TOKEN": "api", "CF_API_TOKEN": "api"}):
            self.assertEqual(tunnel.ensure(self.d, 4321, HOST, self.token)["url"], f"https://{HOST}")
            tunnel.stop(self.d)
            self.assertRegex(tunnel.ensure(self.d, 4321)["url"], ADDRESS)

    def test_an_exited_named_tunnel_comes_back_at_the_same_address(self):
        first = tunnel.ensure(self.d, 4321, HOST, self.token)
        detached.stop(first["pid"], first["marker"])
        second = tunnel.ensure(self.d, 4321, *tunnel.config(tunnel.read(self.d)))
        self.assertNotEqual(second["pid"], first["pid"])
        self.assertEqual(second["url"], first["url"])
        self.assertNotIn("retired", second)

    def test_a_token_cloudflared_cannot_read_is_down_and_leaves_nothing_running(self):
        with mock.patch.object(tunnel, "token_file_problem", return_value=None):  # past the check, so cloudflared itself refuses it
            with self.assertRaisesRegex(tunnel.TunnelDown, f"no connection for {HOST}"):
                tunnel.ensure(self.d, 4321, HOST, str(self.d / "missing.token"))
        self.assertIsNone(tunnel.read(self.d))

    def test_a_tunnel_that_never_connects_is_down(self):
        with mock.patch.dict(os.environ, {"FAKE_CF_NOURL": "1", "SHARED_TUNNEL_SECONDS": "1"}):
            with self.assertRaisesRegex(tunnel.TunnelDown, "no connection"):
                tunnel.ensure(self.d, 4321, HOST, self.token)
        self.assertIsNone(tunnel.read(self.d))

    def test_a_token_file_that_cannot_serve_is_refused_before_cloudflared_starts(self):
        cases = {"relative": "tunnel.token", "missing": str(self.d / "missing.token"), "empty": token_file(self, text=""), "none": ""}
        if not WINDOWS:
            cases["readable by others"] = token_file(self, mode=0o644)
        for why, path in cases.items():
            with self.subTest(why=why), self.assertRaises(tunnel.TunnelDown):
                tunnel.ensure(self.d, 4321, HOST, path)
        self.assertEqual(self.runs(), [])

    def test_a_hostname_must_be_a_dns_name_and_not_a_quick_tunnel(self):
        for bad in ("https://interview.example.com", "interview", "Interview.Example.com", "a.trycloudflare.com", "x..example.com", "-a.example.com"):
            with self.subTest(bad=bad):
                self.assertIsNotNone(tunnel.hostname_problem(bad))
        self.assertIsNone(tunnel.hostname_problem("planning-interview.melodicsoftware.com"))


ME = "S-1-5-21-1-2-3-1001"  # a user's SID, as a fixture


class TestWindowsTokenFileAcl(unittest.TestCase):
    """On Windows the token file may be readable by its user, its owner (OWNER RIGHTS), SYSTEM and Administrators only,
    as chmod 600 means on POSIX. The ACL reader is mocked here; the Windows-only test below runs the real one."""

    def problem(self, acl):
        f = tmpdir(self) / "tunnel.token"
        f.write_text(TOKEN_TEXT, encoding="utf-8")
        with mock.patch.object(detached, "WINDOWS", True), mock.patch.object(tunnel, "_windows_acl", return_value=acl):
            return tunnel.token_file_problem(str(f))

    def test_the_user_owner_system_and_administrators_pass(self):
        self.assertIsNone(self.problem((ME, [ME, "S-1-5-18", "S-1-5-32-544", "S-1-3-4"])))

    def test_any_other_reader_is_refused_by_sid(self):
        for other in ("S-1-5-32-545", "S-1-1-0", "S-1-5-11", "?"):
            with self.subTest(other=other):
                self.assertIn(f"can be read by others ({other})", self.problem((ME, [ME, "S-1-5-18", other])) or "")

    def test_permissions_that_cannot_be_read_are_refused(self):
        self.assertIn("cannot be read", self.problem(None) or "")

    @unittest.skipUnless(WINDOWS, "the real ACL reader needs Windows")
    def test_the_real_reader_passes_a_private_file_and_refuses_one_everyone_reads(self):
        f = tmpdir(self) / "tunnel.token"
        f.write_text(TOKEN_TEXT, encoding="utf-8")
        subprocess.run(["icacls", str(f), "/inheritance:r", "/grant:r", f"*{tunnel._windows_acl(str(f))[0]}:F"], check=True, capture_output=True)
        self.assertIsNone(tunnel.token_file_problem(str(f)))
        subprocess.run(["icacls", str(f), "/grant", "*S-1-1-0:R"], check=True, capture_output=True)
        self.assertIn("S-1-1-0", tunnel.token_file_problem(str(f)) or "")


class TestSwitch(TunnelCase):
    """A switch to another address keeps the old tunnel running as `retired` for RETIRE_SECONDS, so pages open there
    can move with their identity; a restart at the same address retires nothing."""

    def setUp(self):
        super().setUp()
        self.token = token_file(self)
        self.checked = []

    def reaches(self, url):
        """A verify that passes every address, as server.py's probe does for one that reaches it."""
        self.checked.append(url)

    def test_quick_to_named_keeps_the_quick_tunnel_as_retired(self):
        quick = tunnel.ensure(self.d, 4321, verify=self.reaches)
        named = tunnel.ensure(self.d, 4321, HOST, self.token, verify=self.reaches)
        self.assertEqual(named["retired"]["url"], quick["url"])
        self.assertEqual(tunnel.retired(self.d)["pid"], quick["pid"])
        self.assertTrue(detached.alive(quick["pid"], quick["marker"], quick["processStart"]))
        self.assertFalse(tunnel.sweep(self.d))  # its grace time runs
        self.assertTrue(detached.alive(quick["pid"], quick["marker"], quick["processStart"]))

    def test_a_restart_at_the_same_address_keeps_the_retired_tunnel_and_its_grace_time(self):
        quick = tunnel.ensure(self.d, 4321, verify=self.reaches)
        named = tunnel.ensure(self.d, 4321, HOST, self.token, verify=self.reaches)
        detached.stop(named["pid"], named["marker"], named["processStart"])
        again = tunnel.ensure(self.d, 4321, HOST, self.token, verify=self.reaches)
        self.assertEqual((again["retired"]["pid"], again["retired"]["until"]), (quick["pid"], named["retired"]["until"]))
        self.assertTrue(detached.alive(quick["pid"], quick["marker"], quick["processStart"]))

    def test_named_back_to_quick_retires_the_named_one(self):
        named = tunnel.ensure(self.d, 4321, HOST, self.token, verify=self.reaches)
        quick = tunnel.ensure(self.d, 4321, verify=self.reaches)
        self.assertRegex(quick["url"], ADDRESS)
        self.assertEqual(tunnel.retired(self.d)["url"], named["url"])

    def test_a_retired_tunnel_is_stopped_once_its_grace_time_is_up(self):
        with mock.patch.dict(os.environ, {"SHARED_RETIRE_SECONDS": "0"}):
            quick = tunnel.ensure(self.d, 4321, verify=self.reaches)
            tunnel.ensure(self.d, 4321, HOST, self.token, verify=self.reaches)
        self.assertIsNone(tunnel.retired(self.d))
        self.assertTrue(tunnel.sweep(self.d))
        self.assertFalse(detached.alive(quick["pid"], quick["marker"], quick["processStart"]))
        self.assertNotIn("retired", tunnel.read(self.d))
        self.assertIsNotNone(tunnel.alive(self.d))

    def test_stop_ends_the_retired_tunnel_too(self):
        quick = tunnel.ensure(self.d, 4321, verify=self.reaches)
        named = tunnel.ensure(self.d, 4321, HOST, self.token, verify=self.reaches)
        self.assertTrue(tunnel.stop(self.d))
        for rec in (quick, named):
            self.assertFalse(detached.alive(rec["pid"], rec["marker"], rec["processStart"]))

    def test_a_second_switch_ends_the_tunnel_retired_by_the_first(self):
        quick = tunnel.ensure(self.d, 4321, verify=self.reaches)
        named = tunnel.ensure(self.d, 4321, HOST, self.token, verify=self.reaches)
        tunnel.ensure(self.d, 4321, "other.example.com", self.token, verify=self.reaches)
        self.assertFalse(detached.alive(quick["pid"], quick["marker"], quick["processStart"]))
        self.assertEqual(tunnel.retired(self.d)["url"], named["url"])

    def test_another_token_file_at_the_same_address_retires_nothing(self):
        first = tunnel.ensure(self.d, 4321, HOST, self.token, verify=self.reaches)
        second = tunnel.ensure(self.d, 4321, HOST, token_file(self), verify=self.reaches)
        self.assertNotIn("retired", second)
        self.assertFalse(detached.alive(first["pid"], first["marker"], first["processStart"]))

    def test_a_tunnel_to_another_port_is_ended_not_retired(self):
        quick = tunnel.ensure(self.d, 4321, verify=self.reaches)
        named = tunnel.ensure(self.d, 4322, HOST, self.token, verify=self.reaches)
        self.assertNotIn("retired", named)
        self.assertFalse(detached.alive(quick["pid"], quick["marker"], quick["processStart"]))


    def test_a_switch_the_check_refuses_keeps_the_old_tunnel_and_records_nothing(self):
        quick = tunnel.ensure(self.d, 4321)
        before = (self.d / tunnel.RECORD).read_text(encoding="utf-8")
        with self.assertRaisesRegex(tunnel.TunnelDown, "not switching: elsewhere; the current tunnel keeps running"):
            tunnel.ensure(self.d, 4321, HOST, self.token, verify=lambda url: "elsewhere")
        self.assertEqual((self.d / tunnel.RECORD).read_text(encoding="utf-8"), before)
        self.assertTrue(detached.alive(quick["pid"], quick["marker"], quick["processStart"]))
        self.assertEqual(len(self.runs()), 2)
        self.assertIsNone(tunnel.retired(self.d))

    def test_a_refused_switch_keeps_the_tunnel_retired_before_it(self):
        """Pages still on the retired quick address keep learning where to go when a later switch is refused."""
        tunnel.ensure(self.d, 4321)
        tunnel.ensure(self.d, 4321, HOST, self.token, verify=self.reaches)
        old = tunnel.retired(self.d)
        self.assertIsNotNone(old)
        with self.assertRaises(tunnel.TunnelDown):
            tunnel.ensure(self.d, 4321, "typo.example.com", self.token, verify=lambda url: "elsewhere")
        self.assertTrue(detached.alive(*tunnel._identity(old)))
        self.assertEqual(tunnel.retired(self.d)["pid"], old["pid"])

    def test_a_check_that_raises_is_no_proof(self):
        def broken(url):
            raise OSError("the server did not answer")

        tunnel.ensure(self.d, 4321)
        with self.assertRaisesRegex(tunnel.TunnelDown, "did not run"):
            tunnel.ensure(self.d, 4321, HOST, self.token, verify=broken)
        self.assertNotIn("hostname", tunnel.read(self.d))

    def test_a_switch_with_no_check_retires_nothing(self):
        quick = tunnel.ensure(self.d, 4321)
        named = tunnel.ensure(self.d, 4321, HOST, self.token)
        self.assertNotIn("retired", named)
        self.assertFalse(detached.alive(quick["pid"], quick["marker"], quick["processStart"]))

    def test_the_check_is_asked_about_the_new_address(self):
        tunnel.ensure(self.d, 4321)
        tunnel.ensure(self.d, 4321, HOST, self.token, verify=self.reaches)
        self.assertEqual(self.checked, [f"https://{HOST}"])


class TestLiveRecords(TunnelCase):
    """A live prototype's own quick tunnel, keyed by its record's path under .shared-live/: start, end, sweep. The
    session tunnel's record is never touched."""

    def setUp(self):
        super().setUp()
        self.path = tunnel.live_path(self.d, "L1")
        self.addCleanup(lambda: tunnel.sweep_live(self.d, every=True))

    def static_server(self):
        root = tmpdir(self) / "copy"
        root.mkdir()
        proc, port = liveserve.spawn(root, tmpdir(self) / "serve.log")
        self.addCleanup(lambda: (proc.kill(), proc.wait()))
        self.assertIsNotNone(port)
        return {"pid": proc.pid, "marker": liveserve.MARKER, "processStart": detached.started(proc.pid), "port": port}

    def test_start_runs_a_quick_tunnel_to_the_port_and_records_it_at_its_path_only(self):
        rec = tunnel.start_live(self.path, 4400)
        self.assertRegex(rec["url"], ADDRESS)
        self.assertEqual(self.runs(), ["tunnel --no-autoupdate --url http://127.0.0.1:4400"])
        self.assertEqual(tunnel.read_live(self.path), rec)
        self.assertEqual((rec["id"], rec["port"]), ("L1", 4400))
        self.assertIsNone(tunnel.read(self.d))  # the session's own record stays as it was: absent
        self.assertTrue((self.d / tunnel.LIVE_DIR / "L1.cloudflared.log").is_file())

    @unittest.skipIf(WINDOWS, "file modes are advisory on Windows")
    def test_the_record_and_its_folder_are_private(self):
        tunnel.start_live(self.path, 4400)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.path.parent.stat().st_mode), 0o700)

    def test_a_restart_ends_the_tunnel_it_named_and_keeps_the_server_it_named(self):
        srv = self.static_server()
        tunnel.write_live(self.path, {"id": "L1", "port": srv["port"], "server": srv})
        first = tunnel.start_live(self.path, srv["port"])
        second = tunnel.start_live(self.path, srv["port"])
        self.assertNotEqual(first["url"], second["url"])
        self.assertFalse(tunnel.tunnel_running(first))
        self.assertEqual(second["server"], srv)
        self.assertTrue(tunnel.server_running(second))

    def test_end_stops_the_tunnel_and_the_server_and_keeps_the_record(self):
        srv = self.static_server()
        tunnel.write_live(self.path, {"id": "L1", "port": srv["port"], "server": srv})
        rec = tunnel.start_live(self.path, srv["port"])
        done = tunnel.end_live(self.path, "stopped")
        self.assertEqual(sorted(done["stopped"]), ["server", "tunnel"])
        self.assertFalse(tunnel.tunnel_running(rec) or tunnel.server_running(rec))
        kept = tunnel.read_live(self.path)
        self.assertEqual((kept["pid"], kept["url"], kept["reason"]), (rec["pid"], rec["url"], "stopped"))
        self.assertEqual(tunnel.end_live(self.path, "failed")["reason"], "stopped")  # ended once
        self.assertIsNone(tunnel.end_live(tunnel.live_path(self.d, "L9"), "stopped"))

    def test_a_record_naming_no_trycloudflare_address_is_never_handed_on(self):
        with mock.patch.object(tunnel, "_start", return_value={"id": "L1", "pid": 1, "url": "https://evil.example", "marker": "x", "processStart": "0"}):
            with self.assertRaisesRegex(tunnel.TunnelDown, "not a trycloudflare.com address"):
                tunnel.start_live(self.path, 4400)

    def test_sweep_ends_a_record_whose_processes_are_gone_and_leaves_a_running_one(self):
        running = tunnel.start_live(self.path, 4400)
        gone_path = tunnel.live_path(self.d, "L2")
        gone = tunnel.start_live(gone_path, 4401)
        detached.stop(*tunnel._identity(gone))
        ended = tunnel.sweep_live(self.d)
        self.assertEqual([r["id"] for r in ended], ["L2"])
        self.assertEqual(tunnel.read_live(gone_path)["reason"], "failed")
        self.assertTrue(tunnel.tunnel_running(running))
        self.assertNotIn("endedAt", tunnel.read_live(self.path))

    def test_sweep_of_every_record_stops_the_running_ones(self):
        rec = tunnel.start_live(self.path, 4400)
        ended = tunnel.sweep_live(self.d, every=True, reason="session-ended")
        self.assertEqual([(r["id"], r["stopped"]) for r in ended], [("L1", ["tunnel"])])
        self.assertFalse(tunnel.tunnel_running(rec))
        self.assertEqual(tunnel.sweep_live(self.d, every=True), [])  # an ended record is left alone

    def test_the_session_tunnel_record_keeps_its_fields(self):
        rec = tunnel.ensure(self.d, 4321)
        tunnel.start_live(self.path, 4400)
        self.assertEqual(sorted(tunnel.read(self.d)), sorted(rec))
        self.assertEqual(sorted(rec), ["adopted", "marker", "pid", "port", "processStart", "startedAt", "url"])


if __name__ == "__main__":
    unittest.main()

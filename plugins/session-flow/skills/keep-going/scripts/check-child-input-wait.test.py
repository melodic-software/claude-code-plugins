#!/usr/bin/env python3
import importlib.util
import json
import os
import platform
import pty
import subprocess
import sys
import time
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parent / "check-child-input-wait.py"

spec = importlib.util.spec_from_file_location("check_child_input_wait", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def run_checker(pid):
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), str(pid)], capture_output=True, text=True
    )
    return proc.returncode, proc.stdout, proc.stderr


def _proc_syscall_readable():
    try:
        with open("/proc/self/syscall") as fh:
            return fh.read().split()[:1] not in ([], ["running"])
    except OSError:
        return False


class ExitCodeTests(unittest.TestCase):
    def test_missing_root_exits_2(self):
        code, _, err = run_checker(2**22 + 12345)
        self.assertEqual(code, 2)
        self.assertIn("not running", err)

    def test_bad_argument_exits_2(self):
        code, _, _ = run_checker("abc")
        self.assertEqual(code, 2)


@unittest.skipUnless(platform.system() == "Linux", "Linux /proc signal")
class LinuxTreeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not _proc_syscall_readable():
            # A skip would leave the stdin acceptance test green without running.
            if os.environ.get("CI"):
                raise AssertionError("this CI host hides /proc/<pid>/syscall")
            raise unittest.SkipTest("this host hides /proc/<pid>/syscall")

    def spawn(self, script):
        # A background job in a non-interactive shell gets /dev/null as stdin,
        # so the blocking child runs in the foreground of the root shell.
        return subprocess.Popen(
            ["bash", "-c", script], stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    def verdict_of(self, root, needle, want):
        # In-process: hosts that limit ptrace let only an ancestor read a
        # process's syscall, and this test process is the children's ancestor.
        deadline = time.time() + 10
        verdict = None
        while time.time() < deadline:
            table = mod._linux_table()
            for pid, depth in mod.descendants(table, root.pid):
                if depth > 0 and needle in table[pid][1]:
                    verdict = mod._linux_verdict(pid)
            if verdict == want:
                break
            time.sleep(0.2)
        return verdict

    def test_child_blocked_on_stdin_is_flagged(self):
        root = self.spawn("bash -c 'read x'; true")
        try:
            self.assertEqual(self.verdict_of(root, "read x", "yes"), "yes")
        finally:
            root.kill()
            root.wait()

    def wchan_only_verdict(self, root, needle):
        # Real kernel wchan symbols, with /proc/<pid>/syscall made unreadable
        # as it is for a non-ancestor checker under Yama ptrace_scope>=1.
        real_open = open

        def no_syscall(path, *a, **k):
            if str(path).endswith("/syscall"):
                raise PermissionError(path)
            return real_open(path, *a, **k)

        deadline = time.time() + 10
        verdict = None
        while time.time() < deadline:
            table = mod._linux_table()
            for pid, depth in mod.descendants(table, root.pid):
                if depth > 0 and needle in table[pid][1]:
                    with real_open(f"/proc/{pid}/stat") as fh:
                        sleeping = fh.read().rsplit(")", 1)[1].split()[0] == "S"
                    if sleeping:
                        with mock.patch("builtins.open", no_syscall):
                            verdict = mod._linux_verdict(pid)
            if verdict is not None:
                break
            time.sleep(0.2)
        return verdict

    def test_wchan_fallback_never_flags_a_pipe_read(self):
        root = self.spawn("bash -c 'read x'; true")
        try:
            self.assertEqual(self.wchan_only_verdict(root, "read x"), "unknown")
        finally:
            root.kill()
            root.wait()

    def test_wchan_fallback_on_a_tty_read_is_not_no(self):
        primary, secondary = pty.openpty()
        root = subprocess.Popen(
            ["bash", "-c", "bash -c 'read x'; true"], stdin=secondary,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            self.assertIn(self.wchan_only_verdict(root, "read x"), ("yes", "unknown"))
        finally:
            root.kill()
            root.wait()
            os.close(primary)
            os.close(secondary)

    def test_cli_as_non_ancestor_on_blocked_child(self):
        # The skill runs the checker as its own process, a sibling of the
        # shell's children: under Yama ptrace_scope>=1 it reads only wchan,
        # where a pipe read is "unknown" (exit 4); otherwise syscall gives "yes".
        root = self.spawn("bash -c 'read x'; true")
        try:
            deadline = time.time() + 10
            child = None
            while child is None and time.time() < deadline:
                table = mod._linux_table()
                child = next((p for p, d in mod.descendants(table, root.pid)
                              if d > 0 and "read x" in table[p][1]), None)
                time.sleep(0.2)
            self.assertIsNotNone(child)
            probe = subprocess.run(
                [sys.executable, "-c", f"open('/proc/{child}/syscall').read()"],
                capture_output=True,
            )
            want, field = (1, "waiting") if probe.returncode == 0 else (4, "unknown")
            code = out = None
            while time.time() < deadline:
                code, out, _ = run_checker(root.pid)
                if code == want:
                    break
                time.sleep(0.2)
            self.assertEqual(code, want, out)
            self.assertIn(child, json.loads(out)[field])
        finally:
            root.kill()
            root.wait()

    def test_sleeping_child_is_not_flagged(self):
        root = self.spawn("sleep 30; true")
        try:
            self.assertEqual(self.verdict_of(root, "sleep 30", "no"), "no")
        finally:
            subprocess.run(["pkill", "-P", str(root.pid)])
            root.kill()
            root.wait()


class VerdictTests(unittest.TestCase):
    def wchan_verdict(self, wchan):
        # Models a non-ancestor checker on a host with Yama ptrace_scope>=1:
        # /proc/<pid>/syscall is unreadable, only wchan answers.
        def fake_open(path, *a, **k):
            if str(path).endswith("/stat"):
                return mock.mock_open(read_data=b"1 (x) S 0 0")()
            if str(path).endswith("/wchan"):
                return mock.mock_open(read_data=wchan)()
            raise PermissionError

        with mock.patch("builtins.open", fake_open):
            return mod._linux_verdict(1)

    def test_wchan_tty_read_is_flagged(self):
        self.assertEqual(self.wchan_verdict("n_tty_read"), "yes")

    def test_wchan_nanosleep_is_unknown(self):
        self.assertEqual(self.wchan_verdict("hrtimer_nanosleep"), "unknown")

    def test_wchan_pipe_and_generic_waits_are_unknown(self):
        # wchan cannot see the fd: a pipeline consumer sits in a pipe read,
        # and wait_woken backs socket and tty waits alike.
        for wchan in ("pipe_read", "anon_pipe_read", "pipe_wait", "wait_woken"):
            with self.subTest(wchan=wchan):
                self.assertEqual(self.wchan_verdict(wchan), "unknown")

    def test_linux_table_survives_exit_between_reads(self):
        # An empty cmdline sends the table to /proc/<pid>/comm, which can be
        # gone by then.
        def fake_open(path, *a, **k):
            if str(path).endswith("/stat"):
                return mock.mock_open(read_data=b"4242 (x) Z 1 0")()
            if str(path).endswith("/cmdline"):
                return mock.mock_open(read_data=b"")()
            raise FileNotFoundError

        with mock.patch("os.listdir", return_value=["4242"]), \
                mock.patch("builtins.open", fake_open):
            self.assertEqual(mod._linux_table(), {})

    def test_uninspectable_process_is_unknown(self):
        with mock.patch("builtins.open", side_effect=PermissionError):
            self.assertEqual(mod._linux_verdict(1), "unknown")

    def test_unreadable_syscall_and_wchan_is_unknown(self):
        real_open = open

        def fake_open(path, *a, **k):
            if str(path).endswith("/stat"):
                return mock.mock_open(read_data=b"1 (x) S 0 0")()
            raise PermissionError

        with mock.patch("builtins.open", fake_open):
            self.assertEqual(mod._linux_verdict(1), "unknown")
        del real_open

    def test_descendants_walks_tree(self):
        table = {1: (0, "a"), 2: (1, "b"), 3: (2, "c"), 4: (9, "d")}
        self.assertEqual(mod.descendants(table, 1), [(1, 0), (2, 1), (3, 2)])


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Fixture suite for prune-run-roots.py, run by prune-run-roots.test.sh.

Every call runs with HOME set to a temporary directory, so the real $HOME/.ev
is never read or changed.
"""

import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "prune-run-roots.py"
FOUR_DAYS = 4 * 24 * 60 * 60


@unittest.skipUnless(os.path.isdir("/proc/self/fd"), "open files are read from /proc")
class PruneRunRootsTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.base = Path(tmp.name).resolve()
        self.addCleanup(self.open_up, self.base)
        self.home = self.base / "home"
        self.ev = self.home / ".ev"
        self.ev.mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.home))

    def open_up(self, top):
        for dirpath, dirnames, _ in os.walk(top):
            for name in dirnames:
                path = os.path.join(dirpath, name)
                if not os.path.islink(path):
                    os.chmod(path, 0o700)

    def run_root(self, parent, name, age=FOUR_DAYS):
        root = parent / name
        sandbox = root / "claude-eval-abc123"
        (sandbox / "out").mkdir(parents=True)
        (sandbox / "out" / "trace.jsonl").write_text("{}\n", encoding="utf-8")
        (sandbox / "sealed").mkdir()
        (sandbox / "sealed" / "secret").write_text("x\n", encoding="utf-8")
        self.age(root, age)
        os.chmod(sandbox / "sealed", 0)
        return root

    def age(self, top, seconds):
        stamp = time.time() - seconds
        for dirpath, dirnames, filenames in os.walk(top, topdown=False):
            for name in dirnames + filenames:
                os.utime(os.path.join(dirpath, name), (stamp, stamp), follow_symlinks=False)
        os.utime(top, (stamp, stamp))

    def cli(self, *args, env=None):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            env=env or self.env,
            capture_output=True,
            text=True,
            timeout=60,
        )

    def test_old_run_root_is_removed(self):
        root = self.run_root(self.ev, "old111")
        result = self.cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("removed: %s" % root, result.stdout)
        self.assertFalse(root.exists())

    def test_recent_change_deep_inside_keeps_the_root(self):
        root = self.run_root(self.ev, "new222")
        os.chmod(root / "claude-eval-abc123" / "sealed", 0o700)
        os.utime(root / "claude-eval-abc123" / "out" / "trace.jsonl")
        result = self.cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("kept (changed within 3 days)", result.stdout)
        self.assertTrue(root.exists())

    def test_root_without_a_sandbox_is_kept(self):
        root = self.ev / "bare333"
        (root / "notes").mkdir(parents=True)
        self.age(root, FOUR_DAYS)
        result = self.cli()
        self.assertIn("kept (holds no claude-eval-* sandbox)", result.stdout)
        self.assertTrue(root.exists())

    def test_symlink_to_an_old_root_is_not_followed(self):
        outside = self.run_root(self.base, "elsewhere")
        link = self.ev / "link444"
        link.symlink_to(outside)
        result = self.cli()
        self.assertIn("refused (a symlink, not followed): %s" % link, result.stdout)
        self.assertTrue(outside.exists())
        self.assertTrue(link.is_symlink())

    def test_symlink_inside_a_removed_root_keeps_its_target(self):
        target = self.base / "target"
        target.mkdir()
        (target / "keep").write_text("x\n", encoding="utf-8")
        root = self.run_root(self.ev, "old555")
        os.chmod(root / "claude-eval-abc123" / "sealed", 0o700)
        (root / "claude-eval-abc123" / "out" / "link").symlink_to(target)
        self.age(root, FOUR_DAYS)
        os.chmod(root / "claude-eval-abc123" / "sealed", 0)
        result = self.cli()
        self.assertIn("removed: %s" % root, result.stdout)
        self.assertTrue((target / "keep").exists())

    def test_path_outside_the_eval_root_is_refused(self):
        outside = self.run_root(self.base, "outside")
        result = self.cli(str(outside), "/tmp")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("refused (not directly under %s): %s" % (self.ev, outside), result.stdout)
        self.assertIn("refused (not directly under %s): /tmp" % self.ev, result.stdout)
        self.assertTrue(outside.exists())

    def test_eval_root_resolving_to_the_temp_dir_is_refused(self):
        shared = self.base / "shared-tmp"
        shared.mkdir()
        root = self.run_root(shared, "old666")
        self.ev.rmdir()
        self.ev.symlink_to(shared)
        result = self.cli(env=dict(self.env, TMPDIR=str(shared)))
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("shared directory", result.stderr)
        self.assertTrue(root.exists())

    def test_root_a_live_process_holds_is_kept(self):
        root = self.run_root(self.ev, "live777")
        held = subprocess.Popen(["sleep", "60"], cwd=str(root))
        self.addCleanup(held.wait)
        self.addCleanup(held.kill)
        result = self.cli()
        self.assertIn("kept (a process has a file open under it): %s" % root, result.stdout)
        self.assertTrue(root.exists())

    def test_root_with_an_open_file_is_kept(self):
        root = self.run_root(self.ev, "open888")
        os.chmod(root / "claude-eval-abc123" / "sealed", 0o700)
        with open(root / "claude-eval-abc123" / "out" / "trace.jsonl", encoding="utf-8"):
            result = self.cli()
        self.assertIn("kept (a process has a file open under it): %s" % root, result.stdout)
        self.assertTrue(root.exists())

    def test_missing_eval_root_removes_nothing(self):
        self.ev.rmdir()
        result = self.cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")

    def test_sealed_mode_is_restored_before_removal(self):
        root = self.run_root(self.ev, "seal999")
        sealed = root / "claude-eval-abc123" / "sealed"
        self.assertEqual(stat.S_IMODE(os.lstat(sealed).st_mode), 0)
        result = self.cli(str(root))
        self.assertIn("removed: %s" % root, result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)

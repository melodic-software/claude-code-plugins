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
        reason = "not directly under %s and not a legacy %s/.ev* or %s/ev* root" % (
            self.ev,
            self.home,
            self.home,
        )
        self.assertIn("refused (%s): %s" % (reason, outside), result.stdout)
        self.assertIn("refused (%s): /tmp" % reason, result.stdout)
        self.assertTrue(outside.exists())

    def test_old_legacy_run_root_is_removed_with_its_sealed_dir(self):
        root = self.run_root(self.home, ".ev-16626f-a")
        sealed = root / "claude-eval-abc123" / "sealed"
        self.assertEqual(stat.S_IMODE(os.lstat(sealed).st_mode), 0)
        result = self.cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("removed: %s" % root, result.stdout)
        self.assertFalse(root.exists())
        self.assertTrue(self.ev.is_dir())

    def test_legacy_run_root_given_as_an_argument_is_removed(self):
        root = self.run_root(self.home, ".evs3")
        result = self.cli(str(root))
        self.assertIn("removed: %s" % root, result.stdout)
        self.assertFalse(root.exists())

    def test_recent_legacy_run_root_is_kept(self):
        root = self.run_root(self.home, ".evc-16626g", age=60)
        result = self.cli()
        self.assertIn("kept (changed within 3 days): %s" % root, result.stdout)
        self.assertTrue(root.exists())

    def test_legacy_run_root_a_live_process_holds_is_kept(self):
        root = self.run_root(self.home, ".evfsl")
        held = subprocess.Popen(["sleep", "60"], cwd=str(root))
        self.addCleanup(held.wait)
        self.addCleanup(held.kill)
        result = self.cli()
        self.assertIn(
            "kept (a process has a file open under it): %s" % root, result.stdout
        )
        self.assertTrue(root.exists())

    def test_legacy_symlink_is_left_with_how_to_remove_it(self):
        outside = self.run_root(self.base, "elsewhere")
        link = self.home / ".ev-b6"
        link.symlink_to(outside)
        result = self.cli()
        self.assertIn(
            "refused (a symlink, not followed; rm on the link alone removes it, once "
            "nothing uses its target): %s" % link,
            result.stdout,
        )
        self.assertTrue(link.is_symlink())
        self.assertTrue((outside / "claude-eval-abc123").exists())

    def test_legacy_directory_without_a_sandbox_is_left_with_how_to_remove_it(self):
        other = self.home / ".evolution"
        (other / "mail").mkdir(parents=True)
        self.age(other, FOUR_DAYS)
        result = self.cli()
        self.assertIn(
            "kept (holds no claude-eval-* sandbox, so not a run root; remove it by hand "
            "only after checking its contents): %s" % other,
            result.stdout,
        )
        self.assertTrue((other / "mail").is_dir())

    def test_home_entry_without_the_ev_prefix_is_not_a_candidate(self):
        root = self.run_root(self.home, ".cache-ev")
        listed = self.cli()
        self.assertNotIn(str(root), listed.stdout)
        named = self.cli(str(root))
        self.assertIn("refused (not directly under", named.stdout)
        self.assertTrue((root / "claude-eval-abc123").exists())

    def test_undotted_legacy_run_roots_are_removed(self):
        names = [
            "ev8635",
            "ev8635rlg2",
            "ev8431a",
            "ev12251",
            "eval",
            "eval-runs",
            "eval-13765",
            "evcp",
        ]
        roots = [self.run_root(self.home, name) for name in names]
        result = self.cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for root in roots:
            with self.subTest(root=root.name):
                self.assertIn("removed: %s\n" % root, result.stdout)
                self.assertFalse(root.exists())
        self.assertTrue(self.ev.is_dir())

    def test_undotted_legacy_run_root_given_as_an_argument_is_removed(self):
        root = self.run_root(self.home, "ev8635")
        result = self.cli(str(root))
        self.assertIn("removed: %s" % root, result.stdout)
        self.assertFalse(root.exists())

    def test_recent_undotted_legacy_run_root_is_kept(self):
        root = self.run_root(self.home, "eval-13765", age=60)
        result = self.cli()
        self.assertIn("kept (changed within 3 days): %s" % root, result.stdout)
        self.assertTrue((root / "claude-eval-abc123").exists())

    def test_undotted_legacy_run_root_a_live_process_holds_is_kept(self):
        root = self.run_root(self.home, "evcp")
        held = subprocess.Popen(["sleep", "60"], cwd=str(root))
        self.addCleanup(held.wait)
        self.addCleanup(held.kill)
        result = self.cli()
        self.assertIn(
            "kept (a process has a file open under it): %s" % root, result.stdout
        )
        self.assertTrue(root.exists())

    def test_undotted_legacy_symlink_is_left_with_how_to_remove_it(self):
        outside = self.run_root(self.base, "elsewhere")
        link = self.home / "ev12251"
        link.symlink_to(outside)
        result = self.cli()
        self.assertIn(
            "refused (a symlink, not followed; rm on the link alone removes it, once "
            "nothing uses its target): %s" % link,
            result.stdout,
        )
        self.assertTrue(link.is_symlink())
        self.assertTrue((outside / "claude-eval-abc123").exists())

    def test_undotted_user_directory_without_a_sandbox_is_left(self):
        other = self.home / "evolution"
        (other / "mail").mkdir(parents=True)
        self.age(other, FOUR_DAYS)
        result = self.cli()
        self.assertIn(
            "kept (holds no claude-eval-* sandbox, so not a run root; remove it by hand "
            "only after checking its contents): %s" % other,
            result.stdout,
        )
        self.assertTrue((other / "mail").is_dir())

    def test_undotted_user_directory_holding_a_sandbox_and_other_content_is_left(self):
        evals = self.home / "evals"
        (evals / "claude-eval-notes").mkdir(parents=True)
        (evals / "other-project").mkdir()
        self.age(evals, FOUR_DAYS)
        result = self.cli()
        self.assertIn(
            "kept (holds entries other than claude-eval-* sandboxes, so not a run root; "
            "remove it by hand only after checking its contents): %s" % evals,
            result.stdout,
        )
        self.assertTrue((evals / "other-project").is_dir())

    def test_dotted_legacy_root_with_other_content_is_still_removed(self):
        root = self.run_root(self.home, ".ev-16626f-a")
        (root / "stray").write_text("x\n", encoding="utf-8")
        self.age(root, FOUR_DAYS)
        result = self.cli()
        self.assertIn("removed: %s\n" % root, result.stdout)

    def test_sandbox_nested_a_level_down_is_not_a_run_root(self):
        runs = self.home / "eval-runs"
        self.run_root(runs, "123")
        self.age(runs, FOUR_DAYS)
        result = self.cli()
        self.assertIn(
            "kept (holds no claude-eval-* sandbox, so not a run root; remove it by hand "
            "only after checking its contents): %s" % runs,
            result.stdout,
        )
        self.assertTrue((runs / "123" / "claude-eval-abc123").exists())

    def test_home_entries_outside_the_two_prefixes_are_not_candidates(self):
        for name in ("e4", "ev", "my-ev1", "Ev1"):
            with self.subTest(name=name):
                root = self.run_root(self.home, name)
                listed = self.cli()
                self.assertNotIn(str(root), listed.stdout)
                named = self.cli(str(root))
                self.assertIn("refused (not directly under", named.stdout)
                self.assertTrue((root / "claude-eval-abc123").exists())

    def test_undotted_name_below_home_is_refused(self):
        root = self.run_root(self.home / "projects", "ev8635")
        result = self.cli(str(root))
        self.assertIn("refused (not directly under", result.stdout)
        self.assertTrue((root / "claude-eval-abc123").exists())

    def test_eval_root_itself_is_refused(self):
        os.mkdir(self.ev / "claude-eval-abc123")
        self.age(self.ev, FOUR_DAYS)
        result = self.cli(str(self.ev))
        self.assertIn(
            "refused (%s itself, which holds every run's root): %s"
            % (self.ev, self.ev),
            result.stdout,
        )
        self.assertTrue((self.ev / "claude-eval-abc123").is_dir())

    def test_eval_root_linked_to_a_legacy_name_is_refused(self):
        real = self.home / ".evdata"
        self.ev.rmdir()
        self.run_root(self.home, ".evdata")
        self.ev.symlink_to(real)
        result = self.cli()
        self.assertIn(
            "refused (%s itself, which holds every run's root): %s" % (real, real),
            result.stdout,
        )
        self.assertTrue((real / "claude-eval-abc123").exists())

    def test_docker_link_swap_state_files_are_not_candidates(self):
        (self.ev / ".docker-link-swap.lock").write_text("", encoding="utf-8")
        (self.ev / ".docker-link-swap.json").write_text("{}\n", encoding="utf-8")
        result = self.cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertTrue((self.ev / ".docker-link-swap.json").is_file())

    def test_home_resolving_to_the_temp_dir_is_refused(self):
        shared = self.base / "shared-tmp"
        root = self.run_root(shared, ".ev-old")
        result = self.cli(env=dict(self.env, HOME=str(shared), TMPDIR=str(shared)))
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("shared directory", result.stderr)
        self.assertTrue(root.exists())

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

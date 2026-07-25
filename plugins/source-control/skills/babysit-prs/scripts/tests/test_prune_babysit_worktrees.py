"""Native worktree-pruner resolution: no ghq, main checkout from git metadata.

`repo_path` and `remove_worktree` are exercised against a real on-disk git
repository with a linked worktree, so the whole path is hermetic -- no `gh`, and
notably no `ghq`: it is absent from the module's executable allowlist, so any
lingering call would raise "not in the caller's allowlist" and fail these tests.
This is the regression guard for #438, where a consumer without ghq hit a hard
RuntimeError instead of resolving the checkout from the worktree's own gitdir
pointer.

Also covers #816: a worktree entry orphaned by a lock-blocked removal
(residual empty directory, stale lease record) must self-heal on the next
prune run instead of erroring every run.
"""

from __future__ import annotations

import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_lease as leases  # noqa: E402
import prune_babysit_worktrees as prune  # noqa: E402


def git(*args: str) -> str:
    proc = subprocess.run(
        ["git", *args],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return proc.stdout.strip()


def make_repo(tmp: pathlib.Path) -> pathlib.Path:
    """A one-commit repository with committer identity set locally."""
    main = tmp / "mainrepo"
    main.mkdir()
    git("init", "-q", str(main))
    git("-C", str(main), "config", "user.email", "t@t")
    git("-C", str(main), "config", "user.name", "t")
    git("-C", str(main), "commit", "-q", "--allow-empty", "-m", "init")
    return main


def make_bare_hub(tmp: pathlib.Path) -> pathlib.Path:
    """A bare-clone hub: no working tree, so `--git-common-dir` is the repo dir."""
    source = make_repo(tmp)
    bare = tmp / "hub.git"
    git("clone", "-q", "--bare", str(source), str(bare))
    return bare


def add_worktree(main: pathlib.Path, root: pathlib.Path, name: str) -> pathlib.Path:
    root.mkdir(exist_ok=True)
    wt = root / name
    git("-C", str(main), "worktree", "add", "-q", str(wt), "-b", f"feat/{name}")
    return wt


class RepoPathResolvesFromGitMetadata(unittest.TestCase):
    def test_linked_worktree_resolves_its_main_checkout(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            main = make_repo(tmp)
            wt = add_worktree(main, tmp / "root", "owner__repo__pr-1")

            resolved = prune.repo_path(wt)

        self.assertEqual(resolved, main.resolve())

    def test_bare_hub_worktree_resolves_to_the_bare_repo_itself(self) -> None:
        # A bare-clone hub has no working tree, so `--git-common-dir` is the bare
        # repo directory (name != ".git"); the else-branch must return it as-is,
        # not its parent, or `git -C <parent> worktree remove` would fail.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            bare = make_bare_hub(tmp)
            wt = add_worktree(bare, tmp / "root", "owner__repo__pr-1")

            resolved = prune.repo_path(wt)

        self.assertEqual(resolved, bare.resolve())


class RemoveWorktreeIsHermetic(unittest.TestCase):
    def test_removes_a_clean_worktree_under_root_without_ghq(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            main = make_repo(tmp)
            root = tmp / "root"
            wt = add_worktree(main, root, "owner__repo__pr-1")
            worktree = prune.Worktree(path=wt, owner="owner", repo="repo", number=1)

            prune.remove_worktree(worktree, root)

            self.assertFalse(wt.exists())
            listed = git("-C", str(main), "worktree", "list", "--porcelain")
        self.assertNotIn(str(wt), listed)

    def test_refuses_to_remove_a_worktree_outside_the_babysit_root(self) -> None:
        # The path-containment guard must fire for a real worktree that lives
        # outside the caller's declared root -- resolution succeeding never
        # licenses removal beyond the sandbox.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            main = make_repo(tmp)
            actual_root = tmp / "root"
            wt = add_worktree(main, actual_root, "owner__repo__pr-2")
            worktree = prune.Worktree(path=wt, owner="owner", repo="repo", number=2)
            unrelated_root = tmp / "elsewhere"
            unrelated_root.mkdir()

            with self.assertRaises(RuntimeError) as ctx:
                prune.remove_worktree(worktree, unrelated_root)

            self.assertIn("outside babysit root", str(ctx.exception))
            self.assertTrue(wt.exists())

    def test_reports_no_residual_directory_for_a_clean_removal(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            main = make_repo(tmp)
            root = tmp / "root"
            wt = add_worktree(main, root, "owner__repo__pr-3")
            worktree = prune.Worktree(path=wt, owner="owner", repo="repo", number=3)

            info = prune.remove_worktree(worktree, root)

        self.assertEqual(info, {"residual_directory": False})

    def test_reports_a_residual_directory_when_cleanup_stays_blocked(self) -> None:
        # Simulates #816's Windows file-lock scenario: `git worktree remove`
        # succeeds (its administrative record is dropped) but the directory
        # itself refuses to delete. Real `git worktree remove` already clears
        # the directory in this hermetic test environment, so the post-removal
        # cleanup step is forced to report failure directly -- the same
        # `attempt_directory_removal` retry/report contract is exercised on
        # its own in `AttemptDirectoryRemovalTests` against a real lock
        # simulation (a patched `shutil.rmtree` failure).
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            main = make_repo(tmp)
            root = tmp / "root"
            wt = add_worktree(main, root, "owner__repo__pr-4")
            worktree = prune.Worktree(path=wt, owner="owner", repo="repo", number=4)

            with mock.patch.object(
                prune, "attempt_directory_removal", return_value=False
            ):
                info = prune.remove_worktree(worktree, root)

        self.assertEqual(info, {"residual_directory": True})


class MissingRepoErrorDetectionTests(unittest.TestCase):
    def test_detects_gits_not_a_git_repository_failure(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            not_a_repo = pathlib.Path(td) / "not-a-repo"
            not_a_repo.mkdir()

            with self.assertRaises(RuntimeError) as ctx:
                prune.git_status(not_a_repo)

        self.assertTrue(prune.is_missing_repo_error(ctx.exception))

    def test_does_not_match_an_unrelated_failure(self) -> None:
        self.assertFalse(
            prune.is_missing_repo_error(RuntimeError("gh: rate limit exceeded"))
        )


class AttemptDirectoryRemovalTests(unittest.TestCase):
    def test_reports_true_when_the_path_is_already_gone(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            missing = pathlib.Path(td) / "already-gone"

            self.assertTrue(prune.attempt_directory_removal(missing))

    def test_removes_a_surviving_directory(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            target = pathlib.Path(td) / "leftover"
            target.mkdir()
            (target / "stray.txt").write_text("x", encoding="utf-8")

            self.assertTrue(prune.attempt_directory_removal(target))
            self.assertFalse(target.exists())

    def test_reports_false_without_raising_when_removal_stays_blocked(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            target = pathlib.Path(td) / "locked"
            target.mkdir()

            with mock.patch.object(
                prune.shutil, "rmtree", side_effect=OSError("locked")
            ):
                self.assertFalse(prune.attempt_directory_removal(target))
            self.assertTrue(target.exists())


class RemoveEmptyOrphanDirectoryTests(unittest.TestCase):
    def test_reports_true_when_the_path_is_already_gone(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            root = tmp / "root"
            root.mkdir()

            self.assertTrue(prune.remove_empty_orphan_directory(root / "gone", root))

    def test_removes_an_empty_directory_under_root(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            root = tmp / "root"
            target = root / "owner__repo__pr-1"
            target.mkdir(parents=True)

            self.assertTrue(prune.remove_empty_orphan_directory(target, root))
            self.assertFalse(target.exists())

    def test_leaves_a_non_empty_directory_untouched(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            root = tmp / "root"
            target = root / "owner__repo__pr-1"
            target.mkdir(parents=True)
            (target / "stray.txt").write_text("x", encoding="utf-8")

            self.assertFalse(prune.remove_empty_orphan_directory(target, root))
            self.assertTrue((target / "stray.txt").exists())

    def test_refuses_a_directory_outside_root(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            root = tmp / "root"
            root.mkdir()
            outside = tmp / "elsewhere" / "owner__repo__pr-1"
            outside.mkdir(parents=True)

            self.assertFalse(prune.remove_empty_orphan_directory(outside, root))
            self.assertTrue(outside.exists())


class DropOrphanedWorktreeTests(unittest.TestCase):
    def test_drops_the_lease_record_and_removes_the_empty_directory(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            root = tmp / "root"
            root.mkdir()
            orphan_dir = root / "owner__repo__pr-9"
            orphan_dir.mkdir()  # matches the naming convention but isn't a git repo
            worktree = prune.Worktree(
                path=orphan_dir, owner="owner", repo="repo", number=9
            )
            state_dir = tmp / "state"
            lease_path = leases.lease_path(state_dir, "worker", worktree.key)
            lease_path.parent.mkdir(parents=True)
            lease_path.write_text("{}", encoding="utf-8")

            info = prune.drop_orphaned_worktree(worktree, lease_path, root)

        self.assertEqual(
            info, {"lease_dropped": True, "directory_removed": True}
        )
        self.assertFalse(lease_path.exists())
        self.assertFalse(orphan_dir.exists())

    def test_is_a_no_op_when_no_lease_record_exists(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            root = tmp / "root"
            root.mkdir()
            orphan_dir = root / "owner__repo__pr-10"
            orphan_dir.mkdir()
            worktree = prune.Worktree(
                path=orphan_dir, owner="owner", repo="repo", number=10
            )
            lease_path = leases.lease_path(tmp / "state", "worker", worktree.key)

            info = prune.drop_orphaned_worktree(worktree, lease_path, root)

        self.assertEqual(
            info, {"lease_dropped": False, "directory_removed": True}
        )

    def test_never_deletes_content_from_a_non_empty_orphan_directory(self) -> None:
        # An orphan's `.git` pointer could be corrupted or gone while real,
        # uncommitted work still sits in the directory -- unlike
        # `remove_worktree`'s post-removal cleanup, this path was never
        # confirmed safe to discard by git, so it must never force-delete.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            root = tmp / "root"
            root.mkdir()
            orphan_dir = root / "owner__repo__pr-11"
            orphan_dir.mkdir()
            stray_file = orphan_dir / "uncommitted-work.txt"
            stray_file.write_text("do not delete me", encoding="utf-8")
            worktree = prune.Worktree(
                path=orphan_dir, owner="owner", repo="repo", number=11
            )
            lease_path = leases.lease_path(tmp / "state", "worker", worktree.key)

            info = prune.drop_orphaned_worktree(worktree, lease_path, root)

            self.assertFalse(info["directory_removed"])
            self.assertTrue(orphan_dir.exists())
            self.assertEqual(
                stray_file.read_text(encoding="utf-8"), "do not delete me"
            )

    def test_refuses_to_remove_an_orphan_directory_outside_root(self) -> None:
        # Defense in depth, matching `remove_worktree`'s own containment
        # guard -- structurally unreachable through `main` (iter_worktrees
        # only ever yields direct children of root) but a direct caller must
        # not be able to walk this off-root regardless.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            root = tmp / "root"
            root.mkdir()
            outside_dir = tmp / "elsewhere" / "owner__repo__pr-12"
            outside_dir.mkdir(parents=True)
            worktree = prune.Worktree(
                path=outside_dir, owner="owner", repo="repo", number=12
            )
            lease_path = leases.lease_path(tmp / "state", "worker", worktree.key)

            info = prune.drop_orphaned_worktree(worktree, lease_path, root)

            self.assertFalse(info["directory_removed"])
            self.assertTrue(outside_dir.exists())


class MainSelfHealsAnOrphanedWorktreeEntry(unittest.TestCase):
    """End-to-end: an orphaned directory plus its stale lease record must be
    dropped without flipping the run's exit code, so the same orphan does not
    keep erroring every subsequent prune (#816)."""

    def run_orphan_prune(
        self, tmp: pathlib.Path, *extra_argv: str
    ) -> tuple[int, dict[str, object], pathlib.Path, pathlib.Path]:
        root = tmp / "root"
        root.mkdir()
        orphan_dir = root / "owner__repo__pr-9"
        orphan_dir.mkdir()
        state_dir = tmp / "state"
        lease_path = leases.lease_path(state_dir, "worker", "owner/repo#9")
        lease_path.parent.mkdir(parents=True)
        lease_path.write_text("{}", encoding="utf-8")

        argv = [
            "prune_babysit_worktrees.py",
            "--root",
            str(root),
            "--state-dir",
            str(state_dir),
            *extra_argv,
        ]
        buffer = io.StringIO()
        with mock.patch.object(sys, "argv", argv), redirect_stdout(buffer):
            exit_code = prune.main()
        return exit_code, json.loads(buffer.getvalue()), orphan_dir, lease_path

    def test_orphan_dropped_action_with_exit_code_zero(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            exit_code, report, orphan_dir, lease_path = self.run_orphan_prune(
                pathlib.Path(td), "--apply"
            )
            self.assertFalse(orphan_dir.exists())
            self.assertFalse(lease_path.exists())

        self.assertEqual(exit_code, 0)
        [row] = report["worktrees"]
        self.assertEqual(row["action"], "drop_orphan")
        self.assertTrue(row["dropped"])
        self.assertTrue(row["lease_dropped"])
        self.assertTrue(row["directory_removed"])

    def test_dry_run_reports_the_orphan_without_mutating_it(self) -> None:
        """Without --apply the run is a report: the documented dry-run contract
        promises it never mutates, so the orphan directory and its stale lease
        record must both survive."""
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            exit_code, report, orphan_dir, lease_path = self.run_orphan_prune(
                pathlib.Path(td)
            )
            self.assertTrue(orphan_dir.exists())
            self.assertTrue(lease_path.exists())

        self.assertEqual(exit_code, 0)
        [row] = report["worktrees"]
        self.assertEqual(row["action"], "drop_orphan")
        self.assertFalse(row["dropped"])


if __name__ == "__main__":
    unittest.main()

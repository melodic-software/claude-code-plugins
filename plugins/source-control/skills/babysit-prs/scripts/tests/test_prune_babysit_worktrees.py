"""Native worktree-pruner resolution: no ghq, main checkout from git metadata.

`repo_path` and `remove_worktree` are exercised against a real on-disk git
repository with a linked worktree, so the whole path is hermetic -- no `gh`, and
notably no `ghq`: it is absent from the module's executable allowlist, so any
lingering call would raise "not in the caller's allowlist" and fail these tests.
This is the regression guard for #438, where a consumer without ghq hit a hard
RuntimeError instead of resolving the checkout from the worktree's own gitdir
pointer.
"""

from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

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


if __name__ == "__main__":
    unittest.main()

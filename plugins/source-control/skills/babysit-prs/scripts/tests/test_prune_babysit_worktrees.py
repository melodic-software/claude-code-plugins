"""Worktree-pruner resolution and reporting, hermetically.

`repo_path` and `remove_worktree` are exercised against a real on-disk git
repository with a linked worktree, so the whole path is hermetic -- no `gh`, and
notably no `ghq`: it is absent from the module's executable allowlist, so any
lingering call would raise "not in the caller's allowlist" and fail these tests.
This is the regression guard for #438, where a consumer without ghq hit a hard
RuntimeError instead of resolving the checkout from the worktree's own gitdir
pointer.
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

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


def run_main(root: pathlib.Path, state_dir: pathlib.Path, *extra: str) -> tuple[int, dict]:
    argv = [
        "prune_babysit_worktrees.py",
        "--root",
        str(root),
        "--state-dir",
        str(state_dir),
        *extra,
    ]
    out = io.StringIO()
    with mock.patch.object(sys, "argv", argv), contextlib.redirect_stdout(out):
        code = prune.main()
    return code, json.loads(out.getvalue())


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


class NonConformingDirectoriesAreReported(unittest.TestCase):
    """#555: a directory the tool cannot map to a PR must never vanish.

    An unmappable directory reaches no git or gh call, so the whole report is
    assertable hermetically -- which is exactly the failure: before the fix a
    root holding only such a directory produced an empty `worktrees` list, a
    false all-clear for a worktree the caller then had to find by hand.
    """

    def test_iter_worktrees_pairs_recognized_and_unrecognized_directories(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            root = pathlib.Path(td) / "root"
            root.mkdir()
            (root / "medley-1567").mkdir()
            (root / "owner__repo__pr-1").mkdir()
            (root / "loose-file.txt").write_text("not a worktree", encoding="utf-8")

            entries = prune.iter_worktrees(root)

        self.assertEqual(len(entries), 2)
        self.assertIsInstance(entries[0], prune.UnrecognizedWorktree)
        self.assertEqual(entries[0].path.name, "medley-1567")
        self.assertIsInstance(entries[1], prune.Worktree)
        self.assertEqual(entries[1].key, "owner/repo#1")

    def test_main_reports_a_non_conforming_worktree_instead_of_nothing(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            main = make_repo(tmp)
            root = tmp / "root"
            wt = add_worktree(main, root, "medley-1567")

            code, report = run_main(root, tmp / "state")

            self.assertTrue(wt.exists())
        self.assertEqual(code, 0)
        self.assertEqual(
            report["worktrees"],
            [
                {
                    "path": str(wt),
                    "action": "unrecognized",
                    "reason": prune.UNRECOGNIZED_REASON,
                    "removed": False,
                }
            ],
        )

    def test_apply_mode_reports_but_never_removes_an_unrecognized_worktree(self) -> None:
        # The report-don't-remove invariant is what makes an unrecognized row safe
        # to emit at all, and --apply is the only mode that can delete anything.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            tmp = pathlib.Path(td)
            main = make_repo(tmp)
            root = tmp / "root"
            wt = add_worktree(main, root, "medley-1567")

            code, report = run_main(root, tmp / "state", "--apply")

            self.assertTrue(wt.exists())
        self.assertEqual(code, 0)
        self.assertEqual([row["action"] for row in report["worktrees"]], ["unrecognized"])
        self.assertFalse(report["worktrees"][0]["removed"])

    def test_scoped_pr_mode_still_reports_unrecognized_directories(self) -> None:
        # Scoping to one PR narrows which PRs are acted on, never which
        # directories are accounted for.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
            root = pathlib.Path(td) / "root"
            root.mkdir()
            (root / "medley-1567").mkdir()

            code, report = run_main(root, pathlib.Path(td) / "state", "--pr", "owner/repo#1")

        self.assertEqual(code, 0)
        self.assertEqual([row["action"] for row in report["worktrees"]], ["unrecognized"])


if __name__ == "__main__":
    unittest.main()

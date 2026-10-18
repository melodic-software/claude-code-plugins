"""`_Context.contains`: local git first, the compare API as the fallback.

Expected values come from git's `merge-base --is-ancestor` contract (exit 0
when the first commit is an ancestor of the second, 1 when not, any other
status an error) and GitHub's compare statuses: `ahead` or `identical` means
the base is reachable from the head. The compare stub answers from the
fixture repository's own `git rev-list`, so it shares no code with the local
path it is checked against.
"""

from __future__ import annotations

import itertools
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_postmerge as pm

GIT_ENV = {
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.invalid",
    "PATH": os.environ.get("PATH", ""),
}
UNKNOWN = "f" * 40


def git(root: pathlib.Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        capture_output=True,
        text=True,
        env=GIT_ENV,
    ).stdout.strip()


def commit(root: pathlib.Path, message: str) -> str:
    git(root, "commit", "--allow-empty", "-q", "-m", message)
    return git(root, "rev-parse", "HEAD")


class ApiCompare:
    """The compare endpoint, answered from a repository's real ancestry."""

    def __init__(self, root: pathlib.Path | None, error: bool = False) -> None:
        self.root = root
        self.error = error
        self.calls: list[list[str]] = []

    def history(self, sha: str) -> set[str]:
        assert self.root is not None
        return set(git(self.root, "rev-list", sha).split())

    def __call__(
        self, args: list[str], **_: object
    ) -> subprocess.CompletedProcess[str]:
        self.calls.append(args)
        if self.error:
            return subprocess.CompletedProcess(args, 1, "", "gh: Not Found (HTTP 404)")
        base, head = args[1].split("/compare/")[1].split("...")
        if self.root is None:
            status = "diverged"
        elif base == head:
            status = "identical"
        elif base in self.history(head):
            status = "ahead"
        elif head in self.history(base):
            status = "behind"
        else:
            status = "diverged"
        return subprocess.CompletedProcess(args, 0, json.dumps({"status": status}), "")


class Contains(unittest.TestCase):
    """Fixture: main c1-c2-c3, side branch s1 off c1, and f1, a commit on a
    branch that was then force-moved back to c1 (unreachable, still present)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = tempfile.TemporaryDirectory()
        root = cls.root = pathlib.Path(cls.tmp.name) / "repo"
        root.mkdir()
        git(root, "init", "-q", "-b", "main")
        cls.c1 = commit(root, "c1")
        git(root, "checkout", "-q", "-b", "side")
        cls.s1 = commit(root, "s1")
        git(root, "checkout", "-q", "-b", "moved", cls.c1)
        cls.f1 = commit(root, "f1")
        git(root, "reset", "-q", "--hard", cls.c1)
        git(root, "checkout", "-q", "main")
        cls.c2 = commit(root, "c2")
        cls.c3 = commit(root, "c3")
        git(root, "branch", "old", cls.c2)
        cls.shas = [cls.c1, cls.c2, cls.c3, cls.s1, cls.f1]
        cls.shallow = pathlib.Path(cls.tmp.name) / "shallow"
        subprocess.run(
            [
                "git",
                "clone",
                "-q",
                "--depth",
                "1",
                "--no-single-branch",
                root.as_uri(),
                str(cls.shallow),
            ],
            check=True,
            env=GIT_ENV,
        )
        cls.empty = pathlib.Path(cls.tmp.name) / "empty"
        cls.empty.mkdir()
        # A full clone whose graft file cuts c3 off from c2.
        cls.grafted = pathlib.Path(cls.tmp.name) / "grafted"
        subprocess.run(
            ["git", "clone", "-q", root.as_uri(), str(cls.grafted)],
            check=True,
            env=GIT_ENV,
        )
        (cls.grafted / ".git" / "info").mkdir(exist_ok=True)
        (cls.grafted / ".git" / "info" / "grafts").write_text(f"{cls.c3}\n")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tmp.cleanup()

    def context(
        self, checkouts: list[pathlib.Path], api: ApiCompare | None = None
    ) -> tuple[pm._Context, ApiCompare]:
        api = api or ApiCompare(self.root)
        for patcher in (
            mock.patch.object(pm, "gh_capture", api),
            mock.patch.object(pm.policy, "_history_checkouts", return_value=checkouts),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)
        return pm._Context(owner="example-org", name="example-repo", identity="x"), api

    def test_an_ancestor_is_answered_locally(self) -> None:
        ctx, api = self.context([self.root])
        self.assertTrue(ctx.contains(self.c1, self.c3))
        self.assertEqual(api.calls, [])

    def test_a_side_branch_commit_is_answered_locally(self) -> None:
        ctx, api = self.context([self.root])
        self.assertFalse(ctx.contains(self.s1, self.c3))
        self.assertEqual(api.calls, [])

    def test_the_same_sha_needs_no_call(self) -> None:
        ctx, api = self.context([self.root])
        with mock.patch.object(pm, "run_command") as run:
            self.assertTrue(ctx.contains(self.c3, self.c3))
        run.assert_not_called()
        self.assertEqual(api.calls, [])

    def test_a_sha_missing_locally_falls_back_to_the_compare(self) -> None:
        api = ApiCompare(None)
        ctx, api = self.context([self.root], api)
        self.assertFalse(ctx.contains(self.c1, UNKNOWN))
        self.assertEqual(len(api.calls), 1)
        self.assertIn(f"compare/{self.c1}...{UNKNOWN}", api.calls[0][1])

    def test_the_fallback_returns_the_compare_answer(self) -> None:
        # The local clone lacks c3 (the empty dir is no clone); the API knows it.
        ctx, api = self.context([self.empty])
        self.assertTrue(ctx.contains(self.c1, self.c3))
        self.assertEqual(len(api.calls), 1)

    def test_no_git_repository_falls_back(self) -> None:
        ctx, api = self.context([self.empty])
        self.assertFalse(ctx.contains(self.s1, self.c3))
        self.assertEqual(len(api.calls), 1)

    def test_no_git_executable_falls_back(self) -> None:
        ctx, api = self.context([self.root])
        with mock.patch("shutil.which", return_value=None):
            self.assertFalse(ctx.contains(self.s1, self.c3))
        self.assertEqual(len(api.calls), 1)

    def test_a_shallow_clone_falls_back(self) -> None:
        # In the shallow clone c3's parent c2 is cut off, so local git alone
        # would call c2 no ancestor of c3.
        ctx, api = self.context([self.shallow])
        self.assertTrue(ctx.contains(self.c2, self.c3))
        self.assertEqual(len(api.calls), 1)

    def test_a_graft_file_is_ignored(self) -> None:
        # Grafted, git would call c2 no ancestor of c3; the real ancestry wins.
        ctx, api = self.context([self.grafted])
        self.assertTrue(ctx.contains(self.c2, self.c3))
        self.assertEqual(api.calls, [])

    def test_git_failing_after_the_clones_resolve_falls_back(self) -> None:
        ctx, api = self.context([self.root])
        ctx.local_clones = [self.root]
        with mock.patch.object(pm, "run_command", side_effect=RuntimeError("timeout")):
            self.assertTrue(ctx.contains(self.c1, self.c3))
        self.assertEqual(len(api.calls), 1)

    def test_a_clone_that_cannot_decide_passes_to_the_next(self) -> None:
        # The shallow clone is skipped; the empty dir is no clone; root decides.
        ctx, api = self.context([self.empty, self.shallow, self.root])
        self.assertFalse(ctx.contains(self.s1, self.c3))
        self.assertEqual(api.calls, [])

    def test_a_clone_missing_the_commit_passes_to_the_next(self) -> None:
        ctx, api = self.context([self.root])
        other = pathlib.Path(self.tmp.name) / "other"
        if not other.exists():
            other.mkdir()
            git(other, "init", "-q", "-b", "main")
            commit(other, "unrelated")
        ctx.local_clones = [other, self.root]
        self.assertTrue(ctx.contains(self.c1, self.c3))
        self.assertEqual(api.calls, [])

    def test_a_ref_name_falls_back(self) -> None:
        # `moved` was force-moved back to c1 locally; only a full SHA names
        # the same commit on both sides, so a name goes to the API.
        ctx, api = self.context([self.root])
        ctx.contains("moved", self.c3)
        self.assertEqual(len(api.calls), 1)

    def test_a_force_moved_away_commit_is_still_judged_by_its_ancestry(self) -> None:
        ctx, api = self.context([self.root])
        self.assertFalse(ctx.contains(self.f1, self.c3))
        self.assertTrue(ctx.contains(self.c1, self.f1))
        self.assertEqual(api.calls, [])

    def test_the_fallback_keeps_the_read_error(self) -> None:
        ctx, _ = self.context([self.empty], ApiCompare(None, error=True))
        with self.assertRaises(pm.PostMergeReadError):
            ctx.contains(self.c1, self.c3)

    def test_a_cache_hit_makes_no_second_call(self) -> None:
        ctx, api = self.context([self.root])
        self.assertTrue(ctx.contains(self.c1, self.c3))
        with mock.patch.object(pm, "run_command") as run:
            self.assertTrue(ctx.contains(self.c1, self.c3))
        run.assert_not_called()
        self.assertEqual(api.calls, [])

    def test_a_cached_fallback_makes_no_second_call(self) -> None:
        ctx, api = self.context([self.empty])
        ctx.contains(self.c1, self.c3)
        ctx.contains(self.c1, self.c3)
        self.assertEqual(len(api.calls), 1)

    def test_local_and_compare_agree_on_every_pair(self) -> None:
        pairs = list(itertools.product(self.shas, repeat=2))
        local, api = self.context([self.root])
        local_verdicts = [local.contains(a, b) for a, b in pairs]
        self.assertEqual(api.calls, [])
        remote = pm._Context(owner="example-org", name="example-repo", identity="x")
        remote.local_clones = []
        remote_verdicts = [remote.contains(a, b) for a, b in pairs]
        self.assertEqual(len(api.calls), sum(a != b for a, b in pairs))
        for (ancestor, sha), mine, theirs in zip(
            pairs, local_verdicts, remote_verdicts, strict=True
        ):
            with self.subTest(ancestor=ancestor[:7], sha=sha[:7]):
                self.assertEqual(mine, theirs)
        # The fixture exercises both answers.
        self.assertEqual(set(local_verdicts), {True, False})


if __name__ == "__main__":
    unittest.main()

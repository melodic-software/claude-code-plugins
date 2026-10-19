"""`babysit_check_inputs.changed_since_merge_base` over real git clones."""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

# An inherited GIT_DIR, GIT_WORK_TREE or GIT_CONFIG would send the git
# fixtures' identity writes into the caller's repository
# (scripts/check-fixture-git-isolation.sh). Cleared before any test spawns git.
for _leaked_git_var in (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_PREFIX",
    "GIT_OBJECT_DIRECTORY",
    "GIT_CONFIG",
):
    os.environ.pop(_leaked_git_var, None)
del _leaked_git_var

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_check_inputs as check_inputs  # noqa: E402  (after the git-env clear)

GIT_ENV = {
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.invalid",
    "PATH": os.environ.get("PATH", ""),
}
REGISTRY = "scripts/shared-copies.txt"


def git(root: pathlib.Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        capture_output=True,
        text=True,
        env=GIT_ENV,
    ).stdout.strip()


def commit(root: pathlib.Path, path: str, text: str) -> str:
    file = root / path
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(text, encoding="utf-8")
    git(root, "add", path)
    git(root, "commit", "-q", "-m", path)
    return git(root, "rev-parse", "HEAD")


class ChangedSinceMergeBase(unittest.TestCase):
    """origin: main A -> B (registry) -> C (README); feat A -> P."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        self.origin = self.tmp / "origin"
        self.origin.mkdir()
        git(self.origin, "init", "-q", "-b", "main")
        git(self.origin, "config", "uploadpack.allowAnySHA1InWant", "true")
        self.a = commit(self.origin, REGISTRY, "lib/a.sh plugins/x/a.sh\n")
        git(self.origin, "checkout", "-q", "-b", "feat")
        self.p = commit(self.origin, "feat.txt", "pr\n")
        git(self.origin, "checkout", "-q", "main")
        commit(
            self.origin, REGISTRY, "lib/a.sh plugins/x/a.sh\nlib/a.sh plugins/y/a.sh\n"
        )
        self.c = commit(self.origin, "README.md", "readme\n")
        self.clone = self.tmp / "clone"
        git(self.tmp, "clone", "-q", str(self.origin), str(self.clone))

    def read(
        self, paths: tuple[str, ...], head: str, root: pathlib.Path | None = None
    ) -> dict:
        return check_inputs.changed_since_merge_base(
            paths, head, "main", [root or self.clone]
        )

    def test_a_registry_change_since_the_merge_base_is_stale(self) -> None:
        for paths in ((REGISTRY,), ("scripts",), ("docs/none.md", REGISTRY)):
            with self.subTest(paths=paths):
                out = self.read(paths, self.p)
                self.assertEqual(out["state"], "stale")
                self.assertEqual(out["changed"], [REGISTRY])
                self.assertEqual(out["mergeBase"], self.a)
                self.assertEqual(out["baseTip"], self.c)

    def test_a_base_change_off_the_listed_paths_is_current(self) -> None:
        out = self.read(("docs/none.md", ".github/workflows"), self.p)
        self.assertEqual(out["state"], "current")
        self.assertEqual(out["changed"], [])

    def test_a_head_updated_from_the_base_is_current(self) -> None:
        git(self.origin, "checkout", "-q", "feat")
        git(self.origin, "merge", "-q", "--no-edit", "main")
        merged = git(self.origin, "rev-parse", "HEAD")
        out = self.read((REGISTRY,), merged)
        self.assertEqual(out["state"], "current")
        self.assertEqual(out["mergeBase"], self.c)

    def test_a_head_the_clone_lacks_is_fetched_by_sha(self) -> None:
        git(self.origin, "checkout", "-q", "-b", "late", self.a)
        late = commit(self.origin, "late.txt", "late\n")
        git(self.origin, "checkout", "-q", "main")
        out = self.read((REGISTRY,), late)
        self.assertEqual(out["state"], "stale")
        self.assertEqual(out["changed"], [REGISTRY])
        self.assertEqual(git(self.clone, "cat-file", "-t", late), "commit")
        self.assertEqual(git(self.clone, "for-each-ref", "--contains", late), "")

    def test_doubt_is_unknown(self) -> None:
        shallow = self.tmp / "shallow"
        git(
            self.tmp,
            "clone",
            "-q",
            "--depth",
            "1",
            f"file://{self.origin}",
            str(shallow),
        )
        cases = (
            ("unfetchable head", (REGISTRY,), "f" * 40, self.clone),
            ("shallow clone", (REGISTRY,), self.p, shallow),
            ("not a clone", (REGISTRY,), self.p, self.tmp),
            ("not a sha", (REGISTRY,), "main", self.clone),
        )
        for name, paths, head, root in cases:
            with self.subTest(name):
                out = self.read(paths, head, root)
                self.assertEqual(out["state"], "unknown")
                self.assertTrue(out["reason"])

    def test_no_paths_is_off(self) -> None:
        self.assertEqual(self.read((), self.p), {"state": "off"})


if __name__ == "__main__":
    unittest.main()

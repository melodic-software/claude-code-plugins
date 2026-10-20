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
ALLOWLIST = "scripts/docs-only-paths.txt"


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
    """origin: main A -> B (registry) -> C (README); feat A -> P (feat.txt);
    canon A -> K (the registered canonical); copy A -> Y (a copy B
    registers)."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        self.origin = self.tmp / "origin"
        self.origin.mkdir()
        git(self.origin, "init", "-q", "-b", "main")
        git(self.origin, "config", "uploadpack.allowAnySHA1InWant", "true")
        self.a = commit(self.origin, REGISTRY, "lib/a.sh plugins/x/a.sh\n")
        self.p = self.branch("feat", "feat.txt")
        self.k = self.branch("canon", "lib/a.sh")
        self.y = self.branch("copy", "plugins/y/a.sh")
        commit(
            self.origin,
            REGISTRY,
            "# comment\nlib/a.sh plugins/x/a.sh\nlib/a.sh plugins/y/a.sh\n",
        )
        self.c = commit(self.origin, "README.md", "readme\n")
        self.clone = self.tmp / "clone"
        git(self.tmp, "clone", "-q", str(self.origin), str(self.clone))

    def branch(self, name: str, path: str) -> str:
        git(self.origin, "checkout", "-q", "-b", name, self.a)
        sha = commit(self.origin, path, name + "\n")
        git(self.origin, "checkout", "-q", "main")
        return sha

    def read(
        self, paths: tuple[str, ...], head: str, root: pathlib.Path | None = None
    ) -> dict:
        return check_inputs.changed_since_merge_base(
            paths, head, "main", [root or self.clone]
        )

    def test_a_registry_change_is_stale_for_a_pr_touching_a_registered_path(
        self,
    ) -> None:
        for head in (self.k, self.y):
            for paths in ((REGISTRY,), ("scripts",), ("docs/none.md", REGISTRY)):
                with self.subTest(head=head, paths=paths):
                    out = self.read(paths, head)
                    self.assertEqual(out["state"], "stale")
                    self.assertEqual(out["changed"], [REGISTRY])
                    self.assertEqual(out["mergeBase"], self.a)
                    self.assertEqual(out["baseTip"], self.c)

    def test_a_registry_change_is_current_for_a_pr_touching_no_registered_path(
        self,
    ) -> None:
        out = self.read((REGISTRY,), self.p)
        self.assertEqual(out["state"], "current")
        self.assertEqual(out["changed"], [])
        self.assertEqual(out["notApplicable"], [REGISTRY])

    def test_a_registry_change_is_stale_for_a_pr_editing_the_registry(self) -> None:
        # Main retired what the PR now registers: only the PR's own registry
        # line names it, so the tip's registry alone would miss the overlap.
        edit = self.branch("edit", REGISTRY)
        out = self.read((REGISTRY,), edit)
        self.assertEqual(out["state"], "stale")
        self.assertEqual(out["changed"], [REGISTRY])

    def test_a_registry_absent_at_the_tip_registers_nothing(self) -> None:
        git(self.origin, "rm", "-q", REGISTRY)
        git(self.origin, "commit", "-q", "-m", "retire")
        git(self.clone, "fetch", "-q", "origin")
        out = self.read((REGISTRY,), self.k)
        self.assertEqual(out["state"], "current")
        self.assertEqual(out["notApplicable"], [REGISTRY])

    def test_an_unscoped_input_is_stale_for_every_pr(self) -> None:
        commit(self.origin, ALLOWLIST, "docs/**\n")
        git(self.clone, "fetch", "-q", "origin")
        out = self.read((REGISTRY, ALLOWLIST), self.p)
        self.assertEqual(out["state"], "stale")
        self.assertEqual(out["changed"], [ALLOWLIST])
        self.assertEqual(out["notApplicable"], [REGISTRY])

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
        late = self.branch("late", "lib/a.sh")
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

    def test_a_partial_clone_is_unknown(self) -> None:
        # A blobless clone lacks the tip's registry once a fetch moves the tip;
        # read as empty, it would register nothing and answer `current`.
        git(self.origin, "config", "uploadpack.allowFilter", "true")
        partial = self.tmp / "partial"
        git(
            self.tmp,
            "clone",
            "-q",
            "--filter=blob:none",
            f"file://{self.origin}",
            str(partial),
        )
        commit(self.origin, REGISTRY, "lib/a.sh plugins/z/a.sh\n")
        git(partial, "fetch", "-q", "origin")
        out = self.read((REGISTRY,), self.k, partial)
        self.assertEqual(out["state"], "unknown")
        self.assertTrue(out["reason"])

    def test_no_paths_is_off(self) -> None:
        self.assertEqual(self.read((), self.p), {"state": "off"})


if __name__ == "__main__":
    unittest.main()

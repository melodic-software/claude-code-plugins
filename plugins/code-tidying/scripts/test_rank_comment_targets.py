#!/usr/bin/env python3
"""Black-box tests for rank-comment-targets.py on a synthetic repository.

Asserts the gates (administrative, generated, size floor, bot commits,
byte-identical copies), the ordering the formula is meant to produce, the
shallow-clone degradation notice, and the bounded drift column.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

# The fixtures build throwaway repositories. Under an inherited absolute GIT_DIR
# (or GIT_WORK_TREE / GIT_CONFIG) `git init` and `git config` would write into the
# caller's repository instead of the fixture, so clear the ambient git environment
# once, before any fixture is built (scripts/check-fixture-git-isolation.sh).
for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)
del _leaked_git_var

SCRIPT = Path(__file__).with_name("rank-comment-targets.py")


def pygments_present() -> bool:
    try:
        import pygments  # noqa: F401
    except ImportError:
        return False
    return True


def git(repo: Path, *args: str, env: dict | None = None) -> str:
    e = {k: v for k, v in os.environ.items() if not k.startswith("GIT_CONFIG")}
    e.update(
        {
            "GIT_AUTHOR_NAME": "dev",
            "GIT_AUTHOR_EMAIL": "d@x",
            "GIT_COMMITTER_NAME": "dev",
            "GIT_COMMITTER_EMAIL": "d@x",
        }
    )
    if env:
        e.update(env)
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=True,
        env=e,
    ).stdout


def commit(repo: Path, msg: str, author: str = "dev", days_ago: int = 1) -> None:
    import time

    ts = str(int(time.time()) - days_ago * 86400)
    git(repo, "add", "-A")
    git(
        repo,
        "commit",
        "-q",
        "-m",
        msg,
        env={
            "GIT_AUTHOR_NAME": author,
            "GIT_COMMITTER_NAME": author,
            "GIT_AUTHOR_DATE": ts,
            "GIT_COMMITTER_DATE": ts,
        },
    )


def commented(n_lines: int, comments: int) -> str:
    body = ["x=1" for _ in range(n_lines - comments)]
    return (
        "#!/usr/bin/env bash\n"
        + "\n".join(f"# comment {i}" for i in range(comments))
        + "\n"
        + "\n".join(body)
        + "\n"
    )


def build(repo: Path) -> None:
    git(repo, "init", "-q", "-b", "main")
    (repo / ".gitattributes").write_text("gen.sh linguist-generated\n")
    (repo / "hot.sh").write_text(
        commented(40, 12)
    )  # commented and churned: should rank first
    (repo / "cold.sh").write_text(commented(40, 12))  # commented, never touched again
    (repo / "plain.sh").write_text(
        commented(40, 0)
    )  # churned, no comments: payload zero
    (repo / "tiny.sh").write_text(commented(5, 3))  # below the size floor
    (repo / "gen.sh").write_text(commented(40, 12))  # generated: gated
    (repo / "CHANGELOG.md").write_text("# log\n")
    (repo / "copy-a.sh").write_text(commented(40, 6))
    (repo / "copy-b.sh").write_text(commented(40, 6))  # byte-identical to copy-a
    (repo / "user.sh").write_text(
        "#!/usr/bin/env bash\nsource hot.sh\nsource hot.sh\n" + "x=1\n" * 30
    )
    commit(repo, "init", days_ago=400)
    for i in range(4):
        (repo / "hot.sh").write_text(commented(40, 12).replace("x=1", f"x={i}", 5))
        (repo / "plain.sh").write_text(commented(40, 0).replace("x=1", f"x={i}", 5))
        commit(repo, f"churn {i}", days_ago=10 * (i + 1))
    (repo / "hot.sh").write_text(commented(40, 12).replace("x=1", "x=9", 20))
    commit(repo, "bot sweep", author="dependabot[bot]", days_ago=2)


@unittest.skipUnless(pygments_present(), "pygments not installed")
class Ranking(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        cls.repo = cls.tmp / "repo"
        cls.repo.mkdir()
        build(cls.repo)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def run_rank(
        self, *args: str, cwd: Path | None = None
    ) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--json", "--drift-top", "2", *args],
            capture_output=True,
            text=True,
            check=False,
            cwd=str(cwd or self.repo),
        )

    def test_gates_and_collapse(self):
        p = self.run_rank()
        self.assertEqual(p.returncode, 0, p.stderr)
        rep = json.loads(p.stdout)
        paths = [r["path"] for r in rep["rows"]]
        self.assertNotIn("gen.sh", paths)
        self.assertNotIn("tiny.sh", paths)
        self.assertNotIn("CHANGELOG.md", paths)
        self.assertNotIn("copy-b.sh", paths)
        copy = next(r for r in rep["rows"] if r["path"] == "copy-a.sh")
        self.assertEqual(copy["instances"], 2)
        self.assertEqual(rep["gated"]["byte-identical copies collapsed"], 1)
        self.assertGreaterEqual(rep["gated"]["generated"], 1)

    def test_ordering_needs_both_exposure_and_payload(self):
        rep = json.loads(self.run_rank().stdout)
        score = {r["path"]: r["score"] for r in rep["rows"]}
        self.assertGreater(score["hot.sh"], score["cold.sh"], score)
        self.assertEqual(score["plain.sh"], 0.0, score)
        self.assertEqual(rep["rows"][0]["path"], "hot.sh", rep["rows"][:3])

    def test_bot_commits_do_not_count_as_churn(self):
        rep = json.loads(self.run_rank().stdout)
        hot = next(r for r in rep["rows"] if r["path"] == "hot.sh")
        # init added all 41 lines; 4 human commits changed 5 lines each (10 per
        # commit): 41 + 40 = 81. The bot's 20-line sweep (40 more) must not count.
        self.assertEqual(hot["raw_churn"], 81, hot)

    def test_fan_in_counts_other_files_references(self):
        rep = json.loads(self.run_rank().stdout)
        hot = next(r for r in rep["rows"] if r["path"] == "hot.sh")
        self.assertGreaterEqual(hot["fan_in"], 2, hot)

    def test_drift_column_is_bounded_to_top_rows(self):
        rep = json.loads(self.run_rank().stdout)
        with_drift = [r for r in rep["rows"] if "comment_age_vs_code_days" in r]
        self.assertEqual(len(with_drift), 2, [r["path"] for r in with_drift])
        self.assertTrue(rep["reading_order_not_evidence"])

    def test_shallow_clone_degrades_with_notice(self):
        shallow = self.tmp / "shallow"
        subprocess.run(
            ["git", "clone", "-q", "--depth", "1", f"file://{self.repo}", str(shallow)],
            check=True,
            capture_output=True,
            env={k: v for k, v in os.environ.items() if not k.startswith("GIT_CONFIG")},
        )
        p = self.run_rank(cwd=shallow)
        self.assertEqual(p.returncode, 0, p.stderr)
        rep = json.loads(p.stdout)
        self.assertTrue(rep["shallow_clone"])
        text = subprocess.run(
            [sys.executable, str(SCRIPT), "--drift-top", "0"],
            capture_output=True,
            text=True,
            check=False,
            cwd=str(shallow),
        ).stdout
        self.assertIn("shallow clone", text)
        self.assertIn("READING ORDER, NOT EVIDENCE", text)

    def test_outside_git_exits_1(self):
        p = self.run_rank(cwd=self.tmp)
        self.assertEqual(p.returncode, 1, p.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)

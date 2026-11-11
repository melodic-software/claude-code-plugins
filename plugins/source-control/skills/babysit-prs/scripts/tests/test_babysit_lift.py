"""The lift block a canary or revert demotion record carries, and the close of
a record that lifted (#11022's decision of 2026-11-02: a record lifts once the
content whose deletion filed it is on main again, or a referencing pull
request merges with its own condition holding).

Expected values come from the decision, from git fixtures built here (the
lines a commit deletes are the lines the fixture wrote), and from SHA-256's
published empty-input digest. GitHub is stubbed at the policy module's gh
seam.
"""

from __future__ import annotations

import contextlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from typing import Any
from unittest import mock

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

import babysit_lift as lift  # noqa: E402
import babysit_merge_policy as policy  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[6]
REPO = "owner/repo"
IDENTITY = "agent-lanes[bot]"


class Fixture:
    """A throwaway git repository with a pinned identity."""

    def __init__(self, case: unittest.TestCase) -> None:
        tmp = tempfile.TemporaryDirectory()
        case.addCleanup(tmp.cleanup)
        self.dir = tmp.name
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "commit.gpgsign", "false")

    def git(self, *args: str) -> str:
        return subprocess.run(
            ["git", "-C", self.dir, *args], check=True, capture_output=True, text=True
        ).stdout.strip()

    def commit(self, message: str, files: dict[str, str | None]) -> str:
        for path, text in files.items():
            target = pathlib.Path(self.dir, path)
            if text is None:
                target.unlink()
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")


class LiftBlock(unittest.TestCase):
    def test_a_line_hash_is_the_sha256_prefix_of_its_bytes(self) -> None:
        # SHA-256 of the empty input is e3b0c442 98fc1c14 ... (FIPS 180-4
        # test vectors).
        self.assertEqual(policy.line_hash(b""), "e3b0c44298fc")

    def test_a_block_round_trips_its_counts(self) -> None:
        block = policy.lift_block([("a.py", b"x = 1"), ("a.py", b"x = 1"), ("b/c.md", b"")])
        self.assertEqual(
            policy.read_lift_block("intro\n" + block + "\n"),
            {
                "a.py": {policy.line_hash(b"x = 1"): 2},
                "b/c.md": {"e3b0c44298fc": 1},
            },
        )

    def test_a_merge_that_deleted_nothing_has_an_empty_block(self) -> None:
        block = policy.lift_block([])
        self.assertEqual(block, '<!-- lift-content v1 {"paths":{}} -->')
        self.assertEqual(policy.read_lift_block(block), {})

    def test_a_path_cannot_end_the_comment(self) -> None:
        block = policy.lift_block([("x-->y", b"a")])
        self.assertEqual(block.count("-->"), 1)
        self.assertTrue(block.endswith(" -->"))
        self.assertEqual(list(policy.read_lift_block(block)), ["x-->y"])

    def test_no_block_for_a_control_character_path_or_past_the_limit(self) -> None:
        self.assertIsNone(policy.lift_block([("a\nb", b"x")]))
        self.assertIsNone(
            policy.lift_block([("a.py", str(i).encode()) for i in range(5000)])
        )

    def test_a_malformed_block_reads_as_none(self) -> None:
        for name, text in (
            ("no block", "no block here"),
            ("bad json", "<!-- lift-content v1 {nope} -->"),
            ("short hash", '<!-- lift-content v1 {"paths":{"a":{"abc":1}}} -->'),
            ("zero count", '<!-- lift-content v1 {"paths":{"a":{"e3b0c44298fc":0}}} -->'),
            ("not indented alone", ' <!-- lift-content v1 {"paths":{}} -->'),
        ):
            with self.subTest(name):
                self.assertIsNone(policy.read_lift_block(text))


class DeletedLines(unittest.TestCase):
    def test_only_hunk_deletions_count_a_dashed_line_included(self) -> None:
        diff = (
            b"diff --git a/f.txt b/f.txt\n"
            b"--- a/f.txt\n+++ b/f.txt\n"
            b"@@ -1,2 +1 @@\n-gone\n--- looks like a header\n+kept\n"
            b"diff --git a/new.txt b/new.txt\n"
            b"--- /dev/null\n+++ b/new.txt\n@@ -0,0 +1 @@\n+added\n"
        )
        self.assertEqual(
            list(lift._deleted(diff)),
            [("f.txt", b"gone"), ("f.txt", b"-- looks like a header")],
        )

    def test_a_revert_commit_yields_the_lines_it_deleted(self) -> None:
        repo = Fixture(self)
        repo.commit("base", {"keep.txt": "k\n"})
        repo.commit("feat: add (#5)", {"src/f.py": "a\nb\nc\n"})
        revert = repo.commit('Revert "feat: add (#5)"', {"src/f.py": "a\n"})
        self.assertEqual(
            lift.revert_lines(repo.dir, [revert]),
            [("src/f.py", b"b"), ("src/f.py", b"c")],
        )

    @staticmethod
    def with_canary(repo: Fixture) -> None:
        """This tree's canary in the fixture, untracked, as main's checkout
        carries its own: the script scans the repository it sits in."""
        for part in (
            "scripts/check-silent-revert.sh",
            "scripts/lib/changed-files.sh",
            "scripts/lib/changelog-fragments.sh",
        ):
            target = pathlib.Path(repo.dir, part)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / part).read_bytes())

    def test_the_canary_yields_the_lines_its_finding_counts(self) -> None:
        repo = Fixture(self)
        repo.commit("base", {"keep.txt": "k\n"})
        repo.commit("feat: add (#5)", {"f.txt": "one\ntwo\nthree\nfour\n"})
        silent = repo.commit("feat: other (#6)", {"f.txt": "one\n"})
        clean = repo.commit("docs: touch (#7)", {"keep.txt": "k\nl\n"})
        self.with_canary(repo)
        with mock.patch.dict(os.environ, {"SILENT_REVERT_THRESHOLD": "3"}):
            self.assertEqual(
                lift.canary_lines(repo.dir, [silent]),
                [("f.txt", b"two"), ("f.txt", b"three"), ("f.txt", b"four")],
            )
            self.assertEqual(lift.canary_lines(repo.dir, [clean]), [])

    def test_the_canary_scans_from_a_relative_repo_dir(self) -> None:
        # The alert passes `--repo-dir .base`, relative to its working
        # directory.
        repo = Fixture(self)
        repo.commit("base", {"keep.txt": "k\n"})
        repo.commit("feat: add (#5)", {"f.txt": "one\ntwo\nthree\nfour\n"})
        silent = repo.commit("feat: other (#6)", {"f.txt": "one\n"})
        self.with_canary(repo)
        parent, base = os.path.split(repo.dir)
        with (
            mock.patch.dict(os.environ, {"SILENT_REVERT_THRESHOLD": "3"}),
            contextlib.chdir(parent),
        ):
            self.assertEqual(
                lift.canary_lines(base, [silent]),
                [("f.txt", b"two"), ("f.txt", b"three"), ("f.txt", b"four")],
            )

    def test_a_deleted_line_holding_tabs_is_kept_whole(self) -> None:
        repo = Fixture(self)
        repo.commit("base", {"keep.txt": "k\n"})
        repo.commit("feat: add (#5)", {"f.go": "func f() {\n\tone()\n\ta\tb\n\t\tc\n}\n"})
        silent = repo.commit("feat: other (#6)", {"f.go": "func f() {\n}\n"})
        self.with_canary(repo)
        with mock.patch.dict(os.environ, {"SILENT_REVERT_THRESHOLD": "3"}):
            self.assertEqual(
                lift.canary_lines(repo.dir, [silent]),
                [("f.go", b"\tone()"), ("f.go", b"\ta\tb"), ("f.go", b"\t\tc")],
            )

    def test_a_scan_that_cannot_run_raises(self) -> None:
        repo = Fixture(self)
        repo.commit("base", {"keep.txt": "k\n"})
        self.with_canary(repo)
        with self.assertRaises(RuntimeError):
            lift.canary_lines(repo.dir, ["0" * 40])

    def test_the_cli_prints_the_block_or_fails(self) -> None:
        repo = Fixture(self)
        repo.commit("base", {"f.py": "a\nb\n"})
        revert = repo.commit("revert: drop b", {"f.py": "a\n"})
        out = subprocess.run(
            [sys.executable, str(pathlib.Path(lift.__file__)), "revert-block",
             "--repo-dir", repo.dir, revert],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(
            policy.read_lift_block(out.stdout), {"f.py": {policy.line_hash(b"b"): 1}}
        )
        bad = subprocess.run(
            [sys.executable, str(pathlib.Path(lift.__file__)), "revert-block",
             "--repo-dir", repo.dir, "0" * 40],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual((bad.returncode, bad.stdout), (1, ""))


def ok(payload: Any) -> subprocess.CompletedProcess[str]:
    text = payload if isinstance(payload, str) else json.dumps(payload)
    return subprocess.CompletedProcess([], 0, text, "")


def fail(status: int) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess([], 1, "", f"gh: request failed (HTTP {status})")


REVERT = "<!-- babysit-merge-demotion sha=" + "b" * 40 + " signal=revert -->\n- x"
FIX_MERGE = "e" * 40


class Gh:
    """The policy module's gh seam: the open-record listing, the record and
    lift queries, main's tip, and every write, logged."""

    def __init__(
        self,
        records: dict[int, str],
        references: list[dict[str, Any]],
        files: dict[str, str] | None = None,
    ) -> None:
        self.records, self.references = records, references
        self.files = files or {}
        self.writes: list[list[str]] = []

    def __call__(self, args: list[str], **_: Any) -> subprocess.CompletedProcess[str]:
        if "-X" in args:
            self.writes.append(args)
            return ok({})
        if args[:2] == ["api", "graphql"]:
            query = next(a for a in args if a.startswith("query="))
            number = int(next(a for a in args if a.startswith("n="))[2:])
            if "PolicyRecordLift" in query:
                issue = {
                    "timelineItems": {"pageInfo": {"hasNextPage": False}, "nodes": [
                        {
                            "actor": {"__typename": "Bot", "login": "agent-lanes"},
                            "referencedAt": "2026-10-13T08:00:00Z",
                            "source": p,
                        }
                        for p in self.references
                    ]},
                    "comments": {"pageInfo": {"hasNextPage": False}, "nodes": []},
                }
                return ok({"data": {"repository": {"issue": issue}}})
            record = {
                "number": number,
                "state": "OPEN",
                "body": self.records[number],
                "createdAt": "2026-10-12T10:00:00Z",
                "author": {"__typename": "Bot", "login": "github-actions"},
                "userContentEdits": {"totalCount": 0, "nodes": []},
                "timelineItems": {"nodes": []},
            }
            return ok({"data": {"repository": {"issue": record}}})
        endpoint = next(a for a in args if a.startswith("repos/"))
        if "/issues?state=open" in endpoint:
            if "github-actions" not in endpoint:
                return ok("")
            return ok("\n".join(
                json.dumps({"number": n, "body": b}) for n, b in self.records.items()
            ))
        if endpoint == f"repos/{REPO}/git/ref/heads/main":
            return ok({"object": {"sha": FIX_MERGE}})
        if endpoint in self.files:
            return ok(self.files[endpoint])
        if "/contents/" in endpoint:
            return fail(404)
        raise AssertionError(f"unexpected gh call: {args}")


def merged_pull() -> dict[str, Any]:
    return {
        "__typename": "PullRequest", "number": 7, "merged": True,
        "mergedAt": "2026-10-13T09:00:00Z", "baseRefName": "main",
        "headRefOid": "f" * 40, "mergeCommit": {"oid": FIX_MERGE},
        "repository": {"nameWithOwner": REPO},
        "comments": {"pageInfo": {"hasNextPage": False}, "nodes": []},
    }


class CloseLifted(unittest.TestCase):
    def run_close(self, gh: Gh, status: object = None) -> int:
        with (
            mock.patch.object(policy, "gh_capture", gh),
            mock.patch.object(lift.postmerge, "_role_label", lambda *_: "needs-human"),
            mock.patch.object(lift.postmerge, "_issue_status", lambda *_: status),
            mock.patch("sys.stdout"),
        ):
            return lift.close_lifted(REPO, IDENTITY)

    def test_a_lifted_record_is_commented_unlabeled_and_closed(self) -> None:
        gh = Gh({9: REVERT}, [merged_pull()])
        self.assertEqual(self.run_close(gh), 1)
        self.assertEqual(
            [(w[w.index("-X") + 1], w[w.index("-X") + 2]) for w in gh.writes],
            [
                ("POST", f"repos/{REPO}/issues/9/comments"),
                ("DELETE", f"repos/{REPO}/issues/9/labels/needs-human"),
                ("PATCH", f"repos/{REPO}/issues/9"),
            ],
        )
        self.assertIn("state_reason=completed", gh.writes[2])
        self.assertIn(f"pull request #7 merged at {FIX_MERGE}", gh.writes[0][-1])

    def test_a_stack_layer_merged_into_main_lifts_the_record(self) -> None:
        # An upper layer of a native stack lands with the layers below it and
        # keeps the lower layer's branch as its base; its stack's base is main.
        layer = merged_pull() | {"baseRefName": "feat/lower", "stack": {"baseRefName": "main"}}
        gh = Gh({9: REVERT}, [layer])
        self.assertEqual(self.run_close(gh), 1)
        self.assertIn(f"pull request #7 merged at {FIX_MERGE}", gh.writes[0][-1])

    def test_a_pull_request_into_another_branch_lifts_nothing(self) -> None:
        for other in (
            {"baseRefName": "feat/lower"},
            {"baseRefName": "feat/lower", "stack": None},
            {"baseRefName": "feat/lower", "stack": {"baseRefName": "release"}},
        ):
            gh = Gh({9: REVERT}, [merged_pull() | other])
            self.assertEqual((self.run_close(gh), gh.writes), (0, []), other)

    def test_a_field_repository_close_removes_a_legacy_label(self) -> None:
        # A record filed before the repository set models.issue-status still
        # carries the label; post-merge-demotion-alert.yml removes it on close.
        gh = Gh({9: REVERT}, [merged_pull()])
        self.assertEqual(self.run_close(gh, status=object()), 1)
        self.assertEqual(
            [(w[w.index("-X") + 1], w[w.index("-X") + 2]) for w in gh.writes],
            [
                ("POST", f"repos/{REPO}/issues/9/comments"),
                ("DELETE", f"repos/{REPO}/issues/9/labels/needs-human"),
                ("PATCH", f"repos/{REPO}/issues/9"),
            ],
        )

    def test_a_content_lift_pins_the_commit_it_was_found_at(self) -> None:
        body = REVERT + "\n" + policy.lift_block([("f.py", b"gone")])
        gh = Gh({9: body}, [], {f"repos/{REPO}/contents/f.py?ref={FIX_MERGE}": "gone\n"})
        self.assertEqual(self.run_close(gh), 1)
        comment = gh.writes[0][-1]
        self.assertTrue(
            comment.startswith(f"body=<!-- lift-evidence sha={FIX_MERGE} -->\n"), comment
        )
        self.assertIn("the deleted content is on main at", comment)

    def test_a_copy_the_deletion_left_behind_closes_nothing(self) -> None:
        # The close runs the merge gate's own rule: a deleted line the file
        # still held at the record's SHA is no restore.
        body = REVERT + "\n" + policy.lift_block([("f.py", b"gone")])
        files = {
            f"repos/{REPO}/contents/f.py?ref={FIX_MERGE}": "gone\n",
            f"repos/{REPO}/contents/f.py?ref={'b' * 40}": "gone\n",
        }
        gh = Gh({9: body}, [], files)
        self.assertEqual((self.run_close(gh), gh.writes), (0, []))

    def test_a_failed_evidence_comment_leaves_the_record_open(self) -> None:
        # The comment carries the lift evidence; without it the record must
        # stay open and labeled for the next run to retry.
        gh = Gh({9: REVERT}, [merged_pull()])

        def comment_fails(args: list[str], **kw: Any) -> subprocess.CompletedProcess[str]:
            if "POST" in args:
                gh.writes.append(args)
                return fail(502)
            return gh(args, **kw)

        with (
            mock.patch.object(policy, "gh_capture", comment_fails),
            mock.patch.object(lift.postmerge, "_role_label", lambda *_: "needs-human"),
            mock.patch("sys.stdout"),
        ):
            self.assertEqual(lift.close_lifted(REPO, IDENTITY), 0)
        self.assertEqual(
            [(w[w.index("-X") + 1]) for w in gh.writes], ["POST"]
        )

    def test_a_record_that_has_not_lifted_stays_open(self) -> None:
        gh = Gh({9: REVERT}, [])
        self.assertEqual((self.run_close(gh), gh.writes), (0, []))

    def test_a_record_of_another_kind_is_never_read(self) -> None:
        red = "<!-- babysit-merge-demotion sha=" + "b" * 40 + " signal=schedule -->"
        gh = Gh({9: red}, [merged_pull()])
        self.assertEqual((self.run_close(gh), gh.writes), (0, []))

    def test_a_failed_read_closes_nothing(self) -> None:
        gh = Gh({9: REVERT}, [merged_pull()])

        def broken(args: list[str], **kw: Any) -> subprocess.CompletedProcess[str]:
            if args[:2] == ["api", "graphql"]:
                return fail(502)
            return gh(args, **kw)

        with (
            mock.patch.object(policy, "gh_capture", broken),
            mock.patch.object(lift.postmerge, "_role_label", lambda *_: "needs-human"),
            mock.patch("sys.stdout"),
        ):
            self.assertEqual(lift.close_lifted(REPO, IDENTITY), 0)
        self.assertEqual(gh.writes, [])


if __name__ == "__main__":
    unittest.main()

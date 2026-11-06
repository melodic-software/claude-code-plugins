"""The merge gate's verification evidence comment (`babysit_evidence_comment`):
which capture artifact it links, the body it renders, and the `post` command
enable-auto-merge.mjs runs."""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_evidence_comment as ec
import babysit_merge

REPO = "owner/repo"
PR = 41
HEAD = "a" * 40
NAME = f"pr-capture-{PR}-{HEAD}"
LISTING = f"repos/{REPO}/actions/artifacts?name={NAME}&per_page=100"


def capture_run(**overrides: Any) -> dict[str, Any]:
    return {
        "id": 900,
        "path": ".github/workflows/pr-verify-capture.yml",
        "event": "workflow_run",
        "head_branch": "main",
        "repository": {"full_name": REPO},
        "conclusion": "success",
        "display_title": f"pr-verify-capture 812 {HEAD}",
        **overrides,
    }


def artifact(**overrides: Any) -> dict[str, Any]:
    return {
        "id": 5001,
        "name": NAME,
        "expired": False,
        "expires_at": "2026-12-06T10:00:00Z",
        "workflow_run": {"id": 900},
        **overrides,
    }


def reader(answers: dict[str, Any]) -> Any:
    def read(args: list[str]) -> Any:
        if args[1] not in answers:
            raise AssertionError(f"unexpected read: {args}")
        answer = answers[args[1]]
        if isinstance(answer, Exception):
            raise answer
        return answer

    return read


class FindCapture(unittest.TestCase):
    def test_the_capture_workflows_artifact_is_found(self) -> None:
        read = reader(
            {
                LISTING: {"artifacts": [artifact()]},
                f"repos/{REPO}/actions/runs/900": capture_run(),
            }
        )
        self.assertEqual(
            ec.find_capture(REPO, PR, HEAD, read),
            {
                "name": NAME,
                "runId": 900,
                "artifactId": 5001,
                "expiresAt": "2026-12-06T10:00:00Z",
            },
        )

    def test_an_artifact_from_any_other_run_is_not_taken(self) -> None:
        for name, run in (
            ("another workflow", capture_run(path=".github/workflows/ci.yml")),
            ("a pull request event", capture_run(event="pull_request")),
            ("a branch", capture_run(head_branch="feat")),
            ("a fork", capture_run(repository={"full_name": "fork/repo"})),
            ("a failed run", capture_run(conclusion="failure")),
            ("another head", capture_run(display_title=f"pr-verify-capture 812 {'b' * 40}")),
            ("no record", None),
        ):
            with self.subTest(name):
                read = reader(
                    {
                        LISTING: {"artifacts": [artifact()]},
                        f"repos/{REPO}/actions/runs/900": run,
                    }
                )
                self.assertIsNone(ec.find_capture(REPO, PR, HEAD, read))

    def test_expired_or_misnamed_artifacts_are_not_read_further(self) -> None:
        read = reader(
            {
                LISTING: {
                    "artifacts": [
                        artifact(expired=True),
                        artifact(name=f"{NAME}-x"),
                        artifact(id="5001"),
                        artifact(workflow_run={}),
                    ]
                }
            }
        )
        self.assertIsNone(ec.find_capture(REPO, PR, HEAD, read))

    def test_the_newest_capture_run_wins(self) -> None:
        read = reader(
            {
                LISTING: {
                    "artifacts": [
                        artifact(),
                        artifact(id=5002, workflow_run={"id": 901}),
                    ]
                },
                f"repos/{REPO}/actions/runs/901": capture_run(id=901),
            }
        )
        found = ec.find_capture(REPO, PR, HEAD, read)
        self.assertEqual((found or {}).get("artifactId"), 5002)

    def test_an_unreadable_run_does_not_hide_the_capture_run(self) -> None:
        listing = {
            "artifacts": [artifact(), artifact(id=5002, workflow_run={"id": 901})]
        }
        read = reader(
            {
                LISTING: listing,
                f"repos/{REPO}/actions/runs/901": RuntimeError("HTTP 404"),
                f"repos/{REPO}/actions/runs/900": capture_run(),
            }
        )
        found = ec.find_capture(REPO, PR, HEAD, read)
        self.assertEqual((found or {}).get("artifactId"), 5001)
        # With no capture run found, the failed read is the answer.
        read = reader(
            {
                LISTING: {"artifacts": [artifact()]},
                f"repos/{REPO}/actions/runs/900": RuntimeError("HTTP 502"),
            }
        )
        with self.assertRaisesRegex(RuntimeError, "HTTP 502"):
            ec.find_capture(REPO, PR, HEAD, read)


class Post(unittest.TestCase):
    def test_a_capture_writes_the_marked_body(self) -> None:
        written: list[str] = []
        read = reader(
            {
                LISTING: {"artifacts": [artifact()]},
                f"repos/{REPO}/actions/runs/900": capture_run(),
            }
        )
        outcome = ec.post(REPO, PR, HEAD, read, lambda b: written.append(b) or "created")
        self.assertEqual(outcome, "created")
        (body,) = written
        self.assertEqual(body.split("\n", 1)[0], ec.MARKER)
        self.assertIn(
            f"[{NAME}](https://github.com/{REPO}/actions/runs/900/artifacts/5001), "
            "expires on 2026-12-06.",
            body,
        )

    def test_no_capture_writes_nothing(self) -> None:
        read = reader({LISTING: {"total_count": 0, "artifacts": []}})
        outcome = ec.post(REPO, PR, HEAD, read, mock.Mock(side_effect=AssertionError))
        self.assertEqual(outcome, "no-capture")

    def test_a_failed_read_is_reported_not_raised(self) -> None:
        read = reader({LISTING: RuntimeError("HTTP 403")})
        self.assertEqual(
            ec.post(REPO, PR, HEAD, read, mock.Mock()), "error: HTTP 403"
        )

    def test_a_head_that_is_not_a_sha_reads_nothing(self) -> None:
        self.assertEqual(
            ec.post(REPO, PR, "main", reader({}), mock.Mock()),
            "error: the head is not a commit SHA",
        )

    def test_an_expiry_that_is_not_a_timestamp_names_the_retention_setting(
        self,
    ) -> None:
        body = ec.evidence_body(
            REPO,
            HEAD,
            {"name": NAME, "runId": 900, "artifactId": 5001, "expiresAt": None},
        )
        self.assertIn("expires with the repository's artifact retention setting", body)


class Command(unittest.TestCase):
    def test_post_upserts_under_the_identity_and_prints_the_outcome(self) -> None:
        calls: list[tuple[Any, ...]] = []

        def gh_json(args: list[str], env: Any = None) -> Any:
            calls.append(("read", args[1], env))
            if args[1] == LISTING:
                return {"artifacts": [artifact()]}
            return capture_run()

        def upsert(repo: str, number: int, identity: str, body: str, comments: Any, marker: str) -> str:
            calls.append(("write", identity, marker, comments))
            return "created"

        out = io.StringIO()
        with (
            mock.patch("babysit_gh.gh_json", side_effect=gh_json),
            mock.patch.object(babysit_merge, "upsert_marker_comment", side_effect=upsert),
            mock.patch.dict("os.environ", {ec.TOKEN_ENV: "job"}),
            contextlib.redirect_stdout(out),
        ):
            code = ec.main(
                ["post", "--repo", REPO, "--pr", str(PR), "--head", HEAD, "--identity", "lanes[bot]"]
            )
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out.getvalue()), {"outcome": "created"})
        self.assertEqual(calls[0], ("read", LISTING, {"GH_TOKEN": "job"}))
        self.assertEqual(calls[-1], ("write", "lanes[bot]", ec.MARKER, None))


if __name__ == "__main__":
    unittest.main()

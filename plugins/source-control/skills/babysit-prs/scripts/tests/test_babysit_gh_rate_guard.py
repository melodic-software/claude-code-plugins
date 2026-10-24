"""The rate-limit guard in `babysit_gh._run_gh`.

Expected values come from two sources the code does not compute: the shared
decision vectors (.github/actions/log-api-budget/rate-guard.vectors.json, run
by the JavaScript client too) and the `limits.api` shares in
docs/conventions/pr-pipeline.yaml with their schema defaults. Canned gh output
follows GitHub's documented signals and `gh api -i`'s observed shape.
"""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import textwrap
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_gh as gh
import babysit_merge as merge
import babysit_verify_evidence as verify_evidence

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent
REPO_ROOT = SCRIPTS.parents[4]
VECTORS = (
    REPO_ROOT / ".github" / "actions" / "log-api-budget" / "rate-guard.vectors.json"
)
SCHEMA = REPO_ROOT / "docs" / "conventions" / "pr-pipeline" / "pr-pipeline.schema.json"


def schema_default(field: str) -> float:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    return schema["$defs"]["api-pool"]["properties"][field]["default"]


def head(status: int, **headers: str) -> str:
    lines = [f"HTTP/2.0 {status} X", "Content-Type: application/json"]
    lines += [f"{name.replace('_', '-')}: {value}" for name, value in headers.items()]
    return "\r\n".join(lines) + "\r\n\r\n"


def core(remaining: int, limit: int = 5000, **extra: str) -> dict[str, str]:
    return {
        "X_Ratelimit_Limit": str(limit),
        "X_Ratelimit_Remaining": str(remaining),
        "X_Ratelimit_Reset": "4102444800",  # 2100-01-01, after any test run
        "X_Ratelimit_Resource": "core",
        **extra,
    }


class SharedVectors(unittest.TestCase):
    def test_every_vector_in_the_shared_file(self) -> None:
        table = json.loads(VECTORS.read_text(encoding="utf-8"))
        floor = schema_default("read-floor")
        self.assertTrue(table["vectors"])
        for vector in table["vectors"]:
            with self.subTest(vector["name"]):
                given = vector["input"]
                got = gh.evaluate_rate_response(
                    url=given["url"],
                    status=given["status"],
                    headers=given["headers"],
                    body=given["body"],
                    now=table["vector_now"],
                    read_floor=floor,
                )
                self.assertEqual(got, vector["expect"])


class GuardCase(unittest.TestCase):
    """gh is faked at `babysit_gh.run_command`; each answer is consumed in
    order, and `sent` is every argv that reached it."""

    def setUp(self) -> None:
        gh.reset_rate_guard()
        self.addCleanup(gh.reset_rate_guard)
        self.sent: list[list[str]] = []
        self.answers: list[tuple[int, str, str]] = []

        def fake(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.sent.append(argv)
            code, stdout, stderr = self.answers.pop(0)
            return subprocess.CompletedProcess(argv, code, stdout, stderr)

        for patcher in (
            mock.patch.object(gh, "run_command", fake),
            mock.patch.dict(
                os.environ,
                {"API_BUDGET_TOKEN": "", "GITHUB_ACTIONS": "true"},
            ),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def answer(self, code: int, stdout: str, stderr: str = "") -> None:
        self.answers.append((code, stdout, stderr))


class TheLatchTripsOnEachSignal(GuardCase):
    def assert_tripped_then_silent(self, args: list[str], *, raised: bool) -> None:
        if raised:
            with self.assertRaises(gh.RateLimitExhausted):
                gh.gh_capture(args)
        else:
            gh.gh_capture(args)
        sent = len(self.sent)
        with self.assertRaises(gh.RateLimitExhausted):
            gh.gh_capture(args)
        self.assertEqual(len(self.sent), sent, "a call was sent after the trip")

    def test_remaining_zero_on_a_success_returns_it_and_stops_the_next(self) -> None:
        self.answer(0, head(200, **core(0)) + '{"ok":1}')
        proc = gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertEqual(proc.stdout, '{"ok":1}')
        with self.assertRaises(gh.RateLimitExhausted):
            gh.gh_capture(["api", "repos/o/r/pulls/2"])
        self.assertEqual(len(self.sent), 1)

    def test_a_primary_403(self) -> None:
        self.answer(
            1,
            head(403, **core(0))
            + '{"message":"API rate limit exceeded for user ID 1."}',
            "gh: API rate limit exceeded for user ID 1. (HTTP 403)",
        )
        self.assert_tripped_then_silent(["api", "repos/o/r/pulls/1"], raised=True)

    def test_a_secondary_429(self) -> None:
        self.answer(
            1,
            head(429, **core(4000))
            + '{"message":"You have exceeded a secondary rate limit."}',
            "gh: You have exceeded a secondary rate limit. (HTTP 429)",
        )
        self.assert_tripped_then_silent(["api", "repos/o/r/pulls/1"], raised=True)

    def test_retry_after(self) -> None:
        self.answer(0, head(200, **core(4000, Retry_After="60")) + "{}")
        self.assert_tripped_then_silent(["api", "repos/o/r/pulls/1"], raised=False)

    def test_graphql_rate_limited(self) -> None:
        body = (
            '{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}'
        )
        self.answer(1, head(200) + body, "gh: API rate limit exceeded")
        self.assert_tripped_then_silent(
            ["api", "graphql", "-f", "query=query{viewer{login}}"], raised=True
        )

    def test_a_subcommand_naming_a_rate_limit(self) -> None:
        self.answer(1, "", "GraphQL: API rate limit exceeded for user ID 1.")
        self.assert_tripped_then_silent(
            ["pr", "view", "1", "--json", "number"], raised=True
        )

    def test_a_secondary_limit_stops_every_pool(self) -> None:
        self.answer(
            1,
            head(403, **core(4000, Retry_After="60"))
            + '{"message":"You have exceeded a secondary rate limit."}',
            "gh: You have exceeded a secondary rate limit. (HTTP 403)",
        )
        with self.assertRaises(gh.RateLimitExhausted):
            gh.gh_capture(["api", "repos/o/r/pulls/1"])
        with self.assertRaises(gh.RateLimitExhausted):
            gh.gh_capture(["api", "graphql", "-f", "query=query{viewer{login}}"])
        self.assertEqual(len(self.sent), 1)

    def test_a_spent_pool_leaves_the_others_open(self) -> None:
        self.answer(
            0, head(200, **{**core(0), "X_Ratelimit_Resource": "search"}) + "{}"
        )
        self.answer(0, head(200, **core(4000)) + "{}")
        gh.gh_capture(["api", "search/issues?q=x"])
        with self.assertRaises(gh.RateLimitExhausted):
            gh.gh_capture(["api", "search/issues?q=y"])
        gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertEqual(len(self.sent), 2)


class WhatIsNotARateLimit(GuardCase):
    def test_a_403_that_is_not_a_rate_limit_is_not_latched(self) -> None:
        self.answer(
            1,
            head(403, **core(4000))
            + '{"message":"Resource not accessible by integration"}',
            "gh: Resource not accessible by integration (HTTP 403)",
        )
        self.answer(0, head(200, **core(3999)) + "{}")
        self.assertEqual(gh.gh_capture(["api", "repos/o/r/pulls/1"]).returncode, 1)
        self.assertEqual(gh.gh_capture(["api", "repos/o/r/pulls/1"]).returncode, 0)
        self.assertEqual(len(self.sent), 2)

    def test_a_5xx_keeps_its_bounded_retry(self) -> None:
        # The verdict listing re-reads after each of LISTING_WAITS on a 5xx;
        # the guard lets every one of those reads through.
        for _ in range(len(verify_evidence.LISTING_WAITS) + 1):
            # A paginated read runs without -i: gh prints only its message.
            self.answer(1, "", "gh: Server Error (HTTP 502)")
        reader = verify_evidence.Reader("o/r", "main")
        with (
            mock.patch.object(verify_evidence, "_listing_sleep"),
            self.assertRaises(verify_evidence._Unreadable),
        ):
            reader._listing()
        self.assertEqual(len(self.sent), len(verify_evidence.LISTING_WAITS) + 1)


class HeadroomShares(GuardCase):
    def shares(self, pool: str) -> dict[str, float]:
        limits = gh.pool_limits(pool)
        assert not isinstance(limits, str), limits
        return limits

    def test_a_set_share_is_read_and_an_unset_one_is_the_schema_default(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config = pathlib.Path(tmp, "pr-pipeline.yaml")
            config.write_text(
                "limits:\n  api:\n    lanes-app:\n      writer-pause: 0.3\n",
                encoding="utf-8",
            )
            with mock.patch.object(gh, "LIMITS_CONFIG", config):
                shares = self.shares("lanes-app")
        self.assertEqual(shares["writer-pause"], 0.3)
        self.assertEqual(shares["read-floor"], schema_default("read-floor"))

    def test_below_the_read_floor_report_only_reads_are_skipped(self) -> None:
        floor = self.shares("github-token")["read-floor"]
        just_below = int(floor * 5000) - 1
        self.answer(0, head(200, **core(just_below)) + "{}")
        gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertTrue(gh.low_headroom())
        reader = mock.Mock(spec=verify_evidence.Reader)
        verify = {
            "refusal": verify_evidence.REPEATED_FAIL,
            "headFail": {"run": 7, "artifact": "a"},
            "head": "h",
        }
        self.assertIsNone(merge._fail_summary(verify, {"verify_reader": reader}, 1))
        reader.fail_summary.assert_not_called()

    def test_at_the_read_floor_the_read_runs(self) -> None:
        floor = self.shares("github-token")["read-floor"]
        self.answer(0, head(200, **core(int(floor * 5000))) + "{}")
        gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertFalse(gh.low_headroom())

    def test_below_the_writer_pause_a_write_is_not_sent(self) -> None:
        pause = self.shares("github-token")["writer-pause"]
        self.answer(0, head(200, **core(int(pause * 5000) - 1)) + "{}")
        self.answer(0, head(200, **core(1000)) + "{}")
        gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertTrue(gh.writes_paused("github-token"))
        with self.assertRaises(gh.WritesPaused):
            gh.gh_capture(
                ["api", "-X", "POST", "repos/o/r/issues/1/labels", "-f", "labels[]=x"]
            )
        with self.assertRaises(gh.WritesPaused):
            gh.gh_capture(["pr", "comment", "1", "--body", "x"])
        gh.gh_capture(["api", "repos/o/r/pulls/2"])
        self.assertEqual(len(self.sent), 2)


class FailClosed(GuardCase):
    def test_an_unreadable_limits_block_sends_nothing(self) -> None:
        with mock.patch.object(gh, "LIMITS_CONFIG", REPO_ROOT / "no-such-file.yaml"):
            with self.assertRaises(gh.RateLimitExhausted) as raised:
                gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertIn("fail closed", str(raised.exception))
        self.assertEqual(self.sent, [])

    def test_an_unreadable_schema_sends_nothing(self) -> None:
        with mock.patch.object(gh, "LIMITS_SCHEMA", REPO_ROOT / "no-such-schema.json"):
            with self.assertRaises(gh.RateLimitExhausted):
                gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertEqual(self.sent, [])


class TheProcessExitsRed(unittest.TestCase):
    def run_python(self, body: str) -> subprocess.CompletedProcess[str]:
        code = f"import sys; sys.path.insert(0, {str(SCRIPTS)!r})\n" + textwrap.dedent(
            body
        )
        return subprocess.run(
            [sys.executable, "-c", code], capture_output=True, text=True, check=False
        )

    def test_an_uncaught_trip_prints_one_error_naming_the_reset(self) -> None:
        proc = self.run_python(
            """
            import babysit_gh as gh
            raise gh.RateLimitExhausted("core", 1792863330, "x-ratelimit-reset reset")
            """
        )
        self.assertEqual(proc.returncode, 75)  # the code pr-merge.yml stops on
        errors = [
            line for line in proc.stderr.splitlines() if line.startswith("::error")
        ]
        self.assertEqual(len(errors), 1, proc.stderr)
        # 1792863330 is 2026-10-24T17:35:30Z (date -u -d @1792863330).
        self.assertIn("2026-10-24T17:35:30Z", errors[0])
        self.assertIn("core", errors[0])
        self.assertNotIn("Traceback", proc.stderr)

    def test_a_swallowed_trip_still_exits_red(self) -> None:
        proc = self.run_python(
            """
            import babysit_gh as gh
            try:
                raise gh._trip("graphql", 1792863330, "x-ratelimit-reset reset")
            except BaseException:
                pass
            """
        )
        self.assertEqual(proc.returncode, 75)
        self.assertIn("2026-10-24T17:35:30Z", proc.stderr)
        self.assertIn("graphql", proc.stderr)


if __name__ == "__main__":
    unittest.main()

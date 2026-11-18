# test-scope: plugins/source-control/skills/babysit-prs/scripts/*.py
"""The bounded retry of a read in `babysit_gh._send`.

Expected values come from the outage posture's element 1 in
docs/conventions/pr-pipeline/README.md ("Each call gets at most 3 attempts",
"capped exponential backoff with full jitter", "Non-idempotent writes are never
retried"). The stderr shapes are the ones the pr-merge job logged:
`gh: Server Error (HTTP 502)` and `gh: HTTP 502`. A subcommand's shape is
go-gh's `HTTPError.Error()`, `HTTP %d: %s (%s)` (cli/go-gh pkg/api/errors.go).
"""

from __future__ import annotations

import io
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_gh as gh
import babysit_verify_evidence as verify_evidence
from babysit_util import deadline_after, read_deadline

READ = ["api", "repos/acme/widgets/pulls/7"]
READ_KIND = "default GET repos/{}/{}/pulls/{}"
BAD_GATEWAY = "gh: Server Error (HTTP 502)\n"


def head(status: int, **headers: str) -> str:
    lines = [f"HTTP/2.0 {status} X", "Content-Type: application/json"]
    lines += [f"{name.replace('_', '-')}: {value}" for name, value in headers.items()]
    return "\r\n".join(lines) + "\r\n\r\n"


class RetryCase(unittest.TestCase):
    """gh is faked at `babysit_gh.run_command`; each answer is consumed in
    order, `sent` is every argv that reached it and `waits` every sleep."""

    def setUp(self) -> None:
        gh.reset_rate_guard()
        gh.reset_gh_call_counts()
        self.addCleanup(gh.reset_rate_guard)
        self.addCleanup(gh.reset_gh_call_counts)
        self.sent: list[list[str]] = []
        self.timeouts: list[float] = []
        self.answers: list[tuple[int, str, str, float]] = []
        self.waits: list[float] = []
        self.oversleep = 0.0
        self.now = 1000.0
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)

        def sleep(seconds: float) -> None:
            self.waits.append(seconds)
            self.now += seconds + self.oversleep

        def fake(argv: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.sent.append(argv)
            self.timeouts.append(kwargs["timeout_seconds"])
            code, stdout, stderr, seconds = self.answers.pop(0)
            self.now += seconds
            return subprocess.CompletedProcess(argv, code, stdout, stderr)

        for patcher in (
            mock.patch.object(gh, "run_command", fake),
            mock.patch.object(gh, "_retry_sleep", sleep),
            mock.patch.object(gh, "_retry_clock", lambda: self.now),
            mock.patch.dict(
                os.environ,
                {
                    "API_BUDGET_TOKEN": "",
                    "GITHUB_ACTIONS": "true",
                    "RUNNER_TEMP": temp.name,
                },
            ),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def answer(
        self, code: int, stdout: str, stderr: str = "", seconds: float = 0.0
    ) -> None:
        self.answers.append((code, stdout, stderr, seconds))

    def bad_gateway(self, times: int = 1, seconds: float = 0.0) -> None:
        for _ in range(times):
            self.answer(
                1, head(502) + '{"message":"Server Error"}', BAD_GATEWAY, seconds
            )


class ATransientReadIsSentAgain(RetryCase):
    def test_a_502_then_a_success_returns_it_with_two_calls_counted(self) -> None:
        self.bad_gateway()
        self.answer(0, head(200) + '{"number":7}')
        proc = gh.gh_capture(READ)
        self.assertEqual((proc.returncode, proc.stdout), (0, '{"number":7}'))
        self.assertEqual(len(self.sent), 2)
        self.assertEqual(gh.gh_call_counts(), {READ_KIND: 2})
        self.assertEqual(len(self.waits), 1)

    def test_every_status_from_500_to_599_is_sent_again(self) -> None:
        for status in (500, 501, 503, 504, 599):
            with self.subTest(status):
                self.sent.clear()
                self.answer(1, head(status) + "{}", f"gh: HTTP {status}\n")
                self.answer(0, head(200) + "{}")
                self.assertEqual(gh.gh_capture(READ).returncode, 0)
                self.assertEqual(len(self.sent), 2)

    def test_a_status_only_stderr_names_it_with_no_header_block(self) -> None:
        for stderr in ("gh: HTTP 502\n", BAD_GATEWAY):
            with self.subTest(stderr):
                self.sent.clear()
                self.answer(1, "", stderr)
                self.answer(0, head(200) + "{}")
                self.assertEqual(gh.gh_capture(READ).returncode, 0)
                self.assertEqual(len(self.sent), 2)

    def test_a_graphql_query_is_sent_again(self) -> None:
        self.answer(1, head(502) + "{}", BAD_GATEWAY)
        self.answer(0, head(200) + '{"data":{}}')
        proc = gh.gh_capture(
            ["api", "graphql", "-f", "query=query { viewer { login } }"]
        )
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(len(self.sent), 2)

    def test_one_page_of_a_paged_read_is_sent_again_and_paging_goes_on(self) -> None:
        link = {"Link": '<https://api.github.com/repos/o/r/pulls?page=2>; rel="next"'}
        self.answer(0, head(200, **link) + "[1]")
        self.bad_gateway()
        self.answer(0, head(200) + "[2]")
        proc = gh.gh_capture(["api", "repos/o/r/pulls", "--paginate", "--slurp"])
        self.assertEqual((proc.returncode, proc.stdout), (0, "[[1], [2]]"))
        self.assertEqual(len(self.sent), 3)

    def test_each_retry_logs_one_line_that_names_no_repository(self) -> None:
        self.bad_gateway(2)
        self.answer(0, head(200) + "{}")
        err = io.StringIO()
        with redirect_stderr(err):
            gh.gh_capture(READ)
        lines = err.getvalue().splitlines()
        self.assertEqual(len(lines), 2)
        for attempt, line in enumerate(lines, 1):
            self.assertIn(READ_KIND, line)
            self.assertIn("502", line)
            self.assertIn(f"attempt {attempt} of 3", line)
            self.assertNotIn("acme", line)


class TheAttemptsAreBounded(RetryCase):
    def test_three_502s_fail_as_one_did_after_three_attempts(self) -> None:
        self.bad_gateway(3)
        proc = gh.gh_capture(READ)
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(proc.stderr, BAD_GATEWAY)
        self.assertEqual(len(self.sent), 3)
        self.assertEqual(gh.gh_call_counts(), {READ_KIND: 3})

    def test_a_checked_read_still_raises_gh_s_message(self) -> None:
        self.bad_gateway(3)
        with self.assertRaisesRegex(RuntimeError, r"Server Error \(HTTP 502\)"):
            gh.run_gh(READ)
        self.assertEqual(len(self.sent), 3)

    def test_each_wait_is_a_random_share_of_4_then_8_seconds(self) -> None:
        self.bad_gateway(3)
        with mock.patch.object(gh.random, "uniform", lambda low, high: high):
            gh.gh_capture(READ)
        self.assertEqual(self.waits, [4.0, 8.0])

    def test_full_jitter_lets_a_wait_be_as_short_as_nothing(self) -> None:
        self.bad_gateway(3)
        with mock.patch.object(gh.random, "uniform", lambda low, high: low):
            gh.gh_capture(READ)
        self.assertEqual(self.waits, [0.0, 0.0])

    def test_a_retry_that_does_not_fit_the_timeout_is_not_sent(self) -> None:
        self.bad_gateway()
        with mock.patch.object(gh.random, "uniform", lambda low, high: high):
            proc = gh.gh_capture(READ, timeout_seconds=3.0)
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.waits, [])

    def test_the_attempts_share_the_one_timeout_a_call_gets(self) -> None:
        self.bad_gateway()
        self.answer(0, head(200) + "{}")
        with mock.patch.object(gh.random, "uniform", lambda low, high: 4.0):
            gh.gh_capture(READ, timeout_seconds=30.0)
        self.assertEqual(self.timeouts, [30.0, 26.0])

    def test_a_retry_the_elapsed_attempt_leaves_no_room_for_is_not_sent(self) -> None:
        self.bad_gateway(seconds=40.0)
        self.answer(0, head(200) + "{}")
        with mock.patch.object(gh.random, "uniform", lambda low, high: high):
            proc = gh.gh_capture(READ, timeout_seconds=60.0)
        self.assertEqual((proc.returncode, proc.stderr), (1, BAD_GATEWAY))
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.waits, [])

    def test_a_retry_the_elapsed_attempt_leaves_room_for_is_sent(self) -> None:
        self.bad_gateway(seconds=10.0)
        self.answer(0, head(200) + "{}")
        with mock.patch.object(gh.random, "uniform", lambda low, high: high):
            proc = gh.gh_capture(READ, timeout_seconds=60.0)
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(self.timeouts, [60.0, 46.0])

    def test_a_sleep_that_overruns_the_timeout_sends_nothing_more(self) -> None:
        self.bad_gateway()
        self.answer(0, head(200) + "{}")
        self.oversleep = 30.0
        with mock.patch.object(gh.random, "uniform", lambda low, high: 4.0):
            proc = gh.gh_capture(READ, timeout_seconds=30.0)
        self.assertEqual((proc.returncode, proc.stderr), (1, BAD_GATEWAY))
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.waits, [4.0])

    def test_a_sleep_that_overruns_the_read_phase_sends_nothing_more(self) -> None:
        self.bad_gateway()
        self.answer(0, head(200) + "{}")
        with (
            mock.patch.object(gh.random, "uniform", lambda low, high: 4.0),
            mock.patch.object(gh, "read_seconds_left", side_effect=[60.0, 0.0]),
        ):
            proc = gh.gh_capture(READ)
        self.assertEqual((proc.returncode, proc.stderr), (1, BAD_GATEWAY))
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.waits, [4.0])

    def test_a_retry_past_the_read_phase_deadline_is_not_sent(self) -> None:
        self.bad_gateway()
        with (
            mock.patch.object(gh.random, "uniform", lambda low, high: high),
            read_deadline(deadline_after(3.0)),
        ):
            proc = gh.gh_capture(READ)
        self.assertEqual((proc.returncode, proc.stderr), (1, BAD_GATEWAY))
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.waits, [])

    def test_a_retry_inside_the_read_phase_deadline_is_sent(self) -> None:
        self.bad_gateway()
        self.answer(0, head(200) + "{}")
        with (
            mock.patch.object(gh.random, "uniform", lambda low, high: high),
            read_deadline(deadline_after(60.0)),
        ):
            proc = gh.gh_capture(READ)
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(len(self.sent), 2)


class TheProcessHasTenRetriesToSpend(RetryCase):
    """One process sends at most ten retries, across all of its reads."""

    def spend(self, retries: int) -> None:
        for _ in range(retries):
            self.bad_gateway()
            self.answer(0, head(200) + "{}")
            self.assertEqual(gh.gh_capture(READ).returncode, 0)
        self.sent.clear()
        self.waits.clear()

    def test_the_tenth_retry_is_sent(self) -> None:
        self.spend(9)
        self.bad_gateway()
        self.answer(0, head(200) + "{}")
        self.assertEqual(gh.gh_capture(READ).returncode, 0)
        self.assertEqual(len(self.sent), 2)

    def test_the_retry_after_the_allowance_is_not_sent(self) -> None:
        self.spend(10)
        self.bad_gateway()
        self.answer(0, head(200) + "{}")
        proc = gh.gh_capture(READ)
        self.assertEqual((proc.returncode, proc.stderr), (1, BAD_GATEWAY))
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.waits, [])

    def test_the_allowance_can_run_out_between_two_attempts_of_one_read(self) -> None:
        self.spend(9)
        self.bad_gateway(2)
        self.answer(0, head(200) + "{}")
        self.assertEqual(gh.gh_capture(READ).returncode, 1)
        self.assertEqual(len(self.sent), 2)

    def test_a_retry_that_did_not_fit_spends_none_of_it(self) -> None:
        with mock.patch.object(gh.random, "uniform", lambda low, high: high):
            for _ in range(11):
                self.bad_gateway()
                gh.gh_capture(READ, timeout_seconds=3.0)
        self.sent.clear()
        self.bad_gateway()
        self.answer(0, head(200) + "{}")
        self.assertEqual(gh.gh_capture(READ).returncode, 0)
        self.assertEqual(len(self.sent), 2)


class OnlyATransientReadIsSentAgain(RetryCase):
    def test_a_subcommand_read_is_sent_once(self) -> None:
        self.answer(1, "", "HTTP 502: Bad Gateway (https://api.github.com/graphql)\n")
        self.answer(0, "{}")
        proc = gh.gh_capture(["pr", "view", "7", "--json", "number"])
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.waits, [])

    def test_a_binary_read_is_sent_once(self) -> None:
        self.answer(1, "", BAD_GATEWAY)
        self.answer(0, "{}")
        proc = gh.gh_capture(READ, binary=True)
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.waits, [])

    def test_a_write_is_never_sent_again(self) -> None:
        writes = {
            "REST": [
                "api",
                "-X",
                "POST",
                "repos/o/r/issues/1/labels",
                "-f",
                "labels[]=x",
            ],
            "subcommand": ["pr", "comment", "1", "--body", "x"],
            "mutation": ["api", "graphql", "-f", "query=mutation { a { b } }"],
            "mutation after a comment": [
                "api",
                "graphql",
                "-f",
                "query=# note\nmutation { a { b } }",
            ],
            "document from a file": ["api", "graphql", "-F", "query=@doc.graphql"],
            "document from stdin": ["api", "graphql", "--input", "body.json"],
            "query beside a document from stdin": [
                "api",
                "graphql",
                "-f",
                "query=query { viewer { login } }",
                "--input",
                "body.json",
            ],
        }
        for name, args in writes.items():
            with self.subTest(name):
                self.sent.clear()
                self.bad_gateway()
                self.assertEqual(gh.gh_capture(args).returncode, 1)
                self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.waits, [])

    def test_a_rate_limit_is_never_sent_again(self) -> None:
        for status in (403, 429):
            with self.subTest(status):
                gh.reset_rate_guard()
                shutil.rmtree(
                    pathlib.Path(os.environ["RUNNER_TEMP"], "api-budget"),
                    ignore_errors=True,
                )
                self.sent.clear()
                self.answer(
                    1,
                    head(status) + '{"message":"API rate limit exceeded"}',
                    f"gh: API rate limit exceeded (HTTP {status})\n",
                )
                with self.assertRaises(gh.RateLimitExhausted):
                    gh.gh_capture(READ)
                self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.waits, [])

    def test_a_refusal_that_is_no_rate_limit_is_never_sent_again(self) -> None:
        for status, stderr in (
            (403, "gh: Resource not accessible by integration (HTTP 403)\n"),
            (404, "gh: Not Found (HTTP 404)\n"),
            (499, "gh: Client Closed Request (HTTP 499)\n"),
            (600, "gh: Unknown (HTTP 600)\n"),
        ):
            with self.subTest(status):
                self.sent.clear()
                self.answer(1, head(status) + "{}", stderr)
                self.assertEqual(gh.gh_capture(READ).returncode, 1)
                self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.waits, [])

    def test_a_failure_with_no_status_is_never_sent_again(self) -> None:
        self.answer(1, "", "error connecting to api.github.com\n")
        self.assertEqual(gh.gh_capture(READ).returncode, 1)
        self.assertEqual(len(self.sent), 1)


class EveryAttemptPassesTheGuards(RetryCase):
    def test_a_read_floor_reached_on_attempt_one_refuses_attempt_two(self) -> None:
        low = {
            "X_Ratelimit_Limit": "5000",
            "X_Ratelimit_Remaining": "1",
            "X_Ratelimit_Reset": "4102444800",
            "X_Ratelimit_Resource": "core",
        }
        self.answer(1, head(502, **low) + "{}", BAD_GATEWAY)
        with (
            mock.patch.dict(os.environ, {gh.READ_FLOOR_STOP_ENV: "1"}),
            self.assertRaises(gh.ReadsFloored),
        ):
            gh.gh_capture(READ)
        self.assertEqual(len(self.sent), 1)

    def test_a_rate_limit_on_attempt_two_stops_the_retry(self) -> None:
        self.bad_gateway()
        self.answer(
            1,
            head(429) + '{"message":"API rate limit exceeded"}',
            "gh: API rate limit exceeded (HTTP 429)\n",
        )
        with self.assertRaises(gh.RateLimitExhausted):
            gh.gh_capture(READ)
        self.assertEqual(len(self.sent), 2)
        self.assertEqual(len(self.waits), 1)

    def test_a_502_with_retry_after_holds_as_the_guard_holds_it(self) -> None:
        self.answer(1, head(502, Retry_After="30") + "{}", BAD_GATEWAY)
        with self.assertRaises(gh.RateLimitExhausted) as caught:
            gh.gh_capture(READ)
        self.assertEqual(caught.exception.server_status, 502)
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.waits, [])


class AnOuterRetryDoesNotMultiply(RetryCase):
    """`verify_evidence.Reader` reads a listing again after each of
    `LISTING_WAITS`, so each of its reads goes out once."""

    def reader(self) -> verify_evidence.Reader:
        return verify_evidence.Reader("o/r", "main")

    def outer_reads(self) -> int:
        return len(verify_evidence.LISTING_WAITS) + 1

    def test_the_live_count_is_read_once_per_outer_read(self) -> None:
        self.bad_gateway(self.outer_reads())
        with (
            mock.patch.object(verify_evidence, "_listing_sleep"),
            self.assertRaises(verify_evidence._Transient),
        ):
            self.reader()._live_count()
        self.assertEqual(len(self.sent), self.outer_reads())
        self.assertEqual(self.waits, [])

    def test_the_whole_listing_is_read_once_per_outer_read(self) -> None:
        self.bad_gateway(self.outer_reads())
        with (
            mock.patch.object(verify_evidence, "_listing_sleep"),
            self.assertRaises(verify_evidence._Transient),
        ):
            self.reader()._read_listing()
        self.assertEqual(len(self.sent), self.outer_reads())
        self.assertEqual(self.waits, [])

    def test_a_named_listing_page_is_read_once_per_outer_read(self) -> None:
        self.bad_gateway(self.outer_reads())
        with mock.patch.object(verify_evidence, "_listing_sleep"):
            read = self.reader()._api_object(
                "repos/o/r/actions/artifacts?name=x",
                verify_evidence._listing_clock() + 60.0,
            )
        self.assertIsNone(read)
        self.assertEqual(len(self.sent), self.outer_reads())
        self.assertEqual(self.waits, [])

    def test_a_read_outside_those_loops_keeps_its_retry(self) -> None:
        self.bad_gateway()
        self.answer(0, head(200) + "{}")
        self.assertEqual(self.reader()._actions(READ, "a pull request"), {})
        self.assertEqual(len(self.sent), 2)


class ThePacerCountsEverySend(RetryCase):
    def test_a_502_through_the_pacer_is_one_counted_send(self) -> None:
        self.bad_gateway(3)
        pacer = verify_evidence._Pacer(
            verify_evidence.postmerge.gh_capture, 0, 100, 0, None
        )
        self.assertEqual(pacer._raw(READ).returncode, 1)
        self.assertEqual(pacer.calls, len(self.sent))
        self.assertEqual(pacer.window_calls, 1)
        self.assertEqual(self.waits, [])


if __name__ == "__main__":
    unittest.main()

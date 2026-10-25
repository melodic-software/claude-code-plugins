"""The rate-limit guard in `babysit_gh._run_gh`.

Expected values come from two sources the code does not compute: the shared
decision vectors (.github/actions/log-api-budget/rate-guard.vectors.json, run
by the JavaScript client too) and the `limits.api` shares in
docs/conventions/pr-pipeline.yaml with their schema defaults. Canned gh output
follows GitHub's documented signals and `gh api -i`'s observed shape.
"""

from __future__ import annotations

import io
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
        self.assertGreaterEqual(len(table["vectors"]), 26)
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
        # A job's real RUNNER_TEMP must never take a test's stop.
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.runner_temp = temp.name
        self.stop_file = pathlib.Path(temp.name, "api-budget", "stop")

        def fake(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.sent.append(argv)
            code, stdout, stderr = self.answers.pop(0)
            return subprocess.CompletedProcess(argv, code, stdout, stderr)

        for patcher in (
            mock.patch.object(gh, "run_command", fake),
            mock.patch.dict(
                os.environ,
                {
                    "API_BUDGET_TOKEN": "",
                    "GITHUB_ACTIONS": "true",
                    "RUNNER_TEMP": self.runner_temp,
                },
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


class PaginatedReads(GuardCase):
    """`gh api --paginate --slurp` reads go one guarded page at a time, so
    each page's headers can stop the next page and every later call."""

    NEXT = (
        '<https://api.github.com/repositories/1/pulls?per_page=100&page=2>; rel="next"'
    )

    def test_a_page_that_spends_the_pool_stops_the_next_call(self) -> None:
        self.answer(0, head(200, **core(1, Link=self.NEXT)) + '[{"n":1}]')
        self.answer(0, head(200, **core(0)) + '[{"n":2}]')
        rows = gh.fetch_paginated_api("repos/o/r/pulls?per_page=100", "pulls")
        self.assertEqual(rows, [{"n": 1}, {"n": 2}])
        with self.assertRaises(gh.RateLimitExhausted):
            gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertEqual(len(self.sent), 2)
        self.assertEqual(
            self.sent[1][-1],
            "repositories/1/pulls?per_page=100&page=2",
        )

    def test_a_page_that_spends_the_pool_stops_the_pages_after_it(self) -> None:
        self.answer(0, head(200, **core(0, Link=self.NEXT)) + "[]")
        with self.assertRaises(gh.RateLimitExhausted):
            gh.fetch_paginated_api("repos/o/r/pulls?per_page=100", "pulls")
        self.assertEqual(len(self.sent), 1)

    def test_the_pages_come_back_in_the_slurp_shape(self) -> None:
        self.answer(
            0, head(200, **core(4000, Link=self.NEXT)) + '{"total_count":2,"items":[1]}'
        )
        self.answer(0, head(200, **core(3999)) + '{"total_count":2,"items":[2]}')
        proc = gh.gh_capture(["api", "search/issues?q=x", "--paginate", "--slurp"])
        self.assertEqual(
            json.loads(proc.stdout),
            [{"total_count": 2, "items": [1]}, {"total_count": 2, "items": [2]}],
        )

    def test_a_failed_page_fails_the_read_with_its_own_answer(self) -> None:
        self.answer(0, head(200, **core(4000, Link=self.NEXT)) + "[1]")
        self.answer(
            1, head(404) + '{"message":"Not Found"}', "gh: Not Found (HTTP 404)"
        )
        with self.assertRaises(RuntimeError) as raised:
            gh.fetch_paginated_api("repos/o/r/pulls?per_page=100", "pulls")
        self.assertIn("(HTTP 404)", str(raised.exception))
        self.assertIn("--paginate", str(raised.exception))


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


class NoRepoConfig(GuardCase):
    """The installed-plugin layout: no pr-pipeline.yaml or schema beside it."""

    def setUp(self) -> None:
        super().setUp()
        for name in ("LIMITS_CONFIG", "LIMITS_SCHEMA"):
            patcher = mock.patch.object(gh, name, REPO_ROOT / f"no-such-{name}")
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_calls_go_through_with_no_margins(self) -> None:
        self.answer(0, head(200, **core(1)) + "{}")
        self.answer(0, head(200, **core(1)) + "{}")
        gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertFalse(gh.low_headroom())
        self.assertFalse(gh.writes_paused())
        gh.gh_capture(["pr", "comment", "1", "--body", "x"])
        self.assertEqual(len(self.sent), 2)

    def test_the_latch_still_trips_on_a_403_or_429(self) -> None:
        for status, message in (
            (403, "API rate limit exceeded for user ID 1."),
            (429, "You have exceeded a secondary rate limit."),
        ):
            # Each case is its own job: the last one's stop file goes too.
            gh.reset_rate_guard()
            self.stop_file.unlink(missing_ok=True)
            self.sent.clear()
            self.answer(
                1,
                head(status, **core(0)) + json.dumps({"message": message}),
                f"gh: {message} (HTTP {status})",
            )
            with self.assertRaises(gh.RateLimitExhausted):
                gh.gh_capture(["api", "repos/o/r/pulls/1"])
            with self.assertRaises(gh.RateLimitExhausted):
                gh.gh_capture(["api", "repos/o/r/pulls/2"])
            self.assertEqual(len(self.sent), 1, status)


class FailClosed(GuardCase):
    def present_config(self, text: str) -> pathlib.Path:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        config = pathlib.Path(tmp.name, "pr-pipeline.yaml")
        config.write_text(text, encoding="utf-8")
        return config

    def test_a_present_limits_block_that_is_not_a_share_sends_nothing(self) -> None:
        config = self.present_config(
            "limits:\n  api:\n    github-token:\n      writer-pause: lots\n"
        )
        with mock.patch.object(gh, "LIMITS_CONFIG", config):
            with self.assertRaises(gh.RateLimitExhausted) as raised:
                gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertIn("fail closed", str(raised.exception))
        self.assertEqual(self.sent, [])

    def test_a_present_config_its_reader_cannot_run_sends_nothing(self) -> None:
        # No usable bash: the shared reader fails.
        def no_bash(
            argv: list[str], **_kwargs: Any
        ) -> subprocess.CompletedProcess[str]:
            raise FileNotFoundError(argv[0])

        config = self.present_config("limits:\n  api: {}\n")
        with (
            mock.patch.object(gh, "LIMITS_CONFIG", config),
            mock.patch.object(gh, "_reader_run", no_bash),
            self.assertRaises(gh.RateLimitExhausted) as raised,
        ):
            gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertIn("fail closed", str(raised.exception))
        self.assertEqual(self.sent, [])

    def test_an_unreadable_schema_sends_nothing(self) -> None:
        with mock.patch.object(gh, "LIMITS_SCHEMA", REPO_ROOT / "no-such-schema.json"):
            with self.assertRaises(gh.RateLimitExhausted):
                gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertEqual(self.sent, [])


class TheProcessExitsRed(unittest.TestCase):
    def run_python(
        self, body: str, runner_temp: str = ""
    ) -> subprocess.CompletedProcess[str]:
        code = f"import sys; sys.path.insert(0, {str(SCRIPTS)!r})\n" + textwrap.dedent(
            body
        )
        env = {**os.environ, "RUNNER_TEMP": runner_temp}
        return subprocess.run(
            [sys.executable, "-c", code],
            capture_output=True,
            text=True,
            check=False,
            env=env,
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

    def test_a_later_process_sends_nothing_while_the_job_stop_holds(self) -> None:
        # One process per pull request (enable-auto-merge's reader): the
        # stop an earlier one recorded holds in the next, before any call.
        with tempfile.TemporaryDirectory() as temp:
            stop = pathlib.Path(temp, "api-budget", "stop")
            stop.parent.mkdir()
            stop.write_text("core 4102444800\n", encoding="utf-8")
            proc = self.run_python(
                """
                import babysit_gh as gh
                sent = []
                gh.run_command = lambda argv, **_: sent.append(argv)
                try:
                    gh.gh_capture(["api", "repos/o/r/pulls/1"])
                finally:
                    print(f"sent={len(sent)}", flush=True)
                """,
                runner_temp=temp,
            )
            self.assertEqual(stop.read_text(encoding="utf-8"), "core 4102444800\n")
        self.assertEqual(proc.returncode, 75, proc.stderr)
        self.assertIn("sent=0", proc.stdout)
        errors = [
            line for line in proc.stderr.splitlines() if line.startswith("::error")
        ]
        self.assertEqual(len(errors), 1, proc.stderr)
        self.assertIn("the core pool", errors[0])
        self.assertIn("2100-01-01T00:00:00Z", errors[0])


class TheJobStopFile(GuardCase):
    """The stop file rate-guard.mjs and api-budget.bash share: lines
    `<pool> <reset epoch>` in $RUNNER_TEMP/api-budget/stop."""

    def write_stops(self, text: str) -> None:
        self.stop_file.parent.mkdir(parents=True, exist_ok=True)
        self.stop_file.write_bytes(text.encode("utf-8"))

    def test_every_stop_file_vector_in_the_shared_file(self) -> None:
        table = json.loads(VECTORS.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(table["stop_files"]), 7)
        for vector in table["stop_files"]:
            with self.subTest(vector["name"]):
                gh.reset_rate_guard()
                self.write_stops(vector["text"])
                got = {
                    pool: gh.stopped_until(pool, now=table["vector_now"])
                    for pool in vector["until"]
                }
                self.assertEqual(got, vector["until"])

    def assert_unrecorded_stop_reported_and_latched(self) -> None:
        self.answer(
            1,
            head(403, **core(0))
            + '{"message":"API rate limit exceeded for user ID 1."}',
            "gh: API rate limit exceeded for user ID 1. (HTTP 403)",
        )
        with (
            mock.patch("sys.stderr", new_callable=io.StringIO) as err,
            self.assertRaises(gh.RateLimitExhausted),
        ):
            gh.gh_capture(["api", "repos/o/r/pulls/1"])
        unrecorded = [
            line for line in err.getvalue().splitlines() if "not be recorded" in line
        ]
        self.assertEqual(len(unrecorded), 1, err.getvalue())
        self.assertIn("the core pool", unrecorded[0])
        with self.assertRaises(gh.RateLimitExhausted):
            gh.gh_capture(["api", "repos/o/r/pulls/2"])
        self.assertEqual(len(self.sent), 1)

    def test_a_stop_the_file_cannot_take_is_reported_and_the_latch_holds(
        self,
    ) -> None:
        self.stop_file.mkdir(parents=True)
        self.assert_unrecorded_stop_reported_and_latched()

    def test_a_stop_dir_that_cannot_be_made_is_reported_and_the_latch_holds(
        self,
    ) -> None:
        self.stop_file.parent.write_text("", encoding="utf-8")
        self.assert_unrecorded_stop_reported_and_latched()

    def test_a_recorded_stop_refuses_its_pool_before_any_call(self) -> None:
        self.write_stops("core 4102444800\n")
        with self.assertRaises(gh.RateLimitExhausted) as raised:
            gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertEqual(
            (raised.exception.pool, raised.exception.reset), ("core", 4102444800)
        )
        self.assertEqual(self.sent, [])
        # Its refusal is no new stop: the file is unchanged.
        self.assertEqual(
            self.stop_file.read_text(encoding="utf-8"), "core 4102444800\n"
        )

    def test_a_recorded_stop_leaves_the_other_pools_open(self) -> None:
        self.write_stops("core 4102444800\n")
        self.answer(0, head(200) + "{}")
        gh.gh_capture(["api", "graphql", "-f", "query=query{viewer{login}}"])
        self.assertEqual(len(self.sent), 1)

    def test_a_recorded_secondary_stop_refuses_every_pool(self) -> None:
        self.write_stops("* 4102444800\n")
        for args in (
            ["api", "repos/o/r/pulls/1"],
            ["api", "graphql", "-f", "query=query{viewer{login}}"],
            ["pr", "view", "1", "--json", "number"],
        ):
            with self.assertRaises(gh.RateLimitExhausted):
                gh.gh_capture(args)
        self.assertEqual(self.sent, [])

    def test_a_past_stop_lets_the_call_go(self) -> None:
        self.write_stops("core 1000000000\n")
        self.answer(0, head(200, **core(4000)) + "{}")
        gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertEqual(len(self.sent), 1)

    def test_an_unreadable_stop_file_holds_no_stop(self) -> None:
        # As rate-guard.mjs readStops: a file that cannot be read is empty.
        self.stop_file.mkdir(parents=True)
        self.answer(0, head(200, **core(4000)) + "{}")
        gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertEqual(len(self.sent), 1)

    def test_a_latch_appends_its_stop_as_the_js_guard_writes_it(self) -> None:
        self.answer(
            1,
            head(403, **core(0))
            + '{"message":"API rate limit exceeded for user ID 1."}',
            "gh: API rate limit exceeded for user ID 1. (HTTP 403)",
        )
        with self.assertRaises(gh.RateLimitExhausted):
            gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertEqual(
            self.stop_file.read_text(encoding="utf-8"), "core 4102444800\n"
        )

    def test_a_secondary_latch_appends_a_stop_for_every_pool(self) -> None:
        self.write_stops("graphql 4102444800\n")
        self.answer(
            1,
            head(429, **core(4000, Retry_After="60"))
            + '{"message":"You have exceeded a secondary rate limit."}',
            "gh: You have exceeded a secondary rate limit. (HTTP 429)",
        )
        with (
            mock.patch.object(gh.time, "time", return_value=1792748000.5),
            self.assertRaises(gh.RateLimitExhausted),
        ):
            gh.gh_capture(["api", "repos/o/r/pulls/1"])
        self.assertEqual(
            self.stop_file.read_text(encoding="utf-8"),
            "graphql 4102444800\n* 1792748060\n",
        )

    def test_with_no_runner_temp_nothing_is_written_and_the_latch_still_holds(
        self,
    ) -> None:
        self.answer(0, head(200, **core(0)) + "{}")
        with mock.patch.dict(os.environ, {"RUNNER_TEMP": ""}):
            gh.gh_capture(["api", "repos/o/r/pulls/1"])
            with self.assertRaises(gh.RateLimitExhausted):
                gh.gh_capture(["api", "repos/o/r/pulls/2"])
        self.assertFalse(self.stop_file.parent.exists())
        self.assertEqual(len(self.sent), 1)


if __name__ == "__main__":
    unittest.main()

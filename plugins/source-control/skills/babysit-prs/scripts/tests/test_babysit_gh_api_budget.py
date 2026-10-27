"""Rate-limit readings from `babysit_gh._run_gh`'s own responses.

With API_BUDGET_TOKEN (or API_BUDGET_OVERRIDE_TOKEN for a call that carries
its own GH_TOKEN) and RUNNER_TEMP set, an `api` call runs with -i, each header
block becomes one reading line, and the caller gets the output it would have
had without -i. The line shape is .github/actions/log-api-budget/api-budget.bash's.
"""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_gh as gh

HEAD = (
    "HTTP/2.0 {status} OK\n"
    "Content-Type: application/json\r\n"
    "X-Ratelimit-Limit: 5000\r\n"
    "X-Ratelimit-Remaining: {remaining}\r\n"
    "X-Ratelimit-Reset: 1792748042\r\n"
    "X-Ratelimit-Resource: core\r\n"
    "X-Ratelimit-Used: {used}\r\n"
    "\r\n"
)


class ApiBudgetTests(unittest.TestCase):
    def setUp(self) -> None:
        gh.reset_rate_guard()
        self.addCleanup(gh.reset_rate_guard)
        self.dir = tempfile.mkdtemp()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", self.dir], check=False))
        self.calls: list[list[str]] = []

    def run_gh(
        self,
        stdout: str,
        args: list[str],
        *,
        env: dict[str, str],
        code: int = 0,
        stderr: str = "",
        check: bool = False,
        overrides: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[Any]:
        def fake(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.calls.append(argv)
            return subprocess.CompletedProcess(argv, code, stdout, stderr)

        with (
            mock.patch.dict(os.environ, env, clear=False),
            mock.patch.object(gh, "run_command", fake),
        ):
            return gh._run_gh(
                args, timeout_seconds=None, check=check, env_overrides=overrides
            )

    def readings(self, token: str) -> str:
        return pathlib.Path(self.dir, "api-budget", token).read_text(encoding="utf-8")

    def test_the_leading_header_block_becomes_a_reading_and_the_body_is_kept_byte_for_byte(
        self,
    ) -> None:
        # A body line shaped like a status line is body, never a second block.
        body = "keep1\nHTTP/1.1 200 x\nflagged()\n\nafter"
        env = {"RUNNER_TEMP": self.dir, "API_BUDGET_TOKEN": "lanes-app"}
        proc = self.run_gh(
            HEAD.format(status=200, remaining=4880, used=120) + body,
            ["api", "repos/o/r/contents/x", "-H", "Accept: application/vnd.github.raw"],
            env=env,
        )
        self.assertEqual(
            self.calls,
            [
                [
                    "gh",
                    "api",
                    "-i",
                    "repos/o/r/contents/x",
                    "-H",
                    "Accept: application/vnd.github.raw",
                ]
            ],
        )
        self.assertEqual(proc.stdout, body)
        self.assertEqual(
            self.readings("lanes-app"), "200 5000 4880 120 1792748042 core\n"
        )

    def test_a_failed_call_is_read_and_still_raises_as_without_headers(self) -> None:
        body = '{"message":"Not Found"}'
        env = {"RUNNER_TEMP": self.dir, "API_BUDGET_TOKEN": "github-token"}
        with self.assertRaises(RuntimeError) as raised:
            self.run_gh(
                HEAD.format(status=404, remaining=4000, used=1000) + body,
                ["api", "repos/o/r/pulls/1"],
                env=env,
                code=1,
                stderr="gh: Not Found (HTTP 404)\n",
                check=True,
            )
        self.assertEqual(
            str(raised.exception),
            "gh api repos/o/r/pulls/1 failed: gh: Not Found (HTTP 404)",
        )
        self.assertEqual(
            self.readings("github-token"), "404 5000 4000 1000 1792748042 core\n"
        )

    def test_a_rate_limited_call_is_read_before_the_latch_trips(self) -> None:
        body = '{"message":"API rate limit exceeded for installation."}'
        env = {"RUNNER_TEMP": self.dir, "API_BUDGET_TOKEN": "github-token"}
        with self.assertRaises(gh.RateLimitExhausted):
            self.run_gh(
                HEAD.format(status=403, remaining=0, used=5000) + body,
                ["api", "repos/o/r/pulls/1"],
                env=env,
                code=1,
                stderr="gh: API rate limit exceeded (HTTP 403)\n",
                check=True,
            )
        self.assertEqual(
            self.readings("github-token"), "403 5000 0 5000 1792748042 core\n"
        )

    def test_a_call_with_its_own_token_reads_into_the_override_name(self) -> None:
        env = {
            "RUNNER_TEMP": self.dir,
            "API_BUDGET_TOKEN": "lanes-app",
            "API_BUDGET_OVERRIDE_TOKEN": "github-token",
        }
        self.run_gh(
            HEAD.format(status=200, remaining=3, used=7) + "{}",
            ["api", "x"],
            env=env,
            overrides={"GH_TOKEN": "t"},
        )
        self.assertEqual(
            self.readings("github-token"), "200 5000 3 7 1792748042 core\n"
        )
        self.assertFalse(pathlib.Path(self.dir, "api-budget", "lanes-app").exists())

    def test_without_a_token_name_or_for_a_non_api_call_nothing_is_read(self) -> None:
        # Every `api` call but a paginated one still runs with -i, for the
        # guard, and a `--paginate --slurp` read goes page by page with -i
        # (`_run_pages`); only a named token writes a reading.
        self.run_gh(
            "{}", ["api", "x"], env={"RUNNER_TEMP": self.dir, "API_BUDGET_TOKEN": ""}
        )
        self.run_gh(
            "{}",
            ["pr", "view", "1"],
            env={"RUNNER_TEMP": self.dir, "API_BUDGET_TOKEN": "lanes-app"},
        )
        self.run_gh(
            "{}",
            ["api", "x", "--slurp", "--paginate"],
            env={"RUNNER_TEMP": self.dir, "API_BUDGET_TOKEN": "lanes-app"},
        )
        self.run_gh(
            "[]",
            ["api", "x", "--paginate", "--jq", "."],
            env={"RUNNER_TEMP": self.dir, "API_BUDGET_TOKEN": "lanes-app"},
        )
        self.assertEqual(
            self.calls,
            [
                ["gh", "api", "-i", "x"],
                ["gh", "pr", "view", "1"],
                ["gh", "api", "-i", "x"],
                ["gh", "api", "x", "--paginate", "--jq", "."],
            ],
        )
        self.run_gh(
            "{}",
            ["api", "rate_limit"],
            env={"RUNNER_TEMP": self.dir, "API_BUDGET_TOKEN": "lanes-app"},
        )
        self.assertEqual(self.calls[-1], ["gh", "api", "rate_limit"])
        self.assertFalse(pathlib.Path(self.dir, "api-budget").exists())


if __name__ == "__main__":
    unittest.main()

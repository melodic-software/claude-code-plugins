# test-scope: plugins/source-control/lib/parse-concern-value.sh
"""Rate-limit readings from `babysit_gh._run_gh`'s own responses.

With API_BUDGET_TOKEN (or API_BUDGET_OVERRIDE_TOKEN for a call that carries
its own GH_TOKEN) and RUNNER_TEMP set, an `api` call runs with -i, each header
block becomes one reading line, and the caller gets the output it would have
had without -i. The line shape is .github/actions/log-api-budget/api-budget.bash's.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
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
            self.readings("lanes-app"),
            "200 5000 4880 120 1792748042 core repos/{repo}/contents/{x}\n",
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
            self.readings("github-token"),
            "404 5000 4000 1000 1792748042 core repos/{repo}/pulls/{n}\n",
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
            self.readings("github-token"),
            "403 5000 0 5000 1792748042 core repos/{repo}/pulls/{n}\n",
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
            self.readings("github-token"), "200 5000 3 7 1792748042 core {x}\n"
        )
        self.assertFalse(pathlib.Path(self.dir, "api-budget", "lanes-app").exists())

    def test_without_a_token_name_or_for_a_non_api_call_no_reading_is_written(
        self,
    ) -> None:
        # Every `api` call but a paginated one still runs with -i, for the
        # guard, and a `--paginate --slurp` read goes page by page with -i
        # (`_run_pages`); only a named token writes a reading. A non-api call
        # writes `request` lines only for the trace its stderr carries, none here.
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

    def test_a_call_without_a_header_block_counts_each_api_request_it_traces(
        self,
    ) -> None:
        # api-budget.bash's api_budget_traced: GH_DEBUG=1 head lines become
        # `request <route>` lines, a redirect to a download host is not one,
        # and stderr comes back without what the debug level added.
        trace = (
            "* Request at 2026-11-04 04:00:00\n"
            "* Request to https://api.github.com/repos/o/r/actions/runs/7/artifacts?per_page=100\n"
            "* Request took 80ms\n"
            "* Request at 2026-11-04 04:00:01\n"
            "* Request to https://api.github.com/repos/o/r/actions/artifacts/9/zip\n"
            "* Request took 90ms\n"
            "* Request at 2026-11-04 04:00:02\n"
            "* Request to https://productionresultssa1.blob.core.windows.net/x\n"
            "* Request took 30ms\n"
            "[git remote -v]\n"
            "error connecting to api.github.com\n"
            "lookup api.github.com: no such host\n"
            "real error\n"
        )
        seen: list[dict[str, Any]] = []

        def fake(argv: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
            seen.append({"argv": argv, "env": kwargs.get("env_overrides")})
            return subprocess.CompletedProcess(argv, 1, "", trace)

        env = {"RUNNER_TEMP": self.dir, "API_BUDGET_TOKEN": "github-token"}
        with (
            mock.patch.dict(os.environ, env, clear=False),
            mock.patch.object(gh, "run_command", fake),
        ):
            proc = gh._run_gh(
                ["run", "download", "7", "-n", "a"], timeout_seconds=None, check=False
            )
            binary = gh._run_gh(
                ["api", "repos/o/r/actions/artifacts/9/zip"],
                timeout_seconds=None,
                check=False,
                binary=True,
            )
        self.assertEqual(seen[0]["env"], {"GH_DEBUG": "1"})
        self.assertEqual(
            seen[1]["argv"], ["gh", "api", "repos/o/r/actions/artifacts/9/zip"]
        )
        self.assertEqual(
            proc.stderr, "error connecting to api.github.com\nreal error\n"
        )
        self.assertEqual(binary.stderr, proc.stderr)
        self.assertEqual(
            self.readings("github-token"),
            (
                "request repos/{repo}/actions/runs/{n}/artifacts\n"
                "request repos/{repo}/actions/artifacts/{n}/{x}\n"
            )
            * 2,
        )

    def test_without_a_token_name_a_header_less_call_runs_untraced(self) -> None:
        seen: list[Any] = []

        def fake(argv: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
            seen.append(kwargs.get("env_overrides"))
            return subprocess.CompletedProcess(
                argv, 0, "", "* Request to https://api.github.com/x\n"
            )

        with (
            mock.patch.dict(
                os.environ,
                {"RUNNER_TEMP": self.dir, "API_BUDGET_TOKEN": ""},
                clear=False,
            ),
            mock.patch.object(gh, "run_command", fake),
        ):
            proc = gh._run_gh(["pr", "view", "1"], timeout_seconds=None, check=False)
        self.assertEqual(seen, [None])
        self.assertEqual(proc.stderr, "* Request to https://api.github.com/x\n")
        self.assertFalse(pathlib.Path(self.dir, "api-budget").exists())

    def test_each_page_of_a_paged_read_is_a_reading_under_its_route(self) -> None:
        env = {"RUNNER_TEMP": self.dir, "API_BUDGET_TOKEN": "github-token"}
        page = HEAD.format(status=200, remaining=9, used=1).replace(
            "\r\n\r\n",
            '\r\nLink: <https://api.github.com/repositories/1/pulls?page=2>; rel="next"\r\n\r\n',
        )
        pages = iter(
            [page + "[1]", HEAD.format(status=200, remaining=8, used=2) + "[2]"]
        )

        def fake(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.calls.append(argv)
            return subprocess.CompletedProcess(argv, 0, next(pages), "")

        with (
            mock.patch.dict(os.environ, env, clear=False),
            mock.patch.object(gh, "run_command", fake),
        ):
            gh._run_gh(
                ["api", "repos/o/r/pulls?state=open", "--paginate", "--slurp"],
                timeout_seconds=None,
                check=True,
            )
        self.assertEqual(
            self.readings("github-token"),
            "200 5000 9 1 1792748042 core repos/{repo}/pulls\n"
            "200 5000 8 2 1792748042 core repositories/{n}/pulls\n",
        )


VECTORS = json.loads(
    (
        pathlib.Path(__file__).resolve().parents[6]
        / ".github"
        / "actions"
        / "log-api-budget"
        / "rate-guard.vectors.json"
    ).read_text(encoding="utf-8")
)
RATE_GUARD = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github"
    / "actions"
    / "log-api-budget"
    / "rate-guard.mjs"
).read_text(encoding="utf-8")


class ApiRouteTests(unittest.TestCase):
    def test_api_route_templates_each_shared_vector_as_route_of_does(self) -> None:
        self.assertGreaterEqual(len(VECTORS["routes"]), 30)
        for vector in VECTORS["routes"]:
            with self.subTest(url=vector["url"]):
                route = gh.api_route(vector["url"])
                self.assertEqual(route, vector["route"])
                for name in vector["absent"]:
                    self.assertNotIn(name, route)

    def test_the_route_words_are_rate_guard_mjs_rest_path_words(self) -> None:
        match = re.search(
            r'REST_PATH_WORDS = new Set\(\s*"([^"]+)"\.split\(" "\)', RATE_GUARD
        )
        assert match is not None
        self.assertEqual(gh.REST_PATH_WORDS, frozenset(match[1].split(" ")))


if __name__ == "__main__":
    unittest.main()

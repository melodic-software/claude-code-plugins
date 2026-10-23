"""The per-process gh call counter in `babysit_gh._run_gh`.

The method rule comes from `gh api --help`: GET by default, POST once a
parameter or `--input` is given, `-X/--method` overriding both. The route
template keeps only known route words and replaces every other segment with
`{}`, so the log carries no
identifier or branch name.
"""

from __future__ import annotations

import json
import re
import pathlib
import subprocess
import sys
import textwrap
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_gh as gh

SCRIPTS = pathlib.Path(gh.__file__).resolve().parent


def _ok(*_args: Any, **_kwargs: Any) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess(["gh"], 0, "{}", "")


class GhCallKindTests(unittest.TestCase):
    def kind(self, *args: str, env: dict[str, str] | None = None) -> str:
        return gh.gh_call_kind(list(args), env)

    def test_a_rest_read_is_get_with_owner_repo_and_ids_templated(self) -> None:
        self.assertEqual(
            self.kind("api", "repos/acme/widgets/actions/runs/123/attempts/2"),
            "default GET repos/{}/{}/actions/runs/{}/attempts/{}",
        )

    def test_the_query_string_and_flag_values_are_dropped(self) -> None:
        self.assertEqual(
            self.kind(
                "api",
                "repos/acme/widgets/actions/workflows/pr-review.yml/runs"
                "?branch=feat%2Fsecret&per_page=100",
                "--paginate",
                "--slurp",
                "--jq",
                ".workflow_runs",
            ),
            "default GET repos/{}/{}/actions/workflows/{}/runs+paginate",
        )

    def test_a_branch_a_contents_path_and_a_compare_range_are_templated(
        self,
    ) -> None:
        self.assertEqual(
            self.kind("api", "repos/acme/widgets/rules/branches/feature-x"),
            "default GET repos/{}/{}/rules/branches/{}",
        )
        self.assertEqual(
            self.kind("api", "repos/acme/widgets/contents/docs/private-notes.md"),
            "default GET repos/{}/{}/contents/{}",
        )
        self.assertEqual(
            self.kind("api", "repos/acme/widgets/compare/main...abc123"),
            "default GET repos/{}/{}/compare/{}",
        )

    def test_an_owner_that_looks_like_a_route_word_is_templated(self) -> None:
        self.assertEqual(
            self.kind("api", "orgs/melodic-software/repos?per_page=100", "--paginate"),
            "default GET orgs/{}/repos+paginate",
        )
        self.assertEqual(
            self.kind("api", "users/kyle-sexton/repos?per_page=100"),
            "default GET users/{}/repos",
        )
        self.assertEqual(
            self.kind("api", "repos/melodic-software/claude-code-plugins/pulls"),
            "default GET repos/{}/{}/pulls",
        )

    def test_a_branch_after_heads_or_commits_is_templated_whatever_it_spells(
        self,
    ) -> None:
        self.assertEqual(
            self.kind("api", "repos/acme/widgets/git/ref/heads/secretfeature"),
            "default GET repos/{}/{}/git/ref/heads/{}",
        )
        self.assertEqual(
            self.kind("api", "repos/acme/widgets/git/ref/heads/release/hotfix-login"),
            "default GET repos/{}/{}/git/ref/heads/{}",
        )
        self.assertEqual(
            self.kind("api", "repos/acme/widgets/commits/secret-feature"),
            "default GET repos/{}/{}/commits/{}",
        )
        self.assertEqual(
            self.kind("api", "repos/acme/widgets/commits/status/status"),
            "default GET repos/{}/{}/commits/{}/status",
        )

    def test_a_segment_outside_the_route_words_is_templated(self) -> None:
        self.assertEqual(
            self.kind("api", "repos/acme/widgets/issues/7/labels/needs-review"),
            "default GET repos/{}/{}/issues/{}/labels/{}",
        )

    def test_a_field_makes_it_post_and_an_explicit_method_wins(self) -> None:
        self.assertEqual(
            self.kind("api", "repos/acme/widgets/issues/7/labels", "-f", "labels[]=x"),
            "default POST repos/{}/{}/issues/{}/labels",
        )
        self.assertEqual(
            self.kind("api", "-X", "PUT", "repos/acme/widgets/pulls/7/update-branch"),
            "default PUT repos/{}/{}/pulls/{}/update-branch",
        )
        self.assertEqual(
            self.kind(
                "api", "--method=get", "repos/acme/widgets/issues", "-f", "state=open"
            ),
            "default GET repos/{}/{}/issues",
        )

    def test_graphql_and_other_subcommands_have_their_own_kinds(self) -> None:
        self.assertEqual(
            self.kind("api", "graphql", "-f", "query={ viewer { login } }"),
            "default graphql",
        )
        self.assertEqual(
            self.kind("pr", "view", "7", "--repo", "acme/widgets", "--json", "title"),
            "default gh pr view",
        )

    def test_a_call_with_its_own_token_is_counted_apart(self) -> None:
        self.assertEqual(
            self.kind("api", "user", env={"GH_TOKEN": "x"}), "override GET user"
        )
        self.assertEqual(
            self.kind("api", "user", env={"LC_ALL": "C"}), "default GET user"
        )


class ScriptRoutesTests(unittest.TestCase):
    """Every REST route literal the scripts build, with each `{...}` value
    filled by a word-shaped sentinel, logs no sentinel and only route words."""

    SENTINEL = "leakvalue"
    ROUTE_RE = re.compile(r'f?"((?:repos|orgs|users)/[^"?]*)')

    def routes(self) -> list[str]:
        found = set()
        for path in SCRIPTS.glob("*.py"):
            for match in self.ROUTE_RE.finditer(path.read_text(encoding="utf-8")):
                route = match.group(1)
                # A single `{repo}` after `repos/` holds owner and name.
                route = re.sub(r"^repos/\{[^{}]+\}(?=/(?!\{)|$)", "repos/x/x", route)
                found.add(re.sub(r"\{[^{}]*\}", self.SENTINEL, route))
        return sorted(found)

    def test_every_built_route_maps_to_route_words_and_values(self) -> None:
        routes = self.routes()
        self.assertGreater(len(routes), 50)
        for route in routes:
            with self.subTest(route):
                kind = gh.gh_call_kind(["api", route], None)
                self.assertNotIn(self.SENTINEL, kind)
                path = kind.split(" ")[2]
                self.assertLessEqual(
                    set(path.split("/")) - {"{}"}, set(gh._ROUTE_WORDS), kind
                )


class GhCallCounterTests(unittest.TestCase):
    def setUp(self) -> None:
        gh.reset_gh_call_counts()
        self.addCleanup(gh.reset_gh_call_counts)

    def test_each_invocation_is_counted_by_kind(self) -> None:
        with mock.patch.object(gh, "run_command", side_effect=_ok):
            gh.gh_json(["api", "repos/acme/widgets/pulls/1"])
            gh.gh_json(["api", "repos/acme/widgets/pulls/2"])
            gh.run_gh(["api", "graphql", "-f", "query=q"])
        self.assertEqual(
            gh.gh_call_counts(),
            {"default GET repos/{}/{}/pulls/{}": 2, "default graphql": 1},
        )

    def test_a_failed_call_is_still_counted(self) -> None:
        with (
            mock.patch.object(gh, "run_command", side_effect=RuntimeError("timeout")),
            self.assertRaises(RuntimeError),
        ):
            gh.run_gh(["api", "user"])
        self.assertEqual(gh.gh_call_counts(), {"default GET user": 1})

    def test_no_call_means_no_summary(self) -> None:
        self.assertIsNone(gh.gh_call_summary())


class GhCallSummaryProcessTests(unittest.TestCase):
    """A real process: the summary goes to stderr on exit and stdout stays
    the script's own output, which the gate step parses as JSON."""

    def run_script(self, body: str) -> subprocess.CompletedProcess[str]:
        code = textwrap.dedent(
            f"""
            import subprocess, sys
            sys.path.insert(0, {str(SCRIPTS)!r})
            import babysit_gh as gh
            gh.run_command = lambda *a, **k: subprocess.CompletedProcess(
                ["gh"], 0, "{{}}", ""
            )
            """
        ) + textwrap.dedent(body)
        return subprocess.run(
            [sys.executable, "-c", code],
            capture_output=True,
            text=True,
            check=True,
            timeout=60,
        )

    def test_the_counts_print_to_stderr_once_on_exit(self) -> None:
        proc = self.run_script(
            """
            gh.gh_json(["api", "repos/acme/widgets/pulls/9"])
            gh.gh_json(["api", "repos/acme/widgets/pulls/9"], {"GH_TOKEN": "t"})
            print('{"ready": true}')
            """
        )
        self.assertEqual(proc.stdout, '{"ready": true}\n')
        lines = proc.stderr.splitlines()
        self.assertEqual(len(lines), 1)
        prefix, _, payload = lines[0].partition(" ")
        self.assertEqual(prefix, "babysit-gh-calls")
        self.assertEqual(
            json.loads(payload)["calls"],
            {
                "default GET repos/{}/{}/pulls/{}": 1,
                "override GET repos/{}/{}/pulls/{}": 1,
            },
        )
        self.assertEqual(json.loads(payload)["total"], 2)

    def test_a_process_with_no_gh_call_prints_nothing(self) -> None:
        proc = self.run_script("print('done')\n")
        self.assertEqual((proc.stdout, proc.stderr), ("done\n", ""))


if __name__ == "__main__":
    unittest.main()

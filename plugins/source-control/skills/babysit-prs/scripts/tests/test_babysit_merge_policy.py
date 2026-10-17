"""The unattended merge policy readers.

Every reader fails closed: an unreadable answer is off, refuse or not clear,
never permissive. Each expected value below comes from the plan's Design
(threads T3, T4, T5, T8, T9, T10, T12, T13, T15, the "Human" definition, and
rows D6, D20, D23) or, for bash resolution, from `lib/exec-bash.mjs`'s
documented Windows rules. GitHub is stubbed at the one gh seam
(`babysit_gh.gh_capture`, imported into the policy module); the YAML reader is
the real shared copy run through bash.
"""

from __future__ import annotations

import base64
import contextlib
import json
import os
import pathlib
import shutil
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

import babysit_merge_policy as policy  # noqa: E402  (follows the git-env clear above)

REPO = "owner/repo"
SHA = "a" * 40
IDENTITY = "agent-lanes[bot]"
POLICY = ".github/standards/dependabot-policy/policy.json"
OPERATOR = "operator"
PR_CREATED = "2026-10-12T12:00:00Z"
DEMOTION_BODY = (
    "<!-- babysit-merge-demotion sha=" + "b" * 40 + " signal=dispatch -->\nPR #5"
)

PIPELINE = """\
merge:
  rung: C2
  authority: local-babysit
  agent-identity: agent-lanes[bot]
  diff-check:
    denied-paths: [".github/**", "docs/conventions/pr-pipeline.yaml"]
    max-changed-lines: 200
"""
SOURCE_CONTROL = "## babysit_loop_merge\n\nc2-mechanical\n"


def ok(payload: Any) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess([], 0, json.dumps(payload), "")


def http_error(status: int) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess([], 1, "", f"gh: request failed (HTTP {status})")


def file_payload(text: str) -> dict[str, Any]:
    return {
        "type": "file",
        "encoding": "base64",
        "content": base64.encodebytes(text.encode()).decode(),
    }


class GhFake:
    """A gh seam answering REST endpoints and named GraphQL operations.

    `rest` maps an endpoint to a payload, or to an int HTTP status for a
    failure. `graphql` maps an operation name to a payload or to a callable of
    the query's string variables. Any other call fails the test.
    """

    def __init__(self) -> None:
        self.rest: dict[str, Any] = {}
        self.graphql: dict[str, Any] = {}
        self.calls: list[list[str]] = []

    def __call__(self, args: list[str], **_: Any) -> subprocess.CompletedProcess[str]:
        self.calls.append(args)
        if args[:2] == ["api", "graphql"]:
            query = next(a for a in args if a.startswith("query="))
            variables = dict(
                a.split("=", 1)
                for a in args[2:]
                if a not in ("-f", "-F") and not a.startswith("query=")
            )
            for name, answer in self.graphql.items():
                if f"query {name}" in query:
                    if isinstance(answer, int):
                        return http_error(answer)
                    return ok(
                        {"data": answer(variables) if callable(answer) else answer}
                    )
            raise AssertionError(f"unexpected graphql call: {query[:80]}")
        endpoint = args[1]
        if endpoint not in self.rest:
            raise AssertionError(f"unexpected gh call: {args}")
        answer = self.rest[endpoint]
        if isinstance(answer, int):
            return http_error(answer)
        return ok([answer] if "--paginate" in args else answer)

    def install(self, case: unittest.TestCase) -> GhFake:
        patcher = mock.patch.object(policy, "gh_capture", self)
        patcher.start()
        case.addCleanup(patcher.stop)
        return self


def permissions(table: dict[str, str]) -> Any:
    return lambda login: table.get(login)


HUMANS = permissions({OPERATOR: "admin", "maintainer": "write", "reader": "read"})


def user(login: str) -> dict[str, str]:
    return {"__typename": "User", "login": login}


def bot(login: str) -> dict[str, str]:
    return {"__typename": "Bot", "login": login}


class ResolveBash(unittest.TestCase):
    """`lib/exec-bash.mjs`'s candidate order and refusals, ported to Python."""

    def resolve(
        self, env: dict[str, str], files: set[str], platform: str = "win32"
    ) -> Any:
        return policy.resolve_bash(env, platform, files.__contains__)

    def test_system32_first_on_path_is_skipped_for_the_next_bash(self) -> None:
        env = {"PATH": r"C:\Windows\System32;D:\tools\git\bin"}
        files = {r"C:\Windows\System32\bash.exe", r"D:\tools\git\bin\bash.exe"}
        self.assertEqual(self.resolve(env, files), r"D:\tools\git\bin\bash.exe")

    def test_system32_alone_resolves_nothing(self) -> None:
        env = {"PATH": r"C:\Windows\System32"}
        self.assertIsNone(self.resolve(env, {r"C:\Windows\System32\bash.exe"}))

    def test_sysnative_and_windowsapps_are_refused(self) -> None:
        env = {
            "PATH": r"C:\Windows\Sysnative;C:\Users\<user>\AppData\Local\Microsoft\WindowsApps"
        }
        files = {
            r"C:\Windows\Sysnative\bash.exe",
            r"C:\Users\<user>\AppData\Local\Microsoft\WindowsApps\bash.exe",
        }
        self.assertIsNone(self.resolve(env, files))

    def test_git_bash_path_variable_wins_when_named_bash(self) -> None:
        env = {
            "CLAUDE_CODE_GIT_BASH_PATH": r"E:\git\bin\bash.exe",
            "ProgramFiles": r"C:\Program Files",
        }
        files = {r"E:\git\bin\bash.exe", r"C:\Program Files\Git\bin\bash.exe"}
        self.assertEqual(self.resolve(env, files), r"E:\git\bin\bash.exe")

    def test_git_bash_path_variable_with_another_name_is_ignored(self) -> None:
        env = {"CLAUDE_CODE_GIT_BASH_PATH": r"E:\tools\wsl.exe", "PATH": r"D:\b"}
        files = {r"E:\tools\wsl.exe", r"D:\b\bash.exe"}
        self.assertEqual(self.resolve(env, files), r"D:\b\bash.exe")

    def test_git_bash_path_variable_naming_system32_is_refused(self) -> None:
        env = {"CLAUDE_CODE_GIT_BASH_PATH": r"C:\Windows\System32\bash.exe"}
        self.assertIsNone(self.resolve(env, {r"C:\Windows\System32\bash.exe"}))

    def test_program_files_git_comes_before_path(self) -> None:
        env = {"ProgramFiles": r"C:\Program Files", "PATH": r"D:\b"}
        files = {r"C:\Program Files\Git\usr\bin\bash.exe", r"D:\b\bash.exe"}
        self.assertEqual(
            self.resolve(env, files), r"C:\Program Files\Git\usr\bin\bash.exe"
        )

    def test_relative_and_quoted_path_entries(self) -> None:
        env = {"PATH": r'tools;"D:\quoted dir"'}
        files = {r"tools\bash.exe", r"D:\quoted dir\bash.exe"}
        self.assertEqual(self.resolve(env, files), r"D:\quoted dir\bash.exe")

    def test_posix_takes_path_then_bin(self) -> None:
        self.assertEqual(
            self.resolve({"PATH": "rel:/opt/b"}, {"/opt/b/bash", "/bin/bash"}, "linux"),
            "/opt/b/bash",
        )
        self.assertEqual(
            self.resolve({"PATH": ""}, {"/bin/bash"}, "linux"), "/bin/bash"
        )


def config_fake(
    case: unittest.TestCase,
    pipeline: str | int | None,
    source: str | int | None = SOURCE_CONTROL,
) -> GhFake:
    """Contents reads at SHA: text, an HTTP status, or None for an absent file."""
    gh = GhFake().install(case)
    gh.rest[f"repos/{REPO}/contents?ref={SHA}"] = []
    for path, value in (
        (policy.CONFIG_PATH, pipeline),
        (policy.SOURCE_CONTROL_PATH, source),
    ):
        endpoint = f"repos/{REPO}/contents/{path}?ref={SHA}"
        gh.rest[endpoint] = (
            404
            if value is None
            else (value if isinstance(value, int) else file_payload(value))
        )
    return gh


class ReadConfigAt(unittest.TestCase):
    def test_reads_the_merge_block_at_the_base_sha(self) -> None:
        gh = config_fake(self, PIPELINE)
        config = policy.read_config_at(REPO, SHA)
        self.assertEqual(config.rung, "C2")
        self.assertEqual(config.authority, "local-babysit")
        self.assertEqual(config.agent_identity, IDENTITY)
        self.assertEqual(config.max_changed_lines, 200)
        self.assertEqual(
            config.denied_paths, (".github/**", "docs/conventions/pr-pipeline.yaml")
        )
        self.assertEqual(config.loop_merge, "c2-mechanical")
        self.assertIsNone(config.error)
        self.assertIn(
            ["api", f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={SHA}"], gh.calls
        )

    def test_a_parse_error_is_off(self) -> None:
        config_fake(self, "merge:\n  rung: [C2\n")
        config = policy.read_config_at(REPO, SHA)
        self.assertEqual(config.rung, "off")
        self.assertEqual(config.error, "config-parse-error")
        self.assertIsNone(config.agent_identity)

    def test_an_absent_file_is_rung_off_and_no_authority(self) -> None:
        config_fake(self, None)
        config = policy.read_config_at(REPO, SHA)
        self.assertEqual(
            (config.rung, config.authority, config.error), ("off", None, None)
        )

    def test_an_unknown_rung_is_off(self) -> None:
        config_fake(self, "merge:\n  rung: C4\n")
        self.assertEqual(policy.read_config_at(REPO, SHA).rung, "off")

    def test_a_value_with_a_line_separator_is_a_parse_error(self) -> None:
        for char in ("\u0085", "\u2028", "\x0b", "\x1c"):
            with self.subTest(char=repr(char)):
                config_fake(
                    self, f'merge:\n  rung: C2\n  authority: "pr-merge{char}x"\n'
                )
                config = policy.read_config_at(REPO, SHA)
                self.assertEqual(
                    (config.rung, config.error), ("off", "config-parse-error")
                )

    def test_a_max_changed_lines_that_is_not_a_count_is_off(self) -> None:
        for value in ("lots", "²", "-5"):
            with self.subTest(value=value):
                text = f"merge:\n  rung: C2\n  diff-check:\n    max-changed-lines: {value}\n"
                config_fake(self, text)
                config = policy.read_config_at(REPO, SHA)
                self.assertEqual((config.rung, config.max_changed_lines), ("off", None))
                self.assertTrue(config.notes)

    def test_a_hidden_file_raises(self) -> None:
        gh = config_fake(self, None)
        gh.rest[f"repos/{REPO}/contents?ref={SHA}"] = 404
        with self.assertRaises(policy.PolicyReadError):
            policy.read_config_at(REPO, SHA)

    def test_a_failed_read_raises(self) -> None:
        config_fake(self, 502)
        with self.assertRaises(policy.PolicyReadError):
            policy.read_config_at(REPO, SHA)

    def test_a_sha_that_is_not_forty_hex_raises_before_any_call(self) -> None:
        gh = config_fake(self, PIPELINE)
        with self.assertRaises(policy.PolicyReadError):
            policy.read_config_at(REPO, "main")
        self.assertEqual(gh.calls, [])

    def test_a_malformed_source_control_file_leaves_loop_merge_unknown(self) -> None:
        duplicate = SOURCE_CONTROL + "\n## babysit_loop_merge\n\nfull-autonomy\n"
        config_fake(self, PIPELINE, duplicate)
        self.assertIsNone(policy.read_config_at(REPO, SHA).loop_merge)


class EffectiveRung(unittest.TestCase):
    def rung(self, **overrides: Any) -> Any:
        inputs = {
            "config_rung": "C3",
            "loop_merge": "c3-autonomous",
            "cap": None,
            "demoted": False,
        } | overrides
        return policy.effective_rung(**inputs)

    def test_the_minimum_of_four_inputs(self) -> None:
        self.assertEqual(self.rung().rung, "C3")
        self.assertEqual(self.rung(loop_merge="c2-mechanical").rung, "C2")
        self.assertEqual(self.rung(cap="C2").rung, "C2")
        self.assertEqual(self.rung(config_rung="C2").rung, "C2")
        self.assertEqual(self.rung(demoted=True).rung, "off")

    def test_full_autonomy_maps_no_higher_than_c3(self) -> None:
        self.assertEqual(self.rung(loop_merge="full-autonomy").rung, "C3")

    def test_unknown_inputs_are_off(self) -> None:
        for overrides in (
            {"config_rung": "C4"},
            {"loop_merge": None},
            {"loop_merge": "c3-this-run"},
            {"cap": "C5"},
            {"loop_merge": "human-only"},
        ):
            with self.subTest(overrides):
                self.assertEqual(self.rung(**overrides).rung, "off")

    def test_names_the_input_that_holds_it_off(self) -> None:
        self.assertEqual(self.rung(cap="off").limited_by, "rungCap")


class KillSwitch(unittest.TestCase):
    VARS = f"repos/{REPO}/actions/variables"

    def fake(
        self, org: str | None = "false", repo: Any = "false", shadow: Any = 404
    ) -> GhFake:
        gh = GhFake().install(self)
        gh.rest[f"{self.VARS}?per_page=1"] = {"total_count": 0, "variables": []}
        org_vars = [{"name": "CLAUDE_REVIEW_DISABLED", "value": "false"}]
        if org is not None:
            org_vars.append({"name": "CLAUDE_LANES_DISABLED", "value": org})
        gh.rest[f"repos/{REPO}/actions/organization-variables?per_page=100"] = {
            "total_count": len(org_vars),
            "variables": org_vars,
        }
        gh.rest[f"{self.VARS}/CLAUDE_LANES_REPO_DISABLED"] = (
            repo
            if isinstance(repo, int)
            else {"name": "CLAUDE_LANES_REPO_DISABLED", "value": repo}
        )
        gh.rest[f"{self.VARS}/CLAUDE_LANES_DISABLED"] = (
            shadow
            if isinstance(shadow, int)
            else {"name": "CLAUDE_LANES_DISABLED", "value": shadow}
        )
        return gh

    def test_both_exactly_false_and_no_shadow_proceeds(self) -> None:
        self.fake()
        self.assertTrue(policy.read_kill_switch(REPO).proceed)

    def test_every_other_state_refuses(self) -> None:
        cases = {
            "org true": {"org": "true"},
            "org absent": {"org": None},
            "org False": {"org": "False"},
            "repo true": {"repo": "true"},
            "repo absent": {"repo": 404},
            "repo unreadable": {"repo": 500},
            "shadow present": {"shadow": "false"},
            "shadow unreadable": {"shadow": 403},
        }
        for name, overrides in cases.items():
            with self.subTest(name):
                self.fake(**overrides)
                self.assertFalse(policy.read_kill_switch(REPO).proceed)

    def test_an_unreadable_variables_surface_refuses(self) -> None:
        gh = self.fake()
        gh.rest[f"{self.VARS}?per_page=1"] = 403
        self.assertFalse(policy.read_kill_switch(REPO).proceed)


class RungCap(unittest.TestCase):
    VARS = f"repos/{REPO}/actions/variables"

    def cap(self, listing: Any, value: Any) -> Any:
        gh = GhFake().install(self)
        gh.rest[f"{self.VARS}?per_page=1"] = listing
        gh.rest[f"{self.VARS}/CLAUDE_LANES_MERGE_RUNG_CAP"] = (
            value if isinstance(value, int) else {"name": "x", "value": value}
        )
        return policy.read_rung_cap(REPO).value

    def test_404_after_a_readable_listing_is_no_cap(self) -> None:
        self.assertIsNone(self.cap({"variables": []}, 404))

    def test_404_with_an_unreadable_listing_is_off(self) -> None:
        self.assertEqual(self.cap(403, 404), "off")

    def test_a_set_value_caps_and_an_unknown_value_is_off(self) -> None:
        self.assertEqual(self.cap({"variables": []}, "C2"), "C2")
        self.assertEqual(self.cap({"variables": []}, "C4"), "off")
        self.assertEqual(self.cap({"variables": []}, 500), "off")


class IsHuman(unittest.TestCase):
    def human(self, actor: Any, identity: str | None = IDENTITY, **kw: Any) -> bool:
        return policy.is_human(
            actor, repo=REPO, agent_identity=identity, permission=HUMANS, **kw
        )

    def test_a_user_with_write_or_admin_is_human(self) -> None:
        self.assertTrue(self.human(user(OPERATOR)))
        self.assertTrue(self.human(user("maintainer")))

    def test_a_user_below_write_is_not(self) -> None:
        self.assertFalse(self.human(user("reader")))
        self.assertFalse(self.human(user("stranger")))

    def test_a_null_actor_is_not(self) -> None:
        self.assertFalse(self.human(None))

    def test_the_configured_identity_as_a_user_is_not(self) -> None:
        # A machine-user identity is a `User` with write; it must still fail.
        identity_table = permissions({"agent-lanes": "admin", "machine-user": "write"})
        for identity, actor in (
            (IDENTITY, user("agent-lanes")),
            ("machine-user", user("machine-user")),
            ("Machine-User", user("machine-user")),
        ):
            with self.subTest(identity):
                self.assertFalse(
                    policy.is_human(
                        actor,
                        repo=REPO,
                        agent_identity=identity,
                        permission=identity_table,
                    )
                )

    def test_bots_and_automation_logins_are_not(self) -> None:
        self.assertFalse(self.human(bot("renovate")))
        self.assertFalse(self.human(user("github-actions")))
        self.assertFalse(self.human(user("some-app[bot]")))
        self.assertFalse(
            self.human(user(OPERATOR), self_logins=frozenset({"Operator"}))
        )

    def test_an_unreadable_permission_is_not(self) -> None:
        def broken(login: str) -> str:
            raise policy.PolicyReadError("permission read failed")

        self.assertFalse(
            policy.is_human(
                user(OPERATOR), repo=REPO, agent_identity=IDENTITY, permission=broken
            )
        )


def demotion_fake(case: unittest.TestCase, **issue: Any) -> GhFake:
    """One demotion record, #9, filed by the identity, with `issue` overrides."""
    record = {
        "number": 9,
        "state": "CLOSED",
        "body": DEMOTION_BODY,
        "createdAt": "2026-10-12T10:00:00Z",
        "author": bot("agent-lanes"),
        "userContentEdits": {"totalCount": 0, "nodes": []},
        "timelineItems": {
            "nodes": [
                {
                    "createdAt": "2026-10-12T12:00:00Z",
                    "actor": user(OPERATOR),
                    "closer": None,
                }
            ]
        },
    } | issue
    gh = GhFake().install(case)

    def by_author(variables: dict[str, str]) -> dict[str, Any]:
        nodes = []
        # Shape per GitHub's GraphQL createdBy filter, which matches the [bot]
        # login: probed, "github-actions[bot]" returned this repository's issues
        # and "github-actions" and "app/github-actions" returned none.
        if variables["a"] == IDENTITY:
            nodes = [
                {
                    "number": 9,
                    "body": record["body"],
                    "lastEditedAt": issue.get("lastEditedAt"),
                }
            ]
        page = {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": nodes}
        return {"repository": {"issues": page}}

    gh.graphql["PolicyIssuesByAuthor"] = by_author
    gh.graphql["PolicyDemotionRecord"] = {"repository": {"issue": record}}
    return gh


def read_demotion() -> Any:
    return policy.read_demotion(REPO, agent_identity=IDENTITY, permission=HUMANS)


class ReadDemotion(unittest.TestCase):
    def test_closed_directly_by_a_human_with_no_non_human_edit_is_clear(self) -> None:
        demotion_fake(self)
        result = read_demotion()
        self.assertFalse(result.active, result.reason)
        self.assertEqual(result.records, (9,))
        # The cleared record restarts the evidence window and the floor.
        self.assertEqual(
            (result.newest_created, result.cleared_at),
            (
                policy.datetime.fromisoformat("2026-10-12T10:00:00Z"),
                policy.datetime.fromisoformat("2026-10-12T12:00:00Z"),
            ),
        )

    def test_a_cleared_record_without_a_close_time_is_off(self) -> None:
        demotion_fake(
            self,
            timelineItems={"nodes": [{"actor": user(OPERATOR), "closer": None}]},
        )
        result = read_demotion()
        self.assertTrue(result.active)
        self.assertTrue(result.reason.startswith("demotion-unreadable"), result.reason)

    def test_no_record_has_no_window_restart(self) -> None:
        gh = demotion_fake(self)
        empty = {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": []}
        gh.graphql["PolicyIssuesByAuthor"] = {"repository": {"issues": empty}}
        result = read_demotion()
        self.assertEqual(
            (result.active, result.newest_created, result.cleared_at),
            (False, None, None),
        )

    def test_open_is_off(self) -> None:
        demotion_fake(self, state="OPEN", timelineItems={"nodes": []})
        self.assertTrue(read_demotion().active)

    def test_closed_by_the_identity_is_off(self) -> None:
        demotion_fake(
            self,
            timelineItems={"nodes": [{"actor": bot("agent-lanes"), "closer": None}]},
        )
        self.assertTrue(read_demotion().active)

    def test_closed_by_a_pull_request_reference_is_off(self) -> None:
        # A merged PR's "Closes #N" sets `closer`; its actor is the human who merged.
        demotion_fake(
            self,
            timelineItems={
                "nodes": [
                    {"actor": user(OPERATOR), "closer": {"__typename": "PullRequest"}}
                ]
            },
        )
        self.assertTrue(read_demotion().active)

    def test_issues_past_the_page_limit_are_off(self) -> None:
        gh = demotion_fake(self)
        page = {"pageInfo": {"hasNextPage": True, "endCursor": "next"}, "nodes": []}
        gh.graphql["PolicyIssuesByAuthor"] = {"repository": {"issues": page}}
        result = read_demotion()
        self.assertTrue(result.active)
        self.assertIn(f"more than {policy.ISSUES_PAGE_LIMIT} pages", result.reason)

    def test_marker_beyond_a_truncated_edit_history_is_off(self) -> None:
        # Only the newest 100 revisions are read; the marker may sit in an older one.
        edit = {"editedAt": "2026-10-12T11:00:00Z", "deletedAt": None}
        edit |= {"editor": bot("agent-lanes"), "diff": "scrubbed"}
        demotion_fake(
            self,
            state="OPEN",
            body="scrubbed",
            lastEditedAt="2026-10-12T11:00:00Z",
            userContentEdits={"totalCount": 150, "nodes": [edit] * 100},
            timelineItems={"nodes": []},
        )
        result = read_demotion()
        self.assertTrue(result.active)
        self.assertEqual(result.reason, "#9 edit-history-incomplete")

    def test_marker_edited_away_by_the_identity_is_still_found_and_off(self) -> None:
        edits = {
            "totalCount": 2,
            "nodes": [
                {
                    "editedAt": "2026-10-12T11:00:00Z",
                    "deletedAt": None,
                    "editor": bot("agent-lanes"),
                    "diff": "PR #5",
                },
                {
                    "editedAt": "2026-10-12T10:00:00Z",
                    "deletedAt": None,
                    "editor": bot("agent-lanes"),
                    "diff": DEMOTION_BODY,
                },
            ],
        }
        demotion_fake(
            self,
            body="PR #5",
            lastEditedAt="2026-10-12T11:00:00Z",
            userContentEdits=edits,
        )
        result = read_demotion()
        self.assertEqual(result.records, (9,))
        self.assertTrue(result.active)

    def test_role_label_removed_is_still_off(self) -> None:
        # Records are found by author and marker: neither query reads labels,
        # so a record with its role label removed is still found and held.
        gh = demotion_fake(
            self,
            timelineItems={"nodes": [{"actor": bot("agent-lanes"), "closer": None}]},
        )
        result = read_demotion()
        self.assertEqual((result.active, result.records), (True, (9,)))
        queries = [a for call in gh.calls for a in call if a.startswith("query=")]
        self.assertEqual(len(queries), 3)
        for query in queries:
            self.assertNotIn("labels", query)

    def test_only_the_earliest_revision_at_creation_is_the_original(self) -> None:
        # A second identity revision stamped at createdAt is an edit, not the
        # original body, even when a human edited after it.
        edits = {
            "totalCount": 3,
            "nodes": [
                {
                    "editedAt": "2026-10-12T11:00:00Z",
                    "deletedAt": None,
                    "editor": user(OPERATOR),
                    "diff": DEMOTION_BODY + " note",
                },
                {
                    "editedAt": "2026-10-12T10:00:00Z",
                    "deletedAt": None,
                    "editor": bot("agent-lanes"),
                    "diff": DEMOTION_BODY + " rewritten",
                },
                {
                    "editedAt": "2026-10-12T10:00:00Z",
                    "deletedAt": None,
                    "editor": bot("agent-lanes"),
                    "diff": DEMOTION_BODY,
                },
            ],
        }
        demotion_fake(self, lastEditedAt="2026-10-12T11:00:00Z", userContentEdits=edits)
        result = read_demotion()
        self.assertEqual(result.reason, "#9 edited-by-non-human")

    def test_a_null_author_or_editor_is_never_the_original(self) -> None:
        original = {
            "editedAt": "2026-10-12T10:00:00Z",
            "deletedAt": None,
            "editor": None,
            "diff": DEMOTION_BODY,
        }
        for name, author, editor in (
            ("both null", None, None),
            ("null editor", bot("agent-lanes"), None),
            ("null author", None, bot("agent-lanes")),
        ):
            with self.subTest(name):
                edits = {"totalCount": 1, "nodes": [original | {"editor": editor}]}
                demotion_fake(self, author=author, userContentEdits=edits)
                self.assertEqual(read_demotion().reason, "#9 edited-by-non-human")

    def test_any_non_human_edit_is_off(self) -> None:
        for editor in (bot("renovate"), user("reader"), None):
            with self.subTest(editor):
                edits = {
                    "totalCount": 2,
                    "nodes": [
                        {
                            "editedAt": "2026-10-12T11:00:00Z",
                            "deletedAt": None,
                            "editor": editor,
                            "diff": DEMOTION_BODY + " x",
                        },
                        {
                            "editedAt": "2026-10-12T10:00:00Z",
                            "deletedAt": None,
                            "editor": bot("agent-lanes"),
                            "diff": DEMOTION_BODY,
                        },
                    ],
                }
                demotion_fake(
                    self, lastEditedAt="2026-10-12T11:00:00Z", userContentEdits=edits
                )
                self.assertTrue(read_demotion().active)

    def test_a_human_edit_keeps_it_clear(self) -> None:
        # GitHub lists the original body as an edit by the author once anyone
        # edits it (probed on #6202); that entry alone is not a non-human edit.
        edits = {
            "totalCount": 2,
            "nodes": [
                {
                    "editedAt": "2026-10-12T11:00:00Z",
                    "deletedAt": None,
                    "editor": user(OPERATOR),
                    "diff": DEMOTION_BODY + " note",
                },
                {
                    "editedAt": "2026-10-12T10:00:00Z",
                    "deletedAt": None,
                    "editor": bot("agent-lanes"),
                    "diff": DEMOTION_BODY,
                },
            ],
        }
        demotion_fake(self, lastEditedAt="2026-10-12T11:00:00Z", userContentEdits=edits)
        self.assertFalse(read_demotion().active)

    def test_an_unedited_issue_without_the_marker_is_not_a_record(self) -> None:
        demotion_fake(self, body="an unrelated lane issue", state="OPEN")
        result = read_demotion()
        self.assertEqual((result.active, result.records), (False, ()))

    def test_an_unreadable_listing_is_off(self) -> None:
        gh = demotion_fake(self)
        gh.graphql["PolicyIssuesByAuthor"] = 502
        self.assertTrue(read_demotion().active)

    def test_a_listing_page_without_a_boolean_has_next_page_is_off(self) -> None:
        gh = demotion_fake(self)
        page = {"pageInfo": {"endCursor": "p0"}, "nodes": []}
        gh.graphql["PolicyIssuesByAuthor"] = {"repository": {"issues": page}}
        result = read_demotion()
        self.assertTrue(result.active)
        self.assertTrue(result.reason.startswith("demotion-unreadable"), result.reason)

    def test_a_timestamp_without_an_offset_is_off(self) -> None:
        # The original revision's naive stamp equals createdAt, so its offset
        # is read when compared with the human edit's stamp.
        edits = {
            "totalCount": 2,
            "nodes": [
                {
                    "editedAt": "2026-10-12T11:00:00Z",
                    "deletedAt": None,
                    "editor": user(OPERATOR),
                    "diff": DEMOTION_BODY + " note",
                },
                {
                    "editedAt": "2026-10-12T10:00:00",
                    "deletedAt": None,
                    "editor": bot("agent-lanes"),
                    "diff": DEMOTION_BODY,
                },
            ],
        }
        demotion_fake(
            self,
            createdAt="2026-10-12T10:00:00",
            lastEditedAt="2026-10-12T11:00:00Z",
            userContentEdits=edits,
        )
        result = read_demotion()
        self.assertTrue(result.active)
        self.assertTrue(result.reason.startswith("demotion-unreadable"), result.reason)


class ResolveIdentity(unittest.TestCase):
    def test_equal_logins_resolve(self) -> None:
        result = policy.resolve_identity(IDENTITY, "Agent-Lanes[bot]")
        self.assertEqual((result.login, result.reason), (IDENTITY, None))

    def test_refusals(self) -> None:
        cases = {
            "unset": (None, IDENTITY, frozenset(), "agent-identity-unconfigured"),
            "blank": ("  ", IDENTITY, frozenset(), "agent-identity-unconfigured"),
            "a user login": (
                "machine-user",
                "machine-user",
                frozenset(),
                "agent-identity-invalid",
            ),
            "a shared bot": (
                "github-actions[bot]",
                "github-actions[bot]",
                frozenset(),
                "agent-identity-invalid",
            ),
            "unequal": (IDENTITY, OPERATOR, frozenset(), "acting-login-mismatch"),
            "unreadable": (IDENTITY, None, frozenset(), "acting-login-unreadable"),
            "bare slug": (
                IDENTITY,
                "agent-lanes",
                frozenset(),
                "acting-login-mismatch",
            ),
            "self login": (
                IDENTITY,
                IDENTITY,
                frozenset({IDENTITY}),
                "agent-identity-self-login",
            ),
        }
        for name, (configured, acting, selves, reason) in cases.items():
            with self.subTest(name):
                result = policy.resolve_identity(configured, acting, selves)
                self.assertEqual(result.reason, reason)


ISSUE = 40


def eligibility_fake(
    case: unittest.TestCase,
    *,
    pr: dict[str, Any] | None = None,
    issue: dict[str, Any] | None = None,
    issues: list[dict[str, Any]] | None = None,
) -> GhFake:
    linked = {
        "number": ISSUE,
        "lastEditedAt": None,
        "repository": {"nameWithOwner": REPO},
        "labels": {"totalCount": 1, "nodes": [{"name": "work-class: mechanical"}]},
    } | (issue or {})
    nodes = [linked] if issues is None else issues
    pull = {
        "number": 7,
        "createdAt": PR_CREATED,
        "lastEditedAt": None,
        "isCrossRepository": False,
        "author": bot("agent-lanes"),
        "headRepositoryOwner": {"login": "owner"},
        "labels": {"totalCount": 0, "nodes": []},
        "closingIssuesReferences": {"totalCount": len(nodes), "nodes": nodes},
    } | (pr or {})
    gh = GhFake().install(case)
    gh.graphql["PolicyEligibility"] = {"repository": {"pullRequest": pull}}
    # REST issue timeline `labeled` event: `actor` is a REST user object
    # (`login`, `type`), the field label-provenance.sh reads as `.actor.login`.
    gh.rest[f"repos/{REPO}/issues/{ISSUE}/timeline?per_page=100"] = [
        {
            "event": "labeled",
            "label": {"name": "work-class: mechanical"},
            "actor": {"login": OPERATOR, "type": "User"},
            "created_at": "2026-10-11T09:00:00Z",
        },
    ]
    gh.rest[f"repos/{REPO}/issues/{ISSUE}/comments?per_page=100"] = [
        lease_comment(IDENTITY, "2026-10-12T11:00:00Z")
    ]
    return gh


def lease_comment(
    holder: str, created_at: str, poster: dict[str, str] | None = None
) -> dict[str, Any]:
    """A REST issue comment carrying a work-item lease; `user` is the REST user
    object of whoever posted it, the identity's App by default."""
    lease = {"holder": holder, "acquired_at": created_at}
    return {
        "body": f"{policy.LEASE_MARKER}{json.dumps(lease)} -->",
        "created_at": created_at,
        "user": poster or {"login": IDENTITY, "type": "Bot"},
    }


def eligibility() -> Any:
    return policy.eligibility(REPO, 7, agent_identity=IDENTITY, permission=HUMANS)


class Eligibility(unittest.TestCase):
    def test_a_lane_authored_pr_with_one_classed_issue_and_an_earlier_claim(
        self,
    ) -> None:
        eligibility_fake(self)
        result = eligibility()
        self.assertTrue(result.eligible, result.reason)
        self.assertEqual((result.work_class, result.issue), ("C2", ISSUE))

    def test_fork_and_dependency_prs_are_ineligible(self) -> None:
        for name, pr, reason in (
            ("cross repository", {"isCrossRepository": True}, "fork"),
            ("other head owner", {"headRepositoryOwner": {"login": "someone"}}, "fork"),
            ("dependabot", {"author": bot("dependabot")}, "dependency-manager"),
        ):
            with self.subTest(name):
                eligibility_fake(self, pr=pr)
                self.assertEqual(eligibility().reason, reason)

    def test_a_human_pr_needs_the_opt_in_label_from_a_human(self) -> None:
        gh = eligibility_fake(self, pr={"author": user(OPERATOR)})
        self.assertEqual(eligibility().reason, "not-lane-authored-or-opted-in")

        labeled = {"totalCount": 1, "nodes": [{"name": policy.OPT_IN_LABEL}]}
        gh = eligibility_fake(self, pr={"author": user(OPERATOR), "labels": labeled})
        gh.rest[f"repos/{REPO}/issues/7/timeline?per_page=100"] = [
            {
                "event": "labeled",
                "label": {"name": policy.OPT_IN_LABEL},
                "actor": {"login": "maintainer", "type": "User"},
                "created_at": "2026-10-12T12:30:00Z",
            },
        ]
        self.assertTrue(eligibility().eligible)

        gh.rest[f"repos/{REPO}/issues/7/timeline?per_page=100"] = [
            {
                "event": "labeled",
                "label": {"name": policy.OPT_IN_LABEL},
                "actor": {"login": "agent-lanes[bot]", "type": "Bot"},
                "created_at": "2026-10-12T12:30:00Z",
            },
        ]
        self.assertEqual(eligibility().reason, "opt-in-label:labeler-not-human")

    def test_the_enqueue_recheck_reads_the_opt_in_again(self) -> None:
        # #7339 comment 2: a removal, or a removal and a bot re-add, between
        # the eligibility read and the enqueue must refuse the enqueue.
        def recheck() -> str | None:
            return policy.recheck_opt_in(
                REPO, 7, agent_identity=IDENTITY, permission=HUMANS
            )

        eligibility_fake(self, pr={"author": user(OPERATOR)})
        self.assertEqual(recheck(), "not-lane-authored-or-opted-in")

        labeled = {"totalCount": 1, "nodes": [{"name": policy.OPT_IN_LABEL}]}
        gh = eligibility_fake(self, pr={"author": user(OPERATOR), "labels": labeled})
        gh.rest[f"repos/{REPO}/issues/7/timeline?per_page=100"] = [
            {
                "event": "labeled",
                "label": {"name": policy.OPT_IN_LABEL},
                "actor": {"login": "maintainer", "type": "User"},
                "created_at": "2026-10-12T12:30:00Z",
            },
            {
                "event": "unlabeled",
                "label": {"name": policy.OPT_IN_LABEL},
                "actor": {"login": "maintainer", "type": "User"},
                "created_at": "2026-10-12T12:40:00Z",
            },
            {
                "event": "labeled",
                "label": {"name": policy.OPT_IN_LABEL},
                "actor": {"login": "some-app[bot]", "type": "Bot"},
                "created_at": "2026-10-12T12:45:00Z",
            },
        ]
        self.assertEqual(recheck(), "opt-in-label:labeler-not-human")

        eligibility_fake(self)
        self.assertIsNone(recheck())

    def test_exactly_one_same_repository_linked_issue(self) -> None:
        second = {
            "number": 41,
            "lastEditedAt": None,
            "repository": {"nameWithOwner": REPO},
            "labels": {"totalCount": 0, "nodes": []},
        }
        eligibility_fake(self, issues=[])
        self.assertEqual(eligibility().reason, "linked-issues:0")
        first = {
            "number": ISSUE,
            "lastEditedAt": None,
            "repository": {"nameWithOwner": REPO},
            "labels": {"totalCount": 1, "nodes": [{"name": "work-class: mechanical"}]},
        }
        eligibility_fake(self, issues=[first, second])
        self.assertEqual(eligibility().reason, "linked-issues:2")
        eligibility_fake(self, issue={"repository": {"nameWithOwner": "other/repo"}})
        self.assertEqual(eligibility().reason, "linked-issue-other-repository")

    def test_the_class_must_be_provenance_valid(self) -> None:
        eligibility_fake(self, issue={"labels": {"totalCount": 0, "nodes": []}})
        self.assertEqual(eligibility().reason, "class-missing")

        gh = eligibility_fake(self)
        gh.rest[f"repos/{REPO}/issues/{ISSUE}/timeline?per_page=100"] = [
            {
                "event": "labeled",
                "label": {"name": "work-class: mechanical"},
                "actor": {"login": "agent-lanes[bot]", "type": "Bot"},
                "created_at": "2026-10-11T09:00:00Z",
            },
        ]
        self.assertEqual(eligibility().reason, "class-provenance:labeler-not-human")

        eligibility_fake(self, issue={"lastEditedAt": "2026-10-11T10:00:00Z"})
        self.assertEqual(
            eligibility().reason, "class-provenance:body-edited-after-label"
        )

    def test_the_lane_claim_must_predate_the_pr(self) -> None:
        gh = eligibility_fake(self)
        late = {"holder": IDENTITY}
        gh.rest[f"repos/{REPO}/issues/{ISSUE}/comments?per_page=100"] = [
            {
                "body": f"{policy.LEASE_MARKER}{json.dumps(late)} -->",
                "created_at": "2026-10-12T12:00:01Z",
            },
        ]
        self.assertEqual(eligibility().reason, "claim-missing")

        for poster in (
            {"login": "stranger", "type": "User"},
            {"login": OPERATOR, "type": "User"},
            {"login": "agent-lanes", "type": "User"},
            {"login": "other-app[bot]", "type": "Bot"},
        ):
            with self.subTest(poster):
                gh.rest[f"repos/{REPO}/issues/{ISSUE}/comments?per_page=100"] = [
                    lease_comment(IDENTITY, "2026-10-12T11:00:00Z", poster)
                ]
                self.assertEqual(eligibility().reason, "claim-missing")

        other = {"holder": OPERATOR}
        gh.rest[f"repos/{REPO}/issues/{ISSUE}/comments?per_page=100"] = [
            {
                "body": f"{policy.LEASE_MARKER}{json.dumps(other)} -->",
                "created_at": "2026-10-12T11:00:00Z",
            },
        ]
        self.assertEqual(eligibility().reason, "claim-missing")


class EligibilityAgentSignals(unittest.TestCase):
    """Carried from #7324: an App acting on a human's token is not the human,
    and a class label removed by a non-human leaves a lower class untrusted."""

    TIMELINE = f"repos/{REPO}/issues/{ISSUE}/timeline?per_page=100"

    def test_a_class_label_applied_through_an_app_is_not_human(self) -> None:
        gh = eligibility_fake(self)
        gh.rest[self.TIMELINE][0]["performed_via_github_app"] = {"slug": "agent"}
        self.assertEqual(eligibility().reason, "class-provenance:labeler-via-app")

    def test_a_class_label_removed_by_a_non_human_is_ineligible(self) -> None:
        for actor, via in (
            ({"login": IDENTITY, "type": "Bot"}, None),
            ({"login": OPERATOR, "type": "User"}, {"slug": "agent"}),
        ):
            with self.subTest(actor=actor, via=via):
                gh = eligibility_fake(self)
                gh.rest[self.TIMELINE].append(
                    {
                        "event": "unlabeled",
                        "label": {"name": "work-class: scoped"},
                        "actor": actor,
                        "performed_via_github_app": via,
                        "created_at": "2026-10-11T10:00:00Z",
                    }
                )
                self.assertEqual(
                    eligibility().reason, "class-label-removed-by-non-human"
                )

    def test_a_human_removing_a_class_label_stays_eligible(self) -> None:
        gh = eligibility_fake(self)
        gh.rest[self.TIMELINE].append(
            {
                "event": "unlabeled",
                "label": {"name": "work-class: scoped"},
                "actor": {"login": OPERATOR, "type": "User"},
                "created_at": "2026-10-11T10:00:00Z",
            }
        )
        self.assertTrue(eligibility().eligible)

    def test_a_label_event_without_an_offset_is_ineligible(self) -> None:
        gh = eligibility_fake(self)
        gh.rest[self.TIMELINE][0]["created_at"] = "2026-10-11T09:00:00"
        result = eligibility()
        self.assertFalse(result.eligible)
        self.assertTrue(result.reason.startswith("unreadable"), result.reason)


class ChangedFiles(unittest.TestCase):
    """Git modes come from the trees API, which the PR files API omits."""

    HEAD = "e" * 40

    def test_modes_come_from_the_head_and_base_trees(self) -> None:
        gh = GhFake().install(self)
        gh.rest[f"repos/{REPO}/pulls/7/files?per_page=100"] = [
            {
                "filename": "docs/a.md",
                "status": "modified",
                "additions": 1,
                "deletions": 0,
                "patch": "@@",
            },
            {
                "filename": "docs/b.md",
                "previous_filename": "docs/old.md",
                "status": "renamed",
                "additions": 0,
                "deletions": 0,
            },
        ]
        gh.rest[f"repos/{REPO}/git/trees/{self.HEAD}?recursive=1"] = {
            "truncated": False,
            "tree": [
                {"path": "docs/a.md", "mode": "100755"},
                {"path": "docs/b.md", "mode": "120000"},
            ],
        }
        gh.rest[f"repos/{REPO}/git/trees/{SHA}?recursive=1"] = {
            "truncated": False,
            "tree": [
                {"path": "docs/a.md", "mode": "100644"},
                {"path": "docs/old.md", "mode": "100644"},
            ],
        }
        pr = {
            "number": 7,
            "changed_files": 2,
            "head": {"sha": self.HEAD},
            "base": {"sha": SHA},
        }
        files, complete = policy.changed_files(REPO, pr)
        self.assertTrue(complete)
        self.assertEqual(
            [(f.path, f.mode, f.previous_mode, f.has_patch) for f in files],
            [
                ("docs/a.md", "100755", "100644", True),
                ("docs/b.md", "120000", "100644", False),
            ],
        )

    def test_a_truncated_tree_is_incomplete(self) -> None:
        gh = GhFake().install(self)
        gh.rest[f"repos/{REPO}/pulls/7/files?per_page=100"] = []
        for sha in (self.HEAD, SHA):
            gh.rest[f"repos/{REPO}/git/trees/{sha}?recursive=1"] = {
                "truncated": True,
                "tree": [],
            }
        pr = {
            "number": 7,
            "changed_files": 0,
            "head": {"sha": self.HEAD},
            "base": {"sha": SHA},
        }
        self.assertEqual(policy.changed_files(REPO, pr), ((), False))


class LaneWritable(unittest.TestCase):
    def test_a_writable_ancestor_directory_is_lane_writable(self) -> None:
        # #7339 item 1: renaming a writable grandparent replaces the file.
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp).resolve()
            target = root / "a" / "b" / "evidence.json"
            target.parent.mkdir(parents=True)
            target.write_text("[]", encoding="utf-8")
            with (
                mock.patch.object(
                    policy.os, "access", side_effect=lambda p, _m: p == root / "a"
                ),
                mock.patch.object(policy.os, "getuid", return_value=-1, create=True),
            ):
                self.assertTrue(policy._lane_writable(target))
            with (
                mock.patch.object(policy.os, "access", return_value=False),
                mock.patch.object(policy.os, "getuid", return_value=-1, create=True),
            ):
                self.assertFalse(policy._lane_writable(target))


# The checker's evaluation block (check-security-binding.mjs evaluation mode).
EVALUATION = (
    "Effective promotion state (evaluation mode):\n"
    "- C2-auto-merge: bound promoted -> effective promoted\n"
    "- C3-auto-merge: bound unpromoted -> effective unpromoted\n"
)


def _host_configures_promotion() -> bool:
    """Host managed settings that set these options would decide the result."""
    managed = pathlib.Path("/etc/claude-code")
    files = [managed / "managed-settings.json", *managed.glob("managed-settings.d/*")]
    for path in files:
        try:
            if "promotion_evidence_" in path.read_text(encoding="utf-8"):
                return True
        except OSError:
            continue
    return False


@unittest.skipUnless(shutil.which("node"), "node not installed")
@unittest.skipIf(_host_configures_promotion(), "host managed settings set the options")
class RealResolver(unittest.TestCase):
    """`read_promotion` runs the real `resolve-promotion-evidence.mjs`, copied
    into a marketplace install layout so it finds its user settings there. The
    checker is the operator's program, so a recording stub stands in for it.

    Every file here is the test user's own, so the resolver's own writability
    check would refuse first; the cases run its `main()` through a seam wrapper
    that judges every path administrator-owned, leaving the gate's
    `writable` as the layer under test."""

    def setUp(self) -> None:
        import tempfile

        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        base = pathlib.Path(tmp.name).resolve()
        config = base / "config"
        scripts = config.joinpath(
            "plugins", "cache", "mkt", "source-control", "9.9.9"
        ).joinpath("skills", "babysit-loop", "scripts")
        scripts.mkdir(parents=True)
        for name in ("resolve-promotion-evidence.mjs", "operator-options.mjs"):
            shutil.copy(policy.PROMOTION_RESOLVER.parent / name, scripts / name)
        self.resolver = scripts / "resolve-promotion-evidence.mjs"
        seam = scripts / "seam.mjs"
        seam.write_text(
            'import { main } from "./resolve-promotion-evidence.mjs";\n'
            'main({ platform: "linux", uid: 1000, access: () => false, '
            "stat: () => ({ uid: 0 }) });\n",
            encoding="utf-8",
        )
        patcher = mock.patch.object(policy, "PROMOTION_RESOLVER", seam)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.ops = base / "ops"
        (self.ops / "probe").mkdir(parents=True)
        self.prior = {
            "cell": "C2-auto-merge",
            "event": "reverted-merge",
            "at": "2026-10-01T00:00:00Z",
        }
        self.source = self.ops / "evidence.json"
        self.source.write_text(json.dumps([self.prior]), encoding="utf-8")
        (self.ops / "binding.json").write_text("{}", encoding="utf-8")
        self.record = self.ops / "record.json"
        checker = self.ops / "checker.mjs"
        checker.write_text(
            'import { readFileSync, writeFileSync } from "node:fs";\n'
            "const evidence = process.argv[process.argv.indexOf('--evidence') + 1];\n"
            f"writeFileSync({json.dumps(str(self.record))}, JSON.stringify("
            "{ evidence, argv: process.argv.slice(2), "
            'events: JSON.parse(readFileSync(evidence, "utf8")) }));\n'
            f"process.stdout.write({json.dumps(EVALUATION)});\n",
            encoding="utf-8",
        )
        self.settings = config / "settings.json"
        options = {
            "promotion_evidence_binding": str(self.ops / "binding.json"),
            "promotion_evidence_root": str(self.ops / "probe"),
            "promotion_evidence_source": str(self.source),
            "promotion_evidence_checker": str(checker),
        }
        self.settings.write_text(
            json.dumps({"pluginConfigs": {"source-control@mkt": {"options": options}}}),
            encoding="utf-8",
        )
        self.checkout = base / "checkout"
        self.checkout.mkdir()

    def read(self, **kwargs: Any) -> Any:
        arguments: dict[str, Any] = {
            "checkout": self.checkout,
            "window_start": None,
            "worktrees": lambda c: [str(self.checkout)],
            "writable": lambda p: False,
        }
        return policy.read_promotion(**(arguments | kwargs))

    def seen(self) -> dict[str, Any]:
        return json.loads(self.record.read_text(encoding="utf-8"))

    def test_the_resolver_promotes_from_the_operator_settings(self) -> None:
        # Against the retired --binding/--evidence call shape the resolver
        # refused every call as a usage error, so nothing was ever promoted.
        result = self.read()
        self.assertIsNone(result.reason)
        self.assertTrue(result.promoted("C2"))
        self.assertFalse(result.promoted("C3"))
        self.assertEqual(self.seen()["evidence"], str(self.source))

    def test_operator_credential_roots_reach_the_checker(self) -> None:
        self.read()
        self.assertNotIn("--credential-roots", self.seen()["argv"])
        settings = json.loads(self.settings.read_text(encoding="utf-8"))
        options = settings["pluginConfigs"]["source-control@mkt"]["options"]
        options["promotion_evidence_credential_roots"] = "/srv/probe-creds"
        self.settings.write_text(json.dumps(settings), encoding="utf-8")
        result = self.read()
        self.assertIsNone(result.reason)
        self.assertEqual(
            self.seen()["argv"][-2:], ["--credential-roots", "/srv/probe-creds"]
        )

    def test_a_demotion_restarts_the_window_at_its_creation(self) -> None:
        start = policy.datetime(2026, 10, 11, 7, 0, 0, 500000, tzinfo=policy.UTC)
        result = self.read(window_start=start)
        self.assertIsNone(result.reason)
        seen = self.seen()
        self.assertNotEqual(seen["evidence"], str(self.source))
        # Rounded up to the next whole second, never before the demotion.
        self.assertEqual(
            seen["events"],
            [
                self.prior,
                *(
                    {"cell": c, "event": "gate-failure", "at": "2026-10-11T07:00:01Z"}
                    for c in policy.PROMOTABLE_CELLS
                ),
            ],
        )

    def test_a_surface_in_a_sibling_worktree_refuses(self) -> None:
        result = self.read(worktrees=lambda c: [str(self.checkout), str(self.ops)])
        self.assertRegex(result.reason or "", "is inside")
        self.assertFalse(result.promoted("C2"))

    def test_a_lane_writable_value_or_settings_file_refuses(self) -> None:
        # The real check: every file this test created is the lane user's own.
        self.assertEqual(
            self.read(writable=policy._lane_writable).reason,
            "evidence-lane-writable:promotion_evidence_binding",
        )
        only_settings = self.read(writable=lambda p: p == self.settings)
        self.assertEqual(
            only_settings.reason, "settings-lane-writable:promotion_evidence_binding"
        )
        checker = self.ops / "checker.mjs"
        self.assertEqual(
            self.read(writable=lambda p: p == checker).reason,
            "evidence-lane-writable:promotion_evidence_checker",
        )

    def test_the_resolver_itself_refuses_a_lane_writable_surface(self) -> None:
        # The babysit-loop prose route has no gate `writable` behind it, so
        # the resolver's own check is the one that refuses there.
        with mock.patch.object(policy, "PROMOTION_RESOLVER", self.resolver):
            result = self.read()
        self.assertEqual(result.reason, "lane-writable:promotion_evidence_checker")
        self.assertFalse(result.promoted("C2"))


class ReadPromotion(unittest.TestCase):
    """The resolver call shape, with the resolver itself stubbed."""

    CELLS = {c: {"effective": "promoted"} for c in policy.PROMOTABLE_CELLS}

    def run_resolver(
        self, payload: dict[str, Any] | None = None, **kwargs: Any
    ) -> tuple[Any, list[list[str]]]:
        seen: list[list[str]] = []
        options = {
            o: {"value": f"/opt/p/{o}", "scope": "managed", "file": "/etc/m.json"}
            for o in policy.PROMOTION_OPTIONS
        }

        def fake_run(argv: list[str], **_: Any) -> Any:
            seen.append(argv)
            answer = payload or {
                "failClosedReason": None,
                "options": options,
                "cells": self.CELLS,
            }
            return subprocess.CompletedProcess(argv, 0, json.dumps(answer), "")

        arguments: dict[str, Any] = {
            "checkout": pathlib.Path("/w/main"),
            "window_start": None,
            "worktrees": lambda c: [],
            "writable": lambda p: False,
        }
        with mock.patch.object(policy, "run_command", fake_run):
            result = policy.read_promotion(**(arguments | kwargs))
        return result, seen

    def test_every_worktree_is_a_root_the_resolver_refuses(self) -> None:
        # #7339 item 1: without the roots a surface in a sibling worktree passed.
        roots = ["/w/main", "/w/sibling"]
        _, seen = self.run_resolver(worktrees=lambda c: roots)
        argv = seen[0]
        passed = [argv[i + 1] for i, a in enumerate(argv) if a == "--worktree-root"]
        self.assertEqual(passed, roots)

    def test_unlisted_worktrees_promote_nothing(self) -> None:
        result, seen = self.run_resolver(worktrees=lambda c: None)
        self.assertEqual(result.reason, "worktrees-unreadable")
        self.assertEqual(seen, [])

    def test_worktree_roots_come_from_git(self) -> None:
        proc = subprocess.CompletedProcess(
            [],
            0,
            "worktree /w/main\nHEAD abc\nbranch refs/heads/main\n\n"
            "worktree /w/side\nHEAD def\ndetached\n",
            "",
        )
        with mock.patch.object(policy, "run_command", return_value=proc):
            self.assertEqual(
                policy.worktree_roots(pathlib.Path("/w/main")), ["/w/main", "/w/side"]
            )
        failed = subprocess.CompletedProcess([], 128, "", "not a git repository")
        with mock.patch.object(policy, "run_command", return_value=failed):
            self.assertIsNone(policy.worktree_roots(pathlib.Path("/w/main")))

    def test_credential_roots_check_only_their_settings_file(self) -> None:
        # The roots name the probe host, so the value is never judged as a
        # local path: one absent here is not refused, as the real
        # _lane_writable would refuse it (OSError).
        absent = "/nonexistent-probe-host/creds"
        creds_file = "/etc/claude-code/managed-settings.d/20-creds.json"
        payload = {
            "failClosedReason": None,
            "options": {
                o: {"value": f"/opt/p/{o}", "scope": "managed", "file": "/etc/m.json"}
                for o in policy.PROMOTION_OPTIONS
            }
            | {
                "promotion_evidence_credential_roots": {
                    "value": absent,
                    "scope": "managed",
                    "file": creds_file,
                }
            },
            "cells": self.CELLS,
        }

        def writable(path: pathlib.Path) -> bool:
            if str(path) == absent:
                return policy._lane_writable(path)
            return str(path) == creds_file

        result, _ = self.run_resolver(payload, writable=writable)
        self.assertEqual(
            result.reason, "settings-lane-writable:promotion_evidence_credential_roots"
        )
        result, _ = self.run_resolver(
            payload,
            writable=lambda p: policy._lane_writable(p) if str(p) == absent else False,
        )
        self.assertIsNone(result.reason)
        self.assertTrue(result.promoted("C3"))

    def test_unset_credential_roots_are_not_a_refusal(self) -> None:
        result, _ = self.run_resolver()
        self.assertIsNone(result.reason)
        unfiled = {
            "failClosedReason": None,
            "cells": self.CELLS,
            "options": {
                o: {"value": "/opt/p", "scope": "managed", "file": "/etc/m.json"}
                for o in policy.PROMOTION_OPTIONS
            }
            | {"promotion_evidence_credential_roots": {"value": "/srv/probe-creds"}},
        }
        result, _ = self.run_resolver(unfiled)
        self.assertEqual(
            result.reason, "option-unreported:promotion_evidence_credential_roots"
        )

    def test_an_unreported_option_refuses(self) -> None:
        payload = {"failClosedReason": None, "options": {}, "cells": self.CELLS}
        result, _ = self.run_resolver(payload)
        self.assertEqual(result.reason, "option-unreported:promotion_evidence_binding")
        self.assertFalse(result.promoted("C2"))

    def test_c4_and_c5_are_never_promoted(self) -> None:
        result, _ = self.run_resolver()
        self.assertTrue(result.promoted("C2"))
        for work_class in ("C4", "C5", None):
            self.assertFalse(result.promoted(work_class))

    def test_a_fail_closed_resolver_promotes_nothing(self) -> None:
        payload = {"failClosedReason": "checker exited 1", "cells": {}}
        result, _ = self.run_resolver(payload)
        self.assertEqual(result.reason, "checker exited 1")
        self.assertFalse(result.promoted("C2"))


class EntryHold(unittest.TestCase):
    """D3: a hold that lands on a queued identity entry after the enqueue."""

    def fake(self, **pr: Any) -> GhFake:
        gh = GhFake().install(self)
        gh.graphql["PolicyEntryHold"] = {
            "repository": {
                "pullRequest": {
                    "number": 5,
                    "body": "Closes #40",
                    "labels": {"totalCount": 0, "nodes": []},
                    "timelineItems": {"nodes": [{"createdAt": "2026-10-12T10:00:00Z"}]},
                }
                | pr
            }
        }
        for kind in (
            "issues/5/comments",
            "pulls/5/reviews",
            "pulls/5/comments",
            "issues/5/timeline",
        ):
            gh.rest[f"repos/{REPO}/{kind}?per_page=100"] = []
        return gh

    def hold(self) -> str | None:
        return policy.entry_hold(REPO, 5, IDENTITY)

    def test_no_hold(self) -> None:
        self.fake()
        self.assertIsNone(self.hold())

    def test_the_do_not_merge_label(self) -> None:
        self.fake(labels={"totalCount": 1, "nodes": [{"name": "Do-Not-Merge"}]})
        self.assertEqual(self.hold(), "do-not-merge")

    def test_a_body_hold(self) -> None:
        self.fake(body="Please do not merge until the release")
        self.assertEqual(self.hold(), "body-hold")

    def test_a_body_hold_line(self) -> None:
        self.fake(body="Refs: #1\r\n\r\nHold: a human merges this")
        self.assertEqual(self.hold(), "body-hold")

    def test_a_human_blocking_comment(self) -> None:
        gh = self.fake()
        gh.rest[f"repos/{REPO}/issues/5/comments?per_page=100"] = [
            {
                "user": {"login": OPERATOR, "type": "User"},
                "author_association": "MEMBER",
                "body": "don't merge this",
            }
        ]
        self.assertEqual(self.hold(), f"human-blocking-comment:{OPERATOR}")

    def test_a_strangers_blocking_text_is_no_hold(self) -> None:
        # #7339 item 4: this repository is public, so anyone can comment.
        gh = self.fake()
        for kind, association in (
            ("issues/5/comments", "NONE"),
            ("pulls/5/reviews", "CONTRIBUTOR"),
            ("pulls/5/comments", "FIRST_TIME_CONTRIBUTOR"),
        ):
            gh.rest[f"repos/{REPO}/{kind}?per_page=100"] = [
                {
                    "user": {"login": "passer-by", "type": "User"},
                    "author_association": association,
                    "body": "do not merge, this is blocking",
                }
            ]
        self.assertIsNone(self.hold())

    def test_the_opt_in_label_removed_since_the_enqueue(self) -> None:
        gh = self.fake()
        gh.rest[f"repos/{REPO}/issues/5/timeline?per_page=100"] = [
            {
                "event": "labeled",
                "label": {"name": policy.OPT_IN_LABEL},
                "created_at": "2026-10-12T09:00:00Z",
            },
            {
                "event": "unlabeled",
                "label": {"name": policy.OPT_IN_LABEL},
                "created_at": "2026-10-12T10:30:00Z",
            },
        ]
        self.assertEqual(self.hold(), "opt-in-label-removed")

    def relabeled(self, actor: dict[str, Any], via_app: Any = None) -> str | None:
        # A human opts in, the entry is queued (10:00), the human revokes the
        # opt-in (10:30), then `actor` puts the label back (10:45).
        gh = self.fake(
            labels={"totalCount": 1, "nodes": [{"name": policy.OPT_IN_LABEL}]}
        )
        label = {"name": policy.OPT_IN_LABEL}
        human = {"login": OPERATOR, "type": "User"}
        gh.rest[f"repos/{REPO}/issues/5/timeline?per_page=100"] = [
            {
                "event": "labeled",
                "label": label,
                "actor": human,
                "created_at": "2026-10-12T09:00:00Z",
            },
            {
                "event": "unlabeled",
                "label": label,
                "actor": human,
                "created_at": "2026-10-12T10:30:00Z",
            },
            {
                "event": "labeled",
                "label": label,
                "actor": actor,
                "performed_via_github_app": via_app,
                "created_at": "2026-10-12T10:45:00Z",
            },
        ]
        return policy.entry_hold(REPO, 5, IDENTITY, permission=HUMANS)

    def test_a_revoked_opt_in_restored_by_a_non_human_is_a_hold(self) -> None:
        # The claude-security-review finding on #7335: presence alone let a bot
        # silently restore a consent the human had withdrawn.
        for name, actor, via_app, hold in (
            (
                "a bot",
                {"login": "some-app[bot]", "type": "Bot"},
                None,
                "opt-in-label:labeler-not-human",
            ),
            (
                "the identity",
                {"login": IDENTITY, "type": "Bot"},
                None,
                "opt-in-label:labeler-not-human",
            ),
            (
                "a human's token through an App",
                {"login": OPERATOR, "type": "User"},
                {"slug": "some-app"},
                "opt-in-label:labeler-via-app",
            ),
        ):
            with self.subTest(name):
                self.assertEqual(self.relabeled(actor, via_app), hold)

    def test_a_removal_the_timeline_shows_beats_the_label_snapshot(self) -> None:
        # The labels were read before a human removed the label; the timeline,
        # read after, already shows the removal (local review of ed841af72).
        gh = self.fake(
            labels={"totalCount": 1, "nodes": [{"name": policy.OPT_IN_LABEL}]}
        )
        label = {"name": policy.OPT_IN_LABEL}
        human = {"login": OPERATOR, "type": "User"}
        gh.rest[f"repos/{REPO}/issues/5/timeline?per_page=100"] = [
            {
                "event": "labeled",
                "label": label,
                "actor": human,
                "created_at": "2026-10-12T09:00:00Z",
            },
            {
                "event": "unlabeled",
                "label": label,
                "actor": human,
                "created_at": "2026-10-12T10:30:00Z",
            },
        ]
        self.assertEqual(
            policy.entry_hold(REPO, 5, IDENTITY, permission=HUMANS),
            "opt-in-label-removed",
        )

    def test_a_revoked_opt_in_restored_by_a_human_is_no_hold(self) -> None:
        self.assertIsNone(self.relabeled({"login": "maintainer", "type": "User"}))

    def test_an_unreadable_entry_is_a_hold(self) -> None:
        self.fake(timelineItems={"nodes": []})
        self.assertEqual(self.hold(), "unreadable")


def queue_fake(
    case: unittest.TestCase, entries: list[dict[str, Any]], merges: list[dict[str, Any]]
) -> GhFake:
    gh = GhFake().install(case)
    gh.graphql["PolicyMergeQueue"] = {
        "repository": {
            "mergeQueue": {"entries": {"totalCount": len(entries), "nodes": entries}}
        }
    }
    gh.graphql["PolicyRecentMerges"] = merge_pages([merges])
    return gh


def merge_pages(pages: list[list[dict[str, Any]]], *, endless: bool = False) -> Any:
    """Answer the merged-PR read one page per cursor: page i+1 at cursor "p<i>"."""

    def answer(variables: dict[str, str]) -> dict[str, Any]:
        index = int(variables["c"][1:]) + 1 if "c" in variables else 0
        more = endless or index + 1 < len(pages)
        page = {
            "pageInfo": {"hasNextPage": more, "endCursor": f"p{index}"},
            "nodes": pages[index] if index < len(pages) else [],
        }
        return {"repository": {"pullRequests": page}}

    return answer


def merged(
    number: int, actor: Any, enqueuer: Any, updated: str = "2026-10-12T09:00:00Z"
) -> dict[str, Any]:
    return {
        "number": number,
        "mergedAt": updated,
        "updatedAt": updated,
        "headRefOid": "c" * 40,
        "mergeCommit": {"oid": "d" * 40},
        "timelineItems": {"nodes": [{"actor": actor, "enqueuer": enqueuer}]},
    }


FLOOR = policy.datetime.fromisoformat("2026-01-01T00:00:00Z")


class InFlight(unittest.TestCase):
    def flight(self, verified: Any = None) -> Any:
        return policy.in_flight(
            REPO,
            agent_identity=IDENTITY,
            permission=HUMANS,
            verified=verified,
            merged_since=FLOOR,
        )

    def test_an_unset_floor_is_not_clear_and_reads_nothing(self) -> None:
        gh = queue_fake(self, [], [])
        result = policy.in_flight(REPO, agent_identity=IDENTITY, permission=HUMANS)
        self.assertEqual((result.clear, result.reason), (False, "merged-since-unset"))
        self.assertEqual(gh.calls, [])

    def test_a_page_without_a_boolean_has_next_page_is_not_clear(self) -> None:
        for info in ({"endCursor": "p0"}, {"hasNextPage": "false", "endCursor": "p0"}):
            with self.subTest(info):
                gh = queue_fake(self, [], [])
                page = {"pageInfo": info, "nodes": []}
                gh.graphql["PolicyRecentMerges"] = {
                    "repository": {"pullRequests": page}
                }
                result = self.flight()
                self.assertFalse(result.clear)
                self.assertTrue(result.reason.startswith("unreadable"), result.reason)

    def test_a_timestamp_without_an_offset_is_not_clear(self) -> None:
        gh = queue_fake(self, [], [])
        naive = merged(2, user(OPERATOR), user(OPERATOR), "2026-10-12T09:00:00")
        gh.graphql["PolicyRecentMerges"] = merge_pages([[naive]])
        result = self.flight()
        self.assertFalse(result.clear)
        self.assertTrue(result.reason.startswith("unreadable"), result.reason)

    def test_clear_with_no_identity_entry_and_only_human_merges(self) -> None:
        queue_fake(
            self,
            [{"enqueuer": user(OPERATOR), "pullRequest": {"number": 3}}],
            [merged(2, user(OPERATOR), user(OPERATOR))],
        )
        result = self.flight()
        self.assertTrue(result.clear, result.reason)

    def test_an_identity_entry_in_the_queue_is_in_flight(self) -> None:
        queue_fake(
            self, [{"enqueuer": bot("agent-lanes"), "pullRequest": {"number": 3}}], []
        )
        self.assertEqual(self.flight().reason, "identity-entry-queued:#3")

    def test_a_non_human_enqueue_is_an_auto_merge_that_must_be_verified(self) -> None:
        for name, actor, enqueuer in (
            ("app actor, null enqueuer", bot("agent-lanes"), None),
            ("human actor, null enqueuer", user(OPERATOR), None),
            ("other bot", bot("github-actions"), None),
        ):
            with self.subTest(name):
                queue_fake(self, [], [merged(2, actor, enqueuer)])
                self.assertEqual(self.flight().reason, "unverified-auto-merge:#2")
                self.assertTrue(self.flight(verified=lambda m: m.number == 2).clear)

    def test_a_queue_bypassing_merge_counts_by_merged_by(self) -> None:
        bypass = merged(2, None, None)
        bypass["timelineItems"] = {"nodes": []}
        for merged_by, reason in (
            (user(OPERATOR), None),
            (None, "unverified-auto-merge:#2"),
            (bot("agent-lanes"), "unverified-auto-merge:#2"),
        ):
            with self.subTest(merged_by=merged_by):
                queue_fake(self, [], [{**bypass, "mergedBy": merged_by}])
                self.assertEqual(self.flight().reason, reason)

    def test_an_auto_merge_past_the_first_page_is_found(self) -> None:
        gh = queue_fake(self, [], [])
        human = merged(2, user(OPERATOR), user(OPERATOR))
        gh.graphql["PolicyRecentMerges"] = merge_pages(
            [[human], [merged(1, bot("agent-lanes"), None, "2026-10-01T09:00:00Z")]]
        )
        self.assertEqual(self.flight().reason, "unverified-auto-merge:#1")

    def test_a_history_longer_than_the_read_bound_is_not_clear(self) -> None:
        gh = queue_fake(self, [], [])
        human = merged(2, user(OPERATOR), user(OPERATOR))
        gh.graphql["PolicyRecentMerges"] = merge_pages([[human]], endless=True)
        self.assertEqual(self.flight().reason, "merged-history-truncated")

    def test_the_read_stops_at_the_merged_since_floor(self) -> None:
        gh = queue_fake(self, [], [])
        human = merged(2, user(OPERATOR), user(OPERATOR))
        older = merged(1, bot("agent-lanes"), None, "2026-09-01T09:00:00Z")
        gh.graphql["PolicyRecentMerges"] = merge_pages([[human], [older]], endless=True)
        floor = policy.datetime.fromisoformat("2026-10-01T00:00:00Z")
        result = policy.in_flight(
            REPO, agent_identity=IDENTITY, permission=HUMANS, merged_since=floor
        )
        self.assertTrue(result.clear, result.reason)
        reads = [c for c in gh.calls if any("PolicyRecentMerges" in a for a in c)]
        # Two pages walked, then page 1 again for a PR that moved mid-read;
        # the endless third page is never read.
        self.assertEqual(len(reads), 3)

    def test_a_merge_that_jumped_to_page_one_mid_read_is_not_clear(self) -> None:
        # Local review of ed841af72: an unverified auto-merge on a later page
        # updated during the walk moves to page 1 behind the cursor.
        gh = queue_fake(self, [], [])
        human = merged(2, user(OPERATOR), user(OPERATOR))
        jumped = merged(1, bot("agent-lanes"), None, "2026-10-01T09:00:00Z")
        older = merged(0, user(OPERATOR), user(OPERATOR), "2025-12-01T09:00:00Z")
        reads: list[str] = []

        def answer(variables: dict[str, str]) -> dict[str, Any]:
            first = "c" not in variables
            reads.append(variables.get("c", "first"))
            if first and len(reads) > 1:
                nodes, more = [jumped, human], True  # the re-read of page 1
            elif first:
                nodes, more = [human], True
            else:
                nodes, more = [older], False  # #1 left this page mid-read
            info = {"hasNextPage": more, "endCursor": "p0"}
            return {"repository": {"pullRequests": {"pageInfo": info, "nodes": nodes}}}

        gh.graphql["PolicyRecentMerges"] = answer
        result = self.flight()
        self.assertFalse(result.clear)
        self.assertTrue(result.reason.startswith("unreadable"), result.reason)

    def test_a_merge_before_the_floor_updated_after_it_is_not_judged(self) -> None:
        # Codex P1 on #7335: a comment on an old bot-queued merge moves its
        # updatedAt past the floor, but it merged before the path was enabled,
        # so the post-merge verdict never judges it and in_flight must not.
        old = merged(2, bot("agent-lanes"), None, "2025-12-01T09:00:00Z")
        old["updatedAt"] = "2026-10-12T09:00:00Z"
        queue_fake(self, [], [old])
        result = self.flight()
        self.assertTrue(result.clear, result.reason)

    def test_an_unreadable_queue_is_not_clear(self) -> None:
        gh = queue_fake(self, [], [])
        gh.graphql["PolicyMergeQueue"] = 502
        self.assertFalse(self.flight().clear)

    def test_an_unconfigured_identity_is_not_clear(self) -> None:
        queue_fake(self, [], [])
        self.assertFalse(
            policy.in_flight(REPO, agent_identity=None, permission=HUMANS).clear
        )


ENABLED_AT = "2026-10-10T00:00:00Z"
IDENTITY_ONLY = {
    "hosts": {
        "github.com": [
            {
                "login": IDENTITY,
                "active": True,
                "host": "github.com",
                "state": "success",
            }
        ]
    }
}


def gate(refusal: str | None = None, verified: Any = None) -> policy.PostMergeGate:
    return policy.PostMergeGate(refusal, {"ok": refusal is None}, verified)


PROMOTED = policy.Promotion(dict.fromkeys(policy.PROMOTABLE_CELLS, "promoted"), None)


class Assess(unittest.TestCase):
    """The readers composed for one pull request, in the wiring order."""

    def fake(self, pipeline: str | None = PIPELINE) -> GhFake:
        gh = config_fake(self, pipeline)
        gh.rest[f"repos/{REPO}/pulls/1"] = {
            "number": 1,
            "base": {"ref": "trunk", "sha": SHA},
            "head": {"ref": "feat", "sha": "e" * 40},
        }
        gh.rest[f"repos/{REPO}"] = {"default_branch": "trunk"}
        return gh

    def readable(self) -> GhFake:
        """Identity-only credentials, kill switch on, no cap, no demotion
        record, and the path enabled since ENABLED_AT."""
        gh = self.fake()
        gh.rest["status"] = IDENTITY_ONLY  # gh auth status --json hosts
        variables = f"repos/{REPO}/actions/variables"
        gh.rest[f"{variables}?per_page=1"] = {"variables": []}
        gh.rest[f"repos/{REPO}/actions/organization-variables?per_page=100"] = {
            "variables": [{"name": "CLAUDE_LANES_DISABLED", "value": "false"}]
        }
        gh.rest[f"{variables}/CLAUDE_LANES_REPO_DISABLED"] = {"value": "false"}
        gh.rest[f"{variables}/CLAUDE_LANES_DISABLED"] = 404
        gh.rest[f"{variables}/CLAUDE_LANES_MERGE_RUNG_CAP"] = 404
        empty = {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": []}
        gh.graphql["PolicyIssuesByAuthor"] = {"repository": {"issues": empty}}
        history = f"repos/{REPO}/commits?sha={SHA}&path=docs%2Fconventions%2Fpr-pipeline.yaml&per_page=100"
        gh.rest[history] = [{"sha": SHA, "commit": {"committer": {"date": ENABLED_AT}}}]
        return gh

    def assess(self, **kwargs: Any) -> policy.UnattendedPolicy:
        kwargs.setdefault("acting_login", IDENTITY)
        return policy.assess(REPO, 1, **kwargs)

    def all_clear(self, work_class: str | None = "C2") -> Any:
        """Patch the in-flight and eligibility readers clear."""
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(
            mock.patch.object(
                policy, "in_flight", return_value=policy.InFlight(True, None)
            )
        )
        stack.enter_context(
            mock.patch.object(
                policy,
                "eligibility",
                return_value=policy.Eligibility(True, None, work_class, ISSUE),
            )
        )
        return stack

    def test_every_input_good_permits_the_merge(self) -> None:
        # The outcome that replaced Phase 6's `merge-unconnected`: nothing refuses.
        self.readable()
        self.all_clear()
        result = self.assess(
            post_merge=lambda floor, who: gate(), promotion=lambda s: PROMOTED
        )
        self.assertIsNone(result.reason)
        self.assertIs(result.enabled, True)
        self.assertIs(result.promoted, True)
        self.assertEqual(result.report()["credentials"], "identity-only")

    def test_config_is_read_at_the_pull_requests_base_sha(self) -> None:
        gh = self.readable()
        self.all_clear()
        self.assess(post_merge=lambda floor, who: gate(), promotion=lambda s: PROMOTED)
        self.assertIn(
            ["api", f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={SHA}"], gh.calls
        )

    def test_the_floor_and_branch_reach_the_post_merge_check_and_in_flight(
        self,
    ) -> None:
        self.readable()
        seen: list[Any] = []
        verified = lambda merge: True  # noqa: E731
        ineligible = policy.Eligibility(False, "fork")
        with (
            mock.patch.object(
                policy, "in_flight", return_value=policy.InFlight(False, "x")
            ) as flight,
            mock.patch.object(policy, "eligibility", return_value=ineligible),
        ):
            result = self.assess(
                post_merge=lambda floor, who: (
                    seen.append((floor, who)) or gate(verified=verified)
                )
            )
        floor = policy.datetime.fromisoformat(ENABLED_AT)
        self.assertEqual(seen, [(floor, IDENTITY)])
        self.assertEqual(flight.call_args.kwargs["branch"], "trunk")
        self.assertEqual(flight.call_args.kwargs["merged_since"], floor)
        self.assertIs(flight.call_args.kwargs["verified"], verified)
        self.assertEqual(result.reason, "in-flight:x")
        self.assertIs(result.enabled, True)

    def test_a_human_clear_of_a_demotion_record_restarts_the_floor(self) -> None:
        self.readable()
        cleared = policy.datetime.fromisoformat("2026-10-11T08:00:00Z")
        seen: list[Any] = []
        with mock.patch.object(
            policy,
            "read_demotion",
            return_value=policy.Demotion(False, None, (9,), cleared, cleared),
        ):
            self.assess(post_merge=lambda floor, who: seen.append(floor) or gate("x"))
        self.assertEqual(seen, [cleared])

    def test_a_post_merge_refusal_stops_before_any_later_read(self) -> None:
        self.readable()
        with mock.patch.object(policy, "in_flight") as flight:
            result = self.assess(post_merge=lambda floor, who: gate("failure:#7"))
        self.assertEqual(result.reason, "post-merge:failure:#7")
        self.assertIs(result.enabled, False)
        flight.assert_not_called()

    def test_a_base_other_than_the_default_branch_refuses_before_any_write(
        self,
    ) -> None:
        # Codex P1 on #7335: the post-merge check, its dispatch and the
        # scheduled full run all judge the default branch, so a merge into any
        # other base would go unjudged. The refusal comes after the kill
        # switch with the identity accepted, so the identity's queued entries
        # can still be held or dequeued (local review of ed841af72).
        for name, answer, reason in (
            ("another branch", {"default_branch": "main"}, "base-not-default:trunk"),
            ("unreadable", 502, "default-branch-unreadable"),
        ):
            with self.subTest(name):
                gh = self.readable()
                gh.rest[f"repos/{REPO}"] = answer
                result = self.assess(post_merge=mock.Mock(side_effect=AssertionError))
                self.assertEqual(result.reason, reason)
                self.assertIs(result.enabled, False)
                self.assertEqual(result.inputs["identity"], IDENTITY)

    def test_the_kill_switch_is_read_before_the_default_branch(self) -> None:
        gh = self.readable()
        gh.rest[f"repos/{REPO}/actions/variables/CLAUDE_LANES_REPO_DISABLED"] = {
            "value": "true"
        }
        gh.rest[f"repos/{REPO}"] = 502
        result = self.assess(post_merge=mock.Mock(side_effect=AssertionError))
        self.assertEqual(result.reason, "kill-switch:repo-switch-not-false")

    def test_without_a_post_merge_check_the_path_refuses(self) -> None:
        self.readable()
        self.assertEqual(self.assess().reason, "post-merge:unchecked")

    def test_the_kill_switch_stops_before_the_post_merge_check(self) -> None:
        gh = self.readable()
        gh.rest[f"repos/{REPO}/actions/variables/CLAUDE_LANES_REPO_DISABLED"] = {
            "value": "true"
        }
        never = mock.Mock(side_effect=AssertionError("must not run"))
        result = self.assess(post_merge=never)
        self.assertEqual(result.reason, "kill-switch:repo-switch-not-false")
        self.assertIs(result.enabled, False)

    def test_another_listed_account_refuses_before_the_kill_switch(self) -> None:
        gh = self.readable()
        operator = {"login": OPERATOR, "active": False, "host": "github.com"}
        gh.rest["status"] = {
            "hosts": {"github.com": [IDENTITY_ONLY["hosts"]["github.com"][0], operator]}
        }
        result = self.assess(post_merge=mock.Mock(side_effect=AssertionError))
        self.assertEqual(result.reason, "credentials:other-account-listed")
        self.assertFalse(any("variables" in " ".join(c) for c in gh.calls))

    def test_a_work_class_above_the_rung_refuses(self) -> None:
        self.readable()
        for work_class in ("C3", "C4", "C5"):
            with self.subTest(work_class=work_class), self.all_clear(work_class):
                result = self.assess(
                    post_merge=lambda floor, who: gate(), promotion=lambda s: PROMOTED
                )
                self.assertEqual(result.reason, f"class-above-rung:{work_class}>C2")
                self.assertIs(result.enabled, True)

    def test_unread_promotion_refuses_but_the_path_stays_enabled(self) -> None:
        self.readable()
        self.all_clear()
        result = self.assess(post_merge=lambda floor, who: gate())
        self.assertEqual(result.reason, "promotion-unqualified:promotion-unread")
        self.assertIs(result.enabled, True)
        self.assertIs(result.promoted, False)

    def test_the_demotion_window_start_reaches_the_promotion_read(self) -> None:
        self.readable()
        self.all_clear()
        created = policy.datetime.fromisoformat("2026-10-11T07:00:00Z")
        seen: list[Any] = []
        with mock.patch.object(
            policy,
            "read_demotion",
            return_value=policy.Demotion(False, None, (9,), created, created),
        ):
            self.assess(
                post_merge=lambda floor, who: gate(),
                promotion=lambda start: seen.append(start) or PROMOTED,
            )
        self.assertEqual(seen, [created])

    def test_no_merge_block_is_authority_unconfigured_with_no_identity(self) -> None:
        self.fake(None)
        result = self.assess()
        self.assertFalse(result.enabled)
        self.assertEqual(
            (result.reason, result.agent_identity), ("authority-unconfigured", None)
        )

    def test_a_configured_identity_is_reported_even_while_inert(self) -> None:
        self.fake(PIPELINE.replace("local-babysit", "pr-merge"))
        result = self.assess()
        self.assertEqual(
            (result.reason, result.agent_identity), ("authority-unconfigured", IDENTITY)
        )

    def test_a_parse_error_refuses_rather_than_hiding_the_identity(self) -> None:
        self.fake("merge:\n  rung: [C2\n")
        with self.assertRaises(policy.PolicyReadError):
            self.assess()

    def test_the_first_failing_reader_is_the_reason(self) -> None:
        gh = self.fake()
        result = self.assess(acting_login=OPERATOR)
        self.assertEqual(result.reason, "acting-login-mismatch")
        self.assertNotIn(["auth", "status", "--json", "hosts"], gh.calls)


class CredentialRefusal(unittest.TestCase):
    """The `gh auth status` chokepoint (plan Phase 13): any account other than
    the identity refuses, every run."""

    def refusal(self, hosts: Any) -> str | None:
        gh = GhFake().install(self)
        gh.rest["status"] = hosts
        return policy.credential_refusal(IDENTITY)

    def test_the_identity_alone_passes(self) -> None:
        self.assertIsNone(self.refusal(IDENTITY_ONLY))

    def test_an_app_token_with_no_login_passes_as_the_active_entry(self) -> None:
        entry = {"login": "", "active": True, "host": "github.com"}
        self.assertIsNone(self.refusal({"hosts": {"github.com": [entry]}}))

    def test_a_second_account_on_any_host_refuses(self) -> None:
        second = {"login": OPERATOR, "active": True, "host": "ghe.example.com"}
        hosts = {**IDENTITY_ONLY["hosts"], "ghe.example.com": [second]}
        self.assertEqual(self.refusal({"hosts": hosts}), "other-account-listed")

    def test_the_operator_active_refuses(self) -> None:
        entry = {"login": OPERATOR, "active": True, "host": "github.com"}
        self.assertEqual(
            self.refusal({"hosts": {"github.com": [entry]}}), "other-account-listed"
        )

    def test_an_inactive_entry_with_no_login_refuses(self) -> None:
        unknown = {"login": "", "active": False, "host": "github.com"}
        hosts = {"github.com": [IDENTITY_ONLY["hosts"]["github.com"][0], unknown]}
        self.assertEqual(self.refusal({"hosts": hosts}), "unknown-account-listed")

    def test_no_entry_or_an_unreadable_status_refuses(self) -> None:
        self.assertEqual(self.refusal({"hosts": {}}), "credentials-unreadable")
        self.assertEqual(self.refusal(1), "credentials-unreadable")


class EnabledSince(unittest.TestCase):
    """The post-merge floor's enabling commit: the oldest commit in the run of
    pipeline-file commits that enable the path."""

    HISTORY = (
        f"repos/{REPO}/commits?sha={SHA}"
        "&path=docs%2Fconventions%2Fpr-pipeline.yaml&per_page=100"
    )

    def commit(self, sha: str, date: str) -> dict[str, Any]:
        return {"sha": sha, "commit": {"committer": {"date": date}}}

    def fake(
        self,
        history: list[dict[str, Any]],
        configs: dict[str, str],
        base: str = SHA,
        clones: tuple[pathlib.Path, ...] = (),
    ) -> GhFake:
        """The commits and contents APIs answering for `base`; `clones` are
        the local clones `enabled_since` may read instead (none by default)."""
        checkouts = mock.patch.object(
            policy, "_history_checkouts", return_value=list(clones)
        )
        checkouts.start()
        self.addCleanup(checkouts.stop)
        gh = GhFake().install(self)
        gh.rest[self.HISTORY.replace(SHA, base)] = history
        for sha, text in configs.items():
            gh.rest[f"repos/{REPO}/contents?ref={sha}"] = []
            gh.rest[f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={sha}"] = (
                file_payload(text)
            )
            gh.rest[f"repos/{REPO}/contents/{policy.SOURCE_CONTROL_PATH}?ref={sha}"] = (
                file_payload(SOURCE_CONTROL)
            )
        return gh

    def test_a_later_edit_that_keeps_it_enabled_does_not_move_the_floor(self) -> None:
        older, oldest = "b" * 40, "c" * 40
        self.fake(
            [
                self.commit(SHA, "2026-10-12T00:00:00Z"),
                self.commit(older, "2026-10-11T00:00:00Z"),
                self.commit(oldest, "2026-10-01T00:00:00Z"),
            ],
            {SHA: PIPELINE, older: PIPELINE, oldest: "merge:\n  rung: C2\n"},
        )
        self.assertEqual(
            policy.enabled_since(REPO, SHA),
            policy.datetime.fromisoformat("2026-10-11T00:00:00Z"),
        )

    def test_a_base_that_does_not_enable_the_path_has_no_floor(self) -> None:
        self.fake(
            [self.commit(SHA, "2026-10-12T00:00:00Z")], {SHA: "merge:\n  rung: C2\n"}
        )
        with self.assertRaises(policy.PolicyReadError):
            policy.enabled_since(REPO, SHA)

    def test_an_enabled_run_longer_than_the_read_has_no_floor(self) -> None:
        history = [self.commit(SHA, "2026-10-12T00:00:00Z")] * 100
        self.fake(history, {})
        enabled = policy.PipelineConfig(
            SHA, "C2", "local-babysit", IDENTITY, 200, (), None
        )
        with (
            mock.patch.object(policy, "read_config_at", return_value=enabled),
            self.assertRaises(policy.PolicyReadError),
        ):
            policy.enabled_since(REPO, SHA)

    def test_an_unreadable_history_has_no_floor(self) -> None:
        self.fake(502, {})  # type: ignore[arg-type]
        with self.assertRaises(policy.PolicyReadError):
            policy.enabled_since(REPO, SHA)


DISABLED = "merge:\n  rung: C2\n"


class LocalEnabledSince(unittest.TestCase):
    """`enabled_since` read from a real local clone holding the base SHA:
    the floor the contents API gives for the same history, with no gh call
    and no 100-commit limit. A clone that is shallow or lacks the base SHA
    leaves the read to the API."""

    commit_record = EnabledSince.commit
    HISTORY = EnabledSince.HISTORY
    fake = EnabledSince.fake

    def setUp(self) -> None:
        self.tmp = pathlib.Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.clone = self.tmp / "clone"
        self.git(self.tmp, "init", "-q", str(self.clone))
        # The lane runs the script from a subdirectory of its checkout.
        self.scripts = self.clone / "scripts"
        self.scripts.mkdir()

    def git(self, root: pathlib.Path, *args: str, date: str = "") -> str:
        env = {"GIT_COMMITTER_DATE": date, "GIT_AUTHOR_DATE": date} if date else {}
        return subprocess.run(
            ["git", "-C", str(root), "-c", "user.name=t", "-c", "user.email=t@t",
             "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", *args],
            check=True, capture_output=True, text=True, env={**os.environ, **env},
        ).stdout.strip()  # fmt: skip

    def commit(self, path: str, text: str | None, date: str) -> str:
        """Commit `text` at `path` (None deletes it) with this committer date."""
        if text is None:
            self.git(self.clone, "rm", "-q", path)
        else:
            (self.clone / path).parent.mkdir(parents=True, exist_ok=True)
            (self.clone / path).write_text(text)
            self.git(self.clone, "add", path)
        self.git(self.clone, "commit", "-q", "-m", date, date=date)
        return self.git(self.clone, "rev-parse", "HEAD")

    def pipeline(self, text: str | None, date: str) -> str:
        return self.commit(policy.CONFIG_PATH, text, date)

    def local(self) -> GhFake:
        """No API answers: any gh call fails the test."""
        return self.fake(
            [], {}, base="0" * 40, clones=(self.tmp / "none", self.scripts)
        )

    def test_the_floor_matches_the_contents_api_for_the_same_history(self) -> None:
        oldest = self.pipeline(DISABLED, "2026-10-01T00:00:00Z")
        older = self.pipeline(PIPELINE, "2026-10-11T02:00:00+02:00")
        self.commit("README.md", "unrelated", "2026-10-11T12:00:00Z")
        newest = self.pipeline(PIPELINE + "# edit\n", "2026-10-12T00:00:00Z")
        base = self.commit("README.md", "unrelated too", "2026-10-13T00:00:00Z")
        expected = policy.datetime.fromisoformat("2026-10-11T00:00:00Z")
        gh = self.local()
        self.assertEqual(policy.enabled_since(REPO, base), expected)
        self.assertEqual(policy.enabled_since(REPO, base, "local-babysit"), expected)
        with self.assertRaises(policy.PolicyReadError):
            policy.enabled_since(REPO, base, "pr-merge")
        self.assertEqual(gh.calls, [])
        # Pin: the contents-API path gives the same floor for this history.
        self.fake(
            [
                self.commit_record(newest, "2026-10-12T00:00:00Z"),
                self.commit_record(older, "2026-10-11T00:00:00Z"),
                self.commit_record(oldest, "2026-10-01T00:00:00Z"),
            ],
            {newest: PIPELINE + "# edit\n", older: PIPELINE, oldest: DISABLED},
            base=base,
        )
        self.assertEqual(policy.enabled_since(REPO, base), expected)

    def test_a_deleted_pipeline_file_ends_the_enabled_run(self) -> None:
        self.pipeline(PIPELINE, "2026-10-01T00:00:00Z")
        self.pipeline(None, "2026-10-05T00:00:00Z")
        base = self.pipeline(PIPELINE, "2026-10-09T00:00:00Z")
        self.local()
        self.assertEqual(
            policy.enabled_since(REPO, base),
            policy.datetime.fromisoformat("2026-10-09T00:00:00Z"),
        )

    def test_more_than_100_enabled_commits_still_have_a_floor(self) -> None:
        # Every commit enables the path, so the walk reaches the first one.
        for n in range(101):
            base = self.pipeline(
                f"{PIPELINE}# {n}\n", f"2026-02-01T00:{n // 60:02d}:{n % 60:02d}Z"
            )
        gh = self.local()
        self.assertEqual(
            policy.enabled_since(REPO, base),
            policy.datetime.fromisoformat("2026-02-01T00:00:00Z"),
        )
        self.assertEqual(gh.calls, [])

    def test_a_shallow_clone_falls_back_to_the_api(self) -> None:
        self.pipeline(PIPELINE, "2026-10-01T00:00:00Z")
        base = self.pipeline(PIPELINE + "# edit\n", "2026-10-11T00:00:00Z")
        shallow = self.tmp / "shallow"
        self.git(
            self.tmp, "clone", "-q", "--depth", "1", self.clone.as_uri(), str(shallow)
        )
        self.fake(
            [self.commit_record(base, "2026-09-01T00:00:00Z")],
            {base: PIPELINE},
            base=base,
            clones=(shallow,),
        )
        self.assertEqual(
            policy.enabled_since(REPO, base),
            policy.datetime.fromisoformat("2026-09-01T00:00:00Z"),
        )

    def test_a_clone_without_the_base_falls_back_to_the_api(self) -> None:
        self.pipeline(PIPELINE, "2026-10-01T00:00:00Z")
        self.fake(
            [self.commit_record(SHA, "2026-09-02T00:00:00Z")],
            {SHA: PIPELINE},
            clones=(self.clone,),
        )
        self.assertEqual(
            policy.enabled_since(REPO, SHA),
            policy.datetime.fromisoformat("2026-09-02T00:00:00Z"),
        )


LANE_PIPELINE = PIPELINE.replace("local-babysit", "pr-merge").replace(
    "  diff-check:",
    "  report-only: true\n  require-verifier-verdict: true\n  diff-check:",
)
MECHANICAL = "work-class: mechanical"
LANE_DENIED = (
    ".github/**",
    "docs/conventions/**",
    "plugins/source-control/skills/babysit-prs/**",
    ".claude/**",
    "plugins/*/skills/**",
    "plugins/*/agents/**",
)


class LaneConfig(unittest.TestCase):
    """`merge.report-only` (plan Phase 1): the lane starts report-only and the
    owner flips it live (D16); anything but true or false keeps it report-only."""

    def test_report_only_is_read(self) -> None:
        config_fake(self, LANE_PIPELINE)
        config = policy.read_config_at(REPO, SHA)
        self.assertEqual((config.authority, config.report_only), ("pr-merge", True))

    def test_absent_is_live_and_an_unknown_value_is_report_only(self) -> None:
        config_fake(self, PIPELINE)
        self.assertIs(policy.read_config_at(REPO, SHA).report_only, False)
        config_fake(
            self, LANE_PIPELINE.replace("report-only: true", "report-only: yes")
        )
        self.assertIs(policy.read_config_at(REPO, SHA).report_only, True)

    def diff_check(self, lines: str) -> Any:
        text = LANE_PIPELINE.replace(
            "    max-changed-lines: 200\n", "".join(f"    {x}\n" for x in lines)
        )
        config_fake(self, text)
        return policy.read_config_at(REPO, SHA)

    def test_the_lane_switches_default_to_off(self) -> None:
        # Owner decision Q624: absent, the floor, the C2 contradictions and
        # both size caps are off.
        config = self.diff_check([])
        self.assertEqual(
            (
                config.high_path_floor,
                config.c2_contradictions,
                config.max_changed_files,
                config.max_changed_lines,
                config.rung,
            ),
            (False, False, None, None, "C2"),
        )

    def test_the_lane_switches_are_read(self) -> None:
        config = self.diff_check(
            [
                "high-path-floor: true",
                "c2-contradictions: true",
                "max-changed-files: 8",
                "max-changed-lines: 400",
            ]
        )
        self.assertEqual(
            (
                config.high_path_floor,
                config.c2_contradictions,
                config.max_changed_files,
                config.max_changed_lines,
            ),
            (True, True, 8, 400),
        )

    def test_an_unreadable_switch_is_on_and_a_bad_cap_is_off(self) -> None:
        config = self.diff_check(["high-path-floor: maybe", "c2-contradictions: 1"])
        self.assertEqual(
            (config.high_path_floor, config.c2_contradictions), (True, True)
        )
        self.assertEqual(len(config.notes), 2)
        config = self.diff_check(["max-changed-files: lots"])
        self.assertEqual((config.rung, config.max_changed_files), ("off", None))


class LaneEligibility(unittest.TestCase):
    """The pr-merge lane's eligibility (merge-criterion plan, Design 1 and 2):
    a pull request the lanes App opened, not a fork or a dependency
    manager's, with exactly one closing issue in this repository and a diff
    touching no denied path, is fixed class C2. No `work-class:` label is
    read, on the issue or the pull request; the verifier verdict, bound to
    that closing issue, is the merge criterion."""

    ISSUE = 41
    TIMELINE = f"repos/{REPO}/issues/41/timeline?per_page=100"
    FILES = f"repos/{REPO}/pulls/7/files?per_page=100"
    COMMENTS = f"repos/{REPO}/issues/41/comments?per_page=100"

    def issue_node(
        self,
        number: int = 41,
        labels: list[str] | None = None,
        repository: str = REPO,
    ) -> dict[str, Any]:
        names = [] if labels is None else labels
        return {
            "number": number,
            "lastEditedAt": None,
            "repository": {"nameWithOwner": repository},
            "labels": {"totalCount": len(names), "nodes": [{"name": n} for n in names]},
        }

    def fake(
        self,
        *,
        labels: list[str] | None = None,
        files: list[str] | None = None,
        pr_labels: list[str] | None = None,
        closing: list[dict[str, Any]] | None = None,
        author: dict[str, str] | None = None,
        base_ref: str = "main",
    ) -> GhFake:
        issues = [self.issue_node(labels=labels)] if closing is None else closing
        names = pr_labels or []
        gh = GhFake().install(self)
        gh.rest[f"repos/{REPO}"] = {"default_branch": "main"}
        gh.graphql["PolicyEligibility"] = {
            "repository": {
                "pullRequest": {
                    "number": 7,
                    "baseRefName": base_ref,
                    "createdAt": PR_CREATED,
                    "lastEditedAt": "2026-10-12T13:00:00Z",
                    "isCrossRepository": False,
                    "author": author or bot("agent-lanes"),
                    "headRepositoryOwner": {"login": "owner"},
                    "labels": {
                        "totalCount": len(names),
                        "nodes": [{"name": n} for n in names],
                    },
                    "closingIssuesReferences": {
                        "totalCount": len(issues),
                        "nodes": issues,
                    },
                }
            }
        }
        self.paths = ["docs/guide.md"] if files is None else files
        gh.rest[self.FILES] = [{"filename": p} for p in self.paths]
        return gh

    def eligibility(self, changed: int | None = None) -> Any:
        pr = {
            "number": 7,
            "base": {"sha": SHA},
            "changed_files": len(self.paths) if changed is None else changed,
        }
        return policy.lane_eligibility(
            REPO,
            7,
            pr=pr,
            denied_paths=LANE_DENIED,
            agent_identity=IDENTITY,
            permission=HUMANS,
        )

    def test_a_lane_pr_whose_issue_has_no_class_label_is_eligible_as_c2(self) -> None:
        gh = self.fake()
        result = self.eligibility()
        self.assertTrue(result.eligible, result.reason)
        self.assertEqual((result.work_class, result.issue), ("C2", 41))
        # No label history and no issue comment is read: the agent-ready
        # label alone admitted the issue, and the fake answers neither call.
        calls = [" ".join(c) for c in gh.calls]
        self.assertFalse(any(self.TIMELINE in c or self.COMMENTS in c for c in calls))

    def test_a_class_label_on_the_issue_or_the_pr_is_ignored(self) -> None:
        # The admitted issues still carrying these labels (#5981, #6821).
        for labels in (
            ["work-class: scoped"],
            ["Work-Class: Structural"],
            [MECHANICAL, "work-class: untrusted-provenance"],
        ):
            with self.subTest(labels=labels):
                self.fake(labels=labels, pr_labels=["work-class: structural"])
                result = self.eligibility()
                self.assertTrue(result.eligible, result.reason)
                self.assertEqual(result.work_class, "C2")

    def test_a_pr_the_lanes_app_did_not_open_is_ineligible(self) -> None:
        # Anyone with write access could name an issue in `Closes #N`.
        for author in (user(OPERATOR), bot("other-app")):
            with self.subTest(author["login"]):
                self.fake(author=author)
                result = self.eligibility()
                self.assertFalse(result.eligible)
                self.assertEqual(result.reason, "not-lane-authored")

    def test_no_or_several_closing_issues_refuse(self) -> None:
        self.fake(closing=[])
        self.assertEqual(self.eligibility().reason, "linked-issues:0")
        self.fake(closing=[self.issue_node(), self.issue_node(number=42)])
        self.assertEqual(self.eligibility().reason, "linked-issues:2")

    def test_a_closing_issue_in_another_repository_refuses(self) -> None:
        self.fake(closing=[self.issue_node(repository="other/repo")])
        self.assertEqual(self.eligibility().reason, "linked-issue-other-repository")

    def test_a_denied_path_pr_refuses(self) -> None:
        for path in (
            ".github/workflows/x.yml",
            "docs/conventions/pr-pipeline.yaml",
            "plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py",
            ".claude/rules/x.md",
            "plugins/foo/skills/bar/SKILL.md",
            "plugins/foo/agents/baz.md",
        ):
            with self.subTest(path):
                self.fake(files=["docs/guide.md", path])
                result = self.eligibility()
                self.assertFalse(result.eligible)
                self.assertEqual(result.reason, f"denied-path:{path}")

    def test_the_live_config_denies_no_path(self) -> None:
        # Owner decision Q624: the live denied-path list is empty, so a lane
        # PR touching the paths it used to deny is eligible.
        live = pathlib.Path(__file__).resolve().parents[6] / policy.CONFIG_PATH
        values = policy._concern_values(
            live.read_text(encoding="utf-8"),
            [("merge.diff-check.denied-paths", True)],
        )
        denied = tuple((values or {}).get("merge.diff-check.denied-paths", ()))
        self.assertEqual(denied, ())
        for path in (
            ".github/workflows/x.yml",
            "docs/conventions/pr-pipeline.yaml",
            "plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py",
            ".claude/rules/x.md",
            "plugins/foo/skills/bar/SKILL.md",
            "plugins/foo/agents/baz.md",
            "plugins/foo/hooks/hooks.json",
            "plugins/foo/.claude-plugin/plugin.json",
            "scripts/check-convention-yaml.sh",
            # The wrapper pr-merge.yml runs under the lane token (#7476 review).
            "plugins/source-control/scripts/source-control-babysit-merge",
        ):
            with self.subTest(path):
                self.fake(files=["docs/guide.md", path])
                result = policy.lane_eligibility(
                    REPO,
                    7,
                    pr={"number": 7, "base": {"sha": SHA}, "changed_files": 2},
                    denied_paths=denied,
                    agent_identity=IDENTITY,
                )
                self.assertTrue(result.eligible, result.reason)
                self.assertEqual(result.work_class, "C2")

    def test_a_renamed_file_from_a_denied_path_refuses(self) -> None:
        gh = self.fake()
        gh.rest[self.FILES] = [
            {"filename": "docs/moved.md", "previous_filename": ".claude/old.md"}
        ]
        self.assertEqual(self.eligibility().reason, "denied-path:.claude/old.md")

    def test_a_file_listing_short_of_the_changed_count_refuses(self) -> None:
        self.fake()
        self.assertEqual(
            self.eligibility(changed=3001).reason, "changed-files-incomplete"
        )

    def test_no_denied_paths_configured_allows_any_path(self) -> None:
        # Owner decision Q624: an empty list is the permissive default.
        self.fake(files=["plugins/source-control/skills/babysit-prs/scripts/x.py"])
        result = policy.lane_eligibility(
            REPO,
            7,
            pr={"number": 7, "base": {"sha": SHA}, "changed_files": 1},
            denied_paths=(),
            agent_identity=IDENTITY,
        )
        self.assertTrue(result.eligible, result.reason)

    def test_no_identity_trusts_no_author(self) -> None:
        self.fake()
        result = policy.lane_eligibility(
            REPO,
            7,
            pr={"number": 7, "base": {"sha": SHA}, "changed_files": 1},
            denied_paths=LANE_DENIED,
            agent_identity=None,
        )
        self.assertEqual(result.reason, "not-lane-authored")

    def test_a_pr_into_another_branch_refuses(self) -> None:
        self.fake(base_ref="release")
        self.assertEqual(self.eligibility().reason, "base-not-default:release")
        self.assertEqual(
            policy.recheck_lane_issue(REPO, 7, issue=41), "base-not-default:release"
        )

    def test_an_unreadable_default_branch_refuses(self) -> None:
        gh = self.fake()
        gh.rest[f"repos/{REPO}"] = 502
        self.assertTrue(self.eligibility().reason.startswith("unreadable:"))
        reason = policy.recheck_lane_issue(REPO, 7, issue=41)
        self.assertTrue(str(reason).startswith("unreadable:"))

    def test_the_enqueue_recheck_reads_the_closing_issue_again(self) -> None:
        def recheck(issue: int | None = 41) -> str | None:
            return policy.recheck_lane_issue(REPO, 7, issue=issue)

        self.fake()
        self.assertIsNone(recheck())
        # A label removed since the eligibility read no longer refuses.
        self.fake(labels=[])
        self.assertIsNone(recheck())
        self.fake(closing=[self.issue_node(number=42)])
        self.assertEqual(recheck(), "closing-issue-changed:41>42")
        self.fake(closing=[])
        self.assertEqual(recheck(), "linked-issues:0")
        self.fake(closing=[self.issue_node(repository="other/repo")])
        self.assertEqual(recheck(), "linked-issue-other-repository")
        # No issue from the eligibility read: nothing to hold the recheck to.
        self.fake()
        self.assertEqual(recheck(None), "closing-issue-changed:None>41")


class LaneEnabledSince(unittest.TestCase):
    """Authority pr-merge reads its own enabled run (plan Design "Lane mode")."""

    HISTORY = EnabledSince.HISTORY
    commit = EnabledSince.commit
    fake = EnabledSince.fake

    def test_authority_pr_merge_reads_its_own_enabled_since(self) -> None:
        older, oldest = "b" * 40, "c" * 40
        self.fake(
            [
                self.commit(SHA, "2026-10-12T00:00:00Z"),
                self.commit(older, "2026-10-11T00:00:00Z"),
                self.commit(oldest, "2026-10-01T00:00:00Z"),
            ],
            {SHA: LANE_PIPELINE, older: LANE_PIPELINE, oldest: PIPELINE},
        )
        expected = policy.datetime.fromisoformat("2026-10-11T00:00:00Z")
        self.assertEqual(policy.enabled_since(REPO, SHA, "pr-merge"), expected)
        self.assertEqual(policy.enabled_since(REPO, SHA), expected)
        with self.assertRaises(policy.PolicyReadError):
            policy.enabled_since(REPO, SHA, "local-babysit")

    def test_pr_merge_without_an_identity_does_not_enable(self) -> None:
        inert = "merge:\n  rung: C2\n  authority: pr-merge\n"
        self.fake([self.commit(SHA, "2026-10-12T00:00:00Z")], {SHA: inert})
        with self.assertRaises(policy.PolicyReadError):
            policy.enabled_since(REPO, SHA, "pr-merge")


class LaneAssess(unittest.TestCase):
    """`assess(authority="pr-merge")`: the lane's own authority, floor,
    eligibility, and no local promotion read (D16)."""

    fake = Assess.fake
    assess = Assess.assess

    def readable(self) -> GhFake:
        gh = Assess.readable(self)
        gh.rest[f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={SHA}"] = file_payload(
            LANE_PIPELINE
        )
        return gh

    def lane_clear(self) -> mock.Mock:
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(
            mock.patch.object(
                policy, "in_flight", return_value=policy.InFlight(True, None)
            )
        )
        lane = stack.enter_context(
            mock.patch.object(
                policy,
                "lane_eligibility",
                return_value=policy.Eligibility(True, None, "C2"),
            )
        )
        stack.enter_context(
            mock.patch.object(policy, "eligibility", side_effect=AssertionError)
        )
        return lane

    def lane_assess(self, **kwargs: Any) -> policy.UnattendedPolicy:
        kwargs.setdefault("lane_kill_switch", "proceed")
        kwargs.setdefault("lane_rung_cap", "")
        return self.assess(authority="pr-merge", **kwargs)

    def unreadable_variables(self) -> GhFake:
        gh = self.readable()
        for path in (
            "actions/variables?per_page=1",
            "actions/organization-variables?per_page=100",
            "actions/variables/CLAUDE_LANES_MERGE_RUNG_CAP",
        ):
            gh.rest[f"repos/{REPO}/{path}"] = 403
        return gh

    def test_an_empty_workflow_cap_allows_the_configured_rung(self) -> None:
        # The variable's own rule: unset (empty in `vars`) is no cap.
        gh = self.unreadable_variables()
        self.lane_clear()
        result = self.lane_assess(post_merge=lambda floor, who: gate())
        self.assertIsNone(result.reason)
        self.assertEqual(result.report()["rung"], "C2")
        self.assertEqual(
            result.report()["rungCap"], {"value": None, "reason": "no-cap"}
        )
        self.assertFalse(any("actions/" in " ".join(c) for c in gh.calls))

    def test_a_workflow_cap_below_the_rung_refuses(self) -> None:
        for cap in ("off", None, "C9", " C2"):
            with self.subTest(cap=cap):
                self.unreadable_variables()
                self.lane_clear()
                result = self.lane_assess(
                    post_merge=lambda floor, who: gate(), lane_rung_cap=cap
                )
                self.assertEqual(result.reason, "rung-off:rungCap")

    def test_a_workflow_cap_at_the_rung_allows_it(self) -> None:
        self.unreadable_variables()
        self.lane_clear()
        result = self.lane_assess(
            post_merge=lambda floor, who: gate(), lane_rung_cap="C3"
        )
        self.assertIsNone(result.reason)

    def test_local_babysit_reads_the_cap_from_the_variables(self) -> None:
        gh = Assess.readable(self)
        gh.rest[f"repos/{REPO}/actions/variables/CLAUDE_LANES_MERGE_RUNG_CAP"] = {
            "value": "off"
        }
        Assess.all_clear(self)
        result = self.assess(
            post_merge=lambda floor, who: gate(),
            promotion=lambda s: PROMOTED,
            lane_rung_cap="",
        )
        self.assertEqual(result.reason, "rung-off:rungCap")

    def test_the_lane_takes_the_kill_switch_from_the_workflow(self) -> None:
        # Owner decision 2026-10-14: the lane token cannot read Actions
        # variables, so the workflow's own kill-switch check is passed in.
        gh = self.readable()
        gh.rest[f"repos/{REPO}/actions/variables?per_page=1"] = 403
        gh.rest[f"repos/{REPO}/actions/organization-variables?per_page=100"] = 403
        self.lane_clear()
        result = self.lane_assess(post_merge=lambda floor, who: gate())
        self.assertEqual(
            result.report()["killSwitch"], {"proceed": True, "reason": "proceed"}
        )
        self.assertFalse(str(result.reason).startswith("kill-switch:"))
        read = " ".join(" ".join(c) for c in gh.calls)
        self.assertNotIn("organization-variables", read)
        self.assertNotIn("CLAUDE_LANES_REPO_DISABLED", read)

    def test_the_lane_refuses_without_the_workflow_kill_switch(self) -> None:
        for value, reason in (
            (None, "kill-switch:lane-value-missing"),
            ("", "kill-switch:lane-value-missing"),
            ("true", "kill-switch:lane-value-not-proceed"),
            ("Proceed", "kill-switch:lane-value-not-proceed"),
            (" proceed", "kill-switch:lane-value-not-proceed"),
        ):
            with self.subTest(value=value):
                self.readable()
                never = mock.Mock(side_effect=AssertionError("must not run"))
                result = self.lane_assess(post_merge=never, lane_kill_switch=value)
                self.assertEqual(result.reason, reason)
                self.assertIs(result.enabled, False)

    def test_local_babysit_ignores_a_passed_kill_switch_value(self) -> None:
        gh = Assess.readable(self)
        gh.rest[f"repos/{REPO}/actions/variables/CLAUDE_LANES_REPO_DISABLED"] = {
            "value": "true"
        }
        result = self.assess(
            post_merge=mock.Mock(side_effect=AssertionError),
            lane_kill_switch="proceed",
        )
        self.assertEqual(result.reason, "kill-switch:repo-switch-not-false")

    def test_the_lane_counts_only_its_own_merges_in_flight(self) -> None:
        # #7481: another App's merge on main is not the lane's.
        self.readable()
        self.lane_clear()
        self.lane_assess(post_merge=lambda floor, who: gate())
        self.assertIs(policy.in_flight.call_args.kwargs["lane_merges_only"], True)

    def test_local_babysit_counts_every_auto_merge_in_flight(self) -> None:
        Assess.readable(self)
        Assess.all_clear(self)
        self.assess(post_merge=lambda floor, who: gate(), promotion=lambda s: PROMOTED)
        self.assertIs(policy.in_flight.call_args.kwargs["lane_merges_only"], False)

    def test_the_lane_permits_without_a_promotion_read(self) -> None:
        self.readable()
        lane = self.lane_clear()
        result = self.lane_assess(
            post_merge=lambda floor, who: gate(),
            promotion=mock.Mock(side_effect=AssertionError("no local promotion")),
        )
        self.assertIsNone(result.reason)
        self.assertIs(result.promoted, True)
        self.assertIs(result.report()["reportOnly"], True)
        self.assertEqual(
            lane.call_args.kwargs["denied_paths"],
            (".github/**", "docs/conventions/pr-pipeline.yaml"),
        )

    def test_the_lane_refuses_when_the_verdict_is_not_required(self) -> None:
        # Design 3: with no class read, the verdict is the merge criterion, so
        # a lane that does not require it has none; absent reads as false.
        key = "  require-verifier-verdict: true\n"
        for value in ("", key.replace("true", "false")):
            with self.subTest(value=value):
                gh = self.readable()
                path = f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={SHA}"
                gh.rest[path] = file_payload(LANE_PIPELINE.replace(key, value))
                self.lane_clear()
                result = self.lane_assess(post_merge=lambda floor, who: gate())
                self.assertEqual(result.reason, "verifier-verdict-not-required")
                self.assertEqual(
                    result.inputs["own_refusal"], "verifier-verdict-not-required"
                )

    def test_authority_pr_merge_reads_its_own_enabled_since(self) -> None:
        self.readable()
        self.lane_clear()
        seen: list[Any] = []
        self.lane_assess(post_merge=lambda floor, who: seen.append(floor) or gate())
        self.assertEqual(seen, [policy.datetime.fromisoformat(ENABLED_AT)])

    def test_the_lane_refuses_a_local_babysit_config(self) -> None:
        gh = self.readable()
        gh.rest[f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={SHA}"] = file_payload(
            PIPELINE
        )
        self.assertEqual(self.lane_assess().reason, "authority-unconfigured")

    def test_local_babysit_refuses_a_pr_merge_config(self) -> None:
        self.readable()
        self.assertEqual(self.assess().reason, "authority-unconfigured")


MAIN_SHA = "c" * 40
CONFIG_SHA = "d" * 40
NEWEST_CONFIG = (
    f"repos/{REPO}/commits?sha={SHA}"
    "&path=docs%2Fconventions%2Fpr-pipeline.yaml&per_page=1"
)


class SharedPostMergeAnswer(unittest.TestCase):
    """`assess(shared=...)`: the pr-merge run's one demotion, floor and
    post-merge answer stands in for each candidate's own reads only while it
    is bound to the default branch head, the base's pipeline-config commit,
    the identity, self logins and lane, and is fresh. The expected decisions
    are the fresh path's own (a pin of the reads it replaces)."""

    readable = LaneAssess.readable
    fake = Assess.fake
    assess = Assess.assess
    lane_assess = LaneAssess.lane_assess

    def bound(self) -> GhFake:
        gh = self.readable()
        gh.rest[f"repos/{REPO}/commits/trunk"] = {"sha": MAIN_SHA}
        gh.rest[NEWEST_CONFIG] = [{"sha": CONFIG_SHA}]
        return gh

    def shared(self, gate_: policy.PostMergeGate, **overrides: Any) -> Any:
        fields: dict[str, Any] = {
            "main_sha": MAIN_SHA,
            "config_sha": CONFIG_SHA,
            "identity": IDENTITY,
            "self_logins": frozenset(),
            "lane_merges_only": True,
            "computed_at": policy.datetime.now(policy.UTC),
            "demotion": policy.Demotion(False, None, ()),
            "floor": policy.datetime.fromisoformat(ENABLED_AT),
            "gate": gate_,
        }
        return policy.SharedPostMerge(**{**fields, **overrides})

    def flight(self) -> mock.Mock:
        patcher = mock.patch.object(
            policy, "in_flight", return_value=policy.InFlight(True, None)
        )
        self.addCleanup(patcher.stop)
        flight = patcher.start()
        lane = mock.patch.object(
            policy,
            "lane_eligibility",
            return_value=policy.Eligibility(True, None, "C2"),
        )
        lane.start()
        self.addCleanup(lane.stop)
        return flight

    def decided(self, result: policy.UnattendedPolicy) -> tuple[Any, ...]:
        details = {
            k: v for k, v in (result.details or {}).items() if k != "postMergeShared"
        }
        return result.reason, result.enabled, result.promoted, details

    def test_a_bound_answer_decides_as_the_fresh_reads_do(self) -> None:
        verified = lambda merge: True  # noqa: E731
        for answer in (gate("failure:canary#7708"), gate(verified=verified)):
            with self.subTest(refusal=answer.refusal):
                self.bound()
                self.flight()
                fresh = self.lane_assess(post_merge=lambda floor, who: answer)
                self.bound()
                flight = self.flight()
                never = mock.Mock(side_effect=AssertionError("read fresh"))
                with (
                    mock.patch.object(policy, "read_demotion", never),
                    mock.patch.object(policy, "enabled_since", never),
                ):
                    reused = self.lane_assess(
                        post_merge=never, shared=self.shared(answer)
                    )
                self.assertEqual(self.decided(reused), self.decided(fresh))
                self.assertEqual(reused.details["postMergeShared"], "used")
                if answer.refusal is None:
                    self.assertIs(flight.call_args.kwargs["verified"], verified)

    def test_an_unbound_answer_is_not_used(self) -> None:
        late = policy.datetime.now(policy.UTC) - policy.timedelta(minutes=31)
        for overrides, rest, reason in (
            ({}, {f"repos/{REPO}/commits/trunk": {"sha": "f" * 40}}, "main-moved"),
            ({}, {f"repos/{REPO}/commits/trunk": 502}, "main-moved"),
            ({}, {NEWEST_CONFIG: [{"sha": "f" * 40}]}, "config-differs"),
            ({}, {NEWEST_CONFIG: 404}, "config-unreadable"),
            ({"identity": "other[bot]"}, {}, "identity-differs"),
            ({"self_logins": frozenset({"x[bot]"})}, {}, "self-logins-differ"),
            ({"lane_merges_only": False}, {}, "lane-differs"),
            ({"computed_at": late}, {}, "stale"),
        ):
            with self.subTest(reason=reason, rest=rest):
                gh = self.bound()
                gh.rest.update(rest)
                self.flight()
                seen: list[Any] = []
                shared = self.shared(gate("failure:canary#1"), **overrides)
                result = self.lane_assess(
                    post_merge=lambda floor, who: seen.append(floor) or gate(),
                    shared=shared,
                )
                self.assertEqual(result.details["postMergeShared"], f"unused:{reason}")
                self.assertEqual(seen, [policy.datetime.fromisoformat(ENABLED_AT)])
                self.assertIsNone(result.reason)

    def test_without_an_answer_the_reads_run_as_before(self) -> None:
        self.readable()
        self.flight()
        seen: list[Any] = []
        result = self.lane_assess(
            post_merge=lambda floor, who: seen.append(floor) or gate()
        )
        self.assertNotIn("postMergeShared", result.details)
        self.assertEqual(seen, [policy.datetime.fromisoformat(ENABLED_AT)])
        self.assertIsNone(result.reason)


class PlainMergeRefusesTheIdentityFromRealConfig(unittest.TestCase):
    """`babysit_merge.py --merge` with the token acting as the configured
    `merge.agent-identity`, read from a real pipeline file through the config
    reader and the shared YAML reader, exits 10 before any evaluation or write."""

    def run_main(self, login: str) -> tuple[int, dict[str, Any]]:
        import contextlib
        import io

        import babysit_merge as merge

        gh = config_fake(self, PIPELINE.replace("local-babysit", "pr-merge"))
        # The config is read at the pull request's base SHA (S4), not main's head.
        gh.rest[f"repos/{REPO}/pulls/1"] = {
            "number": 1,
            "base": {"ref": "main", "sha": SHA},
            "head": {"ref": "feat", "sha": "e" * 40},
        }
        never = mock.Mock(side_effect=AssertionError("must not run"))
        argv = ["babysit_merge.py", f"{REPO}#1", "--allowed-owners", "owner"]
        argv += ["--merge", "--expected-head", "e" * 40]
        out = io.StringIO()
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(merge, "resolve_author", return_value=login),
            mock.patch.object(merge, "evaluate", never),
            mock.patch.object(merge, "gh_capture", never),
            mock.patch.object(merge, "async_merge", never),
            contextlib.redirect_stdout(out),
        ):
            code = merge.main()
        self.assertIn(
            ["api", f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={SHA}"], gh.calls
        )
        return code, json.loads(out.getvalue())

    def test_the_identity_token_is_refused_at_exit_10(self) -> None:
        code, out = self.run_main("Agent-Lanes[bot]")
        self.assertEqual(code, 10)
        self.assertEqual(out["agentIdentity"], IDENTITY)
        self.assertEqual(out["actingLogin"], "Agent-Lanes[bot]")


DEPENDABOT_EMAIL = "49699333+dependabot[bot]@users.noreply.github.com"


def dependabot_commit(
    update_type: str = "semver-minor",
    *,
    name: str = "dependabot[bot]",
    email: str = DEPENDABOT_EMAIL,
    message: str | None = None,
    login: str | None = None,
    sha: str = "d" * 40,
) -> dict[str, Any]:
    version = "2.0.0" if update_type == "semver-major" else "1.3.0"
    message = message or (
        "build(deps): bump x\n\n---\nupdated-dependencies:\n"
        f"- dependency-name: x\n  dependency-version: {version}\n"
        f"  update-type: version-update:{update_type}\n...\n"
    )
    return {
        "sha": sha,
        "author": {"login": login} if login else None,
        "commit": {
            "message": message,
            "author": {"name": name, "email": email},
            "committer": {"email": "noreply@github.com"},
            "verification": {"verified": True},
        },
    }


class DependabotConfig(unittest.TestCase):
    """`merge.dependabot.mode`: absent or unknown is off, so a repository
    that never set it keeps refusing every Dependabot pull request."""

    def test_the_mode_is_read_and_anything_else_is_off(self) -> None:
        for written, mode in (
            (None, "off"),
            ("enforce", "enforce"),
            ("report", "report"),
            ("off", "off"),
            ("yes", "off"),
        ):
            with self.subTest(written=written):
                text = LANE_PIPELINE
                if written is not None:
                    text += f"  dependabot:\n    mode: {written}\n"
                config_fake(self, text)
                self.assertEqual(policy.read_config_at(REPO, SHA).dependabot_mode, mode)


class DependabotEligibility(unittest.TestCase):
    """The pr-merge lane's Dependabot class: tier `auto` on verified
    Dependabot commits with non-major updates, a green `ci-status`, and no
    human blocking comment. No closing issue and no denied paths are read."""

    HEAD = "e" * 40
    COMMITS = f"repos/{REPO}/pulls/7/commits?per_page=100"
    ACTIVITY = (
        f"repos/{REPO}/activity?ref=refs%2Fheads%2Fdependabot%2Fnpm_and_yarn%2Fx-1.3.0"
        "&per_page=100"
    )
    CI = (
        f"repos/{REPO}/commits/{'e' * 40}/check-runs"
        "?check_name=ci-status&filter=latest&per_page=100"
    )

    def fake(
        self,
        *,
        commits: list[dict[str, Any]] | None = None,
        ci: list[dict[str, Any]] | None = None,
        comments: list[dict[str, Any]] | None = None,
        author: dict[str, str] | None = None,
        cross: bool = False,
        pushes: list[dict[str, Any]] | None = None,
        files: list[dict[str, Any]] | None = None,
        review_only: list[dict[str, Any]] | None = None,
        registry: dict[str, Any] | None = None,
    ) -> GhFake:
        gh = GhFake().install(self)
        # The package registry: by default x has never had provenance.
        pages = (
            {
                "https://registry.npmjs.org/x": {
                    "versions": {"1.2.0": {}, "1.3.0": {}},
                    "time": {
                        "1.2.0": "2026-09-01T00:00:00Z",
                        "1.3.0": "2026-10-01T00:00:00Z",
                    },
                }
            }
            if registry is None
            else registry
        )
        self.registry_calls: list[str] = []

        def read(url: str, accept: str) -> Any:
            self.registry_calls.append(url)
            if url not in pages:
                raise OSError(f"HTTP 404 {url}")
            return pages[url]

        patcher = mock.patch.object(policy, "_registry_json", read)
        patcher.start()
        self.addCleanup(patcher.stop)
        gh.rest[f"repos/{REPO}/contents/{POLICY}?ref={SHA}"] = file_payload(
            json.dumps(
                {
                    "autoMerge": {
                        "reviewOnly": [self.entry(dependency="y")]
                        if review_only is None
                        else review_only
                    }
                }
            )
        )
        gh.graphql["PolicyEligibility"] = {
            "repository": {
                "pullRequest": {
                    "number": 7,
                    "isCrossRepository": cross,
                    "author": author or bot("dependabot"),
                    "headRepositoryOwner": {"login": "owner"},
                }
            }
        }
        self.commits = [dependabot_commit()] if commits is None else commits
        gh.rest[self.COMMITS] = self.commits
        runs = [{"status": "completed", "conclusion": "success"}] if ci is None else ci
        gh.rest[self.CI] = {"check_runs": runs}
        gh.rest[f"repos/{REPO}/issues/7/comments?per_page=100"] = comments or []
        gh.rest[f"repos/{REPO}/pulls/7/reviews?per_page=100"] = []
        gh.rest[f"repos/{REPO}/pulls/7/comments?per_page=100"] = []
        # Dependabot pushed the head; the diff is a covered lock file.
        gh.rest[self.ACTIVITY] = (
            [
                {
                    "activity_type": "branch_creation",
                    "after": self.HEAD,
                    "actor": {"login": "dependabot[bot]", "type": "Bot"},
                }
            ]
            if pushes is None
            else pushes
        )
        gh.rest[f"repos/{REPO}/contents/.github/dependabot.yml?ref={SHA}"] = (
            file_payload("updates:\n  - package-ecosystem: npm\n    directory: /\n")
        )
        self.files = [{"filename": "package-lock.json"}] if files is None else files
        gh.rest[f"repos/{REPO}/pulls/7/files?per_page=100"] = self.files
        return gh

    @staticmethod
    def entry(**fields: str) -> dict[str, str]:
        return {
            "repository": REPO,
            "ecosystem": "npm",
            "directory": "/",
            "dependency": "x",
            "reviewed": "2026-10-17",
            "basis": "runs with a secret",
            "control": "docs/x.md#control",
            **fields,
        }

    def eligibility(self, title: str = "build(deps): bump x") -> Any:
        pr = {
            "number": 7,
            "title": title,
            "body": "",
            "commits": len(self.commits),
            "changed_files": len(self.files),
            "base": {"sha": SHA},
            "head": {"sha": self.HEAD, "ref": "dependabot/npm_and_yarn/x-1.3.0"},
            "user": {"login": "dependabot[bot]", "type": "Bot"},
        }
        return policy.dependabot_eligibility(REPO, 7, pr=pr, agent_identity=IDENTITY)

    def marker(
        self, head: str | None = None, verdict: str = "merge", login: str = IDENTITY
    ) -> dict[str, Any]:
        return {
            "id": 9,
            "created_at": "2026-10-16T12:00:00Z",
            "user": {"login": login, "type": "Bot"},
            "body": (
                "<!-- pr-unblock:review-dependency-round "
                f"head={head or self.HEAD} verdict={verdict} run=55-1 -->"
            ),
        }

    def test_a_minor_bump_whose_provenance_changed_waits_for_a_review(self) -> None:
        attested = {"dist": {"attestations": {"url": "u"}}}
        payload = {
            "predicate": {
                "buildDefinition": {
                    "externalParameters": {
                        "workflow": {
                            "repository": "https://github.com/o/x",
                            "path": "w",
                        }
                    }
                }
            }
        }
        packument = {
            "versions": {"1.2.0": attested, "1.3.0": {}},
            "time": {"1.2.0": "2026-09-01T00:00:00Z", "1.3.0": "2026-10-01T00:00:00Z"},
        }
        attestation = {
            "attestations": [
                {
                    "predicateType": "https://slsa.dev/provenance/v1",
                    "bundle": {
                        "dsseEnvelope": {
                            "payload": base64.b64encode(
                                json.dumps(payload).encode()
                            ).decode()
                        }
                    },
                }
            ]
        }
        self.fake(
            registry={
                "https://registry.npmjs.org/x": packument,
                "https://registry.npmjs.org/-/npm/v1/attestations/x@1.2.0": attestation,
            }
        )
        result = self.eligibility()
        self.assertFalse(result.eligible)
        self.assertEqual(
            result.reason,
            "dependabot-review:provenance-missing:x;review-verdict-missing",
        )
        self.assertEqual(result.dependabot.tier, "review")

    def test_an_unreadable_registry_waits_for_a_review(self) -> None:
        self.fake(registry={})
        self.assertEqual(
            self.eligibility().reason,
            "dependabot-review:provenance-unreadable:x;review-verdict-missing",
        )

    def test_a_review_tier_bump_spends_no_registry_read(self) -> None:
        self.fake(commits=[dependabot_commit("semver-major")], registry={})
        self.assertEqual(
            self.eligibility().reason,
            "dependabot-review:major:x;review-verdict-missing",
        )
        self.assertEqual(self.registry_calls, [])

    def test_a_patch_or_minor_bump_on_a_green_ci_status_is_eligible_as_c2(self) -> None:
        for kind in ("semver-patch", "semver-minor"):
            with self.subTest(kind=kind):
                gh = self.fake(commits=[dependabot_commit(kind)])
                result = self.eligibility()
                self.assertTrue(result.eligible, result.reason)
                self.assertEqual(result.work_class, "C2")
                self.assertIsNone(result.issue)
                self.assertEqual(result.dependabot.tier, "auto")
                calls = " ".join(" ".join(c) for c in gh.calls)
                self.assertNotIn("timeline", calls)

    def test_a_major_bump_is_tier_review_and_waits_for_the_verdict(self) -> None:
        self.fake(commits=[dependabot_commit("semver-major")])
        result = self.eligibility()
        self.assertFalse(result.eligible)
        self.assertEqual(
            result.reason, "dependabot-review:major:x;review-verdict-missing"
        )
        self.assertEqual(result.dependabot.tier, "review")

    def test_a_merge_verdict_at_the_current_head_on_green_ci_is_eligible(self) -> None:
        self.fake(commits=[dependabot_commit("semver-major")], comments=[self.marker()])
        result = self.eligibility()
        self.assertTrue(result.eligible, result.reason)
        self.assertEqual(result.work_class, "C2")
        self.assertEqual(
            (result.dependabot.tier, result.dependabot.approved), ("review", "55-1")
        )

    def test_a_verdict_that_does_not_approve_this_head_refuses(self) -> None:
        for comment, why in (
            (self.marker(head="a" * 40), "review-verdict-head-moved"),
            (self.marker(login="other-app[bot]"), "review-verdict-missing"),
            (self.marker(verdict="close"), "review-verdict:close"),
        ):
            with self.subTest(why=why):
                self.fake(
                    commits=[dependabot_commit("semver-major")], comments=[comment]
                )
                result = self.eligibility()
                self.assertFalse(result.eligible)
                self.assertEqual(result.reason, f"dependabot-review:major:x;{why}")

    def test_an_approved_review_still_needs_a_green_ci_status(self) -> None:
        self.fake(
            commits=[dependabot_commit("semver-major")],
            comments=[self.marker()],
            ci=[{"status": "in_progress", "conclusion": None}],
        )
        self.assertEqual(self.eligibility().reason, "ci-status:pending")

    def test_the_lanes_app_fix_commit_counts_only_after_a_review(self) -> None:
        fix = dependabot_commit(
            name="agent-lanes[bot]",
            email="1+agent-lanes[bot]@users.noreply.github.com",
            message="fix: adapt [dependabot skip]",
            login=IDENTITY,
            sha=self.HEAD,
        )
        gh = self.fake(commits=[dependabot_commit(), fix])
        gh.rest[f"repos/{REPO}/commits/{self.HEAD}"] = {
            "files": [{"filename": "src/x.js"}]
        }
        self.assertEqual(self.eligibility().reason, f"commit-not-dependabot:{'e' * 12}")
        pushes = [
            {
                "activity_type": "push",
                "after": self.HEAD,
                "actor": {"login": IDENTITY, "type": "Bot"},
            },
            {
                "activity_type": "branch_creation",
                "after": "d" * 40,
                "actor": {"login": "dependabot[bot]", "type": "Bot"},
            },
        ]
        major = [dependabot_commit("semver-major"), fix]
        fixed = [{"filename": "package-lock.json"}, {"filename": "src/x.js"}]
        gh = self.fake(
            commits=major, comments=[self.marker()], pushes=pushes, files=fixed
        )
        gh.rest[f"repos/{REPO}/commits/{self.HEAD}"] = {
            "files": [{"filename": "src/x.js"}]
        }
        result = self.eligibility()
        self.assertTrue(result.eligible, result.reason)
        # A fix commit may not touch .github/.
        gh = self.fake(
            commits=major, comments=[self.marker()], pushes=pushes, files=fixed
        )
        gh.rest[f"repos/{REPO}/commits/{self.HEAD}"] = {
            "files": [{"filename": ".github/workflows/ci.yml"}]
        }
        self.assertEqual(
            self.eligibility().reason,
            "dependabot-fix-content:.github/workflows/ci.yml",
        )

    def test_an_unreadable_fix_commit_file_list_refuses(self) -> None:
        # Unreadable is not "touches nothing": the .github/ boundary must hold.
        fix = dependabot_commit(
            name="agent-lanes[bot]",
            email="1+agent-lanes[bot]@users.noreply.github.com",
            message="fix: adapt [dependabot skip]",
            login=IDENTITY,
            sha=self.HEAD,
        )
        for answer in (500, {"files": [{"filename": f"f{i}"} for i in range(300)]}):
            with self.subTest(answer=type(answer).__name__):
                gh = self.fake(
                    commits=[dependabot_commit("semver-major"), fix],
                    comments=[self.marker()],
                )
                gh.rest[f"repos/{REPO}/commits/{self.HEAD}"] = answer
                self.assertEqual(
                    self.eligibility().reason,
                    f"unreadable: commit files {self.HEAD[:12]}",
                )

    FOREIGN_PUSH = [
        {
            "activity_type": "push",
            "after": "e" * 40,
            "actor": {"login": "maintainer", "type": "User"},
        },
        {
            "activity_type": "branch_creation",
            "after": "d" * 40,
            "actor": {"login": "dependabot[bot]", "type": "Bot"},
        },
    ]

    def test_bad_provenance_refuses_even_with_a_merge_verdict(self) -> None:
        # A commit's author is text; the pusher is who it is.
        self.fake(pushes=self.FOREIGN_PUSH)
        self.assertEqual(self.eligibility().reason, "pushed-by:maintainer")
        self.fake(pushes=self.FOREIGN_PUSH, comments=[self.marker()])
        self.assertEqual(self.eligibility().reason, "pushed-by:maintainer")
        self.fake(pushes=[], comments=[self.marker()])
        self.assertEqual(self.eligibility().reason, "push-history-incomplete")
        gh = self.fake(comments=[self.marker()])
        gh.rest[self.ACTIVITY] = 403
        self.assertTrue(self.eligibility().reason.startswith("unreadable:"))

    def test_content_beyond_manifests_is_tier_review_not_a_refusal(self) -> None:
        # A rebuilt bundle on a minor bump: the AI review judges it.
        files = [
            {"filename": "package-lock.json"},
            {"filename": "plugins/miro/server/dist/index.min.js"},
        ]
        self.fake(files=files)
        result = self.eligibility()
        self.assertFalse(result.eligible)
        self.assertEqual(result.dependabot.tier, "review")
        self.assertEqual(
            result.reason,
            "dependabot-review:dependabot-content:plugins/miro/server/dist/index.min.js;"
            "review-verdict-missing",
        )
        self.fake(files=files, comments=[self.marker()])
        result = self.eligibility()
        self.assertTrue(result.eligible, result.reason)
        self.assertEqual(result.dependabot.approved, "55-1")
        self.fake(files=files, comments=[self.marker(head="a" * 40)])
        self.assertFalse(self.eligibility().eligible)

    def test_a_review_only_dependency_is_tier_review_whatever_its_version(
        self,
    ) -> None:
        self.fake(review_only=[self.entry(repository="OWNER/Repo")])
        result = self.eligibility()
        self.assertFalse(result.eligible)
        self.assertEqual(result.dependabot.tier, "review")
        self.assertEqual(
            result.reason, "dependabot-review:review-only:x;review-verdict-missing"
        )
        self.fake(review_only=[self.entry()], comments=[self.marker()])
        result = self.eligibility()
        self.assertTrue(result.eligible, result.reason)
        self.assertEqual(result.dependabot.approved, "55-1")

    def test_an_entry_for_another_repo_ecosystem_directory_or_dependency_is_auto(
        self,
    ) -> None:
        for fields in (
            {"repository": "owner/other"},
            {"ecosystem": "pip"},
            {"directory": "/plugins/miro/server"},
            {"dependency": "y"},
        ):
            with self.subTest(fields=fields):
                self.fake(review_only=[self.entry(**fields)])
                result = self.eligibility()
                self.assertTrue(result.eligible, result.reason)
                self.assertEqual(result.dependabot.tier, "auto")

    def test_an_unreadable_policy_sends_every_update_to_review(self) -> None:
        for answer in (404, file_payload("{not json"), file_payload("{}")):
            with self.subTest(answer=answer):
                gh = self.fake()
                gh.rest[f"repos/{REPO}/contents/{POLICY}?ref={SHA}"] = answer
                gh.rest[f"repos/{REPO}/contents?ref={SHA}"] = []
                result = self.eligibility()
                self.assertFalse(result.eligible)
                self.assertEqual(result.dependabot.tier, "review")
                self.assertEqual(
                    result.reason,
                    "dependabot-review:dependabot-policy-unreadable;"
                    "review-verdict-missing",
                )

    def test_a_0x_minor_is_review_and_a_1x_minor_is_auto(self) -> None:
        zero = dependabot_commit(
            message=(
                "bump x\n\n---\nupdated-dependencies:\n- dependency-name: x\n"
                "  dependency-version: 0.4.0\n  update-type: version-update:semver-minor\n...\n"
            )
        )
        self.fake(commits=[zero])
        self.assertEqual(self.eligibility().dependabot.tier, "review")
        self.fake()
        self.assertEqual(self.eligibility().dependabot.tier, "auto")

    def test_a_commit_not_dependabots_is_refused(self) -> None:
        pushed = dependabot_commit(name="octocat", email="octocat@example.com")
        self.fake(commits=[dependabot_commit(), pushed])
        result = self.eligibility()
        self.assertFalse(result.eligible)
        self.assertEqual(result.reason, f"commit-not-dependabot:{'d' * 12}")

    def test_a_red_ci_status_is_tier_review(self) -> None:
        self.fake(ci=[{"status": "completed", "conclusion": "failure"}])
        result = self.eligibility()
        self.assertFalse(result.eligible)
        self.assertEqual(
            result.reason, "dependabot-review:ci-status-red;review-verdict-missing"
        )
        self.assertEqual(result.dependabot.tier, "review")

    def test_a_running_or_missing_ci_status_waits_at_tier_auto(self) -> None:
        for runs in ([], [{"status": "in_progress", "conclusion": None}]):
            with self.subTest(runs=runs):
                self.fake(ci=runs)
                result = self.eligibility()
                self.assertFalse(result.eligible)
                self.assertEqual(result.reason, "ci-status:pending")
                self.assertEqual(result.dependabot.tier, "auto")

    def test_a_human_hold_comment_refuses(self) -> None:
        hold = {
            "user": {"login": "maintainer", "type": "User"},
            "author_association": "MEMBER",
            "body": "Do not merge this one yet",
        }
        self.fake(comments=[hold])
        result = self.eligibility()
        self.assertFalse(result.eligible)
        self.assertEqual(result.reason, "human-blocking-comment:maintainer")

    def test_a_fork_or_another_author_is_ineligible(self) -> None:
        self.fake(cross=True)
        self.assertEqual(self.eligibility().reason, "fork")
        self.fake(author=bot("renovate"))
        self.assertEqual(self.eligibility().reason, "not-dependabot-authored")

    def test_a_commit_list_short_of_the_pull_requests_count_is_ineligible(self) -> None:
        self.fake()
        self.commits = [dependabot_commit(), dependabot_commit()]
        self.assertEqual(self.eligibility().reason, "commits-listed:1-of:2")


class DependabotAssess(unittest.TestCase):
    """`assess(authority="pr-merge")` on a Dependabot pull request: its own
    eligibility and its own report-only, `merge.dependabot.mode`."""

    readable = LaneAssess.readable
    fake = Assess.fake

    def assess_mode(
        self, mode: str | None, eligible: Any = None, pipeline: str = LANE_PIPELINE
    ) -> Any:
        gh = self.readable()
        text = pipeline + (f"  dependabot:\n    mode: {mode}\n" if mode else "")
        gh.rest[f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={SHA}"] = file_payload(
            text
        )
        gh.rest[f"repos/{REPO}/pulls/1"]["user"] = {
            "login": "dependabot[bot]",
            "type": "Bot",
        }
        tier = policy.dependabot.Classification("auto")
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(
            mock.patch.object(
                policy, "in_flight", return_value=policy.InFlight(True, None)
            )
        )
        self.read = stack.enter_context(
            mock.patch.object(
                policy,
                "dependabot_eligibility",
                return_value=eligible
                or policy.Eligibility(True, None, "C2", dependabot=tier),
            )
        )
        for other in ("lane_eligibility", "eligibility"):
            stack.enter_context(
                mock.patch.object(policy, other, side_effect=AssertionError)
            )
        return policy.assess(
            REPO,
            1,
            acting_login=IDENTITY,
            authority="pr-merge",
            post_merge=lambda floor, who: gate(),
            lane_kill_switch="proceed",
            lane_rung_cap="",
        )

    def test_enforce_merges_while_the_lane_is_report_only(self) -> None:
        result = self.assess_mode("enforce")
        self.assertIsNone(result.reason)
        self.assertIs(result.report()["reportOnly"], False)
        self.assertEqual(result.report()["dependabot"]["tier"], "auto")

    def test_a_dependabot_pr_needs_no_verdict_key(self) -> None:
        # Its tier and ci-status are its criterion, not the verifier verdict.
        pipeline = LANE_PIPELINE.replace("  require-verifier-verdict: true\n", "")
        self.assertIsNone(self.assess_mode("enforce", pipeline=pipeline).reason)

    def test_report_writes_nothing_and_off_refuses(self) -> None:
        self.assertIs(self.assess_mode("report").report()["reportOnly"], True)
        result = self.assess_mode(None)
        self.assertEqual(result.reason, "ineligible:dependabot-merge-off")
        self.read.assert_not_called()

    def test_tier_review_is_refused(self) -> None:
        tier = policy.dependabot.Classification("review", ("major:x",))
        result = self.assess_mode(
            "enforce",
            policy.Eligibility(False, "dependabot-review:major:x", dependabot=tier),
        )
        self.assertEqual(result.reason, "ineligible:dependabot-review:major:x")

    def test_the_rung_still_binds_the_class(self) -> None:
        self.readable()
        result = None
        with mock.patch.object(
            policy, "rung_cap", return_value=policy.RungCap("off", "x")
        ):
            result = self.assess_mode("enforce")
        self.assertEqual(result.reason, "rung-off:rungCap")


if __name__ == "__main__":
    unittest.main()

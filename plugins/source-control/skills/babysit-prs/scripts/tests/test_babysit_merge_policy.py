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
import json
import pathlib
import subprocess
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy

REPO = "owner/repo"
SHA = "a" * 40
IDENTITY = "agent-lanes[bot]"
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
            "PATH": r"C:\Windows\Sysnative;C:\Users\u\AppData\Local\Microsoft\WindowsApps"
        }
        files = {
            r"C:\Windows\Sysnative\bash.exe",
            r"C:\Users\u\AppData\Local\Microsoft\WindowsApps\bash.exe",
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
        "timelineItems": {"nodes": [{"actor": user(OPERATOR), "closer": None}]},
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
        self.assertEqual(len(reads), 2)

    def test_an_unreadable_queue_is_not_clear(self) -> None:
        gh = queue_fake(self, [], [])
        gh.graphql["PolicyMergeQueue"] = 502
        self.assertFalse(self.flight().clear)

    def test_an_unconfigured_identity_is_not_clear(self) -> None:
        queue_fake(self, [], [])
        self.assertFalse(
            policy.in_flight(REPO, agent_identity=None, permission=HUMANS).clear
        )


class Assess(unittest.TestCase):
    """The readers composed; every outcome stays inert in this phase."""

    def fake(self, pipeline: str | None = PIPELINE) -> GhFake:
        gh = config_fake(self, pipeline)
        return gh

    def test_no_merge_block_is_authority_unconfigured_with_no_identity(self) -> None:
        self.fake(None)
        result = policy.assess(REPO, base_sha=SHA)
        self.assertFalse(result.enabled)
        self.assertEqual(
            (result.reason, result.agent_identity), ("authority-unconfigured", None)
        )

    def test_a_configured_identity_is_reported_even_while_inert(self) -> None:
        self.fake(PIPELINE.replace("local-babysit", "pr-merge"))
        result = policy.assess(REPO, base_sha=SHA)
        self.assertEqual(
            (result.reason, result.agent_identity), ("authority-unconfigured", IDENTITY)
        )

    def test_a_parse_error_refuses_rather_than_hiding_the_identity(self) -> None:
        self.fake("merge:\n  rung: [C2\n")
        with self.assertRaises(policy.PolicyReadError):
            policy.assess(REPO, base_sha=SHA)

    def test_the_first_failing_reader_is_the_reason(self) -> None:
        self.fake()
        result = policy.assess(REPO, base_sha=SHA, acting_login=OPERATOR)
        self.assertEqual(result.reason, "acting-login-mismatch")

    def test_with_no_floor_yet_the_in_flight_reader_refuses(self) -> None:
        gh = self.fake()
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
        result = policy.assess(REPO, base_sha=SHA, acting_login=IDENTITY)
        self.assertFalse(result.enabled)
        self.assertEqual(result.reason, "in-flight:merged-since-unset")
        report = result.report()
        self.assertEqual(report["rung"], "C2")
        self.assertIs(report["killSwitch"]["proceed"], True)


class PlainMergeRefusesTheIdentityFromRealConfig(unittest.TestCase):
    """`babysit_merge.py --merge` with the token acting as the configured
    `merge.agent-identity`, read from a real pipeline file through the config
    reader and the shared YAML reader, exits 10 before any evaluation or write.
    `resolve` is pointed at `assess` so the test holds before and after the
    two are wired together."""

    def run_main(self, login: str) -> tuple[int, dict[str, Any]]:
        import contextlib
        import io

        import babysit_merge as merge

        gh = config_fake(self, PIPELINE.replace("local-babysit", "pr-merge"))
        gh.rest[f"repos/{REPO}"] = {"default_branch": "main"}
        gh.rest[f"repos/{REPO}/commits/main"] = {"sha": SHA}
        never = mock.Mock(side_effect=AssertionError("must not run"))
        argv = ["babysit_merge.py", f"{REPO}#1", "--allowed-owners", "owner"]
        argv += ["--merge", "--expected-head", "e" * 40]
        out = io.StringIO()
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(policy, "resolve", policy.assess),
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


if __name__ == "__main__":
    unittest.main()

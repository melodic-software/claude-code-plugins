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
import dataclasses
import io
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
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

import babysit_gh  # noqa: E402
import babysit_merge_policy as policy  # noqa: E402  (follows the git-env clear above)
import babysit_postmerge  # noqa: E402

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
TEAM_YAML = "docs/conventions/source-control.yaml"


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


class RawText(str):
    """A REST answer gh prints as it is: a raw-media-type file read."""


class GhFake:
    """A gh seam answering REST endpoints and named GraphQL operations.

    `rest` maps an endpoint to a payload, a `RawText` printed as it is, or to
    an int HTTP status for a failure. `graphql` maps an operation name to a payload or to a callable of
    the query's string variables, which may return a whole gh result. Any other call fails the test,
    except a read of the team `docs/conventions/source-control.yaml` no test set: that file is
    absent from a readable tree, so a fixture written before it existed stays a legacy-only repo.
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
                    got = answer(variables) if callable(answer) else answer
                    if isinstance(got, subprocess.CompletedProcess):
                        return got
                    return ok({"data": got})
            raise AssertionError(f"unexpected graphql call: {query[:80]}")
        endpoint = args[1]
        if endpoint not in self.rest:
            prefix, _, ref = endpoint.partition(f"/contents/{TEAM_YAML}?ref=")
            if ref:
                self.rest.setdefault(f"{prefix}/contents?ref={ref}", [])
                return http_error(404)
            raise AssertionError(f"unexpected gh call: {args}")
        answer = self.rest[endpoint]
        if isinstance(answer, int):
            return http_error(answer)
        if isinstance(answer, RawText):
            return subprocess.CompletedProcess([], 0, str(answer), "")
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
    team: str | int | None = None,
) -> GhFake:
    """Contents reads at SHA: text, an HTTP status, or None for an absent file."""
    gh = GhFake().install(case)
    gh.rest[f"repos/{REPO}/contents?ref={SHA}"] = []
    for path, value in (
        (policy.CONFIG_PATH, pipeline),
        (policy.SOURCE_CONTROL_PATH, source),
        (TEAM_YAML, team),
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

    def test_max_in_flight_defaults_to_one_and_reads_a_count(self) -> None:
        for text, expected, noted in (
            (PIPELINE, 1, False),
            (PIPELINE.replace("merge:\n", "merge:\n  max-in-flight: 5\n"), 5, False),
            (PIPELINE.replace("merge:\n", "merge:\n  max-in-flight: 0\n"), 1, True),
            (PIPELINE.replace("merge:\n", "merge:\n  max-in-flight: two\n"), 1, True),
        ):
            with self.subTest(expected=expected, noted=noted):
                config_fake(self, text)
                config = policy.read_config_at(REPO, SHA)
                self.assertEqual(config.max_in_flight, expected)
                self.assertEqual(config.rung, "C2")
                self.assertEqual(any("max-in-flight" in n for n in config.notes), noted)

    def test_max_queue_ejections_defaults_to_two_and_reads_a_count(self) -> None:
        def with_cap(value: str) -> str:
            return PIPELINE.replace(
                "merge:\n", f"merge:\n  max-queue-ejections: {value}\n"
            )

        for text, expected, noted in (
            (PIPELINE, 2, False),
            (with_cap("3"), 3, False),
            (with_cap(str(policy.MAX_QUEUE_EJECTIONS_LIMIT)), 20, False),
            (with_cap("0"), 2, True),
            (with_cap(str(policy.MAX_QUEUE_EJECTIONS_LIMIT + 1)), 2, True),
            (with_cap("two"), 2, True),
        ):
            with self.subTest(text=text):
                config_fake(self, text)
                config = policy.read_config_at(REPO, SHA)
                self.assertEqual(config.max_queue_ejections, expected)
                self.assertEqual(config.rung, "C2")
                self.assertEqual(
                    any("max-queue-ejections" in n for n in config.notes), noted
                )

    def test_max_verify_fails_defaults_to_three_and_a_bad_value_is_one(
        self,
    ) -> None:
        # Owner decision 2026-10-21: 3 by default; a value that is not a
        # count of at least 1 fails closed, so any earlier FAIL holds.
        def with_cap(value: str) -> str:
            return PIPELINE.replace(
                "merge:\n", f"merge:\n  max-verify-fails: {value}\n"
            )

        for text, expected, noted in (
            (PIPELINE, 3, False),
            (with_cap("1"), 1, False),
            (with_cap("5"), 5, False),
            (with_cap("0"), 1, True),
            (with_cap("-3"), 1, True),
            (with_cap("three"), 1, True),
            # Present but empty or not a scalar: the shared reader prints
            # nothing for these, as for an absent key.
            (with_cap("''"), 1, True),
            (with_cap("[]"), 1, True),
            (with_cap("[3]"), 1, True),
            (with_cap(""), 1, True),
            (with_cap("\n    a: 1"), 1, True),
            (with_cap("\n    - 3"), 1, True),
            # A key of that name in another mapping is not the setting.
            (
                PIPELINE.replace(
                    "diff-check:\n", "diff-check:\n    max-verify-fails:\n"
                ),
                3,
                False,
            ),
        ):
            with self.subTest(text=text):
                config_fake(self, text)
                config = policy.read_config_at(REPO, SHA)
                self.assertEqual(config.max_verify_fails, expected)
                self.assertEqual(config.rung, "C2")
                self.assertEqual(
                    any("max-verify-fails" in n for n in config.notes), noted
                )

    def test_a_flow_mapping_max_verify_fails_turns_the_lane_off(self) -> None:
        # The shared reader's subset rejects any flow mapping, empty or not,
        # so the whole config is unread and the lane is off.
        for value in ("{}", "{a: 1}"):
            with self.subTest(value=value):
                config_fake(
                    self,
                    PIPELINE.replace(
                        "merge:\n", f"merge:\n  max-verify-fails: {value}\n"
                    ),
                )
                config = policy.read_config_at(REPO, SHA)
                self.assertEqual(
                    (config.rung, config.error), ("off", "config-parse-error")
                )

    def test_risk_escalation_minutes_defaults_to_sixty_and_reads_minutes(
        self,
    ) -> None:
        def with_minutes(value: str) -> str:
            return PIPELINE.replace(
                "merge:\n", f"merge:\n  risk-escalation-minutes: {value}\n"
            )

        for text, expected, noted in (
            (PIPELINE, 60, False),
            (with_minutes("0"), 0, False),
            (with_minutes("90"), 90, False),
            (with_minutes("-5"), 60, True),
            (with_minutes("an hour"), 60, True),
        ):
            with self.subTest(text=text):
                config_fake(self, text)
                config = policy.read_config_at(REPO, SHA)
                self.assertEqual(config.risk_escalation_minutes, expected)
                self.assertEqual(config.rung, "C2")
                self.assertEqual(
                    any("risk-escalation-minutes" in n for n in config.notes), noted
                )

    def test_check_inputs_reads_a_path_list_and_is_empty_when_absent(self) -> None:
        listed = PIPELINE.replace(
            "merge:\n",
            "merge:\n  check-inputs:\n    - scripts/shared-copies.txt\n"
            "    - scripts/docs-only-paths.txt\n",
        )
        for text, expected in (
            (PIPELINE, ()),
            (listed, ("scripts/shared-copies.txt", "scripts/docs-only-paths.txt")),
        ):
            with self.subTest(expected=expected):
                config_fake(self, text)
                self.assertEqual(
                    policy.read_config_at(REPO, SHA).check_inputs, expected
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

    def test_the_lower_of_the_team_yaml_and_the_legacy_file_reaches_the_gate(
        self,
    ) -> None:
        loose = "## babysit_loop_merge\n\nc3-autonomous\n"
        for team, source, expected in (
            # A demotion written only to the YAML holds the gate.
            ("babysit_loop_merge: human-only\n", SOURCE_CONTROL, "human-only"),
            # A demotion written only to the legacy file still holds it.
            ("babysit_loop_merge: c3-autonomous\n", SOURCE_CONTROL, "c2-mechanical"),
            ("babysit_loop_merge: c2-mechanical\n", loose, "c2-mechanical"),
            # One file alone supplies the value.
            ("babysit_loop_merge: c2-mechanical\n", None, "c2-mechanical"),
            (None, SOURCE_CONTROL, "c2-mechanical"),
            ("babysit_loop_stop_mode: standing\n", SOURCE_CONTROL, "c2-mechanical"),
            (None, None, None),
        ):
            with self.subTest(team=team, source=source):
                config_fake(self, PIPELINE, source, team)
                config = policy.read_config_at(REPO, SHA)
                self.assertEqual(config.loop_merge, expected)
                self.assertEqual(config.notes, ())

    def test_an_untrustworthy_team_yaml_holds_the_gate_over_the_legacy_value(
        self,
    ) -> None:
        for team, noted in (
            ("babysit_loop_merge: {a: b}\n", "rejects it"),
            ("babysit_loop_merge:\n  - human-only\n", "not a scalar value"),
            ("babysit_loop_merge: c3-this-run\n", "not a known value"),
            (502, "unreadable"),
        ):
            with self.subTest(team=team):
                config_fake(self, PIPELINE, SOURCE_CONTROL, team)
                config = policy.read_config_at(REPO, SHA)
                self.assertIsNone(config.loop_merge)
                self.assertTrue(any(noted in n for n in config.notes), config.notes)

    def test_an_untrustworthy_legacy_file_holds_the_gate_over_the_team_value(
        self,
    ) -> None:
        team = "babysit_loop_merge: c3-autonomous\n"
        for source in (
            502,
            SOURCE_CONTROL + "\n## babysit_loop_merge\n\nhuman-only\n",
            "## babysit_loop_merge\n\n## next\n",
        ):
            with self.subTest(source=source):
                config_fake(self, PIPELINE, source, team)
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
        # A write-access human wrote it, so it is vouched for (`_vouch_refusal`).
        "author": user(OPERATOR),
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


def eligibility(admission: str = "agent-ready") -> Any:
    return policy.eligibility(
        REPO, 7, agent_identity=IDENTITY, permission=HUMANS, admission=lambda: admission
    )


OUTSIDER = "outsider"


class IssueVouch(unittest.TestCase):
    """The local gate merges only work a human vouched for: a write-access
    human wrote the linked issue, or one applied the admission label in
    person with no body edit after it."""

    TIMELINE = f"repos/{REPO}/issues/{ISSUE}/timeline?per_page=100"

    def outside_issue(
        self, labels: list[str], labeler: dict[str, str], edited: str | None = None
    ) -> GhFake:
        gh = eligibility_fake(
            self,
            issue={
                "author": user(OUTSIDER),
                "lastEditedAt": edited,
                "labels": {
                    "totalCount": len(labels),
                    "nodes": [{"name": n} for n in labels],
                },
            },
        )
        gh.rest[self.TIMELINE] = [
            {
                "event": "labeled",
                "label": {"name": n},
                "actor": labeler,
                "created_at": "2026-10-11T09:00:00Z",
            }
            for n in labels
        ]
        return gh

    def test_a_human_authored_issue_passes(self) -> None:
        eligibility_fake(self, issue={"labels": {"totalCount": 0, "nodes": []}})
        self.assertTrue(eligibility().eligible)

    def test_an_untriaged_outside_issue_is_refused(self) -> None:
        self.outside_issue([], {"login": OPERATOR, "type": "User"})
        self.assertEqual(
            eligibility().reason,
            "issue-not-vouched:no-human-author-or-admission-label",
        )

    def test_an_outside_issue_labeled_by_the_lane_identity_is_refused(self) -> None:
        self.outside_issue(["agent-ready"], {"login": IDENTITY, "type": "Bot"})
        self.assertEqual(eligibility().reason, "issue-not-vouched:labeler-not-human")

    def test_an_outside_issue_a_human_labeled_agent_ready_passes(self) -> None:
        self.outside_issue(["Agent-Ready"], {"login": OPERATOR, "type": "User"})
        result = eligibility()
        self.assertTrue(result.eligible, result.reason)

    def test_a_body_edit_after_the_label_is_refused(self) -> None:
        self.outside_issue(
            ["agent-ready"],
            {"login": OPERATOR, "type": "User"},
            edited="2026-10-11T10:00:00Z",
        )
        self.assertEqual(
            eligibility().reason, "issue-not-vouched:body-edited-after-label"
        )

    def test_the_admission_label_is_the_resolved_one(self) -> None:
        # A tracker that maps the role elsewhere: the default name no longer
        # vouches, the mapped one does.
        self.outside_issue(["agent-ready"], {"login": OPERATOR, "type": "User"})
        self.assertEqual(
            eligibility("ready-for-agent").reason,
            "issue-not-vouched:no-human-author-or-admission-label",
        )
        self.outside_issue(["ready-for-agent"], {"login": OPERATOR, "type": "User"})
        self.assertTrue(eligibility("ready-for-agent").eligible)

    def test_the_admission_label_reads_the_tracker_config(self) -> None:
        gh = GhFake().install(self)
        path = f"repos/{REPO}/contents/.work-item-tracker.json?ref=main"
        mapped = {"config": {"role_labels": {"autonomous-eligible": "go"}}}
        gh.rest[path] = {
            "type": "file",
            "encoding": "base64",
            "content": base64.b64encode(json.dumps(mapped).encode()).decode(),
        }
        self.assertEqual(policy.admission_label("owner", "repo", "main"), "go")
        gh.rest[path] = 404
        gh.rest[f"repos/{REPO}/contents?ref=main"] = []
        self.assertEqual(policy.admission_label("owner", "repo", "main"), "agent-ready")

    def test_an_admission_label_applied_through_an_app_is_refused(self) -> None:
        gh = self.outside_issue(["agent-ready"], {"login": OPERATOR, "type": "User"})
        gh.rest[self.TIMELINE][0]["performed_via_github_app"] = {"slug": "agent"}
        self.assertEqual(eligibility().reason, "issue-not-vouched:labeler-via-app")

    def test_an_admission_label_from_a_read_only_person_is_refused(self) -> None:
        self.outside_issue(["agent-ready"], {"login": "reader", "type": "User"})
        self.assertEqual(eligibility().reason, "issue-not-vouched:labeler-not-human")

    def test_a_failed_timeline_read_refuses(self) -> None:
        gh = self.outside_issue(["agent-ready"], {"login": OPERATOR, "type": "User"})
        gh.rest[self.TIMELINE] = 502
        result = eligibility()
        self.assertFalse(result.eligible)
        self.assertTrue(result.reason.startswith("unreadable:"), result.reason)

    def test_a_title_rename_after_the_label_is_refused(self) -> None:
        gh = self.outside_issue(["agent-ready"], {"login": OPERATOR, "type": "User"})
        gh.rest[self.TIMELINE].append(
            {
                "event": "renamed",
                "actor": {"login": OUTSIDER, "type": "User"},
                "rename": {"from": "Fix a typo", "to": "Rewrite the merge gate"},
                "created_at": "2026-10-11T10:00:00Z",
            }
        )
        self.assertEqual(
            eligibility().reason, "issue-not-vouched:title-edited-after-label"
        )
        # A rename before the label is what the labeler read: it vouches.
        gh.rest[self.TIMELINE][-1]["created_at"] = "2026-10-11T08:00:00Z"
        self.assertTrue(eligibility().eligible)

    def test_a_retitle_with_no_recorded_actor_is_refused(self) -> None:
        # A title edit leaves `lastEditedAt` empty, and a `renamed` event
        # with no actor is not shown to be a person's.
        gh = eligibility_fake(self, issue={"labels": {"totalCount": 0, "nodes": []}})
        gh.rest[self.TIMELINE] = [
            {
                "event": "renamed",
                "actor": None,
                "rename": {"from": "Fix a typo", "to": "Rewrite the merge gate"},
                "created_at": "2026-10-11T10:00:00Z",
            }
        ]
        self.assertEqual(
            eligibility().reason, "issue-not-vouched:title-edited-by-non-human"
        )

    def test_a_human_relabel_after_a_non_human_retitle_vouches(self) -> None:
        gh = eligibility_fake(
            self,
            issue={"labels": {"totalCount": 1, "nodes": [{"name": "agent-ready"}]}},
        )
        gh.rest[self.TIMELINE] = [
            {
                "event": "renamed",
                "actor": {"login": "agent-lanes[bot]", "type": "Bot"},
                "rename": {"from": "Fix a typo", "to": "Rewrite the merge gate"},
                "created_at": "2026-10-11T10:00:00Z",
            },
            {
                "event": "labeled",
                "label": {"name": "agent-ready"},
                "actor": {"login": OPERATOR, "type": "User"},
                "created_at": "2026-10-11T11:00:00Z",
            },
        ]
        result = eligibility()
        self.assertTrue(result.eligible, result.reason)
        # A label applied before the retitle did not see it.
        gh.rest[self.TIMELINE][1]["created_at"] = "2026-10-11T09:00:00Z"
        self.assertEqual(
            eligibility().reason, "issue-not-vouched:title-edited-by-non-human"
        )

    def test_an_admission_label_with_no_labeled_event_is_refused(self) -> None:
        gh = self.outside_issue(["agent-ready"], {"login": OPERATOR, "type": "User"})
        gh.rest[self.TIMELINE] = []
        self.assertEqual(eligibility().reason, "issue-not-vouched:no-labeled-event")
        # Past a provenance read that passes, an empty timeline still refuses
        # rather than raising out of the rename check.
        with mock.patch.object(policy, "_label_provenance", return_value=None):
            self.assertEqual(eligibility().reason, "issue-not-vouched:no-labeled-event")

    def tracker(self, gh: GhFake, text: str) -> None:
        gh.rest[f"repos/{REPO}/contents/.work-item-tracker.json?ref=main"] = {
            "type": "file",
            "encoding": "base64",
            "content": base64.b64encode(text.encode()).decode(),
        }

    def test_the_production_default_reads_the_tracker_at_the_base(self) -> None:
        # No `admission=` override: the label comes from the base branch's
        # tracker config, here mapped away from the default name.
        gh = eligibility_fake(
            self,
            pr={"baseRefName": "main"},
            issue={
                "author": user(OUTSIDER),
                "labels": {"totalCount": 1, "nodes": [{"name": "ready-for-agent"}]},
            },
        )
        gh.rest[self.TIMELINE] = [
            {
                "event": "labeled",
                "label": {"name": "ready-for-agent"},
                "actor": {"login": OPERATOR, "type": "User"},
                "created_at": "2026-10-11T09:00:00Z",
            }
        ]
        mapped = {"config": {"role_labels": {"autonomous-eligible": "ready-for-agent"}}}
        self.tracker(gh, json.dumps(mapped))
        production = policy.eligibility(
            REPO, 7, agent_identity=IDENTITY, permission=HUMANS
        )
        self.assertTrue(production.eligible, production.reason)

    def test_a_non_json_tracker_config_refuses_unreadable(self) -> None:
        gh = self.outside_issue(["agent-ready"], {"login": OPERATOR, "type": "User"})
        gh.graphql["PolicyEligibility"]["repository"]["pullRequest"]["baseRefName"] = (
            "main"
        )
        self.tracker(gh, "{ not json")
        result = policy.eligibility(REPO, 7, agent_identity=IDENTITY, permission=HUMANS)
        self.assertFalse(result.eligible)
        self.assertTrue(result.reason.startswith("unreadable:"), result.reason)

    def edited_issue(self, editor: dict[str, str]) -> GhFake:
        created = "2026-10-10T09:00:00Z"
        gh = eligibility_fake(self, issue={"lastEditedAt": "2026-10-11T10:00:00Z"})
        gh.graphql["PolicyDemotionRecord"] = {
            "repository": {
                "issue": {
                    "number": ISSUE,
                    "createdAt": created,
                    "author": user(OPERATOR),
                    "userContentEdits": {
                        "totalCount": 2,
                        "nodes": [
                            {
                                "editedAt": "2026-10-11T10:00:00Z",
                                "deletedAt": None,
                                "editor": editor,
                                "diff": "rewritten",
                            },
                            {
                                "editedAt": created,
                                "deletedAt": None,
                                "editor": user(OPERATOR),
                                "diff": "original",
                            },
                        ],
                    },
                }
            }
        }
        return gh

    def test_a_human_issue_rewritten_by_the_lane_app_is_refused(self) -> None:
        self.edited_issue(bot("agent-lanes"))
        self.assertEqual(
            eligibility().reason, "issue-not-vouched:body-edited-by-non-human"
        )

    def test_a_human_issue_retitled_by_a_non_human_is_refused(self) -> None:
        # A title edit leaves the body history alone, so the author path reads
        # the `renamed` events too: only a human in person may retitle.
        gh = eligibility_fake(self, issue={"labels": {"totalCount": 0, "nodes": []}})
        rename = {
            "event": "renamed",
            "actor": {"login": IDENTITY, "type": "Bot"},
            "rename": {"from": "Fix a typo", "to": "Rewrite the merge gate"},
            "created_at": "2026-10-11T10:00:00Z",
        }
        gh.rest[self.TIMELINE] = [rename]
        self.assertEqual(
            eligibility().reason, "issue-not-vouched:title-edited-by-non-human"
        )
        rename["actor"] = {"login": OPERATOR, "type": "User"}
        rename["performed_via_github_app"] = {"slug": "agent"}
        self.assertEqual(
            eligibility().reason, "issue-not-vouched:title-edited-by-non-human"
        )
        del rename["performed_via_github_app"]
        result = eligibility()
        self.assertTrue(result.eligible, result.reason)

    def test_a_human_relabel_after_a_lane_rewrite_vouches(self) -> None:
        # Either vouch suffices: a human who re-applies the admission label in
        # person after the lane's edit vouches for the edited body.
        gh = self.edited_issue(bot("agent-lanes"))
        issue = gh.graphql["PolicyEligibility"]["repository"]["pullRequest"][
            "closingIssuesReferences"
        ]["nodes"][0]
        issue["labels"] = {"totalCount": 1, "nodes": [{"name": "agent-ready"}]}
        gh.rest[self.TIMELINE] = [
            {
                "event": "labeled",
                "label": {"name": "agent-ready"},
                "actor": {"login": OPERATOR, "type": "User"},
                "created_at": "2026-10-11T11:00:00Z",
            }
        ]
        result = eligibility()
        self.assertTrue(result.eligible, result.reason)
        # A label applied before the rewrite did not see it: the author
        # path's reason stands.
        gh.rest[self.TIMELINE][0]["created_at"] = "2026-10-11T09:00:00Z"
        self.assertEqual(
            eligibility().reason, "issue-not-vouched:body-edited-by-non-human"
        )

    def test_a_human_issue_edited_only_by_its_author_passes(self) -> None:
        self.edited_issue(user(OPERATOR))
        result = eligibility()
        self.assertTrue(result.eligible, result.reason)

    def test_an_incomplete_edit_history_refuses(self) -> None:
        gh = self.edited_issue(user(OPERATOR))
        record = gh.graphql["PolicyDemotionRecord"]["repository"]["issue"]
        record["userContentEdits"]["totalCount"] = 101
        self.assertEqual(
            eligibility().reason, "issue-not-vouched:edit-history-incomplete"
        )


class Eligibility(unittest.TestCase):
    def test_a_lane_authored_pr_with_one_issue_and_an_earlier_claim(
        self,
    ) -> None:
        eligibility_fake(self)
        result = eligibility()
        self.assertTrue(result.eligible, result.reason)
        self.assertEqual(result.issue, ISSUE)

    def test_a_structural_unknown_or_class_less_issue_is_eligible(self) -> None:
        # Owner decision (option a): no work class gates the merge, so the
        # former class-missing and class-unknown refusals are gone.
        for name, labels in (
            ("structural", ["work-class: structural"]),
            ("class-less", []),
            ("unknown class", ["work-class: bespoke"]),
        ):
            with self.subTest(name):
                eligibility_fake(
                    self,
                    issue={
                        "labels": {
                            "totalCount": len(labels),
                            "nodes": [{"name": n} for n in labels],
                        }
                    },
                )
                result = eligibility()
                self.assertTrue(result.eligible, result.reason)
                self.assertEqual(result.issue, ISSUE)

    def test_an_untrusted_provenance_issue_is_held(self) -> None:
        # The trust hold stays (owner decision, option a), in any case or
        # whitespace, beside any other label.
        for label in (
            "work-class: untrusted-provenance",
            "Work-Class: Untrusted-Provenance",
            " work-class: untrusted-provenance ",
            "work-class:untrusted-provenance",
            "work-class: untrusted_provenance",
            "work-class: untrusted–provenance",
            "untrusted-provenance",
        ):
            with self.subTest(label):
                eligibility_fake(
                    self,
                    issue={
                        "labels": {
                            "totalCount": 2,
                            "nodes": [
                                {"name": "work-class: mechanical"},
                                {"name": label},
                            ],
                        }
                    },
                )
                result = eligibility()
                self.assertFalse(result.eligible)
                self.assertEqual(result.reason, "untrusted-provenance")

    def test_unreadable_issue_labels_hold(self) -> None:
        # The trust hold cannot be ruled out, so it fails closed.
        eligibility_fake(
            self, issue={"labels": {"totalCount": 101, "nodes": [{"name": "a"}]}}
        )
        self.assertEqual(eligibility().reason, "issue-labels-unreadable")

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

    def test_a_class_label_s_provenance_no_longer_refuses(self) -> None:
        # Owner decision (option a): the former class-provenance refusals,
        # an agent's class label and a body edit after it, are gone.
        gh = eligibility_fake(self)
        gh.rest[f"repos/{REPO}/issues/{ISSUE}/timeline?per_page=100"] = [
            {
                "event": "labeled",
                "label": {"name": "work-class: structural"},
                "actor": {"login": "agent-lanes[bot]", "type": "Bot"},
                "created_at": "2026-10-11T09:00:00Z",
            },
        ]
        self.assertIsNone(eligibility().reason)

        # A body edit after the class label, by the human author.
        IssueVouch.edited_issue(self, user(OPERATOR))
        self.assertIsNone(eligibility().reason)

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
    """An App acting on a human's token is not the human, so only a human in
    person may lift the untrusted-provenance hold. No other class label's
    history is read."""

    TIMELINE = f"repos/{REPO}/issues/{ISSUE}/timeline?per_page=100"

    def unlabeled(
        self, label: str, actor: dict[str, str], via: Any = None
    ) -> dict[str, Any]:
        return {
            "event": "unlabeled",
            "label": {"name": label},
            "actor": actor,
            "performed_via_github_app": via,
            "created_at": "2026-10-11T10:00:00Z",
        }

    def test_a_class_label_applied_through_an_app_stays_eligible(self) -> None:
        gh = eligibility_fake(self)
        gh.rest[self.TIMELINE][0]["performed_via_github_app"] = {"slug": "agent"}
        self.assertTrue(eligibility().eligible)

    def test_the_trust_label_removed_by_a_non_human_is_held(self) -> None:
        for actor, via in (
            ({"login": IDENTITY, "type": "Bot"}, None),
            ({"login": OPERATOR, "type": "User"}, {"slug": "agent"}),
        ):
            with self.subTest(actor=actor, via=via):
                gh = eligibility_fake(self)
                gh.rest[self.TIMELINE].append(
                    self.unlabeled("Work-Class: Untrusted-Provenance", actor, via)
                )
                self.assertEqual(
                    eligibility().reason, "untrusted-provenance-removed-by-non-human"
                )

    def test_another_class_label_removed_by_a_non_human_stays_eligible(self) -> None:
        # The former class-label-removed-by-non-human refusal, for a
        # structural label and a scoped one.
        for label in ("work-class: structural", "work-class: scoped"):
            with self.subTest(label):
                gh = eligibility_fake(self)
                gh.rest[self.TIMELINE].append(
                    self.unlabeled(label, {"login": IDENTITY, "type": "Bot"})
                )
                self.assertTrue(eligibility().eligible)

    def test_a_human_removing_the_trust_label_lifts_the_hold(self) -> None:
        gh = eligibility_fake(self)
        gh.rest[self.TIMELINE].append(
            self.unlabeled(
                "work-class: untrusted-provenance", {"login": OPERATOR, "type": "User"}
            )
        )
        self.assertTrue(eligibility().eligible)

    def test_an_unreadable_timeline_is_ineligible(self) -> None:
        gh = eligibility_fake(self)
        gh.rest[self.TIMELINE] = 502
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

    def test_only_an_on_rung_is_promoted(self) -> None:
        # Keyed by the rung: `off`, a missing rung and any class name have no
        # cells, so nothing outside RUNG_CELLS is ever promoted.
        result, _ = self.run_resolver()
        self.assertTrue(result.promoted("C2"))
        self.assertTrue(result.promoted("C3"))
        for other in ("off", None, "C1", "C4", "C5"):
            self.assertFalse(result.promoted(other))

    def test_each_rung_needs_its_own_cells(self) -> None:
        # promotion-evidence-resolution.md "Promotable cells and rung
        # mapping": C2 needs C2-auto-merge; C3 also needs C3-auto-merge and
        # its prerequisite C3-ai-review-blocking.
        cells = self.CELLS | {"C3-ai-review-blocking": {"effective": "unpromoted"}}
        options = {
            o: {"value": f"/opt/p/{o}", "scope": "managed", "file": "/etc/m.json"}
            for o in policy.PROMOTION_OPTIONS
        }
        payload = {"failClosedReason": None, "options": options, "cells": cells}
        result, _ = self.run_resolver(payload)
        self.assertTrue(result.promoted("C2"))
        self.assertFalse(result.promoted("C3"))
        payload["cells"] = self.CELLS | {"C2-auto-merge": {"effective": "unpromoted"}}
        result, _ = self.run_resolver(payload)
        self.assertFalse(result.promoted("C2"))
        self.assertFalse(result.promoted("C3"))

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

    def test_the_needs_human_label(self) -> None:
        # A queued entry that gains the human-gated label leaves the queue.
        self.fake(labels={"totalCount": 1, "nodes": [{"name": "Needs-Human"}]})
        self.assertEqual(self.hold(), "needs-human")

    def test_a_remapped_human_gated_label(self) -> None:
        self.fake(labels={"totalCount": 1, "nodes": [{"name": "Human-Review"}]})
        with mock.patch.object(
            babysit_postmerge, "_role_label", return_value="human-review"
        ):
            self.assertEqual(self.hold(), "human-review")

    def test_an_unreadable_human_gated_label_is_a_hold(self) -> None:
        self.fake()
        failed = babysit_postmerge.PostMergeReadError("tracker: HTTP 502")
        with mock.patch.object(babysit_postmerge, "_role_label", side_effect=failed):
            self.assertEqual(self.hold(), "unreadable: tracker: HTTP 502")

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

    def capped(self, cap: int | None, queued: int, unverified: int) -> Any:
        """In flight: `queued` identity entries and `unverified` lane merges,
        under `max_in_flight=cap` (None: the default)."""
        queue_fake(
            self,
            [
                {"enqueuer": bot("agent-lanes"), "pullRequest": {"number": 10 + i}}
                for i in range(queued)
            ],
            [merged(20 + i, bot("agent-lanes"), None) for i in range(unverified)],
        )
        cap_kwargs = {} if cap is None else {"max_in_flight": cap}
        return policy.in_flight(
            REPO,
            agent_identity=IDENTITY,
            permission=HUMANS,
            merged_since=FLOOR,
            lane_merges_only=True,
            **cap_kwargs,
        )

    def test_a_cap_of_five_admits_four_in_flight_and_refuses_five(self) -> None:
        admitted = self.capped(5, 2, 2)
        self.assertEqual((admitted.clear, admitted.reason), (True, None))
        self.assertEqual(admitted.unverified, 2)
        # Two queued entries and two unverified merges: four in flight.
        self.assertEqual(admitted.count, 4)
        self.assertEqual(self.capped(5, 3, 2).reason, "unverified-auto-merge:#21")
        self.assertEqual(self.capped(5, 5, 0).reason, "identity-entry-queued:#14")

    def test_the_default_cap_refuses_one_in_flight_as_before(self) -> None:
        for cap in (None, 1):
            with self.subTest(cap=cap):
                self.assertEqual(
                    self.capped(cap, 1, 1).reason, "identity-entry-queued:#10"
                )
                self.assertEqual(
                    self.capped(cap, 0, 1).reason, "unverified-auto-merge:#20"
                )
                self.assertTrue(self.capped(cap, 0, 0).clear)

    def test_an_unknown_enqueuer_refuses_under_any_cap(self) -> None:
        queue_fake(
            self,
            [
                {"enqueuer": bot("agent-lanes"), "pullRequest": {"number": 3}},
                {"enqueuer": None, "pullRequest": {"number": 4}},
            ],
            [],
        )
        result = policy.in_flight(
            REPO,
            agent_identity=IDENTITY,
            permission=HUMANS,
            merged_since=FLOOR,
            max_in_flight=5,
        )
        self.assertEqual(result.reason, "entry-enqueuer-unknown:#4")

    def test_the_queue_read_names_every_entry_or_none(self) -> None:
        queue_fake(
            self,
            [
                {"enqueuer": user(OPERATOR), "pullRequest": {"number": 3}},
                {"enqueuer": bot("agent-lanes"), "pullRequest": {"number": 4}},
            ],
            [],
        )
        result = self.flight()
        self.assertEqual(result.reason, "identity-entry-queued:#4")
        self.assertEqual(result.queued, frozenset({3, 4}))
        queue_fake(self, [{"enqueuer": user(OPERATOR), "pullRequest": {}}], [])
        self.assertIsNone(self.flight().queued)

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

    def test_an_unreadable_queue_or_truncated_history_refuses_under_a_cap_of_five(
        self,
    ) -> None:
        def capped_flight() -> Any:
            return policy.in_flight(
                REPO,
                agent_identity=IDENTITY,
                permission=HUMANS,
                merged_since=FLOOR,
                max_in_flight=5,
            )

        gh = queue_fake(self, [], [])
        gh.graphql["PolicyMergeQueue"] = {
            "repository": {"mergeQueue": {"entries": {"totalCount": 2, "nodes": []}}}
        }
        self.assertEqual(capped_flight().reason, "merge-queue-unreadable")
        gh = queue_fake(self, [], [])
        human = merged(2, user(OPERATOR), user(OPERATOR))
        gh.graphql["PolicyRecentMerges"] = merge_pages([[human]], endless=True)
        self.assertEqual(capped_flight().reason, "merged-history-truncated")

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
        # The default branch head is the base, so the in-flight cap is the
        # base config's.
        gh.rest[f"repos/{REPO}/commits/trunk"] = {"sha": SHA}
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
        self.assertNotIn("configNotes", result.report())

    def test_the_config_notes_reach_the_report(self) -> None:
        # A retired key's note (read_config_at) is what tells the operator
        # the setting does nothing.
        self.readable()
        self.all_clear()
        note = "merge.diff-check.c2-contradictions is retired and has no effect"
        tighten = policy.with_default_branch
        with mock.patch.object(
            policy,
            "with_default_branch",
            lambda *a, **k: dataclasses.replace(tighten(*a, **k), notes=(note,)),
        ):
            result = self.assess(post_merge=lambda floor, who: gate())
        self.assertEqual(result.report()["configNotes"], [note])

    def test_a_merged_pull_request_stops_before_the_post_merge_reads(self) -> None:
        gh = self.readable()
        gh.rest[f"repos/{REPO}/pulls/1"].update(state="closed", merged=True)
        later = mock.Mock(side_effect=AssertionError("read after the refusal"))
        with (
            mock.patch.object(policy, "read_demotion", later),
            mock.patch.object(policy, "in_flight", later),
            mock.patch.object(policy, "eligibility", later),
        ):
            result = self.assess(
                post_merge=later, promotion=later, stop_when_closed=True
            )
        later.assert_not_called()
        # The gate's own blocker for a pull request that is not open.
        self.assertEqual(result.reason, "state=MERGED (not OPEN)")
        self.assertIs(result.enabled, False)
        self.assertIs(result.report()["reportOnly"], False)
        # What the queue sweep reads: the identity, branch and readers.
        for key in ("identity", "branch", "config", "permission", "self_logins"):
            self.assertIn(key, result.inputs)

    def test_a_closed_unmerged_pull_request_is_read_in_full_with_the_stop(
        self,
    ) -> None:
        # Closed but not merged can reopen before the gate's own state read,
        # so only a merge, which is final, stops early.
        gh = self.readable()
        gh.rest[f"repos/{REPO}/pulls/1"].update(state="closed", merged=False)
        self.all_clear()
        seen: list[Any] = []
        self.assess(
            post_merge=lambda floor, who: seen.append(who) or gate(),
            promotion=lambda s: PROMOTED,
            stop_when_closed=True,
        )
        self.assertEqual(seen, [IDENTITY])

    def test_a_closed_pull_request_is_read_in_full_without_the_stop(self) -> None:
        gh = self.readable()
        gh.rest[f"repos/{REPO}/pulls/1"].update(state="closed", merged=True)
        self.all_clear()
        seen: list[Any] = []
        self.assess(
            post_merge=lambda floor, who: seen.append(who) or gate(),
            promotion=lambda s: PROMOTED,
        )
        self.assertEqual(seen, [IDENTITY])

    def test_an_open_pull_request_is_read_in_full_with_the_stop(self) -> None:
        gh = self.readable()
        gh.rest[f"repos/{REPO}/pulls/1"].update(state="open", merged=False)
        self.all_clear()
        result = self.assess(
            post_merge=lambda floor, who: gate(),
            promotion=lambda s: PROMOTED,
            stop_when_closed=True,
        )
        self.assertIsNone(result.reason)

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

    def test_an_in_flight_refusal_off_the_queue_reads_nothing_after_it(self) -> None:
        self.readable()
        later = mock.Mock(side_effect=AssertionError("read after the refusal"))
        flight = policy.InFlight(False, "identity-entry-queued:#3", frozenset({3}))
        with (
            mock.patch.object(policy, "in_flight", return_value=flight),
            mock.patch.object(policy, "eligibility", later),
            mock.patch.object(policy, "lane_eligibility", later),
            mock.patch.object(policy, "dependabot_eligibility", later),
        ):
            result = self.assess(post_merge=lambda floor, who: gate(), promotion=later)
        later.assert_not_called()
        self.assertEqual(result.reason, "in-flight:identity-entry-queued:#3")
        self.assertIs(result.enabled, True)
        self.assertNotIn("eligibility", result.inputs)

    def test_a_rung_off_outranks_an_in_flight_refusal_off_the_queue(self) -> None:
        self.readable()
        flight = policy.InFlight(False, "x", frozenset({3}))
        ineligible = policy.Eligibility(False, "fork")
        with (
            mock.patch.object(policy, "in_flight", return_value=flight),
            mock.patch.object(
                policy, "rung_cap", return_value=policy.RungCap("off", "cap-set")
            ),
            mock.patch.object(policy, "eligibility", return_value=ineligible) as read,
        ):
            result = self.assess(
                post_merge=lambda floor, who: gate(), promotion=lambda s: PROMOTED
            )
        self.assertTrue(result.reason.startswith("rung-off:"), result.reason)
        self.assertTrue(read.called)
        self.assertEqual(result.inputs["own_refusal"], "ineligible:fork")

    def test_the_in_flight_refusal_matches_the_full_judgment(self) -> None:
        # None: the queue was not read whole, so the pull request is read in
        # full; its own queued entry (#1) is read in full too, and refused.
        self.readable()
        ineligible = policy.Eligibility(False, "fork")
        seen = []
        for queued in (None, frozenset({1, 3}), frozenset({3})):
            flight = policy.InFlight(False, "identity-entry-queued:#3", queued)
            with (
                mock.patch.object(policy, "in_flight", return_value=flight),
                mock.patch.object(
                    policy, "eligibility", return_value=ineligible
                ) as read,
            ):
                result = self.assess(
                    post_merge=lambda floor, who: gate(),
                    promotion=lambda s: PROMOTED,
                )
            seen.append(
                (
                    result.reason,
                    result.enabled,
                    read.called,
                    result.inputs.get("own_refusal"),
                )
            )
        reason = "in-flight:identity-entry-queued:#3"
        self.assertEqual(
            seen,
            [
                (reason, True, True, "ineligible:fork"),
                (reason, True, True, "ineligible:fork"),
                (reason, True, False, None),
            ],
        )

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

    def test_no_work_class_is_a_ceiling_on_the_rung(self) -> None:
        # Owner decision (option a): the former class-above-rung refusal is
        # gone, and promotion is keyed by the rung (Q21 option b). An eligible
        # pull request reporting no class, or a class above the C2 rung,
        # merges at a promoted C2.
        self.readable()
        for work_class in (None, "C3", "C5"):
            with self.subTest(work_class=work_class), self.all_clear(work_class):
                result = self.assess(
                    post_merge=lambda floor, who: gate(), promotion=lambda s: PROMOTED
                )
                self.assertIsNone(result.reason)
                self.assertIs(result.promoted, True)

    def at_rung(self, rung: str) -> Any:
        at = policy.EffectiveRung(rung, {"merge.rung": rung}, None)
        return mock.patch.object(policy, "effective_rung", return_value=at)

    def test_the_rung_names_the_promotion_cells_it_needs(self) -> None:
        # Q21 option b: rung C2 needs C2-auto-merge; rung C3 needs every C3
        # cell. The pull request's class does not change the answer.
        only_c2 = policy.Promotion(
            {
                "C2-auto-merge": "promoted",
                "C3-auto-merge": "unpromoted",
                "C3-ai-review-blocking": "unpromoted",
            },
            None,
        )
        none = policy.Promotion(
            dict.fromkeys(policy.PROMOTABLE_CELLS, "unpromoted"), None
        )
        self.readable()
        for rung, promo, reason in (
            ("C2", PROMOTED, None),
            ("C2", only_c2, None),
            ("C2", none, "promotion-unqualified:C2"),
            ("C3", PROMOTED, None),
            ("C3", only_c2, "promotion-unqualified:C3"),
        ):
            for work_class in (None, "C2", "C5"):
                with (
                    self.subTest(rung=rung, work_class=work_class, reason=reason),
                    self.all_clear(work_class),
                    self.at_rung(rung),
                ):
                    result = self.assess(
                        post_merge=lambda floor, who: gate(),
                        promotion=lambda s, p=promo: p,
                    )
                    self.assertEqual(result.reason, reason)
                    self.assertIs(result.promoted, reason is None)
                    # The pull request's own refusal, so a queued entry leaves.
                    self.assertEqual(result.inputs["own_refusal"], reason)

    def test_an_unreadable_resolver_refuses(self) -> None:
        self.readable()
        self.all_clear(None)
        failed = policy.Promotion(None, "resolver-failed")
        result = self.assess(
            post_merge=lambda floor, who: gate(), promotion=lambda s: failed
        )
        self.assertEqual(result.reason, "promotion-unqualified:resolver-failed")
        self.assertIs(result.enabled, True)

    def test_the_real_eligibility_holds_an_untrusted_provenance_issue(self) -> None:
        # The trust hold through `eligibility()` itself, not a stubbed answer.
        gh = self.readable()
        issue = {
            "number": ISSUE,
            "lastEditedAt": None,
            "author": user(OPERATOR),
            "repository": {"nameWithOwner": REPO},
            "labels": {
                "totalCount": 1,
                "nodes": [{"name": "work-class: untrusted-provenance"}],
            },
        }
        gh.graphql["PolicyEligibility"] = {
            "repository": {
                "pullRequest": {
                    "number": 1,
                    "createdAt": PR_CREATED,
                    "lastEditedAt": None,
                    "isCrossRepository": False,
                    "baseRefName": "trunk",
                    "author": bot("agent-lanes"),
                    "headRepositoryOwner": {"login": "owner"},
                    "labels": {"totalCount": 0, "nodes": []},
                    "closingIssuesReferences": {"totalCount": 1, "nodes": [issue]},
                }
            }
        }
        with mock.patch.object(
            policy, "in_flight", return_value=policy.InFlight(True, None)
        ):
            result = self.assess(
                post_merge=lambda floor, who: gate(), promotion=lambda s: PROMOTED
            )
        self.assertEqual(result.reason, "ineligible:untrusted-provenance")
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
            # The restarted window holds the rung's cells unpromoted until a
            # human re-ratifies them after the demotion: the merge refuses.
            restarted = policy.Promotion(
                dict.fromkeys(policy.PROMOTABLE_CELLS, "unpromoted"), None
            )
            held = self.assess(
                post_merge=lambda floor, who: gate(),
                promotion=lambda start: restarted if start == created else PROMOTED,
            )
        self.assertEqual(seen, [created])
        self.assertEqual(held.reason, "promotion-unqualified:C2")

    def test_after_a_demotion_the_rung_waits_for_re_ratified_evidence(self) -> None:
        # The resolver, given --window-start, adds a gate-failure per cell at
        # the demotion (resolve-promotion-evidence.test.mjs "--window-start
        # hands the checker a copy with one gate-failure per cell"), so its
        # cells read unpromoted until a promotion newer than that exists. Here
        # the resolver's answer is canned on each side of that ratification;
        # the gate must pass the window start through read_promotion's argv
        # and refuse until the cells read promoted.
        self.readable()
        self.all_clear()
        created = policy.datetime.fromisoformat("2026-10-11T07:00:00Z")
        options = {
            o: {"value": f"/opt/p/{o}", "scope": "managed", "file": "/etc/m.json"}
            for o in policy.PROMOTION_OPTIONS
        }
        argvs: list[list[str]] = []
        real = policy.run_command

        def resolver(effective: str) -> Any:
            answer = {
                "failClosedReason": None,
                "options": options,
                "cells": {c: {"effective": effective} for c in policy.PROMOTABLE_CELLS},
            }

            def run(argv: list[str], **kwargs: Any) -> Any:
                if str(policy.PROMOTION_RESOLVER) not in argv:
                    return real(argv, **kwargs)
                argvs.append(argv)
                return subprocess.CompletedProcess(argv, 0, json.dumps(answer), "")

            return run

        def promotion(start: Any) -> policy.Promotion:
            return policy.read_promotion(
                checkout=pathlib.Path("/w/main"),
                window_start=start,
                worktrees=lambda c: [],
                writable=lambda p: False,
            )

        demotion = policy.Demotion(False, None, (9,), created, created)
        with mock.patch.object(policy, "read_demotion", return_value=demotion):
            for effective, reason in (
                ("unpromoted", "promotion-unqualified:C2"),
                ("promoted", None),
            ):
                with (
                    self.subTest(effective=effective),
                    mock.patch.object(policy, "run_command", resolver(effective)),
                ):
                    result = self.assess(
                        post_merge=lambda floor, who: gate(), promotion=promotion
                    )
                    self.assertEqual(result.reason, reason)
        for argv in argvs:
            self.assertEqual(
                argv[argv.index("--window-start") + 1], "2026-10-11T07:00:00Z"
            )
        self.assertEqual(len(argvs), 2)

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

    def test_the_newest_config_commit_comes_from_the_same_clone(self) -> None:
        self.pipeline(PIPELINE, "2026-10-11T00:00:00Z")
        newest = self.pipeline(PIPELINE + "# edit\n", "2026-10-12T00:00:00Z")
        base = self.commit("README.md", "unrelated", "2026-10-13T00:00:00Z")
        gh = self.local()
        self.assertEqual(policy.newest_config_commit(REPO, base), newest)
        self.assertEqual(gh.calls, [])

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
        # Two alternating texts keep each commit a change to the file.
        for n in range(101):
            base = self.pipeline(
                f"{PIPELINE}# {n % 2}\n", f"2026-02-01T00:{n // 60:02d}:{n % 60:02d}Z"
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

    def test_a_partial_clone_falls_back_to_the_api(self) -> None:
        # Its older blobs are not local, and the read never lazy-fetches.
        self.pipeline(PIPELINE, "2026-10-01T00:00:00Z")
        base = self.pipeline(PIPELINE + "# edit\n", "2026-10-11T00:00:00Z")
        self.git(self.clone, "config", "uploadpack.allowFilter", "true")
        partial = self.tmp / "partial"
        self.git(
            self.tmp,
            "clone",
            "-q",
            "--no-checkout",
            "--filter=blob:none",
            self.clone.as_uri(),
            str(partial),
        )
        self.fake(
            [self.commit_record(base, "2026-09-01T00:00:00Z")],
            {base: PIPELINE},
            base=base,
            clones=(partial,),
        )
        self.assertEqual(
            policy.enabled_since(REPO, base),
            policy.datetime.fromisoformat("2026-09-01T00:00:00Z"),
        )

    def cut_history(self) -> tuple[str, Any]:
        """Three pipeline commits and a base; returns the middle commit and
        `_local_history` of the base before anything cuts the history."""
        self.pipeline(PIPELINE, "2026-10-01T00:00:00Z")
        middle = self.pipeline(PIPELINE + "# a\n", "2026-10-11T00:00:00Z")
        self.pipeline(PIPELINE + "# b\n", "2026-10-12T00:00:00Z")
        self.base = self.commit("README.md", "unrelated", "2026-10-13T00:00:00Z")
        self.local()
        whole = policy._local_history(self.base)
        assert whole is not None and len(whole[1]) == 3
        return middle, whole

    def test_a_graft_file_does_not_cut_the_history(self) -> None:
        # Grafted parentless, the middle commit would end the walk there.
        middle, whole = self.cut_history()
        (self.clone / ".git" / "info").mkdir(exist_ok=True)
        (self.clone / ".git" / "info" / "grafts").write_text(f"{middle}\n")
        self.assertEqual(policy._local_history(self.base), whole)

    def test_a_replace_ref_does_not_cut_the_history(self) -> None:
        middle, whole = self.cut_history()
        self.git(self.clone, "replace", "--graft", middle)
        self.assertEqual(policy._local_history(self.base), whole)

    def test_the_base_config_comes_from_the_clone(self) -> None:
        # Before the clone read: two contents-API calls per candidate.
        self.commit(policy.SOURCE_CONTROL_PATH, SOURCE_CONTROL, "2026-10-01T00:00:00Z")
        base = self.pipeline(PIPELINE, "2026-10-02T00:00:00Z")
        gh = self.local()
        config = policy.read_config_at(REPO, base)
        self.assertEqual(
            (config.authority, config.agent_identity, config.loop_merge),
            ("local-babysit", IDENTITY, "c2-mechanical"),
        )
        self.assertEqual(gh.calls, [])

    def test_a_symlinked_config_reads_the_api_as_before(self) -> None:
        # The contents API follows an in-repository symlink to a file; the
        # clone read hands such a path to it rather than refusing it.
        self.commit("docs/source-control.md", SOURCE_CONTROL, "2026-10-01T00:00:00Z")
        (self.clone / policy.SOURCE_CONTROL_PATH).parent.mkdir(exist_ok=True)
        (self.clone / policy.SOURCE_CONTROL_PATH).symlink_to(
            "../docs/source-control.md"
        )
        self.git(self.clone, "add", policy.SOURCE_CONTROL_PATH)
        base = self.pipeline(PIPELINE, "2026-10-02T00:00:00Z")
        gh = self.local()
        api = f"repos/{REPO}/contents/{policy.SOURCE_CONTROL_PATH}?ref={base}"
        gh.rest[api] = file_payload(SOURCE_CONTROL)
        config = policy.read_config_at(REPO, base)
        self.assertEqual(config.loop_merge, "c2-mechanical")
        self.assertEqual(gh.calls, [["api", api]])

    def test_a_base_missing_from_the_clone_reads_the_api_not_no_config(
        self,
    ) -> None:
        self.pipeline(DISABLED, "2026-10-01T00:00:00Z")
        gh = self.fake([], {SHA: PIPELINE}, clones=(self.scripts,))
        config = policy.read_config_at(REPO, SHA)
        self.assertEqual(
            (config.authority, config.agent_identity), ("local-babysit", IDENTITY)
        )
        self.assertIn(
            ["api", f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={SHA}"], gh.calls
        )

    def test_changed_file_modes_come_from_the_clone(self) -> None:
        # Before the clone read: one trees-API call per side.
        base = self.commit("tool.sh", "echo\n", "2026-10-01T00:00:00Z")
        (self.clone / "tool.sh").chmod(0o755)
        self.git(self.clone, "add", "tool.sh")
        self.git(self.clone, "commit", "-q", "-m", "x", date="2026-10-02T00:00:00Z")
        head = self.git(self.clone, "rev-parse", "HEAD")
        gh = self.local()
        gh.rest[f"repos/{REPO}/pulls/7/files?per_page=100"] = [
            {
                "filename": "tool.sh",
                "status": "modified",
                "additions": 0,
                "deletions": 0,
            }
        ]
        pr = {
            "number": 7,
            "changed_files": 1,
            "head": {"sha": head},
            "base": {"sha": base},
        }
        files, complete = policy.changed_files(REPO, pr)
        self.assertTrue(complete)
        self.assertEqual(
            [(f.path, f.mode, f.previous_mode) for f in files],
            [("tool.sh", "100755", "100644")],
        )
        self.assertEqual(
            gh.calls,
            [
                [
                    "api",
                    f"repos/{REPO}/pulls/7/files?per_page=100",
                    "--paginate",
                    "--slurp",
                ]
            ],
        )

    def test_a_tree_missing_from_the_clone_reads_the_api(self) -> None:
        self.pipeline(PIPELINE, "2026-10-01T00:00:00Z")
        gh = self.fake([], {}, clones=(self.scripts,))
        gh.rest[f"repos/{REPO}/git/trees/{SHA}?recursive=1"] = {
            "truncated": False,
            "tree": [{"path": "docs/a.md", "mode": "100644"}],
        }
        self.assertEqual(
            policy._tree_modes("owner", "repo", SHA), {"docs/a.md": "100644"}
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
        # Owner decision Q624: absent, the floor and both size caps are off.
        config = self.diff_check([])
        self.assertEqual(
            (
                config.high_path_floor,
                config.max_changed_files,
                config.max_changed_lines,
                config.rung,
            ),
            (False, None, None, "C2"),
        )

    def test_the_lane_switches_are_read(self) -> None:
        config = self.diff_check(
            [
                "high-path-floor: true",
                "max-changed-files: 8",
                "max-changed-lines: 400",
            ]
        )
        self.assertEqual(
            (
                config.high_path_floor,
                config.max_changed_files,
                config.max_changed_lines,
            ),
            (True, 8, 400),
        )

    def test_the_retired_c2_contradictions_key_only_leaves_a_note(self) -> None:
        # Kept valid in the schema for existing configs; it has no effect, and
        # an operator who set it is told so.
        config = self.diff_check(["c2-contradictions: true"])
        self.assertEqual(config.rung, "C2")
        self.assertEqual(
            config.notes,
            (
                "merge.diff-check.c2-contradictions is retired and has no effect:"
                " no work class is read",
            ),
        )
        self.assertFalse(hasattr(config, "c2_contradictions"))
        self.assertEqual(self.diff_check(["c2-contradictions: false"]).notes, ())

    def test_an_unreadable_switch_is_on_and_a_bad_cap_is_off(self) -> None:
        config = self.diff_check(["high-path-floor: maybe"])
        self.assertIs(config.high_path_floor, True)
        self.assertEqual(len(config.notes), 1)
        config = self.diff_check(["max-changed-files: lots"])
        self.assertEqual((config.rung, config.max_changed_files), ("off", None))


class LaneEligibility(unittest.TestCase):
    """The pr-merge lane's eligibility (merge-criterion plan, Design 1 and 2):
    a pull request the lanes App opened, not a fork or a dependency
    manager's, with exactly one closing issue in this repository and a diff
    touching no denied path, is fixed class C2. No `work-class:` label is
    read, on the issue or the pull request, but the trust hold
    (`trust_refusal`) still refuses an issue carrying a label naming untrusted
    work, or one a non-human removed; the verifier verdict, bound to that
    closing issue, is the merge criterion."""

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
        body: str | None = None,
        timeline: Any = (),
    ) -> GhFake:
        issues = [self.issue_node(labels=labels)] if closing is None else closing
        names = pr_labels or []
        gh = GhFake().install(self)
        gh.rest[f"repos/{REPO}"] = {"default_branch": "main"}
        gh.rest[self.TIMELINE] = list(timeline) if timeline != 502 else 502
        gh.graphql["PolicyEligibility"] = {
            "repository": {
                "pullRequest": {
                    "number": 7,
                    "body": body,
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
        # One label history read, the trust hold's, and no issue comment:
        # the agent-ready label alone admitted the issue.
        calls = [" ".join(c) for c in gh.calls]
        self.assertEqual(sum(self.TIMELINE in c for c in calls), 1)
        self.assertFalse(any(self.COMMENTS in c for c in calls))

    def test_a_class_label_on_the_issue_or_the_pr_is_ignored(self) -> None:
        # The admitted issues still carrying these labels (#5981, #6821).
        for labels in (
            ["work-class: scoped"],
            ["Work-Class: Structural"],
        ):
            with self.subTest(labels=labels):
                self.fake(labels=labels, pr_labels=["work-class: structural"])
                result = self.eligibility()
                self.assertTrue(result.eligible, result.reason)
                self.assertEqual(result.work_class, "C2")

    def test_an_issue_labeled_untrusted_refuses_in_any_spelling(self) -> None:
        for label in (
            "work-class: untrusted-provenance",
            "Work-Class: Untrusted_Provenance",
            "untrusted",
        ):
            with self.subTest(label=label):
                self.fake(labels=[MECHANICAL, label])
                result = self.eligibility()
                self.assertFalse(result.eligible)
                self.assertEqual(result.reason, "untrusted-provenance")

    def test_the_label_match_agrees_with_the_queue_step(self) -> None:
        # The shared table scripts/ci-hold-merge-group.test.sh runs through the
        # merge-queue step's jq `ascii_downcase`: an ASCII-only match, so a
        # letter that folds to an ASCII one ("ſ", "ﬆ") holds in neither.
        table = json.loads(
            (pathlib.Path(__file__).parent / "fixtures/untrusted-labels.json").read_text(
                encoding="utf-8"
            )
        )
        for want, labels in ((True, table["holds"]), (False, table["passes"])):
            for label in labels:
                with self.subTest(label=label):
                    self.assertIs(policy._untrusted(label), want)

    def test_the_trust_label_removed_by_a_non_human_refuses(self) -> None:
        def unlabeled(actor: dict[str, str], via: Any = None) -> dict[str, Any]:
            return {
                "event": "unlabeled",
                "label": {"name": "work-class: untrusted-provenance"},
                "actor": actor,
                "performed_via_github_app": via,
            }

        for event in (
            unlabeled({"login": IDENTITY, "type": "Bot"}),
            unlabeled({"login": OPERATOR, "type": "User"}, {"slug": "agent"}),
            unlabeled({"login": "reader", "type": "User"}),
        ):
            with self.subTest(event=event):
                self.fake(timeline=[event])
                self.assertEqual(
                    self.eligibility().reason,
                    "untrusted-provenance-removed-by-non-human",
                )
        # A write-access person's removal lifts it.
        self.fake(timeline=[unlabeled({"login": "maintainer", "type": "User"})])
        self.assertTrue(self.eligibility().eligible)

    def test_unreadable_labels_or_timeline_refuse(self) -> None:
        cut = self.issue_node(labels=[MECHANICAL])
        cut["labels"]["totalCount"] = 101
        self.fake(closing=[cut])
        self.assertEqual(self.eligibility().reason, "issue-labels-unreadable")
        self.fake(timeline=502)
        self.assertTrue(str(self.eligibility().reason).startswith("unreadable: "))

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


def refs_answer(*issues: dict[str, Any], pulls: tuple[int, ...] = ()) -> Any:
    """The PolicyRefsIssue answer: each issue node by number, a pull request
    for each number in `pulls`, and for any other number GitHub's NOT_FOUND
    answer, as a live read of a missing number returned it: gh exits 1."""
    by_number = {issue["number"]: issue for issue in issues}

    def answer(variables: dict[str, str]) -> Any:
        number = int(variables["n"])
        if number in pulls:
            node: dict[str, Any] = {"__typename": "PullRequest"}
        elif number in by_number:
            node = {"__typename": "Issue"} | by_number[number]
        else:
            missing = {
                "data": {"repository": {"issueOrPullRequest": None}},
                "errors": [
                    {"type": "NOT_FOUND", "path": ["repository", "issueOrPullRequest"]}
                ],
            }
            return subprocess.CompletedProcess(
                [], 1, json.dumps(missing), "gh: Could not resolve"
            )
        return {"repository": {"issueOrPullRequest": node}}

    return answer


class RefsIssueEligibility(unittest.TestCase):
    """Owner decision 2026-10-23: a pull request that closes no issue and
    names one with a plain `Refs: #<n>` line is read as if that issue closed
    it. The expected numbers are the ones each body names."""

    issue_node = LaneEligibility.issue_node
    fake = LaneEligibility.fake
    FILES = LaneEligibility.FILES
    TIMELINE = LaneEligibility.TIMELINE
    eligibility = LaneEligibility.eligibility

    def refs_calls(self, gh: GhFake) -> int:
        return sum("query PolicyRefsIssue" in " ".join(c) for c in gh.calls)

    def test_a_lane_pr_naming_one_issue_with_refs_is_eligible(self) -> None:
        gh = self.fake(closing=[], body="Refs: #41\n\n## Summary\n\nPart one.")
        gh.graphql["PolicyRefsIssue"] = refs_answer(self.issue_node())
        result = self.eligibility()
        self.assertTrue(result.eligible, result.reason)
        # The issue the cost-decision lookup and the enqueue recheck bind to.
        self.assertEqual((result.work_class, result.issue), ("C2", 41))
        self.assertIsNone(policy.recheck_lane_issue(REPO, 7, issue=41))

    def test_hidden_refs_lines_name_nothing(self) -> None:
        for body in (
            "<!-- Refs: #41 -->",
            "<!--\nRefs: #41",
            "```\nRefs: #41\n```",
            "~~~~\nRefs: #41\n~~~\n~~~~",
            "````md\nRefs: #41",
            "    Refs: #41",
            "> Refs: #41",
            "Fixes nothing. Refs: #41",
        ):
            with self.subTest(body=body):
                gh = self.fake(closing=[], body=body)
                self.assertEqual(self.eligibility().reason, "linked-issues:0")
                self.assertEqual(self.refs_calls(gh), 0)

    def test_a_refs_line_after_a_closed_fence_counts(self) -> None:
        gh = self.fake(closing=[], body="```\nRefs: #9\n```\r\nRefs: #41")
        gh.graphql["PolicyRefsIssue"] = refs_answer(self.issue_node())
        result = self.eligibility()
        self.assertEqual((result.reason, result.issue), (None, 41))

    def test_another_repository_or_several_issues_refuse(self) -> None:
        for body, reason in (
            ("Refs: other/repo#41", "refs-line-not-plain"),
            ("Refs: https://github.com/other/repo/issues/41", "refs-line-not-plain"),
            ("Refs: #41, #42", "refs-line-not-plain"),
            ("refs: #41", "refs-line-not-plain"),
            ("Refs: #41\nRefs: other/repo#42", "refs-line-not-plain"),
            ("Refs: #41\n\nRefs: #42", "refs-issues:2"),
        ):
            with self.subTest(body=body):
                gh = self.fake(closing=[], body=body)
                self.assertEqual(self.eligibility().reason, reason)
                self.assertEqual(self.refs_calls(gh), 0)
        # The same issue named twice is one issue.
        gh = self.fake(closing=[], body="Refs: #41\nRefs: #41")
        gh.graphql["PolicyRefsIssue"] = refs_answer(self.issue_node())
        self.assertEqual(self.eligibility().issue, 41)

    def test_a_refs_number_that_is_a_pull_request_or_moved_refuses(self) -> None:
        gh = self.fake(closing=[], body="Refs: #41")
        gh.graphql["PolicyRefsIssue"] = refs_answer(pulls=(41,))
        self.assertEqual(self.eligibility().reason, "refs-not-an-issue")
        gh = self.fake(closing=[], body="Refs: #41")
        gh.graphql["PolicyRefsIssue"] = refs_answer(
            self.issue_node(repository="other/repo")
        )
        self.assertEqual(self.eligibility().reason, "linked-issue-other-repository")
        gh = self.fake(closing=[], body="Refs: #41")
        gh.graphql["PolicyRefsIssue"] = 502
        self.assertTrue(self.eligibility().reason.startswith("unreadable:"))

    def test_a_refs_number_that_names_nothing_refuses_as_no_issue(self) -> None:
        # A typo: no issue or pull request has the number. It names no
        # issue here (`no_issue_here`), never a read error.
        gh = self.fake(closing=[], body="Refs: #99999")
        gh.graphql["PolicyRefsIssue"] = refs_answer(self.issue_node())
        self.assertEqual(self.eligibility().reason, "refs-not-an-issue")
        self.assertTrue(policy.no_issue_here("refs-not-an-issue"))
        self.assertEqual(
            policy.recheck_lane_issue(REPO, 7, issue=41), "refs-not-an-issue"
        )
        # NOT_FOUND anywhere else, or beside another error, stays unreadable.
        for errors in (
            [{"type": "NOT_FOUND", "path": ["repository"]}],
            [
                {"type": "NOT_FOUND", "path": ["repository", "issueOrPullRequest"]},
                {"type": "INTERNAL"},
            ],
            [{"type": "RATE_LIMITED", "path": ["repository", "issueOrPullRequest"]}],
        ):
            with self.subTest(errors=errors):
                gh = self.fake(closing=[], body="Refs: #99999")
                answer = {
                    "data": {"repository": {"issueOrPullRequest": None}},
                    "errors": errors,
                }
                gh.graphql["PolicyRefsIssue"] = subprocess.CompletedProcess(
                    [], 1, json.dumps(answer), "gh: error"
                )
                self.assertTrue(self.eligibility().reason.startswith("unreadable:"))
        # An answer with no errors and no repository is no answer.
        gh = self.fake(closing=[], body="Refs: #41")
        gh.graphql["PolicyRefsIssue"] = {}
        self.assertTrue(self.eligibility().reason.startswith("unreadable:"))
        # Nor is a null issue without NOT_FOUND "no issue".
        gh = self.fake(closing=[], body="Refs: #41")
        gh.graphql["PolicyRefsIssue"] = {"repository": {"issueOrPullRequest": None}}
        self.assertTrue(self.eligibility().reason.startswith("unreadable:"))

    def test_a_closing_issue_wins_over_refs(self) -> None:
        gh = self.fake(body="Refs: #42")
        result = self.eligibility()
        self.assertEqual((result.reason, result.issue), (None, 41))
        self.assertEqual(self.refs_calls(gh), 0)
        # Two closing issues still refuse; a Refs line does not pick one.
        self.fake(
            closing=[self.issue_node(), self.issue_node(number=42)], body="Refs: #41"
        )
        self.assertEqual(self.eligibility().reason, "linked-issues:2")
        # Another repository's closing issue is not "none": Refs is not read.
        self.fake(closing=[self.issue_node(repository="other/repo")], body="Refs: #41")
        self.assertEqual(self.eligibility().reason, "linked-issue-other-repository")

    def test_the_enqueue_recheck_reads_the_refs_line_again(self) -> None:
        gh = self.fake(closing=[], body="Refs: #42")
        gh.graphql["PolicyRefsIssue"] = refs_answer(self.issue_node(number=42))
        self.assertEqual(
            policy.recheck_lane_issue(REPO, 7, issue=41), "closing-issue-changed:41>42"
        )
        self.fake(closing=[], body="<!-- Refs: #41 -->")
        self.assertEqual(
            policy.recheck_lane_issue(REPO, 7, issue=41), "linked-issues:0"
        )

    def test_the_worker_tier_reads_the_trust_hold_and_claim_from_the_refs_issue(
        self,
    ) -> None:
        def refs_issue(label: str) -> dict[str, Any]:
            return {
                "number": ISSUE,
                "lastEditedAt": None,
                "author": user(OPERATOR),
                "repository": {"nameWithOwner": REPO},
                "labels": {"totalCount": 1, "nodes": [{"name": label}]},
            }

        gh = eligibility_fake(self, issues=[], pr={"body": f"Refs: #{ISSUE}"})
        # A structural class an agent applied no longer refuses: no class is
        # read (owner decision, option a).
        gh.graphql["PolicyRefsIssue"] = refs_answer(
            refs_issue("work-class: structural")
        )
        timeline = gh.rest[f"repos/{REPO}/issues/{ISSUE}/timeline?per_page=100"]
        timeline[0]["label"]["name"] = "work-class: structural"
        timeline[0]["actor"] = {"login": "agent-lanes[bot]", "type": "Bot"}
        result = eligibility()
        self.assertTrue(result.eligible, result.reason)
        self.assertEqual(result.issue, ISSUE)
        gh.graphql["PolicyRefsIssue"] = refs_answer(
            refs_issue("work-class: untrusted-provenance")
        )
        self.assertEqual(eligibility().reason, "untrusted-provenance")

    def test_an_unclaimed_refs_issue_is_refused_claim_missing(self) -> None:
        gh = eligibility_fake(self, issues=[], pr={"body": f"Refs: #{ISSUE}"})
        gh.graphql["PolicyRefsIssue"] = refs_answer(
            {
                "number": ISSUE,
                "lastEditedAt": None,
                "author": user(OPERATOR),
                "repository": {"nameWithOwner": REPO},
                "labels": {
                    "totalCount": 1,
                    "nodes": [{"name": "work-class: mechanical"}],
                },
            }
        )
        gh.rest[f"repos/{REPO}/issues/{ISSUE}/comments?per_page=100"] = []
        self.assertEqual(eligibility().reason, "claim-missing")


OWNER_LOGIN = "kyle-sexton"
OWNER_ID = 153232337
ADOPT_NOW = datetime(2026, 10, 12, 12, tzinfo=UTC)
IDLE = "2026-10-11T11:00:00Z"  # 25 hours before ADOPT_NOW
FRESH = "2026-10-11T13:00:00Z"  # 23 hours before ADOPT_NOW
NOW_ISH = "2026-10-11T14:00:00Z"  # an hour after FRESH
REMOVED = "2026-10-11T13:30:00Z"  # the queue removed the entry FRESH queued
SEEN = "2026-10-11T12:50:00Z"  # the head first reached GitHub
HEAD = "c" * 40


def owner_pr(**changes: Any) -> dict[str, Any]:
    """An idle, ready, unheld REST pull request the owner account opened."""
    pr = {
        "number": 7,
        "base": {"sha": SHA},
        "head": {"sha": HEAD},
        "changed_files": 1,
        "draft": False,
        "user": {"login": OWNER_LOGIN, "id": OWNER_ID, "type": "User"},
        "updated_at": IDLE,
        "labels": [{"name": "enhancement"}],
        "body": "Closes #41\n\nA plain body.",
    }
    pr.update(changes)
    return pr


class AdoptIdleOwnerPullRequests(unittest.TestCase):
    """Owner decision Q22: a ready, unheld pull request the owner account
    opened, idle `adoption.idle-hours` by its update and its head commit, is
    adopted by the pr-merge lane."""

    ISSUE = LaneEligibility.ISSUE
    TIMELINE = LaneEligibility.TIMELINE
    FILES = LaneEligibility.FILES
    COMMENTS = LaneEligibility.COMMENTS
    COMMIT = f"repos/{REPO}/commits/{HEAD}"
    SUITES = f"repos/{REPO}/commits/{HEAD}/check-suites?app_id=15368&per_page=100"
    issue_node = LaneEligibility.issue_node
    fake_lane = LaneEligibility.fake

    def refusal(self, pr: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        args: dict[str, Any] = {
            "idle_hours": 24,
            "owner_ids": (OWNER_ID,),
            "human_gated": "needs-human",
            "now": ADOPT_NOW,
        }
        args.update(kwargs)
        committed = args.pop("committed", IDLE)
        return policy.adoption_refusal(
            owner_pr() if pr is None else pr, lambda: committed, **args
        )

    def test_an_idle_ready_unheld_owner_pr_is_adopted(self) -> None:
        self.assertIsNone(self.refusal())

    def test_idle_exactly_the_configured_hours_is_adopted(self) -> None:
        at = "2026-10-11T12:00:00Z"
        self.assertIsNone(self.refusal(owner_pr(updated_at=at), committed=at))

    def test_a_draft_is_not_adopted(self) -> None:
        self.assertEqual(self.refusal(owner_pr(draft=True)), "draft")
        self.assertEqual(self.refusal(owner_pr(draft=None)), "draft")

    def test_another_account_is_not_adopted(self) -> None:
        for user in (
            {"login": "someone", "id": 1, "type": "User"},
            {"login": OWNER_LOGIN, "type": "User"},
            {"login": "agent-lanes[bot]", "id": 2, "type": "Bot"},
        ):
            with self.subTest(user=user):
                self.assertEqual(self.refusal(owner_pr(user=user)), "author-not-owner")

    def test_the_owner_login_with_another_id_is_not_adopted(self) -> None:
        # Login text is never the match: only the account id is.
        for login in (OWNER_LOGIN, OWNER_LOGIN.upper()):
            with self.subTest(login=login):
                spoof = {
                    "login": login,
                    "id": OWNER_ID + 1,
                    "type": "User",
                }
                self.assertEqual(self.refusal(owner_pr(user=spoof)), "author-not-owner")

    def test_a_listed_app_is_adopted_with_no_idle_wait(self) -> None:
        # Owner decision 2026-10-22: a trusted App's PR (the release App's)
        # is adopted at once; only a person may still be working on theirs.
        app = {"login": "melodic-plugin-release[bot]", "id": 337859524, "type": "Bot"}
        fresh = owner_pr(user=app, updated_at=FRESH)
        self.assertIsNone(
            self.refusal(fresh, committed=FRESH, owner_ids=(OWNER_ID, 337859524))
        )
        self.assertEqual(self.refusal(fresh, committed=FRESH), "author-not-owner")
        org = {"login": OWNER_LOGIN, "id": OWNER_ID, "type": "Organization"}
        self.assertEqual(self.refusal(owner_pr(user=org)), "author-not-owner")

    def test_a_recent_update_is_not_adopted(self) -> None:
        self.assertEqual(self.refusal(owner_pr(updated_at=FRESH)), "updated-fresh")

    def test_a_recent_head_commit_is_not_adopted(self) -> None:
        self.assertEqual(self.refusal(committed=FRESH), "head-fresh")

    def test_an_unreadable_time_is_not_idle(self) -> None:
        for bad in (None, "", "yesterday", "2026-10-10T00:00:00"):
            with self.subTest(bad=bad):
                self.assertEqual(
                    self.refusal(owner_pr(updated_at=bad)), "updated-fresh"
                )
                self.assertEqual(self.refusal(committed=bad), "head-fresh")

        def unreadable() -> str:
            raise policy.PolicyReadError("502")

        self.assertEqual(
            policy.adoption_refusal(
                owner_pr(),
                unreadable,
                idle_hours=24,
                owner_ids=(OWNER_ID,),
                human_gated="needs-human",
                now=ADOPT_NOW,
            ),
            "head-fresh",
        )

    def test_the_owner_ids_come_from_the_caller(self) -> None:
        other = {"login": "other", "id": 77, "type": "User"}
        self.assertIsNone(self.refusal(owner_pr(user=other), owner_ids=(5, 77)))
        self.assertEqual(self.refusal(owner_ids=(77,)), "author-not-owner")
        self.assertEqual(self.refusal(owner_ids=()), "author-not-owner")

    def test_the_head_commit_is_not_read_for_a_pr_refused_earlier(self) -> None:
        def unread() -> str:
            raise AssertionError("head commit read")

        for pr in (
            owner_pr(draft=True),
            owner_pr(user={"login": "x", "id": 1, "type": "User"}),
            owner_pr(updated_at=FRESH),
            owner_pr(labels=[{"name": "do-not-merge"}]),
        ):
            with self.subTest(pr=pr):
                self.assertIsNotNone(
                    policy.adoption_refusal(
                        pr,
                        unread,
                        idle_hours=24,
                        owner_ids=(OWNER_ID,),
                        human_gated="needs-human",
                        now=ADOPT_NOW,
                    )
                )

    def test_the_do_not_merge_label_holds(self) -> None:
        pr = owner_pr(labels=[{"name": "Do-Not-Merge"}])
        self.assertEqual(self.refusal(pr), "hold-label:do-not-merge")

    def test_the_resolved_human_gated_label_holds(self) -> None:
        pr = owner_pr(labels=[{"name": "awaiting-owner"}])
        self.assertEqual(
            self.refusal(pr, human_gated="awaiting-owner"),
            "hold-label:awaiting-owner",
        )
        # The label is the resolved one, never the literal default.
        pr = owner_pr(labels=[{"name": "needs-human"}])
        self.assertIsNone(self.refusal(pr, human_gated="awaiting-owner"))
        self.assertEqual(self.refusal(pr), "hold-label:needs-human")

    def test_an_unresolved_human_gated_label_is_not_adopted(self) -> None:
        self.assertEqual(self.refusal(human_gated=None), "human-gated-label-unresolved")

    def test_a_hold_line_in_the_body_holds(self) -> None:
        for body in ("Closes #41\n\nHold: waiting on the owner", "  hold: x"):
            with self.subTest(body=body):
                self.assertEqual(self.refusal(owner_pr(body=body)), "hold-body")

    # --- While the lane's own queue entry is pending ------------------------

    def test_a_fresh_update_keeps_adoption_while_the_lane_entry_is_queued(self) -> None:
        # The lane's pin comment and enqueue refresh `updated_at`; its own
        # entry at this head must not then leave the queue as not adopted.
        pr = owner_pr(updated_at=FRESH)
        self.assertIsNone(self.refusal(pr, queued_at_head=lambda: True))
        self.assertEqual(
            self.refusal(pr, queued_at_head=lambda: False), "updated-fresh"
        )
        self.assertEqual(self.refusal(pr), "updated-fresh")

    def test_a_queued_entry_still_needs_an_idle_head_commit(self) -> None:
        pr = owner_pr(updated_at=FRESH)
        self.assertEqual(
            self.refusal(pr, committed=FRESH, queued_at_head=lambda: True),
            "head-fresh",
        )

    def test_a_queued_entry_still_answers_to_every_hold(self) -> None:
        for pr, refused in (
            (owner_pr(labels=[{"name": "do-not-merge"}]), "hold-label:do-not-merge"),
            (owner_pr(labels=[{"name": "needs-human"}]), "hold-label:needs-human"),
            (owner_pr(body="Hold: the owner merges"), "hold-body"),
            (owner_pr(draft=True), "draft"),
        ):
            with self.subTest(refused=refused):
                pr["updated_at"] = FRESH
                self.assertEqual(self.refusal(pr, queued_at_head=lambda: True), refused)

    def test_the_queue_is_not_read_for_an_idle_update(self) -> None:
        def unread() -> bool:
            raise AssertionError("queue read")

        self.assertIsNone(self.refusal(queued_at_head=unread))

    def test_the_lane_entry_is_its_own_at_the_current_head(self) -> None:
        cases = (
            ("queued and pinned at the head", [7], HEAD, True),
            ("no entry of the identity", [8], HEAD, False),
            ("pinned at another head", [7], "d" * 40, False),
            ("no pin, or an edited one", [7], None, False),
        )
        for label, queued, pinned, expected in cases:
            with self.subTest(label):
                with (
                    mock.patch.object(
                        babysit_postmerge, "identity_queue", return_value=(queued, 0)
                    ) as queue,
                    mock.patch.object(
                        babysit_postmerge, "read_pin", return_value=pinned
                    ) as read,
                ):
                    self.assertIs(
                        policy.lane_queued_at_head(REPO, 7, "trunk", IDENTITY, HEAD),
                        expected,
                    )
                    queue.assert_called_once_with(REPO, "trunk", IDENTITY)
                    if queued == [7]:
                        read.assert_called_once_with(REPO, 7, IDENTITY, alone=True)

    def test_a_comment_after_the_pin_ends_the_queued_excuse(self) -> None:
        # A human asking to wait refreshes `updated_at`: with the lane's
        # entry still queued at the head, the next sweep refuses it again.
        pin = {
            "author": bot("agent-lanes"),
            "body": babysit_postmerge.pin_comment(HEAD),
            "createdAt": "2026-10-11T13:00:00Z",
            "lastEditedAt": None,
        }
        wait = {
            "author": user(OWNER_LOGIN),
            "body": "Please wait on this one",
            "createdAt": "2026-10-11T14:00:00Z",
            "lastEditedAt": None,
        }
        for comments, reviews, expected in (
            ([pin], [], None),
            ([pin, wait], [], "updated-fresh"),
            (
                [pin],
                [{"author": user(OWNER_LOGIN), "submittedAt": "2026-10-11T14:00:00Z"}],
                "updated-fresh",
            ),
            ([pin], None, "updated-fresh"),
        ):
            with self.subTest(comments=len(comments), reviews=reviews):
                answer = {
                    "data": {
                        "repository": {
                            "pullRequest": {
                                "comments": {
                                    "pageInfo": {
                                        "hasNextPage": False,
                                        "endCursor": None,
                                    },
                                    "nodes": comments,
                                },
                                "reviews": {"nodes": reviews},
                            }
                        }
                    }
                }
                with (
                    mock.patch.object(
                        babysit_postmerge, "identity_queue", return_value=([7], 0)
                    ),
                    mock.patch.object(babysit_postmerge, "_read", return_value=answer),
                ):
                    self.assertEqual(
                        self.refusal(
                            owner_pr(updated_at=FRESH),
                            queued_at_head=lambda: policy.lane_queued_at_head(
                                REPO, 7, "trunk", IDENTITY, HEAD
                            ),
                        ),
                        expected,
                    )

    def test_an_unreadable_queue_or_pin_is_not_queued(self) -> None:
        error = babysit_postmerge.PostMergeReadError("502")
        for target in ("identity_queue", "read_pin"):
            with self.subTest(target):
                with (
                    mock.patch.object(
                        babysit_postmerge, "identity_queue", return_value=([7], 0)
                    ),
                    mock.patch.object(babysit_postmerge, "read_pin", return_value=HEAD),
                    mock.patch.object(babysit_postmerge, target, side_effect=error),
                ):
                    self.assertFalse(
                        policy.lane_queued_at_head(REPO, 7, "trunk", IDENTITY, HEAD)
                    )
        self.assertFalse(policy.lane_queued_at_head(REPO, 7, "trunk", IDENTITY, ""))

    def test_no_idle_hours_adopts_nothing(self) -> None:
        self.assertEqual(self.refusal(idle_hours=None), "idle-hours-invalid")

    def test_idle_hours_come_from_the_caller(self) -> None:
        self.assertEqual(self.refusal(idle_hours=26), "updated-fresh")
        self.assertIsNone(
            self.refusal(owner_pr(updated_at=FRESH), committed=FRESH, idle_hours=1)
        )

    # --- In the lane's eligibility ------------------------------------------

    def eligibility(self, pr: dict[str, Any], **kwargs: Any) -> Any:
        args: dict[str, Any] = {
            "denied_paths": LANE_DENIED,
            "agent_identity": IDENTITY,
            "adoption_idle_hours": 24,
            "adoption_owner_ids": (OWNER_ID,),
            "spec_from_body_ids": (OWNER_ID,),
            "human_gated": "needs-human",
            "now": ADOPT_NOW,
        }
        args.update(kwargs)
        return policy.lane_eligibility(REPO, 7, pr=pr, **args)

    def owner_fake(self, committed: str = IDLE) -> GhFake:
        gh = self.fake_lane(author=user(OWNER_LOGIN))
        gh.rest[self.COMMIT] = {
            "sha": HEAD,
            "commit": {"committer": {"date": committed}},
        }
        return gh

    def test_an_adopted_owner_pr_is_eligible_and_says_why(self) -> None:
        self.owner_fake()
        result = self.eligibility(owner_pr())
        self.assertTrue(result.eligible, result.reason)
        self.assertEqual((result.work_class, result.issue), ("C2", 41))
        self.assertEqual(result.adoption, "idle-owner:24h")

    def test_an_adopted_pr_with_no_issue_here_is_its_own_intent(self) -> None:
        # Owner decision 2026-10-22: its title and body are the spec, so no
        # closing issue in this repository is needed; two still refuse.
        committed = {"sha": HEAD, "commit": {"committer": {"date": IDLE}}}
        for closing, reason, issue in (
            ([], None, None),
            ([self.issue_node(repository="other/repo")], None, None),
            ([self.issue_node(), self.issue_node(number=42)], "linked-issues:2", None),
        ):
            with self.subTest(closing=closing):
                gh = self.fake_lane(author=user(OWNER_LOGIN), closing=closing)
                gh.rest[self.COMMIT] = committed
                result = self.eligibility(owner_pr())
                self.assertEqual((result.reason, result.issue), (reason, issue))
        # Before the enqueue the issue is read again: still none here holds.
        self.fake_lane(author=user(OWNER_LOGIN), closing=[])
        self.assertIsNone(policy.recheck_lane_issue(REPO, 7, issue=None))

    def test_an_adopted_pr_reads_a_refs_issue_as_a_closing_one(self) -> None:
        # One Refs issue is its issue, as resolve-pr gives the verifier; Refs
        # lines that name none or several leave the body as its intent.
        committed = {"sha": HEAD, "commit": {"committer": {"date": IDLE}}}
        for body, issue in (
            ("Refs: #41", 41),
            ("Refs: #41\nRefs: #42", None),
            ("Refs: other/repo#41", None),
        ):
            with self.subTest(body=body):
                gh = self.fake_lane(author=user(OWNER_LOGIN), closing=[], body=body)
                gh.graphql["PolicyRefsIssue"] = refs_answer(self.issue_node())
                gh.rest[self.COMMIT] = committed
                result = self.eligibility(owner_pr(body=body))
                self.assertEqual((result.reason, result.issue), (None, issue))
                self.assertEqual(result.body_is_intent, True)
                self.assertIsNone(policy.recheck_lane_issue(REPO, 7, issue=issue))

    def test_only_a_script_written_apps_body_is_its_intent(self) -> None:
        # A model-written App body (claude[bot]) would grade the diff against
        # the spec the same run wrote: it needs a closing issue. The release
        # App's script-written body does not (adoption.spec-from-body-apps).
        release = {
            "login": "melodic-plugin-release[bot]",
            "id": 337859524,
            "type": "Bot",
        }
        claude = {"login": "claude[bot]", "id": 209825114, "type": "Bot"}
        # A GitHub User the trusted list marks kind bot: a model writes its
        # bodies, so being a User does not make it a person.
        cursoragent = {"login": "cursoragent", "id": 199161495, "type": "User"}
        ids = (OWNER_ID, release["id"], claude["id"], cursoragent["id"])
        for author, reason in (
            (release, None),
            (claude, "linked-issues:0"),
            (cursoragent, "linked-issues:0"),
        ):
            with self.subTest(author=author["login"]):
                gh = self.fake_lane(author=user(author["login"]), closing=[])
                gh.rest[self.COMMIT] = {
                    "sha": HEAD,
                    "commit": {"committer": {"date": IDLE}},
                }
                result = self.eligibility(
                    owner_pr(user=author),
                    adoption_owner_ids=ids,
                    spec_from_body_ids=(OWNER_ID, release["id"]),
                )
                self.assertEqual(result.reason, reason)
                # S&C B: only these authors' own lines skip the floor.
                self.assertEqual(result.body_is_intent, reason is None)
        self.fake_lane(author=user(OWNER_LOGIN), closing=[])
        self.assertIsNone(policy.recheck_lane_issue(REPO, 7, issue=None))

    def test_spec_from_body_apps_reads_the_setting(self) -> None:
        for text, expected in (
            (PIPELINE, ()),
            (PIPELINE + "adoption:\n  spec-from-body-apps: [5, 77]\n", (5, 77)),
            (PIPELINE + "adoption:\n  spec-from-body-apps: [5, x]\n", ()),
        ):
            with self.subTest(text=text):
                config_fake(self, text)
                config = policy.read_config_at(REPO, SHA)
                self.assertEqual(config.spec_from_body_apps, expected)

    def test_a_fresh_owner_pr_is_not_adopted(self) -> None:
        self.owner_fake(committed=FRESH)
        result = self.eligibility(owner_pr())
        self.assertFalse(result.eligible)
        self.assertEqual(result.reason, "not-adopted:head-fresh")
        self.assertIsNone(result.adoption)

    def test_a_fresh_owner_pr_queued_by_the_lane_stays_adopted(self) -> None:
        self.owner_fake()
        pr = owner_pr(updated_at=FRESH)
        result = self.eligibility(pr, queued_at_head=lambda: True)
        self.assertTrue(result.eligible, result.reason)
        self.assertEqual(result.adoption, "idle-owner:24h")
        result = self.eligibility(pr, queued_at_head=lambda: False)
        self.assertEqual(result.reason, "not-adopted:updated-fresh")

    # --- After a person's enqueue left the queue on failed checks ----------
    # Owner decision Q-REQ (a): that person's enqueue of this head stands in
    # for the idle wait; every other rule still applies.

    def ejected(self, **changes: Any) -> dict[str, Any]:
        enqueue = {
            "__typename": "AddedToMergeQueueEvent",
            "createdAt": FRESH,
            "actor": {"__typename": "User", "databaseId": OWNER_ID},
            "enqueuer": {"databaseId": OWNER_ID},
        }
        enqueue.update(changes.pop("enqueue", {}))
        return {"enqueue": enqueue, "removedAt": REMOVED, "requeued": False, **changes}

    def requeued(self, ejected: Any, **kwargs: Any) -> bool:
        args: dict[str, Any] = {
            "human_ids": (OWNER_ID,),
            "head_last_seen": lambda: SEEN,
            "queued_at_head": lambda: False,
            "quiet_since": lambda when: True,
        }
        args.update(kwargs)
        return policy.requeued_by_person(ejected, **args)

    def test_a_persons_ejected_enqueue_at_this_head_requeues(self) -> None:
        self.assertTrue(self.requeued(self.ejected()))
        # The lane's own retry, queued at this head, keeps it adopted.
        retry = self.ejected(requeued=True)
        self.assertTrue(self.requeued(retry, queued_at_head=lambda: True))
        self.assertFalse(self.requeued(retry))

    def test_only_a_trusted_persons_enqueue_requeues(self) -> None:
        app = {"__typename": "Bot", "databaseId": 337595936}
        for label, enqueue, humans in (
            ("an App actor", {"actor": app}, (OWNER_ID,)),
            # GitHub types the lanes App's enqueuer a User: only the id counts.
            (
                "an App enqueuer typed User",
                {"enqueuer": {"login": "agent-lanes[bot]", "databaseId": 337595936}},
                (OWNER_ID,),
            ),
            ("a null enqueuer", {"enqueuer": None}, (OWNER_ID,)),
            ("a null actor", {"actor": None}, (OWNER_ID,)),
            (
                "a person not on the list",
                {
                    "actor": {"__typename": "User", "databaseId": 77},
                    "enqueuer": {"databaseId": 77},
                },
                (OWNER_ID,),
            ),
            ("a login and no id", {"enqueuer": {"login": OWNER_LOGIN}}, (OWNER_ID,)),
            ("no people on the list", {}, ()),
        ):
            with self.subTest(label):
                ejected = self.ejected(enqueue=enqueue)
                self.assertFalse(self.requeued(ejected, human_ids=humans))

    def test_a_head_pushed_after_the_enqueue_does_not_requeue(self) -> None:
        # The server's newest check suite on the head, never a commit date: a
        # backdated commit fast-forwarded after the removal, or a head staged
        # before, reset away and pushed back, has a suite after the enqueue.
        self.assertFalse(self.requeued(self.ejected(), head_last_seen=lambda: NOW_ISH))
        self.assertTrue(self.requeued(self.ejected(), head_last_seen=lambda: FRESH))

        def unreadable() -> str:
            raise policy.PolicyReadError("502")

        self.assertFalse(self.requeued(self.ejected(), head_last_seen=unreadable))
        self.assertFalse(self.requeued(self.ejected(enqueue={"createdAt": None})))

    def test_a_word_after_the_removal_stops_the_requeue(self) -> None:
        seen: list[Any] = []

        def quiet(when: Any) -> bool:
            seen.append(when)
            return False

        self.assertFalse(self.requeued(self.ejected(), quiet_since=quiet))
        # From the enqueue: a request to wait made then, before the run
        # failed, still holds.
        self.assertEqual(seen, [policy._time(FRESH)])

        def unreadable(when: Any) -> bool:
            raise policy.PolicyReadError("502")

        self.assertFalse(self.requeued(self.ejected(), quiet_since=unreadable))
        for removed in (None, "", "2026-10-11T13:30:00"):
            with self.subTest(removed=removed):
                self.assertFalse(self.requeued(self.ejected(removedAt=removed)))

    def discussion_fake(self, **surfaces: list[dict[str, Any]]) -> GhFake:
        gh = GhFake().install(self)
        for kind in ("issues/7/comments", "pulls/7/reviews", "pulls/7/comments"):
            key = kind.replace("/", "_")
            gh.rest[f"repos/{REPO}/{kind}?per_page=100"] = surfaces.get(key, [])
        return gh

    def test_only_a_persons_word_after_the_removal_breaks_the_quiet(self) -> None:
        removed = policy._time(REMOVED)
        person = {"login": OWNER_LOGIN, "type": "User"}
        lanes = {"login": IDENTITY, "type": "Bot"}
        review_bot = {"login": "claude[bot]", "type": "Bot"}
        before, after = "2026-10-11T13:00:00Z", "2026-10-11T14:00:00Z"
        for label, surfaces, quiet in (
            ("nothing said", {}, True),
            (
                "a person before the removal",
                {
                    "issues_7_comments": [
                        {"user": person, "created_at": before, "updated_at": before}
                    ]
                },
                True,
            ),
            (
                "a person asking to wait after it",
                {
                    "issues_7_comments": [
                        {"user": person, "created_at": after, "updated_at": after}
                    ]
                },
                False,
            ),
            (
                "an earlier comment edited after it",
                {
                    "issues_7_comments": [
                        {"user": person, "created_at": before, "updated_at": after}
                    ]
                },
                False,
            ),
            (
                "a person's review after it",
                {"pulls_7_reviews": [{"user": person, "submitted_at": after}]},
                False,
            ),
            (
                "a person's inline comment after it",
                {
                    "pulls_7_comments": [
                        {"user": person, "created_at": after, "updated_at": after}
                    ]
                },
                False,
            ),
            (
                "the lane identity after it",
                {
                    "issues_7_comments": [
                        {"user": lanes, "created_at": after, "updated_at": after}
                    ]
                },
                True,
            ),
            (
                "a review bot after it",
                {"pulls_7_reviews": [{"user": review_bot, "submitted_at": after}]},
                True,
            ),
            (
                "a person's item with no time",
                {"issues_7_comments": [{"user": person}]},
                False,
            ),
        ):
            with self.subTest(label):
                self.discussion_fake(**surfaces)
                self.assertIs(
                    policy._quiet_since("owner", "repo", 7, IDENTITY, removed), quiet
                )

    def test_an_unreadable_discussion_is_not_quiet(self) -> None:
        gh = self.discussion_fake()
        gh.rest[f"repos/{REPO}/pulls/7/comments?per_page=100"] = 502
        with self.assertRaises(policy.PolicyReadError):
            policy._quiet_since("owner", "repo", 7, IDENTITY, policy._time(REMOVED))

    def suites(self, *suites: dict[str, Any], total: int | None = None) -> GhFake:
        gh = GhFake().install(self)
        gh.rest[self.SUITES] = {
            "total_count": len(suites) if total is None else total,
            "check_suites": list(suites),
        }
        return gh

    def test_the_head_is_last_seen_at_its_newest_check_suite_here(self) -> None:
        pr = owner_pr(head={"sha": HEAD, "ref": "feat/x"})
        mine = {"head_branch": "feat/x", "created_at": "2026-10-11T12:40:00Z"}
        later = {"head_branch": "feat/x", "created_at": "2026-10-11T12:55:00Z"}
        elsewhere = {"head_branch": "other", "created_at": "2026-10-11T09:00:00Z"}
        self.suites(mine, later, elsewhere)
        self.assertEqual(
            policy._head_last_seen("owner", "repo", pr), "2026-10-11T12:55:00Z"
        )
        for label, gh_setup in (
            ("no suite on its branch", lambda: self.suites(elsewhere)),
            ("more suites than one page", lambda: self.suites(mine, total=101)),
            (
                "an unreadable listing",
                lambda: self.suites().rest.update({self.SUITES: 502}),
            ),
        ):
            with self.subTest(label):
                gh_setup()
                with self.assertRaises(policy.PolicyReadError):
                    policy._head_last_seen("owner", "repo", pr)

    def test_no_ejected_enqueue_does_not_requeue(self) -> None:
        for ejected in (None, {}, [], {"enqueue": None, "requeued": False}):
            with self.subTest(ejected=ejected):
                self.assertFalse(self.requeued(ejected))
        self.assertFalse(self.requeued(self.ejected(requeued=None)))

    def test_an_unreadable_queue_reads_no_ejected_enqueue(self) -> None:
        import babysit_merge  # noqa: PLC0415

        for queue, expected in (
            ({"readError": "502", "ejectedEnqueue": self.ejected()}, None),
            ({"readError": None, "ejectedEnqueue": self.ejected()}, self.ejected()),
        ):
            with self.subTest(queue=queue["readError"]):
                with mock.patch.object(
                    babysit_merge, "read_merge_queue", return_value=queue
                ) as read:
                    self.assertEqual(policy.ejected_enqueue(REPO, 7), expected)
                read.assert_called_once_with(REPO, 7)

    def requeue_fake(self, comments: list[dict[str, Any]] | None = None) -> GhFake:
        gh = self.owner_fake(committed=FRESH)
        gh.rest[self.SUITES] = {
            "total_count": 1,
            "check_suites": [{"head_branch": "feat/x", "created_at": SEEN}],
        }
        gh.rest[f"repos/{REPO}/issues/7/comments?per_page=100"] = comments or []
        gh.rest[f"repos/{REPO}/pulls/7/reviews?per_page=100"] = []
        gh.rest[f"repos/{REPO}/pulls/7/comments?per_page=100"] = []
        return gh

    def test_a_fresh_owner_pr_a_person_enqueued_is_adopted(self) -> None:
        self.requeue_fake()
        pr = owner_pr(updated_at=FRESH, head={"sha": HEAD, "ref": "feat/x"})
        result = self.eligibility(
            pr, adoption_human_ids=(OWNER_ID,), ejected_enqueue=self.ejected
        )
        self.assertTrue(result.eligible, result.reason)
        self.assertEqual(result.adoption, policy.REQUEUE_ADOPTION)
        self.assertTrue(result.body_is_intent)
        for label, kwargs, reason in (
            ("not ejected", {"ejected_enqueue": lambda: None}, "updated-fresh"),
            ("no people", {"adoption_human_ids": ()}, "updated-fresh"),
        ):
            with self.subTest(label):
                args = {
                    "adoption_human_ids": (OWNER_ID,),
                    "ejected_enqueue": self.ejected,
                    **kwargs,
                }
                result = self.eligibility(pr, **args)
                self.assertEqual(result.reason, f"not-adopted:{reason}")
                self.assertIsNone(result.adoption)

    def test_a_wait_comment_after_the_removal_keeps_the_idle_rule(self) -> None:
        # AGENTS.md: a person's comment asking to wait stops the merge.
        wait = {
            "user": {"login": OWNER_LOGIN, "type": "User"},
            "body": "hold on, looking at the flake",
            "created_at": "2026-10-11T14:00:00Z",
            "updated_at": "2026-10-11T14:00:00Z",
        }
        self.requeue_fake(comments=[wait])
        pr = owner_pr(updated_at=FRESH, head={"sha": HEAD, "ref": "feat/x"})
        result = self.eligibility(
            pr, adoption_human_ids=(OWNER_ID,), ejected_enqueue=self.ejected
        )
        self.assertEqual(result.reason, "not-adopted:updated-fresh")
        self.assertIsNone(result.adoption)

    def test_a_wait_comment_before_the_run_failed_keeps_the_idle_rule(self) -> None:
        # "Wait for me if this fails", posted after the enqueue and before the
        # removal, still holds.
        wait = {
            "user": {"login": OWNER_LOGIN, "type": "User"},
            "body": "wait for me if this fails",
            "created_at": "2026-10-11T13:15:00Z",
            "updated_at": "2026-10-11T13:15:00Z",
        }
        self.requeue_fake(comments=[wait])
        pr = owner_pr(updated_at=FRESH, head={"sha": HEAD, "ref": "feat/x"})
        result = self.eligibility(
            pr, adoption_human_ids=(OWNER_ID,), ejected_enqueue=self.ejected
        )
        self.assertEqual(result.reason, "not-adopted:updated-fresh")

    def test_a_check_suite_after_the_enqueue_keeps_the_idle_rule(self) -> None:
        # The head staged before the enqueue, reset away, and pushed back
        # after the removal: its newest suite is after the enqueue.
        gh = self.requeue_fake()
        gh.rest[self.SUITES] = {
            "total_count": 2,
            "check_suites": [
                {"head_branch": "feat/x", "created_at": SEEN},
                {"head_branch": "feat/x", "created_at": NOW_ISH},
            ],
        }
        pr = owner_pr(updated_at=FRESH, head={"sha": HEAD, "ref": "feat/x"})
        result = self.eligibility(
            pr, adoption_human_ids=(OWNER_ID,), ejected_enqueue=self.ejected
        )
        self.assertEqual(result.reason, "not-adopted:updated-fresh")

    def test_a_hold_or_an_idle_pr_never_reads_the_queue(self) -> None:
        def unread() -> Any:
            raise AssertionError("merge queue read")

        self.owner_fake()
        result = self.eligibility(
            owner_pr(), adoption_human_ids=(OWNER_ID,), ejected_enqueue=unread
        )
        self.assertEqual(result.adoption, "idle-owner:24h")
        for pr, reason in (
            (owner_pr(labels=[{"name": "do-not-merge"}]), "hold-label:do-not-merge"),
            (owner_pr(body="Hold: the owner merges"), "hold-body"),
            (owner_pr(draft=True), "draft"),
        ):
            with self.subTest(reason):
                pr["updated_at"] = FRESH
                result = self.eligibility(
                    pr, adoption_human_ids=(OWNER_ID,), ejected_enqueue=unread
                )
                self.assertEqual(result.reason, f"not-adopted:{reason}")

    def test_another_author_stays_not_lane_authored(self) -> None:
        self.owner_fake()
        pr = owner_pr(user={"login": OWNER_LOGIN, "id": 1, "type": "User"})
        self.assertEqual(self.eligibility(pr).reason, "not-lane-authored")

    def test_a_lane_pr_is_not_adopted(self) -> None:
        self.fake_lane()
        result = self.eligibility(owner_pr())
        self.assertTrue(result.eligible, result.reason)
        self.assertIsNone(result.adoption)

    def test_without_adoption_settings_nothing_is_adopted(self) -> None:
        self.owner_fake()
        result = policy.lane_eligibility(
            REPO, 7, pr=owner_pr(), denied_paths=(), agent_identity=IDENTITY
        )
        self.assertEqual(result.reason, "not-lane-authored")

    # --- The setting ---------------------------------------------------------

    def test_idle_hours_default_to_24_and_read_the_setting(self) -> None:
        for text, expected, noted in (
            # No setting, no adoption, as in fix-ci.
            (PIPELINE, None, False),
            (PIPELINE + "adoption:\n  idle-hours: 48\n", 48, False),
            (PIPELINE + "adoption:\n  idle-hours: 1\n", 1, False),
            (PIPELINE + "adoption:\n  idle-hours: 720\n", 720, False),
            (PIPELINE + "adoption:\n  idle-hours: 0\n", None, True),
            (PIPELINE + "adoption:\n  idle-hours: 721\n", None, True),
            (PIPELINE + "adoption:\n  idle-hours: 01\n", None, True),
            (PIPELINE + "adoption:\n  idle-hours: soon\n", None, True),
            (PIPELINE + "adoption:\n  idle-hours: -1\n", None, True),
            # Under merge it is another key, not the setting.
            (PIPELINE.replace("merge:\n", "merge:\n  idle-hours: 1\n"), None, False),
        ):
            with self.subTest(text=text):
                config_fake(self, text)
                config = policy.read_config_at(REPO, SHA)
                self.assertEqual(config.adoption_idle_hours, expected)
                self.assertEqual(config.rung, "C2")
                self.assertEqual(any("idle-hours" in n for n in config.notes), noted)

    def test_the_adoptable_ids_are_every_trusted_actor_by_id(self) -> None:
        # Owner decision 2026-10-22: the trusted-actor list, people and Apps.
        listing = {
            "version": 1,
            "actors": [
                {"id": 5, "login": "a-person", "kind": "human"},
                {"id": 77, "login": "an-app[bot]", "kind": "bot"},
            ],
        }
        endpoint = f"repos/{REPO}/contents/{policy.TRUSTED_ACTORS_PATH}?ref=trunk"
        none: tuple[tuple[int, ...], tuple[int, ...]] = ((), ())
        for payload, expected in (
            (file_payload(json.dumps(listing)), ((5, 77), (5,))),
            (file_payload(json.dumps({"version": 2, "actors": []})), none),
            (file_payload(json.dumps({"version": 1, "actors": [{"id": "5"}]})), none),
            (file_payload("{not json"), none),
            (502, none),
        ):
            with self.subTest(payload=payload):
                policy._TRUSTED_IDS.clear()
                gh = GhFake().install(self)
                gh.rest[endpoint] = payload
                gh.rest[f"repos/{REPO}/contents?ref=trunk"] = []
                self.assertEqual(policy.trusted_actors(REPO, "trunk"), expected)

    def test_the_default_branch_head_decides_idle_hours(self) -> None:
        base = policy.PipelineConfig(SHA, "C2", None, IDENTITY, None, (), None)
        for ours, main in ((24, 48), (48, 24), (24, None), (None, 24)):
            with self.subTest(base=ours, main=main):
                combined = policy.stricter_config(
                    dataclasses.replace(base, adoption_idle_hours=ours),
                    dataclasses.replace(base, adoption_idle_hours=main),
                )
                self.assertEqual(combined.adoption_idle_hours, main)


class ForeignPaths(unittest.TestCase):
    """Owner decision 2026-10-22: an adopted pull request's floor scores only
    the paths someone other than its author touched."""

    LANES = 337595936
    WEB_FLOW = 19864447
    CHANGED = (".github/a.yml", ".github/o.yml", "scripts/x.sh", ".github/x.yml")

    def commit(
        self,
        sha: str,
        author: int | None,
        committer: int | None = None,
        *,
        parents: int = 1,
        verified: bool = True,
    ) -> dict[str, Any]:
        return {
            "sha": sha,
            "author": None if author is None else {"id": author},
            "committer": {"id": author if committer is None else committer},
            "commit": {"verification": {"verified": verified}},
            "parents": [{"sha": "p"}] * parents,
        }

    def paths(self, commits: list[Any], files: dict[str, Any], pr: Any = None) -> Any:
        def get(endpoint: str) -> tuple[int, Any]:
            sha = endpoint.rsplit("/", 1)[1]
            return (200, {"files": files[sha]}) if sha in files else (502, None)

        with (
            mock.patch.object(policy, "_paginated", return_value=commits),
            mock.patch.object(policy, "_get", side_effect=get),
        ):
            return policy.foreign_paths(REPO, pr or owner_pr(), self.CHANGED)

    def test_only_other_accounts_commits_count(self) -> None:
        commits = [
            self.commit("a1", OWNER_ID),
            self.commit("l1", self.LANES),
            self.commit("n1", None),
        ]
        files = {
            "l1": [{"filename": ".github/a.yml", "previous_filename": ".github/o.yml"}],
            "n1": [{"filename": "scripts/x.sh"}],
        }
        self.assertEqual(
            self.paths(commits, files),
            frozenset({".github/a.yml", ".github/o.yml", "scripts/x.sh"}),
        )
        self.assertEqual(self.paths(commits[:1], {}), frozenset())

    def test_a_commit_is_the_authors_own_only_when_committed_and_verified(
        self,
    ) -> None:
        # The author id is the git author email, which anyone can set.
        x = {"x": [{"filename": ".github/x.yml"}]}
        forged = self.commit("x", OWNER_ID, self.LANES)
        self.assertEqual(self.paths([forged], x), frozenset({".github/x.yml"}))
        unverified = self.commit("x", OWNER_ID, verified=False)
        self.assertEqual(self.paths([unverified], x), frozenset({".github/x.yml"}))
        self.assertEqual(self.paths([self.commit("x", OWNER_ID)], x), frozenset())

    def test_a_trusted_apps_own_verified_commits_score_nothing(self) -> None:
        # An App commits through the API, so GitHub's web-flow commits it:
        # author and signature alone, the weaker case.
        app = owner_pr(
            user={
                "login": "melodic-plugin-release[bot]",
                "id": 337859524,
                "type": "Bot",
            }
        )
        own = self.commit("r1", 337859524, self.WEB_FLOW)
        unsigned = self.commit("r2", 337859524, self.WEB_FLOW, verified=False)
        # S&C: an App's commit someone else committed is not its own.
        other = self.commit("r3", 337859524, self.LANES)
        r3 = {"r3": [{"filename": "scripts/x.sh"}]}
        self.assertEqual(self.paths([other], r3, app), frozenset({"scripts/x.sh"}))
        files = {"r2": [{"filename": "scripts/x.sh"}]}
        self.assertEqual(self.paths([own], {}, app), frozenset())
        self.assertEqual(
            self.paths([own, unsigned], files, app), frozenset({"scripts/x.sh"})
        )

    def test_s_and_c_forged_merged_and_parentless_commits_score(self) -> None:
        # S&C review of #9107: an owner-email commit the lanes App committed,
        # a lanes App merge adding a PR file, and a parentless commit.
        changed = (".github/workflows/x.yml", "plugins/x/hooks/evil.sh")
        workflow = {"w": [{"filename": ".github/workflows/x.yml"}]}
        evil = {"m": [{"filename": "plugins/x/hooks/evil.sh"}]}
        cases = (
            (self.commit("w", OWNER_ID, self.LANES), workflow, changed[:1]),
            (self.commit("m", self.LANES, parents=2), evil, changed[1:]),
            (self.commit("w", self.LANES, parents=0), workflow, changed[:1]),
        )
        for commit, files, expected in cases:
            with (
                self.subTest(commit=commit["sha"], parents=len(commit["parents"])),
                mock.patch.object(policy, "_paginated", return_value=[commit]),
                mock.patch.object(
                    policy, "_get", return_value=(200, {"files": files[commit["sha"]]})
                ),
            ):
                self.assertEqual(
                    policy.foreign_paths(REPO, owner_pr(), changed), frozenset(expected)
                )

    def test_some_paths_are_never_the_authors_own(self) -> None:
        # The HIGH path floor always scores, even in a standards-sync PR whose
        # every commit is its own; everything else is the author's own.
        changed = frozenset(
            {
                ".github/workflows/pr-merge.yml",
                ".github/workflows/release-publish-plugins.yml",
                ".github/actions/check-trusted-trigger/action.yml",
                ".github/standards/trusted-actors/trusted-actors.json",
                ".github/actions/resolve-config/resolve.mjs",
                "CODEOWNERS",
                "docs/CODEOWNERS",
                ".claude/settings.json",
                "config/settings.local.json",
                ".gitmodules",
                "package.json",
                "plugins/x/package-lock.json",
                ".github/requirements-ci.txt",
                "docs/x.md",
                "plugins/x/skills/y/SKILL.md",
                "AGENTS.md",
                "plugins/x/hooks/h.sh",
                "plugins/x/.claude-plugin/plugin.json",
                ".github/scripts/pr-verify/resolve-pr.mjs",
            }
        )
        own = {
            ".github/workflows/pr-merge.yml",
            ".github/workflows/release-publish-plugins.yml",
            ".claude/settings.json",
            "config/settings.local.json",
            "package.json",
            "plugins/x/package-lock.json",
            ".github/requirements-ci.txt",
            "docs/x.md",
            "plugins/x/skills/y/SKILL.md",
            "AGENTS.md",
            "plugins/x/hooks/h.sh",
            "plugins/x/.claude-plugin/plugin.json",
            ".github/scripts/pr-verify/resolve-pr.mjs",
        }
        for user in (
            {"login": "melodic-standards-sync[bot]", "id": 300666570, "type": "Bot"},
            {"login": OWNER_LOGIN, "id": OWNER_ID, "type": "User"},
            {"login": "claude[bot]", "id": 209825114, "type": "Bot"},
            {"login": "cursoragent", "id": 199161495, "type": "User"},
        ):
            with (
                self.subTest(author=user["login"]),
                mock.patch.object(policy, "foreign_paths", return_value=frozenset()),
            ):
                self.assertEqual(
                    policy.own_paths(REPO, owner_pr(user=user), changed), own
                )
        with mock.patch.object(policy, "foreign_paths", return_value=None):
            self.assertEqual(policy.own_paths(REPO, owner_pr(), changed), frozenset())

    def test_a_model_app_owns_only_its_script_lines(self) -> None:
        # Owner decision Q14 (c): plugins/*/scripts/, less the never-exempt
        # paths. Top-level scripts/ runs in credentialed jobs on main (S&C).
        changed = frozenset(
            {
                "scripts/release-plugins.sh",
                "plugins/x/scripts/y.py",
                "Plugins/X/Scripts/Z.SH",
                "plugins/x/skills/s/scripts/y.py",
                "plugins/x/hooks/scripts/h.sh",
                "plugins/source-control/skills/babysit-prs/scripts/x.py",
                ".github/scripts/x.mjs",
                "plugins/x/.claude-plugin/plugin.json",
                "docs/x.md",
            }
        )
        user = {"login": "claude[bot]", "id": 209825114, "type": "Bot"}
        with mock.patch.object(policy, "foreign_paths", return_value=frozenset()):
            self.assertEqual(
                policy.own_paths(
                    REPO, owner_pr(user=user), changed, only=policy.MODEL_APP_OWN
                ),
                {"plugins/x/scripts/y.py", "Plugins/X/Scripts/Z.SH"},
            )

    def test_a_merge_commit_scores_its_files_the_pr_changed(self) -> None:
        resolved = self.commit("m1", self.LANES, parents=2)
        files = {"m1": [{"filename": ".github/x.yml"}, {"filename": "main-only.md"}]}
        self.assertEqual(self.paths([resolved], files), frozenset({".github/x.yml"}))
        clean = {"m1": [{"filename": "main-only.md"}]}
        self.assertEqual(self.paths([resolved], clean), frozenset())
        own = self.commit("m2", OWNER_ID, parents=2)
        self.assertEqual(self.paths([own], {}), frozenset())

    def test_a_listing_that_may_be_cut_off_or_fails_scores_every_path(self) -> None:
        lane = self.commit("l1", self.LANES)
        self.assertIsNone(self.paths([lane], {}))
        self.assertIsNone(self.paths([lane], {"l1": [{"filename": "x"}] * 300}))
        self.assertIsNone(self.paths([self.commit("a", OWNER_ID)] * 250, {}))
        with mock.patch.object(
            policy, "_paginated", side_effect=policy.PolicyReadError("502")
        ):
            self.assertIsNone(policy.foreign_paths(REPO, owner_pr(), self.CHANGED))


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

    def test_adoption_settings_reach_the_lane_and_the_report(self) -> None:
        gh = self.unreadable_variables()
        gh.rest[f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={SHA}"] = file_payload(
            LANE_PIPELINE + "adoption:\n  idle-hours: 48\n"
        )
        policy._TRUSTED_IDS.clear()
        # Read at the default branch head's SHA, never the PR's base ref
        # (owner decision Q22): a stacked PR's base is its author's.
        gh.rest[f"repos/{REPO}/contents/{policy.TRUSTED_ACTORS_PATH}?ref={SHA}"] = (
            file_payload(
                json.dumps(
                    {
                        "version": 1,
                        "actors": [
                            {"id": 5, "login": "a", "kind": "human"},
                            {"id": 77, "login": "b[bot]", "kind": "bot"},
                            # S&C E: never adopted, the lanes App and Dependabot.
                            {"id": 9, "login": IDENTITY, "kind": "bot"},
                            {"id": 49699333, "login": "dependabot[bot]", "kind": "bot"},
                        ],
                    }
                )
            )
        )
        lane = self.lane_clear()
        lane.return_value = policy.Eligibility(
            True, None, "C2", 41, adoption="idle-owner:24h"
        )
        result = self.lane_assess(
            post_merge=lambda floor, who: gate(), human_gated="awaiting-owner"
        )
        self.assertIsNone(result.reason)
        kwargs = lane.call_args.kwargs
        self.assertEqual(kwargs["human_gated"], "awaiting-owner")
        # The queue read names the resolved identity, the base and the head.
        with mock.patch.object(
            policy, "lane_queued_at_head", return_value=True
        ) as queued:
            self.assertTrue(kwargs["queued_at_head"]())
        queued.assert_called_once_with(REPO, 1, "trunk", IDENTITY, "e" * 40)
        self.assertEqual(kwargs["adoption_idle_hours"], 48)
        self.assertEqual(kwargs["adoption_owner_ids"], (5, 77))
        # The people (kind human) and the configured Apps: whose body is intent.
        self.assertEqual(kwargs["spec_from_body_ids"], (5,))
        # Q-REQ (a): the people may stand in for the idle wait, by the queue read.
        self.assertEqual(kwargs["adoption_human_ids"], (5,))
        with mock.patch.object(policy, "ejected_enqueue", return_value=None) as read:
            self.assertIsNone(kwargs["ejected_enqueue"]())
        read.assert_called_once_with(REPO, 1)
        self.assertEqual(result.details["eligibility"]["adoption"], "idle-owner:24h")

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


class TheInFlightCapIsTheDefaultBranchHeads(unittest.TestCase):
    """`merge.max-in-flight` caps the one merge queue, so every candidate of
    a run reads it at the default branch head, not at its own base; a failed
    head read refuses, since the head's config tightens every other setting
    (`TheStricterOfBaseAndMainGoverns`), and is never shared."""

    readable = LaneAssess.readable
    fake = Assess.fake
    assess = Assess.assess
    lane_assess = LaneAssess.lane_assess
    lane_clear = LaneAssess.lane_clear
    HEAD_CONFIG = f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={MAIN_SHA}"

    def moved(self, head_config: Any) -> GhFake:
        """Main has moved past the base (whose config has no cap) to a head
        whose config read answers `head_config`."""
        gh = self.readable()
        gh.rest[f"repos/{REPO}/commits/trunk"] = {"sha": MAIN_SHA}
        gh.rest[self.HEAD_CONFIG] = head_config
        gh.rest[
            f"repos/{REPO}/contents/{policy.SOURCE_CONTROL_PATH}?ref={MAIN_SHA}"
        ] = file_payload(SOURCE_CONTROL)
        return gh

    def cap(self) -> tuple[int, dict[str, Any]]:
        self.lane_clear()
        result = self.lane_assess(post_merge=lambda floor, who: gate())
        (call,) = policy.in_flight.call_args_list
        return call.kwargs["max_in_flight"], result.details["inFlight"]

    def test_the_heads_cap_governs_a_base_without_one(self) -> None:
        for base in (
            LANE_PIPELINE,
            LANE_PIPELINE.replace("merge:\n", "merge:\n  max-in-flight: 1\n"),
        ):
            with self.subTest(base=base):
                gh = self.moved(
                    file_payload(
                        LANE_PIPELINE.replace(
                            "merge:\n", "merge:\n  max-in-flight: 5\n"
                        )
                    )
                )
                gh.rest[f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={SHA}"] = (
                    file_payload(base)
                )
                cap, details = self.cap()
                self.assertEqual(cap, 5)
                self.assertEqual(details["cap"], 5)
                self.assertEqual(details["capSource"], "default-branch")

    def test_an_unreadable_head_config_refuses_and_an_unparsable_one_stops(
        self,
    ) -> None:
        for answer in (502, file_payload("merge: [unclosed\n")):
            with self.subTest(answer=answer):
                gh = self.moved(answer)
                gh.rest[f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={SHA}"] = (
                    file_payload(
                        LANE_PIPELINE.replace(
                            "merge:\n", "merge:\n  max-in-flight: 3\n"
                        )
                    )
                )
                if answer == 502:
                    with self.assertRaises(policy.PolicyReadError):
                        self.cap()
                    continue
                self.lane_clear()
                result = self.lane_assess(post_merge=lambda floor, who: gate())
                self.assertEqual(result.reason, "default-branch-unreadable")
                policy.in_flight.assert_not_called()

    def test_the_heads_cap_is_shared_per_cache_window_and_a_failure_never(
        self,
    ) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        env = {"BABYSIT_RUN_CACHE": str(pathlib.Path(tmp.name, "run.json"))}
        patcher = mock.patch.dict("os.environ", env)
        patcher.start()
        self.addCleanup(patcher.stop)
        gh = self.moved(502)
        for _ in range(2):
            self.lane_clear()
            with self.assertRaises(policy.PolicyReadError):
                self.lane_assess(post_merge=lambda floor, who: gate())
        self.assertEqual(gh.calls.count(["api", self.HEAD_CONFIG]), 2)
        gh.rest[self.HEAD_CONFIG] = file_payload(
            LANE_PIPELINE.replace("merge:\n", "merge:\n  max-in-flight: 5\n")
        )
        for _ in range(2):
            self.assertEqual(self.cap()[0], 5)
        self.assertEqual(gh.calls.count(["api", self.HEAD_CONFIG]), 3)


# Two lane pipelines differing in every merge setting: LOOSE allows more on
# each, STRICT less.
LOOSE_PIPELINE = """\
merge:
  rung: C3
  authority: pr-merge
  agent-identity: agent-lanes[bot]
  report-only: false
  require-verifier-verdict: false
  max-queue-ejections: 5
  max-verify-fails: 4
  risk-escalation-minutes: 90
  check-inputs: ["x/**"]
  dependabot:
    mode: enforce
    majors: review
  diff-check:
    denied-paths: [".github/**"]
    high-path-floor: false
    max-changed-lines: 500
"""
STRICT_PIPELINE = """\
merge:
  rung: C2
  authority: pr-merge
  agent-identity: agent-lanes[bot]
  report-only: true
  require-verifier-verdict: true
  max-queue-ejections: 1
  max-verify-fails: 2
  risk-escalation-minutes: 10
  check-inputs: ["y/**"]
  dependabot:
    mode: report
    majors: hold
  diff-check:
    denied-paths: [".github/**", "docs/**"]
    high-path-floor: true
    max-changed-lines: 100
    max-changed-files: 0
"""
LOOSE_SOURCE = "## babysit_loop_merge\n\nc3-autonomous\n"


class TheStricterOfBaseAndMainGoverns(unittest.TestCase):
    """GitHub never moves a pull request's base SHA as the default branch
    advances, so the gate combines the merge config at the base with the one
    at the default branch head, taking the stricter value of each setting: a
    tightening on main reaches pull requests opened before it, and a pull
    request still cannot drop its own base's declaration. Expected values are
    the per-setting rules the owner decided."""

    readable = LaneAssess.readable
    fake = Assess.fake
    assess = Assess.assess
    lane_assess = LaneAssess.lane_assess
    lane_clear = LaneAssess.lane_clear
    MAIN_CONFIG = f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={MAIN_SHA}"

    def moved(
        self,
        base: str,
        main: Any,
        *,
        base_source: str = SOURCE_CONTROL,
        main_source: str = SOURCE_CONTROL,
    ) -> GhFake:
        """The base's pipeline is `base`; main has moved to MAIN_SHA, whose
        pipeline read answers `main` (text, an HTTP status, or None for an
        absent file)."""
        gh = self.readable()
        gh.rest[f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={SHA}"] = file_payload(
            base
        )
        gh.rest[f"repos/{REPO}/contents/{policy.SOURCE_CONTROL_PATH}?ref={SHA}"] = (
            file_payload(base_source)
        )
        gh.rest[f"repos/{REPO}/commits/trunk"] = {"sha": MAIN_SHA}
        gh.rest[f"repos/{REPO}/contents?ref={MAIN_SHA}"] = []
        gh.rest[self.MAIN_CONFIG] = (
            404
            if main is None
            else (main if isinstance(main, int) else file_payload(main))
        )
        gh.rest[
            f"repos/{REPO}/contents/{policy.SOURCE_CONTROL_PATH}?ref={MAIN_SHA}"
        ] = file_payload(main_source)
        return gh

    def config(self) -> Any:
        self.lane_clear()
        result = self.lane_assess(post_merge=lambda floor, who: gate())
        return result.inputs["config"]

    def assert_strict(self, config: Any, escalation_minutes: int) -> None:
        expected = {
            "rung": "C2",
            "loop_merge": "c2-mechanical",
            "report_only": True,
            "require_verifier_verdict": True,
            "high_path_floor": True,
            "max_changed_lines": 100,
            "max_changed_files": 0,
            "dependabot_mode": "report",
            "dependabot_majors": "hold",
            "max_queue_ejections": 1,
            "max_verify_fails": 2,
            "agent_identity": IDENTITY,
            # Timing only: the base's, whichever side is stricter.
            "risk_escalation_minutes": escalation_minutes,
        }
        for name, value in expected.items():
            with self.subTest(setting=name):
                self.assertEqual(getattr(config, name), value)
        unions = {
            "denied_paths": {".github/**", "docs/**"},
        }
        for name, value in unions.items():
            with self.subTest(setting=name):
                self.assertEqual(set(getattr(config, name)), value)
        with self.subTest(setting="check_inputs"):
            # Both lists are read, each in its own diff.
            self.assertEqual(
                set(config.check_inputs) | set(config.head_check_inputs),
                {"x/**", "y/**"},
            )

    def test_a_stricter_main_tightens_every_setting(self) -> None:
        self.moved(
            LOOSE_PIPELINE,
            STRICT_PIPELINE,
            base_source=LOOSE_SOURCE,
            main_source=SOURCE_CONTROL,
        )
        self.assert_strict(self.config(), 90)

    def test_a_stricter_base_is_never_loosened_by_main(self) -> None:
        self.moved(
            STRICT_PIPELINE,
            LOOSE_PIPELINE,
            base_source=SOURCE_CONTROL,
            main_source=LOOSE_SOURCE,
        )
        self.assert_strict(self.config(), 10)

    def test_main_turning_report_only_on_reports_the_base_pull_request(
        self,
    ) -> None:
        self.moved(LOOSE_PIPELINE, STRICT_PIPELINE)
        self.lane_clear()
        result = self.lane_assess(post_merge=lambda floor, who: gate())
        self.assertIs(result.details["reportOnly"], True)

    def test_main_turning_the_rung_off_refuses(self) -> None:
        self.moved(LOOSE_PIPELINE, LOOSE_PIPELINE.replace("rung: C3", "rung: off"))
        self.lane_clear()
        result = self.lane_assess(post_merge=lambda floor, who: gate())
        self.assertEqual(result.reason, "rung-off:merge.rung")

    def test_main_dropping_the_pipeline_or_identity_stops_the_lane(self) -> None:
        # Either switches the lane off on main: a stop, as rung: off is, so
        # the identity's queued entries leave.
        for main in (
            None,
            LOOSE_PIPELINE.replace("  agent-identity: agent-lanes[bot]\n", ""),
        ):
            with self.subTest(main=main):
                self.moved(LOOSE_PIPELINE, main)
                self.lane_clear()
                result = self.lane_assess(post_merge=lambda floor, who: gate())
                self.assertEqual(result.reason, "authority-differs")
                self.assertEqual(result.inputs["identity"], IDENTITY)

    def test_an_implicit_and_an_explicit_pr_merge_authority_agree(self) -> None:
        implicit = LOOSE_PIPELINE.replace("  authority: pr-merge\n", "")
        for base, main in ((implicit, LOOSE_PIPELINE), (LOOSE_PIPELINE, implicit)):
            with self.subTest(base=base is implicit):
                self.moved(base, main)
                self.lane_clear()
                result = self.lane_assess(post_merge=lambda floor, who: gate())
                # Past the authority and identity checks: the path stays enabled.
                self.assertIs(result.enabled, True)

    def test_an_identity_differing_only_in_case_agrees(self) -> None:
        self.moved(
            LOOSE_PIPELINE,
            LOOSE_PIPELINE.replace("agent-lanes[bot]", "Agent-Lanes[bot]"),
        )
        self.lane_clear()
        result = self.lane_assess(post_merge=lambda floor, who: gate())
        # Past the authority and identity checks: the path stays enabled.
        self.assertIs(result.enabled, True)

    def test_main_turning_dependabot_enforce_down_reports_a_dependabot_pr(
        self,
    ) -> None:
        # A Dependabot pull request's report-only is its own mode short of
        # enforce, recomputed from the combined config.
        gh = self.moved(LOOSE_PIPELINE, STRICT_PIPELINE)
        gh.rest[f"repos/{REPO}/pulls/1"]["user"] = {
            "login": "dependabot[bot]",
            "type": "Bot",
        }
        tier = policy.dependabot.Classification("auto")
        self.lane_clear()
        with mock.patch.object(
            policy,
            "dependabot_eligibility",
            return_value=policy.Eligibility(True, None, "C2", dependabot=tier),
        ):
            result = self.lane_assess(post_merge=lambda floor, who: gate())
        self.assertIs(result.details["reportOnly"], True)
        self.assertEqual(result.details["dependabot"]["mode"], "report")

    def test_main_enabling_another_authority_disables_the_lane(self) -> None:
        self.moved(LOOSE_PIPELINE, LOOSE_PIPELINE.replace("pr-merge", "local-babysit"))
        self.lane_clear()
        result = self.lane_assess(post_merge=lambda floor, who: gate())
        self.assertEqual(result.reason, "authority-differs")
        self.assertIs(result.enabled, False)

    def test_an_unreadable_main_config_refuses(self) -> None:
        self.moved(LOOSE_PIPELINE, 502)
        self.lane_clear()
        with self.assertRaises(policy.PolicyReadError):
            self.lane_assess(post_merge=lambda floor, who: gate())

    def test_an_unparsable_main_config_stops(self) -> None:
        duplicate = LOOSE_PIPELINE.replace("merge:\n", "merge:\n  rung: C2\n")
        for main in ("merge: [unclosed\n", duplicate):
            with self.subTest(main=main):
                self.moved(LOOSE_PIPELINE, main)
                self.lane_clear()
                result = self.lane_assess(post_merge=lambda floor, who: gate())
                self.assertEqual(result.reason, "default-branch-unreadable")
                self.assertIs(result.enabled, False)
                self.assertEqual(result.inputs["identity"], IDENTITY)

    def test_an_unreadable_main_head_refuses(self) -> None:
        gh = self.moved(LOOSE_PIPELINE, LOOSE_PIPELINE)
        gh.rest[f"repos/{REPO}/commits/trunk"] = 502
        self.lane_clear()
        with self.assertRaises(policy.PolicyReadError):
            self.lane_assess(post_merge=lambda floor, who: gate())

    def test_a_different_identity_on_main_stops(self) -> None:
        self.moved(
            LOOSE_PIPELINE, LOOSE_PIPELINE.replace("agent-lanes[bot]", "other[bot]")
        )
        self.lane_clear()
        result = self.lane_assess(post_merge=lambda floor, who: gate())
        self.assertEqual(result.reason, "authority-differs")
        self.assertIs(result.enabled, False)
        self.assertEqual(result.inputs["identity"], IDENTITY)

    def test_the_plain_merge_identity_read_names_both_identities(
        self,
    ) -> None:
        self.moved(
            LOOSE_PIPELINE, LOOSE_PIPELINE.replace("agent-lanes[bot]", "other[bot]")
        )
        resolved = policy.resolve(REPO, 1)
        self.assertEqual(resolved.agent_identity, IDENTITY)
        self.assertEqual(resolved.details["agentIdentities"], [IDENTITY, "other[bot]"])

    def test_main_is_read_once_per_cache_window_and_a_failure_never_saved(
        self,
    ) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        env = {"BABYSIT_RUN_CACHE": str(pathlib.Path(tmp.name, "run.json"))}
        patcher = mock.patch.dict("os.environ", env)
        patcher.start()
        self.addCleanup(patcher.stop)
        gh = self.moved(LOOSE_PIPELINE, 502)
        for _ in range(2):
            self.lane_clear()
            with self.assertRaises(policy.PolicyReadError):
                self.lane_assess(post_merge=lambda floor, who: gate())
        self.assertEqual(gh.calls.count(["api", self.MAIN_CONFIG]), 2)
        gh.rest[self.MAIN_CONFIG] = file_payload(STRICT_PIPELINE)
        for _ in range(3):
            self.assertEqual(self.config().rung, "C2")
        self.assertEqual(gh.calls.count(["api", self.MAIN_CONFIG]), 3)


class TheStricterConfigEdges(unittest.TestCase):
    """The combination never lets the default branch's config loosen the
    base's through a side door: the in-flight fallback, a cached copy, or a
    check-inputs pathspec."""

    BASE = policy.PipelineConfig(
        SHA, "C2", "pr-merge", IDENTITY, None, (), "c2-mechanical", max_in_flight=5
    )

    def test_a_failed_cap_re_read_never_exceeds_mains_cap(self) -> None:
        main = dataclasses.replace(self.BASE, base_sha=MAIN_SHA, max_in_flight=1)
        gh = GhFake().install(self)
        gh.rest[f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={MAIN_SHA}"] = 502
        cap, _ = policy._run_max_in_flight(
            REPO,
            "trunk",
            MAIN_SHA,
            policy.stricter_config(self.BASE, main),
            shared=False,
        )
        self.assertEqual(cap, 1)

    def test_an_exclude_pathspec_on_main_never_removes_a_base_path(self) -> None:
        base = dataclasses.replace(self.BASE, check_inputs=("scripts/a.txt",))
        for exclude in (
            ":!scripts/a.txt",
            ":(exclude)scripts/a.txt",
            ":^scripts/a.txt",
        ):
            with self.subTest(exclude=exclude):
                main = dataclasses.replace(
                    base, base_sha=MAIN_SHA, check_inputs=("scripts/b.txt", exclude)
                )
                combined = policy.stricter_config(base, main)
                # Each list is listed on its own, so main's exclude reaches
                # only main's paths.
                self.assertEqual(combined.check_inputs, ("scripts/a.txt",))
                self.assertEqual(combined.head_check_inputs, ("scripts/b.txt", exclude))

    def test_a_malformed_cached_main_config_is_read_again(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        env = {"BABYSIT_RUN_CACHE": str(pathlib.Path(tmp.name, "run.json"))}
        patcher = mock.patch.dict("os.environ", env)
        patcher.start()
        self.addCleanup(patcher.stop)
        good = dataclasses.asdict(dataclasses.replace(self.BASE, base_sha=MAIN_SHA))
        for broken in (
            {**good, "rung": "C9"},
            {**good, "dependabot_mode": "always"},
            {**good, "max_in_flight": "five"},
            {**good, "notes": 7},
            {**good, "denied_paths": [1, 2]},
            {**good, "adoption_idle_hours": 0},
            {**good, "adoption_idle_hours": 721},
        ):
            with self.subTest(broken=broken):
                # No commit's config saved by an earlier case either.
                pathlib.Path(env["BABYSIT_RUN_CACHE"]).unlink(missing_ok=True)
                policy.run_cache.put(policy.DEFAULT_BRANCH_CONFIG_SECTION, REPO, broken)
                gh = config_fake(self, PIPELINE.replace("local-babysit", "pr-merge"))
                gh.rest[f"repos/{REPO}"] = {"default_branch": "trunk"}
                gh.rest[f"repos/{REPO}/commits/trunk"] = {"sha": MAIN_SHA}
                gh.rest[f"repos/{REPO}/contents?ref={MAIN_SHA}"] = []
                for path, text in (
                    (policy.CONFIG_PATH, PIPELINE.replace("local-babysit", "pr-merge")),
                    (policy.SOURCE_CONTROL_PATH, SOURCE_CONTROL),
                ):
                    gh.rest[f"repos/{REPO}/contents/{path}?ref={MAIN_SHA}"] = (
                        file_payload(text)
                    )
                combined = policy.with_default_branch(
                    REPO, dataclasses.replace(self.BASE, max_changed_lines=200)
                )
                self.assertEqual(combined.rung, "C2")
                self.assertIn(
                    [
                        "api",
                        f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={MAIN_SHA}",
                    ],
                    gh.calls,
                )


class ConfigAtIsSharedByCommit(unittest.TestCase):
    """`config_at`: one read of the config files per commit per run, shared
    through the run cache by commit; a read with a note is read again."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        env = {"BABYSIT_RUN_CACHE": str(pathlib.Path(tmp.name, "run.json"))}
        patcher = mock.patch.dict("os.environ", env)
        patcher.start()
        self.addCleanup(patcher.stop)

    def reads(self, gh: GhFake, sha: str) -> int:
        endpoint = f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={sha}"
        return gh.calls.count(["api", endpoint])

    def test_a_commit_is_read_once_and_another_commit_again(self) -> None:
        gh = config_fake(self, PIPELINE)
        first = policy.config_at(REPO, SHA)
        second = policy.config_at(REPO, SHA)
        self.assertEqual((first.rung, second.rung), ("C2", "C2"))
        self.assertEqual(second.loop_merge, "c2-mechanical")
        self.assertEqual(self.reads(gh, SHA), 1)
        other = "b" * 40
        gh.rest[f"repos/{REPO}/contents?ref={other}"] = []
        for path, text in (
            (policy.CONFIG_PATH, PIPELINE.replace("rung: C2", "rung: C3")),
            (policy.SOURCE_CONTROL_PATH, SOURCE_CONTROL),
        ):
            gh.rest[f"repos/{REPO}/contents/{path}?ref={other}"] = file_payload(text)
        self.assertEqual(policy.config_at(REPO, other).rung, "C3")
        self.assertEqual(self.reads(gh, other), 1)

    def test_a_read_with_a_note_is_not_saved(self) -> None:
        gh = config_fake(self, PIPELINE, source=502)
        self.assertIsNone(policy.config_at(REPO, SHA).loop_merge)
        policy.config_at(REPO, SHA)
        self.assertEqual(self.reads(gh, SHA), 2)

    def test_the_default_branch_config_is_read_again_only_when_its_head_moves(
        self,
    ) -> None:
        gh = config_fake(self, PIPELINE.replace("local-babysit", "pr-merge"))
        gh.rest[f"repos/{REPO}"] = {"default_branch": "trunk"}
        gh.rest[f"repos/{REPO}/commits/trunk"] = {"sha": SHA}
        start = datetime(2026, 10, 24, 12, 0, tzinfo=UTC)
        base = policy.PipelineConfig(MAIN_SHA, "C2", "pr-merge", None, None, (), None)
        # Past the repository-keyed window (two minutes), the head is read
        # again and the same commit's config comes from the cache.
        for minutes in (0, 3, 6):
            with mock.patch.object(
                policy.run_cache, "now", return_value=start + timedelta(minutes=minutes)
            ):
                policy.with_default_branch(REPO, base)
        self.assertEqual(gh.calls.count(["api", f"repos/{REPO}/commits/trunk"]), 3)
        self.assertEqual(self.reads(gh, SHA), 1)


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
        # The merge config at the head this class moves main to: the base's.
        for sha in (MAIN_SHA, "f" * 40):
            gh.rest[f"repos/{REPO}/contents/{policy.CONFIG_PATH}?ref={sha}"] = (
                file_payload(LANE_PIPELINE)
            )
            gh.rest[f"repos/{REPO}/contents/{policy.SOURCE_CONTROL_PATH}?ref={sha}"] = (
                file_payload(SOURCE_CONTROL)
            )
        gh.rest[NEWEST_CONFIG] = [{"sha": CONFIG_SHA}]
        self.computed_at = policy.datetime.now(policy.UTC)
        gh.rest[self.issues_since()] = []
        return gh

    def issues_since(self) -> str:
        """The demotion re-read: issues updated since the answer, to the
        second GitHub's `since` takes, less the clock margin."""
        since = (self.computed_at - policy.SINCE_CLOCK_MARGIN).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
        return f"repos/{REPO}/issues?state=all&since={since}&per_page=100"

    def shared(self, gate_: policy.PostMergeGate, **overrides: Any) -> Any:
        fields: dict[str, Any] = {
            "main_sha": MAIN_SHA,
            "config_sha": CONFIG_SHA,
            "identity": IDENTITY,
            "self_logins": frozenset(),
            "lane_merges_only": True,
            "computed_at": self.computed_at,
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
        # Where the cap was read is provenance, not a decision: an unreadable
        # head falls back to the base's cap.
        if isinstance(details.get("inFlight"), dict):
            details["inFlight"] = {
                k: v for k, v in details["inFlight"].items() if k != "capSource"
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

    def moved(self, merges: Any) -> GhFake:
        """Bound, but the default branch moved to a head that merged
        `merges` (a PolicyRecentMerges answer) since the floor."""
        gh = self.bound()
        gh.rest[f"repos/{REPO}/commits/trunk"] = {"sha": "f" * 40}
        gh.graphql["PolicyRecentMerges"] = merges
        return gh

    def test_a_moved_head_with_no_new_lane_merge_decides_as_the_fresh_reads_do(
        self,
    ) -> None:
        # The check judges only the identity's merges since the floor, so a
        # person's merge, another App's, or one already in the answer moves
        # the head without changing the answer.
        counted = policy.PostMergeGate(
            None, {"ok": True, "autoMerges": [{"number": 7}]}, lambda m: True
        )
        merges = merge_pages(
            [
                [
                    merged(9, user(OPERATOR), user(OPERATOR)),
                    merged(8, bot("release"), bot("release")),
                    merged(7, bot("agent-lanes"), None),
                ]
            ]
        )
        self.moved(merges)
        self.flight()
        fresh = self.lane_assess(post_merge=lambda floor, who: counted)
        gh = self.moved(merges)
        gh.rest[f"repos/{REPO}/commits/trunk"] = {"sha": "f" * 40}
        self.flight()
        never = mock.Mock(side_effect=AssertionError("read fresh"))
        with mock.patch.object(policy, "read_demotion", never):
            reused = self.lane_assess(post_merge=never, shared=self.shared(counted))
        self.assertEqual(reused.details["postMergeShared"], "used")
        self.assertEqual(self.decided(reused), self.decided(fresh))
        # An unreadable head leaves its config unread, which refuses.
        gh.rest[f"repos/{REPO}/commits/trunk"] = 502
        with self.assertRaises(policy.PolicyReadError):
            self.lane_assess(post_merge=never, shared=self.shared(counted))

    def test_a_base_behind_with_the_same_floor_decides_as_the_fresh_reads_do(
        self,
    ) -> None:
        # A later config commit on the default branch that keeps the path
        # enabled leaves the floor where the base's own history puts it.
        answer = gate("failure:canary#7708")
        self.bound().rest[NEWEST_CONFIG] = [{"sha": "f" * 40}]
        self.flight()
        fresh = self.lane_assess(post_merge=lambda floor, who: answer)
        self.bound().rest[NEWEST_CONFIG] = [{"sha": "f" * 40}]
        self.flight()
        never = mock.Mock(side_effect=AssertionError("read fresh"))
        with mock.patch.object(policy, "read_demotion", never):
            reused = self.lane_assess(post_merge=never, shared=self.shared(answer))
        self.assertEqual(reused.details["postMergeShared"], "used")
        self.assertEqual(self.decided(reused), self.decided(fresh))

    def test_a_demotion_record_filed_since_the_answer_is_not_missed(self) -> None:
        # The answer says not demoted; a record opened after it, an edit or
        # close of a known record, an unreadable re-read, or a full page
        # sends the pull request to its own demotion read.
        record = {
            "number": 90,
            "user": {"login": "github-actions[bot]"},
            "body": DEMOTION_BODY,
            "state": "open",
        }
        known = {"number": 12, "user": {"login": OPERATOR}, "state": "closed"}
        full = [
            {"number": 1000 + n, "user": {"login": OPERATOR}, "state": "open"}
            for n in range(100)
        ]
        for issues, records in (
            ([record], ()),
            ([known], (12,)),
            (502, ()),
            (full, ()),
        ):
            with self.subTest(issues=issues):
                gh = self.bound()
                gh.rest[self.issues_since()] = issues
                self.flight()
                reads = mock.Mock(wraps=policy.read_demotion)
                seen: list[Any] = []
                with mock.patch.object(policy, "read_demotion", reads):
                    result = self.lane_assess(
                        post_merge=lambda floor, who: seen.append(floor) or gate(),
                        shared=self.shared(
                            gate("failure:canary#1"),
                            demotion=policy.Demotion(False, None, records),
                        ),
                    )
                self.assertEqual(
                    result.details["postMergeShared"], "unused:demotion-changed"
                )
                reads.assert_called_once()
                self.assertEqual(seen, [policy.datetime.fromisoformat(ENABLED_AT)])

    def test_an_unrelated_issue_or_a_pull_request_leaves_the_answer_bound(
        self,
    ) -> None:
        gh = self.bound()
        gh.rest[self.issues_since()] = [
            {"number": 91, "user": {"login": OPERATOR}, "state": "open"},
            {"number": 92, "user": {"login": IDENTITY}, "pull_request": {}},
        ]
        self.flight()
        never = mock.Mock(side_effect=AssertionError("read fresh"))
        result = self.lane_assess(post_merge=never, shared=self.shared(gate()))
        self.assertEqual(result.details["postMergeShared"], "used")

    def test_a_fresh_filer_issue_without_the_marker_leaves_the_answer_bound(
        self,
    ) -> None:
        # `read_demotion` never counts it: no marker, and never touched since
        # it was opened, so no earlier revision could carry one.
        gh = self.bound()
        gh.rest[self.issues_since()] = [
            {
                "number": 93,
                "user": {"login": "github-actions[bot]"},
                "body": "Scheduled report",
                "state": "open",
                "created_at": "2026-10-24T07:00:33Z",
                "updated_at": "2026-10-24T07:00:33Z",
            }
        ]
        self.flight()
        never = mock.Mock(side_effect=AssertionError("read fresh"))
        with mock.patch.object(policy, "read_demotion", never):
            result = self.lane_assess(post_merge=never, shared=self.shared(gate()))
        self.assertEqual(result.details["postMergeShared"], "used")

    def test_a_demoted_answer_needs_no_re_read(self) -> None:
        # Already demoted, the answer is the conservative one.
        gh = self.bound()
        del gh.rest[self.issues_since()]
        self.flight()
        demoted = policy.Demotion(True, "#5 open", (5,))
        result = self.lane_assess(
            post_merge=mock.Mock(side_effect=AssertionError("read fresh")),
            shared=self.shared(gate(), demotion=demoted),
        )
        self.assertEqual(result.details["postMergeShared"], "used")

    def test_an_unbound_answer_is_not_used(self) -> None:
        late = policy.datetime.now(policy.UTC) - policy.timedelta(minutes=31)
        other_floor = policy.datetime.fromisoformat("2026-10-11T00:00:00Z")
        lane_merge = merge_pages([[merged(7, bot("agent-lanes"), None)]])
        moved = {f"repos/{REPO}/commits/trunk": {"sha": "f" * 40}}
        for overrides, rest, graphql, reason in (
            ({}, moved, {"PolicyRecentMerges": lane_merge}, "new-merge:#7"),
            ({}, moved, {"PolicyRecentMerges": 502}, "merged-unreadable"),
            (
                {},
                moved,
                {"PolicyRecentMerges": merge_pages([[]], endless=True)},
                "merged-history-truncated",
            ),
            (
                {"floor": other_floor},
                {NEWEST_CONFIG: [{"sha": "f" * 40}]},
                {},
                "floor-differs",
            ),
            ({}, {NEWEST_CONFIG: 404}, {}, "config-unreadable"),
            ({"identity": "other[bot]"}, {}, {}, "identity-differs"),
            ({"self_logins": frozenset({"x[bot]"})}, {}, {}, "self-logins-differ"),
            ({"lane_merges_only": False}, {}, {}, "lane-differs"),
            ({"computed_at": late}, {}, {}, "stale"),
        ):
            with self.subTest(reason=reason, rest=rest):
                gh = self.bound()
                gh.rest.update(rest)
                gh.graphql.update(graphql)
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


def lane_gate(verified: bool, failed: bool = False) -> policy.PostMergeGate:
    """The check's answer on lane merge #8040: its verifying run passed,
    is still pending, or failed."""
    return babysit_postmerge.gate_from_report(
        {
            "ok": not failed,
            "readable": True,
            "autoMerges": [{"number": 8040, "verified": verified}],
            "failures": [{"signal": "full-run", "number": 8040}] if failed else [],
        }
    )


class DemotionChanged(unittest.TestCase):
    """`_demotion_changed`: an issue updated since the answer counts only
    when `read_demotion` could count it as a record. That is a known record,
    or a record filer's issue whose body carries the marker now, or that may
    have been edited since it was opened (`updated_at` differs from
    `created_at`, or either is unreadable), so an earlier revision could."""

    OPENED = "2026-10-24T07:00:33Z"

    def changed(self, issue: dict[str, Any], records: tuple[int, ...] = ()) -> bool:
        answer = policy.SharedPostMerge(
            main_sha=MAIN_SHA,
            config_sha=CONFIG_SHA,
            identity=IDENTITY,
            self_logins=frozenset(),
            lane_merges_only=True,
            computed_at=policy.datetime.fromisoformat(self.OPENED),
            demotion=policy.Demotion(False, None, records),
            floor=policy.datetime.fromisoformat(ENABLED_AT),
            gate=gate(),
        )
        with mock.patch.object(policy, "_get", return_value=(200, [issue])):
            return policy._demotion_changed("owner", "repo", answer, IDENTITY)

    def filed(self, **fields: Any) -> dict[str, Any]:
        """A fresh, unedited issue `github-actions[bot]` opened, no marker."""
        issue = {
            "number": 93,
            "user": {"login": "github-actions[bot]"},
            "body": "Scheduled report",
            "state": "open",
            "created_at": self.OPENED,
            "updated_at": self.OPENED,
        }
        issue.update(fields)
        return {k: v for k, v in issue.items() if v is not None}

    def test_a_fresh_unedited_filer_issue_without_the_marker_is_unchanged(
        self,
    ) -> None:
        self.assertFalse(self.changed(self.filed()))
        self.assertFalse(self.changed(self.filed(user={"login": IDENTITY})))
        self.assertFalse(self.changed(self.filed(body="")))

    def test_a_filer_issue_with_the_marker_is_changed(self) -> None:
        self.assertTrue(self.changed(self.filed(body=DEMOTION_BODY)))

    def test_a_filer_issue_touched_since_it_was_opened_is_changed(self) -> None:
        self.assertTrue(self.changed(self.filed(updated_at="2026-10-24T07:05:00Z")))

    def test_a_filer_issue_without_readable_timestamps_is_changed(self) -> None:
        for fields in (
            {"created_at": None},
            {"updated_at": None},
            {"created_at": None, "updated_at": None},
            {"updated_at": "not a time"},
            {"created_at": "2026-10-24T07:00:33"},
        ):
            with self.subTest(fields=fields):
                self.assertTrue(self.changed(self.filed(**fields)))

    def test_a_known_record_updated_is_changed(self) -> None:
        known = self.filed(user={"login": OPERATOR}, number=12)
        self.assertTrue(self.changed(known, records=(12,)))
        # Its author and its timestamps do not matter.
        self.assertTrue(self.changed(self.filed(number=12), records=(12,)))


class AStaleSharedAnswerIsRefreshed(unittest.TestCase):
    """A shared answer that still waits on a lane merge's verifying run is
    read again once `SHARED_UNVERIFIED_MAX_AGE` old, and each recompute is
    handed back (`share`) for the next candidate. A recompute decides as a
    from-scratch run at that moment does: only a passed verification clears."""

    readable = LaneAssess.readable
    fake = Assess.fake
    assess = Assess.assess
    lane_assess = LaneAssess.lane_assess
    bound = SharedPostMergeAnswer.bound
    issues_since = SharedPostMergeAnswer.issues_since
    shared = SharedPostMergeAnswer.shared
    decided = SharedPostMergeAnswer.decided
    moved = SharedPostMergeAnswer.moved

    def judged_flight(self) -> None:
        """`in_flight` as the post-merge answer judges #8040, with the
        eligibility reader clear."""

        def judge(repo: str, **kwargs: Any) -> policy.InFlight:
            verified = kwargs["verified"]
            if verified is not None and verified(mock.Mock(number=8040)):
                return policy.InFlight(True, None, frozenset())
            return policy.InFlight(False, "unverified-auto-merge:#8040", frozenset())

        for name, kwargs in (
            ("in_flight", {"side_effect": judge}),
            (
                "lane_eligibility",
                {"return_value": policy.Eligibility(True, None, "C2")},
            ),
        ):
            patcher = mock.patch.object(policy, name, **kwargs)
            patcher.start()
            self.addCleanup(patcher.stop)

    def aged(self, minutes: float) -> GhFake:
        """Bound, with the answer computed `minutes` ago."""
        gh = self.bound()
        self.computed_at -= policy.timedelta(minutes=minutes)
        gh.rest[self.issues_since()] = []
        return gh

    def test_a_stale_unverified_answer_decides_as_a_from_scratch_run(self) -> None:
        # Pending at the shared read; by now the run passed, is still pending,
        # or failed. Only a pass clears the in-flight refusal.
        for fresh, expected in (
            (lane_gate(True), None),
            (lane_gate(False), "in-flight:unverified-auto-merge:#8040"),
            (lane_gate(False, failed=True), "post-merge:failure:full-run#8040"),
        ):
            with self.subTest(expected=expected):
                self.bound()
                self.judged_flight()
                scratch = self.lane_assess(post_merge=lambda floor, who: fresh)
                self.aged(3)
                self.judged_flight()
                seen: list[Any] = []
                shared: list[policy.SharedPostMerge] = []
                refreshed = self.lane_assess(
                    post_merge=lambda floor, who: seen.append(floor) or fresh,
                    shared=self.shared(lane_gate(False)),
                    share=shared.append,
                )
                self.assertEqual(
                    refreshed.details["postMergeShared"], "unused:unverified-stale"
                )
                self.assertEqual(seen, [policy.datetime.fromisoformat(ENABLED_AT)])
                self.assertEqual(refreshed.reason, expected)
                self.assertEqual(self.decided(refreshed), self.decided(scratch))
                self.assertEqual(len(shared), 1)

    def test_the_candidate_that_refreshed_proceeds_through_the_rest_of_the_gate(
        self,
    ) -> None:
        # Judged against the fresh answer in the same invocation: no in-flight
        # refusal, and every later read runs as a from-scratch run's does.
        self.aged(3)
        self.judged_flight()
        refreshed = self.lane_assess(
            post_merge=lambda floor, who: lane_gate(True),
            shared=self.shared(lane_gate(False)),
            share=lambda answer: None,
        )
        self.assertEqual(
            refreshed.details["inFlight"],
            {"clear": True, "reason": None, "cap": 1, "capSource": "default-branch"},
        )
        self.assertIsNone(refreshed.reason)
        self.assertTrue(refreshed.enabled)
        self.assertIn("eligibility", refreshed.details)

    def test_the_refreshed_in_flight_read_carries_the_configured_cap(
        self,
    ) -> None:
        self.aged(3)
        self.judged_flight()
        read = policy.read_config_at
        with mock.patch.object(
            policy,
            "read_config_at",
            side_effect=lambda *a, **k: dataclasses.replace(
                read(*a, **k), max_in_flight=5
            ),
        ):
            self.lane_assess(
                post_merge=lambda floor, who: lane_gate(False),
                shared=self.shared(lane_gate(False)),
                share=lambda answer: None,
            )
        (call,) = policy.in_flight.call_args_list
        self.assertEqual(call.kwargs["max_in_flight"], 5)

    def test_a_stale_answer_with_every_merge_verified_is_reused(self) -> None:
        self.aged(3)
        self.judged_flight()
        never = mock.Mock(side_effect=AssertionError("read fresh"))
        share = mock.Mock()
        result = self.lane_assess(
            post_merge=never, shared=self.shared(lane_gate(True)), share=share
        )
        self.assertEqual(result.details["postMergeShared"], "used")
        self.assertIsNone(result.reason)
        share.assert_not_called()

    def test_a_fresh_unverified_answer_is_reused(self) -> None:
        self.aged(1.5)
        self.judged_flight()
        never = mock.Mock(side_effect=AssertionError("read fresh"))
        result = self.lane_assess(
            post_merge=never, shared=self.shared(lane_gate(False)), share=mock.Mock()
        )
        self.assertEqual(result.details["postMergeShared"], "used")
        self.assertEqual(result.reason, "in-flight:unverified-auto-merge:#8040")

    def test_a_recompute_is_handed_back_bound_to_what_it_read(self) -> None:
        self.aged(3)
        self.judged_flight()
        before = policy.datetime.now(policy.UTC)
        fresh = lane_gate(True)
        shared: list[policy.SharedPostMerge] = []
        self.lane_assess(
            post_merge=lambda floor, who: fresh,
            shared=self.shared(lane_gate(False)),
            share=shared.append,
        )
        (answer,) = shared
        self.assertEqual(
            (answer.main_sha, answer.config_sha, answer.identity, answer.floor),
            (MAIN_SHA, CONFIG_SHA, IDENTITY, policy.datetime.fromisoformat(ENABLED_AT)),
        )
        self.assertIs(answer.gate, fresh)
        self.assertTrue(answer.lane_merges_only)
        self.assertGreaterEqual(answer.computed_at, before)

    def test_the_next_candidate_reuses_the_written_recompute(self) -> None:
        self.aged(3)
        self.judged_flight()
        path = pathlib.Path(self.enterContext(tempfile.TemporaryDirectory()))
        path /= "post-merge.json"
        share = lambda answer: babysit_postmerge.write_shared(str(path), answer)  # noqa: E731
        first = self.lane_assess(
            post_merge=lambda floor, who: lane_gate(True),
            shared=self.shared(lane_gate(False)),
            share=share,
        )
        reread = babysit_postmerge.read_shared(str(path))
        assert reread is not None
        gh = self.bound()
        self.computed_at = reread.computed_at
        gh.rest[self.issues_since()] = []
        self.judged_flight()
        never = mock.Mock(side_effect=AssertionError("read fresh"))
        written = mock.Mock()
        second = self.lane_assess(post_merge=never, shared=reread, share=written)
        self.assertEqual(second.details["postMergeShared"], "used")
        self.assertEqual(self.decided(second), self.decided(first))
        written.assert_not_called()

    def test_a_failed_write_back_keeps_the_verdict(self) -> None:
        self.bound()
        self.judged_flight()
        scratch = self.lane_assess(post_merge=lambda floor, who: lane_gate(True))
        self.aged(3)
        self.judged_flight()
        missing = pathlib.Path(self.enterContext(tempfile.TemporaryDirectory()))
        missing /= "gone/post-merge.json"
        refreshed = self.lane_assess(
            post_merge=lambda floor, who: lane_gate(True),
            shared=self.shared(lane_gate(False)),
            share=lambda answer: babysit_postmerge.write_shared(str(missing), answer),
        )
        self.assertFalse(missing.exists())
        self.assertEqual(self.decided(refreshed), self.decided(scratch))

    def test_a_new_merge_refusal_also_hands_back_its_recompute(self) -> None:
        lane_merge = merge_pages([[merged(7, bot("agent-lanes"), None)]])
        self.moved(lane_merge)
        self.judged_flight()
        shared: list[policy.SharedPostMerge] = []
        result = self.lane_assess(
            post_merge=lambda floor, who: lane_gate(True),
            shared=self.shared(lane_gate(True)),
            share=shared.append,
        )
        self.assertEqual(result.details["postMergeShared"], "unused:new-merge:#7")
        self.assertEqual([answer.main_sha for answer in shared], ["f" * 40])

    def test_the_binding_is_read_before_the_check(self) -> None:
        # A lane merge landing during the check moves the head after the
        # binding read, so the next candidate lists merges rather than taking
        # the unchanged-head shortcut on an answer that never judged it.
        gh = self.aged(3)
        self.judged_flight()
        called: list[Any] = []

        def check(floor: Any, who: str) -> policy.PostMergeGate:
            called.append(policy.datetime.now(policy.UTC))
            gh.rest[f"repos/{REPO}/commits/trunk"] = {"sha": "e" * 40}
            return lane_gate(True)

        shared: list[policy.SharedPostMerge] = []
        self.lane_assess(
            post_merge=check, shared=self.shared(lane_gate(False)), share=shared.append
        )
        (answer,) = shared
        self.assertEqual(answer.main_sha, MAIN_SHA)
        self.assertLessEqual(answer.computed_at, called[0])

    def test_an_answer_bound_to_another_candidate_is_not_overwritten(self) -> None:
        # Not a fresher answer, only a different one: writing it back would
        # send the candidates that match the run's answer to their own reads.
        other_floor = policy.datetime.fromisoformat("2026-10-11T00:00:00Z")
        for overrides, rest, reason in (
            (
                {"floor": other_floor},
                {NEWEST_CONFIG: [{"sha": "f" * 40}]},
                "floor-differs",
            ),
            ({"identity": "other[bot]"}, {}, "identity-differs"),
            ({"self_logins": frozenset({"x[bot]"})}, {}, "self-logins-differ"),
            ({"lane_merges_only": False}, {}, "lane-differs"),
        ):
            with self.subTest(reason=reason):
                self.bound().rest.update(rest)
                self.judged_flight()
                share = mock.Mock()
                result = self.lane_assess(
                    post_merge=lambda floor, who: lane_gate(True),
                    shared=self.shared(lane_gate(True), **overrides),
                    share=share,
                )
                self.assertEqual(result.details["postMergeShared"], f"unused:{reason}")
                share.assert_not_called()

    def test_an_unreadable_config_history_writes_nothing_back(self) -> None:
        # The binding check could not read the base's config history; the
        # reads after it can succeed, but the floor they compute may be
        # another one, which later candidates would refuse as floor-differs.
        self.bound()
        self.judged_flight()
        share = mock.Mock()
        reads = mock.Mock(side_effect=[policy.PolicyReadError("502"), CONFIG_SHA])
        with mock.patch.object(policy, "newest_config_commit", reads):
            result = self.lane_assess(
                post_merge=lambda floor, who: lane_gate(True),
                shared=self.shared(lane_gate(True)),
                share=share,
            )
        self.assertEqual(result.details["postMergeShared"], "unused:config-unreadable")
        self.assertIsNone(result.reason)
        share.assert_not_called()

    def test_another_floor_on_a_stale_answer_leaves_the_runs_answer(self) -> None:
        # The binding is checked before the age: a candidate on another floor
        # is refused as bound elsewhere and writes nothing back, so the next
        # main-floor candidate refreshes the run's answer and the one after
        # reuses it. Every verdict is a from-scratch run's.
        other_floor = policy.datetime.fromisoformat("2026-10-11T00:00:00Z")
        path = pathlib.Path(self.enterContext(tempfile.TemporaryDirectory()))
        path /= "post-merge.json"
        late = policy.datetime.now(policy.UTC) - policy.timedelta(minutes=31)
        self.bound()
        babysit_postmerge.write_shared(
            str(path), self.shared(lane_gate(True), computed_at=late)
        )
        share = lambda answer: babysit_postmerge.write_shared(str(path), answer)  # noqa: E731

        def candidate(floor: Any, expected: str) -> None:
            """One candidate, from scratch and then on the run's file."""
            with contextlib.ExitStack() as stack:
                if floor is not None:
                    stack.enter_context(
                        mock.patch.object(
                            policy, "merged_since_floor", return_value=floor
                        )
                    )
                for shared in (None, babysit_postmerge.read_shared(str(path))):
                    gh = self.bound()
                    if floor is not None:
                        gh.rest[NEWEST_CONFIG] = [{"sha": "f" * 40}]
                    if shared is not None:
                        self.computed_at = shared.computed_at
                        gh.rest[self.issues_since()] = []
                    self.judged_flight()
                    result = self.lane_assess(
                        post_merge=lambda floor, who: lane_gate(True),
                        shared=shared,
                        share=share if shared is not None else None,
                    )
                    if shared is None:
                        scratch = result
                self.assertEqual(result.details["postMergeShared"], expected)
                self.assertEqual(self.decided(result), self.decided(scratch))

        before = path.read_bytes()
        candidate(other_floor, "unused:floor-differs")
        self.assertEqual(path.read_bytes(), before)
        candidate(None, "unused:stale")
        candidate(None, "used")

    def test_the_age_is_the_recorded_computed_at_not_the_files_mtime(self) -> None:
        # Written just now, but its answer was computed 3 minutes ago with
        # #8040 unverified: read again.
        path = pathlib.Path(self.enterContext(tempfile.TemporaryDirectory()))
        path /= "post-merge.json"
        self.aged(3)
        babysit_postmerge.write_shared(str(path), self.shared(lane_gate(False)))
        reread = babysit_postmerge.read_shared(str(path))
        assert reread is not None
        self.judged_flight()
        result = self.lane_assess(
            post_merge=lambda floor, who: lane_gate(True),
            shared=reread,
            share=mock.Mock(),
        )
        self.assertEqual(result.details["postMergeShared"], "unused:unverified-stale")

    def test_an_unreadable_shared_answer_is_recomputed_and_handed_back(self) -> None:
        self.bound()
        self.judged_flight()
        shared: list[policy.SharedPostMerge] = []
        self.lane_assess(
            post_merge=lambda floor, who: lane_gate(True), share=shared.append
        )
        self.assertEqual(len(shared), 1)

    def test_an_unreadable_recompute_is_not_handed_back(self) -> None:
        self.aged(3)
        self.judged_flight()
        share = mock.Mock()
        result = self.lane_assess(
            post_merge=lambda floor, who: gate("unreadable"),
            shared=self.shared(lane_gate(False)),
            share=share,
        )
        self.assertEqual(result.reason, "post-merge:unreadable")
        share.assert_not_called()


class PlainMergeRefusesTheIdentityFromRealConfig(unittest.TestCase):
    """`babysit_merge.py --merge` with the token acting as the configured
    `merge.agent-identity`, read from a real pipeline file through the config
    reader and the shared YAML reader, exits 10 before any evaluation or write."""

    def run_main(
        self, login: str, main_identity: str | None = None
    ) -> tuple[int, dict[str, Any]]:
        import contextlib
        import io

        import babysit_merge as merge

        pipeline = PIPELINE.replace("local-babysit", "pr-merge")
        gh = config_fake(self, pipeline)
        gh.rest[f"repos/{REPO}"] = {"default_branch": "main"}
        gh.rest[f"repos/{REPO}/commits/main"] = {"sha": SHA}
        if main_identity is not None:
            # Main has moved to a head that names another identity.
            gh.rest[f"repos/{REPO}/commits/main"] = {"sha": MAIN_SHA}
            gh.rest[f"repos/{REPO}/contents?ref={MAIN_SHA}"] = []
            for path, text in (
                (policy.CONFIG_PATH, pipeline.replace(IDENTITY, main_identity)),
                (policy.SOURCE_CONTROL_PATH, SOURCE_CONTROL),
            ):
                gh.rest[f"repos/{REPO}/contents/{path}?ref={MAIN_SHA}"] = file_payload(
                    text
                )
        # The config is read at the pull request's base SHA (S4), and at main's head.
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

    def test_either_sides_identity_token_is_refused_after_a_rotation(self) -> None:
        for login, named in (("Other[bot]", "other[bot]"), (IDENTITY, IDENTITY)):
            with self.subTest(login=login):
                code, out = self.run_main(login, main_identity="other[bot]")
                self.assertEqual(code, 10)
                self.assertEqual(out["agentIdentity"], named)
                self.assertEqual(out["actingLogin"], login)


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

    def test_majors_hold_unless_set_to_review(self) -> None:
        for written, majors in (
            (None, "hold"),
            ("hold", "hold"),
            ("review", "review"),
            ("merge", "hold"),
        ):
            with self.subTest(written=written):
                text = LANE_PIPELINE + "  dependabot:\n    mode: enforce\n"
                if written is not None:
                    text += f"    majors: {written}\n"
                config_fake(self, text)
                self.assertEqual(
                    policy.read_config_at(REPO, SHA).dependabot_majors, majors
                )


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
        "?check_name=ci-status&app_id=15368&filter=latest&per_page=100"
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

    def eligibility(self, title: str = "build(deps): bump x", **options: Any) -> Any:
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
        return policy.dependabot_eligibility(
            REPO, 7, pr=pr, agent_identity=IDENTITY, **options
        )

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

    def test_a_candidate_scope_reads_the_commits_once(self) -> None:
        gh = self.fake(commits=[dependabot_commit(sha=self.HEAD)])
        with babysit_gh.candidate_reads():
            first, again = self.eligibility(), self.eligibility()
        self.assertEqual(first, again)
        self.assertTrue(first.eligible, first.reason)
        self.assertEqual(sum(self.COMMITS in call for call in gh.calls), 1)

    def test_an_unreadable_registry_waits_for_a_review(self) -> None:
        self.fake(registry={})
        self.assertEqual(
            self.eligibility().reason,
            "dependabot-review:provenance-unreadable:x;review-verdict-missing",
        )

    def test_a_review_tier_bump_spends_no_registry_read(self) -> None:
        self.fake(commits=[dependabot_commit("semver-major")], registry={})
        self.assertEqual(
            self.eligibility(hold_majors=False).reason,
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
        result = self.eligibility(hold_majors=False)
        self.assertFalse(result.eligible)
        self.assertEqual(
            result.reason, "dependabot-review:major:x;review-verdict-missing"
        )
        self.assertEqual(result.dependabot.tier, "review")

    def test_a_major_bump_is_held_for_a_human_despite_a_merge_verdict(self) -> None:
        self.fake(commits=[dependabot_commit("semver-major")], comments=[self.marker()])
        result = self.eligibility()
        self.assertFalse(result.eligible)
        self.assertEqual(result.reason, "dependabot-major-held:x")
        self.assertIsNone(result.dependabot.approved)

    SHA_PIN = dependabot_commit(
        message=(
            "build(deps): bump x\n\n---\nupdated-dependencies:\n"
            f"- dependency-name: x\n  dependency-version: {'a' * 40}\n"
            "  dependency-type: direct:production\n...\n"
        )
    )

    def test_a_sha_pin_bump_is_held_despite_a_merge_verdict(self) -> None:
        # Fail closed: an unreadable version may be a major.
        self.fake(commits=[self.SHA_PIN], comments=[self.marker()])
        result = self.eligibility()
        self.assertFalse(result.eligible)
        self.assertEqual(result.reason, "dependabot-major-held:x(unreadable)")
        self.assertEqual(result.dependabot.reasons, ("unparsed-version:x",))

    def test_sources_that_disagree_are_held_despite_a_merge_verdict(self) -> None:
        # The metadata says minor, the title says major.
        self.fake(comments=[self.marker()])
        result = self.eligibility(title="build(deps): bump x from 1.2.0 to 2.0.0")
        self.assertFalse(result.eligible)
        self.assertEqual(result.reason, "dependabot-major-held:x(disagree)")
        self.assertIn("sources-disagree", result.dependabot.reasons)

    def test_no_readable_update_is_held_despite_a_merge_verdict(self) -> None:
        # Fail closed: neither the title nor the commit names an update.
        self.fake(
            commits=[dependabot_commit(message="build(deps): update dependencies")],
            comments=[self.marker()],
        )
        result = self.eligibility(title="build(deps): update dependencies")
        self.assertFalse(result.eligible)
        self.assertEqual(result.reason, "dependabot-major-held:updates(unreadable)")
        self.assertIsNone(result.dependabot.approved)

    def test_with_majors_review_the_verdict_path_is_unchanged(self) -> None:
        for commit, why in (
            (dependabot_commit("semver-major"), "major:x"),
            (self.SHA_PIN, "unparsed-version:x"),
        ):
            with self.subTest(why=why):
                self.fake(commits=[commit])
                self.assertEqual(
                    self.eligibility(hold_majors=False).reason,
                    f"dependabot-review:{why};review-verdict-missing",
                )
                self.fake(commits=[commit], comments=[self.marker()])
                result = self.eligibility(hold_majors=False)
                self.assertTrue(result.eligible, result.reason)
                self.assertEqual(result.dependabot.approved, "55-1")

    def test_a_minor_bump_still_merges_while_majors_are_held(self) -> None:
        self.fake()
        result = self.eligibility(hold_majors=True)
        self.assertTrue(result.eligible, result.reason)
        self.assertEqual(result.dependabot.tier, "auto")
        # A non-major review-tier bump still merges on the verdict.
        self.fake(review_only=[self.entry()], comments=[self.marker()])
        result = self.eligibility(hold_majors=True)
        self.assertTrue(result.eligible, result.reason)
        self.assertEqual(result.dependabot.approved, "55-1")

    def test_a_merge_verdict_at_the_current_head_on_green_ci_is_eligible(self) -> None:
        self.fake(commits=[dependabot_commit("semver-major")], comments=[self.marker()])
        result = self.eligibility(hold_majors=False)
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
                result = self.eligibility(hold_majors=False)
                self.assertFalse(result.eligible)
                self.assertEqual(result.reason, f"dependabot-review:major:x;{why}")

    def test_an_approved_review_still_needs_a_green_ci_status(self) -> None:
        self.fake(
            commits=[dependabot_commit("semver-major")],
            comments=[self.marker()],
            ci=[{"status": "in_progress", "conclusion": None}],
        )
        self.assertEqual(
            self.eligibility(hold_majors=False).reason, "ci-status:pending"
        )

    def test_the_lanes_app_fix_commit_counts_only_after_a_review(self) -> None:
        fix = dependabot_commit(
            name="agent-lanes[bot]",
            email="1+agent-lanes[bot]@users.noreply.github.com",
            message="fix: adapt [dependabot skip]",
            login=IDENTITY,
            sha=self.HEAD,
        )
        gh = self.fake(commits=[dependabot_commit(), fix])
        self.lane_fix(gh, ["package.json"])
        self.assertEqual(
            self.eligibility(hold_majors=False).reason,
            f"commit-not-dependabot:{'e' * 12}",
        )
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
        fixed = [{"filename": "package-lock.json"}, {"filename": "package.json"}]
        gh = self.fake(
            commits=major, comments=[self.marker()], pushes=pushes, files=fixed
        )
        self.lane_fix(gh, ["package.json"])
        result = self.eligibility(hold_majors=False)
        self.assertTrue(result.eligible, result.reason)
        # A fix commit may change only npm or pip manifests outside .github/.
        for path in (".github/workflows/ci.yml", ".github/scripts/x.mjs", "src/x.js"):
            with self.subTest(path=path):
                gh = self.fake(
                    commits=major, comments=[self.marker()], pushes=pushes, files=fixed
                )
                self.lane_fix(gh, [path])
                self.assertEqual(
                    self.eligibility(hold_majors=False).reason,
                    f"dependabot-fix-content:fix-scope:{path}",
                )

    PARENT = "d" * 40
    PUSHES = [
        {
            "activity_type": "push",
            "after": "e" * 40,
            "actor": {"login": IDENTITY, "type": "Bot"},
        },
        {
            "activity_type": "branch_creation",
            "after": "d" * 40,
            "actor": {"login": "dependabot[bot]", "type": "Bot"},
        },
    ]

    @staticmethod
    def pkg(range_: str, **extra: Any) -> str:
        return json.dumps(
            {
                "name": "p",
                "scripts": {"test": "node t.js"},
                "dependencies": {"x": range_},
                **extra,
            }
        )

    @staticmethod
    def lock(version: str, resolved: str | None = None, **extra: Any) -> str:
        entry = {
            "version": version,
            "resolved": resolved or f"https://registry.npmjs.org/x/-/x-{version}.tgz",
            "integrity": "sha512-" + "A" * 86 + "==",
            **extra,
        }
        return json.dumps(
            {"lockfileVersion": 3, "packages": {"": {}, "node_modules/x": entry}}
        )

    def lane_fix(
        self,
        gh: GhFake,
        paths: list[str],
        *,
        after: dict[str, str] | None = None,
        modes: dict[str, dict[str, Any]] | None = None,
    ) -> None:
        """The lanes App's fix commit at the head on Dependabot's commit: its
        files, their tree entries (a regular file unless `modes` names it),
        and each side's text (a plain bump of x unless `after` names it)."""
        before = {
            "package.json": self.pkg("^1.0.0"),
            "package-lock.json": self.lock("1.0.0"),
            "requirements.txt": "numpy==2.5.3\n",
            "plugin.json": json.dumps({"name": "p", "version": "1.0.0"}),
            "CHANGELOG.md": "# Changelog\n",
        }
        bumped = {
            "package.json": self.pkg("^2.0.0"),
            "package-lock.json": self.lock("2.0.0"),
            "requirements.txt": "numpy==2.5.4\n",
            "plugin.json": json.dumps({"name": "p", "version": "1.0.1"}),
            "CHANGELOG.md": "# Changelog\n\n## 1.0.1\n",
        }
        gh.rest[f"repos/{REPO}/commits/{self.HEAD}"] = {
            "files": [{"filename": p, "status": "modified"} for p in paths],
            "parents": [{"sha": self.PARENT}],
        }
        for path in paths:
            name = path.rsplit("/", 1)[-1]
            for ref, side in ((self.PARENT, before), (self.HEAD, bumped)):
                text = (after or {}).get(path) if ref == self.HEAD else None
                gh.rest[f"repos/{REPO}/contents/{path}?ref={ref}"] = RawText(
                    text if text is not None else side.get(name, "")
                )

        def tree(variables: dict[str, str]) -> dict[str, Any]:
            at = variables["e"].split(":", 1)[1]
            entries = [
                {
                    "name": p.rsplit("/", 1)[-1],
                    **(modes or {}).get(p, {"type": "blob", "mode": 0o100644}),
                }
                for p in paths
                if (p.rsplit("/", 1)[0] if "/" in p else "") == at
            ]
            return {"repository": {"object": {"entries": entries}}}

        gh.graphql["FixTree"] = tree

    def lane_fix_reason(self, paths: list[str], **options: Any) -> str | None:
        fix = dependabot_commit(
            name="agent-lanes[bot]",
            email="1+agent-lanes[bot]@users.noreply.github.com",
            message="fix: adapt [dependabot skip]",
            login=IDENTITY,
            sha=self.HEAD,
        )
        gh = self.fake(
            commits=[dependabot_commit("semver-major"), fix],
            comments=[self.marker()],
            pushes=self.PUSHES,
            files=[{"filename": p} for p in paths],
        )
        self.lane_fix(gh, paths, **options)
        return self.eligibility(hold_majors=False).reason

    def bump_reason(self, after: dict[str, str] | None = None) -> str | None:
        """The repository's version-bump commit at the head, pushed by
        github-actions[bot], on Dependabot's minor bump."""
        bump = dependabot_commit(
            name="github-actions[bot]",
            email="41898282+github-actions[bot]@users.noreply.github.com",
            message="chore: bump plugin versions [dependabot skip]",
            sha=self.HEAD,
        )
        pushes = [
            {
                "activity_type": "push",
                "after": self.HEAD,
                "actor": {"login": "github-actions[bot]", "type": "Bot"},
            },
            self.PUSHES[1],
        ]
        paths = ["plugins/p/.claude-plugin/plugin.json", "plugins/p/CHANGELOG.md"]
        gh = self.fake(
            commits=[dependabot_commit(), bump],
            pushes=pushes,
            files=[
                {"filename": "package-lock.json"},
                *({"filename": p} for p in paths),
            ],
        )
        self.lane_fix(gh, paths, after=after)
        return self.eligibility(hold_majors=False).reason

    def test_the_version_bump_commit_may_change_only_the_plugin_version(
        self,
    ) -> None:
        self.assertIsNone(self.bump_reason())
        hooks = {"name": "p", "version": "1.0.1", "hooks": {"PreToolUse": []}}
        path = "plugins/p/.claude-plugin/plugin.json"
        self.assertEqual(
            self.bump_reason({path: json.dumps(hooks)}),
            f"dependabot-bump-content:bump-content:{path}:plugin-json-key",
        )

    def test_a_lanes_app_fix_must_be_a_version_change_of_regular_manifest_files(
        self,
    ) -> None:
        self.assertIsNone(self.lane_fix_reason(["package.json", "package-lock.json"]))
        for mode in (0o120000, 0o160000, 0o100755):
            with self.subTest(mode=oct(mode)):
                kind = "commit" if mode == 0o160000 else "blob"
                self.assertEqual(
                    self.lane_fix_reason(
                        ["package.json"],
                        modes={"package.json": {"type": kind, "mode": mode}},
                    ),
                    "dependabot-fix-content:fix-mode:package.json",
                )
        steal = {"test": "node t.js", "postinstall": "node steal.js"}
        self.assertEqual(
            self.lane_fix_reason(
                ["package.json"],
                after={"package.json": self.pkg("^2.0.0", scripts=steal)},
            ),
            "dependabot-fix-content:fix-content:package.json:package-json-key:scripts",
        )
        self.assertEqual(
            self.lane_fix_reason(
                ["package-lock.json"],
                after={
                    "package-lock.json": self.lock(
                        "2.0.0", "https://evil.example/x.tgz"
                    )
                },
            ),
            "dependabot-fix-content:fix-content:package-lock.json:"
            "lock-resolved:node_modules/x",
        )
        evil = "https://registry.npmjs.org/evilpkg/-/evilpkg-6.6.6.tgz"
        self.assertEqual(
            self.lane_fix_reason(
                ["package-lock.json"],
                after={"package-lock.json": self.lock("2.0.0", evil)},
            ),
            "dependabot-fix-content:fix-content:package-lock.json:"
            "lock-resolved:node_modules/x",
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

    def test_the_ci_status_run_that_started_last_decides(self) -> None:
        # `filter=latest` keeps the latest run of each check suite, so a
        # re-triggered workflow leaves an older red run beside a newer one.
        red = {"status": "completed", "conclusion": "failure"}
        green = {"status": "completed", "conclusion": "success"}
        running = {"status": "in_progress", "conclusion": None}
        cases = [
            ("green after red", [red, green], "success"),
            ("red after green", [green, red], "failure"),
            ("running after green", [green, running], "pending"),
        ]
        for label, (older, newer), expected in cases:
            pair = [
                {**newer, "started_at": "2026-10-24T05:40:00Z"},
                {**older, "started_at": "2026-10-23T21:56:00Z"},
            ]
            for listed in (pair, pair[::-1]):
                with self.subTest(label, newer_listed_first=listed is pair):
                    self.fake(ci=listed)
                    self.assertEqual(
                        policy._ci_status(*REPO.split("/"), self.HEAD), expected
                    )

    def test_ci_status_runs_that_started_together_keep_any_failure(self) -> None:
        at = "2026-10-24T05:40:00Z"
        red = {"status": "completed", "conclusion": "failure", "started_at": at}
        green = {"status": "completed", "conclusion": "success", "started_at": at}
        for listed in ([red, green], [green, red]):
            with self.subTest(listed=listed):
                self.fake(ci=listed)
                self.assertEqual(
                    policy._ci_status(*REPO.split("/"), self.HEAD), "failure"
                )

    def test_ci_status_runs_without_start_times_keep_any_failure(self) -> None:
        green = {"status": "completed", "conclusion": "success"}
        red = {"status": "completed", "conclusion": "failure"}
        queued = {"status": "queued", "conclusion": None, "started_at": None}
        cases = [
            (
                "neither has a start time",
                [green, {**red, "started_at": None}],
                "failure",
            ),
            (
                "newer green beside an unstarted red",
                [
                    {**green, "started_at": "2026-10-24T05:40:00Z"},
                    {**red, "started_at": None},
                ],
                "failure",
            ),
            (
                "unstarted re-run beside an older red",
                [{**red, "started_at": "2026-10-23T21:56:00Z"}, queued],
                "pending",
            ),
            (
                "unreadable start time",
                [
                    {**green, "started_at": "2026-10-24T05:40:00Z"},
                    {**red, "started_at": "soon"},
                ],
                "failure",
            ),
        ]
        for label, runs, expected in cases:
            with self.subTest(label):
                self.fake(ci=runs)
                self.assertEqual(
                    policy._ci_status(*REPO.split("/"), self.HEAD), expected
                )

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

    def test_the_majors_setting_reaches_the_eligibility_read(self) -> None:
        for written, hold in ((None, True), ("hold", True), ("review", False)):
            with self.subTest(written=written):
                pipeline = LANE_PIPELINE + "  dependabot:\n    mode: enforce\n"
                if written is not None:
                    pipeline += f"    majors: {written}\n"
                result = self.assess_mode(None, pipeline=pipeline)
                self.assertIsNone(result.reason)
                self.assertIs(self.read.call_args.kwargs["hold_majors"], hold)
                self.assertEqual(
                    result.report()["dependabot"]["majors"],
                    "hold" if hold else "review",
                )

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


class OneRunSharesItsCredentialReads(unittest.TestCase):
    """pr-merge.yml runs one gate process per candidate and names a file in
    `BABYSIT_RUN_CACHE`: the acting login, a credential pass and permissions
    are read once for the run, never across other credentials, and a refusal
    or failed read is never shared."""

    fake = Assess.fake
    readable = Assess.readable
    all_clear = Assess.all_clear

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        env = {"BABYSIT_RUN_CACHE": str(pathlib.Path(tmp.name, "run.json"))}
        patcher = mock.patch.dict("os.environ", {**env, "GH_TOKEN": "lane"})
        patcher.start()
        self.addCleanup(patcher.stop)

    def gh(self) -> GhFake:
        gh = self.readable()
        gh.graphql["PolicyViewer"] = {"viewer": {"login": IDENTITY}}
        self.all_clear()
        return gh

    def candidate(self) -> policy.UnattendedPolicy:
        """One candidate's gate process, with nothing passed in."""
        return policy.assess(
            REPO, 1, post_merge=lambda floor, who: gate(), promotion=lambda s: PROMOTED
        )

    def reads(self, gh: GhFake) -> tuple[int, int]:
        viewer = sum("query PolicyViewer" in " ".join(c) for c in gh.calls)
        return viewer, gh.calls.count(["auth", "status", "--json", "hosts"])

    def test_candidates_of_one_run_read_them_once(self) -> None:
        gh = self.gh()
        for _ in range(3):
            self.assertIsNone(self.candidate().reason)
        self.assertEqual(self.reads(gh), (1, 1))

    def test_other_credentials_read_them_again(self) -> None:
        gh = self.gh()
        self.candidate()
        with mock.patch.dict("os.environ", {"GH_TOKEN": "another"}):
            self.candidate()
        self.assertEqual(self.reads(gh), (2, 2))

    def test_a_credential_refusal_is_read_again(self) -> None:
        gh = self.gh()
        gh.rest["status"] = {
            "hosts": {
                "github.com": [
                    *IDENTITY_ONLY["hosts"]["github.com"],
                    {"login": OPERATOR, "active": False, "host": "github.com"},
                ]
            }
        }
        for _ in range(2):
            self.assertEqual(
                self.candidate().reason, "credentials:other-account-listed"
            )
        self.assertEqual(self.reads(gh)[1], 2)

    def test_the_default_branch_is_read_once_per_run(self) -> None:
        gh = self.gh()
        for _ in range(3):
            self.candidate()
        self.assertEqual(gh.calls.count(["api", f"repos/{REPO}"]), 1)

    def test_the_pre_enqueue_base_check_reads_the_default_branch_fresh(self) -> None:
        gh = self.gh()
        self.candidate()
        policy._base_refusal("owner", "repo", {"baseRefName": "trunk"})
        self.assertEqual(gh.calls.count(["api", f"repos/{REPO}"]), 2)

    def test_a_failed_default_branch_read_is_not_shared(self) -> None:
        gh = GhFake().install(self)
        gh.rest[f"repos/{REPO}"] = 502
        for _ in range(2):
            with self.assertRaises(policy.PolicyReadError):
                policy._default_branch(REPO, shared=True)
        self.assertEqual(gh.calls.count(["api", f"repos/{REPO}"]), 2)

    def permission_reads(self, answer: Any, readers: int = 2) -> int:
        gh = GhFake().install(self)
        endpoint = f"repos/{REPO}/collaborators/{OPERATOR}/permission"
        gh.rest[endpoint] = answer
        for _ in range(readers):
            policy.permission_reader(REPO)(OPERATOR)
        return gh.calls.count(["api", endpoint])

    def test_a_permission_is_read_once_per_run(self) -> None:
        self.assertEqual(self.permission_reads({"permission": "admin"}, 3), 1)

    def test_a_failed_permission_read_is_not_shared(self) -> None:
        self.assertEqual(self.permission_reads(404), 2)

    def test_a_permission_past_the_bound_is_read_again(self) -> None:
        clock = [datetime(2026, 10, 18, 12, 0, tzinfo=UTC)]
        with mock.patch.object(policy.run_cache, "now", side_effect=lambda: clock[0]):
            gh = GhFake().install(self)
            endpoint = f"repos/{REPO}/collaborators/{OPERATOR}/permission"
            gh.rest[endpoint] = {"permission": "admin"}
            policy.permission_reader(REPO)(OPERATOR)
            clock[0] += policy.run_cache.MAX_AGE + timedelta(seconds=1)
            policy.permission_reader(REPO)(OPERATOR)
        self.assertEqual(gh.calls.count(["api", endpoint]), 2)


# The tracker's human-gated label read an autonomous gate makes: stubbed so
# no test reads GitHub.
_role_label = mock.patch.object(
    babysit_postmerge, "_role_label", return_value="needs-human"
)


_read_concern_values = policy._concern_values
_real_run_command = policy.run_command
_READER = policy.PARSER
_concern_answers: dict[Any, dict[str, list[str]] | None] = {}


def _cached_concern_values(
    text: str, keys: list[tuple[str, bool]]
) -> dict[str, list[str]] | None:
    """The shared YAML reader's answer, read once per document, key list and
    environment: the reader is a pure function of them, and spawning it for
    every config read dominated this module's run time. A test that swaps
    the command runner or the reader script reads through."""
    if policy.run_command is not _real_run_command or policy.PARSER != _READER:
        return _read_concern_values(text, keys)
    key = (text, tuple(keys), tuple(sorted(os.environ.items())))
    if key not in _concern_answers:
        _concern_answers[key] = _read_concern_values(text, keys)
    found = _concern_answers[key]
    return None if found is None else {k: list(v) for k, v in found.items()}


_concern_cache = mock.patch.object(policy, "_concern_values", _cached_concern_values)


def setUpModule() -> None:
    _role_label.start()
    _concern_cache.start()


def tearDownModule() -> None:
    _concern_cache.stop()
    _role_label.stop()


class FileContents(unittest.TestCase):
    """The manifest review and the cost hold read each changed manifest or
    workflow once per side, at the pull request's base and head SHAs."""

    PR = {"base": {"sha": "b" * 40}, "head": {"sha": "c" * 40}}

    def setUp(self) -> None:
        policy._TEXT_AT.clear()
        self.addCleanup(policy._TEXT_AT.clear)

    def changed(self, path: str, **kw: Any) -> policy.ChangedFile:
        fields = {
            "previous_path": None, "status": "modified", "additions": 1,
            "deletions": 0, "has_patch": True, "mode": "100644", **kw,
        }  # fmt: skip
        return policy.ChangedFile(path=path, **fields)

    def read(self, files, texts):
        calls = []

        def file_at(owner, name, path, sha):
            calls.append((path, sha))
            found = texts[(path, sha)]
            if isinstance(found, Exception):
                raise found
            return found

        with mock.patch.object(policy, "_file_at", side_effect=file_at):
            out = policy.with_contents("o/r", self.PR, tuple(files))
        return out, calls

    def test_each_side_is_read_once_and_cached(self) -> None:
        skill = self.changed("plugins/p/.claude-plugin/plugin.json")
        texts = {
            ("plugins/p/.claude-plugin/plugin.json", "b" * 40): "old",
            ("plugins/p/.claude-plugin/plugin.json", "c" * 40): "new",
        }
        out, calls = self.read([skill, skill, self.changed("docs/x.md")], texts)
        self.assertEqual([f.contents for f in out[:2]], [("old", "new")] * 2)
        self.assertIsNone(out[2].contents)
        self.assertEqual(len(calls), 2)

    def test_the_trusted_actor_list_is_read_on_both_sides(self) -> None:
        # The trust-gate hold compares its base and head entries.
        path = ".github/standards/trusted-actors/trusted-actors.json"
        texts = {(path, "b" * 40): "old", (path, "c" * 40): "new"}
        out, _ = self.read([self.changed(path)], texts)
        self.assertEqual(out[0].contents, ("old", "new"))

    def test_a_rename_reads_the_base_at_its_previous_path(self) -> None:
        moved = self.changed(
            ".github/workflows/a.yml",
            status="renamed",
            previous_path=".github/workflows/b.yml",
        )
        texts = {
            (".github/workflows/b.yml", "b" * 40): "old",
            (".github/workflows/a.yml", "c" * 40): "new",
        }
        out, _ = self.read([moved], texts)
        self.assertEqual(out[0].contents, ("old", "new"))

    def test_an_added_file_reads_only_its_head(self) -> None:
        added = self.changed(".github/workflows/go.yml", status="added")
        out, calls = self.read([added], {(".github/workflows/go.yml", "c" * 40): "new"})
        self.assertEqual((out[0].contents, len(calls)), ((None, "new"), 1))

    def test_a_path_is_quoted_so_it_cannot_pick_another_ref(self) -> None:
        odd = self.changed(".github/workflows/x?ref=main#.yml")
        quoted = ".github/workflows/x%3Fref%3Dmain%23.yml"
        out, calls = self.read(
            [odd], {(quoted, "b" * 40): "a", (quoted, "c" * 40): "a"}
        )
        self.assertEqual({path for path, _ in calls}, {quoted})

    def test_any_exception_is_carried_with_its_type(self) -> None:
        skill = self.changed("plugins/p/.claude-plugin/plugin.json")
        texts = {
            ("plugins/p/.claude-plugin/plugin.json", "b" * 40): TypeError("bad payload")
        }
        out, _ = self.read([skill], texts)
        self.assertIsNone(out[0].contents)
        self.assertIn("TypeError", out[0].contents_error)

    def test_the_logged_path_cannot_start_a_workflow_command(self) -> None:
        # Review thread L2597: a newline in a changed path must stay escaped.
        path = ".github/workflows/a\n::set-output name=dispatch::true\nb.yml"
        texts = {(path, "b" * 40): TypeError("bad\n::error::x")}
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.read([self.changed(path)], texts)
        self.assertTrue(err.getvalue())
        self.assertFalse(
            [line for line in err.getvalue().splitlines() if line.startswith("::")]
        )

    def test_a_read_error_is_carried_for_the_scorer(self) -> None:
        skill = self.changed("plugins/p/.claude-plugin/plugin.json")
        texts = {
            ("plugins/p/.claude-plugin/plugin.json", "b" * 40): policy.PolicyReadError(
                "status 502"
            )
        }
        out, _ = self.read([skill], texts)
        self.assertIsNone(out[0].contents)
        self.assertIn("502", out[0].contents_error)


if __name__ == "__main__":
    unittest.main()

# test-scope: .github/actions/resolve-config/issue-status.mjs .github/actions/resolve-config/dimensions.mjs docs/conventions/pr-pipeline.yaml plugins/source-control/lib/yaml-subset.awk
"""The Work status field (`models.issue-status`) as a hold source for the
pr-merge lane, the capped-close park and the post-merge demotion record.

Expected states come from the rule `docs/conventions/pr-pipeline.yaml` states
above `models.issue-status`: a listed human or the lanes App counts for every
state; a `bot-setters` account for every state but agent-ready,
github-actions[bot] always and a `melodic-` bot only while trusted-actors.json
lists it as a bot with the same id and login; anything else reads as none, and
a counted value no option maps fails the read. The hold states are
read-status.mjs HOLD_STATES. GraphQL answers follow the shapes
resolve-config.mjs FIELD_EVENTS and the work-items get-statuses.sh adapter
read; the field write follows write-status.mjs writeState."""

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
import unittest
from typing import Any
from unittest import mock

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
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import babysit_merge_policy as policy  # noqa: E402
import babysit_postmerge as pm  # noqa: E402
import babysit_verify_evidence as ve  # noqa: E402
import test_babysit_merge_unattended as unttd  # noqa: E402
from test_babysit_capped_close import HEAD as CAPPED_HEAD  # noqa: E402
from test_babysit_capped_close import ISSUE as CAPPED_ISSUE  # noqa: E402
from test_babysit_capped_close import PR as CAPPED_PR  # noqa: E402
from test_babysit_capped_close import REPO as CAPPED_REPO  # noqa: E402
from test_babysit_capped_close import StubReader, World, comment  # noqa: E402
from test_babysit_merge_policy import (  # noqa: E402
    HUMANS,
    IDENTITY,
    ISSUE_HOLDS,
    LANE_DENIED,
    PR_CREATED,
    REPO,
    SHA,
    GhFake,
    bot,
    config_fake,
)
from test_babysit_postmerge import (  # noqa: E402
    OTHER_SHA,
    CheckCase,
    FakeGh,
    completed,
    identity_merge,
)
from test_babysit_postmerge import REPO as PM_REPO  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[6]
LIVE = (ROOT / "docs/conventions/pr-pipeline.yaml").read_text(encoding="utf-8")
FIELD = 48484079
MAIN = "c" * 40
TRUSTED = f"repos/{REPO}/contents/{policy.TRUSTED_ACTORS_PATH}?ref={MAIN}"

# The trusted-actor list the cases read: a person, the lanes App, a melodic-
# bot the config lists with the same id, and one listed under another id.
HUMAN_ID = 1001
LANES_ID = 2002
ACTORS = [
    {"id": HUMAN_ID, "login": "kyle-sexton", "kind": "human"},
    {"id": LANES_ID, "login": "melodic-automation-lanes[bot]", "kind": "bot"},
    {"id": 288071998, "login": "melodic-ai[bot]", "kind": "bot"},
    {"id": 999, "login": "melodic-release[bot]", "kind": "bot"},
]

SMALL = """\
models:
  issue-status:
    field-id: 48484079
    bot-setters:
      - id: 41898282
        login: "github-actions[bot]"
    options:
      "84879216": needs-triage
      "84879219": needs-spec
      "86380002": confirmed
      "86380003": ready
      "86380005": needs-human
    labels:
      needs-triage:
        - needs-triage
      needs-spec:
        - needs-spec
      confirmed:
        - "status: confirmed"
      ready:
        - "status: ready"
      needs-human:
        - needs-human
    order:
      - needs-human
      - needs-spec
      - ready
      - confirmed
      - needs-triage
"""


def live_config() -> policy.IssueStatusConfig:
    status = policy._issue_status_config(LIVE)
    assert status is not None and status.error is None, status
    return status


def setter(actor_id: int, login: str, kind: str = "Bot") -> dict[str, Any]:
    """A GraphQL actor: a bot's login comes without `[bot]`."""
    return {"__typename": kind, "login": login, "databaseId": actor_id}


WORK_STATUS = {"fullDatabaseId": str(FIELD)}
# A Work status POST's answer with the field at confirmed (pr-pipeline.yaml).
CONFIRMED_ROWS = [{"issue_field_id": FIELD, "single_select_option": {"id": 86380002}}]
AGENT_READY_ROWS = [{"issue_field_id": FIELD, "single_select_option": {"id": 84879220}}]


def field_event(
    who: dict[str, Any], to: str | None, changed: bool = False
) -> dict[str, Any]:
    """A Work status event as the GraphQL timeline names it: an add's
    `value`, a change's `newValue`, or a removal."""
    if to is None:
        return {
            "__typename": "IssueFieldRemovedEvent",
            "actor": who,
            "issueField": WORK_STATUS,
        }
    kind, key = (
        ("IssueFieldChangedEvent", "newValue")
        if changed
        else ("IssueFieldAddedEvent", "value")
    )
    return {"__typename": kind, key: to, "actor": who, "issueField": WORK_STATUS}


def answer(
    value: str | None,
    who: dict[str, Any] | None,
    *,
    removed: bool = False,
    padding: int = 0,
    later: tuple[dict[str, Any], ...] = (),
    now: Any = "same",
) -> dict[str, Any]:
    """The PolicyIssueStatus answer: `who` setting the field to `value` (or
    removing it) after `padding` events of another field, then the `later`
    Work status events; the field holds `now` (`value` unless given)."""
    other = {"fullDatabaseId": "1"}
    events = [
        {"__typename": "IssueFieldAddedEvent", "actor": who, "issueField": other}
    ] * padding
    if who is not None:
        events.append(field_event(who, None if removed else value))
    events += later
    held = value if now == "same" else now
    values = [] if held is None else [{"name": held, "field": WORK_STATUS}]
    return {
        "repository": {
            "issue": {
                "issueFieldValues": {"nodes": values},
                "timelineItems": {"nodes": events},
            }
        }
    }


# One fixture, neutral between the two readers: who set the field, to what,
# and the state the rule above gives.
PARITY = [
    {
        "setter": [HUMAN_ID, "kyle-sexton", "User"],
        "value": "needs-spec",
        "want": "needs-spec",
    },
    {"setter": [3003, "drive-by", "User"], "value": "needs-spec", "want": None},
    {
        "setter": [41898282, "github-actions", "Bot"],
        "value": "needs-human",
        "want": "needs-human",
    },
    {
        "setter": [41898282, "github-actions", "Bot"],
        "value": "agent-ready",
        "want": None,
    },
    {
        "setter": [288071998, "melodic-ai", "Bot"],
        "value": "needs-owner-decision",
        "want": "needs-owner-decision",
    },
    {"setter": [288071998, "melodic-ai", "Bot"], "value": "agent-ready", "want": None},
    {
        "setter": [LANES_ID, "melodic-automation-lanes", "Bot"],
        "value": "agent-ready",
        "want": "agent-ready",
    },
    {
        "setter": [337859524, "melodic-release", "Bot"],
        "value": "needs-human",
        "want": None,
    },
    {
        "setter": [300666570, "melodic-standards-sync", "Bot"],
        "value": "needs-human",
        "want": None,
    },
    {"setter": [4004, "claude", "Bot"], "value": "needs-human", "want": None},
    {
        "setter": [HUMAN_ID, "kyle-sexton", "User"],
        "value": None,
        "removed": True,
        "want": None,
    },
]


class StatusCase(unittest.TestCase):
    def setUp(self) -> None:
        policy._ISSUE_STATUS.clear()
        self.gh = GhFake().install(self)
        self.gh.rest[TRUSTED] = {
            "type": "file",
            "encoding": "base64",
            "content": base64.b64encode(
                json.dumps({"version": 1, "actors": ACTORS}).encode()
            ).decode(),
        }

    def read(
        self, graphql: Any, config: policy.IssueStatusConfig | None = None
    ) -> str | None:
        self.gh.graphql["PolicyIssueStatus"] = graphql
        return policy.issue_status(REPO, MAIN, 41, config or live_config())


class TheFieldReader(StatusCase):
    def test_each_parity_case_gives_the_rules_state(self) -> None:
        for case in PARITY:
            with self.subTest(case=case):
                who = setter(*case["setter"]) if case["setter"] else None
                got = self.read(
                    answer(case["value"], who, removed=case.get("removed", False))
                )
                self.assertEqual(got, case["want"])

    def test_the_javascript_reader_agrees_on_the_fixture(self) -> None:
        node = shutil.which("node")
        if node is None:
            self.skipTest("node is not installed")
        config = live_config()
        by_state = {state: int(option) for option, state in config.options}
        cases = [
            {
                "fieldValues": []
                if c["value"] is None
                else [{"field": FIELD, "option": by_state[c["value"]]}],
                "fieldSetters": {
                    str(FIELD): None if c.get("removed") else c["setter"][0]
                },
            }
            for c in PARITY
        ]
        payload = {
            "module": (
                ROOT / ".github/actions/resolve-config/issue-status.mjs"
            ).as_uri(),
            "config": {
                "field-id": config.field_id,
                "bot-setters": [
                    {"id": i, "login": login} for i, login in config.bot_setters
                ],
                "options": dict(config.options),
            },
            "trusted": {"actors": ACTORS},
            "cases": cases,
        }
        script = (
            'import { readFileSync } from "node:fs";'
            "const p = JSON.parse(readFileSync(0, 'utf8'));"
            "const { issueStatus } = await import(p.module);"
            "console.log(JSON.stringify(p.cases.map((f) => issueStatus(f, p.config, p.trusted))));"
        )
        proc = subprocess.run(
            [node, "--input-type=module", "-e", script],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        if "ERR_MODULE_NOT_FOUND" in proc.stderr:
            self.skipTest("resolve-config's npm dependencies are not installed")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout), [c["want"] for c in PARITY])

    def test_each_unreadable_answer_raises(self) -> None:
        human = setter(HUMAN_ID, "kyle-sexton", "User")
        for name, graphql in (
            ("graphql error", 502),
            ("no issue", {"repository": {"issue": None}}),
            (
                "no event list",
                {"repository": {"issue": {"issueFieldValues": {"nodes": []}}}},
            ),
            ("counted unmapped name", answer("bogus", human)),
            ("full window, no setter", answer("needs-human", None, padding=100)),
        ):
            with self.subTest(name):
                with self.assertRaises(policy.PolicyReadError):
                    self.read(graphql)

    def test_a_full_page_of_field_values_raises(self) -> None:
        human = setter(HUMAN_ID, "kyle-sexton", "User")
        full = answer("needs-human", human)
        nodes = full["repository"]["issue"]["issueFieldValues"]["nodes"]
        other = {"name": "x", "field": {"fullDatabaseId": "1"}}
        nodes[:0] = [other] * (policy.FIELD_VALUE_PAGE - 1)
        with self.assertRaises(policy.PolicyReadError):
            self.read(full)
        del nodes[0]
        self.assertEqual(self.read(full), "needs-human")

    def test_an_uncounted_later_event_leaves_a_counted_hold(self) -> None:
        human = setter(HUMAN_ID, "kyle-sexton", "User")
        claude = setter(4004, "claude")
        drive_by = setter(3003, "drive-by", "User")
        changed = answer(
            "needs-human",
            human,
            later=(field_event(claude, "ready", changed=True),),
            now="ready",
        )
        self.assertEqual(self.read(changed), "needs-human")
        removed = answer(
            "needs-human", human, later=(field_event(drive_by, None),), now=None
        )
        self.assertEqual(self.read(removed), "needs-human")
        only_uncounted = answer(
            "needs-human",
            claude,
            later=(field_event(drive_by, "ready", changed=True),),
            now="ready",
        )
        self.assertIsNone(self.read(only_uncounted))

    def test_a_counted_later_event_decides(self) -> None:
        human = setter(HUMAN_ID, "kyle-sexton", "User")
        actions = setter(41898282, "github-actions")
        cleared = answer(
            "needs-human", human, later=(field_event(human, None),), now=None
        )
        self.assertIsNone(self.read(cleared))
        moved = answer(
            "needs-spec",
            human,
            later=(field_event(actions, "needs-human", changed=True),),
            now="needs-human",
        )
        self.assertEqual(self.read(moved), "needs-human")

    def test_a_full_window_of_uncounted_events_with_a_value_raises(self) -> None:
        claude = setter(4004, "claude")
        flood = tuple(field_event(claude, "ready", changed=True) for _ in range(99))
        with self.assertRaises(policy.PolicyReadError):
            self.read(answer("ready", claude, later=flood))

    def test_a_short_window_with_no_setter_reads_as_unset(self) -> None:
        self.assertIsNone(self.read(answer("needs-human", None, padding=99)))

    def test_an_uncounted_unmapped_name_is_no_failure(self) -> None:
        self.assertIsNone(self.read(answer("bogus", setter(3003, "drive-by", "User"))))

    def test_an_unreadable_trusted_list_raises(self) -> None:
        human = setter(HUMAN_ID, "kyle-sexton", "User")
        for listing in (502, {"type": "file", "encoding": "base64", "content": "e30="}):
            with self.subTest(listing=listing):
                self.gh.rest[TRUSTED] = listing
                with self.assertRaises(policy.PolicyReadError):
                    self.read(answer("needs-human", human))


class TheConfigBlock(unittest.TestCase):
    def setUp(self) -> None:
        policy._ISSUE_STATUS.clear()

    def test_the_live_block_style_setters_parse(self) -> None:
        status = live_config()
        self.assertEqual(status.field_id, FIELD)
        self.assertIn((41898282, "github-actions[bot]"), status.bot_setters)
        self.assertIn((337859524, "melodic-release[bot]"), status.bot_setters)
        self.assertEqual(len(status.bot_setters), 8)
        self.assertIn(("86380005", "needs-human"), status.options)
        self.assertEqual(
            dict(status.labels)["needs-owner-decision"],
            ("needs-owner-decision",),
        )
        self.assertEqual(status.order[-1], "needs-triage")

    def test_a_malformed_block_is_an_error_that_refuses(self) -> None:
        for name, text in (
            (
                "setter without login",
                SMALL.replace('        login: "github-actions[bot]"\n', ""),
            ),
            ("order missing a state", SMALL.replace("      - ready\n", "")),
            (
                "a state with no label",
                SMALL.replace('      ready:\n        - "status: ready"\n', ""),
            ),
            ("no field id", SMALL.replace("    field-id: 48484079\n", "")),
            ("a scalar block", "models:\n  issue-status: on\n"),
        ):
            with self.subTest(name):
                policy._ISSUE_STATUS.clear()
                status = policy._issue_status_config(text)
                self.assertIsNotNone(status)
                assert status is not None
                self.assertTrue(status.error)
                with self.assertRaises(policy.PolicyReadError):
                    policy.issue_status(REPO, MAIN, 41, status)
                issue = issue_node(labels=[])
                self.assertEqual(
                    policy.issue_hold_refusal(
                        issue,
                        ISSUE_HOLDS,
                        lambda n: policy.issue_status(REPO, MAIN, n, status),
                    ),
                    "closing-issue-status-unreadable",
                )

    def test_a_document_without_the_block_has_none(self) -> None:
        self.assertIsNone(policy._issue_status_config("merge:\n  rung: C2\n"))

    def test_the_config_read_carries_it_and_a_note_when_malformed(self) -> None:
        config_fake(self, "merge:\n  rung: C2\n" + SMALL)
        config = policy.read_config_at(REPO, SHA)
        self.assertIsNotNone(config.issue_status)
        assert config.issue_status is not None
        self.assertEqual(config.issue_status.field_id, FIELD)
        self.assertEqual(config.notes, ())
        policy._ISSUE_STATUS.clear()
        config_fake(self, "merge:\n  rung: C2\n" + SMALL.replace("      - ready\n", ""))
        config = policy.read_config_at(REPO, SHA)
        self.assertTrue(any("models.issue-status" in n for n in config.notes))

    def test_the_stricter_config_takes_mains_block_else_the_bases(self) -> None:
        small = policy._issue_status_rows(
            {"field-id": "7", "options.1": "a", "labels.a.0": "x", "order.0": "a"}
        )
        base = policy.PipelineConfig(SHA, "C2", "pr-merge", IDENTITY, None, (), None)
        main = dataclasses.replace(base, base_sha=MAIN, issue_status=live_config())
        self.assertEqual(policy.stricter_config(base, main).issue_status, live_config())
        based = dataclasses.replace(base, issue_status=small)
        self.assertEqual(
            policy.stricter_config(
                based, dataclasses.replace(based, base_sha=MAIN, issue_status=None)
            ).issue_status,
            small,
        )

    def test_the_block_names_its_hold_and_ready_states_else_the_defaults(self) -> None:
        self.assertEqual(
            (live_config().hold_states, live_config().ready_state),
            (policy.HOLD_STATES, policy.READY_STATE),
        )
        rows = {
            "field-id": "7",
            "options.1": "a",
            "options.2": "b",
            "options.3": "c",
            "labels.a.0": "x",
            "labels.b.0": "y",
            "labels.c.0": "z",
            "order.0": "a",
            "order.1": "b",
            "order.2": "c",
            "hold-states.0": "a",
            "ready-state": "b",
        }
        status = policy._issue_status_rows(rows)
        self.assertIsNone(status.error)
        self.assertEqual((status.hold_states, status.ready_state), (("a",), "b"))
        self.assertEqual(
            policy.status_label_names("c", ["x", "y", "w"], status), ["x", "y", "w", "z"]
        )
        issue = issue_node(labels=[])
        reader = policy.IssueStatusReader(REPO, status)
        for state, want in (("a", "closing-issue-held:a"), ("needs-human", None)):
            with (
                self.subTest(state),
                mock.patch.object(
                    policy,
                    "_default_branch_config",
                    return_value=mock.Mock(base_sha=MAIN),
                ),
                mock.patch.object(policy, "issue_status", return_value=state),
            ):
                self.assertEqual(
                    policy.issue_hold_refusal(issue, ISSUE_HOLDS, reader), want
                )
        for bad in (
            {"hold-states": "a"},
            {"ready-state.0": "b"},
            {"hold-states.1": "unmapped"},
            {"ready-state": "unmapped"},
        ):
            with self.subTest(bad):
                self.assertTrue(policy._issue_status_rows({**rows, **bad}).error)

    def test_a_saved_config_round_trips_the_block_and_rejects_a_bad_one(self) -> None:
        config = policy.PipelineConfig(
            SHA, "C2", "pr-merge", IDENTITY, None, (), None, issue_status=live_config()
        )
        saved = json.loads(json.dumps(dataclasses.asdict(config)))
        self.assertEqual(policy._cached_config(saved), config)
        saved["issue_status"]["bot_setters"][0][0] = "41898282"
        self.assertIsNone(policy._cached_config(saved))
        none = json.loads(
            json.dumps(
                dataclasses.asdict(dataclasses.replace(config, issue_status=None))
            )
        )
        self.assertIsNone(policy._cached_config(none).issue_status)  # type: ignore[union-attr]


def issue_node(number: int = 41, labels: list[str] | None = None) -> dict[str, Any]:
    names = labels or []
    return {
        "number": number,
        "lastEditedAt": None,
        "repository": {"nameWithOwner": REPO},
        "labels": {"totalCount": len(names), "nodes": [{"name": n} for n in names]},
    }


class TheLaneGate(StatusCase):
    """`lane_eligibility` and `recheck_lane_issue` with the field read."""

    def setUp(self) -> None:
        super().setUp()
        main = policy.PipelineConfig(MAIN, "C2", "pr-merge", IDENTITY, None, (), None)
        patcher = mock.patch.object(policy, "_default_branch_config", return_value=main)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.gh.rest[f"repos/{REPO}"] = {"default_branch": "main"}
        self.gh.rest[f"repos/{REPO}/issues/41/timeline?per_page=100"] = []
        self.gh.rest[f"repos/{REPO}/pulls/7/files?per_page=100"] = [
            {"filename": "docs/a.md"}
        ]
        self.labels(["agent-ready"])

    def labels(self, names: list[str]) -> None:
        self.gh.graphql["PolicyEligibility"] = {
            "repository": {
                "pullRequest": {
                    "number": 7,
                    "body": None,
                    "baseRefName": "main",
                    "createdAt": PR_CREATED,
                    "lastEditedAt": "2026-10-12T13:00:00Z",
                    "isCrossRepository": False,
                    "author": bot("agent-lanes"),
                    "headRepositoryOwner": {"login": "owner"},
                    "labels": {"totalCount": 0, "nodes": []},
                    "closingIssuesReferences": {
                        "totalCount": 1,
                        "nodes": [issue_node(labels=names)],
                    },
                }
            }
        }

    def both(
        self, status: policy.IssueStatusConfig | None
    ) -> tuple[str | None, str | None]:
        reader = policy.issue_status_reader(REPO, status, "main")
        eligible = policy.lane_eligibility(
            REPO,
            7,
            pr={"number": 7, "base": {"sha": SHA}, "changed_files": 1},
            denied_paths=LANE_DENIED,
            agent_identity=IDENTITY,
            permission=HUMANS,
            issue_holds=ISSUE_HOLDS,
            issue_status=reader,
        )
        recheck = policy.recheck_lane_issue(
            REPO, 7, issue=41, holds=ISSUE_HOLDS, status=reader
        )
        return eligible.reason, recheck

    def test_a_persons_field_hold_with_no_hold_label_refuses_at_both_reads(
        self,
    ) -> None:
        self.gh.graphql["PolicyIssueStatus"] = answer(
            "needs-spec", setter(HUMAN_ID, "kyle-sexton", "User")
        )
        self.assertEqual(
            self.both(live_config()), ("closing-issue-held:needs-spec",) * 2
        )

    def test_an_untrusted_setters_hold_passes(self) -> None:
        for who in (
            setter(3003, "drive-by", "User"),
            setter(300666570, "melodic-standards-sync"),
            setter(337859524, "melodic-release"),
        ):
            with self.subTest(who=who):
                self.gh.graphql["PolicyIssueStatus"] = answer("needs-human", who)
                self.assertEqual(self.both(live_config()), (None, None))

    def test_github_actions_holds_and_a_bot_setters_agent_ready_is_none(self) -> None:
        self.gh.graphql["PolicyIssueStatus"] = answer(
            "needs-human", setter(41898282, "github-actions")
        )
        self.assertEqual(
            self.both(live_config()), ("closing-issue-held:needs-human",) * 2
        )
        self.gh.graphql["PolicyIssueStatus"] = answer(
            "agent-ready", setter(288071998, "melodic-ai")
        )
        self.assertEqual(self.both(live_config()), (None, None))

    def test_an_unreadable_field_refuses_at_both_reads(self) -> None:
        self.gh.graphql["PolicyIssueStatus"] = 502
        self.assertEqual(
            self.both(live_config()), ("closing-issue-status-unreadable",) * 2
        )

    def test_a_hold_label_still_refuses_whatever_the_field_says(self) -> None:
        self.labels(["needs-human"])
        self.gh.graphql["PolicyIssueStatus"] = answer(
            "ready", setter(HUMAN_ID, "kyle-sexton", "User")
        )
        self.assertEqual(
            self.both(live_config()), ("closing-issue-held:needs-human",) * 2
        )
        self.assertFalse(any("PolicyIssueStatus" in " ".join(c) for c in self.gh.calls))

    def test_no_block_reads_no_field_and_no_trusted_list(self) -> None:
        self.assertIsNone(policy.issue_status_reader(REPO, None))
        self.assertEqual(self.both(None), (None, None))
        joined = [" ".join(c) for c in self.gh.calls]
        self.assertFalse(any("PolicyIssueStatus" in c for c in joined))
        self.assertFalse(any(policy.TRUSTED_ACTORS_PATH in c for c in joined))


class TheStatusLabels(unittest.TestCase):
    """read-status.mjs statusLabels: the field's state decides; queue-state
    labels give way to it, hold labels and agent-ready stay. Expected values
    are the JS reader's output for the same inputs."""

    def test_the_field_decides_as_statusLabels_does(self) -> None:
        config = live_config()
        for state, names, want in (
            (None, ["status: ready"], ["status: ready"]),
            ("confirmed", ["status: ready"], ["status: confirmed"]),
            ("needs-spec", ["status: ready"], ["needs-spec"]),
            ("needs-spec", ["needs-human"], ["needs-human", "needs-spec"]),
            ("confirmed", ["bug"], ["bug", "status: confirmed"]),
            ("needs-triage", ["bug"], ["bug", "needs-triage"]),
            ("agent-ready", ["status: ready", "agent-ready"], ["agent-ready"]),
            (
                "ready",
                ["Status: Confirmed", "needs-human"],
                ["needs-human", "status: ready"],
            ),
            ("ready", ["status: ready"], ["status: ready"]),
        ):
            with self.subTest(state=state, names=names):
                self.assertEqual(policy.status_label_names(state, names, config), want)
        self.assertEqual(policy.status_label_names("needs-spec", ["x"], None), ["x"])


class TheCappedClose(unittest.TestCase):
    """`capped_close` reads the field with the hold labels and, parking an
    issue, sets the field to confirmed and writes no status label."""

    def run_close(
        self,
        world: World,
        read: Any,
        labels: tuple[str, ...] = ("agent-ready",),
        field_events: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        events = {"repository": {"issue": {"timelineItems": {"nodes": field_events or []}}}}
        reader = StubReader(issue_labels=labels)
        reader.branch = "main"  # type: ignore[attr-defined]
        main = policy.PipelineConfig(MAIN, "C2", "pr-merge", IDENTITY, None, (), None)
        with (
            mock.patch.object(ve.merge_policy, "pull_request", return_value=world.pr),
            mock.patch.object(ve.postmerge, "_paginated", side_effect=world.paginated),
            mock.patch.object(ve.postmerge, "gh_capture", side_effect=world.gh),
            mock.patch.object(
                ve.merge_policy, "_default_branch_config", return_value=main
            ),
            mock.patch.object(ve.merge_policy, "issue_status", side_effect=read),
            mock.patch.object(ve.merge_policy, "_graphql", return_value=events),
        ):
            return ve.capped_close(
                reader,
                CAPPED_PR,
                CAPPED_HEAD,
                attempts=1,
                issue_holds=("needs-human",),
                issue_status=live_config(),
            )

    def parked_world(self) -> World:
        world = World()
        world.field_rows = CONFIRMED_ROWS
        world.comments[CAPPED_ISSUE] = [
            comment(
                f"<!-- verify-capped-close pr=40 heads={'3' * 40} attempt=1 of=1 -->\nearlier"
            )
        ]
        return world

    def test_parking_sets_the_field_to_confirmed_with_no_status_label(self) -> None:
        world = self.parked_world()
        result = self.run_close(world, lambda *a: "ready")
        self.assertEqual(result["parked"], [CAPPED_ISSUE])
        base = f"repos/{CAPPED_REPO}/issues/{CAPPED_ISSUE}"
        self.assertEqual(
            world.calls(),
            [
                f"POST repos/{CAPPED_REPO}/issues/{CAPPED_PR}/comments",
                f"POST {base}/comments",
                f"POST {base}/issue-field-values",
                f"PATCH repos/{CAPPED_REPO}/pulls/{CAPPED_PR}",
            ],
            "the park writes the field alone, no agent-ready label removal",
        )
        self.assertEqual(
            world.writes[2][4:],
            [
                "-H",
                "X-GitHub-Api-Version: 2026-03-10",
                "-F",
                f"issue_field_values[][field_id]={FIELD}",
                "-f",
                "issue_field_values[][value]=confirmed",
            ],
        )

    def test_a_park_field_write_that_does_not_land_raises_before_the_close(
        self,
    ) -> None:
        # No label stands in: a failed or drifted field write raises before
        # agent-ready comes off or the pull request closes, so the next run
        # retries the park.
        for name, rows in (
            ("failed", None),
            ("other option", [{"issue_field_id": FIELD, "single_select_option": {"id": 86380003}}]),
        ):
            with self.subTest(name):
                world = self.parked_world()
                base = f"repos/{CAPPED_REPO}/issues/{CAPPED_ISSUE}"
                if rows is None:
                    world.fail_once.add(f"POST {base}/issue-field-values")
                else:
                    world.field_rows = rows
                with self.assertRaises(RuntimeError) as raised:
                    self.run_close(world, lambda *a: "ready")
                self.assertIn("Work status not set to confirmed", str(raised.exception))
                self.assertEqual(world.calls()[-1], f"POST {base}/issue-field-values")
                self.assertFalse(any(a.startswith("labels[]=") for w in world.writes for a in w))

    def test_a_hold_set_before_the_park_keeps_the_issue_unparked(self) -> None:
        reads = iter(["ready", "needs-human"])
        world = self.parked_world()
        result = self.run_close(world, lambda *a: next(reads))
        self.assertEqual((result["parked"], result["held"]), ([], [CAPPED_ISSUE]))
        base = f"repos/{CAPPED_REPO}/issues/{CAPPED_ISSUE}"
        self.assertEqual(
            world.calls(),
            [
                f"POST repos/{CAPPED_REPO}/issues/{CAPPED_PR}/comments",
                f"POST {base}/comments",
                f"PATCH repos/{CAPPED_REPO}/pulls/{CAPPED_PR}",
            ],
            "no park, field or label write over the hold",
        )
        # Both records say the hold, neither says parked, and the issue's
        # marker names no attempt, so a rerun restarts nothing.
        for index in (0, 1):
            body = world.body(index)
            self.assertIn("held at Work status `needs-human`", body)
            self.assertNotIn("parked at", body)
        self.assertNotIn("parked", world.body(1).splitlines()[0])
        self.assertNotIn("attempt=", world.body(1).splitlines()[0])

    def test_a_restart_clears_then_sets_the_field_with_no_label_write(self) -> None:
        # write-status.mjs restart: DELETE the field value, then POST
        # agent-ready (option 84879220 in pr-pipeline.yaml).
        world = World()
        world.field_rows = AGENT_READY_ROWS
        result = self.run_close(world, lambda *a: "agent-ready")
        self.assertEqual(result["restarted"], [CAPPED_ISSUE])
        base = f"repos/{CAPPED_REPO}/issues/{CAPPED_ISSUE}"
        self.assertEqual(
            world.calls(),
            [
                f"POST repos/{CAPPED_REPO}/issues/{CAPPED_PR}/comments",
                f"POST {base}/comments",
                f"DELETE {base}/issue-field-values/{FIELD}",
                f"POST {base}/issue-field-values",
                f"PATCH repos/{CAPPED_REPO}/pulls/{CAPPED_PR}",
            ],
            "the restart goes through the field alone, no label call",
        )
        self.assertEqual(
            world.writes[2][4:], ["-H", "X-GitHub-Api-Version: 2026-03-10"]
        )
        self.assertIn("issue_field_values[][value]=agent-ready", world.writes[3])

    def test_a_restart_set_that_does_not_land_raises_before_the_close(self) -> None:
        world = World()
        world.field_rows = CONFIRMED_ROWS
        with self.assertRaises(RuntimeError) as raised:
            self.run_close(world, lambda *a: "agent-ready")
        self.assertIn("Work status not set to agent-ready", str(raised.exception))
        self.assertNotIn(
            f"PATCH repos/{CAPPED_REPO}/pulls/{CAPPED_PR}", world.calls()
        )

    def restart_rerun(self) -> World:
        # Run 1 wrote both records with an attempt and stopped before the close.
        world = World()
        world.field_rows = AGENT_READY_ROWS
        world.comments[CAPPED_PR] = [
            comment(f"<!-- verify-capped-close pr={CAPPED_PR} heads= -->")
        ]
        world.comments[CAPPED_ISSUE] = [
            comment(f"<!-- verify-capped-close pr={CAPPED_PR} heads= attempt=1 of=1 -->")
        ]
        return world

    def test_a_rerun_after_the_field_restart_landed_restarts_nothing(self) -> None:
        world = self.restart_rerun()
        landed = {
            "__typename": "IssueFieldAddedEvent",
            "createdAt": "2026-10-29T10:00:00Z",
            "value": "agent-ready",
            "actor": setter(LANES_ID, "melodic-automation-lanes"),
            "issueField": WORK_STATUS,
        }
        self.run_close(world, lambda *a: "agent-ready", field_events=[landed])
        self.assertEqual(
            world.calls(),
            [f"PATCH repos/{CAPPED_REPO}/pulls/{CAPPED_PR}"],
            "the lanes App's agent-ready set at the record is run 1's restart: no second one",
        )

    def test_a_rerun_with_no_lanes_app_set_since_the_record_restarts(self) -> None:
        base = f"repos/{CAPPED_REPO}/issues/{CAPPED_ISSUE}"
        restart = [
            f"DELETE {base}/issue-field-values/{FIELD}",
            f"POST {base}/issue-field-values",
            f"PATCH repos/{CAPPED_REPO}/pulls/{CAPPED_PR}",
        ]
        for name, event in (
            ("someone else's set", ("2026-10-29T11:00:00Z", setter(HUMAN_ID, "kyle-sexton", "User"))),
            ("the App's set before the record", ("2026-10-29T09:00:00Z", setter(LANES_ID, "melodic-automation-lanes"))),
        ):
            with self.subTest(name):
                world = self.restart_rerun()
                at, who = event
                self.run_close(
                    world,
                    lambda *a: "agent-ready",
                    field_events=[
                        {
                            "__typename": "IssueFieldAddedEvent",
                            "createdAt": at,
                            "value": "agent-ready",
                            "actor": who,
                            "issueField": WORK_STATUS,
                        }
                    ],
                )
                self.assertEqual(world.calls(), restart)

    def test_a_rerun_restarts_nothing_once_a_person_moved_the_field(self) -> None:
        world = self.restart_rerun()
        self.run_close(world, lambda *a: "ready")
        self.assertEqual(world.calls(), [f"PATCH repos/{CAPPED_REPO}/pulls/{CAPPED_PR}"])

    def test_a_parked_rerun_with_the_field_confirmed_writes_nothing(self) -> None:
        # A lingering agent-ready label does not make the park unfinished.
        world = World()
        world.field_rows = CONFIRMED_ROWS
        world.comments[CAPPED_PR] = [
            comment(f"<!-- verify-capped-close pr={CAPPED_PR} heads= -->")
        ]
        world.comments[CAPPED_ISSUE] = [
            comment(
                f"<!-- verify-capped-close pr={CAPPED_PR} heads= attempt=1 of=1 parked -->"
            )
        ]
        self.run_close(world, lambda *a: "confirmed", ("agent-ready",))
        self.assertEqual(world.calls(), [f"PATCH repos/{CAPPED_REPO}/pulls/{CAPPED_PR}"])

    def test_a_held_field_keeps_it_open(self) -> None:
        world = World()
        result = self.run_close(world, lambda *a: "needs-owner-decision")
        self.assertEqual(
            result,
            {"closed": False, "reason": "closing-issue-held:needs-owner-decision"},
        )
        self.assertEqual(world.writes, [])

    def test_a_parked_rerun_is_done_as_statusLabels_reads_it(self) -> None:
        # read-status.mjs statusLabels: the field decides; a stale queue-state
        # label gives way to it.
        parked = (
            f"<!-- verify-capped-close pr={CAPPED_PR} heads= attempt=1 of=1 parked -->"
        )
        close = [f"PATCH repos/{CAPPED_REPO}/pulls/{CAPPED_PR}"]
        for field, labels, done in (
            ("confirmed", ("status: ready",), True),
            ("confirmed", ("bug",), True),
            ("ready", ("status: confirmed",), False),
        ):
            with self.subTest(field=field, labels=labels):
                world = World()
                world.field_rows = CONFIRMED_ROWS
                world.comments[CAPPED_PR] = [
                    comment(f"<!-- verify-capped-close pr={CAPPED_PR} heads= -->")
                ]
                world.comments[CAPPED_ISSUE] = [comment(parked)]
                result = self.run_close(world, lambda *a, f=field: f, labels)
                self.assertEqual(result["parked"], [CAPPED_ISSUE])
                if done:
                    self.assertEqual(world.calls(), close)
                else:
                    self.assertIn(
                        f"POST repos/{CAPPED_REPO}/issues/{CAPPED_ISSUE}/issue-field-values",
                        world.calls(),
                    )

    def test_a_failed_field_read_raises(self) -> None:
        def fail(*_: Any) -> str:
            raise policy.PolicyReadError("HTTP 502")

        world = World()
        with self.assertRaises(RuntimeError):
            self.run_close(world, fail)
        self.assertEqual(world.writes, [])


class StatusGh(FakeGh):
    """FakeGh serving the default branch's pipeline file raw and the record's
    field and label writes."""

    def __init__(self) -> None:
        super().__init__()
        self.pipeline: str | None = None
        self.field_answer: Any = [
            {"issue_field_id": FIELD, "single_select_option": {"id": 86380005}}
        ]
        # The PolicyIssueStatus answer for a record, or the HTTP status its
        # read fails with.
        self.work_status: Any = answer(None, None)

    def __call__(
        self, args: list[str], **kwargs: Any
    ) -> subprocess.CompletedProcess[Any]:
        joined = " ".join(args)
        if args[:2] == ["api", "graphql"] and "PolicyIssueStatus" in joined:
            self.calls.append(list(args))
            self.tokens.append(None)
            if isinstance(self.work_status, int):
                return completed(
                    returncode=1, stderr=f"gh: Error (HTTP {self.work_status})"
                )
            return completed({"data": self.work_status})
        if f"contents/{policy.CONFIG_PATH}" in joined and "?ref=" not in joined:
            self.calls.append(list(args))
            self.tokens.append(None)
            if self.pipeline is None:
                return completed(returncode=1, stderr="gh: Not Found (HTTP 404)")
            return subprocess.CompletedProcess(["gh"], 0, self.pipeline, "")
        if joined.endswith("/issue-field-values") or "/issue-field-values " in joined:
            self.calls.append(list(args))
            self.tokens.append(None)
            if isinstance(self.field_answer, int):
                return completed(
                    returncode=1, stderr=f"gh: Error (HTTP {self.field_answer})"
                )
            return completed(self.field_answer)
        if "/issues/9001/labels" in joined:
            self.calls.append(list(args))
            self.tokens.append(None)
            return completed([{"name": "needs-human"}])
        return super().__call__(args, **kwargs)


class TheDemotionRecord(CheckCase):
    def setUp(self) -> None:
        super().setUp()
        self.gh = StatusGh()
        for module in (pm, pm.policy):
            patcher = mock.patch.object(module, "gh_capture", self.gh)
            patcher.start()
            self.addCleanup(patcher.stop)
        policy._ISSUE_STATUS.clear()

    def remediate(self) -> dict[str, Any]:
        self.gh.merged = [identity_merge()]
        self.all_green()
        return pm.remediate(
            PM_REPO, self.check(pinned=OTHER_SHA), agent_identity=IDENTITY
        )

    def creates(self) -> list[list[str]]:
        return [w for w in self.gh.writes() if f"repos/{PM_REPO}/issues" in w]

    def test_a_failed_hold_still_files_the_next_record(self) -> None:
        self.gh.pipeline = SMALL
        self.gh.field_answer = 502
        self.gh.merged = [identity_merge()]
        self.all_green()
        verdict = self.check(pinned=OTHER_SHA)
        first = verdict.failures[0]
        second = dataclasses.replace(first, signal="second", run_url=None)
        verdict = dataclasses.replace(verdict, failures=(first, second))
        report = pm.remediate(PM_REPO, verdict, agent_identity=IDENTITY)
        self.assertEqual(len(self.creates()), 2)
        labels = [w for w in self.gh.writes() if w[3].endswith("/labels")]
        self.assertEqual(labels, [])
        self.assertEqual(len(report["errors"]), 2)
        self.assertTrue(all("Work status not set" in e for e in report["errors"]))

    def test_configured_files_unlabeled_then_sets_the_field(self) -> None:
        self.gh.pipeline = SMALL
        report = self.remediate()
        self.assertEqual(report["errors"], [])
        create, set_type, field = self.gh.writes()[-3:]
        self.assertIn(f"repos/{PM_REPO}/issues", create)
        self.assertIn("type=Bug", set_type)
        self.assertFalse(any(a.startswith("labels[]=") for a in create))
        self.assertEqual(
            field,
            [
                "api",
                "-X",
                "POST",
                f"repos/{PM_REPO}/issues/9001/issue-field-values",
                "-H",
                "X-GitHub-Api-Version: 2026-03-10",
                "-F",
                f"issue_field_values[][field_id]={FIELD}",
                "-f",
                "issue_field_values[][value]=needs-human",
            ],
        )

    def test_a_failed_or_mismatched_write_errors_with_no_label(self) -> None:
        # As post-merge-demotion-alert.yml: the field write that did not land
        # is an error, and no status label stands in for it.
        for name, field_answer in (
            ("failed", 502),
            (
                "other option",
                [{"issue_field_id": FIELD, "single_select_option": {"id": 86380003}}],
            ),
        ):
            with self.subTest(name):
                self.setUp()
                self.gh.pipeline = SMALL
                self.gh.field_answer = field_answer
                report = self.remediate()
                self.assertIn("issue-field-values", self.gh.writes()[-1][3])
                self.assertFalse(
                    any(
                        a.startswith("labels[]=")
                        for w in self.gh.writes()
                        for a in w
                    )
                )
                self.assertEqual(len(report["errors"]), 1)
                self.assertIn("Work status not set", report["errors"][0])

    def test_a_later_pass_retries_a_hold_only_while_the_field_is_unset(
        self,
    ) -> None:
        # The first hold write fails; the record then exists, so a second pass
        # over the same verdict takes the existing-record path.
        person = setter(HUMAN_ID, "kyle-sexton", "User")
        for name, work_status, want_hold, want_errors in (
            ("unset", answer(None, None), True, 0),
            ("set by a person", answer("needs-spec", person), False, 0),
            (
                "set by an uncounted account",
                answer("ready", setter(3003, "drive-by", "User")),
                False,
                0,
            ),
            ("unreadable", 502, False, 1),
        ):
            with self.subTest(name):
                self.setUp()
                self.gh.pipeline = SMALL
                self.gh.field_answer = 502
                self.gh.merged = [identity_merge()]
                self.all_green()
                verdict = self.check(pinned=OTHER_SHA)
                first = pm.remediate(PM_REPO, verdict, agent_identity=IDENTITY)
                self.assertEqual(len(first["errors"]), 1)
                create = self.creates()[-1]
                body = next(a for a in create if a.startswith("body="))
                self.gh.issues.append(
                    {
                        "number": 9001,
                        "state": "open",
                        "body": body.removeprefix("body="),
                        "user": {"login": IDENTITY},
                    }
                )
                self.gh.field_answer = [
                    {"issue_field_id": FIELD, "single_select_option": {"id": 86380005}}
                ]
                self.gh.work_status = work_status
                before = len(self.gh.writes())
                report = pm.remediate(PM_REPO, verdict, agent_identity=IDENTITY)
                later = self.gh.writes()[before:]
                holds = [
                    w for w in later if w[3] == f"repos/{PM_REPO}/issues/9001/issue-field-values"
                ]
                self.assertEqual(len(holds), 1 if want_hold else 0, later)
                self.assertFalse(
                    any(a.startswith("labels[]=") for w in later for a in w)
                )
                self.assertEqual(len(report["errors"]), want_errors, report["errors"])
                if want_errors:
                    self.assertIn("Work status", report["errors"][0])
                self.assertEqual(report["issues"], [])

    def test_unconfigured_files_the_labeled_record_as_before(self) -> None:
        report = self.remediate()
        self.assertEqual(report["errors"], [])
        (create,) = self.creates()
        self.assertEqual(create[-2:], ["-f", "labels[]=needs-human"])
        self.assertFalse(
            any("issue-field-values" in " ".join(w) for w in self.gh.writes())
        )


class TheBlockReachesEveryRead(unttd.Unattended):
    """The configured block reaches the gate's eligibility read and its
    re-read before the enqueue, the gate's capped close, and the capped-close
    command."""

    def setUp(self) -> None:
        super().setUp()
        self.status = live_config()
        self.config = policy.PipelineConfig(
            unttd.BASE, "C2", "pr-merge", unttd.IDENTITY, 200, (".github/**",),
            "c2-mechanical", require_verifier_verdict=True, path_holds=True,
            floor_paths=unttd.evidence_tests.FLOOR_ROWS,
            issue_status=self.status,
        )  # fmt: skip
        passing = unttd.merge.verify_evidence.Evidence(
            refusal=None, head=unttd.HEAD, verdicts=(), ignored=0
        )
        patcher = mock.patch.object(
            unttd.merge.verify_evidence.Reader, "evidence", return_value=passing
        )
        patcher.start()
        self.addCleanup(patcher.stop)
        self.opt_in_recheck = "not-lane-authored-or-opted-in"
        self.promotion = policy.Promotion(None, "resolver-failed")
        self.kill = []
        role_label = unttd.fixtures.role_label_stub()
        role_label.start()
        self.addCleanup(role_label.stop)

    def test_the_gate_hands_its_reader_to_both_reads(self) -> None:
        def reader(number: int) -> str | None:
            return None

        made: list[tuple[Any, ...]] = []
        seen: list[dict[str, Any]] = []
        self.lane_eligible = None
        with (
            mock.patch.object(
                policy,
                "issue_status_reader",
                side_effect=lambda *a: made.append(a) or reader,
            ),
            mock.patch.object(
                policy,
                "lane_eligibility",
                side_effect=lambda *a, **k: (
                    seen.append(k) or policy.Eligibility(True, None, "C2", 41)
                ),
            ),
        ):
            self.run_main(
                "--authority", "pr-merge", "--lane-kill-switch", "proceed",
                "--lane-rung-cap", "",
            )  # fmt: skip
        self.assertEqual([a[1] for a in made], [self.status])
        self.assertIs(seen[0]["issue_status"], reader)
        self.assertIs(self.lane_recheck_kwargs[0]["status"], reader)

    def test_the_gates_capped_close_takes_the_block(self) -> None:
        with (
            mock.patch.object(policy, "entry_hold", return_value=None),
            mock.patch.object(unttd.merge, "human_gated_label", return_value="h"),
            mock.patch.object(
                ve, "capped_close", return_value={"closed": False}
            ) as close,
        ):
            unttd.merge.close_capped(
                REPO, 7, IDENTITY, "main", self.config, {"pr": {"head": {"sha": SHA}}}
            )
        self.assertIs(close.call_args.kwargs["issue_status"], self.status)

    def test_the_gates_capped_close_takes_a_remapped_admission_label(self) -> None:
        def role_label(
            owner: str,
            name: str,
            *,
            strict: bool = False,
            role: str = "human-gated",
            default: str = "needs-human",
        ) -> str:
            return "go ready" if role == policy.ADMISSION_ROLE else default

        with (
            mock.patch.object(policy, "entry_hold", return_value=None),
            mock.patch.object(unttd.merge, "human_gated_label", return_value="h"),
            mock.patch.object(
                unttd.merge.postmerge, "_role_label", side_effect=role_label
            ),
            mock.patch.object(
                ve, "capped_close", return_value={"closed": False}
            ) as close,
        ):
            unttd.merge.close_capped(
                REPO, 7, IDENTITY, "main", self.config, {"pr": {"head": {"sha": SHA}}}
            )
        self.assertEqual(close.call_args.kwargs["admission"], "go ready")
        # The default label is not passed, so the kwarg is the remap alone.
        self.assertNotIn("admission", self.default_close_kwargs())

    def default_close_kwargs(self) -> dict[str, Any]:
        with (
            mock.patch.object(policy, "entry_hold", return_value=None),
            mock.patch.object(unttd.merge, "human_gated_label", return_value="h"),
            mock.patch.object(
                ve, "capped_close", return_value={"closed": False}
            ) as close,
        ):
            unttd.merge.close_capped(
                REPO, 7, IDENTITY, "main", self.config, {"pr": {"head": {"sha": SHA}}}
            )
        return dict(close.call_args.kwargs)

    def test_the_capped_close_command_takes_the_block(self) -> None:
        config = dataclasses.replace(self.config, issue_holds=("needs-human",))
        with (
            mock.patch.object(ve.merge_policy, "config_at", return_value=config),
            mock.patch.object(
                ve.merge_policy, "with_default_branch", return_value=config
            ),
            mock.patch.object(
                ve, "capped_close", return_value={"closed": True}
            ) as close,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            ve.main(["capped-close", "--repo", REPO, "--base-sha", SHA, "50", "a" * 40])
        self.assertIs(close.call_args.kwargs["issue_status"], self.status)


if __name__ == "__main__":
    unittest.main()

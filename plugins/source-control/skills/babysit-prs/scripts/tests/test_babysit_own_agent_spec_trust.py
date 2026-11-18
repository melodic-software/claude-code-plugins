# test-scope: .github/scripts/intake-triage/admit.mjs .github/actions/resolve-config/admission-rules.json .github/actions/resolve-config/resolve-config.mjs .github/scripts/work-unblock/label-unblocked.mjs
"""The gate's own-agent trust rule (`babysit_verify_evidence._trusted_spec`)
takes the filings intake admission admits (ADR 0111): an issue an identity in
`own-agents.identities` wrote, no other account edited, carrying exactly one
`source: <producer>` label, sized small or medium by a listed human or the
lanes App. github-actions[bot] never counts, whatever the list says. The
predicates are run beside admit.mjs under node. Network is stubbed at the
`gh_capture` seam.
"""

from __future__ import annotations

import base64
import json
import pathlib
import shutil
import subprocess
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_postmerge as postmerge
import babysit_verify_evidence as ve

ADMIT = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/intake-triage/admit.mjs"
)
RESOLVE_CONFIG = ADMIT.parents[2] / "actions/resolve-config/resolve-config.mjs"
REPO = "example-org/example-repo"
ISSUE = 7
MAIN_TIP = "a" * 40
IDENTITY = "agent-lanes[bot]"
APP_ID = 337595936
OTHER_BOT_ID = 555
HUMAN_ID = 100
OUTSIDER_ID = 999
ACTIONS_ID = 41898282
APP = {"__typename": "Bot", "login": "agent-lanes", "databaseId": APP_ID}
OTHER_BOT = {"__typename": "Bot", "login": "other", "databaseId": OTHER_BOT_ID}
ACTIONS = {"__typename": "Bot", "login": "github-actions", "databaseId": ACTIONS_ID}
HUMAN = {"__typename": "User", "login": "human-100", "databaseId": HUMAN_ID}
OUTSIDER = {"__typename": "User", "login": "drive-by", "databaseId": OUTSIDER_ID}
EDITED = "2026-11-10T00:00:00Z"
SIZE_FIELD = 501
OTHER_FIELD = 502
SMALL, MEDIUM, LARGE, UNMAPPED = 11, 12, 13, 14
CONFIG = f"""\
models:
  issue-dimensions:
    fields:
      size:
        field-id: {SIZE_FIELD}
        options:
          "{SMALL}": small
          "{MEDIUM}": medium
          "{LARGE}": large
"""
ACTORS = {
    "version": 1,
    "actors": [
        {"id": HUMAN_ID, "login": "human-100", "kind": "human"},
        {"id": APP_ID, "login": IDENTITY, "kind": "bot"},
    ],
}


def field_event(
    actor: dict[str, Any] | None,
    kind: str = "IssueFieldAddedEvent",
    field: int = SIZE_FIELD,
) -> dict[str, Any]:
    return {
        "__typename": kind,
        "actor": actor,
        "issueField": {"fullDatabaseId": str(field)},
    }


class FakeGitHub:
    """Answers the default branch, the trusted-actor list, admission's rules,
    the pipeline config, the issue, its field values and its field events. A
    name in `fail` answers that read with a server error."""

    def __init__(
        self,
        issue: dict[str, Any],
        option: int | None,
        events: list[dict[str, Any]],
        rules: dict[str, Any],
        fail: str | None,
        config: str,
    ):
        self.issue = issue
        self.option = option
        self.events = events
        self.rules = rules
        self.fail = fail
        self.config = config
        self.reads: dict[str, int] = {}
        self.tokens: dict[str, Any] = {}

    def served(
        self, name: str, args: list[str], kwargs: dict[str, Any], answer: Any
    ) -> Any:
        self.reads[name] = self.reads.get(name, 0) + 1
        self.tokens[name] = kwargs.get("env_overrides")
        if self.fail == name:
            return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
        return subprocess.CompletedProcess(args, 0, json.dumps(answer), "")

    def __call__(
        self, args: list[str], **kwargs: Any
    ) -> subprocess.CompletedProcess[str]:
        def ok(answer: Any) -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(args, 0, json.dumps(answer), "")

        if args == ["api", f"repos/{REPO}"]:
            return ok({"default_branch": "main"})
        if args == ["api", f"repos/{REPO}/git/ref/heads/main"]:
            return ok(
                {
                    "ref": "refs/heads/main",
                    "object": {"sha": MAIN_TIP, "type": "commit"},
                }
            )
        if args[:2] == ["api", "graphql"]:
            if f"query={ve.SPLIT_CHILD_QUERY}" in args:
                return ok({"data": {"repository": {"issue": {"parent": None}}}})
            if f"query={ve.ACTIONS_ISSUE_QUERY}" in args:
                return ok({"data": {"repository": {"issue": self.issue}}})
            if f"query={ve.OWN_AGENT_ISSUE_QUERY}" in args:
                answer = {"data": {"repository": {"issue": self.issue}}}
                return self.served("issue", args, kwargs, answer)
            if f"query={ve.merge_policy.ISSUE_STATUS_QUERY}" in args:
                nodes = {"timelineItems": {"nodes": self.events}}
                answer = {"data": {"repository": {"issue": nodes}}}
                return self.served("events", args, kwargs, answer)
            raise AssertionError(f"unexpected query: {args}")
        if any(a == f"repos/{REPO}/issues/{ISSUE}/issue-field-values" for a in args):
            assert f"X-GitHub-Api-Version: {ve.merge_policy.FIELD_API_VERSION}" in args
            rows = [
                {"issue_field_id": OTHER_FIELD, "single_select_option": {"id": SMALL}}
            ]
            if self.option is not None:
                rows.append(
                    {
                        "issue_field_id": SIZE_FIELD,
                        "single_select_option": {"id": self.option},
                    }
                )
            return self.served("values", args, kwargs, rows)
        if args == [
            "api",
            f"repos/{REPO}/contents/{ve.merge_policy.CONFIG_PATH}?ref={MAIN_TIP}",
        ]:
            content = base64.b64encode(self.config.encode()).decode()
            answer = {"type": "file", "encoding": "base64", "content": content}
            return self.served("config", args, kwargs, answer)
        for a in args:
            if a.startswith(f"repos/{REPO}/contents/{ve.ADMISSION_RULES_PATH}?"):
                return self.served("rules", args, kwargs, self.rules)
            if a.startswith(f"repos/{REPO}/contents/{ve.TRUSTED_ACTORS_PATH}?"):
                return ok(ACTORS)
            if a.startswith(f"repos/{REPO}/contents/{ve.RECURRING_SCHEDULE_PATH}?"):
                return ok({"items": []})
        raise AssertionError(f"unexpected gh call: {args}")


def recorded(author: dict[str, Any]) -> dict[str, Any]:
    """The issue as a verdict's `linked_issues` records it."""
    return {
        "number": ISSUE,
        "author_login": author["login"],
        "author_id": author["databaseId"],
        "author_type": author["__typename"],
        "last_edited_at": None,
        "editor_login": None,
        "editor_id": None,
        "editor_type": None,
        "spec_comments": [],
    }


def judge(
    *,
    author: dict[str, Any] = APP,
    editor: dict[str, Any] | None = None,
    body: str = "## Done when\n\n- [ ] The thing is done.\n",
    labels: list[str] | None = None,
    labels_total: int | None = None,
    option: int | None = SMALL,
    events: list[dict[str, Any]] | None = None,
    rules: dict[str, Any] | None = None,
    fail: str | None = None,
    config: str = CONFIG,
    identity: str | None = IDENTITY,
) -> tuple[bool, FakeGitHub]:
    names = ["source: improvement"] if labels is None else labels
    issue = {
        "title": "Tidy the thing",
        "body": body,
        "author": author,
        "lastEditedAt": EDITED if editor else None,
        "editor": editor,
        "labels": {
            "totalCount": len(names) if labels_total is None else labels_total,
            "nodes": [{"name": name} for name in names],
        },
    }
    fake = FakeGitHub(
        issue,
        option,
        [field_event(APP)] if events is None else events,
        {"task-list": "- [ ] "} if rules is None else rules,
        fail,
        config,
    )
    with (
        mock.patch.dict("os.environ", {}, clear=False) as env,
        mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
    ):
        env.pop("BABYSIT_RUN_CACHE", None)
        reader = ve.Reader(
            REPO, "main", agent_identity=identity, actions_token="actions-token"
        )
        return reader._trusted_spec({"linked_issues": [recorded(author)]}), fake


class AFilingAdmissionAdmits(unittest.TestCase):
    def test_a_small_or_medium_filing_with_one_source_label_is_trusted(self) -> None:
        for option in (SMALL, MEDIUM):
            with self.subTest(option):
                self.assertIs(judge(option=option)[0], True)

    def test_the_filing_identity_editing_its_own_body_keeps_it_trusted(self) -> None:
        self.assertIs(judge(editor=APP)[0], True)

    def test_a_size_a_listed_human_set_counts(self) -> None:
        self.assertIs(judge(events=[field_event(HUMAN)])[0], True)

    def test_a_source_label_in_any_case_counts(self) -> None:
        self.assertIs(judge(labels=["SOURCE: improvement", "bug"])[0], True)

    def test_labels_beside_the_source_label_do_not_matter(self) -> None:
        self.assertIs(judge(labels=["bug", "source: tidy lane", "area: ci"])[0], True)


class EachAdmissionConditionHolds(unittest.TestCase):
    def test_a_filing_short_of_one_condition_is_refused(self) -> None:
        for why, kwargs in {
            "no source label": {"labels": ["bug"]},
            "no labels at all": {"labels": []},
            "two source labels": {"labels": ["source: a", "source: b"]},
            "a source label with no producer": {"labels": ["source:"]},
            "a source label with no space": {"labels": ["source:tidy"]},
            "a source label naming two producers": {"labels": ["source: a, b"]},
            "a label list cut short": {"labels_total": 101},
            "size large": {"option": LARGE},
            "no size": {"option": None},
            "a size no option maps": {"option": UNMAPPED},
            "a body a listed human edited": {"editor": HUMAN},
            "a body an outsider edited": {"editor": OUTSIDER},
            "a body another bot edited": {"editor": OTHER_BOT},
            "a body github-actions edited": {"editor": ACTIONS},
            "a split child's marker": {"body": f"{ve.SPLIT_CHILD_MARKER}\nPart 1 of 2"},
        }.items():
            with self.subTest(why):
                self.assertIs(judge(**kwargs)[0], False)

    def test_a_size_only_a_trusted_setter_set_counts(self) -> None:
        for why, events in {
            "an outsider set it": [field_event(OUTSIDER)],
            "another bot set it": [field_event(OTHER_BOT)],
            "github-actions set it": [field_event(ACTIONS)],
            "an outsider changed the App's value": [
                field_event(APP),
                field_event(OUTSIDER, "IssueFieldChangedEvent"),
            ],
            "the newest event removed it": [
                field_event(APP),
                field_event(HUMAN, "IssueFieldRemovedEvent"),
            ],
            "the setter has no id": [field_event(None)],
            "only another field was set": [field_event(APP, field=OTHER_FIELD)],
            "no event names a setter": [],
        }.items():
            with self.subTest(why):
                self.assertIs(judge(events=events)[0], False)

    def test_a_trusted_setter_after_an_outsider_counts(self) -> None:
        events = [field_event(OUTSIDER), field_event(HUMAN, "IssueFieldChangedEvent")]
        self.assertIs(judge(events=events)[0], True)

    def test_a_refused_filing_reads_no_size(self) -> None:
        _, fake = judge(labels=["bug"])
        self.assertNotIn("values", fake.reads)
        self.assertNotIn("events", fake.reads)


class OnlyTheListedIdentitiesCount(unittest.TestCase):
    def test_with_no_list_the_lanes_app_alone_counts(self) -> None:
        self.assertIs(judge(rules={"task-list": "- [ ] "})[0], True)
        self.assertIs(judge(author=OTHER_BOT)[0], False)

    def test_an_account_id_on_the_list_counts(self) -> None:
        rules = {"own-agents": {"identities": [OTHER_BOT_ID]}}
        self.assertIs(judge(author=OTHER_BOT, rules=rules)[0], True)

    def test_the_lanes_app_off_the_list_does_not_count(self) -> None:
        rules = {"own-agents": {"identities": [OTHER_BOT_ID]}}
        trusted, fake = judge(rules=rules)
        self.assertIs(trusted, False)
        self.assertNotIn("issue", fake.reads)

    def test_no_agent_identity_leaves_the_lanes_app_uncounted(self) -> None:
        self.assertIs(judge(identity=None)[0], False)

    def test_github_actions_never_counts_even_when_listed(self) -> None:
        rules = {"own-agents": {"identities": ["lanes-app", ACTIONS_ID]}}
        trusted, fake = judge(author=ACTIONS, rules=rules)
        self.assertIs(trusted, False)
        self.assertNotIn("issue", fake.reads)

    def test_a_person_never_counts_as_an_identity(self) -> None:
        rules = {"own-agents": {"identities": [OUTSIDER_ID]}}
        trusted, fake = judge(author=OUTSIDER, rules=rules)
        self.assertIs(trusted, False)
        self.assertNotIn("rules", fake.reads)

    def test_a_person_using_a_listed_id_is_no_own_agent(self) -> None:
        impostor = {**OTHER_BOT, "__typename": "User"}
        rules = {"own-agents": {"identities": [OTHER_BOT_ID]}}
        self.assertIs(judge(author=impostor, rules=rules)[0], False)

    def test_a_malformed_list_is_unreadable(self) -> None:
        for why, section in {
            "identities not a list": {"identities": "lanes-app"},
            "an unknown name": {"identities": ["someone"]},
            "a negative id": {"identities": [-1]},
            "a boolean": {"identities": [True]},
            "a section that is no object": ["lanes-app"],
        }.items():
            with self.subTest(why), self.assertRaises(ve._Unreadable):
                judge(rules={"own-agents": section})


class AFailedReadRefusesAsUnreadable(unittest.TestCase):
    def test_each_read_behind_the_rule(self) -> None:
        for read in ("rules", "issue", "values", "events", "config"):
            with self.subTest(read), self.assertRaises(ve._Unreadable):
                judge(fail=read)

    def test_a_config_with_no_size_field_is_unreadable(self) -> None:
        with self.assertRaises(ve._Unreadable):
            judge(config="models:\n  other: 1\n")


class TheReadsAreTheGatesOwn(unittest.TestCase):
    def test_the_issue_and_its_size_are_read_under_the_actions_token(self) -> None:
        _, fake = judge()
        for read in ("issue", "values", "events"):
            with self.subTest(read):
                self.assertEqual(fake.tokens[read], {"GH_TOKEN": "actions-token"})

    def test_a_filing_judged_twice_is_read_once(self) -> None:
        fake = FakeGitHub(
            {
                "body": "b",
                "author": APP,
                "lastEditedAt": None,
                "editor": None,
                "labels": {"totalCount": 1, "nodes": [{"name": "source: x"}]},
            },
            SMALL,
            [field_event(APP)],
            {"task-list": "- [ ] "},
            None,
            CONFIG,
        )
        with (
            mock.patch.dict("os.environ", {}, clear=False) as env,
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
        ):
            env.pop("BABYSIT_RUN_CACHE", None)
            reader = ve.Reader(REPO, "main", agent_identity=IDENTITY)
            record = {"linked_issues": [recorded(APP)]}
            self.assertIs(reader._trusted_spec(record), True)
            self.assertIs(reader._trusted_spec(record), True)
        self.assertEqual((fake.reads["issue"], fake.reads["values"]), (1, 1))

    def test_comments_stay_a_listed_humans(self) -> None:
        with mock.patch.object(
            ve.Reader, "_trusted_humans", return_value=frozenset({HUMAN_ID})
        ):
            reader = ve.Reader(REPO, "main", agent_identity=IDENTITY)
            self.assertIs(reader._trusted_actor("Bot", APP_ID), False)
            self.assertIs(reader._trusted_actor("User", HUMAN_ID), True)


LABEL_CASES: list[tuple[list[str], bool]] = [
    (["source: improvement"], True),
    (["Source: improvement"], True),
    (["SOURCE: a b c"], True),
    (["source: a", "bug"], True),
    (["bug"], False),
    ([], False),
    (["source: a", "source: b"], False),
    (["source: a", "SOURCE: b"], False),
    (["source:"], False),
    (["source: "], False),
    (["source:a"], False),
    (["source:  a"], False),
    (["source: a,b"], False),
    (["source: ,a"], False),
    (["source:\ta"], False),
    (["source: \ta"], False),
    (["source: \u00a0a"], False),
    (["source: \ufeffa"], False),
    (["source: \u2003a"], False),
    (["\u017fource: a"], False),
    (["source: a", "\u017fource: b"], True),
    (["sources: a"], False),
    ([" source: a"], False),
    (["source: a\n"], True),
]
TEXT_CASES: list[tuple[dict[str, Any], Any, list[int], bool]] = [
    (APP, None, [APP_ID], True),
    (APP, APP, [APP_ID], True),
    (APP, HUMAN, [APP_ID], False),
    (APP, OUTSIDER, [APP_ID], False),
    (APP, OTHER_BOT, [APP_ID], False),
    (APP, None, [OTHER_BOT_ID], False),
    (OTHER_BOT, OTHER_BOT, [APP_ID, OTHER_BOT_ID], True),
    (OTHER_BOT, APP, [APP_ID, OTHER_BOT_ID], False),
    (HUMAN, None, [HUMAN_ID], False),
    ({**APP, "__typename": "User"}, None, [APP_ID], False),
    (APP, {**APP, "__typename": "User"}, [APP_ID], False),
]
ID_CASES: list[tuple[list[Any], list[int]]] = [
    (["lanes-app"], [APP_ID]),
    ([], []),
    ([OTHER_BOT_ID], [OTHER_BOT_ID]),
    (["lanes-app", OTHER_BOT_ID], [OTHER_BOT_ID, APP_ID]),
]
NODE = """
import { LANES_APP_IDENTITY, OWN_AGENT_DEFAULTS, OWN_AGENT_SIZES, SOURCE_LABEL, SPLIT_CHILD_MARKER,
  ownAgentIds, ownAgentText, sourceLabels } from %s;
const { labels, texts, ids, app } = JSON.parse(process.argv[1]);
console.log(JSON.stringify({
  identity: LANES_APP_IDENTITY,
  defaults: OWN_AGENT_DEFAULTS.identities,
  sizes: OWN_AGENT_SIZES,
  marker: SPLIT_CHILD_MARKER,
  labels: labels.map((names) => {
    const found = sourceLabels(names.map((name) => ({ name })));
    return found.length === 1 && SOURCE_LABEL.test(found[0]);
  }),
  texts: texts.map(([author, editor, listed]) =>
    ownAgentText({ author, editor, lastEditedAt: editor ? "2026-11-10T00:00:00Z" : null }, new Set(listed))),
  ids: ids.map((identities) => [...ownAgentIds({ "own-agents": { identities } }, app)].sort((a, b) => a - b)),
}));
"""


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheGateAndAdmissionAgree(unittest.TestCase):
    answer: dict[str, Any]

    @classmethod
    def setUpClass(cls) -> None:
        payload = {
            "labels": [names for names, _ in LABEL_CASES],
            "texts": [case[:3] for case in TEXT_CASES],
            "ids": [identities for identities, _ in ID_CASES],
            "app": APP_ID,
        }
        proc = subprocess.run(
            [
                "node",
                "--input-type=module",
                "-e",
                NODE % json.dumps(ADMIT.as_uri()),
                json.dumps(payload),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        cls.answer = json.loads(proc.stdout)

    def test_the_constants_are_admissions(self) -> None:
        self.assertEqual(self.answer["identity"], ve.LANES_APP_IDENTITY)
        self.assertEqual(self.answer["defaults"], list(ve.OWN_AGENT_DEFAULT_IDENTITIES))
        self.assertEqual(self.answer["sizes"], list(ve.OWN_AGENT_SIZES))
        self.assertEqual(self.answer["marker"], ve.SPLIT_CHILD_MARKER)

    def test_both_read_the_same_source_labels(self) -> None:
        for (names, expected), js in zip(
            LABEL_CASES, self.answer["labels"], strict=True
        ):
            with self.subTest(names):
                self.assertEqual(js, expected, "admission")
                self.assertEqual(ve.one_source_label(names), expected, "the gate")

    def test_both_read_the_same_own_agent_text(self) -> None:
        for (author, editor, listed, expected), js in zip(
            TEXT_CASES, self.answer["texts"], strict=True
        ):
            issue = {
                "author": author,
                "editor": editor,
                "lastEditedAt": EDITED if editor else None,
            }
            with self.subTest(author=author, editor=editor, listed=listed):
                self.assertEqual(js, expected, "admission")
                self.assertEqual(
                    ve.own_agent_text(issue, frozenset(listed)), expected, "the gate"
                )

    def test_both_resolve_the_same_identities(self) -> None:
        for (identities, expected), js in zip(
            ID_CASES, self.answer["ids"], strict=True
        ):
            with self.subTest(identities):
                self.assertEqual(js, expected, "admission")
                got = ve.own_agent_ids({"identities": identities}, APP_ID)
                self.assertEqual(sorted(got), expected, "the gate")

    def test_both_take_the_same_newest_setter_of_the_size_field(self) -> None:
        tables = {
            "the App set it": ([field_event(APP)], True),
            "a listed human set it": ([field_event(HUMAN)], True),
            "an outsider set it": ([field_event(OUTSIDER)], False),
            "another bot set it": ([field_event(OTHER_BOT)], False),
            "an outsider changed the App's value": (
                [field_event(APP), field_event(OUTSIDER, "IssueFieldChangedEvent")],
                False,
            ),
            "a human changed an outsider's value": (
                [field_event(OUTSIDER), field_event(HUMAN, "IssueFieldChangedEvent")],
                True,
            ),
            "the newest event removed it": (
                [field_event(APP), field_event(HUMAN, "IssueFieldRemovedEvent")],
                False,
            ),
            "the setter has no id": ([field_event(None)], False),
            "another field's setter": ([field_event(APP, field=OTHER_FIELD)], False),
            "another field set after it": (
                [field_event(OUTSIDER), field_event(APP, field=OTHER_FIELD)],
                False,
            ),
            "no events": ([], False),
        }
        source = RESOLVE_CONFIG.read_text(encoding="utf-8")
        fold = source[
            source.index("function eventsFrom(nodes) {") : source.index(
                "// Open issues per issuesByStatus page."
            )
        ].replace("export async function", "async function")
        script = (
            f"{fold}\n"
            " const { tables, field, humans, app } = JSON.parse(process.argv[1]);"
            " const out = tables.map((nodes) => {"
            "   const setter = settersOf(eventsFrom(nodes))[String(field)];"
            "   return humans.includes(setter) || setter === app;"
            " });"
            " console.log(JSON.stringify(out));"
        )
        payload = {
            "tables": [events for events, _ in tables.values()],
            "field": SIZE_FIELD,
            "humans": [HUMAN_ID],
            "app": APP_ID,
        }
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script, json.dumps(payload)],
            capture_output=True,
            text=True,
            check=True,
        )
        size = {"id": SIZE_FIELD, "options": {str(SMALL): "small"}}
        values = [{"issue_field_id": SIZE_FIELD, "single_select_option": {"id": SMALL}}]
        for (why, (events, expected)), js in zip(
            tables.items(), json.loads(proc.stdout), strict=True
        ):
            with self.subTest(why):
                self.assertEqual(js, expected, "admission")
                counted = ve.counted_size(
                    values, events, size, lambda a: a in {HUMAN_ID, APP_ID}
                )
                self.assertEqual(counted == "small", expected, "the gate")

    def test_the_gate_folds_the_whitespace_javascript_does(self) -> None:
        script = (
            "const found = [];"
            " for (let c = 0; c < 0x10000; c += 1) {"
            "   if (/\\s/.test(String.fromCharCode(c))) found.push(c);"
            " }"
            " console.log(JSON.stringify(found));"
        )
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertEqual(sorted(map(ord, ve.JS_SPACE)), json.loads(proc.stdout))

    def test_the_repositorys_own_list_never_names_github_actions(self) -> None:
        rules = json.loads(
            (
                ADMIT.parents[2] / "actions/resolve-config/admission-rules.json"
            ).read_text()
        )
        self.assertNotIn(ACTIONS_ID, rules["own-agents"]["identities"])


if __name__ == "__main__":
    unittest.main()

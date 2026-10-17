# test-scope: .github/actions/resolve-config/ratification.mjs
# test-scope: .github/actions/check-trusted-trigger/check-trusted-trigger.mjs
"""The owner's ratification rule agrees across languages: resolve-issue's
start (`.github/actions/resolve-config/ratification.mjs`, and the start check
`checkRatifiedAppLabel` in check-trusted-trigger.mjs, run here under node) and
the pr-merge lane's gate (`babysit_merge_policy.find_ratification` and
`ratified`).

`findRatification`: each case is one comments list; both sides must pick the
same ratifying comment, or none: the marker on a line of its own, a listed
human's id, no App, never edited. `checkRatifiedAppLabel`: each case adds the
denied ids and the issue's last body edit and title change; both sides must
agree whether the issue stands ratified.

Under CI (the `CI` variable set) a missing node fails instead of skipping.
"""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys
import unittest
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy

ROOT = pathlib.Path(__file__).resolve().parents[6]
RULE = ROOT / ".github/actions/resolve-config/ratification.mjs"
START = ROOT / ".github/actions/check-trusted-trigger/check-trusted-trigger.mjs"
START_NODE = """
import { evaluateTrigger } from %s;
const { cases, humans, app } = JSON.parse(process.argv[1]);
const list = {
  ids: new Set([...humans, app]),
  humans: new Set(humans),
  logins: new Map([["lanes[bot]", app]]),
};
const out = [];
for (const { comments, issue, denied } of cases) {
  const github = async (method, path) => {
    if (method === "GET" && path.includes("/issues/41/comments")) return comments;
    if (method === "POST" && path === "/graphql") return { data: { repository: { issue } } };
    throw new Error(`unexpected ${method} ${path}`);
  };
  try {
    const result = await evaluateTrigger({
      eventName: "issues",
      event: { action: "labeled", label: { name: "agent-ready" }, issue: { number: 41 }, sender: { id: app } },
      repository: "owner/repo",
      list,
      deniedIds: new Set(denied),
      triggeringActor: "lanes[bot]",
      lanesAppId: app,
      requirePr: "false",
      requireKind: "human",
      ratifiedAppLabel: "agent-ready",
      github,
    });
    out.push(result.proceed === "true");
  } catch (error) {
    if (!error.reason) throw error;
    out.push(false);
  }
}
console.log(JSON.stringify(out));
"""
NODE = """
import { findRatification } from %s;
const { cases, ratifiers } = JSON.parse(process.argv[1]);
const set = new Set(ratifiers);
console.log(JSON.stringify(cases.map((comments) => findRatification(comments, set)?.id ?? null)));
"""
MARKER = (
    "<!-- admission: admitted when unblocked, owner batch ratification 2026-10-16 -->"
)
OWNER, OTHER = 153232337, 99
AT = "2026-10-16T12:00:00Z"


def comment(cid: int = 1, **changes: Any) -> dict[str, Any]:
    return {
        "id": cid,
        "body": MARKER,
        "user": {"id": OWNER},
        "performed_via_github_app": None,
        "created_at": AT,
        "updated_at": AT,
    } | changes


def without(key: str) -> dict[str, Any]:
    base = comment()
    del base[key]
    return base


BODIES = [
    MARKER,
    f"text\n{MARKER}\nmore",
    f"text\r\n{MARKER}\r\nmore",
    f"text\r{MARKER}",
    f"text {MARKER} more",
    f"text\x85{MARKER}",
    f" {MARKER}",
    f"{MARKER} ",
    f"> {MARKER}",
    MARKER.replace("2026-10-16", "2026-1-16"),
    MARKER.replace("2026", "٢٠٢٦"),
    MARKER.replace("admitted", "Admitted"),
    "",
    None,
]
CASES: list[list[dict[str, Any]]] = [
    *([comment(body=body)] for body in BODIES),
    [without("body")],
    [comment(user={"id": OTHER})],
    [comment(user={"id": str(OWNER)})],
    [comment(user=None)],
    [without("user")],
    [comment(performed_via_github_app={"id": 1})],
    [comment(performed_via_github_app=False)],
    [comment(performed_via_github_app=0)],
    [without("performed_via_github_app")],
    [comment(updated_at="2026-10-16T12:05:00Z")],
    [comment(updated_at=None)],
    [comment(created_at=None, updated_at=None)],
    [without("updated_at")],
    [comment(1, body="hi"), comment(2), comment(3)],
    [comment(1, user={"id": OTHER}), comment(2, updated_at="x"), comment(3)],
    [],
]


APP = 337595936
LATER = "2026-10-16T13:00:00Z"


def issue(edited: Any = None, *renamed: Any) -> dict[str, Any]:
    return {
        "lastEditedAt": edited,
        "timelineItems": {"nodes": [{"createdAt": at} for at in renamed]},
    }


START_CASES: list[dict[str, Any]] = [
    {"comments": comments, "issue": node, "denied": denied}
    for comments, node, denied in (
        ([comment()], issue(), []),
        ([comment()], issue(), [OWNER]),
        ([comment()], issue(), [OTHER]),
        ([], issue(), []),
        ([comment()], issue("2026-10-16T11:00:00Z", "2026-10-16T10:00:00Z"), []),
        ([comment()], issue(AT), []),
        ([comment()], issue("2026-10-16T12:00:01Z"), []),
        ([comment()], issue(None, "2026-10-16T12:00:01Z"), []),
        ([comment()], issue("2026-10-16T12:00:00.500Z"), []),
        ([comment()], issue("2026-10-16T14:00:00+02:00"), []),
        ([comment()], issue("2026-10-16T11:00:00-02:00"), []),
        ([comment()], issue("not a time"), []),
        ([comment()], issue(12345), []),
        ([comment()], issue(None, None), []),
        ([comment()], {"lastEditedAt": None}, []),
        ([comment()], None, []),
        ([comment()], [], []),
        ([comment(), comment(2, created_at=LATER, updated_at=LATER)],
         issue("2026-10-16T12:30:00Z"), []),
        ([comment(2, created_at=LATER, updated_at=LATER), comment()],
         issue("2026-10-16T12:30:00Z"), []),
        ([comment(), comment(2, created_at=LATER, updated_at=LATER)],
         issue("2026-10-16T13:30:00Z"), []),
        ([comment(created_at="garbage", updated_at="garbage")], issue(), []),
        ([comment(created_at="garbage", updated_at="garbage")], issue(AT), []),
        ([comment(1, user={"id": OTHER}), comment(2, created_at=LATER, updated_at=LATER)],
         issue("2026-10-16T12:30:00Z"), []),
    )
]  # fmt: skip


def run_node(script: str, payload: dict[str, Any]) -> Any:
    proc = subprocess.run(
        ["node", "--input-type=module", "-e", script, json.dumps(payload)],
        capture_output=True,
        text=True,
        check=True,
    )
    # The start check logs each ratifying comment; the answer is the last line.
    return json.loads(proc.stdout.strip().splitlines()[-1])


def node_picks(cases: list[Any], ratifiers: list[int]) -> list[Any]:
    script = NODE % json.dumps(RULE.as_uri())
    return run_node(script, {"cases": cases, "ratifiers": ratifiers})


class TheRatificationRuleAgrees(unittest.TestCase):
    def setUp(self) -> None:
        if shutil.which("node"):
            return
        if os.environ.get("CI"):
            self.fail("node is not installed, and CI must run this sync test")
        self.skipTest("node is not installed")

    def test_the_start_check_and_the_gate_agree(self) -> None:
        script = START_NODE % json.dumps(START.as_uri())
        started = run_node(
            script, {"cases": START_CASES, "humans": [OWNER], "app": APP}
        )
        for case, expected in zip(START_CASES, started, strict=True):
            with self.subTest(case=case):
                self.assertIs(
                    policy.ratified(
                        case["comments"],
                        frozenset({OWNER}),
                        frozenset(case["denied"]),
                        case["issue"],
                    ),
                    expected,
                )
        self.assertGreater(started.count(True), 4)
        self.assertGreater(started.count(False), 8)

    def test_both_sides_pick_the_same_comment(self) -> None:
        picked = node_picks(CASES, [OWNER])
        for case, expected in zip(CASES, picked, strict=True):
            with self.subTest(case=case):
                found = policy.find_ratification(case, frozenset({OWNER}))
                self.assertEqual(found.get("id") if found else None, expected)

    def test_the_cases_cover_both_outcomes(self) -> None:
        picked = node_picks(CASES, [OWNER])
        self.assertGreater(picked.count(None), 10)
        self.assertGreater(len(picked) - picked.count(None), 4)


class AMissingNode(unittest.TestCase):
    def outcome(self, env: dict[str, str]) -> unittest.TestResult:
        from unittest import mock

        result = unittest.TestResult()
        with (
            mock.patch.object(shutil, "which", return_value=None),
            mock.patch.dict(os.environ, env, clear=True),
        ):
            TheRatificationRuleAgrees("test_the_start_check_and_the_gate_agree").run(
                result
            )
        return result

    def test_fails_under_ci_and_skips_elsewhere(self) -> None:
        under_ci = self.outcome({"CI": "true"})
        self.assertEqual((len(under_ci.failures), len(under_ci.skipped)), (1, 0))
        local = self.outcome({})
        self.assertEqual((len(local.failures), len(local.skipped)), (0, 1))


if __name__ == "__main__":
    unittest.main()

# test-scope: .github/scripts/pr-merge/merge-holds.mjs
"""The native auto-merge holds (`.github/scripts/pr-merge/merge-holds.mjs`,
run here under node) cover the merge gate's cost paths and manifests, so a
lane pull request native auto-merge merges cannot skip them. The gate's other
cost reasons (Pulumi project files, workflow and pipeline lines) are not
mirrored; workflows and the repository's pipeline config are hold paths
already.

- The cost paths: the same globs as `babysit_risk.COST_PATHS`, and the same
  paths matched (`glob_match` folds case and covers what sits under a glob).
- The manifests: every path `babysit_risk.is_manifest_path` takes is a hold
  path (`pathHold`).
- The cost decision: `costDecision` accepts the same comments as
  `babysit_merge_policy.cost_decision`, with the owner a trusted person in
  place of an admin.
"""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy
import babysit_risk as risk

MODULE = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/pr-merge/merge-holds.mjs"
)
NODE = """
import { COST_PATHS, costHold, pathHold } from %s;
const paths = JSON.parse(process.argv[1]);
console.log(JSON.stringify({
  costPaths: COST_PATHS,
  cost: paths.map((path) => costHold([path], null) !== null),
  held: paths.map((path) => pathHold([path], []) !== null),
}));
"""
PATHS = [
    "plugins/multi-agent/reference/defaults.yaml",
    "Plugins/Multi-Agent/Reference/Defaults.YAML",
    "plugins/multi-agent/reference/defaults.yml",
    "Pulumi.yaml",
    "infra/Pulumi.yaml",
    "infra/pulumi.PROD.yaml",
    "infra/Pulumi.md",
    "main.tf",
    ".infra/net/main.TF",
    "a.tf/inside.txt",
    ".tf",
    "infra/.tf",
    "x/.tfvars",
    ".bicep",
    "a/.bicepparam",
    "infra/.x.tf",
    "infra/.terraform/x.tf",
    "vars.tfvars",
    "deploy/main.bicep",
    "deploy/main.bicepparam",
    "deploy/main.bicep.md",
    "docs/a.md",
    ".claude-plugin/marketplace.json",
    "plugins/foo/.claude-plugin/plugin.json",
    "plugins/foo/.claude-plugin/other.json",
]


def module(paths: list[str]) -> dict[str, Any]:
    script = NODE % json.dumps(MODULE.as_uri())
    proc = subprocess.run(
        ["node", "--input-type=module", "-e", script, json.dumps(paths)],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheNativeHoldsCoverTheGate(unittest.TestCase):
    def test_the_cost_paths_are_the_same(self) -> None:
        answer = module(PATHS)
        self.assertEqual(answer["costPaths"], list(risk.COST_PATHS))
        for path, held in zip(PATHS, answer["cost"], strict=True):
            with self.subTest(path):
                self.assertEqual(
                    held, any(risk.glob_match(g, path) for g in risk.COST_PATHS)
                )
        self.assertIn(True, answer["cost"])
        self.assertIn(False, answer["cost"])

    def test_every_manifest_the_gate_reads_is_a_hold_path(self) -> None:
        answer = module(PATHS)
        manifests = [p for p in PATHS if risk.is_manifest_path(p)]
        self.assertEqual(
            manifests,
            [
                ".claude-plugin/marketplace.json",
                "plugins/foo/.claude-plugin/plugin.json",
            ],
        )
        for path, held in zip(PATHS, answer["held"], strict=True):
            if path in manifests:
                with self.subTest(path):
                    self.assertTrue(held)


REPO = "o/r"
PR = {"number": 7, "created_at": "2026-01-02T00:00:00Z"}
ISSUE = 5
OWNER = {"login": "owner", "id": 1, "type": "User"}
OTHER = {"login": "other", "id": 2, "type": "User"}
DECISION = "**Decision recorded.** Cost: approved"


def _comment(target: int, **fields: Any) -> dict[str, Any]:
    return {
        "issue_url": f"https://api.github.com/repos/{REPO}/issues/{target}",
        "user": OWNER,
        "performed_via_github_app": None,
        "body": DECISION,
        "created_at": "2026-01-03T00:00:00Z",
        "node_id": "N",
        "edited": None,
    } | fields


def _link(target: int, kind: str = "pull", repo: str = REPO) -> str:
    return f"https://github.com/{repo}/{kind}/{target}#issuecomment-11"


# Each case: the body, then the comment its link names.
DECISIONS = {
    "on the pull request": (_link(7), _comment(7)),
    "on the closing issue after the pull request": (
        _link(ISSUE, "issues"),
        _comment(ISSUE),
    ),
    "on the closing issue before the pull request": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, created_at="2026-01-01T00:00:00Z"),
    ),
    "on another issue": (_link(9, "issues"), _comment(9)),
    "in another repository": (_link(7, repo="x/r"), _comment(7)),
    "inside an HTML comment": (f"<!-- {_link(7)} -->", _comment(7)),
    "inside an unclosed HTML comment": (f"<!-- {_link(7)}", _comment(7)),
    "a comment on another issue": (_link(7), _comment(9)),
    "by a bot": (_link(7), _comment(7, user=OWNER | {"type": "Bot"})),
    "through an App": (_link(7), _comment(7, performed_via_github_app={"id": 1})),
    "by someone else": (_link(7), _comment(7, user=OTHER)),
    "edited": (_link(7), _comment(7, edited="2026-01-04T00:00:00Z")),
    "another decision": (_link(7), _comment(7, body="**Decision recorded.** Ship")),
    "indented": (_link(7), _comment(7, body=f"  {DECISION}")),
}
NODE_DECISION = """
import { costDecision } from %s;
const [body, comment, issue] = JSON.parse(process.argv[1]);
const github = async (method, path, data) => {
  if (method === "GET") return comment;
  if (data.variables.number !== undefined) {
    return { data: { repository: { pullRequest: { createdAt: "2026-01-02T00:00:00Z",
      closingIssuesReferences: { totalCount: 1, nodes: [{ number: issue, repository: { nameWithOwner: "o/r" } }] } } } } };
  }
  return { data: { node: { lastEditedAt: comment.edited } } };
};
console.log(JSON.stringify(await costDecision(github, "o/r", 7, body, new Set([1]))));
"""


def js_decision(body: str, comment: dict[str, Any]) -> str | None:
    script = NODE_DECISION % json.dumps(MODULE.as_uri())
    proc = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            script,
            json.dumps([body, comment, ISSUE]),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


def py_decision(body: str, comment: dict[str, Any]) -> str | None:
    def graphql(_query: str, _what: str, **_vars: Any) -> dict[str, Any]:
        return {"node": {"lastEditedAt": comment["edited"]}}

    with (
        mock.patch.object(policy, "_get", return_value=(200, comment)),
        mock.patch.object(policy, "_graphql", graphql),
    ):
        return policy.cost_decision(
            REPO,
            PR | {"body": body},
            ISSUE,
            permission=lambda login: "admin" if login == OWNER["login"] else "write",
            agent_identity=None,
        )


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheCostDecisionIsTheGates(unittest.TestCase):
    def test_both_accept_the_same_comments(self) -> None:
        answers = {}
        for case, (body, comment) in DECISIONS.items():
            with self.subTest(case):
                answers[case] = py_decision(body, comment)
                self.assertEqual(js_decision(body, comment), answers[case])
        self.assertIsNotNone(answers["on the pull request"])
        self.assertIsNone(answers["edited"])


if __name__ == "__main__":
    unittest.main()

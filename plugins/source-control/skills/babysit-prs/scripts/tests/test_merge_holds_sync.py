# test-scope: .github/scripts/pr-merge/merge-holds.mjs
"""The native auto-merge holds (`.github/scripts/pr-merge/merge-holds.mjs`,
run here under node) cover the merge gate's HIGH floor, cost paths and
manifest review, so a lane pull request native auto-merge merges cannot skip
them. The gate's other cost reasons (Pulumi project files, workflow and
pipeline lines) are not mirrored: the lanes App's token cannot push a
workflow file, and the repository's pipeline config is a hold path.

- The floor: every `babysit_risk.HIGH_FLOOR` glob is a hold path glob
  (`HOLD_PATH_FLOOR`).
- The cost paths: the same globs as `babysit_risk.COST_PATHS`, and the same
  paths matched (`glob_match` folds case and covers what sits under a glob).
- The manifests: `manifestChanges` finds what `babysit_risk._manifest_changes`
  finds for each change, so ci-status holds what the gate's manifest review
  holds and passes what it passes.
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
import { COST_PATHS, HOLD_PATH_FLOOR, costHold } from %s;
const paths = JSON.parse(process.argv[1]);
console.log(JSON.stringify({
  costPaths: COST_PATHS,
  floor: HOLD_PATH_FLOOR,
  cost: paths.map((path) => costHold([path], null) !== null),
}));
"""
NODE_MANIFEST = """
import { manifestChanges } from %s;
console.log(JSON.stringify(JSON.parse(process.argv[1]).map(manifestChanges)));
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

    def test_the_floor_covers_the_gate_s(self) -> None:
        floor = module([])["floor"]
        self.assertTrue(set(risk.HIGH_FLOOR) <= set(floor), floor)

    def test_the_manifest_review_is_the_gate_s(self) -> None:
        js = manifest_changes([change for _, change, _ in MANIFEST_CASES])
        for (name, change, holds), found in zip(MANIFEST_CASES, js, strict=True):
            with self.subTest(name):
                self.assertEqual(found, py_manifest_changes(change))
                self.assertEqual(bool(found), holds)


PLUGIN = "plugins/foo/.claude-plugin/plugin.json"
MARKET = ".claude-plugin/marketplace.json"
PLUGIN_BASE = (
    '{"name": "foo", "version": "1.0.0",'
    ' "userConfig": {"guard_enabled": {"type": "boolean", "default": true}}}'
)
MARKET_BASE = (
    '{"name": "m", "plugins": [{"name": "foo", "source": "./plugins/foo",'
    ' "category": "dev"}]}'
)


def _key(text: str) -> str:
    return PLUGIN_BASE.replace('"name": "foo",', f'"name": "foo", {text},')


def _case(
    name: str,
    after: str | None,
    holds: bool,
    *,
    path: str = PLUGIN,
    before: str | None = PLUGIN_BASE,
    status: str = "modified",
    previous: str | None = None,
) -> tuple[str, dict[str, Any], bool]:
    return (
        name,
        {"path": path, "previous": previous, "status": status, "contents": [before, after]},
        holds,
    )


# The classes #9280 set the gate's manifest review to hold, then changes it
# lets merge: a userConfig default (#9483), a version, a description, a
# marketplace category.
MANIFEST_CASES = [
    _case("hooks", _key('"hooks": "./h.json"'), True),
    _case("mcpServers", _key('"mcpServers": {}'), True),
    _case("lspServers", _key('"lspServers": {}'), True),
    _case("monitors", _key('"monitors": []'), True),
    _case("experimental.monitors", _key('"experimental": {"monitors": []}'), True),
    _case("experimental.monitors removed", PLUGIN_BASE, True, before=_key('"experimental": {"monitors": []}')),
    _case("hooks reordered", _key('"hooks": {"b": 1, "a": [1, 2]}'), False, before=_key('"hooks": {"a": [1, 2], "b": 1}')),
    _case("hooks 1 to 1.0", _key('"hooks": {"t": 1.0}'), True, before=_key('"hooks": {"t": 1}')),
    _case("hooks false to 0", _key('"hooks": 0'), True, before=_key('"hooks": false')),
    _case(
        "a plugin added",
        MARKET_BASE.replace("]}", ', {"name": "bar", "source": "./plugins/bar"}]}'),
        True,
        path=MARKET,
        before=MARKET_BASE,
    ),
    _case("a plugin removed", '{"name": "m", "plugins": []}', True, path=MARKET, before=MARKET_BASE),
    _case("a plugin renamed", MARKET_BASE.replace('"name": "foo"', '"name": "fob"'), True, path=MARKET, before=MARKET_BASE),
    _case(
        "a plugin source changed",
        MARKET_BASE.replace("./plugins/foo", "https://example.com/foo.git"),
        True,
        path=MARKET,
        before=MARKET_BASE,
    ),
    _case("the marketplace name changed", MARKET_BASE.replace('"name": "m"', '"name": "n"'), True, path=MARKET, before=MARKET_BASE),
    _case("plugins not a list", '{"name": "m", "plugins": {}}', True, path=MARKET, before=MARKET_BASE),
    _case(
        "two entries of one name",
        MARKET_BASE.replace("]}", ', {"name": "foo", "source": "./plugins/foo"}]}'),
        True,
        path=MARKET,
        before=MARKET_BASE,
    ),
    _case("removed", None, True, status="removed"),
    _case("renamed", PLUGIN_BASE, True, status="renamed", previous="plugins/foo/plugin.json"),
    _case("copied", PLUGIN_BASE, True, status="copied", previous="plugins/bar/.claude-plugin/plugin.json"),
    _case("an unreadable head", None, True),
    _case("a parse error", "{", True),
    _case("not an object", "[]", True),
    _case("a duplicate key", _key('"name": "x"'), True),
    _case("a nested duplicate key", _key('"hooks": {"a": 1, "a": 2}'), True),
    _case("an added plugin.json", PLUGIN_BASE, False, before=None, status="added"),
    _case("an added plugin.json with hooks", _key('"hooks": {}'), True, before=None, status="added"),
    _case("a userConfig default (#9483)", PLUGIN_BASE.replace('"default": true', '"default": false'), False),
    _case("a version", PLUGIN_BASE.replace("1.0.0", "1.1.0"), False),
    _case("a marketplace category", MARKET_BASE.replace('"dev"', '"tools"'), False, path=MARKET, before=MARKET_BASE),
    _case(
        "a marketplace metadata key",
        MARKET_BASE.replace('"name": "m",', '"name": "m", "metadata": {"pluginRoot": "x"},'),
        False,
        path=MARKET,
        before=MARKET_BASE,
    ),
]


def manifest_changes(changes: list[dict[str, Any]]) -> list[list[str]]:
    script = NODE_MANIFEST % json.dumps(MODULE.as_uri())
    proc = subprocess.run(
        ["node", "--input-type=module", "-e", script, json.dumps(changes)],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


def py_manifest_changes(change: dict[str, Any]) -> list[str]:
    status = change["status"]
    two_sided = status in ("modified", "changed", "renamed", "copied")
    before, after = change["contents"]
    changed = risk.ChangedFile(
        path=change["path"],
        previous_path=change["previous"],
        status=status,
        additions=1,
        deletions=1,
        has_patch=True,
        mode="100644",
        previous_mode="100644" if two_sided else None,
        contents=(None if status == "added" else before, after),
    )
    return risk._manifest_changes(risk._check_file(changed), changed)


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

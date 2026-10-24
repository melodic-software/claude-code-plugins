# test-scope: .github/scripts/pr-merge/merge-holds.mjs
"""The native auto-merge holds (`.github/scripts/pr-merge/merge-holds.mjs`,
run here under node) cover the merge gate's HIGH floor, cost paths and
manifest review, so a lane pull request native auto-merge merges cannot skip
them. The gate's other cost reasons (Pulumi project files, workflow and
pipeline lines) are not mirrored: the lanes App's token never carries the
`workflows` permission (request-lane-token checks the grant is contents,
pull-requests, issues and at most actions), so no lanes App push changes a
workflow file. That covers lanes App pushes only: another identity with
write access can still push a workflow change after auto-merge is armed.
The repository's pipeline config is a hold path.

- The floor: every `babysit_risk.HIGH_FLOOR` glob is a hold path glob
  (`HOLD_PATH_FLOOR`), and `pathHold` holds the paths `glob_match` matches
  over that floor, case variants included.
- The cost paths: the same globs as `babysit_risk.COST_PATHS`, and the same
  paths matched (`glob_match` folds case and covers what sits under a glob).
- The manifests: `manifestChanges` finds what `babysit_risk._manifest_changes`
  finds for each change, so ci-status holds what the gate's manifest review
  holds and passes what it passes.
- The cost decision: `costDecision` accepts the same comments as
  `babysit_merge_policy.cost_decision`, with the owner a trusted person in
  place of an admin, a linked-issue comment counting only when it names the
  pull request as `#<number>` (`namesPull`, `names_pull`), and both carry it
  to the same heads: the decided head, or a later one with the same net
  change against the base branch (`decidedHead`, `sameNetChange`).
"""

from __future__ import annotations

import json
import pathlib
import re
import shutil
import subprocess
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy
import babysit_risk as risk

ROOT = pathlib.Path(__file__).resolve().parents[6]
MODULE = ROOT / ".github/scripts/pr-merge/merge-holds.mjs"
# The floor actions' entry points: every module they load is code main runs
# with their verdict, so the floor holds it too.
FLOOR_ENTRIES = (
    ".github/actions/check-trusted-trigger/check-trusted-trigger.mjs",
    ".github/actions/resolve-config/resolve-config.mjs",
)
IMPORT = re.compile(r"""(?:from|import)\s*\(?\s*["'](\.{1,2}/[^"']+)["']""")


def import_closure(entries: tuple[str, ...]) -> list[str]:
    seen: set[str] = set()
    todo = [ROOT / entry for entry in entries]
    while todo:
        file = todo.pop().resolve()
        name = file.relative_to(ROOT).as_posix()
        if name in seen:
            continue
        seen.add(name)
        for spec in IMPORT.findall(file.read_text(encoding="utf-8")):
            todo.append(file.parent / spec)
    return sorted(seen)
NODE = """
import { COST_PATHS, HOLD_PATH_FLOOR, costHold, pathHold } from %s;
const paths = JSON.parse(process.argv[1]);
console.log(JSON.stringify({
  costPaths: COST_PATHS,
  floor: HOLD_PATH_FLOOR,
  cost: paths.map((path) => costHold([path], null) !== null),
  held: paths.map((path) => pathHold([path], []) !== null),
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
FLOOR_PATHS = [
    ".github/actions/resolve-config/resolve.mjs",
    ".github/actions/Resolve-Config/resolve.mjs",
    ".github/CODEOWNERS",
    ".github/codeowners",
    "CODEOWNERS",
    "docs/CodeOwners",
    ".gitmodules",
    "vendor/.GitModules",
    ".github/standards/trusted-actors/trusted-actors.json",
    ".github/Standards/trusted-actors/trusted-actors.json",
    ".github/actions/check-trusted-trigger/action.yml",
    ".github/actions/Check-Trusted-Trigger/action.yml",
    "Docs/Conventions/PR-Pipeline.yaml",
    ".github/actions/other/action.yml",
    ".github/workflows/x.yml",
    "docs/CODEOWNERS.md",
    "plugins/foo/.claude-plugin/plugin.json",
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
        answer = module(FLOOR_PATHS)
        self.assertTrue(set(risk.HIGH_FLOOR) <= set(answer["floor"]), answer["floor"])
        for path, held in zip(FLOOR_PATHS, answer["held"], strict=True):
            with self.subTest(path):
                self.assertEqual(
                    held, any(risk.glob_match(g, path) for g in answer["floor"])
                )
        self.assertIn(True, answer["held"])
        self.assertIn(False, answer["held"])

    def test_the_floor_holds_what_its_actions_load(self) -> None:
        files = import_closure(FLOOR_ENTRIES)
        self.assertIn(".github/actions/check-kill-switch/check-kill-switch.mjs", files)
        answer = module(files)
        for path, held in zip(files, answer["held"], strict=True):
            with self.subTest(path):
                self.assertTrue(held)
                self.assertTrue(any(risk.glob_match(g, path) for g in risk.HIGH_FLOOR))

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
    _case("an integer past int_max_str_digits", _key('"size": ' + "1" * 4301), True),
    _case("hooks true to null", _key('"hooks": null'), True, before=_key('"hooks": true')),
    _case("hooks true to false", _key('"hooks": false'), True, before=_key('"hooks": true')),
    _case(
        "hooks 20-digit integer, last digit",
        _key('"hooks": {"t": 12345678901234567891}'),
        True,
        before=_key('"hooks": {"t": 12345678901234567890}'),
    ),
    _case("hooks -0.0 to 0.0", _key('"hooks": {"t": 0.0}'), True, before=_key('"hooks": {"t": -0.0}')),
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
HEAD = "0123456789abcdef0123456789abcdef01234567"
BASE = "89abcdef0123456789abcdef0123456789abcdef"
OLD = "fedcba9876543210fedcba9876543210fedcba98"
PR = {
    "number": 7,
    "created_at": "2026-01-02T00:00:00Z",
    "head": {"sha": HEAD, "ref": "b", "repo": {"full_name": REPO}},
    "base": {"sha": BASE, "ref": "main"},
}
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
    "on the closing issue after the pull request, naming it": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for #7."),
    ),
    "on the closing issue, naming it in parentheses": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} (#7)"),
    ),
    "on the closing issue, naming no pull request": (
        _link(ISSUE, "issues"),
        _comment(ISSUE),
    ),
    "on the closing issue, naming another pull request": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for #70."),
    ),
    "on the closing issue, naming another repository's": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for x/r#7."),
    ),
    "on the closing issue, naming it only as an entity": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for &#7;"),
    ),
    "on the closing issue, naming it only after a #": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for ##7."),
    ),
    "on the closing issue, naming it, by someone else": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for #7.", user=OTHER),
    ),
    "on the closing issue before the pull request": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for #7.", created_at="2026-01-01T00:00:00Z"),
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
def _marker(sha: str, at: str = "2026-01-02T12:00:00Z", **fields: Any) -> dict[str, Any]:
    body = f"<!-- claude-lane-hold lane=claude-review sha={sha} criteria=cost -->\nHeld."
    user = {"login": "github-actions[bot]", "type": "Bot"}
    return {"user": user, "node_id": "M", "created_at": at, "body": body} | fields


# The head reads: the pull request's comments (a cost hold marker at the head
# before the decision by default) and a compare per head.
# The marker's edit read answers `marker_edited`, or fails when it is "fail".
DEFAULT_HEADS = {"markers": [_marker(HEAD)], "compares": {}, "marker_edited": None}
TF = {"filename": "a.tf", "status": "modified", "patch": "@@ -1 +1 @@\n-a\n+b"}
MORE = {"filename": "b.sh", "status": "added", "patch": "+c"}
# Each case: the heads world for a decision on the pull request (_link(7)).
CARRIES = {
    "a marker at the head": DEFAULT_HEADS,
    "a base merge since the decided head": {
        "markers": [_marker(OLD)],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF]}},
    },
    "a commit of its own since": {
        "markers": [_marker(OLD)],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF, MORE]}},
    },
    "a rename since": {
        "markers": [_marker(OLD)],
        "compares": {
            OLD: {"files": [TF]},
            HEAD: {"files": [TF | {"status": "renamed", "previous_filename": "z.tf"}]},
        },
    },
    "300 files": {
        "markers": [_marker(OLD)],
        "compares": {
            sha: {"files": [TF | {"filename": f"f{i}"} for i in range(300)]}
            for sha in (OLD, HEAD)
        },
    },
    "a file with no patch": {
        "markers": [_marker(OLD)],
        "compares": {sha: {"files": [{"filename": "a.png", "status": "added"}]} for sha in (OLD, HEAD)},
    },
    "an unreadable compare": {"markers": [_marker(OLD)], "compares": {OLD: {"files": [TF]}}},
    "the latest marker before it, not an older one at the head": {
        "markers": [_marker(HEAD, "2026-01-02T06:00:00Z"), _marker(OLD)],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF, MORE]}},
    },
    "a marker after it": {"markers": [_marker(HEAD, "2026-01-04T00:00:00Z")]},
    "a person's marker": {"markers": [_marker(HEAD, user={"type": "User"})]},
    "another bot's marker": {
        "markers": [_marker(HEAD, user={"login": "claude[bot]", "type": "Bot"})]
    },
    "no marker": {"markers": []},
    "an edited marker": {"marker_edited": "2026-01-02T13:00:00Z"},
    "an unreadable marker edit state": {"marker_edited": "fail"},
    "an edited marker after a base merge": {
        "markers": [_marker(OLD)],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF]}},
        "marker_edited": "2026-01-02T13:00:00Z",
    },
    "a filename listed twice": {
        "markers": [_marker(OLD)],
        "compares": {OLD: {"files": [TF, TF]}, HEAD: {"files": [TF, TF]}},
    },
    "a patchless pure rename": {
        "markers": [_marker(OLD)],
        "compares": {
            sha: {"files": [{"filename": "b", "status": "renamed", "previous_filename": "a"}]}
            for sha in (OLD, HEAD)
        },
    },
}
NODE_DECISION = """
import { costDecision } from %s;
const [body, comment, issue, heads] = JSON.parse(process.argv[1]);
const github = async (method, path, data) => {
  if (method === "GET" && path.includes("/compare/")) {
    const sha = path.split("...")[1];
    if (!(sha in heads.compares)) throw new Error("no such commit");
    return heads.compares[sha];
  }
  if (method === "GET" && path === "/repos/o/r/issues/7/comments?per_page=100&page=1") return heads.markers;
  if (method === "GET") return comment;
  if (data.variables.number !== undefined) {
    return { data: { repository: { pullRequest: { createdAt: "2026-01-02T00:00:00Z", baseRefName: "main",
      closingIssuesReferences: { totalCount: 1, nodes: [{ number: issue, repository: { nameWithOwner: "o/r" } }] } } } } };
  }
  if (data.variables.id === "M") {
    if (heads.marker_edited === "fail") throw new Error("unreadable");
    return { data: { node: { lastEditedAt: heads.marker_edited } } };
  }
  return { data: { node: { lastEditedAt: comment.edited } } };
};
console.log(JSON.stringify(await costDecision(github, "o/r", 7, body, new Set([1]), %s)));
"""


def js_decision(
    body: str, comment: dict[str, Any], heads: dict[str, Any] = DEFAULT_HEADS
) -> str | None:
    script = NODE_DECISION % (json.dumps(MODULE.as_uri()), json.dumps(HEAD))
    proc = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            script,
            json.dumps([body, comment, ISSUE, DEFAULT_HEADS | heads]),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


def py_decision(
    body: str, comment: dict[str, Any], heads: dict[str, Any] = DEFAULT_HEADS
) -> str | None:
    heads = DEFAULT_HEADS | heads

    def graphql(_query: str, what: str, **variables: Any) -> dict[str, Any]:
        if variables.get("id") == "M":
            if heads["marker_edited"] == "fail":
                raise policy.PolicyReadError(what)
            return {"node": {"lastEditedAt": heads["marker_edited"]}}
        return {"node": {"lastEditedAt": comment["edited"]}}

    def get(endpoint: str) -> tuple[int | None, Any]:
        if "/compare/" in endpoint:
            sha = endpoint.rsplit("...", 1)[1]
            return (200, heads["compares"][sha]) if sha in heads["compares"] else (404, None)
        return 200, comment

    def paginated(endpoint: str, _label: str) -> list[dict[str, Any]]:
        assert endpoint == "repos/o/r/issues/7/comments?per_page=100", endpoint
        return heads["markers"]

    with (
        mock.patch.object(policy, "_get", side_effect=get),
        mock.patch.object(policy, "_paginated", side_effect=paginated),
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
        self.assertIsNotNone(
            answers["on the closing issue after the pull request, naming it"]
        )
        self.assertIsNone(answers["on the closing issue, naming no pull request"])
        self.assertIsNone(answers["on the closing issue, naming it only as an entity"])
        self.assertIsNone(answers["on the closing issue, naming it only after a #"])
        self.assertIsNone(answers["edited"])

    def test_both_carry_a_decision_to_the_same_heads(self) -> None:
        answers = {}
        for case, heads in CARRIES.items():
            with self.subTest(case):
                answers[case] = py_decision(_link(7), _comment(7), heads)
                self.assertEqual(js_decision(_link(7), _comment(7), heads), answers[case])
        for case in (
            "a marker at the head",
            "a base merge since the decided head",
        ):
            self.assertEqual(answers[case], _link(7), case)
        for case in set(CARRIES) - {
            "a marker at the head",
            "a base merge since the decided head",
        }:
            self.assertIsNone(answers[case], case)


if __name__ == "__main__":
    unittest.main()

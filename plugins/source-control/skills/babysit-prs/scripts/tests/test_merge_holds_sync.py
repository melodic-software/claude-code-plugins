# test-scope: .github/scripts/pr-merge/merge-holds.mjs
"""The native auto-merge holds (`.github/scripts/pr-merge/merge-holds.mjs`,
run here under node) cover the merge gate's cost paths, so a lane pull
request native auto-merge merges cannot skip them. The gate's other cost
reasons (Pulumi project files, workflow and pipeline lines) are not mirrored:
the lanes App's token never carries the `workflows` permission
(request-lane-token checks the grant is contents, pull-requests, issues and
at most actions), so no lanes App push changes a workflow file. That covers
lanes App pushes only: another identity with write access can still push a
workflow change after auto-merge is armed.

- No floor: `babysit_risk.HIGH_FLOOR` is empty, and `pathHold` holds a path
  only for a configured glob, matched as `glob_match` matches it, case
  variants included.
- The cost paths: the same globs as `babysit_risk.COST_PATHS`, and the same
  paths matched (`glob_match` folds case and covers what sits under a glob).
- The cost decision: `costDecision` accepts the same comments as
  `babysit_merge_policy.cost_decision`, with the owner a trusted person in
  place of an admin, a linked-issue comment counting only when it names the
  pull request as `#<number>` (`namesPull`, `names_pull`), and both carry it
  to the same heads: the decided head, or a later one with the same net
  change against the base branch (`costMarker`, `sameNetChange`).
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

ROOT = pathlib.Path(__file__).resolve().parents[6]
MODULE = ROOT / ".github/scripts/pr-merge/merge-holds.mjs"
NODE = """
import { COST_PATHS, costHold, pathHold } from %s;
const [paths, globs] = JSON.parse(process.argv[1]);
console.log(JSON.stringify({
  costPaths: COST_PATHS,
  cost: paths.map((path) => costHold([path], null) !== null),
  held: paths.map((path) => pathHold([path], []) !== null),
  configured: paths.map((path) => pathHold([path], globs) !== null),
}));
"""
# A configured denied-paths list, for the presence case.
CONFIGURED = ["**/CODEOWNERS", ".github/actions/resolve-config/**"]
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
        ["node", "--input-type=module", "-e", script, json.dumps([paths, CONFIGURED])],
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

    def test_no_trusted_path_holds_on_either_side(self) -> None:
        answer = module(FLOOR_PATHS)
        self.assertEqual(risk.HIGH_FLOOR, ())
        self.assertNotIn(True, answer["held"])
        for path, held in zip(FLOOR_PATHS, answer["configured"], strict=True):
            with self.subTest(path):
                self.assertEqual(
                    held, any(risk.glob_match(g, path) for g in CONFIGURED)
                )
        self.assertIn(True, answer["configured"])
        self.assertIn(False, answer["configured"])


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


def _marker(
    sha: str, at: str = "2026-01-02T12:00:00Z", **fields: Any
) -> dict[str, Any]:
    body = (
        f"<!-- claude-lane-hold lane=claude-review sha={sha} criteria=cost -->\nHeld."
    )
    user = {"login": "github-actions[bot]", "type": "Bot"}
    return {"user": user, "node_id": "M", "created_at": at, "body": body} | fields


# The head reads: the pull request's comments (a cost hold marker at the head
# before the decision by default) and a compare per head.
# The marker's edit read answers `marker_edited`, or fails when it is "fail";
# the deleted-comment read lists the `deleted` times (or answers the timeline
# items given), or fails when it is "fail".
DEFAULT_HEADS = {
    "markers": [_marker(HEAD)],
    "compares": {},
    "marker_edited": None,
    "deleted": [],
}
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
        "compares": {
            sha: {"files": [{"filename": "a.png", "status": "added"}]}
            for sha in (OLD, HEAD)
        },
    },
    "an unreadable compare": {
        "markers": [_marker(OLD)],
        "compares": {OLD: {"files": [TF]}},
    },
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
    "a comment deleted since the marker": {"deleted": ["2026-01-02T13:00:00Z"]},
    "a comment deleted since the marker, after a base merge": {
        "markers": [_marker(OLD)],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF]}},
        "deleted": ["2026-01-02T13:00:00Z"],
    },
    "a comment deleted before the marker": {"deleted": ["2026-01-02T11:00:00Z"]},
    "an unreadable deleted-comment list": {"deleted": "fail"},
    "more deleted comments than listed": {
        "deleted": {
            "filteredCount": 2,
            "nodes": [{"createdAt": "2026-01-01T00:00:00Z"}],
        }
    },
    "a deleted-comment count that is not a number": {
        "deleted": {
            "filteredCount": True,
            "nodes": [{"createdAt": "2026-01-01T00:00:00Z"}],
        }
    },
    "a patchless pure rename": {
        "markers": [_marker(OLD)],
        "compares": {
            sha: {
                "files": [
                    {"filename": "b", "status": "renamed", "previous_filename": "a"}
                ]
            }
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
  if (data.query.includes("COMMENT_DELETED_EVENT")) {
    if (heads.deleted === "fail") throw new Error("unreadable");
    const items = Array.isArray(heads.deleted)
      ? { filteredCount: heads.deleted.length, nodes: heads.deleted.map((createdAt) => ({ createdAt })) }
      : heads.deleted;
    return { data: { repository: { pullRequest: { timelineItems: items } } } };
  }
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

    def graphql(query: str, what: str, **variables: Any) -> dict[str, Any]:
        if "COMMENT_DELETED_EVENT" in query:
            if heads["deleted"] == "fail":
                raise policy.PolicyReadError(what)
            deleted = heads["deleted"]
            items = (
                {
                    "filteredCount": len(deleted),
                    "nodes": [{"createdAt": t} for t in deleted],
                }
                if isinstance(deleted, list)
                else deleted
            )
            return {"repository": {"pullRequest": {"timelineItems": items}}}
        if variables.get("id") == "M":
            if heads["marker_edited"] == "fail":
                raise policy.PolicyReadError(what)
            return {"node": {"lastEditedAt": heads["marker_edited"]}}
        return {"node": {"lastEditedAt": comment["edited"]}}

    def get(endpoint: str) -> tuple[int | None, Any]:
        if "/compare/" in endpoint:
            sha = endpoint.rsplit("...", 1)[1]
            return (
                (200, heads["compares"][sha])
                if sha in heads["compares"]
                else (404, None)
            )
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
                self.assertEqual(
                    js_decision(_link(7), _comment(7), heads), answers[case]
                )
        carried = {
            "a marker at the head",
            "a base merge since the decided head",
            "a comment deleted before the marker",
        }
        for case in carried:
            self.assertEqual(answers[case], _link(7), case)
        for case in set(CARRIES) - carried:
            self.assertIsNone(answers[case], case)


if __name__ == "__main__":
    unittest.main()

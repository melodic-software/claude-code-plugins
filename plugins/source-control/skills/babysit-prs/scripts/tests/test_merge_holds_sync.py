# test-scope: .github/scripts/pr-merge/merge-holds.mjs .github/scripts/pr-merge/enable-auto-merge.mjs .github/workflows/pr-review-hosted.yml .github/workflows/pr-review-security-hosted.yml .github/workflows/pr-require-checks.yml
"""The native auto-merge holds (`.github/scripts/pr-merge/merge-holds.mjs`,
run here under node) cover the merge gate's cost paths, so a lane pull
request native auto-merge merges cannot skip them. The gate's other cost
reasons (Pulumi project files, workflow and pipeline lines) are not mirrored:
the lanes App's token never carries the `workflows` permission
(request-lane-token checks the grant is contents, pull-requests, issues and
at most actions), so no lanes App push changes a workflow file. That covers
lanes App pushes only: another identity with write access can still push a
workflow change after auto-merge is armed.

- The floor (owner decisions Q-FLOOR (B) and Q-ENFORCE (A)): `HOLD_PATH_FLOOR` is
  `babysit_risk.HIGH_FLOOR`, and `pathHold` holds, with no configured glob,
  exactly the paths `glob_match` matches over it, case variants included;
  a trusted path off the floor holds only for a configured glob. Every module
  the floor actions load is on it, and of babysit-prs/scripts/ exactly the
  Python that decides the holds. The review callers' `hold-paths` and
  ci-status's exempt-author `hold_patterns` each match every floor entry.
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

import ast
import fnmatch
import json
import pathlib
import re
import shlex
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
# The floor actions' entry points and the floored scripts that enforce the
# floor (owner decision Q-ENFORCE (A)): every module they load is code main
# runs with their verdict, so the floor holds it too.
FLOOR_ENTRIES = (
    ".github/actions/check-trusted-trigger/check-trusted-trigger.mjs",
    ".github/actions/resolve-config/resolve-config.mjs",
    ".github/scripts/pr-merge/merge-holds.mjs",
    ".github/scripts/pr-merge/enable-auto-merge.mjs",
    ".github/scripts/pr-merge/superseded.mjs",
    ".github/scripts/pr-merge/clear-escalations.mjs",
)
# A relative import, or a module-relative file a module reads at load
# (`new URL("./x.json", import.meta.url)`): data such as a routing table
# decides as much as the code that reads it.
IMPORT = re.compile(
    r"""(?:(?:from|import)\s*\(?|new\s+URL\()\s*["'](\.{1,2}/[^"']+)["']"""
)


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


# The Python that decides the holds: babysit_risk, and every script a floored
# JS module runs (enable-auto-merge.mjs's VERIFY_SCRIPT), with every module of
# babysit-prs/scripts/ they import.
SCRIPTS = pathlib.Path(risk.__file__).resolve().parent
PY_RUN = re.compile(r"""["'`][^"'`\s]*?(plugins/[^"'`\s]+\.py)["'`]""")


def python_closure(js_files: list[str]) -> list[str]:
    todo = [SCRIPTS / "babysit_risk.py"]
    floored = {g for g in risk.HIGH_FLOOR if g.endswith(".mjs")}
    for name in sorted(floored | set(js_files)):
        for path in PY_RUN.findall((ROOT / name).read_text(encoding="utf-8")):
            todo.append(ROOT / path)
    seen: set[str] = set()
    while todo:
        file = todo.pop()
        name = file.relative_to(ROOT).as_posix()
        if name in seen:
            continue
        seen.add(name)
        for node in ast.walk(ast.parse(file.read_text(encoding="utf-8"))):
            if isinstance(node, ast.Import):
                names = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom) and not node.level and node.module:
                names = [node.module]
            else:
                continue
            todo.extend(
                SCRIPTS / f"{n}.py" for n in names if (SCRIPTS / f"{n}.py").is_file()
            )
    return sorted(seen)


NODE = """
import { COST_PATHS, HOLD_PATH_FLOOR, costHold, pathHold } from %s;
const [paths, globs] = JSON.parse(process.argv[1]);
console.log(JSON.stringify({
  costPaths: COST_PATHS,
  floor: HOLD_PATH_FLOOR,
  cost: paths.map((path) => costHold([path], null) !== null),
  held: paths.map((path) => pathHold([path], []) !== null),
  configured: paths.map((path) => pathHold([path], globs) !== null),
}));
"""
# A configured denied-paths list, for the presence case.
CONFIGURED = ["Docs/Conventions/PR-Pipeline.yaml", ".github/workflows/**"]
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
    ".github/actions/request-lane-token/action.yml",
    ".github/actions/Request-Lane-Token/index.mjs",
    ".github/actions/check-kill-switch/check-kill-switch.mjs",
    ".github/actions/CHECK-KILL-SWITCH/action.yml",
    ".github/actions/log-api-budget/rate-guard.mjs",
    ".github/actions/log-api-budget/Rate-Guard.MJS",
    ".github/actions/log-api-budget/action.yml",
    ".github/actions/log-api-budget/rate-guard.test.mjs",
    ".github/actions/log-api-budget/rate-limits.json",
    ".github/actions/log-api-budget/Rate-Limits.JSON",
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

    def test_the_floor_is_the_same_on_both_sides(self) -> None:
        answer = module(FLOOR_PATHS)
        self.assertEqual(answer["floor"], list(risk.HIGH_FLOOR))
        self.assertEqual(len(risk.HIGH_FLOOR), 40)
        for path, held, configured in zip(
            FLOOR_PATHS, answer["held"], answer["configured"], strict=True
        ):
            with self.subTest(path):
                on_floor = any(risk.glob_match(g, path) for g in risk.HIGH_FLOOR)
                self.assertEqual(held, on_floor)
                self.assertEqual(
                    configured,
                    on_floor or any(risk.glob_match(g, path) for g in CONFIGURED),
                )
        self.assertIn(True, answer["held"])
        self.assertIn(False, answer["held"])
        self.assertIn(False, answer["configured"])
        self.assertNotEqual(answer["held"], answer["configured"])

    def test_the_floor_holds_what_its_actions_load(self) -> None:
        files = import_closure(FLOOR_ENTRIES)
        self.assertIn(".github/actions/check-kill-switch/check-kill-switch.mjs", files)
        self.assertIn(".github/actions/log-api-budget/rate-guard.mjs", files)
        # The rate-limit defaults rate-guard.mjs reads decide when the lanes
        # stop short of GitHub's limits, so they are held like the module.
        self.assertIn(".github/actions/log-api-budget/rate-limits.json", files)
        answer = module(files)
        for path, held in zip(files, answer["held"], strict=True):
            with self.subTest(path):
                self.assertTrue(held)
                self.assertTrue(any(risk.glob_match(g, path) for g in risk.HIGH_FLOOR))

    def test_the_floor_holds_the_python_that_decides_the_holds(self) -> None:
        files = python_closure(import_closure(FLOOR_ENTRIES))
        scripts = SCRIPTS.relative_to(ROOT).as_posix()
        self.assertIn(f"{scripts}/babysit_verify_evidence.py", files)
        self.assertIn(f"{scripts}/babysit_merge.py", files)
        answer = module(files)
        for path, held in zip(files, answer["held"], strict=True):
            with self.subTest(path):
                self.assertTrue(held)
                self.assertTrue(any(risk.glob_match(g, path) for g in risk.HIGH_FLOOR))
        # Nothing else of that directory: the floor tracks the closure.
        self.assertEqual(
            sorted(g for g in risk.HIGH_FLOOR if g.startswith(f"{scripts}/")), files
        )


def _hold_paths(workflow: str) -> list[str]:
    text = (ROOT / ".github/workflows" / workflow).read_text(encoding="utf-8")
    block = re.search(r"^      hold-paths: \|\n((?:        \S.*\n)+)", text, re.M)
    assert block, workflow
    return block[1].split()


def _hold_patterns() -> list[str]:
    text = (ROOT / ".github/workflows/pr-require-checks.yml").read_text(
        encoding="utf-8"
    )
    found = re.search(r"^ *hold_patterns=\((.*)\)$", text, re.M)
    assert found
    return shlex.split(found[1])


class TheScrutinyListsNameTheFloor(unittest.TestCase):
    """The review callers' `hold-paths` (prompt globs) and ci-status's
    exempt-author `hold_patterns` (bash patterns, `*` crossing `/`) each match
    every floor entry."""

    def test_each_list_covers_every_floor_entry(self) -> None:
        lists = {
            workflow: (_hold_paths(workflow), risk.glob_match)
            for workflow in ("pr-review-hosted.yml", "pr-review-security-hosted.yml")
        }
        lists["hold_patterns"] = (
            _hold_patterns(),
            lambda pattern, entry: fnmatch.fnmatchcase(entry, pattern),
        )
        for name, (patterns, match) in lists.items():
            self.assertTrue(patterns, name)
            for entry in risk.HIGH_FLOOR:
                with self.subTest(list=name, entry=entry):
                    self.assertTrue(any(match(p, entry) for p in patterns))


NODE_ACTORS = """
import { actorsWidened } from %s;
const cases = JSON.parse(process.argv[1]);
console.log(JSON.stringify(cases.map(([status, previous, contents]) => actorsWidened({ status, previous, contents }))));
"""
_KYLE = {"id": 1, "login": "kyle", "kind": "human"}
_BOT = {"id": 2, "login": "lanes[bot]", "kind": "bot"}


def _list(*actors: Any, version: Any = 1) -> str:
    return json.dumps({"version": version, "actors": list(actors)}, indent=2)


_BASE_LIST = _list(_KYLE, _BOT)
# Each case: status, renamed-from path, then [base text, head text] or None.
ACTOR_CASES = {
    "an entry added": ("modified", None, [_BASE_LIST, _list(_KYLE, _BOT, {"id": 3})]),
    "an entry's kind changed": ("modified", None, [_BASE_LIST, _list(_KYLE, _BOT | {"kind": "human"})]),
    "a removal beside an addition": ("modified", None, [_BASE_LIST, _list(_KYLE, {"id": 5})]),
    "an entry repeated": ("modified", None, [_BASE_LIST, _list(_KYLE, _BOT, _BOT)]),
    "another key changed": ("modified", None, [_BASE_LIST, _list(_KYLE, _BOT, version=2)]),
    "unparsable head": ("modified", None, [_BASE_LIST, "{"]),
    "a repeated key": ("modified", None, [_BASE_LIST, _BASE_LIST.replace('"version": 1', '"version": 1, "version": 1')]),
    "actors not a list": ("modified", None, [_BASE_LIST, '{"version": 1, "actors": {}}']),
    "an array at the root": ("modified", None, [_BASE_LIST, "[]"]),
    "contents unread": ("modified", None, None),
    "added": ("added", None, [None, _BASE_LIST]),
    "removed": ("removed", None, [_BASE_LIST, None]),
    "renamed": ("renamed", "a.json", [_BASE_LIST, _BASE_LIST]),
    "an entry removed": ("modified", None, [_BASE_LIST, _list(_KYLE)]),
    "every entry removed": ("modified", None, [_BASE_LIST, _list()]),
    "reformatted and reordered": ("modified", None, [_BASE_LIST, json.dumps({"actors": [_BOT, _KYLE], "version": 1})]),
    "keys reordered in an entry": ("modified", None, [_BASE_LIST, _list({"kind": "human", "login": "kyle", "id": 1}, _BOT)]),
}  # fmt: skip


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheWideningHoldIsTheGates(unittest.TestCase):
    def test_both_hold_the_same_trusted_actor_list_changes(self) -> None:
        cases = list(ACTOR_CASES.values())
        script = NODE_ACTORS % json.dumps(MODULE.as_uri())
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script, json.dumps(cases)],
            capture_output=True,
            text=True,
            check=True,
        )
        answers = json.loads(proc.stdout)
        for (name, (status, previous, contents)), js in zip(
            ACTOR_CASES.items(), answers, strict=True
        ):
            changed = risk.ChangedFile(
                path=risk.TRUSTED_ACTORS_PATH,
                previous_path=previous,
                status=status,
                additions=1,
                deletions=1,
                has_patch=True,
                mode="100644",
                previous_mode=None if status == "added" else "100644",
                contents=None if contents is None else tuple(contents),
            )
            py = risk._actors_widened(risk._check_file(changed), changed)
            with self.subTest(name):
                self.assertEqual(js is None, py is None, (js, py))
        held = [js is not None for js in answers]
        self.assertIn(True, held)
        self.assertIn(False, held)


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

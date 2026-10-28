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

- The floor (owner decisions Q-FLOOR (B), Q-ENFORCE (A) and Q26 option B):
  `HOLD_PATH_CLASSES` is `babysit_risk.FLOOR_CLASSES`, glob and class alike,
  `HOLD_PATH_FLOOR` is `babysit_risk.HIGH_FLOOR` (its `trust` and `gate`
  globs), and `pathHold` holds, with no configured glob, exactly the paths
  `glob_match` matches over that, case variants included; an `enforcement`
  path is the gate's (`review-path:`), and a trusted path off the floor holds
  only for a configured glob. Every module the floor actions load is on the
  floor, every pr-merge script as `gate`, and of babysit-prs/scripts/ exactly
  the Python that decides the holds, `babysit_merge*` as `gate`. The review
  callers' `hold-paths` and ci-status's exempt-author `hold_patterns` each
  match every floor entry, whatever its class.
- The cost paths: the same globs as `babysit_risk.COST_PATHS`, and the same
  paths matched (`glob_match` folds case and covers what sits under a glob).
- The cost decision: `costDecision` accepts the same comments as
  `babysit_merge_policy.cost_decision`, with the owner a trusted person in
  place of an admin, a linked-issue comment counting only when it names the
  pull request as `#<number>` (`namesPull`, `names_pull`), and both carry it
  to the same heads: the decided head, read from the review lanes' check-run
  notices (`noticedHead`, `_noticed_head`) while the head branch's push
  history shows a run of every review lane on each head pushed since it
  (`unranHead`, `unran_head`), or a later one with the same net change
  against the base branch (`sameNetChange`).
- The high-path lift: `pathLifters` over `fromRest` and
  `babysit_merge_policy.path_lifters` name the same trusted approvers of the
  head on the same REST review lists.
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
from datetime import datetime, timedelta
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
    # A floor entry for a script not in this tree yet runs nothing here.
    floored = {g for g in risk.FLOOR if g.endswith(".mjs") and (ROOT / g).is_file()}
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
import { COST_PATHS, HOLD_PATH_CLASSES, HOLD_PATH_FLOOR, REVIEW_FLOOR, costHold, pathHold } from %s;
const [paths, globs] = JSON.parse(process.argv[1]);
console.log(JSON.stringify({
  costPaths: COST_PATHS,
  classes: HOLD_PATH_CLASSES,
  floor: HOLD_PATH_FLOOR,
  review: REVIEW_FLOOR,
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
    ".github/scripts/pr-merge/rotation.mjs",
    ".github/scripts/pr-merge/rotation.test.mjs",
    "plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py",
    "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py",
    ".github/scripts/work-resolve-issue/report-outcome.mjs",
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
        self.assertEqual(answer["classes"], [list(row) for row in risk.FLOOR_CLASSES])
        self.assertEqual(answer["floor"], list(risk.HIGH_FLOOR))
        self.assertEqual(answer["review"], list(risk.REVIEW_FLOOR))
        self.assertEqual(len(risk.FLOOR_CLASSES), 55)
        self.assertEqual(len(risk.REVIEW_FLOOR), 25)
        self.assertEqual(
            {kind for _, kind in risk.FLOOR_CLASSES}, {"trust", "gate", "enforcement"}
        )
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
                self.assertTrue(any(risk.glob_match(g, path) for g in risk.FLOOR))
                self.assertEqual(
                    held, any(risk.glob_match(g, path) for g in risk.HIGH_FLOOR)
                )

    def test_every_pr_merge_script_is_gate_code(self) -> None:
        # Owner decision Q26 option B: the merge gate's own code stays a
        # person's, every script pr-merge.yml runs from that directory.
        folder = ROOT / ".github/scripts/pr-merge"
        scripts = sorted(
            f".github/scripts/pr-merge/{f.name}"
            for f in folder.iterdir()
            if f.is_file()
            and f.suffix in {".mjs", ".bash"}
            and ".test." not in f.name
            and ".fixture." not in f.name
        )
        self.assertIn(".github/scripts/pr-merge/who.mjs", scripts)
        gate = {g for g, kind in risk.FLOOR_CLASSES if kind == "gate"}
        for path in scripts:
            with self.subTest(path):
                self.assertIn(path, gate)

    def test_the_floor_holds_the_python_that_decides_the_holds(self) -> None:
        files = python_closure(import_closure(FLOOR_ENTRIES))
        scripts = SCRIPTS.relative_to(ROOT).as_posix()
        self.assertIn(f"{scripts}/babysit_verify_evidence.py", files)
        self.assertIn(f"{scripts}/babysit_merge.py", files)
        answer = module(files)
        for path, held in zip(files, answer["held"], strict=True):
            with self.subTest(path):
                self.assertTrue(any(risk.glob_match(g, path) for g in risk.FLOOR))
                # babysit_merge*, and the scorer and binder that compute the
                # security review's clear condition, are the gate's own code,
                # a person's; the rest is enforcement, which a clean security
                # review clears.
                name = pathlib.PurePosixPath(path).name
                gate = name.startswith("babysit_merge") or name in {
                    "babysit_risk.py",
                    "babysit_review_evidence.py",
                }
                self.assertEqual(held, gate)
                self.assertEqual(path in risk.REVIEW_FLOOR, not gate)
        # Nothing else of that directory: the floor tracks the closure.
        self.assertEqual(
            sorted(g for g in risk.FLOOR if g.startswith(f"{scripts}/")), files
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
            for entry in risk.FLOOR:
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


NODE_LIFTERS = """
import { fromRest, pathLifters } from %s;
const [cases, humans, head] = JSON.parse(process.argv[1]);
console.log(JSON.stringify(cases.map((rows) => pathLifters(rows.map(fromRest), new Set(humans), head))));
"""
_HEAD = "a" * 40


def _review(
    state: str,
    user: int = 1,
    sha: str = _HEAD,
    at: str = "2026-10-26T16:41:00Z",
    kind: str = "User",
) -> dict[str, Any]:
    return {
        "user": {"id": user, "login": f"u{user}", "type": kind},
        "state": state,
        "commit_id": sha,
        "submitted_at": at,
    }


_LATER = "2026-10-26T17:20:00Z"
# REST review lists, kyle (id 1) and id 3 trusted, at head _HEAD.
LIFTER_CASES = {
    "approved at the head": [_review("APPROVED")],
    "approved at another head": [_review("APPROVED", sha="b" * 40)],
    "an untrusted approver": [_review("APPROVED", user=2)],
    "a bot account": [_review("APPROVED", kind="Bot")],
    "changes requested since": [_review("APPROVED"), _review("CHANGES_REQUESTED", at=_LATER)],
    "dismissed since": [_review("APPROVED"), _review("DISMISSED", at=_LATER)],
    "approved after changes requested": [_review("CHANGES_REQUESTED"), _review("APPROVED", at=_LATER)],
    "a comment after the approval": [_review("APPROVED"), _review("COMMENTED", at=_LATER)],
    "two people, one blocks": [_review("APPROVED", user=3), _review("APPROVED"), _review("CHANGES_REQUESTED", at=_LATER)],
    "no reviews": [],
}  # fmt: skip


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheHighPathLiftIsTheGates(unittest.TestCase):
    def test_both_name_the_same_lifters(self) -> None:
        script = NODE_LIFTERS % json.dumps(MODULE.as_uri())
        proc = subprocess.run(
            [
                "node",
                "--input-type=module",
                "-e",
                script,
                json.dumps([list(LIFTER_CASES.values()), [1, 3], _HEAD]),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        answers = json.loads(proc.stdout)
        for (name, rows), js in zip(LIFTER_CASES.items(), answers, strict=True):
            with self.subTest(name):
                self.assertEqual(policy.path_lifters(rows, {1, 3}, _HEAD), js)
        self.assertIn([], answers)
        self.assertIn(["u1"], answers)
        self.assertIn(["u3"], answers)


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
CHECKS = dict(policy.REVIEW_LANES)


def _run(
    sha: str,
    at: str = "2026-01-02T12:00:00Z",
    *,
    criteria: str = "cost",
    lane: str = "pr-review-hosted.yml",
    job: str | None = None,
    notice: str | None = None,
    created: str = "2026-01-02T11:00:00Z",
    repo: str | None = "o/r",
) -> dict[str, Any]:
    """A review lane's run on `sha` with its head in `repo`, started at
    `created`, whose status job (or `job`) finished at `at` with a hold notice
    naming `notice`."""
    message = f"claude-lane-hold lane=claude-review sha={notice or sha} criteria={criteria} label=needs-human"
    return {
        "lane": lane,
        "sha": sha,
        "at": at,
        "job": job or CHECKS[lane],
        "created": created,
        "repo": repo,
        "notes": [{"annotation_level": "notice", "message": message}],
    }


def _push(after: str, timestamp: str) -> dict[str, Any]:
    return {"after": after, "timestamp": timestamp, "activity_type": "push"}


# The head reads: the review lanes' runs on the head branch (a cost notice at
# the head before the decision by default), their jobs and annotations, a
# compare per head (a run's head answers {"files": [TF]} unless `compares`
# names it), and the head branch's push history, newest first (`activity`,
# by default each run's head pushed five minutes before its first status job
# finished).
DEFAULT_HEADS = {"runs": [_run(HEAD)], "compares": {}}
TF = {"filename": "a.tf", "status": "modified", "patch": "@@ -1 +1 @@\n-a\n+b"}
MORE = {"filename": "b.sh", "status": "added", "patch": "+c"}
LATE = "2026-01-02T18:00:00Z"
NEW = "1" * 40
# A base commit a merge of the base names as its second parent.
MAIN = "5" * 40
# The decided head OLD, then NEW pushed before the decision; HEAD carries
# OLD's net change.
SINCE = [_push(NEW, "2026-01-02T13:00:00Z"), _push(OLD, "2026-01-02T10:00:00Z")]
SAME = {OLD: {"files": [TF]}, HEAD: {"files": [TF]}}


def _plain(lane: str) -> dict[str, Any]:
    """A run on NEW before the decision whose status job noticed no cost."""
    return _run(
        NEW,
        "2026-01-02T13:10:00Z",
        criteria="trust-gate",
        lane=lane,
        created="2026-01-02T13:05:00Z",
    )


# Each case: the heads world for a decision on the pull request (_link(7)).
CARRIES = {
    "a notice at the head": DEFAULT_HEADS,
    "a base merge since the decided head": {
        "runs": [_run(OLD)],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF]}},
    },
    "a commit of its own since": {
        "runs": [_run(OLD)],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF, MORE]}},
    },
    "a rename since": {
        "runs": [_run(OLD)],
        "compares": {
            OLD: {"files": [TF]},
            HEAD: {"files": [TF | {"status": "renamed", "previous_filename": "z.tf"}]},
        },
    },
    "300 files": {
        "runs": [_run(OLD)],
        "compares": {
            sha: {"files": [TF | {"filename": f"f{i}"} for i in range(300)]}
            for sha in (OLD, HEAD)
        },
    },
    "a file with no patch": {
        "runs": [_run(OLD)],
        "compares": {
            sha: {"files": [{"filename": "a.png", "status": "added"}]}
            for sha in (OLD, HEAD)
        },
    },
    "an unreadable compare": {"runs": [_run(OLD)], "compares": {OLD: {"files": [TF]}}},
    "the latest notice before it, not an older one at the head": {
        "runs": [
            _run(HEAD, "2026-01-02T06:00:00Z", created="2026-01-02T05:00:00Z"),
            _run(OLD),
        ],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF, MORE]}},
    },
    "a notice from the security lane": {
        "runs": [_run(HEAD, lane="pr-review-security-hosted.yml")]
    },
    "a job done after it": {"runs": [_run(HEAD, "2026-01-04T00:00:00Z")]},
    "a run started after it": {
        "runs": [_run(HEAD, LATE, created="2026-01-03T01:00:00Z")]
    },
    "a job other than the status job": {
        "runs": [_run(HEAD, job="pr-review / review-key")]
    },
    "a notice naming another head than its run's": {"runs": [_run(OLD, notice=HEAD)]},
    "a notice without cost": {"runs": [_run(HEAD, criteria="trust-gate")]},
    "a run whose head is in another repository": {"runs": [_run(HEAD, repo="f/r")]},
    "a run with no head repository": {"runs": [_run(HEAD, repo=None)]},
    "two heads at the newest time": {
        "runs": [_run(HEAD), _run(OLD, lane="pr-review-security-hosted.yml")]
    },
    "no notice": {"runs": []},
    "a run on a head that changes a review-lane workflow": {
        "compares": {
            HEAD: {"files": [{"filename": ".github/workflows/pr-review-hosted.yml"}]}
        }
    },
    "a run on a head whose compare has no file list": {
        "compares": {HEAD: {"status": "diverged"}}
    },
    "a filename listed twice": {
        "runs": [_run(OLD)],
        "compares": {OLD: {"files": [TF, TF]}, HEAD: {"files": [TF, TF]}},
    },
    "a newer head pushed before it with a run of every lane": {
        "runs": [
            _run(OLD),
            _plain("pr-review-hosted.yml"),
            _plain("pr-review-security-hosted.yml"),
        ],
        "compares": SAME,
        "activity": SINCE,
    },
    "a newer head pushed before it whose lane runs were deleted": {
        "runs": [_run(OLD)],
        "compares": SAME,
        "activity": SINCE,
    },
    "a newer head pushed before it with one lane's run deleted": {
        "runs": [_run(OLD), _plain("pr-review-security-hosted.yml")],
        "compares": SAME,
        "activity": SINCE,
    },
    "a history with no push of the decided head": {
        "runs": [
            _run(OLD),
            _plain("pr-review-hosted.yml"),
            _plain("pr-review-security-hosted.yml"),
        ],
        "compares": SAME,
        "activity": SINCE[:1],
    },
    "a non-merge commit since with the same net change": {
        "runs": [_run(OLD)],
        "compares": {
            OLD: {"files": [TF]},
            HEAD: {
                "files": [TF],
                "commits": [
                    {"sha": OLD, "parents": [{"sha": MAIN}]},
                    {"sha": HEAD, "parents": [{"sha": OLD}]},
                ],
                "total_commits": 2,
            },
        },
    },
    "a merge of a branch other than the base": {
        "runs": [_run(OLD)],
        "compares": {
            OLD: {"files": [TF]},
            HEAD: {
                "files": [TF],
                "commits": [
                    {"sha": OLD, "parents": [{"sha": MAIN}]},
                    {"sha": NEW, "parents": [{"sha": MAIN}]},
                    {"sha": HEAD, "parents": [{"sha": OLD}, {"sha": NEW}]},
                ],
                "total_commits": 3,
            },
        },
    },
    "a merge that also edits a file": {
        "runs": [_run(OLD)],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF, MORE]}},
    },
    "a force push that rewrote the decided head": {
        "runs": [_run(OLD)],
        "compares": {
            OLD: {"files": [TF]},
            HEAD: {
                "files": [TF],
                "commits": [
                    {"sha": NEW, "parents": [{"sha": MAIN}]},
                    {"sha": HEAD, "parents": [{"sha": NEW}, {"sha": MAIN}]},
                ],
                "total_commits": 2,
            },
        },
    },
    "a history longer than the compare lists": {
        "runs": [_run(OLD)],
        "compares": {
            OLD: {"files": [TF]},
            HEAD: {
                "files": [TF],
                "commits": [
                    {"sha": OLD, "parents": [{"sha": MAIN}]},
                    {"sha": HEAD, "parents": [{"sha": OLD}, {"sha": MAIN}]},
                ],
                "total_commits": 251,
            },
        },
    },
    "a patchless pure rename": {
        "runs": [_run(OLD)],
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


def _history(sha: str, answer: Any) -> Any:
    """`answer` (a compare of base...sha) with the commits a history of base
    merges lists unless it names its own: OLD alone for OLD, OLD and a merge
    HEAD of the base for HEAD, the head alone for any other."""
    if not isinstance(answer, dict) or "commits" in answer or "files" not in answer:
        return answer
    commits = [{"sha": OLD if sha == HEAD else sha, "parents": [{"sha": MAIN}]}]
    if sha == HEAD:
        commits.append({"sha": HEAD, "parents": [{"sha": OLD}, {"sha": MAIN}]})
    return answer | {"commits": commits, "total_commits": len(commits)}


def _answers(heads: dict[str, Any]) -> dict[str, Any]:
    answers = {r["sha"]: {"files": [TF]} for r in heads["runs"]} | heads["compares"]
    return {sha: _history(sha, answer) for sha, answer in answers.items()}


def _activity(heads: dict[str, Any]) -> list[dict[str, Any]]:
    if "activity" in heads:
        return heads["activity"]
    first: dict[str, str] = {}
    for r in heads["runs"]:
        first[r["sha"]] = min(first.get(r["sha"], r["at"]), r["at"])
    pushes = [
        _push(
            sha,
            (datetime.fromisoformat(at) - timedelta(minutes=5)).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            ),
        )
        for sha, at in first.items()
    ]
    return sorted(pushes, key=lambda m: m["timestamp"], reverse=True)


NODE_DECISION = """
import { costDecision } from %s;
const [body, comment, issue, heads, answers, activity] = JSON.parse(process.argv[1]);
const github = async (method, path, data) => {
  if (method === "GET" && path === "/repos/o/r/activity?ref=refs%%2Fheads%%2Fb&direction=desc&per_page=100") return activity;
  if (method === "GET" && path.endsWith("...main")) return { status: path.includes(`/compare/${"5".repeat(40)}...`) ? "identical" : "diverged" };
  if (method === "GET" && path.includes("/compare/")) {
    const sha = path.split("...")[1];
    if (!(sha in answers)) throw new Error("no such commit");
    return answers[sha];
  }
  const runs = /\\/actions\\/workflows\\/([a-z-]+\\.yml)\\/runs\\?event=pull_request&branch=b&per_page=100&page=1$/.exec(path);
  if (method === "GET" && runs) {
    return { workflow_runs: heads.runs.flatMap((r, i) => (r.lane === runs[1] ? [{ id: i + 1, head_sha: r.sha, created_at: r.created, head_repository: r.repo && { full_name: r.repo } }] : [])) };
  }
  const jobs = /\\/actions\\/runs\\/([0-9]+)\\/jobs\\?filter=all&per_page=100&page=1$/.exec(path);
  if (method === "GET" && jobs) {
    const r = heads.runs[Number(jobs[1]) - 1];
    return { jobs: [{ id: Number(jobs[1]), name: r.job, completed_at: r.at }] };
  }
  const notes = /\\/check-runs\\/([0-9]+)\\/annotations\\?per_page=100&page=1$/.exec(path);
  if (method === "GET" && notes) return heads.runs[Number(notes[1]) - 1].notes;
  if (method === "GET") return comment;
  if (data.variables.number !== undefined) {
    return { data: { repository: { pullRequest: { createdAt: "2026-01-02T00:00:00Z", baseRefName: "main", headRefName: "b",
      closingIssuesReferences: { totalCount: 1, nodes: [{ number: issue, repository: { nameWithOwner: "o/r" } }] } } } } };
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
            json.dumps(
                [
                    body,
                    comment,
                    ISSUE,
                    DEFAULT_HEADS | heads,
                    _answers(DEFAULT_HEADS | heads),
                    _activity(DEFAULT_HEADS | heads),
                ]
            ),
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
    answers = _answers(heads)

    def graphql(query: str, what: str, **variables: Any) -> dict[str, Any]:
        return {"node": {"lastEditedAt": comment["edited"]}}

    def get(endpoint: str, env: Any = None) -> tuple[int | None, Any]:
        if "/compare/" in endpoint and not re.fullmatch(
            r"[0-9a-f]{40}", endpoint.rsplit("...", 1)[1]
        ):
            parent = endpoint.split("/compare/", 1)[1].split("...")[0]
            return 200, {"status": "identical" if parent == MAIN else "diverged"}
        if "/compare/" in endpoint:
            sha = endpoint.rsplit("...", 1)[1]
            return (200, answers[sha]) if sha in answers else (404, None)
        if "/activity?" in endpoint:
            assert endpoint == (
                "repos/o/r/activity?ref=refs%2Fheads%2Fb&direction=desc&per_page=100"
            ), endpoint
            return 200, _activity(heads)
        return 200, comment

    def paginated(
        endpoint: str, _label: str, items_key: str | None = None, env: Any = None
    ) -> list[dict[str, Any]]:
        if "/actions/workflows/" in endpoint:
            lane = endpoint.split("/actions/workflows/", 1)[1].split("/", 1)[0]
            assert endpoint.endswith(
                "/runs?event=pull_request&branch=b&per_page=100"
            ), endpoint
            return [
                {
                    "id": i + 1,
                    "head_sha": r["sha"],
                    "created_at": r["created"],
                    "head_repository": r["repo"] and {"full_name": r["repo"]},
                }
                for i, r in enumerate(heads["runs"])
                if r["lane"] == lane
            ]
        if "/jobs?" in endpoint:
            n = int(endpoint.split("/actions/runs/", 1)[1].split("/", 1)[0])
            r = heads["runs"][n - 1]
            return [{"id": n, "name": r["job"], "completed_at": r["at"]}]
        n = int(endpoint.split("/check-runs/", 1)[1].split("/", 1)[0])
        return heads["runs"][n - 1]["notes"]

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
            "a notice at the head",
            "a base merge since the decided head",
            "a notice from the security lane",
            "a newer head pushed before it with a run of every lane",
        }
        for case in carried:
            self.assertEqual(answers[case], _link(7), case)
        for case in set(CARRIES) - carried:
            self.assertIsNone(answers[case], case)


NODE_CARRY = """
import { baseMergeCarry, fromRest, liftsOf } from %s;
const [lifts, carries, from] = JSON.parse(process.argv[1]);
console.log(JSON.stringify([
  lifts.map((reviews) => liftsOf(reviews.map(fromRest), new Set([1, 3])).map(({ login, sha }) => [login, sha])),
  carries.map(([then, now, keep, inBase, changed]) => baseMergeCarry(then, now, from, keep, { inBase: new Set(inBase), baseChanged: new Set(changed) })),
]));
"""
_OLD = "c" * 40
_BASE_SHA = "5" * 40
_HELD = ".github/actions/resolve-config/live-config.test.mjs"
_PATCH = {"filename": _HELD, "status": "modified", "patch": "@@ -1 +1 @@\n-a\n+b"}
_DOC = {"filename": "docs/a.md", "status": "modified", "patch": "+x"}
_LIFTED = "2026-10-27T23:26:14Z"


def _moved(*commits: tuple[str, list[str]]) -> dict[str, Any]:
    return {
        "commits": [
            {"sha": sha, "parents": [{"sha": p} for p in parents]}
            for sha, parents in commits
        ],
        "total_commits": len(commits),
    }


_THEN = {"files": [_PATCH], **_moved((_OLD, [_BASE_SHA]))}
_MERGED = _moved((_OLD, [_BASE_SHA]), (_HEAD, [_OLD, _BASE_SHA]))
_OTHER = "e" * 40
_REWRITTEN = "f" * 40
# REST reviews: whose approval stands, as (login, sha).
LIFT_CASES = {
    "an approval of an earlier head": [_review("APPROVED", sha=_OLD, at=_LIFTED)],
    "an approval by an untrusted account": [_review("APPROVED", 2, _OLD, _LIFTED)],
    "an approval by a bot": [_review("APPROVED", 1, _OLD, _LIFTED, "Bot")],
    "an approval then changes requested on another head": [
        _review("APPROVED", sha=_OLD, at=_LIFTED),
        _review("CHANGES_REQUESTED", sha="d" * 40, at="2026-10-27T23:40:00Z"),
    ],
    "a dismissed approval": [_review("DISMISSED", sha=_OLD, at=_LIFTED)],
    "an approval dismissed after a newer approval": [
        _review("APPROVED", sha=_OLD, at=_LIFTED),
        _review("DISMISSED", sha=_HEAD, at="2026-10-27T23:40:00Z"),
    ],
    "a comment after an approval": [_review("APPROVED", sha=_OLD, at=_LIFTED), _review("COMMENTED", sha=_HEAD, at="2026-10-27T23:40:00Z")],
    "two people": [_review("APPROVED", 1, _OLD, _LIFTED), _review("APPROVED", 3, _HEAD, _LIFTED)],
}  # fmt: skip
_KEEP = [".github/actions/resolve-config/**"]
_IN_BASE = [_BASE_SHA]
# (then, now, keep, in_base, changed): whether the lift at _OLD carries to
# _HEAD, given the merged parents the base holds and the files it changed.
CARRY_CASES = {
    "a base merge": (_THEN, {"files": [_PATCH], **_MERGED}, _KEEP, _IN_BASE, []),
    "a base merge after which the base holds a hold path's change": (
        {"files": [_PATCH, _PATCH | {"filename": ".github/actions/resolve-config/b.mjs"}], **_moved((_OLD, [_BASE_SHA]))},
        {"files": [_PATCH], **_MERGED},
        _KEEP,
        _IN_BASE,
        [],
    ),
    "a conflict resolution outside the hold paths": (_THEN, {"files": [_PATCH, _DOC], **_MERGED}, _KEEP, _IN_BASE, []),
    "a file outside H's net change the base changed": (_THEN, {"files": [_PATCH, _DOC], **_MERGED}, _KEEP, _IN_BASE, [_DOC["filename"]]),
    "a merge of a parent the base does not hold": (_THEN, {"files": [_PATCH], **_moved((_OLD, [_BASE_SHA]), (_OTHER, [_BASE_SHA, _BASE_SHA]), (_HEAD, [_OLD, _OTHER]))}, _KEEP, _IN_BASE, []),
    "a merge read with no base answers": (_THEN, {"files": [_PATCH], **_MERGED}, _KEEP, [], []),
    "the same conflict resolution against the whole net change": (_THEN, {"files": [_PATCH, _DOC], **_MERGED}, None, _IN_BASE, []),
    "an evil merge": (_THEN, {"files": [_PATCH | {"patch": "+evil"}], **_MERGED}, _KEEP, _IN_BASE, []),
    "a merge that adds a hold path": (_THEN, {"files": [_PATCH, _PATCH | {"filename": ".github/actions/resolve-config/c.mjs"}], **_MERGED}, _KEEP, _IN_BASE, []),
    "a rename off a hold path": (_THEN, {"files": [_PATCH, _DOC | {"status": "renamed", "previous_filename": _HELD.replace("live", "old")}], **_MERGED}, _KEEP, _IN_BASE, []),
    "a non-merge commit": (_THEN, {"files": [_PATCH], **_moved((_OLD, [_BASE_SHA]), (_HEAD, [_OLD]))}, _KEEP, _IN_BASE, []),
    "a merge of another branch": (_THEN, {"files": [_PATCH], **_moved((_OLD, [_BASE_SHA]), (_OTHER, [_BASE_SHA]), (_HEAD, [_OLD, _OTHER]))}, _KEEP, _IN_BASE, []),
    "a force push": (_THEN, {"files": [_PATCH], **_moved((_REWRITTEN, [_BASE_SHA]), (_HEAD, [_REWRITTEN, _BASE_SHA]))}, _KEEP, _IN_BASE, []),
    "a cut commit list": (_THEN, {"files": [_PATCH], **_MERGED, "total_commits": 251}, _KEEP, _IN_BASE, []),
    "a hold-path file with no patch": (_THEN, {"files": [{"filename": _HELD, "status": "modified"}], **_MERGED}, _KEEP, _IN_BASE, []),
}  # fmt: skip


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheCarriedLiftIsTheGates(unittest.TestCase):
    def test_both_readers_carry_the_same_lifts(self) -> None:
        proc = subprocess.run(
            [
                "node",
                "--input-type=module",
                "-e",
                NODE_CARRY % json.dumps(MODULE.as_uri()),
                json.dumps(
                    [list(LIFT_CASES.values()), list(CARRY_CASES.values()), _OLD]
                ),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        lifts, carries = json.loads(proc.stdout)
        for (name, reviews), js in zip(LIFT_CASES.items(), lifts, strict=True):
            with self.subTest(name):
                self.assertEqual(
                    [list(x) for x in policy.lifts_of(reviews, {1, 3})], js
                )
        for (name, (then, now, keep, in_base, changed)), js in zip(
            CARRY_CASES.items(), carries, strict=True
        ):
            with self.subTest(name):
                self.assertEqual(
                    policy.base_merge_carry(
                        then, now, _OLD, keep, set(in_base), set(changed)
                    ),
                    js,
                )
        # The rule's answers: a trusted person's newest review approves a
        # commit (a dismissed approval never counts); it carries over merges of
        # base commits alone, within the hold paths' net change and no wider
        # than the base's.
        self.assertEqual(
            dict(zip(LIFT_CASES, lifts, strict=True)),
            dict.fromkeys(LIFT_CASES, [])
            | {
                "an approval of an earlier head": [["u1", _OLD]],
                "a comment after an approval": [["u1", _OLD]],
                "two people": [["u1", _OLD], ["u3", _HEAD]],
            },
        )
        self.assertEqual(
            {name for name, js in zip(CARRY_CASES, carries, strict=True) if js},
            {
                "a base merge",
                "a base merge after which the base holds a hold path's change",
                "a file outside H's net change the base changed",
            },
        )


if __name__ == "__main__":
    unittest.main()

# test-scope: .github/scripts/pr-verify/resolve-pr.mjs
"""The verifier's two shared rules agree across languages: the gate's
(`babysit_verify_evidence`, `babysit_classify`) and the resolver's
(`.github/scripts/pr-verify/resolve-pr.mjs`, run here under node).

- The dependency managers: the same logins, and the same users matched (a Bot
  account with one of them, never a User named like one).
- The FAIL-counting rule: for each run record, a FAIL counts from any run of
  verifier origin and a PASS only from a completed success. The resolver also
  needs a completed run for a FAIL, so a run still going never stops a new
  judgment (the README's "Verifier verdict"); that is the one difference.
- The `Refs:` rule: the one issue a pull request body's visible `Refs: #<n>`
  lines name (`babysit_merge_policy.refs_issue`, resolve-pr's `refsIssue`).

The run records are the gate suite's own forgeries and unfinished runs.
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

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_classify as classify
import babysit_merge_policy as merge_policy
import babysit_postmerge as postmerge
import babysit_verify_evidence as ve
import test_babysit_verify_evidence as gate

RESOLVER = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/pr-verify/resolve-pr.mjs"
)
NODE = """
import { DEPENDENCY_MANAGERS, countedBy, isDependencyManager } from %s;
const { users, runs, repo, onMain } = JSON.parse(process.argv[1]);
const counted = [];
for (const { run, verdict } of runs) {
  const github = async (method, path) => {
    if (path === `/repos/${repo}/actions/runs/1`) return run;
    const compare = /\\/compare\\/([^.]+)\\.\\.\\.main$/.exec(path);
    if (compare) return { status: onMain.includes(compare[1]) ? "ahead" : "diverged" };
    throw new Error(`unexpected ${method} ${path}`);
  };
  counted.push(await countedBy({ github, repository: repo, runId: 1, verdict, base: "main" }));
}
console.log(JSON.stringify({ managers: DEPENDENCY_MANAGERS, users: users.map(isDependencyManager), counted }));
"""
USERS = [
    {"login": login, "type": kind}
    for login in ("dependabot[bot]", "Renovate[bot]", "renovate-bot", "someone")
    for kind in ("Bot", "User")
] + [{"login": "dependabot"}, {}]
RUNS = {
    "a completed success": {},
    **gate.UnauthenticatedArtifactsAreIgnored.FORGERIES,
    **gate.AFailCountsWhateverTheRunConcluded.UNFINISHED,
}


def resolver(users: list[Any], runs: list[dict[str, Any]]) -> dict[str, Any]:
    script = NODE % json.dumps(RESOLVER.as_uri())
    payload = {
        "users": users,
        "runs": runs,
        "repo": gate.REPO,
        "onMain": [gate.MAIN_SHA],
    }
    proc = subprocess.run(
        ["node", "--input-type=module", "-e", script, json.dumps(payload)],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


def gate_counts(run: dict[str, Any], verdict: str) -> bool:
    fake = gate.FakeGitHub([], {1: run})
    with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
        state = ve.Reader(gate.REPO, "main")._run_state(1)
    return state == ve.COUNTED or (verdict == "fail" and state == ve.ORIGIN)


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheGateAndTheResolverAgree(unittest.TestCase):
    def test_the_dependency_managers_are_the_same(self) -> None:
        answer = resolver(USERS, [])
        self.assertEqual(set(answer["managers"]), classify.DEPENDENCY_MANAGER_LOGINS)
        for user, matched in zip(USERS, answer["users"], strict=True):
            with self.subTest(user):
                self.assertEqual(ve.dependency_bot(user), matched)
        self.assertIn(True, answer["users"])
        self.assertIn(False, answer["users"])

    def test_a_fail_and_a_pass_count_from_the_same_runs(self) -> None:
        cases = [
            (label, gate.run(1, **overrides), verdict)
            for label, overrides in RUNS.items()
            for verdict in ("fail", "pass")
        ]
        counted = resolver([], [{"run": r, "verdict": v} for _, r, v in cases])
        for (label, run, verdict), js in zip(cases, counted["counted"], strict=True):
            with self.subTest(label, verdict=verdict):
                completed = run["status"] == "completed"
                self.assertEqual(js, gate_counts(run, verdict) and completed)
        self.assertIn(True, counted["counted"])


REFS_BODIES = [
    None,
    "",
    "Refs: #5",
    "Refs:#5",
    "Refs: #5 \t",
    "Refs: #5\r\nRefs: #5",
    "Refs: #5\rRefs: #6",
    "Refs: #5\nRefs: #6",
    "refs: #5",
    "REFS: #5",
    " Refs: #5",
    "\tRefs: #5",
    "> Refs: #5",
    "Refs: #05",
    "Refs: #0",
    "Refs: #1234567890",
    "Refs: #5, #6",
    "Refs: o/r#5",
    "Refs: https://github.com/o/r/issues/5",
    "Refs #5",
    "<!-- Refs: #5 -->",
    "<!--\nRefs: #5\n-->\nRefs: #6",
    "<!-- unclosed\nRefs: #5",
    "```\nRefs: #5\n```",
    "```\nRefs: #5\n```\nRefs: #6",
    "   ```\nRefs: #5",
    "    ```\nRefs: #5",
    "~~~~\n~~~\nRefs: #5\n~~~~\nRefs: #6",
    "````\n```` x\nRefs: #5",
    "```\n~~~\nRefs: #5\n```\nRefs: #6",
    "Refs: #5\u2028Refs: #6",
    "Refs: #5\x0bRefs: #6",
    "Closes #4\nRefs: #5",
]
REFS_NODE = """
import { refsIssue } from %s;
console.log(JSON.stringify(JSON.parse(process.argv[1]).map(refsIssue)));
"""


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheGateAndTheResolverReadRefsAlike(unittest.TestCase):
    def test_every_body_names_the_same_issue(self) -> None:
        script = REFS_NODE % json.dumps(RESOLVER.as_uri())
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script, json.dumps(REFS_BODIES)],
            capture_output=True,
            text=True,
            check=True,
        )
        named = json.loads(proc.stdout)
        for body, js in zip(REFS_BODIES, named, strict=True):
            with self.subTest(body=body):
                self.assertEqual(merge_policy.refs_issue(body)[0], js)
        # Hand-read: the table holds both kinds of answer.
        self.assertEqual(named[2], 5)
        self.assertIn(None, named)


if __name__ == "__main__":
    unittest.main()

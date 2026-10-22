# test-scope: .github/scripts/pr-verify/resolve-pr.mjs
"""The verifier's shared rules agree across languages: the gate's
(`babysit_verify_evidence`, `babysit_classify`) and the resolver's
(`.github/scripts/pr-verify/resolve-pr.mjs`, run here under node).

- The dependency managers: the same logins, and the same users matched (a Bot
  account with one of them, never a User named like one).
- The owner account id whose pull requests the pr-merge lane adopts.
- The FAIL-counting rule: for each run record, a FAIL counts from any run of
  verifier origin and a PASS only from a completed success. The resolver also
  needs a completed run for a FAIL, so a run still going never stops a new
  judgment (the README's "Verifier verdict"); that is the one difference.

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
import babysit_merge_policy as policy
import babysit_postmerge as postmerge
import babysit_verify_evidence as ve
import test_babysit_verify_evidence as gate

RESOLVER = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/pr-verify/resolve-pr.mjs"
)
NODE = """
import { DEPENDENCY_MANAGERS, OWNER_ACCOUNT_ID, countedBy, isDependencyManager } from %s;
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
console.log(JSON.stringify({ managers: DEPENDENCY_MANAGERS, owner: OWNER_ACCOUNT_ID, users: users.map(isDependencyManager), counted }));
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

    def test_the_owner_account_is_the_same(self) -> None:
        self.assertEqual(resolver([], [])["owner"], policy.OWNER_ACCOUNT_ID)

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


if __name__ == "__main__":
    unittest.main()

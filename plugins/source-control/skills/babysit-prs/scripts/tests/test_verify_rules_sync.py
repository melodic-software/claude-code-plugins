# test-scope: .github/scripts/pr-verify/resolve-pr.mjs
"""The verifier's two shared rules agree across languages: the gate's
(`babysit_verify_evidence`, `babysit_classify`) and the resolver's
(`.github/scripts/pr-verify/resolve-pr.mjs`, run here under node).

- The dependency managers: the same logins, and the same users matched (a Bot
  account with one of them, never a User named like one).
- The head-ref digest a verdict's artifact name carries: the same length and
  the same digits for the same branch.
- The FAIL-counting rule: for each run record, a FAIL counts from any run of
  verifier origin and a PASS only from a completed success. The resolver also
  needs a completed run for a FAIL, so a run still going never stops a new
  judgment (the README's "Verifier verdict"); that is the one difference.

The run records are the gate suite's own forgeries and unfinished runs.
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

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_classify as classify
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

    def test_the_head_ref_digest_is_the_same(self) -> None:
        writer = RESOLVER.parent / "write-verdict.mjs"
        refs = [
            "feat/x",
            "perf/pr-merge-verdict-downloads",
            "a",
            "release/1.2.3",
            "x" * 255,
        ]
        script = (
            f"import {{ HEAD_REF_DIGEST_HEX, headRefDigest }} from {json.dumps(writer.as_uri())};"
            " const refs = JSON.parse(process.argv[1]);"
            " console.log(JSON.stringify({ hex: HEAD_REF_DIGEST_HEX, digests: refs.map(headRefDigest) }));"
        )
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script, json.dumps(refs)],
            capture_output=True,
            text=True,
            check=True,
        )
        answer = json.loads(proc.stdout)
        self.assertEqual(answer["hex"], ve.HEAD_REF_DIGEST_HEX)
        self.assertEqual(answer["digests"], [ve.head_ref_digest(r) for r in refs])
        # The first 16 hex digits of `printf %s feat/x | sha256sum`.
        self.assertEqual(answer["digests"][0], "79b4cc554b80dca6")

    def test_every_reader_takes_the_same_fail_names(self) -> None:
        # The gate, the resolver, the notes poster and pr-feedback-dispatch's
        # filter accept the same FAIL names, older ones and ones that carry
        # issue numbers alike; write-verdict.mjs writes the issues only once
        # all of them do. Each expected issue set is read off the name by hand.
        sha = "a" * 40
        base = f"pr-verify-41-{sha}-fail"
        digest = "79b4cc554b80dca6"
        names = {
            base: set(),
            f"{base}-{digest}": set(),
            f"{base}-i7": {7},
            f"{base}-{digest}-i7.12": {7, 12},
            f"{base}-i12.7.7": {7, 12},
            f"{base}-i" + ".".join(str(n) for n in range(1, 11)): set(range(1, 11)),
            f"{base}-i9999999999": {9999999999},
            f"{base}-i" + ".".join(str(n) for n in range(1, 12)): None,
            f"{base}-i10000000000": None,
            f"{base}-i07": None,
            f"{base}-i": None,
            f"{base}-i7.": None,
            f"{base}-i7-{digest}": None,
            f"{base}-I7": None,
            f"{base}-i7,8": None,
            f"{base}-extra": None,
        }
        notes = RESOLVER.parents[1] / "pr-unblock/verify-notes.mjs"
        script = (
            f"import {{ NAME }} from {json.dumps(RESOLVER.as_uri())};"
            f" import {{ FAIL_NAME }} from {json.dumps(notes.as_uri())};"
            " const names = JSON.parse(process.argv[1]);"
            " console.log(JSON.stringify(names.map((n) => [NAME.test(n), FAIL_NAME.test(n)])));"
        )
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script, json.dumps(list(names))],
            capture_output=True,
            text=True,
            check=True,
        )
        js = json.loads(proc.stdout)
        for (name, issues), (resolver_takes, notes_take) in zip(
            names.items(), js, strict=True
        ):
            with self.subTest(name):
                match = ve.NAME_RE.fullmatch(name)
                self.assertEqual(match is not None, issues is not None)
                if match:
                    self.assertEqual(ve.named_issues(match), issues)
                self.assertEqual(resolver_takes, issues is not None)
                self.assertEqual(notes_take, issues is not None)
        if shutil.which("jq"):
            workflow = RESOLVER.parents[2] / "workflows/pr-feedback-dispatch.yml"
            filters = re.findall(
                r'select\(test\("(\^pr-verify-[^"]*)"\)\)', workflow.read_text()
            )
            self.assertEqual(len(filters), 1, filters)
            proc = subprocess.run(
                ["jq", "-c", f'map(test("{filters[0]}"))'],
                input=json.dumps(list(names)),
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertEqual(
                json.loads(proc.stdout), [i is not None for i in names.values()]
            )


if __name__ == "__main__":
    unittest.main()

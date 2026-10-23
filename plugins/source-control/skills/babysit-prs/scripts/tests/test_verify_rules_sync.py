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

    # Each FAIL-shaped name, and the issues its name carries read off by hand,
    # or None for a name no reader takes. One verdict has one name: a PASS
    # carries no issues, and issues are ascending and listed once.
    SHA = "a" * 40
    BASE = f"pr-verify-41-{SHA}-fail"
    DIGEST = "79b4cc554b80dca6"
    NAMES = {
        BASE: set(),
        f"{BASE}-{DIGEST}": set(),
        f"{BASE}-i7": {7},
        f"{BASE}-{DIGEST}-i7.12": {7, 12},
        f"{BASE}-i" + ".".join(str(n) for n in range(1, 11)): set(range(1, 11)),
        f"{BASE}-i9999999999": {9999999999},
        f"{BASE}-i" + ".".join(str(n) for n in range(1, 12)): None,
        f"{BASE}-i12.7": None,
        f"{BASE}-i7.7": None,
        f"{BASE}-i12.7.7": None,
        f"{BASE}-i10000000000": None,
        f"{BASE}-i07": None,
        f"{BASE}-i": None,
        f"{BASE}-i7.": None,
        f"{BASE}-i7-{DIGEST}": None,
        f"{BASE}-I7": None,
        f"{BASE}-i7,8": None,
        f"{BASE}-extra": None,
        f"pr-verify-41-{SHA}-pass-i7": None,
        f"pr-verify-41-{SHA}-pass-notes-i7": None,
        f"pr-verify-41-{SHA}-pass-{DIGEST}-i7": None,
        # The pull request number is 1 to 10 digits in every reader.
        f"pr-verify-9999999999-{SHA}-fail": set(),
        f"pr-verify-10000000000-{SHA}-fail": None,
        f"pr-verify-041-{SHA}-fail": None,
        # The longest name the grammar allows, NAME_MAX (194) characters.
        f"pr-verify-9999999999-{SHA}-fail-{DIGEST}-i"
        + ".".join(str(9999999990 + n) for n in range(10)): set(
            range(9999999990, 10000000000)
        ),
        # A trailing line feed is no part of a name.
        f"{BASE}\n": None,
        f"{BASE}-i7\n": None,
    }

    def test_the_longest_name_is_name_max(self) -> None:
        # 194, counted by hand in NAME_MAX's comment; the table's longest
        # name is that long and every reader takes it.
        longest = max(self.NAMES, key=len)
        self.assertEqual((len(longest), ve.NAME_MAX), (194, 194))
        self.assertIsNotNone(ve.verdict_name(longest))

    def test_every_script_reader_takes_the_same_names(self) -> None:
        # The gate (`verdict_name`), the resolver (`isVerdictName`, the
        # pattern it checks names against; `judged` builds exact names and
        # reads none) and the notes poster (`isFailName`).
        notes = RESOLVER.parents[1] / "pr-unblock/verify-notes.mjs"
        script = (
            f"import {{ isVerdictName }} from {json.dumps(RESOLVER.as_uri())};"
            f" import {{ isFailName }} from {json.dumps(notes.as_uri())};"
            " const names = JSON.parse(process.argv[1]);"
            " console.log(JSON.stringify(names.map((n) => [isVerdictName(n), isFailName(n)])));"
        )
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script, json.dumps(list(self.NAMES))],
            capture_output=True,
            text=True,
            check=True,
        )
        js = json.loads(proc.stdout)
        for (name, issues), (resolver_takes, notes_take) in zip(
            self.NAMES.items(), js, strict=True
        ):
            with self.subTest(name):
                match = ve.verdict_name(name)
                self.assertEqual(match is not None, issues is not None)
                if match:
                    self.assertEqual(ve.named_issues(match), issues)
                self.assertEqual(resolver_takes, issues is not None)
                self.assertEqual(notes_take, issues is not None)

    def test_pr_feedback_dispatch_selects_the_same_fail_names(self) -> None:
        # Its listing keeps every FAIL-shaped name; its strict filter keeps
        # the ones the readers take, and any other fails the run.
        if not shutil.which("jq"):
            self.skipTest("jq not installed")
        workflow = (
            RESOLVER.parents[2] / "workflows/pr-feedback-dispatch.yml"
        ).read_text()
        listing = re.findall(r"--jq '([^']*)'", workflow)
        strict = re.findall(r"jq -Rr '([^']*)'", workflow)
        self.assertEqual((len(listing), len(strict)), (1, 1), (listing, strict))
        names = list(self.NAMES)

        def jq(program: str, payload: Any) -> Any:
            proc = subprocess.run(
                ["jq", "-c", program],
                input=json.dumps(payload),
                capture_output=True,
                text=True,
                check=True,
            )
            return json.loads(proc.stdout)

        fail_shaped = [n for n in names if "-pass" not in n]
        listed = jq(
            f"[{listing[0]}]",
            {"artifacts": [{"expired": False, "name": n} for n in names]},
        )
        # Any digits for the number, so an 11-digit one is listed and fails
        # the strict filter, as the gate holds on it.
        self.assertEqual(listed, fail_shaped)
        self.assertEqual(
            jq(f"[.[] | {strict[0]}]", names),
            [n for n, issues in self.NAMES.items() if issues is not None],
        )


QUEUE_CHECK = RESOLVER.parents[1] / "pr-merge/merge-holds.mjs"
REQUIRE_CHECKS = RESOLVER.parents[2] / "workflows/pr-require-checks.yml"
# The fields the queue check reads differ from the gate's `_origin` only in
# its compare that main holds the run's head SHA, which the queue check skips
# (main's ruleset forbids the force push that could drop it).
HEAD_ONLY = {"head_sha"}


def queue_counts(runs: list[dict[str, Any]]) -> list[bool]:
    script = (
        f"import {{ verdictHold }} from {json.dumps(QUEUE_CHECK.as_uri())};"
        " const { runs, repo } = JSON.parse(process.argv[1]);"
        " console.log(JSON.stringify(runs.map((run) => verdictHold([{ name: 'n', verdict: 'pass', runId: 1, run }], repo) === null)));"
    )
    proc = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            script,
            json.dumps({"runs": runs, "repo": gate.REPO}),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheQueueCheckAndTheGateAgree(unittest.TestCase):
    """ci-status's merge-queue pass check (pr-require-checks.yml's lookup and
    merge-holds.mjs verdictHold) counts a pass from the runs the gate counts."""

    def test_a_pass_counts_from_the_same_runs(self) -> None:
        cases = {label: gate.run(1, **overrides) for label, overrides in RUNS.items()}
        counted = queue_counts(list(cases.values()))
        for (label, run), js in zip(cases.items(), counted, strict=True):
            with self.subTest(label):
                if set(RUNS[label]) <= HEAD_ONLY:
                    # Only the head SHA differs: the gate's compare decides.
                    self.assertEqual(js, True)
                else:
                    self.assertEqual(js, gate_counts(run, "pass"))
        self.assertIn(True, counted)
        self.assertIn(False, counted)

    def test_the_lookup_names_and_origin_are_the_gate_s(self) -> None:
        text = REQUIRE_CHECKS.read_text(encoding="utf-8")
        start = text.index("          verdicts=()\n")
        body = text[
            text.index('if [ "$GITHUB_EVENT_NAME" = merge_group ]; then', start) :
        ]
        body = body[: body.index("          out=$(node")]
        # Every pass name, plain and with the head-ref digest, by exact name.
        for name in (
            '"pr-verify-$pr-$head-pass"',
            '"pr-verify-$pr-$head-pass-$digest"',
            '"pr-verify-$pr-$head-pass-notes"',
            '"pr-verify-$pr-$head-pass-notes-$digest"',
        ):
            self.assertIn(name, body)
        self.assertIn(f"sha256sum | cut -c1-{ve.HEAD_REF_DIGEST_HEX})", body)
        # The early stop counts a pass only from the gate's verifier runs.
        for clause in (
            f'.path == "{ve.WORKFLOW_PATH}"',
            '.event == "workflow_run"',
            '.head_branch == "main"',
            ".repository.full_name == $repo",
            ".head_repository.full_name == $repo",
            '.status == "completed"',
            '.conclusion == "success"',
        ):
            self.assertIn(clause, body)
        self.assertIn(
            f'VERIFY_PATH = "{ve.WORKFLOW_PATH}"',
            QUEUE_CHECK.read_text(encoding="utf-8"),
        )


if __name__ == "__main__":
    unittest.main()

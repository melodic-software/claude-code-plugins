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
- The `Refs:` rule: the one issue a pull request body's visible `Refs: #<n>`
  lines name (`babysit_merge_policy.refs_issue`, resolve-pr's `refsIssue`).
- The spec kind: the verdict write-verdict.mjs builds from resolve-pr's spec
  text records `spec_kind`, and the gate allows a pass only when it matches
  how the issue is linked now (a `Refs:` slice or a closing issue).

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

    def test_the_gate_reads_the_issues_the_writer_names(self) -> None:
        # Each FAIL write-verdict.mjs names parses to the issues it records;
        # a pass's name carries none.
        writer = RESOLVER.parent / "write-verdict.mjs"
        sha = "a" * 40
        cases = [
            ("fail", [7], {7}),
            ("fail", [12, 7, 12], {7, 12}),
            ("fail", list(range(1, 11)), set(range(1, 11))),
            ("fail", [9999999999], {9999999999}),
            ("fail", [], set()),
            ("pass", [7], set()),
            ("pass-notes", [7, 8], set()),
        ]
        verdicts = [
            {
                "pr": 41,
                "head_sha": sha,
                "verdict": v,
                "linked_issues": [{"number": n} for n in numbers],
            }
            for v, numbers, _ in cases
        ]
        script = (
            f"import {{ artifactName }} from {json.dumps(writer.as_uri())};"
            " console.log(JSON.stringify(JSON.parse(process.argv[1]).map(artifactName)));"
        )
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script, json.dumps(verdicts)],
            capture_output=True,
            text=True,
            check=True,
        )
        for (verdict, _, issues), name in zip(
            cases, json.loads(proc.stdout), strict=True
        ):
            with self.subTest(name):
                match = ve.NAME_RE.fullmatch(name)
                self.assertIsNotNone(match)
                assert match is not None
                self.assertEqual(match[3], verdict)
                self.assertEqual(ve.named_issues(match), issues)


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
WRITER = RESOLVER.with_name("write-verdict.mjs")
KIND_NODE = """
import { buildVerdict } from %s;
const { linked, entries } = JSON.parse(process.argv[1]);
const ids = { pr: "41", headSha: "a".repeat(40), baseSha: "b".repeat(40), runId: "1", headRef: "feat/x" };
const output = JSON.stringify({ verdict: "pass", summary: "s", notes: [] });
console.log(JSON.stringify(entries.map((kind) =>
  buildVerdict({ ...ids, linkedIssues: [linked], output, specText: [{ number: 7, spec_kind: kind, body: "b", comments: [] }] }).spec_kind)));
"""
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


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheGateBindsThePassToTheSpecKindTheWriterRecords(unittest.TestCase):
    def test_a_pass_allows_only_under_the_link_it_was_judged_for(self) -> None:
        script = KIND_NODE % json.dumps(WRITER.as_uri())
        payload = {"linked": gate.TRUSTED_ISSUE, "entries": ["closes", "refs"]}
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script, json.dumps(payload)],
            capture_output=True,
            text=True,
            check=True,
        )
        written = json.loads(proc.stdout)
        self.assertEqual(written, ["closes", "refs"])
        for judged, kind in zip(("closes", "refs"), written, strict=True):
            for linked in ("closes", "refs"):
                with self.subTest(judged=judged, linked=linked):
                    fake = gate.passing()
                    fake.records[gate.named(gate.HEAD, "pass")] = gate.record(
                        spec_kind=kind
                    )
                    if linked == "refs":
                        fake.closing, fake.body = [], "Refs: #7"
                        fake.refs = {7: gate.REPO}
                    refusal = gate.read(fake).refusal
                    self.assertEqual(
                        refusal, None if judged == linked else "verify:spec-changed"
                    )


if __name__ == "__main__":
    unittest.main()

# test-scope: .github/scripts/pr-verify/resolve-pr.mjs .github/scripts/pr-verify/write-verdict.mjs .github/workflows/pr-require-checks.yml .github/scripts/pr-merge/merge-holds.mjs
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
- The relink rule: the same RELINK_QUERY text, and the same body edits and
  issue connect or disconnect events let a FAIL be superseded (every one
  since the FAIL a trusted person's; a cut or unreadable answer never), and
  the body-edit rule: at least one of them a body edit, every one a trusted
  person's.
- The draft-run rule: the same FAIL is dropped as judged from a checks run
  that started on the draft (`_draft_judged`, resolve-pr's `draftJudgments`),
  and every failed or short read keeps it in both.
- The spec kind: the verdict write-verdict.mjs builds from resolve-pr's spec
  text records `spec_kind`, and the gate allows a pass only when it matches
  how the issue is linked now (a `Refs:` slice or a closing issue).
- The merge queue's pass lookup: ci-status's lines that find the head's pass
  in pr-require-checks.yml, run under bash against stubbed run reads, allow
  a pass from the runs the gate counts, under the exact names it reads.

The run records are the gate suite's own forgeries and unfinished runs.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
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

    def test_a_relink_is_judged_the_same(self) -> None:
        human, app = gate.HUMAN, gate.LANES_ACTOR
        at, before = gate.RELINK_AT, "2026-10-13T00:00:00Z"
        answers = [
            gate.relink_answer([(at, human)], [(at, human)]),
            gate.relink_answer([(before, app)], [(at, human)]),
            gate.relink_answer([(at, app)]),
            gate.relink_answer([], [(at, app)]),
            gate.relink_answer([(at, None)]),
            gate.relink_answer([(at, human)], edits_total=101),
            gate.relink_answer([], [(at, human)], events_filtered=2),
            gate.relink_answer([], [(None, human)]),
            gate.relink_answer(),
            {},
        ]
        script = (
            f"import {{ RELINK_QUERY, relinkedByPeople }} from {json.dumps(RESOLVER.as_uri())};"
            " const { answers, since, humans, repo } = JSON.parse(process.argv[1]);"
            " const judged = [];"
            " for (const pullRequest of answers) {"
            "   const github = async () => ({ data: { repository: { pullRequest } } });"
            "   judged.push(await relinkedByPeople(github, repo, 41, new Set(humans), since));"
            " }"
            " console.log(JSON.stringify({ query: RELINK_QUERY, judged }));"
        )
        payload = {
            "answers": answers,
            "since": gate.OLDER_START,
            "humans": [gate.MAINTAINER["id"]],
            "repo": gate.REPO,
        }
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script, json.dumps(payload)],
            capture_output=True,
            text=True,
            check=True,
        )
        js = json.loads(proc.stdout)
        self.assertEqual(js["query"], ve.RELINK_QUERY)
        since = postmerge._time(gate.OLDER_START)
        # The resolver judges up to now; the gate up to a pass's start.
        until = postmerge._time("2100-01-01T00:00:00Z")
        for answer, judged in zip(answers, js["judged"], strict=True):
            fake = gate.FakeGitHub([], {})
            fake.relink = answer
            with (
                mock.patch.object(postmerge, "gh_capture", side_effect=fake),
                mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
            ):
                reader = ve.Reader(gate.REPO, "main")
                with self.subTest(answer):
                    self.assertEqual(
                        reader._relinked_by_people(gate.PR, since, until), judged
                    )
        self.assertEqual(js["judged"][:3], [True, True, False])

    def test_a_body_edit_is_judged_the_same(self) -> None:
        human, app = gate.HUMAN, gate.LANES_ACTOR
        at, before = gate.RELINK_AT, "2026-10-13T00:00:00Z"
        cases = [
            # A person's edit alone re-opens the head; a connect alone does not.
            (gate.relink_answer([(at, human)]), True),
            (gate.relink_answer([], [(at, human)]), False),
            (gate.relink_answer([(at, human)], [(at, human)]), True),
            (gate.relink_answer([(at, human)], [(at, app)]), False),
            (gate.relink_answer([(at, app)]), False),
            (gate.relink_answer([(at, None)]), False),
            (gate.relink_answer([(before, human)]), False),
            (gate.relink_answer([(before, app), (at, human)]), True),
            (gate.relink_answer([(at, human)], edits_total=101), False),
            (gate.relink_answer([(None, human)]), False),
            ({}, False),
        ]
        script = (
            f"import {{ editedByPeople }} from {json.dumps(RESOLVER.as_uri())};"
            " const { answers, since, humans, repo } = JSON.parse(process.argv[1]);"
            " const judged = [];"
            " for (const pullRequest of answers) {"
            "   const github = async () => ({ data: { repository: { pullRequest } } });"
            "   judged.push(await editedByPeople(github, repo, 41, new Set(humans), since));"
            " }"
            " console.log(JSON.stringify(judged));"
        )
        payload = {
            "answers": [answer for answer, _ in cases],
            "since": gate.OLDER_START,
            "humans": [gate.MAINTAINER["id"]],
            "repo": gate.REPO,
        }
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script, json.dumps(payload)],
            capture_output=True,
            text=True,
            check=True,
        )
        js = json.loads(proc.stdout)
        since = postmerge._time(gate.OLDER_START)
        until = postmerge._time("2100-01-01T00:00:00Z")
        for (answer, expected), judged in zip(cases, js, strict=True):
            fake = gate.FakeGitHub([], {})
            fake.relink = answer
            with (
                mock.patch.object(postmerge, "gh_capture", side_effect=fake),
                mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
            ):
                reader = ve.Reader(gate.REPO, "main")
                with self.subTest(answer):
                    self.assertEqual(judged, expected)
                    self.assertEqual(
                        reader._relinked_by_people(
                            gate.PR, since, until, body_edit=True
                        ),
                        expected,
                    )

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

    def test_a_checks_runs_draft_state_is_read_the_same(self) -> None:
        # Only a listed conclusion of the draft step decides; the jobs API can
        # list a finished job's steps empty or cut short.
        cases = {
            "the draft step ran": gate.DRAFT_JOBS,
            "the draft step skipped": gate.READY_JOBS,
            **gate.UNREADABLE_DRAFT_STATE,
        }
        script = (
            f"import {{ draftRun }} from {json.dumps(RESOLVER.as_uri())};"
            " const cases = JSON.parse(process.argv[1]);"
            " const out = [];"
            " for (const jobs of cases) {"
            "   try { out.push((await draftRun(async () => jobs, 'o/r', 1)) ? 'draft' : 'ready'); }"
            "   catch { out.push('unreadable'); }"
            " }"
            " console.log(JSON.stringify(out));"
        )
        proc = subprocess.run(
            [
                "node",
                "--input-type=module",
                "-e",
                script,
                json.dumps(list(cases.values())),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        js = json.loads(proc.stdout)
        expected = ["draft", "ready"] + ["unreadable"] * len(
            gate.UNREADABLE_DRAFT_STATE
        )
        self.assertEqual(js, expected)
        for (label, jobs), want in zip(cases.items(), expected, strict=True):
            fake = gate.FakeGitHub([], {})
            fake.jobs[gate.DRAFT_CHECKS] = jobs
            with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
                reader = ve.Reader(gate.REPO, "main")
                try:
                    got = "draft" if reader._draft_run(gate.DRAFT_CHECKS) else "ready"
                except ve._Unreadable:
                    got = "unreadable"
            with self.subTest(label):
                self.assertEqual(got, want)

    def test_a_fail_judged_from_a_draft_run_is_dropped_the_same(self) -> None:
        # #11832's checks runs at the head (gate.draft_race), then each change
        # the gate suite's keeps-the-FAIL test makes; `jobs` None is a read
        # that fails, `runs` None a listing that fails.
        base = {
            "runs": [
                {"id": gate.READY_CHECKS, "created_at": "2026-11-01T04:26:33Z"},
                {"id": gate.DRAFT_CHECKS, "created_at": "2026-11-01T04:25:39Z"},
            ],
            "total": None,
            "jobs": {
                gate.DRAFT_CHECKS: gate.DRAFT_JOBS,
                gate.READY_CHECKS: gate.READY_JOBS,
            },
        }
        ready_before = {**base["jobs"], gate.DRAFT_CHECKS: gate.READY_JOBS}
        jobs_cut = {
            **base["jobs"],
            gate.DRAFT_CHECKS: {**gate.DRAFT_JOBS, "total_count": 2},
        }
        scenarios = {
            "a draft run before": base,
            "a ready run before": {**base, "jobs": ready_before},
            "the runs cut short": {**base, "total": 3},
            "the draft run's jobs unread": {
                **base,
                "jobs": {gate.READY_CHECKS: gate.READY_JOBS},
            },
            "the draft run's jobs cut short": {**base, "jobs": jobs_cut},
            "no run before": {**base, "runs": base["runs"][:1]},
            "a ready run beside": {
                "runs": [
                    *base["runs"],
                    {"id": 41273000001, "created_at": "2026-11-01T04:25:00Z"},
                ],
                "total": None,
                "jobs": {**base["jobs"], 41273000001: gate.READY_JOBS},
            },
            "a run with no time": {
                **base,
                "runs": [*base["runs"], {"id": 41273000002}],
            },
            "the runs unread": {**base, "runs": None},
        }
        script = (
            f"import {{ draftJudgments }} from {json.dumps(RESOLVER.as_uri())};"
            " const { scenarios, repo, head, judgedAt } = JSON.parse(process.argv[1]);"
            " const out = [];"
            " for (const { runs, total, jobs } of scenarios) {"
            "   const github = async (method, path) => {"
            "     if (path.includes('/actions/workflows/')) {"
            "       if (runs === null) throw new Error('GET failed with status 502');"
            "       return { total_count: total ?? runs.length, workflow_runs: runs };"
            "     }"
            "     const id = /\\/actions\\/runs\\/(\\d+)\\/jobs/.exec(path)?.[1];"
            "     if (id && jobs[id]) return jobs[id];"
            "     throw new Error(`GET ${path} failed with status 404`);"
            "   };"
            "   out.push(await draftJudgments(github, repo, head)({ created_at: judgedAt }));"
            " }"
            " console.log(JSON.stringify(out));"
        )
        payload = {
            "scenarios": list(scenarios.values()),
            "repo": gate.REPO,
            "head": gate.HEAD,
            "judgedAt": gate.FAIL_JUDGED,
        }
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script, json.dumps(payload)],
            capture_output=True,
            text=True,
            check=True,
        )
        js = json.loads(proc.stdout)
        for (label, scenario), judged in zip(scenarios.items(), js, strict=True):
            fake = gate.FakeGitHub([], {2: gate.judged(2, gate.FAIL_JUDGED)})
            if scenario["runs"] is not None:
                fake.checks_runs[gate.HEAD] = scenario["runs"]
            if scenario["total"] is not None:
                fake.checks_total[gate.HEAD] = scenario["total"]
            fake.jobs = dict(scenario["jobs"])
            with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
                reader = ve.Reader(gate.REPO, "main")
                with self.subTest(label):
                    self.assertEqual(reader._draft_judged(gate.HEAD, 2), judged)
        self.assertEqual(js[:2], [True, False])

    def test_a_fail_outlives_the_look_back_and_a_pass_its_held_head(self) -> None:
        # A FAIL the gate still counts must not expire before the pull
        # request turns too old (TOO_OLD_DAYS), or verify:earlier-fail and the
        # FAIL cap stop refusing. So must a pass judged after a relink: it may
        # supersede a FAIL at its head (`_superseded`), which a later head of
        # the same change still reads. Any other pass is read only at the open
        # head, and 7 days is the window .github/artifact-retention.json records.
        writer = RESOLVER.parent / "write-verdict.mjs"
        script = (
            f"import {{ retentionDays }} from {json.dumps(writer.as_uri())};"
            " console.log(JSON.stringify(["
            ' retentionDays("fail", false), retentionDays("pass", true),'
            ' retentionDays("pass-notes", true), retentionDays("pass", false),'
            ' retentionDays("pass-notes", false)]));'
        )
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script],
            capture_output=True,
            text=True,
            check=True,
        )
        fail, relinked, relinked_notes, passed, notes = json.loads(proc.stdout)
        for days in (fail, relinked, relinked_notes):
            self.assertGreater(days, ve.TOO_OLD_DAYS)
        self.assertEqual((passed, notes), (7, 7))

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
        f"pr-verify-41-{SHA}-pass": set(),
        f"pr-verify-41-{SHA}-pass-notes": set(),
        f"pr-verify-41-{SHA}-pass-notes-{DIGEST}": set(),
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
        # reads none) and the notes poster (`readVerdict`, given a verdict
        # file that records what the name names).
        notes = RESOLVER.parents[1] / "pr-unblock/verify-notes.mjs"
        script = (
            f"import {{ isVerdictName, NAME }} from {json.dumps(RESOLVER.as_uri())};"
            f" import {{ readVerdict }} from {json.dumps(notes.as_uri())};"
            " const names = JSON.parse(process.argv[1]);"
            " const reads = (n) => { const m = NAME.exec(n); if (!m) return false;"
            " const issues = (m[4] ? m[4].split('.') : []).map((number) => ({ number: Number(number) }));"
            " const text = JSON.stringify({ verdict: m[3], pr: Number(m[1]), head_sha: m[2], head_ref: 'feat/x',"
            " linked_issues: issues, summary: 's', notes: [] });"
            " try { readVerdict(n, text); return true; } catch { return false; } };"
            " console.log(JSON.stringify(names.map((n) => [isVerdictName(n), reads(n)])));"
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

    def test_pr_feedback_dispatch_selects_the_same_names(self) -> None:
        # Its listing keeps every verdict-shaped name, a pass's included; its
        # strict filter keeps the ones the readers take, and any other fails
        # the run.
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

        listed = jq(
            f"[{listing[0]}]",
            {"artifacts": [{"expired": False, "name": n} for n in names]},
        )
        # Any digits for the number, so an 11-digit one is listed and fails
        # the strict filter, as the gate holds on it.
        self.assertEqual(listed, names)
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
    # An off-form line beside a plain one still names none.
    "Refs: #5\nrefs: #6",
    "Refs: #5\nRefs: o/r#6",
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


QUEUE_CHECK = RESOLVER.parents[1] / "pr-merge/merge-holds.mjs"
REQUIRE_CHECKS = RESOLVER.parents[2] / "workflows/pr-require-checks.yml"
# The fields the queue check reads differ from the gate's `_origin` only in
# its compare that main holds the run's head SHA, which the queue check skips
# (main's ruleset forbids the force push that could drop it).
HEAD_ONLY = {"head_sha"}


def queue_allows(records: list[list[dict[str, Any]]]) -> list[bool]:
    script = (
        f"import {{ verdictHold }} from {json.dumps(QUEUE_CHECK.as_uri())};"
        " const { records, repo } = JSON.parse(process.argv[1]);"
        " console.log(JSON.stringify(records.map((r) => verdictHold(r, repo) === null)));"
    )
    proc = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            script,
            json.dumps({"records": records, "repo": gate.REPO}),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


def queue_counts(runs: list[dict[str, Any]]) -> list[bool]:
    return queue_allows(
        [[{"name": "n", "verdict": "pass", "runId": 1, "run": run}] for run in runs]
    )


def queue_should_count(label: str) -> bool:
    # Only the head SHA differs: the gate's compare decides, which the queue
    # check skips.
    return set(RUNS[label]) <= HEAD_ONLY or gate_counts(
        gate.run(1, **RUNS[label]), "pass"
    )


QUEUE_REF = "work-resolve-issue/issue-1"
LOOKUP_STUBS = """\
read_api() {
  printf '%s\\n' "$2" >>"$RUNNER_TEMP/reads"
  jq -ce --arg id "${2##*/}" '.[$id] // error' "$RUNNER_TEMP/runs.json"
}
: >"$RUNNER_TEMP/reads"
: >"$RUNNER_TEMP/verdicts.jsonl"
listed=true
"""


def queue_lookup_script() -> str:
    """The merge-queue lines of ci-status's hold step that find the head's
    pass, as the workflow holds them: the head-ref digest, the lookup by
    exact name that stops at a counted pass, and the counted pass's
    artifact."""
    lines = REQUIRE_CHECKS.read_text(encoding="utf-8").splitlines()
    start = lines.index("          verdicts=()")
    body = lines[start : lines.index("          export BASE_SHA", start)]

    def at(prefix: str, after: int = 0) -> int:
        for n in range(after, len(body)):
            if body[n].lstrip().startswith(prefix):
                return n
        raise AssertionError(f"no line starting {prefix!r} in the queue lookup")

    digest = at("digest=$(")
    loop = at('[ "$listed" = false ] || for name in')
    loop_end = body.index("            done", loop)
    artifact = at("artifact=$(jq -sr")
    artifact_end = at("and .repository.full_name == $repo", artifact)
    return textwrap.dedent(
        "\n".join(
            [
                body[digest],
                *body[loop : loop_end + 1],
                *body[artifact : artifact_end + 1],
            ]
        )
    )


def listed(name: str, run: int, expired: bool = False) -> dict[str, Any]:
    return {
        "name": name,
        "id": run * 10,
        "expired": expired,
        "workflow_run": {"id": run},
    }


def queue_lookup(
    artifacts: list[dict[str, Any]], runs: dict[int, dict[str, Any]]
) -> tuple[list[dict[str, Any]], str, int]:
    """Run the lookup for PR 41 at the gate's head over `artifacts` as the
    reader's listing, each run read answering `runs`. Returns the records it
    kept, the counted pass's artifact id ('' for none) and its run reads."""
    for tool in ("bash", "jq", "sha256sum"):
        if not shutil.which(tool):
            raise unittest.SkipTest(f"{tool} not installed")
    script = LOOKUP_STUBS + queue_lookup_script() + '\nprintf "%s\\n" "$artifact"\n'
    with tempfile.TemporaryDirectory() as tmp:
        temp = pathlib.Path(tmp)
        (temp / "listing.json").write_text(json.dumps({"artifacts": artifacts}))
        (temp / "runs.json").write_text(
            json.dumps({str(k): v for k, v in runs.items()})
        )
        proc = subprocess.run(
            ["bash", "-e", "-c", script],
            env={
                **os.environ,
                "RUNNER_TEMP": tmp,
                "BABYSIT_VERIFY_LISTING": str(temp / "listing.json"),
                "GITHUB_REPOSITORY": gate.REPO,
                "pr": str(gate.PR),
                "head": gate.HEAD,
                "ref": QUEUE_REF,
            },
            capture_output=True,
            text=True,
            check=True,
        )
        kept = (temp / "verdicts.jsonl").read_text().splitlines()
        reads = (temp / "reads").read_text().splitlines()
    return [json.loads(row) for row in kept], proc.stdout.strip(), len(reads)


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheQueueCheckAndTheGateAgree(unittest.TestCase):
    """ci-status's merge-queue pass check (pr-require-checks.yml's lookup,
    run here against stubbed run reads, and merge-holds.mjs verdictHold)
    counts a pass from the runs the gate counts."""

    def test_a_pass_counts_from_the_same_runs(self) -> None:
        counted = queue_counts(
            [gate.run(1, **overrides) for overrides in RUNS.values()]
        )
        for label, js in zip(RUNS, counted, strict=True):
            with self.subTest(label):
                self.assertEqual(js, queue_should_count(label))
        self.assertIn(True, counted)
        self.assertIn(False, counted)

    def test_the_lookup_allows_a_pass_from_the_runs_the_gate_counts(self) -> None:
        name = f"pr-verify-{gate.PR}-{gate.HEAD}-pass"
        looked = [
            queue_lookup([listed(name, 1)], {1: gate.run(1, **overrides)})
            for overrides in RUNS.values()
        ]
        allowed = queue_allows([kept for kept, _, _ in looked])
        for label, (_, artifact, _), allows in zip(RUNS, looked, allowed, strict=True):
            with self.subTest(label):
                self.assertEqual(allows, queue_should_count(label))
                self.assertEqual(artifact, "10" if allows else "")
        self.assertIn(True, allowed)
        self.assertIn(False, allowed)

    def test_the_lookup_stops_only_at_a_pass_the_gate_counts(self) -> None:
        # The run record under the first name, a counted pass under a later one.
        first, later = (
            f"pr-verify-{gate.PR}-{gate.HEAD}-{verdict}"
            for verdict in ("pass", "pass-notes")
        )
        for label, overrides in RUNS.items():
            with self.subTest(label):
                _, artifact, reads = queue_lookup(
                    [listed(first, 1), listed(later, 2)],
                    {1: gate.run(1, **overrides), 2: gate.run(2)},
                )
                self.assertEqual(
                    (artifact, reads),
                    ("10", 1) if queue_should_count(label) else ("20", 2),
                )

    def test_the_lookup_takes_each_pass_name_and_no_other(self) -> None:
        base = f"pr-verify-{gate.PR}-{gate.HEAD}"
        digest = ve.head_ref_digest(QUEUE_REF)
        names = {
            f"{base}-pass": True,
            f"{base}-pass-{digest}": True,
            f"{base}-pass-notes": True,
            f"{base}-pass-notes-{digest}": True,
            f"{base}-pass-{ve.head_ref_digest('feat/x')}": False,
            f"{base}-pass-i7": False,
            f"{base}-fail": False,
            f"pr-verify-{gate.PR}-{gate.EARLIER}-pass": False,
            f"pr-verify-{gate.PR + 1}-{gate.HEAD}-pass": False,
        }
        looked = [queue_lookup([listed(name, 1)], {1: gate.run(1)}) for name in names]
        allowed = queue_allows([kept for kept, _, _ in looked])
        for (name, taken), (_, artifact, reads), allows in zip(
            names.items(), looked, allowed, strict=True
        ):
            with self.subTest(name):
                self.assertEqual(
                    (allows, artifact, reads),
                    (True, "10", 1) if taken else (False, "", 0),
                )
        expired = queue_lookup(
            [listed(f"{base}-pass", 1, expired=True)], {1: gate.run(1)}
        )
        self.assertEqual(expired, ([], "", 0))


if __name__ == "__main__":
    unittest.main()

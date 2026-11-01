# test-scope: plugins/source-control/skills/babysit-prs/scripts/babysit_merge_prefilter.py plugins/source-control/skills/babysit-prs/scripts/tests/repo_config_fake.py
# test-scope: plugins/source-control/skills/babysit-prs/scripts/tests/test_babysit_merge.py plugins/source-control/skills/babysit-prs/scripts/tests/test_babysit_merge_async.py
# test-scope: plugins/source-control/skills/babysit-prs/scripts/tests/test_babysit_review_evidence.py plugins/source-control/skills/babysit-prs/scripts/tests/fixtures/review_evidence/*
"""The pr-merge lane's reader of verifier verdicts (`babysit_verify_evidence`).

Expected values come from issue #7702 (Scope, Done when) and the verdict rules
in docs/conventions/pr-pipeline/README.md ("Verifier verdict"): an artifact
named `pr-verify-<pr>-<sha>-<verdict>` counts only through a run of
`.github/workflows/pr-verify.yml` on main of this repository; a FAIL counts
whatever the run's conclusion and under any pull request number, a PASS only
from a completed success at this pull request's head; a FAIL at another head
of the pull request goes to a human unless a counted pass at the head clears
every check; an unreadable FAIL blocks; a pull request
older than 80 days is refused; a pass needs every linked issue written
and last edited by a trusted human, the pull request's author included,
unchanged since the judgment; the Actions reads use the Actions token; a Dependabot pull request
needs no verdict.

The artifact and run shapes follow responses recorded from
`GET /repos/{owner}/{repo}/actions/artifacts` and `GET .../actions/runs/{id}`
for a `workflow_run` run, with identifying details changed. Network is stubbed
at the `gh_capture` seam the reader shares with the post-merge check.
"""

from __future__ import annotations

import contextlib
import dataclasses
import hashlib
import io
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest
import zipfile
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_gh as gh
import babysit_merge as merge
import babysit_merge_policy as policy
import babysit_postmerge as postmerge
import babysit_run_cache as run_cache
import babysit_verify_evidence as ve
import test_babysit_merge_unattended as unattended

REPO = "example-org/example-repo"
PR = 41
HEAD = "a" * 40
EARLIER = "b" * 40  # an earlier head of PR 41, force-pushed away
MAIN_SHA = "c" * 40
OFF_MAIN = "d" * 40
IN_PR = "e" * 40  # a commit still on PR 41
UNRELATED = "f" * 40
WORKFLOW = ".github/workflows/pr-verify.yml"
NOW = datetime(2026, 10, 16, tzinfo=UTC)
MAINTAINER = {"id": 100, "login": "maintainer", "kind": "human"}
LANES = {"id": 200, "login": "agent-lanes[bot]", "kind": "bot"}
TRUSTED_ISSUE = {
    "number": 7,
    "author_login": "maintainer",
    "author_id": 100,
    "author_type": "User",
    "last_edited_at": None,
    "editor_login": None,
    "editor_id": None,
    "editor_type": None,
    "spec_comments": [],
}
HUMAN = {"__typename": "User", "login": "maintainer", "databaseId": 100}
LANES_ACTOR = {"__typename": "Bot", "login": "agent-lanes", "databaseId": 200}


def comment(
    cid: int,
    author: dict[str, Any],
    updated: str = "2026-10-12T00:00:00Z",
    **extra: Any,
) -> dict[str, Any]:
    return {
        "databaseId": cid,
        "updatedAt": updated,
        "lastEditedAt": None,
        "author": author,
        "editor": None,
        **extra,
    }


RUN_STARTED = "2026-10-15T00:00:00Z"
OLDER_START = "2026-10-14T00:00:00Z"


def pull(**overrides: Any) -> dict[str, Any]:
    fields = {
        "number": PR,
        "created_at": "2026-10-10T00:00:00Z",
        "head": {"ref": "feat/x", "sha": HEAD},
        "user": {"login": "agent-lanes[bot]"},
    }
    fields.update(overrides)
    return fields


def artifact(name: str, run_id: int, *, expired: bool = False) -> dict[str, Any]:
    return {
        "id": run_id * 10,
        "name": name,
        "expired": expired,
        "created_at": "2026-10-01T00:00:00Z",
        "expires_at": "2027-01-01T00:00:00Z",
        "workflow_run": {
            "id": run_id,
            "head_branch": "main",
            "head_sha": MAIN_SHA,
            "repository_id": 1,
            "head_repository_id": 1,
        },
    }


def run(run_id: int, **overrides: Any) -> dict[str, Any]:
    fields = {
        "id": run_id,
        "name": "pr-verify",
        "path": WORKFLOW,
        "event": "workflow_run",
        "status": "completed",
        "conclusion": "success",
        "head_branch": "main",
        "head_sha": MAIN_SHA,
        "run_attempt": 1,
        "created_at": RUN_STARTED,
        "run_started_at": RUN_STARTED,
        "updated_at": RUN_STARTED,
        "repository": {"full_name": REPO},
        "head_repository": {"full_name": REPO},
    }
    fields.update(overrides)
    return fields


def record(number: int = PR, sha: str = HEAD, **overrides: Any) -> dict[str, Any]:
    fields = {
        "pr": number,
        "head_sha": sha,
        "base_sha": MAIN_SHA,
        "head_ref": "feat/x",
        "verdict": "pass",
        "summary": "s",
        "notes": [],
        "run_id": 1,
        "linked_issues": [TRUSTED_ISSUE],
    }
    fields.update(overrides)
    return fields


def judged(run_id: int, at: Any, **overrides: Any) -> dict[str, Any]:
    """A run created, and its one attempt started and completed, at `at`."""
    return run(run_id, created_at=at, run_started_at=at, updated_at=at, **overrides)


def named(sha: str, verdict: str, number: int = PR) -> str:
    return f"pr-verify-{number}-{sha}-{verdict}"


def change(
    added: str, at: int = 1, before: str = "one", path: str = "notes.txt"
) -> str:
    """A unified diff adding line `added` to `path` at line `at` after the
    context line `before`, in the form GitHub's compare diff and `git diff`
    write."""
    return (
        f"diff --git a/{path} b/{path}\n"
        "index 1111111..2222222 100644\n"
        f"--- a/{path}\n"
        f"+++ b/{path}\n"
        f"@@ -{at},2 +{at},3 @@\n"
        f" {before}\n"
        f"+{added}\n"
        " two\n"
    )


def zipped(record: Any) -> bytes:
    """An artifact archive holding `record` as verdict.json, as
    `GET .../actions/artifacts/{id}/zip` serves it."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("verdict.json", json.dumps(record))
    return buffer.getvalue()


class FakeGitHub:
    """Answers the reader's reads: the artifact listing, runs, a compare of a
    run head against main, the pull request's commits, the trusted-actor list,
    and a verdict.json, as an archive by artifact id or through
    `gh run download`."""

    def __init__(
        self,
        artifacts: list[dict[str, Any]],
        runs: dict[int, Any],
        records: dict[str, dict[str, Any]] | None = None,
    ):
        self.artifacts = artifacts
        self.runs = runs
        self.records = records or {}
        self.on_main = {MAIN_SHA}
        self.commits = [IN_PR, HEAD]
        # Each commit's git tree, as the commit list and `git/commits` give it.
        # The pull request's own change at each commit: the compare diff from
        # its merge base with main, each unlike the others.
        self.diffs = {s: change(s[:4]) for s in (HEAD, EARLIER, IN_PR, UNRELATED)}
        self.actors: Any = {"version": 1, "actors": [MAINTAINER, LANES]}
        self.calls: list[list[str]] = []
        self.envs: list[tuple[list[str], Any]] = []
        self.fail: set[str] = set()
        self.fail_status = 502
        # The PR's closing issues now: (number, repository).
        self.closing: list[tuple[int, str]] = [(7, REPO)]
        self.closing_total: int | None = None
        # Each closing issue's body lastEditedAt now, by number.
        self.closing_edited: dict[int, str | None] = {}
        # Each closing issue's comments now, and a totalCount that cuts them.
        self.closing_comments: dict[int, list[dict[str, Any]]] = {}
        self.comments_total: dict[int, int] = {}
        # The pull requests, open or closed, that close each issue:
        # (number, repository), and a totalCount that cuts them.
        self.closers: dict[int, list[tuple[int, str]]] = {}
        # Each closing pull request's state: the one judged is open, others
        # closed unless named; its author, unless named none.
        self.closer_states: dict[int, str] = {}
        self.closer_authors: dict[int, dict[str, Any]] = {}
        # The REST record of a pull request no issue lists, by number: closed
        # and unmerged unless named.
        self.pulls: dict[int, dict[str, Any]] = {}
        self.closers_total: dict[int, int] = {}
        # The pull requests each issue's cross-reference timeline shows:
        # (number, repository), or None for an issue as the source; and a
        # totalCount that cuts them. The gate reads no timeline.
        self.mentions: dict[int, list[tuple[int, str] | None]] = {}
        self.mentions_total: dict[int, int] = {}
        # The pull request's body now, and what each number a `Refs:` line
        # may name is: an issue's repository, or "PullRequest".
        self.body: str | None = None
        self.refs: dict[int, str] = {}
        # Each issue's label names now, and a totalCount that cuts them.
        self.labels: dict[int, list[str]] = {}
        self.labels_total: dict[int, int] = {}
        # Each issue's REST timeline events, and each login's permission.
        self.timeline: dict[int, list[dict[str, Any]]] = {}
        self.permissions: dict[str, str] = {}
        # The single pages the reader checks a listing against: the live
        # `total_count` they report (None: the artifacts' count), and a gh
        # error for each.
        self.live_total: int | None = None
        self.page_fail: str | None = None
        # Ids each whole listing leaves out in turn, as one that pages while
        # an earlier artifact expires skips the one at a page boundary.
        self.full_skips: list[set[int]] = []
        # The count reads before whole listings, and a gh error for each.
        self.count_reads: list[list[str]] = []
        self.count_timeouts: list[float | None] = []
        self.count_fail: str | None = None
        # The pull request's RELINK_QUERY answer (its `pullRequest`), or
        # "error" for a failed read; None answers as the closing read does.
        self.relink: Any = None
        # The pr-require-checks pull_request runs at each head, and a
        # total_count that cuts them; a head with none named answers 404.
        self.checks_runs: dict[str, list[dict[str, Any]]] = {}
        self.checks_total: dict[str, int] = {}
        # Each checks run's latest jobs; a run with none named answers 404.
        self.jobs: dict[int, dict[str, Any]] = {}

    def listed(self) -> list[dict[str, Any]]:
        """The artifacts a whole listing returns now, newest id first as
        GitHub orders them."""
        skip = self.full_skips.pop(0) if self.full_skips else set()
        ordered = sorted(self.artifacts, key=lambda a: -a.get("id", 0))
        return [a for a in ordered if a.get("id") not in skip]

    def pages(self) -> int:
        """Single-page reads (the incremental listing and its top-ups)."""
        return sum("&page=" in " ".join(c) for c in self.calls)

    def full_listings(self) -> int:
        return sum(
            c[:2] == ["api", f"repos/{REPO}/actions/artifacts?per_page=100"]
            for c in self.calls
        )

    def probes(self) -> int:
        """Reads of the live artifact count before whole listings, kept out
        of `calls` so the listing counts above stay the listings'."""
        return len(self.count_reads)

    def __call__(
        self, args: list[str], **kwargs: Any
    ) -> subprocess.CompletedProcess[str]:
        def ok(payload: Any) -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(args, 0, json.dumps(payload), "")

        probe = f"repos/{REPO}/actions/artifacts?per_page=1"
        if args == ["api", probe]:
            self.count_reads.append(args)
            self.count_timeouts.append(kwargs.get("timeout_seconds"))
            failed = any(k in probe for k in self.fail)
            if self.count_fail or failed:
                error = self.count_fail or f"gh: boom (HTTP {self.fail_status})"
                return subprocess.CompletedProcess(args, 1, "", error)
            live = len({a.get("id") for a in self.artifacts})
            total = live if self.live_total is None else self.live_total
            return ok({"total_count": total})
        self.calls.append(args)
        self.envs.append((args, kwargs.get("env_overrides")))

        def missing() -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(args, 1, "", "gh: Not Found (HTTP 404)")

        if args[:2] == ["api", "graphql"]:
            if "graphql" in self.fail:
                return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
            if any("userContentEdits" in a for a in args) and self.relink is not None:
                if self.relink == "error":
                    return subprocess.CompletedProcess(
                        args, 1, "", "gh: boom (HTTP 502)"
                    )
                return ok({"data": {"repository": {"pullRequest": self.relink}}})
            if any("issueOrPullRequest" in a for a in args):
                n = int(next(a for a in args if a.startswith("n="))[2:])
                if n not in self.refs:
                    # GitHub's answer for a number that names nothing, as a
                    # live read of a missing number returned it: gh exits 1.
                    missing = {
                        "data": {"repository": {"issueOrPullRequest": None}},
                        "errors": [
                            {
                                "type": "NOT_FOUND",
                                "path": ["repository", "issueOrPullRequest"],
                            }
                        ],
                    }
                    return subprocess.CompletedProcess(
                        args, 1, json.dumps(missing), "gh: Could not resolve"
                    )
                kind = self.refs[n]
                if kind == "error":
                    return subprocess.CompletedProcess(
                        args, 1, "", "gh: boom (HTTP 502)"
                    )
                if kind == "errors":
                    # gh exits 0 on an answer that carries data and errors.
                    return ok(
                        {
                            "data": {"repository": {"issueOrPullRequest": None}},
                            "errors": [{"type": "INTERNAL"}],
                        }
                    )
                if kind == "no-repository":
                    return ok({"data": {}})
                if kind == "null":
                    return ok({"data": {"repository": {"issueOrPullRequest": None}}})
                node = (
                    {"__typename": "PullRequest"}
                    if kind == "PullRequest"
                    else {"__typename": "Issue"} | self.issue(n, kind)
                )
                return ok({"data": {"repository": {"issueOrPullRequest": node}}})
            nodes = [self.issue(n, repo) for n, repo in self.closing]
            refs = {"totalCount": self.closing_total or len(nodes), "nodes": nodes}
            pull = {"body": self.body, "closingIssuesReferences": refs}
            return ok({"data": {"repository": {"pullRequest": pull}}})
        return self.rest(args, ok, missing, kwargs)

    def issue(self, n: int, repo: str) -> dict[str, Any]:
        return {
            "number": n,
            "lastEditedAt": self.closing_edited.get(n),
            "repository": {"nameWithOwner": repo},
            "labels": {
                "totalCount": self.labels_total.get(n, len(self.labels.get(n, []))),
                "nodes": [{"name": name} for name in self.labels.get(n, [])],
            },
            "comments": {
                "totalCount": self.comments_total.get(
                    n, len(self.closing_comments.get(n, []))
                ),
                "nodes": self.closing_comments.get(n, []),
            },
            "closedByPullRequestsReferences": {
                "totalCount": self.closers_total.get(
                    n, len(self.closers.get(n, [(PR, REPO)]))
                ),
                "nodes": [
                    {
                        "number": pr,
                        "state": self.closer_states.get(
                            pr, "OPEN" if pr == PR else "CLOSED"
                        ),
                        "author": self.closer_authors.get(pr),
                        "repository": {"nameWithOwner": repo},
                    }
                    for pr, repo in self.closers.get(n, [(PR, REPO)])
                ],
            },
            "timelineItems": {
                "totalCount": self.mentions_total.get(n, len(self.mentions.get(n, []))),
                "nodes": [
                    {
                        "source": {}
                        if source is None
                        else {
                            "number": source[0],
                            "repository": {"nameWithOwner": source[1]},
                        }
                    }
                    for source in self.mentions.get(n, [])
                ],
            },
        }

    def rest(
        self, args: list[str], ok: Any, missing: Any, kwargs: dict[str, Any]
    ) -> subprocess.CompletedProcess[str]:
        if args[:2] == ["run", "download"]:
            name, target = args[args.index("-n") + 1], args[args.index("-D") + 1]
            if name not in self.records:
                return missing()
            pathlib.Path(target, "verdict.json").write_text(
                json.dumps(self.records[name])
            )
            return ok("")
        path = next(a for a in args if a.startswith("repos/"))
        kind = next((k for k in self.fail if k in path), None)
        if kind:
            return subprocess.CompletedProcess(
                args,
                1,
                b"" if kwargs.get("binary") else "",
                f"gh: boom (HTTP {self.fail_status})",
            )
        zips = f"repos/{REPO}/actions/artifacts/"
        if path.startswith(zips) and path.endswith("/zip"):
            assert kwargs.get("binary") is True, args
            artifact_id = int(path[len(zips) : -len("/zip")])
            name = next(
                (a["name"] for a in self.artifacts if a.get("id") == artifact_id), None
            )
            if name not in self.records:
                return subprocess.CompletedProcess(
                    args, 1, b"", "gh: Not Found (HTTP 404)"
                )
            return subprocess.CompletedProcess(args, 0, zipped(self.records[name]), "")
        if found := re.fullmatch(rf"repos/{REPO}/actions/artifacts/([0-9]+)", path):
            # One artifact by id, as GitHub's "Get an artifact" answers.
            held = [a for a in self.artifacts if a.get("id") == int(found[1])]
            return ok(held[0]) if held else missing()
        by_name = re.fullmatch(
            rf"repos/{REPO}/actions/artifacts\?name=([^&]+)&per_page=100", path
        )
        if by_name:
            # Every artifact with exactly that name, as GitHub's filter answers.
            held = [a for a in self.artifacts if a.get("name") == by_name[1]]
            return ok({"total_count": len(held), "artifacts": held})
        prefix = f"repos/{REPO}/actions/artifacts?per_page="
        if path.startswith(prefix) and "&page=" in path:
            if self.page_fail:
                return subprocess.CompletedProcess(args, 1, "", self.page_fail)
            size, page = (int(v) for v in path[len(prefix) :].split("&page="))
            ordered = sorted(self.artifacts, key=lambda a: -a.get("id", 0))
            return ok(
                {
                    "total_count": len({a.get("id") for a in self.artifacts})
                    if self.live_total is None
                    else self.live_total,
                    "artifacts": ordered[(page - 1) * size : page * size],
                }
            )
        if path == f"repos/{REPO}/actions/artifacts?per_page=100":
            listed = self.listed()
            pages = [listed[i : i + 2] for i in range(0, len(listed), 2)]
            return ok(
                [{"total_count": len(self.artifacts), "artifacts": p} for p in pages]
                or [{"total_count": 0, "artifacts": []}]
            )
        if path == f"repos/{REPO}/pulls/{PR}/commits?per_page=100":
            return ok([[{"sha": sha} for sha in self.commits]])
        if found := re.fullmatch(rf"repos/{REPO}/pulls/([0-9]+)", path):
            n = int(found[1])
            return ok(
                {
                    "number": n,
                    "state": "closed",
                    "merged_at": None,
                    "closed_at": None,
                    "base": {"ref": "main", "sha": MAIN_SHA},
                    "head": {"ref": "feat/other", "sha": UNRELATED},
                }
                | self.pulls.get(n, {})
            )
        if "Accept: application/vnd.github.diff" in args:
            sha = path.removeprefix(f"repos/{REPO}/compare/main...")
            if sha not in self.diffs:
                return missing()
            return subprocess.CompletedProcess(args, 0, self.diffs[sha], "")
        if path == f"repos/{REPO}/git/ref/heads/main":
            return ok({"ref": "refs/heads/main", "object": {"sha": MAIN_SHA}})
        if path.startswith(f"repos/{REPO}/contents/"):
            # Read at main's tip only, never by the branch's name.
            return ok(self.actors) if path.endswith(f"?ref={MAIN_SHA}") else missing()
        issues = f"repos/{REPO}/issues/"
        if path.startswith(issues) and path.endswith("/timeline?per_page=100"):
            n = int(path[len(issues) :].split("/")[0])
            return ok([self.timeline.get(n, [])])
        collaborators = f"repos/{REPO}/collaborators/"
        if path.startswith(collaborators) and path.endswith("/permission"):
            login = path[len(collaborators) :].split("/")[0]
            if login not in self.permissions:
                return missing()
            return ok({"permission": self.permissions[login]})
        checks = re.fullmatch(
            rf"repos/{REPO}/actions/workflows/pr-require-checks\.yml/runs"
            r"\?head_sha=([0-9a-f]{40})&event=pull_request&per_page=100",
            path,
        )
        if checks:
            if checks[1] not in self.checks_runs:
                return missing()
            listed = self.checks_runs[checks[1]]
            total = self.checks_total.get(checks[1], len(listed))
            return ok({"total_count": total, "workflow_runs": listed})
        jobs = re.fullmatch(
            rf"repos/{REPO}/actions/runs/([0-9]+)/jobs\?filter=latest&per_page=100",
            path,
        )
        if jobs:
            found_jobs = self.jobs.get(int(jobs[1]))
            return missing() if found_jobs is None else ok(found_jobs)
        prefix = f"repos/{REPO}/actions/runs/"
        if path.startswith(prefix):
            run_id = int(path[len(prefix) :])
            return ok(self.runs[run_id]) if run_id in self.runs else missing()
        compare = f"repos/{REPO}/compare/"
        if path.startswith(compare):
            sha = path[len(compare) :].split("...")[0]
            return ok({"status": "ahead" if sha in self.on_main else "diverged"})
        raise AssertionError(f"unexpected gh call: {args}")


class OrderedSet(set[str]):
    """A set that iterates in the order given, standing in for whatever order
    another process's string hashing gives."""

    def __init__(self, items: list[str]):
        super().__init__(items)
        self.order = items

    def __iter__(self) -> Iterator[str]:
        return iter(self.order)


def passing(*extra: dict[str, Any], runs: dict[int, Any] | None = None) -> FakeGitHub:
    """A counted pass at the head (run 1) beside `extra` artifacts."""
    return FakeGitHub(
        [artifact(named(HEAD, "pass"), 1), *extra],
        {1: run(1), **(runs or {})},
        {named(HEAD, "pass"): record()},
    )


def read(fake: FakeGitHub, pr: dict[str, Any] | None = None) -> ve.Evidence:
    # The single-page patch too, for modules that import this helper without
    # this module's setUpModule.
    with (
        mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
        mock.patch.object(ve, "gh_api_with_headers", side_effect=_page_with_date),
    ):
        return ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, pr or pull())


class VerdictAtTheCurrentHead(unittest.TestCase):
    def test_a_pass_allows(self) -> None:
        evidence = read(passing())
        self.assertIsNone(evidence.refusal)
        self.assertFalse(evidence.needs_human)

    def test_a_pass_with_notes_allows(self) -> None:
        fake = FakeGitHub(
            [artifact(named(HEAD, "pass-notes"), 1)],
            {1: run(1)},
            {named(HEAD, "pass-notes"): record()},
        )
        self.assertIsNone(read(fake).refusal)

    def test_a_fail_waits_for_a_fix_round_not_a_human(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 1)], {1: run(1)})
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertFalse(evidence.needs_human)

    def test_a_fail_beside_a_pass_at_the_same_head_blocks(self) -> None:
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_no_verdict_is_missing(self) -> None:
        self.assertEqual(read(FakeGitHub([], {})).refusal, "verify:missing")


class EveryPassAtTheHeadIsChecked(unittest.TestCase):
    """Several passes at one head are equivalent: each must allow, whatever
    order the listing returns them in, and a FAIL there still blocks."""

    def judge(self, second: dict[str, Any], *, reverse: bool) -> ve.Evidence:
        """A pass (run 1) and a pass-notes (run 2) whose record or run start
        is `second`'s, listed in that order or reversed."""
        items = [
            artifact(named(HEAD, "pass"), 1),
            artifact(named(HEAD, "pass-notes"), 2),
        ]
        fake = FakeGitHub(
            items[::-1] if reverse else items,
            {1: run(1), 2: run(2, **second.get("run", {}))},
            {
                named(HEAD, "pass"): record(),
                named(HEAD, "pass-notes"): record(**second.get("record", {})),
            },
        )
        fake.closing_edited = second.get("edited", {})
        return read(fake)

    def each_order(self, second: dict[str, Any]) -> set[str | None]:
        return {self.judge(second, reverse=r).refusal for r in (False, True)}

    def test_two_allowing_passes_allow(self) -> None:
        self.assertEqual(self.each_order({}), {None})

    def test_one_judged_before_a_spec_edit_is_superseded_either_way(self) -> None:
        # Run 2 started before the issue's edit; run 1, started after it,
        # judged the live spec and decides (`_newest`).
        second = {
            "run": {"run_started_at": "2026-10-13T00:00:00Z"},
            "edited": {7: "2026-10-14T00:00:00Z"},
        }
        self.assertEqual(self.each_order(second), {None})
        # The stale one alone refuses.
        second["edited"] = {7: "2026-10-15T00:00:01Z"}
        self.assertEqual(self.each_order(second), {"verify:spec-changed"})

    def test_one_recording_an_untrusted_spec_refuses_either_way(self) -> None:
        bot = {**TRUSTED_ISSUE, "author_type": "Bot", "author_id": 200}
        second = {"record": {"linked_issues": [bot]}}
        self.assertEqual(self.each_order(second), {"verify:untrusted-spec"})

    def test_a_changed_spec_is_reported_before_an_untrusted_one(self) -> None:
        # The README's order: the spec must be the judged one before its
        # authors are weighed. Both runs start together (so both decide):
        # run 2 records an untrusted spec, and both predate the issue's edit.
        bot = {**TRUSTED_ISSUE, "author_type": "Bot", "author_id": 200}
        second = {
            "record": {"linked_issues": [bot]},
            "edited": {7: "2026-10-15T06:00:00Z"},
        }
        self.assertEqual(self.each_order(second), {"verify:spec-changed"})

    def test_a_fail_beside_two_passes_blocks(self) -> None:
        for reverse in (False, True):
            with self.subTest(reverse=reverse):
                items = [
                    artifact(named(HEAD, "pass"), 1),
                    artifact(named(HEAD, "fail"), 3),
                    artifact(named(HEAD, "pass-notes"), 2),
                ]
                fake = FakeGitHub(
                    items[::-1] if reverse else items,
                    {1: run(1), 2: run(2), 3: run(3)},
                    {
                        named(HEAD, "pass"): record(),
                        named(HEAD, "pass-notes"): record(),
                    },
                )
                self.assertEqual(read(fake).refusal, "verify:fail")


class AVerdictForAnotherShaDoesNotCount(unittest.TestCase):
    def test_a_pass_at_an_earlier_head_is_missing_at_the_current_one(self) -> None:
        fake = FakeGitHub([artifact(named(EARLIER, "pass"), 1)], {1: run(1)})
        self.assertEqual(read(fake).refusal, "verify:missing")

    def test_another_prs_pass_at_this_head_does_not_count(self) -> None:
        # PR 4 and PR 411 share a prefix with 41; the name is parsed.
        names = (named(HEAD, "pass", 4), named(HEAD, "pass", 411))
        fake = FakeGitHub(
            [artifact(names[0], 1), artifact(names[1], 2)],
            {1: run(1), 2: run(2)},
            {name: record(number=int(name.split("-")[2])) for name in names},
        )
        self.assertEqual(read(fake).refusal, "verify:missing")


class AFailCountsUnderAnyNumber(unittest.TestCase):
    """Closing #41 and reopening the branch as another pull request must not
    re-roll a FAIL."""

    def test_a_fail_at_this_head_under_another_number_blocks(self) -> None:
        fake = passing(artifact(named(HEAD, "fail", 99), 2), runs={2: run(2)})
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_fail_at_one_of_this_prs_commits_under_another_number(self) -> None:
        fake = FakeGitHub([artifact(named(IN_PR, "fail", 99), 2)], {2: run(2)})
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertFalse(evidence.needs_human)

    def test_a_fail_recording_this_head_branch_under_another_number(self) -> None:
        name = named(UNRELATED, "fail", 99)
        fake = FakeGitHub([artifact(name, 2)], {2: run(2)})
        fake.records[name] = record(99, UNRELATED, verdict="fail")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_fail_on_another_branch_and_number_does_not_count(self) -> None:
        name = named(UNRELATED, "fail", 99)
        fake = passing(artifact(name, 2), runs={2: run(2)})
        fake.records[name] = record(99, UNRELATED, verdict="fail", head_ref="feat/y")
        self.assertIsNone(read(fake).refusal)

    def test_an_unrelated_fail_whose_record_cannot_be_read_blocks(self) -> None:
        fake = passing(artifact(named(UNRELATED, "fail", 99), 2), runs={2: run(2)})
        self.assertEqual(read(fake).refusal, "verify:unreadable")


class AnEarlierFailGoesToAHuman(unittest.TestCase):
    def test_a_fail_at_the_current_head_wins_over_an_earlier_fail(self) -> None:
        fake = FakeGitHub(
            [artifact(named(EARLIER, "fail"), 1), artifact(named(HEAD, "fail"), 2)],
            {1: run(1), 2: run(2)},
        )
        self.assertEqual(read(fake).refusal, "verify:fail")


class ACountedPassAtTheHeadClearsAnEarlierFail(unittest.TestCase):
    """An earlier head's FAIL stops holding once the current head has a
    counted pass that clears every spec check and whose run started after
    every earlier FAIL's run; without one it still holds."""

    @staticmethod
    def earlier_fail(started: Any = OLDER_START, *extra: dict[str, Any]) -> FakeGitHub:
        """A pass at the head (run 1, started `RUN_STARTED`) and a FAIL at an
        earlier head (run 2, started `started`)."""
        return passing(
            artifact(named(EARLIER, "fail"), 2),
            *extra,
            runs={2: judged(2, started)},
        )

    def test_an_earlier_fail_and_an_allowing_pass_at_the_head_allow(self) -> None:
        evidence = read(self.earlier_fail())
        self.assertIsNone(evidence.refusal)
        self.assertEqual(evidence.report()["earlierFails"], [EARLIER])

    def test_a_fail_started_after_the_pass_refuses(self) -> None:
        # Head B passed, A was pushed and failed, the branch went back to B.
        fake = self.earlier_fail("2026-10-15T00:00:01Z")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_re_attempted_earlier_pass_does_not_clear_a_later_fail(self) -> None:
        # Run 39652492098's record: attempt 2 keeps the run's created_at and
        # moves run_started_at later. The pass run was created before the
        # FAIL's and re-attempted after it.
        fake = self.earlier_fail("2026-10-15T00:00:01Z")
        fake.runs[1] = run(
            1,
            created_at=RUN_STARTED,
            run_started_at="2026-10-15T00:00:02Z",
            run_attempt=2,
        )
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_re_attempt_created_after_the_fail_clears_it(self) -> None:
        fake = self.earlier_fail()
        fake.runs[1] = run(1, run_started_at="2026-10-15T00:05:00Z", run_attempt=2)
        self.assertIsNone(read(fake).refusal)

    def test_a_run_record_whose_id_is_true_counts_nothing(self) -> None:
        # True == 1 in Python, so the id must be an int, not equal to one.
        fake = self.earlier_fail()
        fake.runs[1] = {**run(1), "id": True}
        self.assertNotEqual(read(fake).refusal, None)
        fake = FakeGitHub(
            [artifact(named(HEAD, "fail"), 1)], {1: {**run(1), "id": True}}
        )
        self.assertEqual(read(fake).refusal, "verify:missing")

    def test_a_fail_started_with_the_pass_refuses(self) -> None:
        fake = self.earlier_fail(RUN_STARTED)
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_fail_with_no_start_time_refuses(self) -> None:
        for started in (None, "yesterday"):
            with self.subTest(started=started):
                fake = self.earlier_fail(started)
                self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_an_earlier_fail_with_no_verdict_at_the_head_waits(self) -> None:
        # The head a fix round pushed, before the verifier judges it.
        fake = FakeGitHub([artifact(named(EARLIER, "fail"), 2)], {2: run(2)})
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertFalse(evidence.needs_human)

    def test_a_pass_from_an_unfinished_run_does_not_clear_it(self) -> None:
        fake = self.earlier_fail()
        fake.runs[1] = run(1, status="in_progress", conclusion=None)
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_fail_at_the_head_still_refuses_beside_the_pass(self) -> None:
        fake = self.earlier_fail(OLDER_START, artifact(named(HEAD, "fail"), 3))
        fake.runs[3] = run(3)
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_pass_on_a_changed_spec_still_refuses(self) -> None:
        fake = self.earlier_fail()
        fake.closing = [(8, REPO)]
        self.assertEqual(read(fake).refusal, "verify:spec-changed")

    def test_a_pass_on_an_untrusted_spec_still_refuses(self) -> None:
        fake = self.earlier_fail()
        fake.records[named(HEAD, "pass")] = record(
            linked_issues=[{**TRUSTED_ISSUE, "author_type": "Bot", "author_id": 200}]
        )
        self.assertEqual(read(fake).refusal, "verify:untrusted-spec")

    def test_an_unreadable_tied_fail_refuses_without_a_human(self) -> None:
        # Run 7 is not in the fake, so the tied FAIL at the head is unread.
        fake = self.earlier_fail(OLDER_START, artifact(named(HEAD, "fail"), 7))
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertFalse(evidence.needs_human)


class AFailCarriesToAHeadOfTheSameChange(unittest.TestCase):
    """A pass clears an earlier head's FAIL only when the pull request's own
    change at the head (the stable patch id of its diff from the merge base
    with main) differs from its change at every FAILed head: a head that only
    merges main, or adds an empty commit, keeps the FAIL (owner decision
    2026-10-21), and a diff that holds no change keeps it too; one that
    cannot be read refuses `verify:unreadable`."""

    earlier_fail = staticmethod(ACountedPassAtTheHeadClearsAnEarlierFail.earlier_fail)

    def diff_reads(self, fake: FakeGitHub) -> list[str]:
        return [c[-1] for c in fake.calls if "Accept: application/vnd.github.diff" in c]

    def test_a_head_that_only_merges_main_still_refuses(self) -> None:
        fake = self.earlier_fail()
        # Main's merge moved the hunk down; the change itself is the same.
        fake.diffs[EARLIER] = change("fix", at=1)
        fake.diffs[HEAD] = change("fix", at=40)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertFalse(evidence.needs_human)

    def test_a_base_merge_that_edits_a_line_beside_the_fix_still_refuses(
        self,
    ) -> None:
        # Main changed the context line next to the fix; the fix is the same.
        fake = self.earlier_fail()
        fake.diffs[EARLIER] = change("fix", before="one")
        fake.diffs[HEAD] = change("fix", at=40, before="one, edited on main")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_whitespace_only_difference_still_refuses(self) -> None:
        fake = self.earlier_fail()
        fake.diffs[EARLIER] = change("x = f(a, b)")
        fake.diffs[HEAD] = change("x  =  f(a,b) ")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_the_same_lines_in_another_file_allow(self) -> None:
        fake = self.earlier_fail()
        fake.diffs[EARLIER] = change("fix")
        fake.diffs[HEAD] = change("fix", path="other.txt")
        self.assertIsNone(read(fake).refusal)

    def test_a_binary_change_allows(self) -> None:
        fake = self.earlier_fail()
        fake.diffs[EARLIER] = change("fix")
        fake.diffs[HEAD] = change("fix") + (
            "diff --git a/logo.png b/logo.png\n"
            "index 3333333..4444444 100644\n"
            "Binary files a/logo.png and b/logo.png differ\n"
        )
        self.assertIsNone(read(fake).refusal)

    def test_a_head_with_a_real_change_allows(self) -> None:
        fake = self.earlier_fail()
        fake.diffs[EARLIER] = change("fix", at=1)
        fake.diffs[HEAD] = change("better fix", at=40)
        self.assertIsNone(read(fake).refusal)
        self.assertEqual(
            sorted(self.diff_reads(fake)),
            sorted(f"repos/{REPO}/compare/main...{s}" for s in (HEAD, EARLIER)),
        )

    def test_one_failed_head_of_the_same_change_among_others_refuses(self) -> None:
        fake = self.earlier_fail(OLDER_START, artifact(named(IN_PR, "fail"), 3))
        fake.runs[3] = judged(3, OLDER_START)
        self.assertIsNone(read(fake).refusal)
        fake.diffs[IN_PR] = fake.diffs[HEAD]
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_change_with_no_lines_keeps_the_fail(self) -> None:
        for sha in (EARLIER, HEAD):
            with self.subTest(sha=sha):
                fake = self.earlier_fail()
                fake.diffs[sha] = ""
                self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_head_github_no_longer_has_keeps_the_fail(self) -> None:
        # A compare that answers 404 (a garbage-collected or force-pushed-away
        # head) holds no readable change, which no later read will find.
        for sha in (EARLIER, HEAD):
            with self.subTest(sha=sha):
                fake = self.earlier_fail()
                del fake.diffs[sha]
                evidence = read(fake)
                self.assertEqual(evidence.refusal, "verify:earlier-fail")
                self.assertFalse(evidence.needs_human)

    def test_the_verdict_does_not_depend_on_the_order_of_failed_heads(self) -> None:
        # EARLIER holds the head's own change; UNRELATED's read fails.
        fake = self.earlier_fail()
        fake.diffs[EARLIER] = fake.diffs[HEAD]
        fake.fail = {f"compare/main...{UNRELATED}"}
        outcomes = set()
        for order in ([EARLIER, UNRELATED], [UNRELATED, EARLIER]):
            with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
                reader = ve.Reader(REPO, "main", now=NOW)
                try:
                    outcomes.add(reader._change_differs(HEAD, OrderedSet(order)))
                except ve._Unreadable:
                    outcomes.add("unreadable")
        self.assertEqual(len(outcomes), 1, outcomes)

    def test_a_head_that_only_adds_blank_lines_refuses(self) -> None:
        fake = self.earlier_fail()
        fake.diffs[HEAD] = change("")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_response_that_is_not_a_diff_refuses(self) -> None:
        fake = self.earlier_fail()
        fake.diffs[HEAD] = "<html>rate limited</html>\n"
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")


class AWholeSpecPassClearsASliceFailOnTheSameChange(unittest.TestCase):
    """A FAIL judged as a `Refs:` slice is cleared at a head of the same
    change by passes judged with the issue closed, which the verifier judges
    against the whole spec; nothing else of the same change clears it."""

    def same_change(
        self, fail_kind: Any, pass_kind: Any, *, live_refs: bool = False
    ) -> FakeGitHub:
        """A FAIL at EARLIER recording `fail_kind`, a pass at the head
        recording `pass_kind` (None: the key is absent), the same change at
        both heads, and the issue linked now by `Refs:` when `live_refs`."""
        fake = ACountedPassAtTheHeadClearsAnEarlierFail.earlier_fail()
        fake.diffs[EARLIER] = fake.diffs[HEAD]
        kinds = {"spec_kind": pass_kind} if pass_kind is not None else {}
        fake.records[named(HEAD, "pass")] = record(**kinds)
        fails = {"spec_kind": fail_kind} if fail_kind is not None else {}
        fake.records[named(EARLIER, "fail")] = record(
            sha=EARLIER, verdict="fail", **fails
        )
        if live_refs:
            fake.closing = []
            fake.body = "Refs: #7"
            fake.refs = {7: REPO}
        return fake

    def test_a_closes_pass_clears_a_refs_fail_of_the_same_change(self) -> None:
        evidence = read(self.same_change("refs", "closes"))
        self.assertIsNone(evidence.refusal)
        self.assertEqual(evidence.report()["earlierFails"], [EARLIER])

    def test_a_refs_pass_never_clears_a_closes_fail_of_the_same_change(
        self,
    ) -> None:
        # The live link is `Refs:`, so the refs pass would otherwise allow.
        fake = self.same_change("closes", "refs", live_refs=True)
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_refs_pass_never_clears_a_refs_fail_of_the_same_change(
        self,
    ) -> None:
        fake = self.same_change("refs", "refs", live_refs=True)
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_closes_pass_never_clears_a_closes_fail_of_the_same_change(
        self,
    ) -> None:
        self.assertEqual(
            read(self.same_change("closes", "closes")).refusal, "verify:earlier-fail"
        )

    def test_a_spec_kind_that_is_missing_or_unknown_keeps_the_fail(self) -> None:
        # A record from before the kind was written reads as `closes` where a
        # pass is checked against the live link; here it clears nothing.
        for fail_kind, pass_kind in (
            (None, "closes"),
            ("refs", None),
            ("Refs", "closes"),
            ("refs", "pull-request"),
            (["refs"], "closes"),
        ):
            with self.subTest(fail=fail_kind, passed=pass_kind):
                fake = self.same_change(fail_kind, pass_kind)
                self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_fail_record_that_cannot_be_read_keeps_the_fail(self) -> None:
        fake = self.same_change("refs", "closes")
        del fake.records[named(EARLIER, "fail")]
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")
        fake = self.same_change("refs", "closes")
        fake.fail = {"actions/artifacts/20/zip"}
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_fail_record_with_no_linked_issue_keeps_the_fail(self) -> None:
        for linked in ([], None, "7", [{"number": "7"}], [7]):
            with self.subTest(linked=linked):
                fake = self.same_change("refs", "closes")
                fake.records[named(EARLIER, "fail")]["linked_issues"] = linked
                self.assertEqual(read(fake).refusal, "verify:earlier-fail")
        fake = self.same_change("refs", "closes")
        del fake.records[named(EARLIER, "fail")]["linked_issues"]
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def closing_another(self, *numbers: int) -> FakeGitHub:
        """A refs FAIL recording issue 7, and a closes pass at the head that
        records, and now closes, `numbers` instead."""
        fake = self.same_change("refs", "closes")
        fake.closing = [(n, REPO) for n in numbers]
        fake.records[named(HEAD, "pass")] = record(
            spec_kind="closes",
            linked_issues=[{**TRUSTED_ISSUE, "number": n} for n in numbers],
        )
        return fake

    def test_a_closes_pass_of_the_refs_issue_clears(self) -> None:
        self.assertIsNone(read(self.closing_another(7)).refusal)

    def test_a_closes_pass_of_another_issue_keeps_the_fail(self) -> None:
        # Failed as a slice of one issue, then relinked to close a different
        # issue on the same diff.
        self.assertEqual(read(self.closing_another(8)).refusal, "verify:earlier-fail")

    def test_a_closes_pass_of_more_issues_keeps_the_fail(self) -> None:
        self.assertEqual(
            read(self.closing_another(7, 8)).refusal, "verify:earlier-fail"
        )

    def test_a_pass_whose_linkage_cannot_be_read_keeps_the_fail(self) -> None:
        for linked in ([], None, "7", [{"number": "7"}], [{"number": True}], [7]):
            with self.subTest(linked=linked):
                fake = self.same_change("refs", "closes")
                fake.records[named(HEAD, "pass")]["linked_issues"] = linked
                self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_fail_record_of_another_judgment_keeps_the_fail(self) -> None:
        for field_name, value in (
            ("pr", 99),
            ("head_sha", HEAD),
            ("verdict", "pass"),
        ):
            with self.subTest(field=field_name):
                fake = self.same_change("refs", "closes")
                fake.records[named(EARLIER, "fail")][field_name] = value
                self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_one_closes_fail_among_refs_fails_at_the_head_keeps_it(self) -> None:
        fake = self.same_change("refs", "closes")
        name = named(EARLIER, "fail") + "-" + "0" * 16
        fake.artifacts.append(artifact(name, 3))
        fake.runs[3] = judged(3, OLDER_START)
        fake.records[name] = record(sha=EARLIER, verdict="fail", spec_kind="closes")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_the_fail_must_still_precede_the_pass(self) -> None:
        fake = self.same_change("refs", "closes")
        fake.runs[2] = judged(2, "2026-10-15T00:00:01Z")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")


# Times between the FAIL's creation (OLDER_START) and the pass's start
# (RUN_STARTED), while the pass ran, its completion, and after it.
RELINK_AT = "2026-10-14T12:00:00Z"
PASS_RUNNING = "2026-10-15T00:05:00Z"
PASS_DONE = "2026-10-15T00:10:00Z"
AFTER_PASS = "2026-10-15T12:00:00Z"


def relink_answer(
    edits: list[tuple[str, Any]] = (),
    events: list[tuple[str, Any]] = (),
    *,
    edits_total: int | None = None,
    events_filtered: int | None = None,
) -> dict[str, Any]:
    """The pull request's RELINK_QUERY answer: body edits (newest first, then
    the original text, stamped before the FAIL, by the lanes App that opened
    the pull request) and issue connect or disconnect events, as a live read
    of an edited pull request answered, with identifying details changed."""
    nodes = [{"editedAt": at, "editor": who} for at, who in edits]
    nodes.append({"editedAt": "2026-10-10T00:00:00Z", "editor": LANES_ACTOR})
    timeline = [{"createdAt": at, "actor": who} for at, who in events]
    return {
        "userContentEdits": {
            "totalCount": len(nodes) if edits_total is None else edits_total,
            "nodes": nodes,
        },
        "timelineItems": {
            "filteredCount": len(timeline)
            if events_filtered is None
            else events_filtered,
            "nodes": timeline,
        },
    }


class ARelinkByPeopleSupersedesAFailAtItsHead(unittest.TestCase):
    """A FAIL at a head stops refusing once the pull request's linked issues
    changed there and it passed again, when every body edit and issue connect
    or disconnect from the FAIL's creation to the pass's start was a trusted
    person's; any other actor, a read that fails or the same linked issues
    keep it. It still counts toward the FAIL cap, and a merge-only head
    carries it forward unless it was superseded at its own head."""

    @staticmethod
    def relinked(sha: str = HEAD) -> FakeGitHub:
        """A FAIL at `sha` (run 2, created OLDER_START) that recorded no
        linked issue, the pull request's title and body being its spec, and a
        pass there (run 1, RUN_STARTED) that records issue 7, which the pull
        request closes now; a person connected it and edited the body."""
        fake = FakeGitHub(
            [artifact(named(sha, "pass"), 1), artifact(named(sha, "fail"), 2)],
            {1: run(1, updated_at=PASS_DONE), 2: judged(2, OLDER_START)},
            {
                named(sha, "pass"): record(sha=sha),
                named(sha, "fail"): record(sha=sha, verdict="fail", linked_issues=[]),
            },
        )
        fake.relink = relink_answer([(RELINK_AT, HUMAN)], [(RELINK_AT, HUMAN)])
        return fake

    def test_a_relink_by_people_only_lets_the_pass_decide(self) -> None:
        self.assertIsNone(read(self.relinked()).refusal)
        # The pass still decides: an untrusted spec refuses as it would alone.
        fake = self.relinked()
        bot = {**TRUSTED_ISSUE, "author_type": "Bot", "author_id": 200}
        fake.records[named(HEAD, "pass")] = record(linked_issues=[bot])
        self.assertEqual(read(fake).refusal, "verify:untrusted-spec")

    def test_the_lanes_app_or_an_unnamed_actor_in_the_window_keeps_the_fail(
        self,
    ) -> None:
        outsider = {"__typename": "User", "login": "outsider", "databaseId": 999}
        for label, answer in (
            (
                "App edit",
                relink_answer([(RELINK_AT, LANES_ACTOR)], [(RELINK_AT, HUMAN)]),
            ),
            (
                "App connect",
                relink_answer([(RELINK_AT, HUMAN)], [(RELINK_AT, LANES_ACTOR)]),
            ),
            ("ghost edit", relink_answer([(RELINK_AT, None)])),
            ("outsider connect", relink_answer([], [(RELINK_AT, outsider)])),
            ("at the FAIL's creation", relink_answer([(OLDER_START, LANES_ACTOR)])),
            ("at the pass's start", relink_answer([], [(RUN_STARTED, LANES_ACTOR)])),
            # The pass's run reads the linked issues after it starts.
            ("while the pass ran", relink_answer([], [(PASS_RUNNING, LANES_ACTOR)])),
            ("at the pass's completion", relink_answer([], [(PASS_DONE, LANES_ACTOR)])),
        ):
            with self.subTest(label):
                fake = self.relinked()
                fake.relink = answer
                self.assertEqual(read(fake).refusal, "verify:fail")

    def test_the_apps_acts_outside_the_window_do_not_count(self) -> None:
        # Its original text before the FAIL, and an edit after the pass began.
        fake = self.relinked()
        fake.relink = relink_answer([(AFTER_PASS, LANES_ACTOR), (RELINK_AT, HUMAN)])
        self.assertIsNone(read(fake).refusal)

    def test_a_relink_that_cannot_be_read_keeps_the_fail(self) -> None:
        for label, answer in (
            ("failed read", "error"),
            ("no pull request", {}),
            ("edits cut short", relink_answer([(RELINK_AT, HUMAN)], edits_total=101)),
            (
                "events cut short",
                relink_answer([], [(RELINK_AT, HUMAN)], events_filtered=2),
            ),
            ("timeless event", relink_answer([], [(None, HUMAN)])),
            # Only the original text, before the FAIL: the link changed some
            # way the read cannot see (an issue deleted or moved).
            ("nothing in the window", relink_answer()),
            ("a pass run with no completion time", relink_answer([(RELINK_AT, HUMAN)])),
        ):
            with self.subTest(label):
                fake = self.relinked()
                fake.relink = answer
                if label == "a pass run with no completion time":
                    fake.runs[1] = run(1, updated_at=None)
                self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_fail_or_pass_record_that_cannot_be_read_keeps_the_fail(self) -> None:
        for name in (named(HEAD, "fail"), named(HEAD, "pass")):
            with self.subTest(name):
                fake = self.relinked()
                fake.records[name]["linked_issues"] = None
                self.assertEqual(read(fake).refusal, "verify:fail")

    def test_the_same_linked_issues_with_no_body_edit_keep_the_fail(self) -> None:
        # A person's connect alone, no body edit: a body-edit re-judgment
        # needs one (ATrustedBodyEditSupersedesAFailAtItsHead).
        fake = self.relinked()
        fake.records[named(HEAD, "fail")]["linked_issues"] = [TRUSTED_ISSUE]
        fake.relink = relink_answer([], [(RELINK_AT, HUMAN)])
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_pass_created_before_the_fail_keeps_it(self) -> None:
        fake = self.relinked()
        fake.runs[2] = judged(2, AFTER_PASS)
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_another_prs_fail_at_the_head_keeps_it(self) -> None:
        fake = self.relinked()
        name = named(HEAD, "fail", 99)
        fake.artifacts.append(artifact(name, 3))
        fake.runs[3] = judged(3, OLDER_START)
        fake.records[name] = record(99, verdict="fail", linked_issues=[])
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_superseded_fail_still_counts_toward_the_cap(self) -> None:
        fake = self.relinked()
        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
            mock.patch.object(ve, "gh_api_with_headers", side_effect=_page_with_date),
        ):
            reader = ve.Reader(REPO, "main", now=NOW, max_fails=1)
            refusal = reader.evidence(PR, HEAD, pull()).refusal
        self.assertEqual(refusal, "verify:repeated-fail")

    def merge_only(self, *, superseded: bool) -> FakeGitHub:
        """The relinked FAIL and pass at EARLIER, and a head that only merged
        main since (the same change), with a pass of its own (run 3) that
        records issue 7; the FAIL superseded at EARLIER or not."""
        fake = self.relinked(EARLIER)
        fake.diffs[EARLIER] = fake.diffs[HEAD]
        fake.artifacts.append(artifact(named(HEAD, "pass"), 3))
        fake.runs[3] = judged(3, AFTER_PASS)
        fake.records[named(HEAD, "pass")] = record()
        if not superseded:
            fake.relink = relink_answer([], [(RELINK_AT, LANES_ACTOR)])
        return fake

    def test_a_merge_only_head_follows_the_failed_heads_verdict(self) -> None:
        evidence = read(self.merge_only(superseded=True))
        self.assertIsNone(evidence.refusal)
        self.assertEqual(evidence.report()["earlierFails"], [EARLIER])
        self.assertEqual(
            read(self.merge_only(superseded=False)).refusal, "verify:earlier-fail"
        )

    def test_a_merge_only_head_with_no_pass_at_the_failed_head_carries_it(
        self,
    ) -> None:
        fake = self.merge_only(superseded=True)
        fake.artifacts = [
            a for a in fake.artifacts if a["name"] != named(EARLIER, "pass")
        ]
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")


class ATrustedBodyEditSupersedesAFailAtItsHead(unittest.TestCase):
    """A FAIL at a head stops refusing once a trusted person edited the pull
    request's body there and it passed again under the same linked issues,
    when from the last FAIL's creation to the pass run's completion there is
    at least one body edit and every body edit and issue connect or
    disconnect was a trusted person's. The rule is the owner's (a body fix
    after a FAIL is judged at the same head); the lanes App, another actor,
    a connect alone, an edit before the last FAIL or a failed read keep it."""

    @staticmethod
    def edited(answer: dict[str, Any] | None = None) -> FakeGitHub:
        """A FAIL at HEAD (run 2, created OLDER_START) and a pass there (run
        1, RUN_STARTED), both recording issue 7; a person edited the body
        between them."""
        fake = FakeGitHub(
            [artifact(named(HEAD, "pass"), 1), artifact(named(HEAD, "fail"), 2)],
            {1: run(1, updated_at=PASS_DONE), 2: judged(2, OLDER_START)},
            {
                named(HEAD, "pass"): record(),
                named(HEAD, "fail"): record(verdict="fail"),
            },
        )
        fake.relink = answer or relink_answer([(RELINK_AT, HUMAN)])
        return fake

    def test_a_persons_body_edit_lets_the_pass_decide(self) -> None:
        self.assertIsNone(read(self.edited()).refusal)

    def test_any_other_actor_or_no_body_edit_keeps_the_fail(self) -> None:
        # The paired case: the same window with only a person's edit clears.
        self.assertIsNone(
            read(self.edited(relink_answer([(RELINK_AT, HUMAN)]))).refusal
        )
        outsider = {"__typename": "User", "login": "outsider", "databaseId": 999}
        for label, answer in (
            ("App edit", relink_answer([(RELINK_AT, LANES_ACTOR)])),
            ("outsider edit", relink_answer([(RELINK_AT, outsider)])),
            ("ghost edit", relink_answer([(RELINK_AT, None)])),
            (
                "person edit, App connect",
                relink_answer([(RELINK_AT, HUMAN)], [(RELINK_AT, LANES_ACTOR)]),
            ),
            ("person connect only", relink_answer([], [(RELINK_AT, HUMAN)])),
            ("nothing in the window", relink_answer()),
            ("edits cut short", relink_answer([(RELINK_AT, HUMAN)], edits_total=101)),
            ("failed read", "error"),
        ):
            with self.subTest(label):
                self.assertEqual(read(self.edited(answer)).refusal, "verify:fail")

    def test_an_edit_before_the_last_fail_keeps_it(self) -> None:
        # The person's edit falls between the two FAILs: the second judged it.
        fake = self.edited()
        fake.artifacts.append(artifact(named(HEAD, "fail"), 3))
        fake.runs[3] = judged(3, "2026-10-14T18:00:00Z")
        self.assertEqual(read(fake).refusal, "verify:fail")
        # An edit after the second FAIL lets the pass decide.
        fake.relink = relink_answer(
            [("2026-10-14T20:00:00Z", HUMAN), (RELINK_AT, HUMAN)]
        )
        self.assertIsNone(read(fake).refusal)

    def test_the_report_names_a_fail_superseded_at_the_head(self) -> None:
        # pr-unblock resolves that FAIL's fail-note threads on this field
        # alone (feedback-dispatch.mjs), so it is true only where the FAIL at
        # the head gave way.
        self.assertIs(read(self.edited()).report()["supersededAtHead"], True)
        for label, answer in (
            ("App edit", relink_answer([(RELINK_AT, LANES_ACTOR)])),
            ("person connect only", relink_answer([], [(RELINK_AT, HUMAN)])),
            ("failed read", "error"),
        ):
            with self.subTest(label):
                evidence = read(self.edited(answer))
                self.assertEqual(evidence.refusal, "verify:fail")
                self.assertIs(evidence.report()["supersededAtHead"], False)

    def test_the_report_names_no_fail_superseded_elsewhere_or_capped(self) -> None:
        # Superseded at an earlier head only: nothing at this head gave way.
        merge_only = ARelinkByPeopleSupersedesAFailAtItsHead().merge_only(
            superseded=True
        )
        self.assertIs(read(merge_only).report()["supersededAtHead"], False)
        # At the cap the FAIL at the head is never judged superseded.
        fake = self.edited()
        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
            mock.patch.object(ve, "gh_api_with_headers", side_effect=_page_with_date),
        ):
            reader = ve.Reader(REPO, "main", now=NOW, max_fails=1)
            evidence = reader.evidence(PR, HEAD, pull())
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertIs(evidence.report()["supersededAtHead"], False)


def rename(old: str, new: str) -> str:
    """A pure rename as GitHub's compare diff shows it: no hunk."""
    return (
        f"diff --git a/{old} b/{new}\n"
        "similarity index 100%\n"
        f"rename from {old}\n"
        f"rename to {new}\n"
    )


class TheChangeDigestKeysOnChangedLines(unittest.TestCase):
    """`change_digest` hashes what the pull request changed, not where: the
    expected equalities come from the review's rules (owner decision
    2026-10-21): context, line numbers, hunk and file order and whitespace
    leave it alone; a marker, a line, a path, a rename, a mode or a binary
    change moves it."""

    def digest(self, diff: str) -> str | None:
        return ve.change_digest(diff)

    def test_context_lines_and_line_numbers_do_not_count(self) -> None:
        self.assertEqual(
            self.digest(change("fix", at=1, before="one")),
            self.digest(change("fix", at=90, before="edited on main")),
        )

    def test_hunk_and_file_order_do_not_count(self) -> None:
        a, b = change("fix", path="a.txt"), change("other", path="b.txt")
        self.assertEqual(self.digest(a + b), self.digest(b + a))
        hunks = (
            "diff --git a/n.txt b/n.txt\n--- a/n.txt\n+++ b/n.txt\n"
            "@@ -1,1 +1,2 @@\n one\n+first\n"
            "@@ -9,1 +10,2 @@\n nine\n+second\n"
        )
        swapped = (
            "diff --git a/n.txt b/n.txt\n--- a/n.txt\n+++ b/n.txt\n"
            "@@ -1,1 +1,2 @@\n one\n+second\n"
            "@@ -9,1 +10,2 @@\n nine\n+first\n"
        )
        self.assertEqual(self.digest(hunks), self.digest(swapped))

    def test_a_removal_swapped_for_an_addition_counts(self) -> None:
        added = change("line")
        removed = added.replace("+line", "-line")
        self.assertNotEqual(self.digest(added), self.digest(removed))

    def test_a_pure_rename_counts_and_names_its_paths(self) -> None:
        first = self.digest(rename("old.txt", "new.txt"))
        self.assertIsNotNone(first)
        self.assertNotEqual(first, self.digest(rename("old.txt", "other.txt")))
        self.assertNotEqual(first, self.digest(rename("was.txt", "new.txt")))

    def test_a_binary_change_carries_its_path(self) -> None:
        def binary(path: str) -> str:
            return (
                f"diff --git a/{path} b/{path}\n"
                f"Binary files a/{path} and b/{path} differ\n"
            )

        self.assertIsNotNone(self.digest(binary("a.png")))
        self.assertNotEqual(self.digest(binary("a.png")), self.digest(binary("b.png")))

    def test_a_mode_change_counts(self) -> None:
        def mode(old: str, new: str) -> str:
            return f"diff --git a/run.sh b/run.sh\nold mode {old}\nnew mode {new}\n"

        self.assertIsNotNone(self.digest(mode("100644", "100755")))
        self.assertNotEqual(
            self.digest(mode("100644", "100755")), self.digest(mode("100755", "100644"))
        )
        content = change("x", path="run.sh")
        self.assertNotEqual(
            self.digest(content),
            self.digest(
                content.replace("index", "old mode 100644\nnew mode 100755\nindex")
            ),
        )

    def test_added_blank_lines_do_not_count(self) -> None:
        # A re-roll must not cost one empty line.
        base = change("x = 2")
        for blank in ("+", "+    ", "+\t"):
            with self.subTest(blank=blank):
                padded = base.replace("+x = 2\n", f"+x = 2\n{blank}\n")
                self.assertEqual(self.digest(base), self.digest(padded))

    def test_a_diff_of_only_blank_lines_has_no_digest(self) -> None:
        self.assertIsNone(self.digest(change("")))
        self.assertIsNone(self.digest(change("   ")))

    def test_crlf_line_ends_do_not_count(self) -> None:
        diff = change("fix") + rename("old.txt", "new.txt")
        self.assertEqual(self.digest(diff), self.digest(diff.replace("\n", "\r\n")))

    def test_no_change_has_no_digest(self) -> None:
        for diff in ("", "\n", "diff --git a/n.txt b/n.txt\nindex 1..2 100644\n"):
            with self.subTest(diff=diff):
                self.assertIsNone(self.digest(diff))


SIBLING = 40  # another pull request, open, that closes issue 7 too
SIBLING_HEADS = ("1" * 40, "2" * 40, "3" * 40)


LANES_APP_USER = {"login": "melodic-automation-lanes[bot]", "type": "Bot"}
LANES_APP_ACTOR = {
    "__typename": "Bot",
    "login": "melodic-automation-lanes",
    "databaseId": 4242,
}


def capped_record(
    number: int,
    author: dict[str, Any],
    tail: str = " attempt=1 of=1",
    **extra: Any,
) -> dict[str, Any]:
    """A capped-close record on issue 7 naming pull request `number`, written
    after every FAIL `artifact` uploads by default."""
    return {
        "databaseId": 900 + number,
        "createdAt": "2026-10-05T00:00:00Z",
        "updatedAt": "2026-10-05T00:00:00Z",
        "lastEditedAt": None,
        "body": f"<!-- verify-capped-close pr={number} heads={SIBLING_HEADS[0]}{tail} -->\nclosed",
        "author": author,
        "editor": None,
        **extra,
    }


def read_as_lane(fake: FakeGitHub) -> ve.Evidence:
    """`read` with the lanes App as `merge.agent-identity`."""
    with (
        mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
        mock.patch.object(ve, "gh_api_with_headers", side_effect=_page_with_date),
    ):
        return ve.Reader(
            REPO,
            "main",
            now=NOW,
            agent_identity="melodic-automation-lanes[bot]",
        ).evidence(PR, HEAD, pull())


def also_closes_issue_8(fake: FakeGitHub, *closers: int) -> FakeGitHub:
    """The judged pull request closes issue 8 too, as do `closers`, and the
    lanes App's capped-close record is on issue 8 alone."""
    fake.closing.append((8, REPO))
    fake.closers[8] = [(n, REPO) for n in (*closers, PR)]
    fake.records[named(HEAD, "pass")] = record(
        linked_issues=[TRUSTED_ISSUE, {**TRUSTED_ISSUE, "number": 8}]
    )
    fake.closing_comments[8] = [capped_record(SIBLING + 2, LANES_APP_ACTOR)]
    return fake


class FailsOnAnotherPullRequestForTheSameIssueCount(unittest.TestCase):
    """A second open pull request for the same issue does not reset the cap:
    counted FAILs of any open pull request in this repository that closes one
    of this pull request's closing issues count toward
    `merge.max-verify-fails`, at their own heads."""

    @staticmethod
    def sibling_fails(*shas: str, number: int = SIBLING) -> FakeGitHub:
        """A pass at the head, and FAILs of open pull request `number`
        (branch feat/old) at `shas`."""
        runs = {i: judged(i, OLDER_START) for i in range(2, 2 + len(shas))}
        fake = passing(
            *(artifact(named(sha, "fail", number), i) for i, sha in zip(runs, shas)),
            runs=runs,
        )
        for sha in shas:
            fake.records[named(sha, "fail", number)] = record(
                number, sha, verdict="fail", head_ref="feat/old"
            )
        fake.closers[7] = [(SIBLING, REPO), (PR, REPO)]
        fake.closer_states[number] = "OPEN"
        return fake

    def test_three_fails_on_an_open_pull_request_refuse(self) -> None:
        evidence = read(self.sibling_fails(*SIBLING_HEADS))
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertFalse(evidence.needs_human)

    def test_two_there_and_one_here_refuse(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS[:2])
        fake.artifacts.append(artifact(named(EARLIER, "fail"), 9))
        fake.runs[9] = judged(9, OLDER_START)
        self.assertEqual(read(fake).refusal, "verify:repeated-fail")

    def test_two_there_and_a_fail_at_the_head_reach_the_cap(self) -> None:
        # Not verify:fail: a fix round whose push could never merge.
        fake = self.sibling_fails(*SIBLING_HEADS[:2])
        fake.artifacts.append(artifact(named(HEAD, "fail"), 9))
        fake.runs[9] = judged(9, OLDER_START)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertFalse(evidence.needs_human)

    def test_one_there_and_a_fail_at_the_head_wait_for_a_fix_round(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS[:1])
        fake.artifacts.append(artifact(named(HEAD, "fail"), 9))
        fake.runs[9] = judged(9, OLDER_START)
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_two_there_leave_the_pass_to_decide(self) -> None:
        self.assertIsNone(read(self.sibling_fails(*SIBLING_HEADS[:2])).refusal)

    def test_a_pull_request_closing_another_issue_does_not_count(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS)
        fake.closers[7] = [(PR, REPO)]
        self.assertIsNone(read(fake).refusal)

    def test_a_merged_or_lanes_app_closed_pull_request_counts_no_more(self) -> None:
        # Owner decision 2026-10-29: each fresh attempt starts its own count.
        fake = self.sibling_fails(*SIBLING_HEADS)
        fake.closer_states[SIBLING] = "MERGED"
        self.assertIsNone(read(fake).refusal)
        fake.closer_states[SIBLING] = "CLOSED"
        fake.closer_authors[SIBLING] = LANES_APP_ACTOR
        self.assertIsNone(read_as_lane(fake).refusal)

    def test_a_closed_pull_request_of_anyone_else_still_counts(self) -> None:
        # Closing and reopening would otherwise re-roll the verifier.
        for author in (
            {"__typename": "User", "login": "someone", "databaseId": 3},
            {"__typename": "Bot", "login": "other-app", "databaseId": 2},
            None,
        ):
            with self.subTest(author):
                fake = self.sibling_fails(*SIBLING_HEADS)
                fake.closer_states[SIBLING] = "CLOSED"
                if author is not None:
                    fake.closer_authors[SIBLING] = author
                self.assertEqual(read_as_lane(fake).refusal, "verify:repeated-fail")

    def test_a_record_covers_a_closed_pull_requests_older_fails(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS)
        fake.closer_states[SIBLING] = "CLOSED"
        fake.closing_comments[7] = [capped_record(SIBLING + 2, LANES_APP_ACTOR)]
        self.assertIsNone(read_as_lane(fake).refusal)

    def test_a_capped_close_record_starts_the_count_again(self) -> None:
        # An open pull request's FAILs uploaded before the record judged the
        # attempt it closed; parked or not, the record ends that attempt.
        for tail in (" attempt=1 of=1", " attempt=1 of=1 parked", ""):
            with self.subTest(tail):
                fake = self.sibling_fails(*SIBLING_HEADS)
                fake.closing_comments[7] = [
                    capped_record(SIBLING + 2, LANES_APP_ACTOR, tail)
                ]
                self.assertIsNone(read_as_lane(fake).refusal)

    def test_fails_after_the_newest_record_still_count(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS)
        fake.closing_comments[7] = [
            capped_record(
                SIBLING + 2, LANES_APP_ACTOR, createdAt="2026-09-01T00:00:00Z"
            )
        ]
        self.assertEqual(read_as_lane(fake).refusal, "verify:repeated-fail")

    def test_only_the_caps_own_close_resets_the_count(self) -> None:
        # A third pull request for the issue closed unmerged with no record,
        # the lanes App's included: the lane closes its own for other reasons,
        # and anyone can open one naming the issue and close it.
        for author in (
            LANES_APP_ACTOR,
            {"__typename": "User", "login": "someone", "databaseId": 3},
            {"__typename": "Bot", "login": "other-app", "databaseId": 2},
            None,
        ):
            with self.subTest(author):
                fake = self.sibling_fails(*SIBLING_HEADS)
                fake.closers[7] = [(SIBLING, REPO), (SIBLING + 2, REPO), (PR, REPO)]
                if author is not None:
                    fake.closer_authors[SIBLING + 2] = author
                self.assertEqual(read_as_lane(fake).refusal, "verify:repeated-fail")

    def test_a_record_resets_only_its_own_issue(self) -> None:
        # A close on one issue ends no attempt at another, whose FAILs stay.
        fake = also_closes_issue_8(self.sibling_fails(*SIBLING_HEADS))
        self.assertEqual(read_as_lane(fake).refusal, "verify:repeated-fail")
        # Records on both of them end the attempts at both.
        fake.closing_comments[7] = [capped_record(SIBLING + 2, LANES_APP_ACTOR)]
        self.assertIsNone(read_as_lane(fake).refusal)

    def test_a_pull_request_for_two_issues_counts_for_the_one_not_reset(self) -> None:
        fake = also_closes_issue_8(self.sibling_fails(*SIBLING_HEADS), SIBLING)
        self.assertEqual(read_as_lane(fake).refusal, "verify:repeated-fail")

    def test_a_capped_close_record_anyone_else_wrote_or_edited_resets_nothing(
        self,
    ) -> None:
        for name, node in (
            (
                "a person's",
                capped_record(
                    SIBLING,
                    {"__typename": "User", "login": "kyle-sexton", "databaseId": 1},
                ),
            ),
            (
                "another bot's",
                capped_record(
                    SIBLING,
                    {"__typename": "Bot", "login": "other-app", "databaseId": 2},
                ),
            ),
            (
                "edited by a person",
                capped_record(
                    SIBLING,
                    LANES_APP_ACTOR,
                    editor={
                        "__typename": "User",
                        "login": "kyle-sexton",
                        "databaseId": 1,
                    },
                ),
            ),
        ):
            with self.subTest(name):
                fake = self.sibling_fails(*SIBLING_HEADS)
                fake.closing_comments[7] = [node]
                self.assertEqual(read_as_lane(fake).refusal, "verify:repeated-fail")

    def test_without_the_lane_identity_no_record_resets(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS)
        fake.closing_comments[7] = [capped_record(SIBLING, LANES_APP_ACTOR)]
        self.assertEqual(read(fake).refusal, "verify:repeated-fail")

    def test_a_pull_request_in_another_repository_does_not_count(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS)
        fake.closers[7] = [(SIBLING, "example-org/other"), (PR, REPO)]
        self.assertIsNone(read(fake).refusal)

    def test_a_cut_list_of_closing_pull_requests_refuses(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS[:1])
        fake.closers_total[7] = 60
        self.assertEqual(read(fake).refusal, "verify:unreadable")

    def test_an_unreadable_fail_run_of_a_sibling_refuses(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS[:2])
        del fake.runs[3]
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        # pr-unblock verify-cap.mjs reads this detail as the cap.
        self.assertEqual(evidence.detail, ve.SIBLING_UNREADABLE)

    def test_an_unreadable_fail_run_of_a_closed_sibling_holds_by_its_author(
        self,
    ) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS[:2])
        del fake.runs[3]
        fake.closer_states[SIBLING] = "CLOSED"
        self.assertEqual(read_as_lane(fake).refusal, "verify:unreadable")
        fake.closer_authors[SIBLING] = LANES_APP_ACTOR
        self.assertIsNone(read_as_lane(fake).refusal)

    def test_an_unreadable_fail_before_the_record_holds_nothing(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS)
        del fake.runs[3]
        fake.closing_comments[7] = [capped_record(SIBLING + 2, LANES_APP_ACTOR)]
        self.assertIsNone(read_as_lane(fake).refusal)

    def test_an_unreadable_fail_the_record_does_not_cover_refuses(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS[:2])
        del fake.runs[3]
        gone = next(a for a in fake.artifacts if a["id"] == 30)
        gone["created_at"] = "2026-10-06T00:00:00Z"
        fake.closing_comments[7] = [capped_record(SIBLING + 2, LANES_APP_ACTOR)]
        evidence = read_as_lane(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertEqual(evidence.detail, ve.SIBLING_UNREADABLE)

    def test_an_unreadable_fail_still_holds_for_an_issue_not_reset(self) -> None:
        fake = also_closes_issue_8(self.sibling_fails(*SIBLING_HEADS[:2]))
        del fake.runs[3]
        self.assertEqual(read_as_lane(fake).refusal, "verify:unreadable")


class AFreshAttemptAfterIssue9241sAttemptsStartsItsOwnCount(unittest.TestCase):
    """Issue 9241's shape (2026-10-30): FAILs named for the issue at three
    heads of earlier pull requests, #10451 (closes it, closed unmerged),
    #10525 (merged, closing another issue) and #10583 (merged, `Refs:`),
    and #11170 closed by hand with no record. #11294 and #11312, fresh
    attempts with no FAIL of their own, were closed at the cap on those three
    heads; a fresh attempt is not capped by them."""

    HEADS = {
        10451: "f436ef9eacc24c728fafc13f1c4e79a5e546faf2",
        10525: "7c72e89bbdd7922e94cecf534d03fc8e30603ae3",
        10583: "fbe89c59c07ce2a833fb9a152f71a2f810018ad0",
    }

    def attempt(self) -> FakeGitHub:
        runs = {i: judged(i, OLDER_START) for i in range(2, 5)}
        fake = passing(
            *(
                artifact(f"{named(sha, 'fail', n)}-i7", i)
                for i, (n, sha) in zip(runs, self.HEADS.items())
            ),
            runs=runs,
        )
        for n, sha in self.HEADS.items():
            fake.records[f"{named(sha, 'fail', n)}-i7"] = record(
                n, sha, verdict="fail", head_ref=f"lane/{n}"
            )
        fake.closers[7] = [(10451, REPO), (11170, REPO), (PR, REPO)]
        fake.closer_authors = {10451: LANES_APP_ACTOR, 11170: LANES_APP_ACTOR}
        fake.pulls = {
            10525: {"merged_at": "2026-09-28T01:09:36Z"},
            10583: {"merged_at": "2026-09-29T15:38:17Z"},
        }
        return fake

    def test_closed_and_merged_attempts_leave_a_fresh_one_uncapped(self) -> None:
        self.assertIsNone(read_as_lane(self.attempt()).refusal)

    def test_after_a_capped_close_record_the_next_attempt_is_uncapped(self) -> None:
        fake = self.attempt()
        fake.closing_comments[7] = [
            capped_record(
                11294,
                LANES_APP_ACTOR,
                " attempt=1 of=1",
                body=(
                    "<!-- verify-capped-close pr=11294 heads= attempt=1 of=1 -->\nclosed"
                ),
            )
        ]
        self.assertIsNone(read_as_lane(fake).refusal)
        # Every FAIL predates the record: no pull request's state is read.
        self.assertFalse(
            [c for c in fake.calls if any(re.search(r"/pulls/[0-9]+$", a) for a in c)]
        )

    def test_the_attempts_own_three_fails_still_cap(self) -> None:
        fake = self.attempt()
        for i, sha in enumerate((EARLIER, IN_PR, UNRELATED), start=9):
            fake.artifacts.append(artifact(named(sha, "fail"), i))
            fake.runs[i] = judged(i, OLDER_START)
        self.assertEqual(read(fake).refusal, "verify:repeated-fail")


class AnAttemptAfterIssue9727sMergedPullRequestStartsItsOwnCount(unittest.TestCase):
    """Issue 9727's shape (2026-10-30): #11402, a lanes App attempt with no
    FAIL of its own, was closed at the cap on three FAILs named for the issue
    at heads of #10134, a lanes App pull request that closes the issue and
    merged on 2026-10-28. A merged pull request's FAILs never count."""

    HEADS = (
        "09f699f1" + "0" * 32,
        "5a4fde34" + "0" * 32,
        "f70b8c1e" + "0" * 32,
    )

    def attempt(self, state: str) -> FakeGitHub:
        runs = {i: judged(i, OLDER_START) for i in range(2, 5)}
        fake = passing(
            *(
                artifact(f"{named(sha, 'fail', 10134)}-i7", i)
                for i, sha in zip(runs, self.HEADS)
            ),
            runs=runs,
        )
        for sha in self.HEADS:
            fake.records[f"{named(sha, 'fail', 10134)}-i7"] = record(
                10134, sha, verdict="fail", head_ref="lane/10134"
            )
        fake.closers[7] = [(10134, REPO), (PR, REPO)]
        fake.closer_states[10134] = state
        return fake

    def test_a_merged_pull_requests_three_fails_leave_the_attempt_uncapped(
        self,
    ) -> None:
        self.assertIsNone(read(self.attempt("MERGED")).refusal)

    def test_the_same_fails_cap_while_that_pull_request_is_open(self) -> None:
        self.assertEqual(read(self.attempt("OPEN")).refusal, "verify:repeated-fail")


class FailsOnARefsPullRequestForTheSameIssueCount(unittest.TestCase):
    """A pull request that names the issue without closing it (a `Refs:` pull
    request) never appears among the issue's closing pull requests, so its
    FAILs count toward the issue's cap through their names alone, while it
    is open: the writer names a FAIL with the `Refs:` issue as with a closing
    one (`-i7`), its state is read on its own, and no record is
    downloaded."""

    @staticmethod
    def sibling_fails(*shas: str, suffix: str = "-i7") -> FakeGitHub:
        """PR 41 links issue 7 by a `Refs:` line and has a counted pass at
        the head judged as a slice; PR 40 (branch feat/other, open) linked
        it the same way and FAILed at `shas`, each named with `suffix`."""
        runs = {i: judged(i, OLDER_START) for i in range(2, 2 + len(shas))}
        fake = passing(
            *(
                artifact(f"{named(sha, 'fail', SIBLING)}-{DIGEST_OTHER}{suffix}", i)
                for i, sha in zip(runs, shas)
            ),
            runs=runs,
        )
        fake.records[named(HEAD, "pass")] = record(spec_kind="refs")
        fake.closing = []
        fake.body = "Refs: #7\n\nPart two."
        fake.refs = {7: REPO}
        fake.closers[7] = []
        fake.pulls[SIBLING] = {"state": "open"}
        return fake

    def test_three_fails_on_another_refs_pull_request_refuse(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertFalse(evidence.needs_human)
        self.assertEqual(downloads(fake), 0)

    def test_two_there_and_a_fail_at_the_head_reach_the_cap(self) -> None:
        fake = self.sibling_fails(*SIBLING_HEADS[:2])
        fake.artifacts.append(artifact(named(HEAD, "fail"), 9))
        fake.runs[9] = judged(9, OLDER_START)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertFalse(evidence.needs_human)

    def test_two_there_leave_the_pass_to_decide(self) -> None:
        self.assertIsNone(read(self.sibling_fails(*SIBLING_HEADS[:2])).refusal)

    def test_only_names_that_carry_the_issue_count(self) -> None:
        # A plain FAIL (an unnamable issue set, or a name from before the
        # writer named issues) counts only for its own pull request.
        for suffix, refusal in (
            ("-i7.8", "verify:repeated-fail"),
            ("-i8", None),
            ("", None),
        ):
            with self.subTest(suffix):
                fake = self.sibling_fails(*SIBLING_HEADS, suffix=suffix)
                self.assertEqual(read(fake).refusal, refusal)

    def test_a_long_cross_reference_timeline_holds_nothing(self) -> None:
        # Anyone can cross-reference an issue, so a hundred and one mentions, from
        # issues here or in another repository, a page of 100 cut from the
        # count, hold no pull request for it, closing or `Refs:`, and its
        # FAILs still count by name.
        mentions = [None] * 99 + [(SIBLING, "example-org/other")]
        closing = passing()
        closing.mentions[7], closing.mentions_total[7] = mentions, 101
        self.assertIsNone(read(closing).refusal)
        fake = self.sibling_fails(*SIBLING_HEADS[:2])
        fake.mentions[7], fake.mentions_total[7] = mentions, 101
        self.assertIsNone(read(fake).refusal)
        fake = self.sibling_fails(*SIBLING_HEADS)
        fake.mentions[7], fake.mentions_total[7] = mentions, 101
        self.assertEqual(read(fake).refusal, "verify:repeated-fail")

    def test_a_refs_pull_requests_own_state_decides(self) -> None:
        # A `Refs:` pull request is in no closing list, so its state is read
        # on its own; a failed read is unreadable, never an excuse.
        for answer, refusal in (
            ({"state": "closed", "merged_at": "2026-10-02T00:00:00Z"}, None),
            ({"state": "closed", "user": LANES_APP_USER}, None),
            ({"state": "closed"}, "verify:repeated-fail"),
            (
                {"state": "closed", "user": {"login": "someone", "type": "User"}},
                "verify:repeated-fail",
            ),
            ({"state": "open"}, "verify:repeated-fail"),
            ("error", "verify:unreadable"),
        ):
            with self.subTest(refusal=refusal, answer=answer):
                fake = self.sibling_fails(*SIBLING_HEADS)
                if answer == "error":
                    fake.fail.add(f"pulls/{SIBLING}")
                else:
                    fake.pulls[SIBLING] = answer
                self.assertEqual(read_as_lane(fake).refusal, refusal)


class AFailNamingTheIssueCounts(unittest.TestCase):
    """A FAIL whose artifact name carries `-i` and the issue numbers its
    verdict records counts toward the cap for each of those issues, whatever
    pull request it judged and whether or not that pull request closes the
    issue: the listing the gate already read decides, with no download. A
    name with no issues keeps the rule above."""

    @staticmethod
    def named_fails(*shas: str, suffix: str = "-i7") -> FakeGitHub:
        """A pass at PR 41's head (closing issue 7), and FAILs of open PR 40
        (branch feat/other, not among issue 7's closing pull requests) at
        `shas`, each named with the feat/other digest and `suffix`."""
        runs = {i: judged(i, OLDER_START) for i in range(2, 2 + len(shas))}
        fake = passing(
            *(
                artifact(f"{named(sha, 'fail', SIBLING)}-{DIGEST_OTHER}{suffix}", i)
                for i, sha in zip(runs, shas)
            ),
            runs=runs,
        )
        fake.closers[7] = [(PR, REPO)]
        fake.pulls[SIBLING] = {"state": "open"}
        return fake

    def test_three_named_fails_refuse(self) -> None:
        evidence = read(self.named_fails(*SIBLING_HEADS))
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertFalse(evidence.needs_human)
        self.assertEqual(downloads(self.named_fails(*SIBLING_HEADS)), 0)

    def test_two_named_and_a_fail_at_the_head_reach_the_cap(self) -> None:
        fake = self.named_fails(*SIBLING_HEADS[:2])
        fake.artifacts.append(artifact(named(HEAD, "fail"), 9))
        fake.runs[9] = judged(9, OLDER_START)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertFalse(evidence.needs_human)

    def test_two_named_leave_the_pass_to_decide(self) -> None:
        self.assertIsNone(read(self.named_fails(*SIBLING_HEADS[:2])).refusal)

    def test_any_listed_issue_counts(self) -> None:
        ten = "-i" + ".".join(str(n) for n in range(1, 11))
        for suffix in ("-i7.12", "-i3.7", ten):
            with self.subTest(suffix):
                fake = self.named_fails(*SIBLING_HEADS, suffix=suffix)
                self.assertEqual(read(fake).refusal, "verify:repeated-fail")

    def test_a_name_without_the_issue_does_not_count(self) -> None:
        # Another issue, or an older name with no issues.
        for suffix in ("-i8", "-i8.70", ""):
            with self.subTest(suffix):
                fake = self.named_fails(*SIBLING_HEADS, suffix=suffix)
                self.assertIsNone(read(fake).refusal)

    OFF_GRAMMAR = (
        "-i07",
        "-i",
        "-i7.",
        "-i7,8",
        "-I7",
        "-i" + ".".join(str(n) for n in range(1, 12)),
        # One verdict has one name: ascending, each issue once.
        "-i12.7",
        "-i7.7",
        "-i3.7.7",
    )

    def test_an_off_grammar_fail_of_verifier_origin_holds(self) -> None:
        # A FAIL name no reader takes is held, never skipped: it may be a
        # FAIL the cap or the head should count.
        for suffix in self.OFF_GRAMMAR:
            with self.subTest(suffix):
                fake = self.named_fails(*SIBLING_HEADS[:1], suffix=suffix)
                self.assertEqual(read(fake).refusal, "verify:unreadable")
                fake = passing(artifact(f"{named(HEAD, 'fail')}{suffix}", 9))
                fake.runs[9] = judged(9, OLDER_START)
                self.assertEqual(read(fake).refusal, "verify:unreadable")

    def test_a_fail_shaped_name_with_any_number_holds(self) -> None:
        # The hold reads any digits, so a number no reader takes (11 digits,
        # a leading zero) never turns a FAIL at the head into a skip.
        # 4301 digits passes Python's limit on converting a string to an
        # int, which must never raise out of the judgment.
        for number in ("12345678901", "041", "1" * 4301):
            with self.subTest(number[:12]):
                fake = passing(artifact(f"pr-verify-{number}-{HEAD}-fail", 9))
                fake.runs[9] = judged(9, OLDER_START)
                self.assertEqual(read(fake).refusal, "verify:unreadable")
                if number.lstrip("0") == str(PR):
                    continue  # 041 is this pull request's number: tied
                untied = f"pr-verify-{number}-{SIBLING_HEADS[0]}-fail"
                for run_record in (judged(9, OLDER_START, event="push"), None):
                    fake = passing(artifact(untied, 9))
                    if run_record is not None:
                        fake.runs[9] = run_record
                    fake.closers[7] = [(SIBLING, REPO), (PR, REPO)]
                    self.assertIsNone(read(fake).refusal)

    def test_an_off_grammar_fail_whose_run_is_gone_holds_only_when_tied(self) -> None:
        tied = passing(artifact(f"{named(HEAD, 'fail')}-i07", 9))
        self.assertEqual(read(tied).refusal, "verify:unreadable")
        untied = passing(artifact(f"{named(SIBLING_HEADS[0], 'fail', SIBLING)}-i07", 9))
        self.assertIsNone(read(untied).refusal)

    def test_an_unreadable_off_grammar_fail_of_a_closer_holds(self) -> None:
        # Untied, but its pull request closes the same issue: the cap
        # cannot be counted without it.
        fake = passing(artifact(f"{named(SIBLING_HEADS[0], 'fail', SIBLING)}-i07", 9))
        fake.closers[7] = [(SIBLING, REPO), (PR, REPO)]
        fake.closer_states[SIBLING] = "OPEN"
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        fake.closer_states[SIBLING] = "CLOSED"
        fake.closer_authors[SIBLING] = LANES_APP_ACTOR
        self.assertIsNone(read_as_lane(fake).refusal)

    def test_an_off_grammar_fail_of_another_run_is_ignored(self) -> None:
        for suffix in self.OFF_GRAMMAR:
            with self.subTest(suffix):
                fake = passing(artifact(f"{named(HEAD, 'fail')}{suffix}", 9))
                fake.runs[9] = judged(9, OLDER_START, event="push")
                self.assertIsNone(read(fake).refusal)

    def test_a_pass_never_carries_issues(self) -> None:
        # Only a FAIL's name carries issues: a lone pass named with them at
        # the head is no verdict, so the head still waits for one.
        for name in (
            f"{named(HEAD, 'pass')}-i7",
            f"{named(HEAD, 'pass-notes')}-i7",
            f"{named(HEAD, 'pass')}-{DIGEST_X}-i7",
        ):
            with self.subTest(name):
                fake = FakeGitHub([artifact(name, 1)], {1: run(1)}, {name: record()})
                self.assertEqual(read(fake).refusal, "verify:missing")
        fake = passing()
        self.assertIsNone(read(fake).refusal)

    def test_an_unreadable_run_of_a_named_fail_refuses(self) -> None:
        fake = self.named_fails(*SIBLING_HEADS[:1])
        del fake.runs[2]
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        fake = self.named_fails(*SIBLING_HEADS[:1], suffix="-i8")
        del fake.runs[2]
        self.assertIsNone(read(fake).refusal)

    def test_a_record_on_another_issue_leaves_a_named_fail_counted(self) -> None:
        fake = also_closes_issue_8(self.named_fails(*SIBLING_HEADS))
        self.assertEqual(read_as_lane(fake).refusal, "verify:repeated-fail")

    def test_an_unreadable_named_fail_before_the_record_reads_no_state(self) -> None:
        fake = self.named_fails(*SIBLING_HEADS)
        del fake.runs[2]
        fake.closing_comments[7] = [capped_record(SIBLING + 2, LANES_APP_ACTOR)]
        self.assertIsNone(read_as_lane(fake).refusal)
        self.assertFalse(
            [c for c in fake.calls if any(re.search(r"/pulls/[0-9]+$", a) for a in c)]
        )

    def test_an_unreadable_off_grammar_fail_before_the_record_holds_nothing(
        self,
    ) -> None:
        fake = passing(artifact(f"{named(SIBLING_HEADS[0], 'fail', SIBLING)}-i07", 9))
        fake.closers[7] = [(SIBLING, REPO), (PR, REPO)]
        fake.closer_states[SIBLING] = "OPEN"
        fake.closing_comments[7] = [capped_record(SIBLING + 2, LANES_APP_ACTOR)]
        self.assertIsNone(read_as_lane(fake).refusal)

    def test_a_foreign_run_never_counts(self) -> None:
        fake = self.named_fails(*SIBLING_HEADS)
        for run_id in (2, 3, 4):
            fake.runs[run_id] = judged(run_id, OLDER_START, event="push")
        self.assertIsNone(read(fake).refusal)


class RepeatedFailsHoldForTheLanes(unittest.TestCase):
    """FAILs at `merge.max-verify-fails` (default 3) distinct heads of one
    pull request hold it, never to merge unattended, whatever a later pass
    says (owner decision 2026-10-21), for the lanes with no label (owner rule
    2026-10-27); fewer leave the pass to decide."""

    @staticmethod
    def failed_at(*shas: str) -> FakeGitHub:
        """A pass at the head (run 1) and a FAIL tied to the pull request at
        each of `shas`, every one judged before the pass."""
        runs = {i: judged(i, OLDER_START) for i in range(2, 2 + len(shas))}
        return passing(
            *(artifact(named(sha, "fail"), i) for i, sha in zip(runs, shas)),
            runs=runs,
        )

    def test_fails_at_three_heads_refuse_despite_a_later_pass(self) -> None:
        evidence = read(self.failed_at(EARLIER, IN_PR, UNRELATED))
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertFalse(evidence.needs_human)
        self.assertEqual(
            evidence.detail,
            f"fails at 3 heads ({EARLIER}, {IN_PR}, {UNRELATED}), the cap is 3",
        )

    def test_the_cap_fails_closed_when_its_fails_cannot_be_read(self) -> None:
        # A listing that does not read refuses rather than letting the pass
        # decide, so a short read never lifts the cap.
        fake = self.failed_at(EARLIER, IN_PR, UNRELATED)
        fake.fail = {"actions/artifacts"}
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")

    def test_a_fresh_pass_clears_an_old_pull_request_whose_fails_expired(self) -> None:
        # Owner decision 2026-11-01: a fresh pass at the head of
        # a pull request past TOO_OLD_DAYS allows it, so FAILs that expired
        # past the 90-day retention no longer count toward its cap.
        expired = passing(
            *(
                artifact(named(sha, "fail"), i, expired=True)
                for i, sha in zip((2, 3, 4), (EARLIER, IN_PR, UNRELATED))
            ),
            runs={i: judged(i, OLDER_START) for i in (2, 3, 4)},
        )
        evidence = read(expired, pull(created_at="2026-07-27T23:00:00Z"))
        self.assertIsNone(evidence.refusal)

    def test_fail_findings_with_no_judgment_name_its_own_fails(self) -> None:
        # The capped close quotes them for the fresh attempt; with no
        # judgment read first they come from the listing (`_own_fails`). A
        # sibling's FAIL and a foreign run's are not this pull request's.
        fake = passing(
            artifact(named(EARLIER, "fail"), 2),
            artifact(named(IN_PR, "fail"), 3),
            artifact(named(UNRELATED, "fail", SIBLING), 4),
            artifact(named(UNRELATED, "fail"), 5),
            runs={
                2: judged(2, OLDER_START),
                3: judged(3, OLDER_START),
                4: judged(4, OLDER_START),
                5: run(5, path=".github/workflows/other.yml"),
            },
        )
        fake.records[named(EARLIER, "fail")] = record(
            PR, EARLIER, verdict="fail", summary="misses the error path"
        )
        fake.records[named(IN_PR, "fail")] = record(
            PR, IN_PR, verdict="fail", summary="text from an unverified run"
        )
        del fake.runs[3]
        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
            mock.patch.object(ve, "gh_api_with_headers", side_effect=_page_with_date),
        ):
            reader = ve.Reader(REPO, "main", now=NOW)
            findings = reader.fail_findings(PR)
        self.assertEqual(
            [(f["head"], f["run"]) for f in findings], [(EARLIER, 2), (IN_PR, 3)]
        )
        self.assertEqual(findings[0]["summary"], "misses the error path")
        # A run whose origin is not verified is never downloaded: its text
        # could be anyone's.
        self.assertEqual(findings[1]["unreadable"], "run origin not verified")
        self.assertFalse(any("artifacts/30/zip" in " ".join(c) for c in fake.calls))

    def test_fails_at_two_heads_leave_the_pass_to_decide(self) -> None:
        self.assertIsNone(read(self.failed_at(EARLIER, IN_PR)).refusal)

    def test_fails_at_one_head_count_once(self) -> None:
        fake = self.failed_at(EARLIER, IN_PR)
        # A second FAIL at IN_PR, under another number, tied by the commit.
        fake.artifacts.append(artifact(named(IN_PR, "fail", 99), 4))
        fake.runs[4] = judged(4, OLDER_START)
        evidence = read(fake)
        self.assertIsNone(evidence.refusal)
        self.assertEqual(len([v for v in evidence.verdicts if v.verdict == "fail"]), 3)

    def test_a_fail_at_the_head_that_reaches_the_cap_is_repeated_fail(self) -> None:
        # The third failing head is refused for good, not sent to a fourth
        # fix round.
        fake = self.failed_at(EARLIER, IN_PR, HEAD)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertFalse(evidence.needs_human)

    def test_a_fail_at_the_head_under_the_cap_stays_verify_fail(self) -> None:
        fake = self.failed_at(EARLIER, HEAD)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertFalse(evidence.needs_human)

    def test_the_reader_takes_its_cap_from_the_setting(self) -> None:
        fake = self.failed_at(EARLIER, IN_PR)
        for cap, expected in (
            (2, "verify:repeated-fail"),
            (1, "verify:repeated-fail"),
            (3, None),
        ):
            with self.subTest(cap=cap):
                with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
                    reader = ve.Reader(REPO, "main", now=NOW, max_fails=cap)
                    self.assertEqual(
                        reader.evidence(PR, HEAD, pull()).refusal, expected
                    )


class AFailCountsWhateverTheRunConcluded(unittest.TestCase):
    """The upload comes before later steps, so a cancel or a failed later step
    must not erase a FAIL; a PASS needs a completed success."""

    UNFINISHED = {
        "failed later": {"conclusion": "failure"},
        "cancelled": {"conclusion": "cancelled"},
        "still going": {"status": "in_progress", "conclusion": None},
        "completed without success": {"status": "completed", "conclusion": None},
        "not completed": {"status": "queued", "conclusion": "success"},
    }

    def test_a_fail_from_an_unfinished_run_blocks(self) -> None:
        for label, overrides in self.UNFINISHED.items():
            with self.subTest(label):
                fake = FakeGitHub(
                    [artifact(named(HEAD, "fail"), 1)], {1: run(1, **overrides)}
                )
                self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_pass_from_an_unfinished_run_does_not_count(self) -> None:
        for label, overrides in self.UNFINISHED.items():
            with self.subTest(label):
                fake = passing()
                fake.runs[1] = run(1, **overrides)
                self.assertEqual(read(fake).refusal, "verify:missing")


class UnauthenticatedArtifactsAreIgnored(unittest.TestCase):
    """Each forgery changes one field of the run record. As a pass at the head
    it reads `verify:missing`; as a FAIL at an earlier head beside a real pass
    it must not route to a human."""

    FORGERIES = {
        "another workflow": {"path": ".github/workflows/pr-require-checks.yml"},
        "a pull_request run": {"event": "pull_request"},
        "a pull_request_target run": {"event": "pull_request_target"},
        "a branch other than main": {"head_branch": "feat/x"},
        "another repository": {"repository": {"full_name": "someone/fork"}},
        "a fork head": {"head_repository": {"full_name": "someone/fork"}},
        "a run head off main": {"head_sha": OFF_MAIN},
        "a malformed run head": {"head_sha": "c" * 39},
        "another run's record": {"id": 12345},
    }

    def test_each_forgery_counts_neither_as_pass_nor_fail(self) -> None:
        for label, overrides in self.FORGERIES.items():
            with self.subTest(label):
                # Only the off-main case may fail on the compare.
                on_main = (
                    set()
                    if label == "a run head off main"
                    else {overrides.get("head_sha", MAIN_SHA)}
                )
                forged_pass = passing()
                forged_pass.on_main |= on_main
                forged_pass.runs[1] = run(1, **overrides)
                self.assertEqual(read(forged_pass).refusal, "verify:missing")
                forged_fail = passing(
                    artifact(named(EARLIER, "fail"), 9), runs={9: run(9, **overrides)}
                )
                forged_fail.on_main |= on_main
                evidence = read(forged_fail)
                self.assertIsNone(evidence.refusal)
                self.assertEqual(evidence.report()["ignored"], 1)

    def test_an_expired_artifact_is_skipped(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 1, expired=True)], {1: run(1)})
        self.assertEqual(read(fake).refusal, "verify:missing")
        self.assertFalse(any("actions/runs/1" in " ".join(c) for c in fake.calls))

    def test_a_name_that_does_not_parse_is_ignored(self) -> None:
        for name in (
            f"pr-verify-{PR}-{HEAD}-FAIL",
            f"pr-verify-{PR}-{HEAD[:39]}-fail",
        ):
            with self.subTest(name):
                fake = FakeGitHub([artifact(name, 1)], {1: run(1)})
                self.assertEqual(read(fake).refusal, "verify:missing")

    def test_a_fail_shaped_name_that_does_not_parse_holds(self) -> None:
        # It starts like a FAIL of verifier origin, so it may be one: held.
        fake = FakeGitHub(
            [artifact(f"pr-verify-{PR}-{HEAD}-fail-extra", 1)], {1: run(1)}
        )
        self.assertEqual(read(fake).refusal, "verify:unreadable")


class UnreadableReadsBlock(unittest.TestCase):
    def test_a_fail_whose_run_cannot_be_read_blocks(self) -> None:
        fake = passing(artifact(named(EARLIER, "fail"), 7))
        self.assertEqual(read(fake).refusal, "verify:unreadable")

    def test_a_fail_whose_compare_cannot_be_read_blocks(self) -> None:
        fake = passing(artifact(named(EARLIER, "fail"), 2), runs={2: run(2)})
        fake.fail = {"/compare/"}
        self.assertEqual(read(fake).refusal, "verify:unreadable")

    def test_a_pass_whose_run_cannot_be_read_is_missing(self) -> None:
        fake = passing()
        del fake.runs[1]
        self.assertEqual(read(fake).refusal, "verify:missing")

    def test_an_unreadable_listing_commits_or_cap_refuses(self) -> None:
        for kind in ("actions/artifacts", "/commits"):
            with self.subTest(kind):
                fake = passing()
                fake.fail = {kind}
                self.assertEqual(read(fake).refusal, "verify:unreadable")
        capped = passing()
        capped.commits = [f"{i:040x}" for i in range(250)]
        self.assertEqual(read(capped).refusal, "verify:unreadable")


class AFailedReadRefusesWithoutAHuman(unittest.TestCase):
    """Issue #9063: a read that fails (a rate limit, pr-merge run
    39725996983) refuses `verify:unreadable`, which the next run re-derives,
    never `verify:earlier-fail`, which holds the head for a human."""

    earlier_fail = staticmethod(ACountedPassAtTheHeadClearsAnEarlierFail.earlier_fail)

    @staticmethod
    def foreign_fail(fake: FakeGitHub) -> FakeGitHub:
        """Adds another pull request's FAIL (run 3) whose record cannot be
        read."""
        fake.artifacts.append(artifact(named(UNRELATED, "fail", 99), 3))
        fake.runs[3] = run(3)
        return fake

    def test_an_unreadable_foreign_record_beside_a_cleared_fail(self) -> None:
        fake = self.foreign_fail(self.earlier_fail())
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertFalse(evidence.needs_human)
        # The next run reads the record and the cleared FAIL merges.
        fake.records[named(UNRELATED, "fail", 99)] = record(
            99, UNRELATED, verdict="fail", head_ref="feat/y"
        )
        self.assertIsNone(read(fake).refusal)

    def test_an_uncleared_earlier_fail_still_refuses(self) -> None:
        fake = self.foreign_fail(
            FakeGitHub([artifact(named(EARLIER, "fail"), 2)], {2: run(2)})
        )
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertFalse(evidence.needs_human)

    def test_a_fail_at_the_head_still_refuses(self) -> None:
        fake = self.foreign_fail(
            FakeGitHub([artifact(named(HEAD, "fail"), 2)], {2: run(2)})
        )
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertFalse(evidence.needs_human)

    def test_a_failed_run_time_read(self) -> None:
        # A second gate process counts the FAIL from the shared run record,
        # then reads its run again for the time, under a rate limit.
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        cache = str(pathlib.Path(tmp.name, "run.json"))
        fake = self.earlier_fail()
        with mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": cache}):
            self.assertIsNone(read(fake).refusal)
            fake.fail = {"actions/runs/2"}
            evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertFalse(evidence.needs_human)

    def test_a_failed_change_read(self) -> None:
        for sha in (EARLIER, HEAD):
            for status in (403, 502):
                with self.subTest(sha=sha, status=status):
                    fake = self.earlier_fail()
                    fake.fail = {f"compare/main...{sha}"}
                    fake.fail_status = status
                    evidence = read(fake)
                    self.assertEqual(evidence.refusal, "verify:unreadable")
                    self.assertFalse(evidence.needs_human)


class AnOldPullRequestIsRefused(unittest.TestCase):
    def test_older_than_80_days_with_no_verdict_is_too_old(self) -> None:
        evidence = read(FakeGitHub([], {}), pull(created_at="2026-07-27T23:00:00Z"))
        self.assertEqual(evidence.refusal, "verify:too-old")
        self.assertFalse(evidence.needs_human)

    def test_a_fresh_pass_at_the_head_clears_it(self) -> None:
        # Owner decision 2026-11-01: the lane re-runs the
        # verifier at the head, and its fresh pass clears verify:too-old.
        self.assertIsNone(
            read(passing(), pull(created_at="2026-07-27T23:00:00Z")).refusal
        )
        self.assertNotIn(ve.TOO_OLD, ve.VERIFY_FINAL)
        self.assertNotIn(ve.TOO_OLD, ve.STANDING)

    def test_a_fail_at_the_head_stays_a_fail(self) -> None:
        # A FAIL at an old pull request's head goes to a fix round as on any
        # other pull request, not to the age refusal.
        fake = passing(
            artifact(named(HEAD, "fail"), 2), runs={2: judged(2, OLDER_START)}
        )
        evidence = read(fake, pull(created_at="2026-07-27T23:00:00Z"))
        self.assertEqual(evidence.refusal, "verify:fail")

    def test_79_days_is_judged(self) -> None:
        self.assertIsNone(
            read(passing(), pull(created_at="2026-07-29T00:00:00Z")).refusal
        )


class TheSpecMustBeTrusted(unittest.TestCase):
    def with_issues(self, issues: list[dict[str, Any]], **pr: Any) -> ve.Evidence:
        fake = passing()
        fake.records[named(HEAD, "pass")] = record(linked_issues=issues)
        fake.closing = [(issue["number"], REPO) for issue in issues]
        return read(fake, pull(**pr))

    def test_a_trusted_humans_issue_allows(self) -> None:
        self.assertIsNone(self.with_issues([TRUSTED_ISSUE]).refusal)

    def test_an_issue_by_anyone_else_does_not(self) -> None:
        cases = {
            "a bot": {**TRUSTED_ISSUE, "author_type": "Bot", "author_id": 200},
            "an unlisted user": {
                **TRUSTED_ISSUE,
                "author_id": 999,
                "author_login": "x",
            },
            "a listed bot as a user": {**TRUSTED_ISSUE, "author_id": 200},
            "a listed human's id on a bot": {**TRUSTED_ISSUE, "author_type": "Bot"},
        }
        for label, issue in cases.items():
            with self.subTest(label):
                evidence = self.with_issues([issue])
                self.assertEqual(evidence.refusal, "verify:untrusted-spec")
                self.assertTrue(evidence.needs_human)
        self.assertEqual(self.with_issues([]).refusal, "verify:untrusted-spec")

    def test_a_trusted_human_authors_own_issue_allows(self) -> None:
        for user in ({"login": "Maintainer"}, {"login": "maintainer"}, {}):
            with self.subTest(user=user):
                self.assertIsNone(self.with_issues([TRUSTED_ISSUE], user=user).refusal)

    def test_an_untrusted_authors_own_issue_does_not(self) -> None:
        cases = {
            "the lanes App": (
                {
                    **TRUSTED_ISSUE,
                    "author_login": "agent-lanes[bot]",
                    "author_id": 200,
                    "author_type": "Bot",
                },
                {"login": "agent-lanes[bot]"},
            ),
            "an unlisted user": (
                {**TRUSTED_ISSUE, "author_login": "x", "author_id": 999},
                {"login": "x"},
            ),
        }
        for label, (issue, user) in cases.items():
            with self.subTest(label):
                self.assertEqual(
                    self.with_issues([issue], user=user).refusal,
                    "verify:untrusted-spec",
                )

    def test_every_linked_issue_must_be_trusted(self) -> None:
        # A trivially satisfied human issue beside the lanes App's own.
        bot = {**TRUSTED_ISSUE, "number": 8, "author_type": "Bot", "author_id": 200}
        self.assertEqual(
            self.with_issues([bot, TRUSTED_ISSUE]).refusal, "verify:untrusted-spec"
        )
        second = {**TRUSTED_ISSUE, "number": 8}
        self.assertIsNone(self.with_issues([TRUSTED_ISSUE, second]).refusal)

    def test_an_edit_by_anyone_but_a_trusted_user_refuses(self) -> None:
        edited = {**TRUSTED_ISSUE, "last_edited_at": "2026-10-14T00:00:00Z"}
        cases = {
            "the lanes App": {
                "editor_login": "agent-lanes[bot]",
                "editor_id": 200,
                "editor_type": "Bot",
            },
            "a listed human's id as a bot": {
                "editor_login": "maintainer",
                "editor_id": 100,
                "editor_type": "Bot",
            },
            "an unlisted user": {
                "editor_login": "x",
                "editor_id": 999,
                "editor_type": "User",
            },
            "no editor": {"editor_login": None, "editor_id": None, "editor_type": None},
        }
        for label, editor in cases.items():
            with self.subTest(label):
                fake = passing()
                fake.records[named(HEAD, "pass")] = record(
                    linked_issues=[{**edited, **editor}]
                )
                self.assertEqual(read(fake).refusal, "verify:untrusted-spec")
        trusted = {
            **edited,
            "editor_login": "maintainer",
            "editor_id": 100,
            "editor_type": "User",
        }
        self.assertIsNone(self.with_issues([trusted]).refusal)
        # The PR author editing their own issue is still a trusted human.
        self.assertIsNone(
            self.with_issues([trusted], user={"login": "maintainer"}).refusal
        )

    def test_a_record_for_another_head_or_an_unreadable_list_refuses(self) -> None:
        fake = passing()
        fake.records[named(HEAD, "pass")] = record(sha=EARLIER)
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        fake = passing()
        fake.actors = {"version": 2, "actors": []}
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        fake = passing()
        del fake.records[named(HEAD, "pass")]
        self.assertEqual(read(fake).refusal, "verify:unreadable")


class TheSpecCommentsMustBeTheJudgedOnes(unittest.TestCase):
    """The trusted comments on each linked issue now (by a User on the
    trusted list's humans, last edited if ever by one) must be the ones the
    verdict recorded, by id and update time."""

    RECORDED = [{"id": 1, "updated_at": "2026-10-12T00:00:00Z"}]

    def judge(
        self, live: list[dict[str, Any]], recorded: Any = None, **pr: Any
    ) -> str | None:
        fake = passing()
        issue = {
            **TRUSTED_ISSUE,
            "spec_comments": self.RECORDED if recorded is None else recorded,
        }
        fake.records[named(HEAD, "pass")] = record(linked_issues=[issue])
        fake.closing_comments = {7: live}
        return read(fake, pull(**pr)).refusal

    def test_the_same_trusted_comments_allow(self) -> None:
        self.assertIsNone(self.judge([comment(1, HUMAN)]))

    def test_an_added_edited_or_deleted_trusted_comment_refuses(self) -> None:
        cases = {
            "added": [comment(1, HUMAN), comment(2, HUMAN)],
            "edited": [comment(1, HUMAN, "2026-10-13T00:00:00Z")],
            "deleted": [],
            "edited by the lanes App": [
                comment(
                    1, HUMAN, lastEditedAt="2026-10-12T00:00:00Z", editor=LANES_ACTOR
                )
            ],
        }
        for label, live in cases.items():
            with self.subTest(label):
                self.assertEqual(self.judge(live), "verify:spec-changed")

    def test_untrusted_comments_are_not_part_of_the_spec(self) -> None:
        stranger = {"__typename": "User", "login": "stranger", "databaseId": 999}
        bot_with_human_id = {**HUMAN, "__typename": "Bot"}
        live = [
            comment(1, HUMAN),
            comment(3, LANES_ACTOR),
            comment(4, stranger),
            comment(5, bot_with_human_id),
        ]
        self.assertIsNone(self.judge(live))

    def test_a_trusted_pr_authors_comments_are_part_of_the_spec(self) -> None:
        user = {"login": "maintainer"}
        self.assertIsNone(self.judge([comment(1, HUMAN)], user=user))
        self.assertEqual(
            self.judge([comment(1, HUMAN)], [], user=user), "verify:spec-changed"
        )

    def test_a_partial_comment_read_or_a_malformed_record_refuses(self) -> None:
        fake = passing()
        fake.records[named(HEAD, "pass")] = record(
            linked_issues=[{**TRUSTED_ISSUE, "spec_comments": self.RECORDED}]
        )
        fake.closing_comments = {7: [comment(1, HUMAN)]}
        fake.comments_total = {7: 101}
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        for recorded in ("x", [{"id": "1", "updated_at": "t"}], [{"id": 1}]):
            with self.subTest(recorded):
                self.assertEqual(
                    self.judge([comment(1, HUMAN)], recorded), "verify:unreadable"
                )


class TheNewestPassDecides(unittest.TestCase):
    """A pass judged again at the same head after a spec change supersedes
    the earlier pass, which judged a spec that is gone."""

    EDITED = "2026-10-15T12:00:00Z"  # after run 1 started, before run 2

    def fake(self, *, second: bool) -> FakeGitHub:
        fake = passing()
        fake.closing_edited = {7: self.EDITED}
        if second:
            fake.artifacts.append(artifact(named(HEAD, "pass"), 2))
            fake.runs[2] = judged(2, "2026-10-15T13:00:00Z")
            fake.records[named(HEAD, "pass")] = record()
        return fake

    def test_a_stale_pass_alone_refuses(self) -> None:
        self.assertEqual(read(self.fake(second=False)).refusal, "verify:spec-changed")

    def test_a_later_pass_after_the_change_allows(self) -> None:
        self.assertIsNone(read(self.fake(second=True)).refusal)

    def test_a_re_attempt_after_the_change_decides_by_its_start(self) -> None:
        # Run 1 created first but re-attempted after the edit; run 2 created
        # later but started before it. The later start judged the live spec.
        fake = self.fake(second=True)
        fake.runs[1] = run(
            1, created_at=RUN_STARTED, run_started_at="2026-10-15T14:00:00Z"
        )
        fake.runs[2] = run(
            2, created_at="2026-10-15T01:00:00Z", run_started_at="2026-10-15T11:00:00Z"
        )
        self.assertIsNone(read(fake).refusal)

    def test_every_pass_decides_when_a_start_time_is_missing(self) -> None:
        fake = self.fake(second=True)
        fake.runs[2] = run(2, created_at="2026-10-15T13:00:00Z", run_started_at=None)
        # Run 2 then decides too, and a pass with no start refuses as an
        # unreadable time does in `_pass_refusal`: never allowed.
        self.assertEqual(read(fake).refusal, "verify:unreadable")


class TheSpecMustBeTheJudgedOne(unittest.TestCase):
    """The PR's closing issues now must be the ones the verdict recorded."""

    def test_the_same_closing_issues_allow(self) -> None:
        fake = passing()
        fake.closing = [
            (7, REPO),
            (3, "someone/else"),
        ]  # another repository's is left out
        self.assertIsNone(read(fake).refusal)

    def test_a_changed_set_refuses(self) -> None:
        for label, closing in {
            "another issue": [(8, REPO)],
            "one more": [(7, REPO), (8, REPO)],
            "none": [],
        }.items():
            with self.subTest(label):
                fake = passing()
                fake.closing = closing
                evidence = read(fake)
                self.assertEqual(evidence.refusal, "verify:spec-changed")
                self.assertFalse(evidence.needs_human)

    def refs(self, body: str | None, kind: str = REPO) -> FakeGitHub:
        """A pass recording issue 7, for a PR that closes none now."""
        fake = passing()
        fake.closing = []
        fake.body = body
        fake.refs = {7: kind, 8: REPO}
        fake.records[named(HEAD, "pass")] = record(spec_kind="refs")
        return fake

    def test_the_one_refs_issue_binds_like_a_closing_one(self) -> None:
        # Owner decision 2026-10-23: a plain `Refs:` line reads the one
        # issue it names as the pull request's issue.
        self.assertIsNone(read(self.refs("Refs: #7\n\nPart one.")).refusal)
        fake = self.refs("Refs: #7")
        fake.closing_edited = {7: "2026-10-15T00:00:01Z"}
        self.assertEqual(read(fake).refusal, "verify:spec-changed")

    def test_a_refs_line_that_names_another_or_none_refuses(self) -> None:
        for body, kind in (
            ("Refs: #8", REPO),
            ("<!-- Refs: #7 -->", REPO),
            ("```\nRefs: #7\n```", REPO),
            ("Refs: #7\nRefs: #8", REPO),
            ("Refs: other/repo#7", REPO),
            ("Refs: #7", "someone/else"),
            ("Refs: #7", "PullRequest"),
            (None, REPO),
        ):
            with self.subTest(body=body, kind=kind):
                self.assertEqual(
                    read(self.refs(body, kind)).refusal, "verify:spec-changed"
                )

    def test_a_refs_number_that_names_nothing_names_no_issue(self) -> None:
        # GitHub answers a number with no issue or pull request NOT_FOUND
        # and gh exits 1: no issue, so the pass recording the issue refuses
        # as for any other link that names none, and no read error.
        self.assertEqual(read(self.refs("Refs: #99999")).refusal, "verify:spec-changed")
        # Any other failed read stays unreadable: gh failing, an answer with
        # other errors gh exits 0 on, one with no repository, and a null
        # issue without NOT_FOUND.
        for kind in ("error", "errors", "no-repository", "null"):
            with self.subTest(kind):
                self.assertEqual(
                    read(self.refs("Refs: #7", kind)).refusal, "verify:unreadable"
                )

    def test_a_pass_binds_to_how_the_issue_was_linked(self) -> None:
        # A Refs pass was judged as a partial slice: it never covers the same
        # issue closed, and a closing pass never covers it as a Refs link.
        fake = passing()
        fake.records[named(HEAD, "pass")] = record(spec_kind="refs")
        self.assertEqual(read(fake).refusal, "verify:spec-changed")
        fake = self.refs("Refs: #7")
        fake.records[named(HEAD, "pass")] = record(spec_kind="closes")
        self.assertEqual(read(fake).refusal, "verify:spec-changed")
        fake = self.refs("Refs: #7")
        fake.records[named(HEAD, "pass")] = record()
        self.assertEqual(read(fake).refusal, "verify:spec-changed")
        fake = passing()
        fake.records[named(HEAD, "pass")] = record(spec_kind="closes")
        self.assertIsNone(read(fake).refusal)

    def test_a_closing_issue_wins_over_refs(self) -> None:
        fake = passing()
        fake.body = "Refs: #8"
        self.assertIsNone(read(fake).refusal)
        self.assertFalse(
            any("issueOrPullRequest" in " ".join(c) for c in fake.calls), fake.calls
        )

    def test_an_issue_edited_after_the_judgment_started_refuses(self) -> None:
        fake = passing()
        fake.closing_edited = {7: "2026-10-15T00:00:01Z"}
        self.assertEqual(read(fake).refusal, "verify:spec-changed")
        fake = passing()
        fake.closing_edited = {7: "2026-10-14T23:59:59Z"}
        self.assertIsNone(read(fake).refusal)

    def test_an_unreadable_edit_or_start_time_refuses(self) -> None:
        fake = passing()
        fake.closing_edited = {7: "yesterday"}
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        fake = passing()
        fake.runs[1] = run(1, run_started_at=None)
        fake.closing_edited = {7: "2026-10-14T00:00:00Z"}
        self.assertEqual(read(fake).refusal, "verify:unreadable")

    def test_an_unreadable_or_partial_listing_refuses(self) -> None:
        fake = passing()
        fake.fail = {"graphql"}
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        fake = passing()
        fake.closing_total = 11
        self.assertEqual(read(fake).refusal, "verify:unreadable")

    def test_a_pull_request_record_of_no_known_shape_refuses(self) -> None:
        with mock.patch.object(postmerge, "gh_capture", side_effect=passing()):
            evidence = ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, {})
        self.assertEqual(evidence.refusal, "verify:unreadable")

    def test_the_pull_request_is_the_intent_when_it_closes_no_issue(self) -> None:
        # Owner decision 2026-10-22: a trusted PR with no closing issue is
        # judged against its own title and body, recorded as the intent.
        pr = pull()
        text = f"{pr.get('title') or ''}\n\n{pr.get('body') or ''}"
        digest = hashlib.sha256(text.encode()).hexdigest()

        def evidence(closing: list[Any], **recorded: Any) -> Any:
            fake = passing()
            fake.closing = closing
            recorded.setdefault("intent_sha256", digest)
            fake.records[named(HEAD, "pass")] = record(linked_issues=[], **recorded)
            return read(fake, pr).refusal

        self.assertIsNone(evidence([], intent="pull-request"))
        self.assertIsNone(evidence([(3, "someone/else")], intent="pull-request"))
        self.assertEqual(evidence([]), "verify:untrusted-spec")
        self.assertEqual(evidence([], intent="issues"), "verify:untrusted-spec")
        self.assertEqual(
            evidence([(7, REPO)], intent="pull-request"), "verify:spec-changed"
        )

    def test_a_pull_request_intent_edited_since_its_verdict_refuses(self) -> None:
        # S&C D: the verdict records the hash of the title and body it judged.
        def evidence(title: str, body: str, digest: str | None) -> Any:
            fake = passing()
            fake.closing = []
            recorded = {"intent": "pull-request"}
            if digest is not None:
                recorded["intent_sha256"] = digest
            fake.records[named(HEAD, "pass")] = record(linked_issues=[], **recorded)
            return read(fake, pull(title=title, body=body)).refusal

        judged = hashlib.sha256(b"feat: x\n\nthe body").hexdigest()
        self.assertIsNone(evidence("feat: x", "the body", judged))
        self.assertEqual(evidence("feat: x", "edited", judged), "verify:spec-changed")
        self.assertEqual(evidence("feat: x", "the body", None), "verify:spec-changed")

    def test_a_record_whose_issues_are_not_a_list_refuses(self) -> None:
        fake = passing()
        fake.records[named(HEAD, "pass")] = record(linked_issues=None)
        self.assertEqual(read(fake).refusal, "verify:unreadable")


class AQueuedDependabotEntryNeedsNoVerdict(unittest.TestCase):
    """The pr-merge lane enqueues Dependabot pull requests in their own class
    (babysit_dependabot), which pr-verify never judges."""

    def hold(self, user: dict[str, Any]) -> tuple[str | None, FakeGitHub]:
        fake = FakeGitHub([], {})
        with (
            mock.patch.object(policy, "pull_request", return_value=pull(user=user)),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        ):
            return ve.Reader(REPO, "main", now=NOW).queued_hold(PR), fake

    def test_a_dependency_managers_entry_is_not_held(self) -> None:
        for login in ("dependabot[bot]", "renovate[bot]"):
            with self.subTest(login):
                hold, fake = self.hold({"login": login, "type": "Bot"})
                self.assertIsNone(hold)
                self.assertEqual(fake.calls, [])

    def test_a_user_named_like_a_dependency_manager_is_judged(self) -> None:
        for login in ("dependabot[bot]", "renovate"):
            with self.subTest(login):
                hold, _ = self.hold({"login": login, "type": "User"})
                self.assertEqual(hold, "verify:missing")

    def test_anyone_elses_entry_is_judged(self) -> None:
        hold, _ = self.hold({"login": "agent-lanes[bot]", "type": "Bot"})
        self.assertEqual(hold, "verify:missing")


class ActionsReadsUseTheActionsToken(unittest.TestCase):
    """The lane token holds no Actions permission, so the artifact listing,
    the run records and the download run under `BABYSIT_VERIFY_GH_TOKEN`, as
    do the run heads' compares to the branch (a contents read the job token
    serves, kept off the lane App's quota); every other read keeps the
    process token."""

    ACTIONS = ("actions/artifacts?", "actions/runs/", "/zip", "/compare/")

    def reads(self, reader: ve.Reader) -> dict[str, Any]:
        fake = passing()
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
        return {" ".join(args): env for args, env in fake.envs}

    def test_only_the_actions_reads_carry_the_token(self) -> None:
        reads = self.reads(ve.Reader(REPO, "main", now=NOW, actions_token="tok"))
        for call, env in reads.items():
            with self.subTest(call):
                if any(kind in call for kind in self.ACTIONS):
                    self.assertEqual(env, {"GH_TOKEN": "tok"})
                else:
                    self.assertIsNone(env)
        for kind in self.ACTIONS:
            self.assertTrue(any(kind in call for call in reads), kind)

    def test_the_token_comes_from_the_environment(self) -> None:
        with mock.patch.dict("os.environ", {"BABYSIT_VERIFY_GH_TOKEN": "env-tok"}):
            reader = ve.Reader(REPO, "main", now=NOW)
        self.assertEqual(reader.actions_token, "env-tok")
        with mock.patch.dict("os.environ", {}, clear=True):
            reads = self.reads(ve.Reader(REPO, "main", now=NOW))
        self.assertTrue(all(env is None for env in reads.values()))


class TheListingIsReadOncePerReader(unittest.TestCase):
    def test_two_reads_share_one_listing(self) -> None:
        fake = passing()
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            reader = ve.Reader(REPO, "main", now=NOW)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
        self.assertEqual(listings(fake), 1)

    def test_a_failed_listing_refuses_every_entry_and_is_not_read_per_entry(
        self,
    ) -> None:
        # One outage holds the whole queue rather than merging blind.
        fake = passing()
        fake.fail = {"actions/artifacts"}
        with (
            mock.patch.object(policy, "pull_request", return_value=pull()),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        ):
            reader = ve.Reader(REPO, "main", now=NOW)
            holds = [reader.queued_hold(n) for n in (PR, PR, PR)]
        self.assertEqual(holds, ["verify:unreadable"] * 3)
        # The count read before the whole listing fails first, and is read
        # again after each wait only: no listing starts.
        listings = [c for c in fake.calls if any("actions/artifacts" in a for a in c)]
        self.assertEqual(listings, [])
        self.assertEqual(fake.probes(), len(ve.LISTING_WAITS) + 1)


def listings(fake: FakeGitHub) -> int:
    """Listings read from the API: each one, whole or built on a base,
    reads the first single page once when it succeeds."""
    return sum(any(a.endswith("&page=1") for a in c) for c in fake.calls)


def name_reads(fake: FakeGitHub) -> int:
    """Reads of artifacts by exact name (`Reader._late_pass`)."""
    return sum(any("actions/artifacts?name=" in a for a in c) for c in fake.calls)


class TheListingIsReadOncePerRun(unittest.TestCase):
    """pr-merge.yml runs one gate, so one `Reader`, per candidate and names a
    file in `BABYSIT_VERIFY_LISTING`: the run pages the artifact listing once,
    and a saved listing never allows on its own."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = str(pathlib.Path(tmp.name, "verify-listing.json"))
        patcher = mock.patch.dict("os.environ", {"BABYSIT_VERIFY_LISTING": self.path})
        patcher.start()
        self.addCleanup(patcher.stop)

    def gate(self, fake: FakeGitHub) -> tuple[ve.Reader, ve.Evidence]:
        """One candidate's gate run: a fresh Reader."""
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            reader = ve.Reader(REPO, "main", now=NOW)
            return reader, reader.evidence(PR, HEAD, pull())

    def test_candidates_of_one_run_share_one_listing(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 1)], {1: run(1)})
        for _ in range(3):
            _, evidence = self.gate(fake)
            self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(listings(fake), 1)

    def test_an_allow_on_the_saved_listing_sees_a_later_fail(self) -> None:
        first, _ = self.gate(passing())
        self.assertFalse(first.saved)
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            reader = ve.Reader(REPO, "main", now=NOW)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
            self.assertTrue(reader.saved)
            reader.refresh()
            self.assertEqual(reader.evidence(PR, HEAD, pull()).refusal, "verify:fail")
        self.assertFalse(reader.saved)
        self.assertEqual(listings(fake), 1)
        # The fresher listing is saved for the rest of the run.
        _, evidence = self.gate(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(listings(fake), 1)

    def test_a_failed_listing_is_not_saved(self) -> None:
        fake = passing()
        fake.fail = {"actions/artifacts"}
        _, evidence = self.gate(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertFalse(pathlib.Path(self.path).exists())
        fake.fail = set()
        _, evidence = self.gate(fake)
        self.assertIsNone(evidence.refusal)

    def test_a_failure_before_a_whole_listing_is_not_noted_for_the_job(self) -> None:
        # Even by a Reader whose earlier listing paged a whole one.
        fake = passing()
        fake.count_fail = "gh: boom (HTTP 502)"
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            reader = ve.Reader(REPO, "main", now=NOW)
            reader._whole_paged = True
            with self.assertRaises(RuntimeError):
                reader.listing()
        self.assertFalse(
            pathlib.Path(f"{self.path}{ve.FAILED_LISTING_SUFFIX}").exists()
        )

    def hold(self, fake: FakeGitHub) -> str | None:
        """A later candidate's gate run judging PR 41 as a queued entry."""
        with (
            mock.patch.object(policy, "pull_request", return_value=pull()),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        ):
            return ve.Reader(REPO, "main", now=NOW).queued_hold(PR)

    def failed_since(self) -> FakeGitHub:
        """The pass the saved listing holds, and a FAIL at the head since."""
        return passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})

    def test_a_saved_listing_without_its_time_is_not_used_for_a_hold(self) -> None:
        pathlib.Path(self.path).write_text(json.dumps(passing().artifacts))
        fake = self.failed_since()
        self.assertEqual(self.hold(fake), "verify:fail")
        self.assertEqual(listings(fake), 1)

    def test_a_saved_listing_past_the_bound_is_not_used(self) -> None:
        clock = [datetime(2026, 10, 16, 12, 0, tzinfo=UTC)]
        with mock.patch.object(ve, "_wall_clock", side_effect=lambda: clock[0]):
            self.gate(passing())
            clock[0] += ve.LISTING_MAX_AGE + timedelta(seconds=1)
            fake = self.failed_since()
            self.assertEqual(self.hold(fake), "verify:fail")
            self.assertEqual(listings(fake), 1)
            # The listing that hold read is saved and recent: the candidate
            # after it reads it, and the FAIL refuses that candidate too.
            _, evidence = self.gate(fake)
            self.assertEqual(evidence.refusal, "verify:fail")
            self.assertEqual(listings(fake), 1)

    def provisional(self, fake: FakeGitHub) -> tuple[ve.Reader, ve.Evidence]:
        """The gate's own candidate (babysit_merge.py): judged provisional."""
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            reader = ve.Reader(REPO, "main", now=NOW)
            return reader, reader.evidence(PR, HEAD, pull(), provisional=True)

    def saved_then(
        self, before: FakeGitHub, later: FakeGitHub
    ) -> tuple[ve.Reader, ve.Evidence]:
        """`before` saves the run's listing; ten minutes on, past the bound,
        a provisional judgment while GitHub holds `later`."""
        clock = [datetime(2026, 10, 16, 12, 0, tzinfo=UTC)]
        with mock.patch.object(ve, "_wall_clock", side_effect=lambda: clock[0]):
            self.gate(before)
            clock[0] += timedelta(minutes=10)
            return self.provisional(later)

    def test_a_fail_on_an_older_saved_listing_refuses_a_provisional_judgment(
        self,
    ) -> None:
        # An upload since cannot clear a FAIL at the head: no listing.
        failed = FakeGitHub([artifact(named(HEAD, "fail"), 1)], {1: run(1)})
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 1)], {1: run(1)})
        fake.artifacts.append(artifact(named(HEAD, "pass"), 2))
        fake.runs[2] = run(2)
        _, evidence = self.saved_then(failed, fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(listings(fake), 0)

    def test_a_provisional_allow_stands_on_an_older_saved_listing(self) -> None:
        # babysit_merge.py lists again before the gate allows (`saved`).
        fake = passing()
        reader, evidence = self.saved_then(passing(), fake)
        self.assertIsNone(evidence.refusal)
        self.assertTrue(reader.saved)
        self.assertEqual(listings(fake), 0)

    def test_a_clearable_refusal_on_an_older_saved_listing_is_judged_again(
        self,
    ) -> None:
        # The saved listing has no verdict; a pass uploaded since allows, so
        # a missing verdict there would dequeue the candidate's entry wrongly.
        reader, evidence = self.saved_then(FakeGitHub([], {}), fake := passing())
        self.assertIsNone(evidence.refusal)
        self.assertFalse(reader.saved)
        self.assertEqual(listings(fake), 1)

    def late_notes(self, **overrides: Any) -> FakeGitHub:
        """GitHub after the run saved a listing with no verdict: a pass-notes
        at the head uploaded since, its run `run(1, **overrides)`."""
        name = named(HEAD, "pass-notes")
        return FakeGitHub(
            [artifact(name, 1)],
            {1: run(1, **overrides)},
            {name: record(verdict="pass-notes")},
        )

    def test_a_pass_uploaded_after_the_saved_listing_is_read_by_name(self) -> None:
        # #11854: the pass-notes landed after the run's listing was read.
        self.gate(FakeGitHub([], {}))
        fake = self.late_notes()
        reader, evidence = self.provisional(fake)
        self.assertIsNone(evidence.refusal)
        self.assertTrue(reader.saved)
        self.assertEqual((listings(fake), name_reads(fake)), (0, 2))
        # babysit_merge.py allows only on a listing of the gate's own.
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            reader.refresh()
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
        self.assertEqual((listings(fake), name_reads(fake)), (1, 2))

    def test_a_late_pass_that_does_not_count_leaves_missing(self) -> None:
        for label, fake in (
            ("run failed", self.late_notes(conclusion="failure")),
            ("run going", self.late_notes(status="in_progress", conclusion=None)),
            ("expired", self.late_notes()),
        ):
            with self.subTest(label):
                if label == "expired":
                    fake.artifacts[0]["expired"] = True
                self.gate(FakeGitHub([], {}))
                reader, evidence = self.provisional(fake)
                self.assertEqual(evidence.refusal, "verify:missing")
                self.assertTrue(reader.saved)
                self.assertEqual(listings(fake), 0)

    def test_a_failed_name_read_leaves_missing_and_notes_nothing(self) -> None:
        self.gate(FakeGitHub([], {}))
        fake = self.late_notes()
        fake.fail = {"?name="}
        _, evidence = self.provisional(fake)
        self.assertEqual(evidence.refusal, "verify:missing")
        # The first name, read again after each wait, and no other read.
        self.assertEqual(name_reads(fake), len(ve.LISTING_WAITS) + 1)
        self.assertEqual(listings(fake), 0)
        for suffix in (ve.FAILED_LISTING_SUFFIX, ve.OVERCOUNT_FALLBACK_SUFFIX):
            self.assertFalse(pathlib.Path(f"{self.path}{suffix}").exists())

    def test_only_a_provisional_missing_on_the_saved_listing_reads_names(self) -> None:
        # The first candidate read its listing just now; a judgment that is
        # not the gate's own (`evidence`, queued entries) reads no name.
        fake = self.late_notes()
        fake.artifacts.clear()
        _, evidence = self.provisional(fake)
        self.assertEqual(evidence.refusal, "verify:missing")
        _, evidence = self.gate(fake)
        self.assertEqual(evidence.refusal, "verify:missing")
        self.assertEqual(name_reads(fake), 0)

    def test_a_listing_in_memory_past_the_bound_is_read_again(self) -> None:
        clock = [datetime(2026, 10, 16, 12, 0, tzinfo=UTC)]
        fake = passing()
        with (
            mock.patch.object(ve, "_wall_clock", side_effect=lambda: clock[0]),
            mock.patch.object(policy, "pull_request", return_value=pull()),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        ):
            reader = ve.Reader(REPO, "main", now=NOW)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
            clock[0] += ve.LISTING_MAX_AGE
            self.assertIsNone(reader.queued_hold(PR))
            self.assertEqual(listings(fake), 1)
            fake.artifacts.append(artifact(named(HEAD, "fail"), 2))
            fake.runs[2] = run(2)
            clock[0] += timedelta(seconds=1)
            self.assertEqual(reader.queued_hold(PR), "verify:fail")
        self.assertEqual(listings(fake), 2)

    def test_a_malformed_saved_listing_is_read_from_the_api(self) -> None:
        recent = datetime.now(UTC).isoformat()
        for text in (
            "not json",
            "[]",
            '{"artifacts": []}',
            json.dumps({"fetchedAt": "yesterday", "artifacts": []}),
            json.dumps({"fetchedAt": "2026-10-16T12:00:00", "artifacts": []}),
            json.dumps({"fetchedAt": recent, "artifacts": [1]}),
            json.dumps({"fetchedAt": recent}),
        ):
            with self.subTest(text):
                pathlib.Path(self.path).write_text(text)
                fake = passing()
                reader, evidence = self.gate(fake)
                self.assertIsNone(evidence.refusal)
                self.assertFalse(reader.saved)
                self.assertEqual(listings(fake), 1)


class OneRunSharesItsVerifierReads(unittest.TestCase):
    """With `BABYSIT_RUN_CACHE` named, the gate processes of one run share a
    run head found on the branch and the trusted-actor list (for its bound);
    a head not found on the branch is compared again."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = str(pathlib.Path(tmp.name, "run.json"))
        patcher = mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": path})
        patcher.start()
        self.addCleanup(patcher.stop)

    @staticmethod
    def compares(fake: FakeGitHub, sha: str) -> int:
        return sum(f"/compare/{sha}..." in " ".join(c) for c in fake.calls)

    @staticmethod
    def trusted_reads(fake: FakeGitHub) -> int:
        return sum(any("/contents/" in a for a in c) for c in fake.calls)

    def candidates(self, fake: FakeGitHub, count: int) -> None:
        for _ in range(count):
            self.assertIsNone(read(fake).refusal)

    def test_a_head_on_the_branch_is_compared_once_per_run(self) -> None:
        fake = passing()
        self.candidates(fake, 3)
        self.assertEqual(self.compares(fake, MAIN_SHA), 1)

    def test_a_head_off_the_branch_is_compared_by_every_candidate(self) -> None:
        off = "d" * 40
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2, head_sha=off)})
        self.candidates(fake, 2)
        self.assertEqual(self.compares(fake, off), 2)

    def test_a_judgment_notes_its_oldest_shared_read(self) -> None:
        # The trusted list another process read 90 s ago dates the judgment.
        clock = [datetime(2026, 10, 18, 11, 58, 30, tzinfo=UTC)]
        fake = passing()
        with (
            mock.patch.object(ve.run_cache, "now", side_effect=lambda: clock[0]),
            mock.patch.object(ve, "_wall_clock", side_effect=lambda: clock[0]),
        ):
            self.candidates(fake, 1)
            listed_before = clock[0]
            clock[0] += timedelta(seconds=90)
            with ve.run_cache.track() as taken:
                self.candidates(fake, 1)
        self.assertEqual(self.trusted_reads(fake), 1)
        self.assertEqual(min(taken), listed_before)
        self.assertIn(clock[0], taken)  # this process's own listing

    def test_the_trusted_list_is_read_once_within_the_bound(self) -> None:
        clock = [datetime(2026, 10, 18, 12, 0, tzinfo=UTC)]
        fake = passing()
        with mock.patch.object(ve.run_cache, "now", side_effect=lambda: clock[0]):
            self.candidates(fake, 2)
            self.assertEqual(self.trusted_reads(fake), 1)
            clock[0] += ve.run_cache.MAX_AGE + timedelta(seconds=1)
            self.candidates(fake, 1)
        self.assertEqual(self.trusted_reads(fake), 2)


class OneRunSharesItsFailRunReads(unittest.TestCase):
    """With `BABYSIT_RUN_CACHE` named, a FAIL's run record and an untied
    FAIL's recorded head ref are read once per run. A PASS's run is read by every gate process, so a re-run
    that undoes a completed success never allows on a shared record."""

    OTHER = UNRELATED

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = str(pathlib.Path(tmp.name, "run.json"))
        patcher = mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": path})
        patcher.start()
        self.addCleanup(patcher.stop)

    def other_fail(self) -> FakeGitHub:
        """A pass at the head (run 1) and another PR's FAIL (run 2)."""
        name = named(self.OTHER, "fail", 99)
        fake = passing(artifact(name, 2), runs={2: run(2)})
        fake.records[name] = record(99, self.OTHER, head_ref="feat/other")
        return fake

    @staticmethod
    def run_reads(fake: FakeGitHub, run_id: int) -> int:
        return sum(
            any(a.endswith(f"/actions/runs/{run_id}") for a in c) for c in fake.calls
        )

    @staticmethod
    def downloads(fake: FakeGitHub, run_id: int) -> int:
        """Downloads of the run's artifact, by its id (any id it was listed
        under) or by run and name."""
        ids = {run_id * 10} | {
            a["id"] for a in fake.artifacts if a["workflow_run"]["id"] == run_id
        }
        zips = {f"repos/{REPO}/actions/artifacts/{i}/zip" for i in ids}
        return sum(
            c[:3] == ["run", "download", str(run_id)] or bool(zips & set(c))
            for c in fake.calls
        )

    def test_a_fail_run_and_its_record_are_read_once_per_run(self) -> None:
        fake = self.other_fail()
        for _ in range(3):
            self.assertIsNone(read(fake).refusal)
        self.assertEqual(self.run_reads(fake, 2), 1)
        self.assertEqual(self.downloads(fake, 2), 1)
        # The pass's run is read by every candidate.
        self.assertEqual(self.run_reads(fake, 1), 3)

    def test_a_replaced_artifact_of_the_same_name_is_read_again(self) -> None:
        # An overwrite uploads a new id under the same name: the head ref
        # shared for the old id must not stand for the new contents.
        fake = self.other_fail()
        del fake.artifacts[0]  # no pass, so a tied FAIL refuses
        self.assertEqual(read(fake).refusal, "verify:missing")
        name = named(self.OTHER, "fail", 99)
        fake.artifacts[0] = {**fake.artifacts[0], "id": 21}
        fake.records[name] = record(99, self.OTHER, head_ref="feat/x")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")
        self.assertEqual(self.downloads(fake, 2), 2)

    def test_a_fail_run_is_not_read_again_past_the_shared_bound(self) -> None:
        # Origin rests on fields a re-run keeps, so the record serves the
        # whole run, however long the sweep takes.
        clock = [datetime(2026, 10, 18, 12, 0, tzinfo=UTC)]
        fake = self.other_fail()
        with mock.patch.object(ve.run_cache, "now", side_effect=lambda: clock[0]):
            read(fake)
            clock[0] += ve.run_cache.MAX_AGE * 20
            read(fake)
        self.assertEqual(self.run_reads(fake, 2), 1)

    def test_a_shared_run_record_keeps_only_repository_names(self) -> None:
        fake = self.other_fail()
        fat = {"full_name": REPO, "id": 1, "owner": {"login": "o"}, "x": "y" * 99}
        fake.runs[2] = run(2, repository=fat, head_repository=dict(fat))
        self.assertIsNone(read(fake).refusal)
        path = pathlib.Path(os.environ["BABYSIT_RUN_CACHE"])
        stored = json.loads(path.read_text())["run-record"][f"{REPO}|2"]["value"]
        self.assertEqual(stored["repository"], {"full_name": REPO})
        self.assertEqual(stored["head_repository"], {"full_name": REPO})
        # The slim record serves the next candidate as the full one did.
        self.assertIsNone(read(fake).refusal)
        self.assertEqual(self.run_reads(fake, 2), 1)

    def test_a_re_run_of_a_counted_pass_does_not_allow(self) -> None:
        fake = passing()
        self.assertIsNone(read(fake).refusal)
        fake.runs[1] = run(1, status="in_progress", conclusion=None, run_attempt=2)
        self.assertEqual(read(fake).refusal, "verify:missing")

    def test_a_re_run_of_a_fail_still_refuses_on_the_shared_record(self) -> None:
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})
        self.assertEqual(read(fake).refusal, "verify:fail")
        fake.runs[2] = run(2, status="in_progress", conclusion=None, run_attempt=2)
        self.assertEqual(read(fake).refusal, "verify:fail")
        self.assertEqual(self.run_reads(fake, 2), 1)


class ACarriedHeadServesOnlyAFail(unittest.TestCase):
    """A run head an earlier pr-merge run found on main reaches this run's
    cache as `carried-on-branch` (carry-run-cache.mjs). Only a FAIL's run may
    rest on it, where it can only count the FAIL; a PASS's run is compared by
    this run, so a wrong carried yes can never allow."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = pathlib.Path(tmp.name, "run.json")
        patcher = mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": str(self.path)})
        patcher.start()
        self.addCleanup(patcher.stop)
        at = datetime.now(UTC).isoformat()
        entry = {f"{REPO}|{MAIN_SHA}...main": {"at": at, "value": True}}
        self.path.write_text(json.dumps({"carried-on-branch": entry}))

    @staticmethod
    def compares(fake: FakeGitHub) -> int:
        return sum("/compare/" in " ".join(c) for c in fake.calls)

    def test_a_fail_run_rests_on_the_carried_head_with_no_compare(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 2)], {2: run(2)})
        self.assertEqual(read(fake).refusal, "verify:fail")
        self.assertEqual(self.compares(fake), 0)

    def test_a_carried_yes_the_branch_denies_still_counts_the_fail(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 2)], {2: run(2)})
        fake.on_main = set()
        self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_pass_run_is_compared_and_not_counted_off_the_branch(self) -> None:
        # The same run uploads another PR's FAIL first: its judgment rests on
        # the carried yes, and the PASS must not reuse it.
        other = named(UNRELATED, "fail", 99)
        fake = FakeGitHub(
            # Two artifacts of one run, so two ids.
            [artifact(other, 1), artifact(named(HEAD, "pass"), 1) | {"id": 11}],
            {1: run(1)},
            {named(HEAD, "pass"): record(), other: record(99, UNRELATED, head_ref="o")},
        )
        fake.on_main = set()
        self.assertEqual(read(fake).refusal, "verify:missing")
        self.assertEqual(self.compares(fake), 1)


CARRY = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/pr-merge/carry-run-cache.mjs"
)


def restore(directory: pathlib.Path, sections: dict[str, Any]) -> None:
    """Carry `sections`, as the cache restored them, into the run cache
    `directory`/run.json, as pr-merge.yml does before the gate."""
    at = datetime.now(UTC).isoformat()
    restored = directory / "restored.json"
    restored.write_text(
        json.dumps(
            {
                s: {k: {"at": at, "value": v} for k, v in e.items()}
                for s, e in sections.items()
            }
        )
    )
    subprocess.run(
        ["node", str(CARRY)],
        env={
            "PATH": os.environ["PATH"],
            "CARRY_FROM": str(restored),
            "CARRY_TO": str(directory / "run.json"),
            "GITHUB_REPOSITORY": REPO,
        },
        check=True,
        capture_output=True,
    )


class APoisonedCarriedCacheNeverRemovesARefusal(unittest.TestCase):
    """pr-merge starts its run cache from the pr-merge-run-cache and
    pr-merge-verify-run-cache artifacts of the newest scheduled or
    hand-started run of main's pr-merge.yml whose head is on main
    (carry-run-cache.mjs `read`), never from actions/cache. Whatever a carried
    entry holds, carry-run-cache.mjs and this reader together may only add
    refusals: a carried read that would turn a FAIL away is read again from
    GitHub. Review-lane runs, read outside this reader
    (babysit_gh.collect_lane_runs), are the exception: their tests are in
    test_babysit_gh_lane_run_carry.py."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)
        patcher = mock.patch.dict(
            "os.environ", {"BABYSIT_RUN_CACHE": str(self.dir / "run.json")}
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def restore(self, sections: dict[str, Any]) -> None:
        restore(self.dir, sections)

    def test_a_forged_run_head_does_not_turn_a_fail_away(self) -> None:
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})
        forged = run(2, head_sha=OFF_MAIN)
        for section in ("run-record", "carried-run-record"):
            with self.subTest(section=section):
                self.restore({section: {f"{REPO}|2": forged}})
                self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_forged_head_ref_does_not_untie_an_earlier_fail(self) -> None:
        name = named(UNRELATED, "fail", 99)
        fake = FakeGitHub([artifact(name, 2)], {2: run(2)})
        fake.records[name] = record(99, UNRELATED, head_ref="feat/x")
        for section in ("fail-head-ref", "carried-fail-head-ref"):
            with self.subTest(section=section):
                self.restore({section: {f"{REPO}|20": {"head_ref": "feat/other"}}})
                self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_a_forged_old_start_never_clears_an_earlier_fail(self) -> None:
        # GitHub says the FAIL's run started after the pass's; the cache
        # claims it started before.
        fake = passing(
            artifact(named(EARLIER, "fail"), 2),
            runs={2: judged(2, "2026-10-15T00:00:01Z")},
        )
        forged = judged(2, "2026-10-01T00:00:00Z")
        for section in ("run-record", "carried-run-record"):
            with self.subTest(section=section):
                self.restore({section: {f"{REPO}|2": forged}})
                self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_carried_reads_that_count_a_fail_spare_the_reads(self) -> None:
        name = named(UNRELATED, "fail", 99)
        fake = FakeGitHub([artifact(name, 2)], {2: run(2)})
        self.restore(
            {
                "run-record": {f"{REPO}|2": run(2)},
                "fail-head-ref": {f"{REPO}|20": {"head_ref": "feat/x"}},
                "on-branch": {f"{REPO}|{MAIN_SHA}...main": True},
            }
        )
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")
        self.assertFalse(any(c[-1].endswith("/actions/runs/2") for c in fake.calls))
        self.assertEqual(OneRunSharesItsFailRunReads.downloads(fake, 2), 0)

    def test_slim_and_full_run_records_both_count_a_fail(self) -> None:
        # Records saved before repositories were trimmed to their names
        # still carry and count, as trimmed ones do.
        name = named(UNRELATED, "fail", 99)
        full = {"full_name": REPO, "id": 1, "owner": {"login": "o"}}
        for label, repository in (("slim", {"full_name": REPO}), ("full", full)):
            for section in ("run-record", "carried-run-record"):
                with self.subTest(record=label, section=section):
                    (self.dir / "run.json").unlink(missing_ok=True)
                    fake = FakeGitHub([artifact(name, 2)], {2: run(2)})
                    stored = run(
                        2, repository=repository, head_repository=dict(repository)
                    )
                    self.restore(
                        {
                            section: {f"{REPO}|2": stored},
                            "fail-head-ref": {f"{REPO}|20": {"head_ref": "feat/x"}},
                            "on-branch": {f"{REPO}|{MAIN_SHA}...main": True},
                        }
                    )
                    self.assertEqual(read(fake).refusal, "verify:earlier-fail")
                    self.assertFalse(
                        any(c[-1].endswith("/actions/runs/2") for c in fake.calls)
                    )

    def test_a_slim_record_of_another_repository_is_not_origin(self) -> None:
        # A trimmed record naming another repository is no origin, so the
        # run is read from GitHub, as for a full one.
        name = named(UNRELATED, "fail", 99)
        fake = FakeGitHub([artifact(name, 2)], {2: run(2)})
        other = {"full_name": "someone/fork"}
        at = datetime.now(UTC).isoformat()
        # Written as it lands, past carry-run-cache.mjs, which would drop it.
        (self.dir / "run.json").write_text(
            json.dumps(
                {
                    "carried-run-record": {
                        f"{REPO}|2": {
                            "at": at,
                            "value": run(2, repository=other, head_repository=other),
                        }
                    },
                    "fail-head-ref": {
                        f"{REPO}|20": {"at": at, "value": {"head_ref": "feat/x"}}
                    },
                }
            )
        )
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")
        self.assertTrue(any(c[-1].endswith("/actions/runs/2") for c in fake.calls))


# --- A transient listing failure is read again --------------------------------

# Every test runs without the backoff sleep; `judge` reads the waits off it.
_no_sleep = mock.patch.object(ve, "_listing_sleep")


# Single pages go to whatever fake `postmerge.gh_capture` is patched to, with
# GitHub's `Date` header (`DATE`); a test that needs other headers patches
# this again.
def _page_with_date(args: list[str], **kwargs: Any) -> Any:
    return postmerge.gh_capture(args, **kwargs), {"date": DATE}


_no_pages = mock.patch.object(ve, "gh_api_with_headers", side_effect=_page_with_date)


# The tracker's human-gated label read an autonomous gate makes: stubbed so
# no test reads GitHub; a test that remaps it patches it again.
_role_label = mock.patch.object(postmerge, "_role_label", return_value="needs-human")


# The branch tip `merge_policy.base_tip` reads goes to whatever fake
# `postmerge.gh_capture` is patched to; a test that answers it otherwise
# patches it again.
_tip_reads = mock.patch.object(
    ve.merge_policy,
    "gh_capture",
    side_effect=lambda args, **kwargs: postmerge.gh_capture(args, **kwargs),
)


def setUpModule() -> None:
    _no_sleep.start()
    _no_pages.start()
    _role_label.start()
    _tip_reads.start()


def tearDownModule() -> None:
    _tip_reads.stop()
    _role_label.stop()
    _no_pages.stop()
    _no_sleep.stop()


def timed_out() -> RuntimeError:
    """What babysit_util.run_command raises when gh outlives its timeout."""
    try:
        raise subprocess.TimeoutExpired(["gh"], 60)
    except subprocess.TimeoutExpired as exc:
        try:
            raise RuntimeError("gh api timed out after 60s") from exc
        except RuntimeError as error:
            return error


class FlakyListing(FakeGitHub):
    """Fails the artifact listing with each of `errors` in turn: a string is
    gh's stderr on exit 1, an exception is raised from `gh_capture`."""

    def __init__(self, errors: list[str | BaseException]):
        fake = passing()
        super().__init__(fake.artifacts, fake.runs, fake.records)
        self.errors = errors
        self.timeouts: list[float | None] = []

    def __call__(
        self, args: list[str], **kwargs: Any
    ) -> subprocess.CompletedProcess[str]:
        if "--paginate" in args and any("actions/artifacts" in a for a in args):
            self.timeouts.append(kwargs.get("timeout_seconds"))
            if self.errors:
                self.calls.append(args)
                error = self.errors.pop(0)
                if isinstance(error, BaseException):
                    raise error
                return subprocess.CompletedProcess(args, 1, "", error)
        return super().__call__(args, **kwargs)

    def listings(self) -> int:
        """Whole listings tried."""
        return sum(
            "--paginate" in c and any("actions/artifacts?" in a for a in c)
            for c in self.calls
        )


class ATransientListingFailureIsReadAgain(unittest.TestCase):
    # gh prints an API error as `gh: <message> (HTTP <status>)`
    # (babysit_gh.GH_HTTP_STATUS_RE); a request that got no response prints
    # gh's "error connecting to <host>" or Go's net/http error instead.
    TRANSIENT: tuple[str | BaseException, ...] = (
        "gh: Bad Gateway (HTTP 502)",
        "gh: Service Unavailable (HTTP 503)",
        "error connecting to api.github.com\n"
        "check your internet connection or https://githubstatus.com",
        'Get "https://api.github.com/repos/o/r/actions/artifacts": '
        "read tcp 10.0.0.1:443: read: connection reset by peer",
        # A page body cut short: Go's JSON decoder error, as gh printed it in
        # pr-merge run 40819274416 (skip step, 2026-10-29T04:59:05Z).
        "unexpected end of JSON input",
    )
    NOT_TRANSIENT: tuple[str | BaseException, ...] = (
        "gh: Not Found (HTTP 404)",
        "gh: Bad credentials (HTTP 401)",
        "gh: Validation Failed (HTTP 422)",
        # GitHub's answer to a GITHUB_TOKEN without the needed permission.
        "gh: Resource not accessible by integration (HTTP 403)",
        # Rate limits (GitHub docs, "Rate limits for the REST API"): a fixed
        # short wait outlasts neither, so neither is read again.
        "gh: Too Many Requests (HTTP 429)",
        "gh: You have exceeded a secondary rate limit. (HTTP 403)",
        # As run 39906176584 logged it (pr-merge.yml, dispatch-full-run,
        # 2026-10-23T05:30:57Z).
        "gh: API rate limit exceeded for installation. If you reach out to"
        " GitHub Support for help, please include the request ID"
        " 8000:1DF2D:1EE39F:657D15:6ADAF110 and timestamp 2026-10-23"
        " 05:30:57 UTC. For more on scraping GitHub and how it may affect"
        " your rights, please review our Terms of Service"
        " (https://docs.github.com/en/site-policy/github-terms/"
        "github-terms-of-service) (HTTP 403)",
        # A read that used the whole gh timeout, gh with no credential
        # (exit 4), and gh missing from PATH (babysit_util.run_command).
        timed_out(),
        "To get started with GitHub CLI, please run:  gh auth login\n"
        "Alternatively, populate the GH_TOKEN environment variable with a "
        "GitHub API authentication token.",
        RuntimeError("gh executable not found on PATH"),
    )

    def judge(self, fake: FlakyListing) -> tuple[ve.Evidence, list[float]]:
        sleep = ve._listing_sleep
        sleep.reset_mock()
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            evidence = ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, pull())
        return evidence, [c.args[0] for c in sleep.call_args_list]

    def test_a_transient_failure_then_a_listing_reads_the_verdict(self) -> None:
        for error in self.TRANSIENT:
            with self.subTest(str(error)):
                fake = FlakyListing([error])
                evidence, sleeps = self.judge(fake)
                self.assertIsNone(evidence.refusal)
                self.assertEqual(fake.listings(), 2)
                self.assertEqual(sleeps, [2.0])

    def test_a_persistent_transient_failure_refuses_after_three_reads(self) -> None:
        fake = FlakyListing(["gh: Bad Gateway (HTTP 502)"] * 3)
        evidence, sleeps = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn("HTTP 502", evidence.detail or "")
        self.assertEqual(fake.listings(), 3)
        self.assertEqual(sleeps, [2.0, 4.0])

    def test_a_whole_listing_cut_short_is_read_once_more_at_most(self) -> None:
        # Each cut-short read may have paged every artifact: two whole reads,
        # never three, then the refusal.
        fake = FlakyListing(["unexpected end of JSON input"] * 3)
        evidence, sleeps = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn("unexpected end of JSON input", evidence.detail or "")
        self.assertEqual(fake.listings(), 2)
        self.assertEqual(sleeps, [2.0])

    def timed(self, clock: list[float]) -> FlakyListing:
        """Three 502s, the clock reading `clock` in turn, a 60s listing timeout
        (2,000 artifacts: three 27 s listings, so the cap is the timeout)."""
        fake = FlakyListing(["gh: Bad Gateway (HTTP 502)"] * 3)
        fake.live_total = 2_000
        with (
            mock.patch.object(ve, "_listing_clock", side_effect=clock),
            mock.patch.object(ve, "LISTING_TIMEOUT_SECONDS", 60.0),
        ):
            self.judge(fake)
        return fake

    def test_the_retries_share_one_read_timeout(self) -> None:
        # Deadline 0 + 60; each retry gets what is left after its wait ends.
        fake = self.timed([0.0, 1.0, 3.0, 20.0, 24.0])
        self.assertEqual(fake.timeouts, [60.0, 60.0 - 3.0, 60.0 - 24.0])

    def test_a_late_sleep_shortens_the_retry_timeout(self) -> None:
        # The 2s sleep returned at 30s: the retry gets 30s, not 57s.
        fake = self.timed([0.0, 1.0, 30.0, 59.0])
        self.assertEqual(fake.timeouts, [60.0, 30.0])

    def test_no_retry_when_the_sleep_ends_past_the_deadline(self) -> None:
        fake = self.timed([0.0, 1.0, 61.0])
        self.assertEqual(fake.timeouts, [60.0])
        self.assertEqual(fake.listings(), 1)

    def test_no_retry_once_the_timeout_is_spent(self) -> None:
        fake = self.timed([0.0, 58.5])
        self.assertEqual(fake.timeouts, [60.0])
        self.assertEqual(fake.listings(), 1)

    def test_any_other_failure_is_not_read_again(self) -> None:
        for error in self.NOT_TRANSIENT:
            with self.subTest(str(error)):
                fake = FlakyListing([error])
                evidence, sleeps = self.judge(fake)
                self.assertEqual(evidence.refusal, "verify:unreadable")
                self.assertEqual(fake.listings(), 1)
                self.assertEqual(sleeps, [])


class AListingOfManyPagesReadsWhole(unittest.TestCase):
    """The pages share one timeout (babysit_gh._run_pages): 76 pages at 1 s a
    page, as ci-status read 7,522 artifacts on 2026-10-27, outlast gh's 60 s
    default and must still read whole."""

    PAGES = 76

    def test_76_pages_at_one_second_each_read_whole(self) -> None:
        clock = [0.0]
        sent: list[str] = []

        def send(args, *, timeout_seconds, env_overrides, binary):
            self.assertGreater(timeout_seconds, 0)
            clock[0] += 1.0
            sent.append(args[1])
            page = len(sent)
            link = (
                f"<https://api.github.com/repositories/1/actions/artifacts"
                f'?per_page=100&page={page + 1}>; rel="next"'
                if page < self.PAGES
                else ""
            )
            body = json.dumps({"total_count": 7522, "artifacts": [{"id": page}]})
            return subprocess.CompletedProcess(args, 0, body, ""), {"link": link}

        with (
            mock.patch.object(gh, "_send", side_effect=send),
            mock.patch.object(gh.time, "monotonic", side_effect=lambda: clock[0]),
            mock.patch.object(ve, "_listing_clock", side_effect=lambda: clock[0]),
        ):
            pages = ve.Reader(REPO, "main", now=NOW)._read_listing()
        self.assertEqual(len(pages), self.PAGES)
        self.assertEqual(len(sent), self.PAGES)


class TheWholeListingTimeoutGrowsWithItsPages(unittest.TestCase):
    """The whole listings' shared timeout comes from GitHub's live
    `total_count`, read from one page before them: every whole listing and
    its top-up at 1 s a page (`LISTING_PAGE_SECONDS`), up to the 300 s cap.
    A listing too long for one whole read and its top-up inside the cap
    refuses before paging, with the reason in the detail, rather than
    running into a reader's step timeout as a bare `verify:unreadable`."""

    def first_timeout(self, total: int) -> float | None:
        fake = FlakyListing([])
        fake.live_total = total
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, pull())
        return fake.timeouts[0] if fake.timeouts else None

    def test_the_timeout_is_three_whole_listings_and_top_ups_at_a_second_a_page(
        self,
    ) -> None:
        # 2,000 artifacts: 20 pages, and 7 top-up pages, for each of 3 reads.
        self.assertEqual(self.first_timeout(2_000), 81.0)
        # 2,001 artifacts start a 21st page.
        self.assertEqual(self.first_timeout(2_001), 84.0)

    def test_the_timeout_stops_at_the_cap(self) -> None:
        # 10,450 artifacts, 105 pages, as on 2026-10-30: 336 s, capped.
        self.assertEqual(self.first_timeout(10_450), 300.0)
        # 293 pages and a 7-page top-up read in exactly the cap.
        self.assertEqual(self.first_timeout(29_300), 300.0)

    def test_a_listing_past_the_cap_refuses_before_paging_with_its_reason(
        self,
    ) -> None:
        fake = passing()
        fake.live_total = 29_301
        out = io.StringIO()
        with (
            mock.patch.object(policy, "pull_request", return_value=pull()),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            contextlib.redirect_stdout(out),
        ):
            ve.main(["evidence", "--repo", REPO, str(PR), HEAD], now=NOW)
        report = json.loads(out.getvalue())
        self.assertEqual(report["refusal"], "verify:unreadable")
        self.assertIn(
            "29301 artifacts in 294 pages need 301 s for a whole listing and its "
            "top-up at 1 s a page, past the 300 s listing cap",
            report["detail"],
        )
        self.assertEqual((fake.probes(), fake.full_listings(), fake.pages()), (1, 0, 0))

    def caller(
        self, limit: str, total: int, elapsed: float = 0.0
    ) -> tuple[ve.Evidence, FlakyListing]:
        """A reader a caller kills at `limit` seconds, `elapsed` seconds in."""
        fake = FlakyListing([])
        fake.live_total = total
        env = {ve.DEADLINE_ENV: limit, ve.CALLER_ENV: "verify-cap.mjs"}
        with (
            mock.patch.dict("os.environ", env),
            mock.patch.object(ve, "_elapsed", return_value=elapsed),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        ):
            evidence = ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, pull())
        return evidence, fake

    def test_a_caller_limit_too_short_for_the_listing_refuses_naming_it(
        self,
    ) -> None:
        # verify-cap.mjs kills its reader at 120 s: 120 - 15 leaves 105 s, and
        # 10,450 artifacts (105 pages and a 7-page top-up) need 112 s.
        evidence, fake = self.caller("120", 10_450)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn(
            "10450 artifacts in 105 pages need 112 s for a whole listing and its "
            "top-up at 1 s a page, past the 105 s left of verify-cap.mjs's 120 s "
            "limit",
            evidence.detail or "",
        )
        self.assertEqual(fake.timeouts, [])
        # pr-unblock verify-cap.mjs skips the round on this detail, for this
        # run only; the 300 s cap's own refusal is not the caller's.
        self.assertTrue((evidence.detail or "").startswith(ve.DEADLINE_UNREADABLE))
        evidence, _ = self.caller("900", 29_301)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn("past the 300 s listing cap", evidence.detail or "")
        self.assertFalse((evidence.detail or "").startswith(ve.DEADLINE_UNREADABLE))

    def test_the_count_read_fits_in_what_the_caller_leaves(self) -> None:
        # 60 s into verify-cap.mjs's 120 s: 120 - 60 - 15 leaves 45 s.
        _, fake = self.caller("120", 2_000, elapsed=60.0)
        self.assertEqual(fake.count_timeouts, [45.0])
        # With no caller limit the count read keeps gh's default timeout.
        _, fake = self.caller("", 2_000)
        self.assertEqual(fake.count_timeouts, [None])

    def test_a_caller_limit_already_spent_refuses_before_the_count_read(
        self,
    ) -> None:
        # 110 s into a 120 s limit leaves nothing after the 15 s margin.
        evidence, fake = self.caller("120", 2_000, elapsed=110.0)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertTrue((evidence.detail or "").startswith(ve.DEADLINE_UNREADABLE))
        self.assertIn("verify-cap.mjs's 120 s limit", evidence.detail or "")
        self.assertEqual((fake.probes(), fake.timeouts), (0, []))

    def test_a_small_listing_keeps_gh_s_60_s_default_as_its_floor(self) -> None:
        # 100 artifacts: 1 page and a 7-page top-up, three times, is 24 s,
        # under gh's 60 s per-call default the listing timeout replaced.
        self.assertEqual(self.first_timeout(100), 60.0)
        # The floor never passes what a caller leaves: 50 - 15 is 35 s.
        _, fake = self.caller("50", 100)
        self.assertEqual(fake.timeouts[0], 35.0)

    def test_a_caller_limit_bounds_the_listing_timeout(self) -> None:
        # enable-auto-merge.mjs kills its reader at 240 s: 225 s left, under
        # the 300 s cap and over the 112 s one whole listing needs.
        _, fake = self.caller("240", 10_450)
        self.assertEqual(fake.timeouts[0], 225.0)
        # A limit past the cap leaves the cap; one that is not a number is
        # ignored.
        for limit in ("900", "soon", "0"):
            with self.subTest(limit):
                _, fake = self.caller(limit, 10_450)
                self.assertEqual(fake.timeouts[0], 300.0)

    def test_a_count_that_does_not_read_refuses_without_paging(self) -> None:
        for error, reads in (
            ("gh: Not Found (HTTP 404)", 1),
            ("gh: Service Unavailable (HTTP 503)", 1 + len(ve.LISTING_WAITS)),
        ):
            with self.subTest(error):
                fake = passing()
                fake.count_fail = error
                with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
                    result = ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, pull())
                self.assertEqual(result.refusal, "verify:unreadable")
                self.assertIn(error, result.detail or "")
                self.assertEqual((fake.probes(), fake.full_listings()), (reads, 0))


# The runner's clock while these tests list, and GitHub's `Date` a few seconds
# later.
LISTED_AT = datetime(2026, 10, 16, 12, 0, tzinfo=UTC)
DATE = "Fri, 16 Oct 2026 12:00:05 GMT"


def stamp(when: datetime) -> str:
    return when.strftime("%Y-%m-%dT%H:%M:%SZ")


def dated(
    name: str,
    run_id: int,
    artifact_id: int,
    created: datetime,
    *,
    expires: datetime | None = None,
    expired: bool = False,
) -> dict[str, Any]:
    """A listed artifact as GitHub gives it: an id, created_at and expires_at."""
    return artifact(name, run_id, expired=expired) | {
        "id": artifact_id,
        "created_at": stamp(created),
        "expires_at": stamp(expires or created + timedelta(days=90)),
    }


VERIFY_CAP = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/pr-unblock/verify-cap.mjs"
)


def verify_cap_env(reads: int = 1) -> dict[str, str]:
    """The `BABYSIT_VERIFY_*` environment verify-cap.mjs starts this reader with
    on read number `reads`, every read before it answering `DEADLINE_UNREADABLE`."""
    script = f"""
    import {{ DEADLINE_UNREADABLE, verifyCapReader }} from {json.dumps(VERIFY_CAP.as_uri())};
    const head = "a".repeat(40);
    const report = {{ head, refusal: "verify:unreadable", detail: DEADLINE_UNREADABLE }};
    const spawn = (command, args, options) => {{
      console.log(JSON.stringify(options.env));
      return {{ status: 0, stdout: JSON.stringify(report), stderr: "" }};
    }};
    const read = verifyCapReader({{}}, {{ spawn, log: () => {{}} }});
    for (let number = 1; number <= {reads}; number += 1) {{
      await read({{ number, head }});
    }}
    """
    out = subprocess.run(
        ["node", "--input-type=module", "-e", script],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    env = json.loads(out.strip().splitlines()[-1])
    return {k: v for k, v in env.items() if k.startswith("BABYSIT_VERIFY_")}


class TheListingBuildsOnACarriedOne(unittest.TestCase):
    """A listing a trusted pr-merge run saved (`BABYSIT_VERIFY_LISTING_CARRY`)
    is a base: the reader pages only down past it, keeps the result only when
    it holds the first page's live `total_count`, and lists every page on any
    doubt."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.carry = pathlib.Path(tmp.name, "verify-listing-carry.json")
        self.saved = pathlib.Path(tmp.name, "verify-listing.json")
        self.failed = pathlib.Path(f"{self.saved}{ve.FAILED_LISTING_SUFFIX}")
        for patcher in (
            mock.patch.dict(
                "os.environ",
                {
                    "BABYSIT_VERIFY_LISTING_CARRY": str(self.carry),
                    "BABYSIT_VERIFY_LISTING": str(self.saved),
                },
            ),
            mock.patch.object(ve, "_wall_clock", side_effect=lambda: LISTED_AT),
            mock.patch.object(ve, "LISTING_PAGE_SIZE", 2),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)
        sleep = mock.patch.object(ve, "_listing_sleep")
        self.sleep = sleep.start()
        self.addCleanup(sleep.stop)
        # The base: a pass at the head (run 1) and three older artifacts,
        # read 10 minutes ago.
        self.base_at = LISTED_AT - timedelta(minutes=10)
        old = self.base_at - timedelta(hours=3)
        self.base = [
            dated(named(HEAD, "pass"), 1, 1000, self.base_at - timedelta(minutes=5)),
            dated("pr-merge-gate-cursor", 3, 900, old),
            dated("pr-merge-gate-cursor", 3, 800, old),
            dated("pr-merge-gate-cursor", 3, 700, old),
        ]

    def write_carry(self, artifacts: list[Any], at: datetime | None = None) -> None:
        self.carry.write_text(
            json.dumps(
                {"fetchedAt": (at or self.base_at).isoformat(), "artifacts": artifacts}
            )
        )

    def fake(self, *extra: dict[str, Any], base: list[Any] | None = None) -> FakeGitHub:
        """GitHub now: the base's artifacts (or `base`) and `extra`."""
        artifacts = [*(self.base if base is None else base), *extra]
        fake = FakeGitHub(
            artifacts, {1: run(1), 2: run(2)}, {named(HEAD, "pass"): record()}
        )
        return fake

    def judge(self, fake: FakeGitHub) -> tuple[ve.Reader, ve.Evidence]:
        def page(args: list[str], **kwargs: Any) -> Any:
            return fake(args, **kwargs), {"date": DATE}

        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve, "gh_api_with_headers", side_effect=page),
        ):
            reader = ve.Reader(REPO, "main", now=NOW)
            return reader, reader.evidence(PR, HEAD, pull())

    def test_a_fail_uploaded_since_is_read_from_the_first_page_alone(self) -> None:
        self.write_carry(self.base)
        fake = self.fake(dated(named(HEAD, "fail"), 2, 1100, LISTED_AT))
        reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(reader.listing_mode, "incremental")
        # Page 1 holds 1100 and 1000 (created within the overlap), page 2
        # holds 900, created before it: two pages, no full listing.
        self.assertEqual((fake.pages(), fake.full_listings()), (2, 0))
        saved = json.loads(self.saved.read_text())
        self.assertEqual(saved["fetchedAt"], LISTED_AT.isoformat())
        self.assertEqual(
            [a["id"] for a in saved["artifacts"]], [1100, 1000, 900, 800, 700]
        )

    def test_the_overlap_reads_a_lower_id_created_after_the_base(self) -> None:
        # 950 is below the base's highest id (1000) but was created after the
        # base was read, so the base lacks it. The first page (1000, 990)
        # already reaches the highest id; paging goes on to 900, created
        # before the overlap, so the second page brings 950.
        base = [
            self.base[0],
            dated("pr-merge-gate-cursor", 3, 990, self.base_at - timedelta(minutes=30)),
            *self.base[1:],
        ]
        self.write_carry(base)
        fake = self.fake(dated(named(HEAD, "fail"), 2, 950, LISTED_AT), base=base)
        reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual((fake.pages(), fake.full_listings()), (2, 0))

    def test_an_expired_carried_entry_is_dropped_by_githubs_date(self) -> None:
        # GitHub no longer lists 800 (its expiry passed by the page's Date,
        # 12:00:05, though not by the runner's clock, 12:00:00) nor 700
        # (marked expired); its live count leaves both out.
        lapsed = dated(
            "pr-merge-gate-cursor",
            3,
            800,
            self.base_at,
            expires=LISTED_AT + timedelta(seconds=2),
        )
        gone = dated("pr-merge-gate-cursor", 3, 700, self.base_at, expired=True)
        self.write_carry([*self.base[:2], lapsed, gone])
        fake = self.fake(base=self.base[:2])
        reader, evidence = self.judge(fake)
        self.assertIsNone(evidence.refusal)
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual(fake.full_listings(), 0)
        ids = [a["id"] for a in json.loads(self.saved.read_text())["artifacts"]]
        self.assertEqual(ids, [1000, 900])

    def test_a_carried_entry_the_pages_no_longer_hold_is_dropped(self) -> None:
        # An overwrite deletes 1000's artifact and uploads 1050 in its place.
        self.write_carry(self.base)
        fake = self.fake(
            dated(named(HEAD, "pass"), 1, 1050, LISTED_AT), base=self.base[1:]
        )
        reader, evidence = self.judge(fake)
        self.assertIsNone(evidence.refusal)
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual(fake.full_listings(), 0)
        ids = [a["id"] for a in json.loads(self.saved.read_text())["artifacts"]]
        self.assertEqual(ids, [1050, 900, 800, 700])

    def tail(self, *expiring: tuple[int, int]) -> list[dict[str, Any]]:
        """The base with four more old artifacts (600 to 300) below it, each
        `(id, minutes)` among them expiring that many minutes after GitHub's
        `Date`."""
        soon = dict(expiring)
        old = self.base_at - timedelta(hours=3)
        return [
            *self.base,
            *(
                dated(
                    "pr-merge-gate-cursor",
                    3,
                    i,
                    old,
                    expires=LISTED_AT + timedelta(minutes=soon[i])
                    if i in soon
                    else None,
                )
                for i in (600, 500, 400, 300)
            ),
        ]

    def test_a_carried_entry_deleted_before_its_expiry_is_read_again(self) -> None:
        # GitHub deleted 500 half an hour before its expires_at, as it did on
        # 2026-11-01; 400 expires 40 minutes on and stands. The base holds both,
        # so first page and base hold one more than the live count. The pages
        # around the entries near expiry decide them instead of a full listing.
        base = self.tail((500, 30), (400, 40))
        self.write_carry(base)
        fake = self.fake(base=[a for a in base if a["id"] != 500])
        reader, evidence = self.judge(fake)
        self.assertIsNone(evidence.refusal)
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual(fake.full_listings(), 0)
        # Page 1 (1000, 900) reaches the base; page 3 (600, 400) brackets 500
        # and 400, the entries near expiry.
        self.assertEqual(fake.pages(), 2)
        ids = [a["id"] for a in json.loads(self.saved.read_text())["artifacts"]]
        self.assertEqual(ids, [1000, 900, 800, 700, 600, 400, 300])

    def test_an_early_deletion_out_of_expiry_order_is_read_again(self) -> None:
        # 400 expires before 500 but GitHub deleted only 400: the pages, not
        # the expiry order, decide which entry went.
        base = self.tail((500, 30), (400, 20))
        self.write_carry(base)
        fake = self.fake(base=[a for a in base if a["id"] != 400])
        reader, _ = self.judge(fake)
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual(fake.full_listings(), 0)
        # Page 3 (600, 500) does not reach 400; page 4 (300) ends the listing.
        self.assertEqual(fake.pages(), 3)
        ids = [a["id"] for a in json.loads(self.saved.read_text())["artifacts"]]
        self.assertEqual(ids, [1000, 900, 800, 700, 600, 500, 300])

    def test_a_fail_a_forged_carry_drops_beside_an_early_deletion_counts(
        self,
    ) -> None:
        # A forged carry leaves out the FAIL 450 GitHub lists between 500 and
        # 400, both deleted early: the region's pages bring the FAIL back.
        base = self.tail((500, 30), (400, 40))
        self.write_carry(base)
        fail = dated(named(EARLIER, "fail"), 2, 450, self.base_at - timedelta(days=2))
        live = [a for a in base if a["id"] not in (500, 400)]
        fake = self.fake(fail, base=live)
        reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual(fake.full_listings(), 0)
        ids = [a["id"] for a in json.loads(self.saved.read_text())["artifacts"]]
        self.assertEqual(ids, [1000, 900, 800, 700, 600, 450, 300])

    def test_a_failed_read_of_the_pages_near_expiry_lists_every_page(self) -> None:
        # Page 3, the one around 500 and 400, answers a 502 on every read:
        # past the page's own retries (`LISTING_WAITS`), like any failed
        # incremental read, every page is listed with no `INCREMENTAL_WAITS`.
        base = self.tail((500, 30), (400, 40))
        self.write_carry(base)
        fake = self.fake(base=[a for a in base if a["id"] != 500])

        def page(args: list[str], **kwargs: Any) -> Any:
            if any(a.endswith("&page=3") for a in args):
                failed = subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
                return failed, {}
            return fake(args, **kwargs), {"date": DATE}

        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve, "gh_api_with_headers", side_effect=page),
        ):
            reader = ve.Reader(REPO, "main", now=NOW)
            reader.evidence(PR, HEAD, pull())
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual(fake.full_listings(), 1)
        waits = [c.args[0] for c in self.sleep.call_args_list]
        self.assertEqual(waits, list(ve.LISTING_WAITS))

    def test_a_deletion_far_from_expiry_still_lists_every_page(self) -> None:
        # 300 expires in 90 days but GitHub no longer lists it, and nothing
        # in the base is near expiry: no region to read, so every page.
        base = self.tail()
        self.write_carry(base)
        fake = self.fake(base=[a for a in base if a["id"] != 300])
        reader, _ = self.judge(fake)
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual(fake.full_listings(), 1)

    def page_numbers(self, fake: FakeGitHub) -> list[int]:
        """The single pages read, in order."""
        return [
            int(a.rsplit("&page=", 1)[1])
            for c in fake.calls
            for a in c
            if "&page=" in a
        ]

    def test_a_deletion_between_region_pages_keeps_the_fail_it_shifts(
        self,
    ) -> None:
        # The carry holds 1000 to 300 and FAIL 450. By page 1 GitHub dropped
        # 800 (90 days from expiry) and 500 (expiring in 30 minutes): live
        # count 7, the listing 9. The re-read around 500 takes page 2 (700,
        # 600); 600 is deleted; page 3 is then (400, 300), so 450 is in
        # neither read. Dropping it would leave 7, the live count, with the
        # FAIL gone: it is read by id (live) and kept, so the count stays
        # over and the one whole listing judges the FAIL.
        old = self.base_at - timedelta(hours=3)
        near = LISTED_AT + timedelta(minutes=30)
        fail = dated(named(EARLIER, "fail"), 2, 450, self.base_at - timedelta(days=2))
        carry = [
            *self.base,
            dated("pr-merge-gate-cursor", 3, 600, old),
            dated("pr-merge-gate-cursor", 3, 500, old, expires=near),
            fail,
            *(dated("pr-merge-gate-cursor", 3, i, old) for i in (400, 300)),
        ]
        self.write_carry(carry)
        fake = self.fake(base=[a for a in carry if a["id"] not in (800, 500)])
        shifted = [False]

        def page(args: list[str], **kwargs: Any) -> Any:
            answer = fake(args, **kwargs)
            if not shifted[0] and any(a.endswith("&page=2") for a in args):
                shifted[0] = True
                fake.artifacts = [a for a in fake.artifacts if a["id"] != 600]
            return answer, {"date": DATE}

        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve, "gh_api_with_headers", side_effect=page),
        ):
            reader = ve.Reader(REPO, "main", now=NOW)
            evidence = reader.evidence(PR, HEAD, pull())
        self.assertEqual(self.page_numbers(fake)[:3], [1, 2, 3])
        self.assertEqual(evidence.refusal, "verify:earlier-fail", evidence.detail)
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual(fake.full_listings(), 1)

    def test_an_id_the_region_pages_omit_is_dropped_only_on_a_404(self) -> None:
        # GitHub deleted 500 early; the region's page shows it gone. A 404
        # for 500 drops it (incremental), after a 502 too; a 502 through the
        # read's waits fails the incremental read, and no id reads left keeps
        # 500: either way the over-count takes the one whole listing.
        attempts = 1 + len(ve.LISTING_WAITS)
        for label, fail, cap, mode, reads in (
            ("404", set(), ve.NEAR_EXPIRY_ID_READ_CAP, "incremental", 1),
            ("502-404", set(), ve.NEAR_EXPIRY_ID_READ_CAP, "incremental", 2),
            ("502", {"artifacts/500"}, ve.NEAR_EXPIRY_ID_READ_CAP, "full", attempts),
            ("cap", set(), 0, "full", 0),
        ):
            with self.subTest(label):
                for path in (self.saved, self.failed):
                    path.unlink(missing_ok=True)
                pathlib.Path(f"{self.saved}{ve.OVERCOUNT_FALLBACK_SUFFIX}").unlink(
                    missing_ok=True
                )
                base = self.tail((500, 30), (400, 40))
                self.write_carry(base)
                fake = self.fake(base=[a for a in base if a["id"] != 500])
                fake.fail = fail
                blipped = [label != "502-404"]

                def page(args: list[str], **kwargs: Any) -> Any:
                    if not blipped[0] and args[-1].endswith("/artifacts/500"):
                        blipped[0] = True
                        fake.calls.append(args)
                        failed = subprocess.CompletedProcess(
                            args, 1, "", "gh: Bad Gateway (HTTP 502)"
                        )
                        return failed, {}
                    return fake(args, **kwargs), {"date": DATE}

                with (
                    mock.patch.object(ve, "NEAR_EXPIRY_ID_READ_CAP", cap),
                    mock.patch.object(postmerge, "gh_capture", side_effect=fake),
                    mock.patch.object(ve, "gh_api_with_headers", side_effect=page),
                ):
                    reader = ve.Reader(REPO, "main", now=NOW)
                    evidence = reader.evidence(PR, HEAD, pull())
                self.assertIsNone(evidence.refusal, evidence.detail)
                self.assertEqual(reader.listing_mode, mode)
                by_id = [c for c in fake.calls if c[-1].endswith("/artifacts/500")]
                self.assertEqual(len(by_id), reads)

    def climbing(self, missing: int) -> tuple[ve.Reader, FakeGitHub]:
        """A carry whose phantoms above the near-expiry 500 outnumber the
        surplus, since `missing` live artifacts below it are not carried: the
        re-read starts below 500's page and walks up."""
        old = self.base_at - timedelta(hours=3)
        near = LISTED_AT + timedelta(minutes=30)
        phantoms = (850, 750, 650, 550, 450) if missing == 4 else (
            875, 850, 825, 775, 750, 650, 550
        )
        held = [
            *self.base,
            dated("pr-merge-gate-cursor", 3, 600, old),
            dated("pr-merge-gate-cursor", 3, 500, old, expires=near),
            *(dated("pr-merge-gate-cursor", 3, i, old) for i in (400, 300)),
        ]
        self.write_carry(
            [*held, *(dated("pr-merge-gate-cursor", 3, i, old) for i in phantoms)]
        )
        below = [250, 240, 230, 220, 210, 200][:missing]
        fake = self.fake(
            base=[*held, *(dated("pr-merge-gate-cursor", 3, i, old) for i in below)]
        )
        reader, _ = self.judge(fake)
        return reader, fake

    def test_the_region_walks_up_to_the_page_that_holds_its_top(self) -> None:
        # Surplus 1, 500 at listing index 9: the start page is 5 (250, 240),
        # page 4 (400, 300) is still below 500, page 3 (600, 500) holds it.
        reader, fake = self.climbing(4)
        self.assertEqual(self.page_numbers(fake), [1, 5, 4, 3])
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual(fake.full_listings(), 0)

    def test_the_region_walk_stops_at_its_upward_bound(self) -> None:
        # Surplus 1, 500 at listing index 12: the start page is 6, and the
        # walk may climb surplus // 2 + 2 = 2 pages, to 4, short of page 3:
        # the group stays unbracketed and the over-count takes a whole listing.
        reader, fake = self.climbing(6)
        self.assertEqual(self.page_numbers(fake)[:4], [1, 6, 5, 4])
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual(fake.full_listings(), 1)

    def test_the_pages_near_expiry_stop_at_their_cap(self) -> None:
        # Out of expiry order, the region takes two pages (3 and 4). Capped
        # at one, the count stays over: one whole listing, whose top-up
        # (page 1) holds the count, and no INCREMENTAL_WAITS.
        base = self.tail((500, 30), (400, 20))
        self.write_carry(base)
        fake = self.fake(base=[a for a in base if a["id"] != 400])
        with mock.patch.object(ve, "NEAR_EXPIRY_PAGE_CAP", 1):
            reader, evidence = self.judge(fake)
        self.assertIsNone(evidence.refusal, evidence.detail)
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual(fake.full_listings(), 1)
        # Page 1, one capped region page, then the top-up's page 1.
        self.assertEqual(fake.pages(), 3)
        self.assertEqual(self.sleep.call_args_list, [])

    def test_two_readers_that_over_count_take_one_whole_listing_a_job(
        self,
    ) -> None:
        # GitHub dropped 300, 90 days from expiry, so both Readers' pages over
        # the carry hold one more than the live count. The first takes the
        # whole listing, which holds the count, and allows. The second, its
        # saved listing gone (as past its age), refuses without another.
        base = self.tail()
        self.write_carry(base)
        fake = self.fake(base=[a for a in base if a["id"] != 300])
        _, first = self.judge(fake)
        self.assertIsNone(first.refusal, first.detail)
        self.assertEqual(fake.full_listings(), 1)
        self.saved.unlink()
        reader, second = self.judge(fake)
        self.assertEqual(second.refusal, "verify:unreadable")
        self.assertIn("already took its whole listing", second.detail or "")
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual(fake.full_listings(), 1)
        # Not a failed listing: #11926's note stays unwritten.
        self.assertFalse(self.failed.exists())

    def test_an_over_count_refused_before_paging_leaves_the_job_its_listing(
        self,
    ) -> None:
        # pr-feedback-dispatch's order: PR A's Reader over-counts under
        # verify-cap's limit, and its whole listing does not fit, so it
        # refuses before paging. PR B's Reader, with the time, takes it.
        base = self.tail()
        self.write_carry(base)
        fake = self.fake(base=[a for a in base if a["id"] != 300])
        first = self.against_the_clock(fake, 0.0, limit="20")
        self.assertEqual(first.refusal, "verify:unreadable")
        self.assertTrue(first.detail.startswith(ve.DEADLINE_UNREADABLE))
        self.assertEqual(fake.full_listings(), 0)
        second = self.against_the_clock(fake, 0.0)
        self.assertIsNone(second.refusal, second.detail)
        self.assertEqual(fake.full_listings(), 1)

    def test_an_over_count_listing_out_of_the_callers_time_refuses_so_later(
        self,
    ) -> None:
        # A's whole listing pages, then its top-up runs out of the caller's
        # time. B's Reader takes no second whole listing, and its refusal
        # keeps the caller-limit prefix, so verify-cap skips B's round too.
        base = self.tail()
        self.write_carry(base)
        fake = self.fake(base=[a for a in base if a["id"] != 300])
        first = self.against_the_clock(fake, 50.0, limit="60")
        self.assertTrue(first.detail.startswith(ve.DEADLINE_UNREADABLE))
        self.assertEqual(fake.full_listings(), 1)
        second = self.against_the_clock(fake, 0.0)
        self.assertEqual(second.refusal, "verify:unreadable")
        self.assertTrue(second.detail.startswith(ve.DEADLINE_UNREADABLE))
        self.assertIn("already took its whole listing", second.detail)
        self.assertEqual(fake.full_listings(), 1)

    def test_an_over_count_the_pages_near_expiry_leave_takes_one_whole_listing(
        self,
    ) -> None:
        # GitHub dropped 500 early, which the region's pages settle, and 300,
        # 90 days from expiry, which no page near expiry reaches. The whole
        # listing skips 700 at a page boundary, so its top-up is one short:
        # another whole listing would restore 700, but an over-count takes
        # one a job, and the refusal is noted for the job's later Readers.
        base = self.tail((500, 30))
        self.write_carry(base)
        fake = self.fake(base=[a for a in base if a["id"] not in (500, 300)])
        fake.full_skips = [{700}]
        reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn("1 whole listing never held", evidence.detail or "")
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual(fake.full_listings(), 1)
        self.assertEqual(self.sleep.call_args_list, [])
        self.assertIn("1 whole listing never held", self.failed.read_text())
        listed = (fake.pages(), fake.full_listings())
        _, again = self.judge(fake)
        self.assertEqual(again.refusal, "verify:unreadable")
        self.assertEqual((fake.pages(), fake.full_listings()), listed)

    def test_a_count_other_than_githubs_lists_every_page(self) -> None:
        # A forged carry drops an old FAIL (600): the live count holds it, so
        # the merged listing is one short and every page is read.
        fail = dated(named(EARLIER, "fail"), 2, 600, self.base_at - timedelta(days=2))
        self.write_carry(self.base)
        fake = self.fake(fail)
        reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertEqual(reader.listing_mode, "full")
        # The incremental first page, read three times with a 15 s and a 30 s
        # wait between, then the whole listing's own check.
        self.assertEqual((fake.pages(), fake.full_listings()), (3 + 1, 1))
        self.assertEqual([c.args[0] for c in self.sleep.call_args_list], [15.0, 30.0])

    def test_a_caller_that_skips_the_waits_lists_every_page_after_one_miss(
        self,
    ) -> None:
        # A forged carry under BABYSIT_VERIFY_NO_INCREMENTAL_WAITS=1: one
        # incremental first page, no wait, then the whole listing, which still
        # holds the dropped FAIL.
        fail = dated(named(EARLIER, "fail"), 2, 600, self.base_at - timedelta(days=2))
        self.write_carry(self.base)
        fake = self.fake(fail)
        with mock.patch.dict(
            "os.environ", {"BABYSIT_VERIFY_NO_INCREMENTAL_WAITS": "1"}
        ):
            reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual((fake.pages(), fake.full_listings()), (1 + 1, 1))
        self.sleep.assert_not_called()
        # Any other value keeps the waits (with no listing saved by the first).
        self.saved.unlink()
        self.sleep.reset_mock()
        with mock.patch.dict(
            "os.environ", {"BABYSIT_VERIFY_NO_INCREMENTAL_WAITS": "true"}
        ):
            self.judge(self.fake(fail))
        self.assertEqual([c.args[0] for c in self.sleep.call_args_list], [15.0, 30.0])

    def verify_cap_read(
        self, reads: int = 1
    ) -> tuple[ve.Reader, ve.Evidence, FakeGitHub]:
        """Read number `reads` of a verify-cap.mjs reader on a carried listing
        whose pages miss GitHub's live count, a count no whole listing fits in
        the 105 s its 120 s kill limit leaves. The miss outlasts the waits
        unless a test ends it."""
        self.write_carry(self.base)
        fake = self.miss = self.fake()
        fake.live_total = 12_000
        with (
            mock.patch.dict("os.environ", verify_cap_env(reads)),
            mock.patch.object(ve, "_elapsed", return_value=0.0),
        ):
            reader, evidence = self.judge(fake)
        return reader, evidence, fake

    def test_a_count_miss_under_verify_cap_settles_on_the_next_read(self) -> None:
        self.sleep.side_effect = lambda _: setattr(self.miss, "live_total", None)
        reader, evidence, fake = self.verify_cap_read()
        self.assertIsNone(evidence.refusal, evidence.detail)
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual((fake.pages(), fake.full_listings()), (2, 0))
        self.assertEqual([c.args[0] for c in self.sleep.call_args_list], [15.0])

    def test_a_miss_that_outlasts_the_waits_still_refuses_for_the_caller_limit(
        self,
    ) -> None:
        _, evidence, fake = self.verify_cap_read()
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertTrue(evidence.detail.startswith(ve.DEADLINE_UNREADABLE))
        self.assertEqual((fake.pages(), fake.full_listings()), (3, 0))
        self.assertEqual([c.args[0] for c in self.sleep.call_args_list], [15.0, 30.0])

    def test_a_read_after_a_refusal_for_the_caller_limit_takes_no_waits(self) -> None:
        _, evidence, fake = self.verify_cap_read(reads=2)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertTrue(evidence.detail.startswith(ve.DEADLINE_UNREADABLE))
        self.assertEqual((fake.pages(), fake.full_listings()), (1, 0))
        self.sleep.assert_not_called()

    def test_a_failed_first_read_is_not_read_again_on_the_base(self) -> None:
        # A 429, a rate-limit 403 or a timeout on the first incremental page
        # is never read again (`_read_listing`'s rule): the whole listing
        # follows at once, as before the count-miss retry.
        failures: dict[str, Any] = {
            "429": subprocess.CompletedProcess(
                [], 1, "", "gh: API rate limit exceeded (HTTP 429)"
            ),
            "rate-limit 403": subprocess.CompletedProcess(
                [], 1, "", "gh: API rate limit exceeded for installation (HTTP 403)"
            ),
            "timeout": timed_out(),
        }
        for label, failure in failures.items():
            with self.subTest(label):
                self.saved.unlink(missing_ok=True)
                self.write_carry(self.base)
                fake = self.fake(dated(named(HEAD, "fail"), 2, 1100, LISTED_AT))
                first = [True]

                def page(args: list[str], **kwargs: Any) -> Any:
                    if first[0] and args[1].endswith("&page=1"):
                        first[0] = False
                        fake.calls.append(args)
                        if isinstance(failure, BaseException):
                            raise failure
                        return failure, {}
                    return fake(args, **kwargs), {"date": DATE}

                with (
                    mock.patch.object(postmerge, "gh_capture", side_effect=fake),
                    mock.patch.object(ve, "gh_api_with_headers", side_effect=page),
                ):
                    reader = ve.Reader(REPO, "main", now=NOW)
                    evidence = reader.evidence(PR, HEAD, pull())
                self.assertEqual(evidence.refusal, "verify:fail")
                self.assertEqual(reader.listing_mode, "full")
                # The failed page, then the whole listing and its top-up, two
                # pages down to 900; no second read on the carried base.
                self.assertEqual((fake.pages(), fake.full_listings()), (3, 1))
                self.sleep.assert_not_called()

    def cut_short(
        self, times: int, failure: Any
    ) -> tuple[ve.Reader, ve.Evidence, FakeGitHub]:
        """The first incremental page fails with `failure` `times` times."""
        self.write_carry(self.base)
        fake = self.fake(dated(named(HEAD, "fail"), 2, 1100, LISTED_AT))
        left = [times]

        def page(args: list[str], **kwargs: Any) -> Any:
            if left[0] and args[1].endswith("&page=1"):
                left[0] -= 1
                fake.calls.append(args)
                return failure, {}
            return fake(args, **kwargs), {"date": DATE}

        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve, "gh_api_with_headers", side_effect=page),
        ):
            reader = ve.Reader(REPO, "main", now=NOW)
            return reader, reader.evidence(PR, HEAD, pull()), fake

    def test_a_cut_short_page_is_read_again_without_a_full_listing(self) -> None:
        # As gh printed it in pr-merge run 40819274416, and a body cut short
        # that gh still exits 0 on.
        failures = {
            "gh error": subprocess.CompletedProcess(
                [], 1, "", "unexpected end of JSON input"
            ),
            "short body": subprocess.CompletedProcess(
                [], 0, '{"total_count": 5, "art', ""
            ),
            "502": subprocess.CompletedProcess([], 1, "", "gh: Bad Gateway (HTTP 502)"),
        }
        for label, failure in failures.items():
            with self.subTest(label):
                self.saved.unlink(missing_ok=True)
                self.sleep.reset_mock()
                reader, evidence, fake = self.cut_short(1, failure)
                self.assertEqual(evidence.refusal, "verify:fail")
                self.assertEqual(reader.listing_mode, "incremental")
                # The failed page, then pages 1 and 2 down to 900.
                self.assertEqual((fake.pages(), fake.full_listings()), (3, 0))
                self.assertEqual([c.args[0] for c in self.sleep.call_args_list], [2.0])

    def test_a_page_cut_short_every_time_lists_every_page(self) -> None:
        failure = subprocess.CompletedProcess([], 1, "", "unexpected end of JSON input")
        # The first page fails all three reads, so the whole listing follows
        # and its top-up reads the pages.
        reader, evidence, fake = self.cut_short(3, failure)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual(fake.full_listings(), 1)
        self.assertEqual([c.args[0] for c in self.sleep.call_args_list], [2.0, 4.0])

    def test_a_count_off_once_is_read_again_on_the_same_base(self) -> None:
        # The first read's live count is one more than its pages hold, as
        # when a page boundary moves during the read; the next read holds it
        # and no page is listed whole.
        self.write_carry(self.base)
        fake = self.fake(dated(named(HEAD, "fail"), 2, 1100, LISTED_AT))
        rest, off = fake.rest, [len(self.base) + 2]

        def first_read_off(args: list[str], *rest_args: Any) -> Any:
            first = any(a.endswith("&page=1") for a in args)
            fake.live_total = off.pop() if first and off else None
            return rest(args, *rest_args)

        fake.rest = first_read_off  # type: ignore[method-assign]
        reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual((fake.pages(), fake.full_listings()), (4, 0))

    def misses_then_reads(self, misses: int) -> tuple[FakeGitHub, str]:
        """GitHub's live count one more than the pages hold on the first
        `misses` incremental reads, then right; the judge's stderr."""
        self.write_carry(self.base)
        fake = self.fake(dated(named(HEAD, "fail"), 2, 1100, LISTED_AT))
        rest, off = fake.rest, [len(self.base) + 2] * misses

        def reads_off(args: list[str], *rest_args: Any) -> Any:
            first = any(a.endswith("&page=1") for a in args)
            if first:
                fake.live_total = off.pop() if off else None
            return rest(args, *rest_args)

        fake.rest = reads_off  # type: ignore[method-assign]
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(reader.listing_mode, "incremental")
        return fake, stderr.getvalue()

    def test_a_miss_that_outlasts_one_read_is_read_again_after_a_wait(self) -> None:
        # Two misses, then the third read holds the count: three reads of two
        # pages, a 15 s and a 30 s wait between them, and no whole listing.
        fake, _ = self.misses_then_reads(2)
        self.assertEqual((fake.pages(), fake.full_listings()), (6, 0))
        self.assertEqual([c.args[0] for c in self.sleep.call_args_list], [15.0, 30.0])

    def test_each_miss_prints_its_counts_on_stderr(self) -> None:
        # Read 1: pages (1100, 1000) and (900, 800), 900 created before the
        # overlap, so 4 fresh and the base's 700 kept: 5 listed against a
        # live count of 6, the base read 10 min before GitHub's Date (12:00:05).
        _, stderr = self.misses_then_reads(1)
        lines = [
            line
            for line in stderr.splitlines()
            if line.startswith("babysit-listing-miss ")
        ]
        self.assertEqual(len(lines), 1, stderr)
        self.assertEqual(
            json.loads(lines[0].removeprefix("babysit-listing-miss ")),
            {
                "stage": "incremental",
                "listed": 5,
                "total_count": 6,
                "fresh": 4,
                "kept": 1,
                "pages": 2,
                "region_pages": 0,
                "base_age_seconds": 605,
            },
        )

    def test_a_read_that_holds_the_count_prints_no_miss(self) -> None:
        _, stderr = self.misses_then_reads(0)
        self.assertNotIn("babysit-listing-miss", stderr)
        self.sleep.assert_not_called()

    def test_no_wait_runs_past_the_reads_timeout(self) -> None:
        # The reads' deadline is 0 + 300 s. After the first miss (clock 3 s)
        # the 15 s wait fits; after the second (clock 271 s) 29 s are left,
        # short of the 30 s wait, so a whole listing follows at once.
        clock = iter([0.0, 1.0, 2.0, 3.0, 260.0, 261.0, 271.0])
        with mock.patch.object(
            ve, "_listing_clock", side_effect=lambda: next(clock, 300.0)
        ):
            self.write_carry(self.base)
            fake = self.fake(dated(named(HEAD, "fail"), 2, 1100, LISTED_AT))
            fake.live_total = len(self.base) + 2
            reader, _ = self.judge(fake)
        self.assertEqual([c.args[0] for c in self.sleep.call_args_list], [15.0])
        self.assertEqual(reader.listing_mode, "full")

    def test_a_live_count_no_listing_can_hold_refuses(self) -> None:
        # One short is a skip another whole listing may restore; one over is
        # an entry GitHub no longer counts, which no further listing drops.
        for delta, reads in ((-1, 1), (1, ve.LISTING_READS)):
            with self.subTest(delta):
                self.write_carry(self.base)
                self.saved.unlink(missing_ok=True)
                self.failed.unlink(missing_ok=True)
                fake = self.fake()
                fake.live_total = len(self.base) + delta
                reader, evidence = self.judge(fake)
                self.assertEqual(evidence.refusal, "verify:unreadable")
                self.assertIn("live artifact count", evidence.detail or "")
                self.assertEqual(reader.listing_mode, "full")
                self.assertEqual(fake.full_listings(), reads)
                self.assertFalse(self.saved.exists())

    def skewed(self, lead: timedelta = timedelta(minutes=30)) -> FakeGitHub:
        """GitHub as on 2026-11-01 08:00-09:00Z: its count drops artifacts up
        to an hour before the `expires_at` it lists, and stamps uploads an
        hour ahead of the runner's clock. The carry still holds 600 and 610,
        which GitHub already dropped; 650 is listed by the whole listing, then
        dropped before its top-up, all three expiring `lead` past GitHub's
        Date."""
        soon = LISTED_AT + lead
        old = self.base_at - timedelta(days=2)
        dropped = [
            dated("pr-merge-gate-cursor", 3, i, old, expires=soon) for i in (600, 610)
        ]
        dropping = dated("pr-merge-gate-cursor", 3, 650, old, expires=soon)
        ahead = dated("pr-merge-gate-cursor", 3, 1100, LISTED_AT + timedelta(hours=1))
        self.write_carry([*self.base, *dropped])
        fake = self.fake(ahead, dropping)
        listed = fake.listed

        def drops_during_the_listing() -> list[dict[str, Any]]:
            items = listed()
            fake.artifacts = [a for a in fake.artifacts if a is not dropping]
            return items

        fake.listed = drops_during_the_listing  # type: ignore[method-assign]
        return fake

    def test_a_count_github_drops_early_is_settled_by_the_pages_near_expiry(
        self,
    ) -> None:
        # 600 and 610 expire within EARLY_DELETION_LEAD, so the pages around
        # them decide them: no whole listing, nothing noted for the job.
        fake = self.skewed()
        reader, evidence = self.judge(fake)
        self.assertIsNone(evidence.refusal, evidence.detail)
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual(fake.full_listings(), 0)
        self.assertFalse(self.failed.exists())
        ids = [a["id"] for a in json.loads(self.saved.read_text())["artifacts"]]
        self.assertEqual(ids, [1100, 1000, 900, 800, 700, 650])

    def test_a_count_the_pages_near_expiry_miss_takes_one_whole_listing_a_job(
        self,
    ) -> None:
        # Dropped three hours before expiry, past EARLY_DELETION_LEAD: no page
        # near expiry is read, and the over-count goes to one whole listing.
        fake = self.skewed(timedelta(hours=3))
        reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn("held more artifacts than", evidence.detail or "")
        self.assertEqual(reader.listing_mode, "full")
        # Another whole listing only adds ids, so it would hold 650 too.
        self.assertEqual(fake.full_listings(), 1)
        self.assertFalse(self.saved.exists())
        self.assertIn("held more artifacts than", self.failed.read_text())
        # The job's next Reader, in this process or another, pages nothing.
        listed = (fake.pages(), fake.full_listings())
        _, again = self.judge(fake)
        self.assertEqual(again.refusal, "verify:unreadable")
        self.assertIn("held more artifacts than", again.detail or "")
        self.assertEqual((fake.pages(), fake.full_listings()), listed)
        self.assertEqual(fake.probes(), 1)

    def against_the_clock(
        self,
        fake: FakeGitHub,
        spend: float,
        *,
        limit: str = "",
        failure: BaseException | None = None,
    ) -> ve.Evidence:
        """One Reader's judgment with no carry, its whole listing taking
        `spend` seconds of the listing clock and raising `failure` if given,
        under a caller that kills it at `limit` seconds ("" for none)."""
        now = [0.0]

        def listing(args: list[str], **kwargs: Any) -> Any:
            if args[:2] == ["api", f"repos/{REPO}/actions/artifacts?per_page=100"]:
                now[0] += spend
                if failure is not None:
                    fake.calls.append(args)
                    raise failure
            return fake(args, **kwargs)

        def page(args: list[str], **kwargs: Any) -> Any:
            return fake(args, **kwargs), {"date": DATE}

        env = {ve.DEADLINE_ENV: limit, ve.CALLER_ENV: "verify-cap.mjs"}
        with (
            mock.patch.dict("os.environ", env),
            mock.patch.object(ve, "_elapsed", return_value=0.0),
            mock.patch.object(ve, "_listing_clock", side_effect=lambda: now[0]),
            mock.patch.object(postmerge, "gh_capture", side_effect=listing),
            mock.patch.object(ve, "gh_api_with_headers", side_effect=page),
        ):
            return ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, pull())

    def test_a_top_up_out_of_the_callers_time_is_not_noted_for_the_job(
        self,
    ) -> None:
        # A 60 s caller limit leaves 45 s, under the 60 s the five artifacts'
        # listings take with no caller. The whole listing spends 50 s, so its
        # top-up has no time left: this caller refuses, a later one may list.
        fake = self.fake()
        evidence = self.against_the_clock(fake, 50.0, limit="60")
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertTrue(evidence.detail.startswith(ve.DEADLINE_UNREADABLE))
        self.assertIn("could not be checked against", evidence.detail)
        self.assertFalse(self.failed.exists())
        # The job's next Reader, with the whole cap, lists and judges.
        evidence = self.against_the_clock(fake, 0.0)
        self.assertIsNone(evidence.refusal, evidence.detail)
        self.assertEqual(fake.full_listings(), 2)

    def test_a_whole_listing_timed_out_by_the_callers_limit_is_not_noted(
        self,
    ) -> None:
        evidence = self.against_the_clock(
            self.fake(), 45.0, limit="60", failure=timed_out()
        )
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertTrue(evidence.detail.startswith(ve.DEADLINE_UNREADABLE))
        self.assertIn("timed out", evidence.detail)
        self.assertFalse(self.failed.exists())

    def test_a_top_up_lost_to_a_5xx_is_not_noted_for_the_job(self) -> None:
        # The top-up's page answers 502 through its waits: this Reader
        # refuses, and the next one, the blip over, lists and judges.
        fake = self.fake()
        fake.page_fail = "gh: Bad Gateway (HTTP 502)"
        evidence = self.against_the_clock(fake, 0.0)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn("could not be checked against", evidence.detail)
        self.assertFalse(self.failed.exists())
        fake.page_fail = None
        evidence = self.against_the_clock(fake, 0.0)
        self.assertIsNone(evidence.refusal, evidence.detail)
        self.assertEqual(fake.full_listings(), 2)

    def test_a_5xx_on_a_top_up_id_read_is_not_noted_for_the_job(self) -> None:
        # No carry, so a whole listing, which lists 650 (expiring in 30
        # minutes); GitHub then drops it early. The top-up's page 1 stops at
        # 1000, keeping 650, one over the live count; the page near expiry
        # omits it, and its read by id answers 502 through its waits: this
        # Reader refuses, transient, and the next one, the blip over, lists.
        old, soon = self.base_at - timedelta(days=2), LISTED_AT + timedelta(minutes=30)
        dropping = dated("pr-merge-gate-cursor", 3, 650, old, expires=soon)
        fake = self.fake(dropping)
        listed = fake.listed

        def drops_during_the_listing() -> list[dict[str, Any]]:
            items = listed()
            fake.artifacts = [a for a in fake.artifacts if a is not dropping]
            return items

        fake.listed = drops_during_the_listing  # type: ignore[method-assign]
        fake.fail = {"artifacts/650"}
        reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn("could not be checked against", evidence.detail or "")
        self.assertEqual(reader.listing_mode, "full")
        by_id = [c for c in fake.calls if c[-1].endswith("/artifacts/650")]
        self.assertEqual(len(by_id), 1 + len(ve.LISTING_WAITS))
        self.assertFalse(self.failed.exists())
        fake.fail = set()
        _, again = self.judge(fake)
        self.assertIsNone(again.refusal, again.detail)
        self.assertEqual(fake.full_listings(), 2)

    def test_a_top_up_read_after_a_5xx_with_no_date_is_noted(self) -> None:
        # The top-up's page 1 answers 502 once, then reads with no `Date`:
        # the failure is the missing header, not the 502, so it is noted.
        fake = self.fake()
        failed = [False]

        def page(args: list[str], **kwargs: Any) -> Any:
            if not failed[0]:
                failed[0] = True
                fake.calls.append(args)
                return subprocess.CompletedProcess(
                    args, 1, "", "gh: Bad Gateway (HTTP 502)"
                ), {}
            return fake(args, **kwargs), {}

        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve, "gh_api_with_headers", side_effect=page),
        ):
            evidence = ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, pull())
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn("could not be checked against", evidence.detail)
        self.assertEqual([c.args[0] for c in self.sleep.call_args_list], [2.0])
        self.assertTrue(self.failed.exists())

    def test_a_whole_listing_lost_to_a_5xx_is_not_noted_for_the_job(self) -> None:
        fake = FlakyListing(["gh: Bad Gateway (HTTP 502)"] * 3)
        _, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn("HTTP 502", evidence.detail)
        self.assertEqual(fake.listings(), 3)
        self.assertFalse(self.failed.exists())
        _, evidence = self.judge(fake)
        self.assertIsNone(evidence.refusal, evidence.detail)
        self.assertEqual(fake.listings(), 4)

    def test_a_whole_listing_failure_not_the_callers_is_noted(self) -> None:
        # A timeout of the whole cap's own budget (60 s for five artifacts),
        # and a top-up page 404, with or without a caller's time left.
        cases: dict[str, tuple[FakeGitHub, float, str, BaseException | None]] = {
            "cap timeout": (self.fake(), 60.0, "", timed_out()),
            "404": (self.fake(), 0.0, "", None),
            "caller 404": (self.fake(), 0.0, "60", None),
        }
        for label in ("404", "caller 404"):
            cases[label][0].page_fail = "gh: Not Found (HTTP 404)"
        for label, (fake, spend, limit, failure) in cases.items():
            with self.subTest(label):
                self.failed.unlink(missing_ok=True)
                evidence = self.against_the_clock(
                    fake, spend, limit=limit, failure=failure
                )
                self.assertEqual(evidence.refusal, "verify:unreadable")
                self.assertFalse(evidence.detail.startswith(ve.DEADLINE_UNREADABLE))
                self.assertIn(evidence.detail, self.failed.read_text())

    def test_uploads_stamped_ahead_of_the_runner_still_read_incrementally(
        self,
    ) -> None:
        # After the skew: a FAIL and another upload stamped an hour ahead of
        # the runner's clock, and a count that holds.
        self.write_carry(self.base)
        ahead = LISTED_AT + timedelta(hours=1)
        fake = self.fake(
            dated(named(HEAD, "fail"), 2, 1100, ahead),
            dated("pr-merge-gate-cursor", 3, 1050, ahead),
        )
        reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual(fake.full_listings(), 0)
        self.assertFalse(self.failed.exists())

    def test_a_carry_past_its_age_bound_lists_every_page(self) -> None:
        # The bound is three hours (LISTING_CARRY_MAX_AGE's basis).
        for age, mode in (
            (timedelta(hours=3), "incremental"),
            (timedelta(hours=3, seconds=1), "full"),
        ):
            with self.subTest(age):
                self.write_carry(self.base, LISTED_AT - age)
                self.saved.unlink(missing_ok=True)
                fake = self.fake()
                reader, _ = self.judge(fake)
                self.assertEqual(reader.listing_mode, mode)
                self.assertEqual(fake.full_listings(), int(mode == "full"))

    def test_a_carry_that_does_not_parse_lists_every_page(self) -> None:
        undated = dict(self.base[1])
        del undated["created_at"]
        for text in (
            "not json",
            json.dumps({"artifacts": self.base}),
            json.dumps({"fetchedAt": "2026-10-16T11:50:00", "artifacts": self.base}),
            json.dumps({"fetchedAt": self.base_at.isoformat(), "artifacts": {}}),
            json.dumps({"fetchedAt": self.base_at.isoformat(), "artifacts": [undated]}),
            json.dumps(
                {
                    "fetchedAt": self.base_at.isoformat(),
                    "artifacts": [self.base[0] | {"id": True}],
                }
            ),
        ):
            with self.subTest(text[:60]):
                self.carry.write_text(text)
                self.saved.unlink(missing_ok=True)
                fake = self.fake()
                reader, _ = self.judge(fake)
                self.assertEqual(reader.listing_mode, "full")
                # No incremental page: the whole listing and its own check.
                self.assertEqual((fake.pages(), fake.full_listings()), (1, 1))

    def test_no_carry_lists_every_page(self) -> None:
        fake = self.fake()
        reader, _ = self.judge(fake)
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual((fake.pages(), fake.full_listings()), (1, 1))

    def test_a_failed_page_read_lists_every_page(self) -> None:
        for error in ("gh: Bad Gateway (HTTP 502)", "gh: Not Found (HTTP 404)"):
            with self.subTest(error):
                self.write_carry(self.base)
                self.saved.unlink(missing_ok=True)
                self.failed.unlink(missing_ok=True)
                fake = self.fake(dated(named(HEAD, "fail"), 2, 1100, LISTED_AT))
                fake.page_fail = error
                reader, evidence = self.judge(fake)
                self.assertEqual(reader.listing_mode, "full")
                # The whole listing is read, but no page can check it: it
                # refuses rather than judge on it, and reads it once.
                self.assertEqual(evidence.refusal, "verify:unreadable")
                self.assertEqual(fake.full_listings(), 1)

    def test_a_page_with_no_date_or_an_odd_entry_lists_every_page(self) -> None:
        self.write_carry(self.base)
        fake = self.fake()

        def undated(args: list[str], **kwargs: Any) -> Any:
            return fake(args, **kwargs), {}

        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve, "gh_api_with_headers", side_effect=undated),
        ):
            reader = ve.Reader(REPO, "main", now=NOW)
            evidence = reader.evidence(PR, HEAD, pull())
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertEqual(fake.full_listings(), 1)
        self.saved.unlink(missing_ok=True)
        self.failed.unlink()
        odd = self.fake(dated("x", 3, 1200, LISTED_AT) | {"expires_at": "soon"})
        reader, evidence = self.judge(odd)
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual(evidence.refusal, "verify:unreadable")

    @staticmethod
    def undated(name: str, run_id: int, artifact_id: int) -> dict[str, Any]:
        """A listed artifact whose dates GitHub gives as null (its artifact
        schema marks `created_at` and `expires_at` nullable)."""
        return artifact(name, run_id) | {
            "id": artifact_id,
            "created_at": None,
            "expires_at": None,
        }

    def test_a_whole_listing_with_an_undated_artifact_lists_fully(self) -> None:
        # No carry: the whole listing's top-up stops on its dated entries, and
        # the undated FAIL is kept, so the listing holds the live count.
        fake = self.fake(self.undated(named(HEAD, "fail"), 2, 850))
        reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(reader.listing_mode, "full")
        self.assertEqual(fake.full_listings(), 1)
        ids = [a["id"] for a in json.loads(self.saved.read_text())["artifacts"]]
        self.assertEqual(ids, [1000, 900, 850, 800, 700])

    def test_an_undated_carried_entry_is_kept_below_the_new_pages(self) -> None:
        # The carry holds an undated FAIL below the pages read now: no date
        # prunes it, and the incremental listing still holds the live count.
        fail = self.undated(named(HEAD, "fail"), 2, 850)
        self.write_carry([*self.base[:2], fail, *self.base[2:]])
        fake = self.fake(fail)
        reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual(fake.full_listings(), 0)

    def test_an_undated_upload_since_is_read_and_paging_stops_on_dated_ones(
        self,
    ) -> None:
        self.write_carry(self.base)
        fake = self.fake(self.undated(named(HEAD, "fail"), 2, 1100))
        reader, evidence = self.judge(fake)
        self.assertEqual(evidence.refusal, "verify:fail")
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual((fake.pages(), fake.full_listings()), (2, 0))

    def test_a_refresh_builds_on_the_listing_it_drops(self) -> None:
        # The gate's re-list before an allow (babysit_merge.py `refresh`)
        # pages only past the run's own listing.
        self.write_carry(self.base)
        fake = self.fake()
        page = lambda args, **kwargs: (fake(args, **kwargs), {"date": DATE})  # noqa: E731
        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve, "gh_api_with_headers", side_effect=page),
        ):
            reader = ve.Reader(REPO, "main", now=NOW)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
            reader = ve.Reader(REPO, "main", now=NOW)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
            self.assertTrue(reader.saved)
            fake.artifacts.append(dated(named(HEAD, "fail"), 2, 1100, LISTED_AT))
            reader.refresh()
            self.assertEqual(reader.evidence(PR, HEAD, pull()).refusal, "verify:fail")
        self.assertEqual(reader.listing_mode, "incremental")
        self.assertEqual(fake.full_listings(), 0)


class AWholeListingMustHoldTheLiveCount(unittest.TestCase):
    """A whole listing skips the artifact at a page boundary when an earlier
    one expires while it pages (#10486: on 2026-10-27 two of three whole
    listings skipped live artifacts, FAILs among them). It is kept only when,
    deduplicated by id and checked by a top-up from the first page, it holds
    GitHub's live `total_count`; the next read restores a skip, and after
    `LISTING_READS` reads that never hold it the gate refuses."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.saved = pathlib.Path(tmp.name, "verify-listing.json")
        for patcher in (
            mock.patch.dict("os.environ", {"BABYSIT_VERIFY_LISTING": str(self.saved)}),
            # One artifact a page, so the top-up's first page holds only the
            # newest id and the FAIL sits below it.
            mock.patch.object(ve, "LISTING_PAGE_SIZE", 1),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    @staticmethod
    def fake() -> FakeGitHub:
        """A pass at the head (run 5, id 50), and an earlier head's FAIL of
        this pull request (run 2, id 20) below it."""
        return FakeGitHub(
            [artifact(named(HEAD, "pass"), 5), artifact(named(EARLIER, "fail"), 2)],
            {5: run(5), 2: run(2)},
            {named(HEAD, "pass"): record()},
        )

    def test_a_fail_the_whole_listing_skips_is_restored_by_the_next_read(self) -> None:
        fake = self.fake()
        fake.full_skips = [{20}]
        evidence = read(fake)
        # On the first listing alone the pass would allow.
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertEqual(listings(fake), 2)
        self.assertEqual(
            sorted(a["id"] for a in json.loads(self.saved.read_text())["artifacts"]),
            [20, 50],
        )

    def test_a_listing_that_never_holds_the_live_count_refuses(self) -> None:
        fake = self.fake()
        fake.full_skips = [{20}] * ve.LISTING_READS
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn("live artifact count", evidence.detail or "")
        self.assertEqual(fake.full_listings(), ve.LISTING_READS)
        self.assertFalse(self.saved.exists())

    def test_a_duplicate_at_a_page_boundary_is_counted_once(self) -> None:
        # An upload while it pages moves an artifact down a page, so the
        # whole listing returns it twice.
        fake = self.fake()
        listed = fake.listed

        def doubled() -> list[dict[str, Any]]:
            items = listed()
            return [*items[:1], *items]

        fake.listed = doubled  # type: ignore[method-assign]
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:earlier-fail")
        self.assertEqual(fake.full_listings(), 1)
        ids = [a["id"] for a in json.loads(self.saved.read_text())["artifacts"]]
        self.assertEqual(sorted(ids), [20, 50])

    def test_the_refresh_before_an_allow_holds_the_live_count_too(self) -> None:
        # babysit_merge.py calls `refresh()` before an allow: with no listing
        # to build on, its whole listing is checked the same way.
        fake = self.fake()
        del fake.artifacts[1]
        with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
            reader = ve.Reader(REPO, "main", now=NOW)
            self.assertIsNone(reader.evidence(PR, HEAD, pull()).refusal)
            self.saved.unlink()
            reader._base = None
            fake.artifacts.append(artifact(named(EARLIER, "fail"), 2))
            fake.runs[2] = run(2)
            fake.full_skips = [{20}] * ve.LISTING_READS
            reader._artifacts, reader._saved = None, True
            reader.refresh()
            self.assertEqual(
                reader.evidence(PR, HEAD, pull()).refusal, "verify:unreadable"
            )


class TheColdReadHeadroomCoversTheListingCaps(unittest.TestCase):
    """ci-status holds a cold reader unless GITHUB_TOKEN's pool has one cold
    read's worst case per queue entry (pr-require-checks.yml), which it works
    out from the live listing: its `total_count` and the FAILs it lists. The
    workflow's figure must cover the reader's listing caps at any listing
    size, so raising `INCREMENTAL_READS`, `LISTING_READS`, `LISTING_WAITS`
    `LISTING_TOP_UP_PAGES`, `NEAR_EXPIRY_PAGE_CAP` or
    `NEAR_EXPIRY_ID_READ_CAP` without it fails here. The other terms are the
    workflow comment's: 3 reads a FAIL (its run, a compare and a download),
    at most 13 pages an incremental read, the count read before the whole
    listings, one page more than the live count fills, and the step's own
    listing, which each entry the queue builds at once also reads."""

    def cold_cost(self, total: int, fails: int) -> int:
        """The workflow's own `pages=` and `cold_cost=` lines, run by bash."""
        workflow = (
            pathlib.Path(__file__).resolve().parents[6]
            / ".github/workflows/pr-require-checks.yml"
        ).read_text(encoding="utf-8")
        lines = [
            re.findall(rf"^ *({name}=\$\(\(.*\)\))$", workflow, re.MULTILINE)
            for name in ("listing_pages", "cold_cost")
        ]
        self.assertEqual([len(found) for found in lines], [1, 1], lines)
        script = f"total={total} fails={fails}\n{lines[0][0]}\n{lines[1][0]}\n"
        out = subprocess.run(
            ["bash", "-c", script + 'echo "$cold_cost"'],
            capture_output=True,
            text=True,
            check=True,
        )
        return int(out.stdout)

    def test_the_workflow_cost_is_the_capped_worst_case_at_any_size(self) -> None:
        attempts = 1 + len(ve.LISTING_WAITS)
        for total, fails in ((7_522, 264), (10_450, 300), (150, 10), (0, 0)):
            with self.subTest(total=total, fails=fails):
                pages = ve.listing_pages(total) + 1
                worst = (
                    pages
                    + 3 * fails
                    + ve.INCREMENTAL_READS * 13
                    + 1
                    + ve.LISTING_READS * (attempts * pages + ve.LISTING_TOP_UP_PAGES)
                    + ve.NEAR_EXPIRY_PAGE_CAP
                    + ve.NEAR_EXPIRY_ID_READ_CAP
                )
                self.assertEqual(self.cold_cost(total, fails), worst)

    def test_the_cost_of_two_listings_differs_by_hand(self) -> None:
        # 10,450 artifacts (106 pages) and 300 FAILs against 7,522 (77) and
        # 264: 2,079 against 1,681, worked by hand in ci-lanes-pr-hold.test.sh.
        self.assertEqual(self.cold_cost(10_450, 300), 2_079)
        self.assertEqual(self.cold_cost(7_522, 264), 1_681)


# --- The --authority pr-merge path ------------------------------------------------


def evidence(refusal: str | None) -> ve.Evidence:
    return ve.Evidence(refusal=refusal, head=unattended.HEAD, verdicts=(), ignored=0)


# A manifest the floor switch's manifest review holds; the floor itself holds
# no path.
MANIFEST = "plugins/foo/.claude-plugin/plugin.json"


def changed(path: str, additions: int = 1) -> unattended.ChangedFile:
    """A modified regular file in the diff."""
    return unattended.ChangedFile(
        path, None, "modified", additions, 1, True, "100644", "100644"
    )


class LaneRequiresAVerdict(unattended.Unattended):
    """`merge.require-verifier-verdict: true` in the pr-merge lane. The lane
    harness is borrowed, not inherited, so its tests do not run twice."""

    lane = unattended.LaneMode.lane

    def setUp(self) -> None:
        super().setUp()
        # The lane's own setup (LaneMode): its config, no local re-reads.
        self.config = policy.PipelineConfig(
            unattended.BASE, "C2", "pr-merge", unattended.IDENTITY, 200,
            (".github/**",), "c2-mechanical", require_verifier_verdict=True,
        )  # fmt: skip
        self.opt_in_recheck = "not-lane-authored-or-opted-in"
        self.promotion = policy.Promotion(None, "resolver-failed")
        self.kill = []
        self.verdicts: dict[int, ve.Evidence] = {}
        # Each judgment's pull request and whether it was provisional.
        self.provisional: list[tuple[int, bool]] = []
        self.read = mock.Mock(
            side_effect=lambda number, head: self.verdicts.get(number, evidence(None))
        )
        patcher = mock.patch.object(ve.Reader, "evidence", side_effect=self._evidence)
        patcher.start()
        self.addCleanup(patcher.stop)
        # The tracker binding's human-gated role label (`babysit_tracker_binding`).
        self.role_label = mock.Mock(return_value="needs-human")
        patcher = mock.patch.object(postmerge, "_role_label", self.role_label)
        patcher.start()
        self.addCleanup(patcher.stop)

        # Writes whose argv holds one of these fail (HTTP 502).
        self.failing: set[str] = set()

    def _evidence(
        self, number: int, head: str, pr: Any = None, *, provisional: bool = False
    ) -> ve.Evidence:
        self.provisional.append((number, provisional))
        return self.read(number, head)

    def _capture(self, args: list[str]) -> Any:
        if any(f in a for f in self.failing for a in args):
            self.log.append("failed:" + " ".join(args))
            return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
        return super()._capture(args)

    def escalation_comment(self) -> dict[str, Any]:
        return {
            "id": 90,
            "user": {"login": unattended.IDENTITY, "type": "Bot"},
            "created_at": "2026-10-12T10:00:00Z",
            "body": merge.verify_escalation_body(
                "verify:untrusted-spec", unattended.HEAD
            ),
        }

    def test_a_failed_comment_adds_no_label(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:untrusted-spec")
        self.failing = {merge.VERIFY_ESCALATION_MARKER}
        _, out = self.lane()
        self.assertFalse(
            any("/labels" in a for w in self.escalation_writes() for a in w)
        )
        self.assertNotIn("escalation", out["unattended"]["writes"])
        self.assertTrue(
            any(
                e.startswith("escalation:")
                for e in out["unattended"]["writes"]["errors"]
            )
        )

    def test_a_failed_label_is_added_on_the_next_run_without_a_second_comment(
        self,
    ) -> None:
        self.verdicts[unattended.PR] = evidence("verify:untrusted-spec")
        self.failing = {"/labels"}
        _, out = self.lane()
        self.assertTrue(
            any(
                e.startswith("escalation:")
                for e in out["unattended"]["writes"]["errors"]
            )
        )
        # The next run reads the comment the first one posted.
        self.failing = set()
        self.comments = [self.escalation_comment()]
        _, out = self.lane()
        (label,) = self.escalation_writes()
        self.assertIn("labels[]=needs-human", label)
        self.assertEqual(
            out["unattended"]["writes"]["escalation"],
            {"label": "added", "comment": "unchanged"},
        )

    def test_a_label_differing_only_in_case_is_not_added_again(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:untrusted-spec")
        self.pr_labels = [{"name": "Needs-Human"}]
        self.comments = [self.escalation_comment()]
        _, out = self.lane()
        self.assertEqual(self.escalation_writes(), [])
        self.assertEqual(out["unattended"]["writes"]["escalation"]["label"], "present")

    def escalation_writes(self) -> list[list[str]]:
        return [
            c.args[0]
            for c in self.capture.call_args_list
            if any(
                "/labels" in a or merge.VERIFY_ESCALATION_MARKER in a for a in c.args[0]
            )
        ]

    def test_a_needs_human_refusal_labels_the_pr_and_comments_once(self) -> None:
        for refusal in ve.NEEDS_HUMAN:
            with self.subTest(refusal):
                self.verdicts[unattended.PR] = evidence(refusal)
                code, out = self.lane()
                self.assert_no_merge(code)
                # The comment explains the label, so it is written first.
                comment, label = self.escalation_writes()
                self.assertEqual(
                    label[-4:],
                    ["POST", f"repos/owner/repo/issues/{unattended.PR}/labels"]
                    + ["-f", "labels[]=needs-human"],
                )
                self.assertIn("POST", comment)
                body = comment[-1].removeprefix("body=")
                self.assertTrue(body.startswith(merge.VERIFY_ESCALATION_MARKER + "\n"))
                self.assertIn(f"`{refusal}`", body)
                self.assertIn(unattended.HEAD, body)
                self.assertEqual(
                    out["unattended"]["writes"]["escalation"],
                    {"label": "added", "comment": "created"},
                )

    def test_the_gate_reads_verdicts_under_the_configured_cap(self) -> None:
        self.config = dataclasses.replace(self.config, max_verify_fails=5)
        with mock.patch.object(ve, "Reader", wraps=ve.Reader) as built:
            self.lane()
        self.assertTrue(built.call_args_list)
        for call in built.call_args_list:
            self.assertEqual(call.kwargs.get("max_fails"), 5)

    def test_the_label_is_the_trackers_human_gated_role(self) -> None:
        self.role_label.return_value = "status: needs-decision"
        self.verdicts[unattended.PR] = evidence("verify:untrusted-spec")
        self.lane()
        self.assertIn("labels[]=status: needs-decision", self.escalation_writes()[-1])

    def test_another_label_does_not_stand_in_for_the_role_label(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:untrusted-spec")
        self.pr_labels = [{"name": "enhancement"}]
        _, out = self.lane()
        self.assertEqual(out["unattended"]["writes"]["escalation"]["label"], "added")

    def test_a_rerun_writes_no_second_label_or_comment(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:untrusted-spec")
        self.pr_labels = [{"name": "needs-human"}]
        self.comments = [
            {
                "id": 90,
                "user": {"login": unattended.IDENTITY, "type": "Bot"},
                "created_at": "2026-10-12T10:00:00Z",
                "body": merge.verify_escalation_body(
                    "verify:untrusted-spec", unattended.HEAD
                ),
            }
        ]
        _, out = self.lane()
        self.assertEqual(self.escalation_writes(), [])
        self.assertEqual(
            out["unattended"]["writes"]["escalation"],
            {"label": "present", "comment": "unchanged"},
        )
        # The escalation's own label is a merge hold too; the reason still
        # names the verifier refusal.
        self.assertEqual(out["unattended"]["reason"], "verify:untrusted-spec")

    def test_a_fail_at_the_head_writes_no_escalation(self) -> None:
        # A fix round answers it (pr-feedback-dispatch.yml); a label would
        # hold that round as awaiting-human.
        self.verdicts[unattended.PR] = evidence("verify:fail")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:fail")
        self.assertEqual(self.escalation_writes(), [])
        self.assertNotIn("escalation", out["unattended"]["writes"])

    def test_an_old_pull_request_waits_for_a_fresh_pass_and_is_not_closed(self) -> None:
        # Owner decision 2026-11-01: the lost-run reconciler
        # re-runs the verifier at the head, whose fresh pass clears it.
        self.verdicts[unattended.PR] = evidence("verify:too-old")
        with mock.patch.object(ve, "capped_close") as close:
            code, out = self.lane()
        self.assert_no_merge(code)
        close.assert_not_called()
        self.assertEqual(out["unattended"]["reason"], "verify:too-old")
        self.assertIs(out["unattended"]["verify"]["needsHuman"], False)
        self.assertEqual(self.escalation_writes(), [])

    def test_the_cap_closes_for_a_fresh_attempt(self) -> None:
        # Owner rule 2026-10-27: it is no intent, design or security
        # question, so it gets no person's label. Owner decision
        # 2026-10-29: the gate closes the pull request for a fresh attempt at
        # its issue (capped_close, which judges it again and checks the
        # author), under merge.verify-cap-attempts.
        self.config = dataclasses.replace(self.config, verify_cap_attempts=2)
        for refusal in ("verify:repeated-fail",):
            with self.subTest(refusal):
                self.verdicts[unattended.PR] = evidence(refusal)
                with mock.patch.object(
                    ve,
                    "capped_close",
                    return_value={"closed": True, "restarted": [7], "parked": []},
                ) as close:
                    code, out = self.lane()
                self.assert_no_merge(code)
                self.assertEqual(out["unattended"]["reason"], refusal)
                self.assertIs(out["unattended"]["verify"]["needsHuman"], False)
                self.assertEqual(self.escalation_writes(), [])
                self.assertNotIn("escalation", out["unattended"]["writes"])
                self.assertEqual(
                    out["unattended"]["writes"]["cappedClose"]["restarted"], [7]
                )
                (reader, number, head), kwargs = close.call_args
                self.assertEqual((number, head), (unattended.PR, unattended.HEAD))
                self.assertEqual(reader.agent_identity, unattended.IDENTITY)
                self.assertEqual(
                    kwargs,
                    {
                        "attempts": 2,
                        "holds": ("do-not-merge", "needs-human"),
                        "issue_holds": ("needs-human",),
                    },
                )

    def test_a_hold_the_gate_reads_on_the_pull_request_closes_nothing(self) -> None:
        # A body hold, a member's veto or a hold label (`entry_hold`) keeps
        # it open, as enable-auto-merge.mjs decide() does on the native path.
        for hold in ("body-hold", "human-blocking-comment:kyle-sexton", "unreadable"):
            with self.subTest(hold):
                self.verdicts[unattended.PR] = evidence("verify:repeated-fail")
                self.holds[unattended.PR] = hold
                seen: list[dict[str, Any]] = []
                self.hold_hook = lambda kw: seen.append(kw)  # type: ignore[assignment]
                with mock.patch.object(ve, "capped_close") as close:
                    _, out = self.lane()
                close.assert_not_called()
                # Read as a pull request never enqueued.
                never_queued = [kw for kw in seen if kw.get("queued") is False]
                self.assertTrue(never_queued)
                for kw in never_queued:
                    self.assertEqual(kw.get("authority"), "pr-merge")
                self.assertEqual(
                    out["unattended"]["writes"]["cappedClose"],
                    {"closed": False, "reason": f"held: {hold}"},
                )

    def test_an_unreadable_human_gated_label_closes_nothing(self) -> None:
        # Its default could miss the label the tracker maps, and so the hold.
        self.verdicts[unattended.PR] = evidence("verify:repeated-fail")
        self.role_label.side_effect = postmerge.PostMergeReadError("tracker gone")
        with mock.patch.object(ve, "capped_close") as close:
            _, out = self.lane()
        close.assert_not_called()
        self.assertNotIn("cappedClose", out["unattended"]["writes"])
        self.assertTrue(
            any("capped close" in e for e in out["unattended"]["writes"]["errors"])
        )

    def test_a_refusal_that_can_clear_closes_nothing(self) -> None:
        for refusal in ("verify:fail", "verify:unreadable", "verify:spec-changed"):
            with self.subTest(refusal):
                self.verdicts[unattended.PR] = evidence(refusal)
                with mock.patch.object(ve, "capped_close") as close:
                    self.lane()
                close.assert_not_called()

    def test_report_only_reports_a_needs_human_refusal_and_writes_nothing(self) -> None:
        self.config = dataclasses.replace(self.config, report_only=True)
        self.verdicts[unattended.PR] = evidence("verify:untrusted-spec")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertIs(out["unattended"]["verify"]["needsHuman"], True)
        self.capture.assert_not_called()
        self.assertNotIn("writes", out["unattended"])

    def test_a_refusal_that_needs_no_human_is_not_escalated(self) -> None:
        for refusal in ("verify:missing", "verify:unreadable"):
            with self.subTest(refusal):
                self.verdicts[unattended.PR] = evidence(refusal)
                _, out = self.lane()
                self.assertEqual(self.escalation_writes(), [])
                self.assertNotIn("escalation", out["unattended"]["writes"])

    def test_a_pass_at_the_head_enqueues(self) -> None:
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.read.assert_called_once_with(unattended.PR, unattended.HEAD)
        self.assertIn("verify", out["unattended"])

    def saved_listing(self) -> mock.Mock:
        """The reader judged on the run's saved listing; returns `refresh`."""
        patcher = mock.patch.object(ve.Reader, "saved", new=True)
        patcher.start()
        self.addCleanup(patcher.stop)
        patcher = mock.patch.object(ve.Reader, "refresh")
        refresh = patcher.start()
        self.addCleanup(patcher.stop)
        return refresh

    def test_an_allow_on_the_saved_listing_is_judged_again_on_its_own(self) -> None:
        # A FAIL uploaded after the run saved its listing still refuses.
        refresh = self.saved_listing()
        self.read.side_effect = [evidence(None), evidence("verify:fail")]
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:fail")
        refresh.assert_called_once_with()
        self.assertEqual(self.read.call_count, 2)

    def test_a_candidate_refused_otherwise_does_not_list_again(self) -> None:
        # Already refused, it is not enqueued: an allow on the saved listing
        # decides nothing, so it pages nothing.
        refresh = self.saved_listing()
        self.lanes = unattended.UNBOUND
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertTrue(out["unattended"]["reason"].startswith("risk:"))
        refresh.assert_not_called()
        self.read.assert_called_once_with(unattended.PR, unattended.HEAD)

    def test_only_the_candidate_is_judged_provisional(self) -> None:
        # Its allow is judged again on its own listing before the gate allows
        # it; a queued entry kept on the judgment has no such second read.
        other = unattended.PR + 1
        self.queued = [other]
        self.lane()
        self.assertEqual(self.provisional, [(unattended.PR, True), (other, False)])

    def test_a_refusal_on_the_saved_listing_stands_without_a_listing(self) -> None:
        refresh = self.saved_listing()
        self.verdicts[unattended.PR] = evidence("verify:missing")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:missing")
        refresh.assert_not_called()
        self.read.assert_called_once_with(unattended.PR, unattended.HEAD)

    def test_a_fail_refuses_and_dequeues_its_own_entry(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:fail")
        self.queued = [unattended.PR]
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:fail")
        self.assertIn(f"dequeue:[{unattended.PR}]", self.log)
        # Its own entry is decided once, not read again in the queue loop.
        self.assertEqual(self.read.call_count, 1)

    def test_a_missing_verdict_refuses(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:missing")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:missing")

    def test_an_earlier_fail_refuses_without_a_human(self) -> None:
        self.verdicts[unattended.PR] = evidence("verify:earlier-fail")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:earlier-fail")
        self.assertIs(out["unattended"]["verify"]["needsHuman"], False)
        self.assertEqual(self.escalation_writes(), [])

    def test_a_queued_entry_without_a_pass_at_its_head_is_dequeued(self) -> None:
        other = unattended.PR + 1
        self.queued = [unattended.PR, other]
        self.verdicts[other] = evidence("verify:missing")
        _, out = self.lane()
        self.assertIn(f"dequeue:[{other}]", self.log)
        self.assertEqual(
            out["unattended"]["writes"]["holds"], {str(other): "verify:missing"}
        )
        # The queued entry is judged at the head its pull request reads now.
        self.read.assert_any_call(other, self.scored_head)

    def test_a_crash_on_one_queued_entry_refuses_it_and_the_sweep_goes_on(self) -> None:
        crash, after = unattended.PR + 1, unattended.PR + 2
        self.queued = [crash, after]
        self.verdicts[after] = evidence("verify:missing")

        def read(number: int, head: str) -> ve.Evidence:
            if number == crash:
                raise KeyError("unexpected")
            return self.verdicts.get(number, evidence(None))

        self.read.side_effect = read
        _, out = self.lane()
        self.assertEqual(
            out["unattended"]["writes"]["holds"],
            {str(crash): "verify:unreadable", str(after): "verify:missing"},
        )
        self.assertIn(f"dequeue:[{crash}, {after}]", self.log)

    def test_an_ineligible_candidate_still_dequeues_an_unverified_entry(self) -> None:
        other = unattended.PR + 1
        self.lane_eligible = policy.Eligibility(False, "linked-issues:0")
        self.queued = [other]
        self.verdicts[other] = evidence("verify:missing")
        _, out = self.lane()
        self.assertEqual(
            out["unattended"]["writes"]["holds"], {str(other): "verify:missing"}
        )
        self.assertIn(f"dequeue:[{other}]", self.log)
        self.read.assert_called_once_with(other, self.scored_head)

    def test_a_verifier_refusal_is_judged_before_the_diff(self) -> None:
        # The refusal stands whatever the diff scores, so neither the lane
        # evidence nor the score is read, and the reason is the verifier's.
        self.verdicts[unattended.PR] = evidence("verify:fail")
        self.lanes = unattended.UNBOUND
        self.queued = [unattended.PR]
        self._lane_evidence = mock.Mock(return_value=(self.lanes, self.comments))
        with mock.patch.object(merge.babysit_risk, "score") as score:
            code, out = self.lane()
        self.assert_no_merge(code)
        self._lane_evidence.assert_not_called()
        score.assert_not_called()
        self.assertEqual(out["unattended"]["reason"], "verify:fail")
        self.assertNotIn("risk", out["unattended"])
        self.assertIn(f"dequeue:[{unattended.PR}]", self.log)

    def test_a_risk_refusal_is_the_reason_when_the_verifier_passes(self) -> None:
        self.lanes = unattended.UNBOUND
        _, out = self.lane()
        self.assertTrue(out["unattended"]["reason"].startswith("risk:"))

    def test_dependabot_needs_no_verdict(self) -> None:
        self.lane_eligible = policy.Eligibility(False, "dependency-manager")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "ineligible:dependency-manager")
        self.read.assert_not_called()

    def test_a_real_dependabot_pull_request_is_refused_before_the_reader(self) -> None:
        # The real lane eligibility over a dependabot[bot]-authored pull
        # request (babysit_merge_policy._foreign_refusal).
        self.lane_eligible = None
        node = {
            "number": unattended.PR,
            "isCrossRepository": False,
            "headRepositoryOwner": {"login": "owner"},
            "author": {"__typename": "Bot", "login": "dependabot"},
        }
        graphql = mock.Mock(return_value={"repository": {"pullRequest": node}})
        with mock.patch.object(policy, "_graphql", graphql):
            code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "ineligible:dependency-manager")
        self.assertIs(graphql.call_args.args[0], policy.ELIGIBILITY)
        self.read.assert_not_called()

    def test_the_lane_without_the_key_refuses(self) -> None:
        # Design 3: the verdict is the lane's only merge criterion.
        self.config = dataclasses.replace(self.config, require_verifier_verdict=False)
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verifier-verdict-not-required")
        self.read.assert_not_called()

    def test_a_lane_pr_touching_the_merge_gate_merges_on_a_pass(self) -> None:
        # Owner decision Q624: no denied path, no HIGH floor, no size caps and
        # no C2 contradictions in the lane by default; the verdict still gates.
        self.config = dataclasses.replace(
            self.config, denied_paths=(), max_changed_lines=None
        )
        self.unlabeled_lane_pr(real_denied_paths=True)
        gate = "plugins/source-control/scripts/source-control-babysit-merge"
        paths = (gate, ".github/workflows/x.yml", *(f"lib/f{i}.sh" for i in range(8)))
        # The workflow's patch adds no cost line, so the cost hold passes it.
        self.files = (
            tuple(
                dataclasses.replace(changed(path, 300), patch="@@ -1 +1 @@\n-a\n+b")
                for path in paths
            ),
            True,
        )
        # The cost hold reads the workflow's text: it starts no model leg.
        reader = mock.patch.object(policy, "_file_at", return_value="jobs: {}\n")
        reader.start()
        self.addCleanup(reader.stop)
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(out["unattended"]["risk"]["score"], "LOW")
        self.assertEqual(self.log, ["pin", f"enqueue:{unattended.HEAD}:merge_queue"])
        # The verdict still decides: a missing one refuses the same pull request.
        self.verdicts[unattended.PR] = evidence("verify:missing")
        self.log = []
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verify:missing")

    def test_the_lane_switches_turned_on_restore_the_refusals(self) -> None:
        self.config = dataclasses.replace(
            self.config, high_path_floor=True, max_changed_files=8,
        )  # fmt: skip
        self.files = ((changed(MANIFEST),), True)
        _, out = self.lane()
        self.assertEqual(out["unattended"]["reason"], "risk:HIGH")

    def test_the_lane_scores_a_manifest_from_the_config_high(self) -> None:
        self.config = dataclasses.replace(self.config, high_path_floor=True)
        self.files = ((changed(MANIFEST),), True)
        _, out = self.lane()
        self.assertEqual(out["unattended"]["reason"], "risk:HIGH")
        codes = [r["code"] for r in out["unattended"]["risk"]["reasons"]]
        self.assertEqual(codes, ["manifest-review-required"])

    def unlabeled_lane_pr(self, real_denied_paths: bool = False) -> None:
        """The real lane eligibility over a lanes-App pull request whose one
        closing issue carries no `work-class:` label."""
        self.lane_eligible = None
        issue = {
            "number": 41,
            "repository": {"nameWithOwner": "owner/repo"},
            "labels": {"totalCount": 0, "nodes": []},
        }
        node = {
            "number": unattended.PR,
            "isCrossRepository": False,
            "headRepositoryOwner": {"login": "owner"},
            "author": {"__typename": "Bot", "login": "agent-lanes"},
            "closingIssuesReferences": {"totalCount": 1, "nodes": [issue]},
        }
        reads = [
            ("_graphql", {"repository": {"pullRequest": node}}),
            ("_base_refusal", None),
            # The trust hold's label history: no removal.
            ("_timeline", []),
        ]
        if not real_denied_paths:
            reads.append(("_denied_path_refusal", None))
        for name, answer in reads:
            patcher = mock.patch.object(policy, name, return_value=answer)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_an_unlabeled_issue_merges_on_a_pass_as_c2(self) -> None:
        self.unlabeled_lane_pr()
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(out["unattended"]["eligibility"]["workClass"], "C2")
        self.assertEqual(out["unattended"]["risk"]["score"], "LOW")

    def test_a_missing_verdict_refuses_even_at_low_risk(self) -> None:
        self.unlabeled_lane_pr()
        self.verdicts[unattended.PR] = evidence("verify:missing")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertNotIn("risk", out["unattended"])
        self.assertEqual(out["unattended"]["reason"], "verify:missing")


class LocalBabysitReadsNoVerdict(unattended.Unattended):
    def test_the_key_does_not_reach_the_local_path(self) -> None:
        self.config = dataclasses.replace(self.config, require_verifier_verdict=True)
        with mock.patch.object(ve.Reader, "evidence") as read:
            code, out = self.run_main()
        self.assertEqual(code, 0, out["blockers"])
        read.assert_not_called()

    def test_the_lane_switches_do_not_reach_the_local_path(self) -> None:
        # Q624 turns the floor and caps off for the pr-merge lane only.
        self.config = dataclasses.replace(
            self.config, high_path_floor=False, max_changed_files=None,
        )  # fmt: skip
        self.files = ((changed(MANIFEST),), True)
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "risk:HIGH")

    def test_the_local_floor_holds_whatever_the_switch_says(self) -> None:
        self.files = ((changed(MANIFEST),), True)
        for on in (False, True):
            with self.subTest(high_path_floor=on):
                self.config = dataclasses.replace(self.config, high_path_floor=on)
                _, out = self.run_main()
                self.assertEqual(out["unattended"]["risk"]["score"], "HIGH")


class TheConfigKey(unittest.TestCase):
    def config(self, value: str | None) -> policy.PipelineConfig:
        line = "" if value is None else f"  require-verifier-verdict: {value}\n"
        text = (
            "version: 1\nmerge:\n  rung: C2\n  authority: pr-merge\n"
            "  agent-identity: agent-lanes[bot]\n" + line
        )

        def file_at(owner: str, name: str, path: str, sha: str) -> str | None:
            return text if path == policy.CONFIG_PATH else None

        with mock.patch.object(policy, "_file_at", side_effect=file_at):
            return policy.read_config_at(REPO, "e" * 40)

    def test_absent_is_off_and_true_is_on(self) -> None:
        self.assertFalse(self.config(None).require_verifier_verdict)
        self.assertFalse(self.config("false").require_verifier_verdict)
        self.assertTrue(self.config("true").require_verifier_verdict)

    def test_any_other_value_requires_a_verdict(self) -> None:
        config = self.config("maybe")
        self.assertTrue(config.require_verifier_verdict)
        self.assertTrue(any("require-verifier-verdict" in n for n in config.notes))


class TheSweepKeepsTheListingBound(unattended.Unattended):
    """A queued entry another candidate kept is skipped only while the
    listing its verdict was judged on is within the bound."""

    def setUp(self) -> None:
        super().setUp()
        self.config = policy.PipelineConfig(
            unattended.BASE, "C2", "pr-merge", unattended.IDENTITY, 200,
            (".github/**",), "c2-mechanical", require_verifier_verdict=True,
        )  # fmt: skip
        self.opt_in_recheck = "not-lane-authored-or-opted-in"
        self.promotion = policy.Promotion(None, "resolver-failed")
        self.kill = []
        self.flight = policy.InFlight(False, "identity-entry-queued:#5")
        self.queued = [unattended.PR, 5]
        self.clock = datetime(2026, 10, 18, 12, 0, tzinfo=UTC)
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = str(pathlib.Path(tmp.name, "run.json"))
        self.reads: list[int] = []
        listed = self.clock - timedelta(seconds=90)
        for patcher in (
            mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": path}),
            mock.patch.object(ve.run_cache, "now", side_effect=lambda: self.clock),
            # The verdict is judged on a listing begun 90 s before the run.
            mock.patch.object(
                ve.Reader,
                "evidence",
                side_effect=lambda n, head, pr=None, **_: (
                    self.reads.append(n) or ve.run_cache.note(listed) or evidence(None)
                ),
            ),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_the_skip_ends_when_the_judged_listing_passes_the_bound(self) -> None:
        for seconds in (0, 29, 31):
            self.clock = datetime(2026, 10, 18, 12, 0, seconds, tzinfo=UTC)
            code, _ = unattended.LaneMode.lane(self)
            self.assert_no_merge(code)
        # Judged at 12:00:00 on a listing from 11:58:30: skipped at :29, not :31.
        self.assertEqual(self.reads.count(5), 2)


# --- Verdict downloads ---------------------------------------------------------

TIE = "9" * 40  # a head of PR 97, whose verdict records PR 41's head ref


def download_requests(fake: FakeGitHub) -> int:
    """REST requests spent on verdict downloads: one per archive fetched by
    id, two per `gh run download`, which lists the run's artifacts and then
    fetches the archive (gh's pkg/cmd/run/download)."""
    return sum(
        2 if c[:2] == ["run", "download"] else 1
        for c in fake.calls
        if c[:2] == ["run", "download"] or c[1].endswith("/zip")
    )


class EachVerdictIsOneRequest(unittest.TestCase):
    """A verdict.json is fetched by the listed artifact's id, one request
    (`GET .../actions/artifacts/{id}/zip` answers a 302 to the archive),
    where `gh run download` spends two. The module docstring's rules decide
    a pull request with an earlier FAIL, an untied FAIL of another pull
    request, a FAIL tied by its recorded head ref, and a pass at the head
    the same way whichever download reads them."""

    @staticmethod
    def heads(tie_created: str = OLDER_START, ids: bool = True) -> FakeGitHub:
        """A pass at the head (run 1), a FAIL at an earlier head (run 2), PR
        98's FAIL recording another ref (run 3) and PR 97's recording
        `feat/x` (run 4, created at `tie_created`)."""
        fake = passing(
            artifact(named(EARLIER, "fail"), 2),
            artifact(named(UNRELATED, "fail", 98), 3),
            artifact(named(TIE, "fail", 97), 4),
            runs={
                2: judged(2, OLDER_START),
                3: judged(3, OLDER_START),
                4: judged(4, tie_created),
            },
        )
        fake.records[named(UNRELATED, "fail", 98)] = record(
            98, UNRELATED, verdict="fail", head_ref="feat/other"
        )
        fake.records[named(TIE, "fail", 97)] = record(
            97, TIE, verdict="fail", head_ref="feat/x"
        )
        fake.diffs[TIE] = change("tie")
        if not ids:
            for item in fake.artifacts:
                del item["id"]
        return fake

    def test_a_later_pass_of_another_change_clears_both_fails(self) -> None:
        fake = self.heads()
        evidence = read(fake)
        self.assertIsNone(evidence.refusal)
        self.assertEqual(evidence.report()["earlierFails"], sorted([EARLIER, TIE]))
        # The pass and the two untied FAILs' records.
        self.assertEqual(download_requests(fake), 3)

    def test_a_tied_fail_after_the_pass_holds(self) -> None:
        fake = self.heads("2026-10-15T00:00:01Z")
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")
        # Only the untied FAILs' records: the pass decides nothing.
        self.assertEqual(download_requests(fake), 2)

    def test_a_third_failed_head_reaches_the_cap(self) -> None:
        fake = self.heads()
        fake.artifacts.append(artifact(named(IN_PR, "fail", 96), 5))
        fake.runs[5] = run(5)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:repeated-fail")
        self.assertFalse(evidence.needs_human)

    def test_a_listing_with_an_artifact_of_no_id_refuses(self) -> None:
        # An entry with no id cannot be counted against the live total, so
        # the listing is never whole and no pass allows on it.
        fake = self.heads(ids=False)
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertIn("no id", evidence.detail or "")
        self.assertEqual(download_requests(fake), 0)

    def test_an_unreadable_untied_record_refuses(self) -> None:
        for ids in (True, False):
            with self.subTest(ids=ids):
                fake = self.heads(ids=ids)
                del fake.records[named(UNRELATED, "fail", 98)]
                self.assertEqual(read(fake).refusal, "verify:unreadable")

    def test_only_a_verdict_json_from_a_good_exit_is_read(self) -> None:
        fake = passing()
        allowing = record()
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("other.json", json.dumps(allowing))
        archives = {
            "another member": (0, buffer.getvalue()),
            "not a zip": (0, b"not a zip"),
            "a failed exit": (1, zipped(allowing)),
        }
        for label, (code, body) in archives.items():

            def answer(args: list[str], **kwargs: Any) -> Any:
                if args[1].endswith("/zip"):
                    return subprocess.CompletedProcess(args, code, body, "")
                return fake(args, **kwargs)

            with (
                self.subTest(label),
                mock.patch.object(postmerge, "gh_capture", side_effect=answer),
            ):
                evidence = ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, pull())
                self.assertEqual(evidence.refusal, "verify:unreadable")
        # The same verdict as verdict.json allows.
        self.assertIsNone(read(fake).refusal)


class TheByIdFetchDecidesAsGhRunDownloadDid(unittest.TestCase):
    """A pin, not a correctness test: each expected report was recorded from
    the reader at 6c4b552396, which fetched every verdict with `gh run
    download`, run on these same fixtures. The by-id fetch must give the same
    report in each of the six cases and spend half the download requests.
    Two fields were changed since by design, not by the fetch: `needsHuman`
    is false for the repeated-FAIL cap (owner rule 2026-10-27), and the
    report no longer carries `headFail`. Break `_record` on purpose and these
    fail."""

    @staticmethod
    def report(
        refusal: Any, at_head: list[str], earlier: list[str], **extra: Any
    ) -> dict[str, Any]:
        return {
            "refusal": refusal,
            "needsHuman": False,
            "head": HEAD,
            "atHead": at_head,
            "earlierFails": sorted(earlier),
            "ignored": 0,
            "detail": None,
            "supersededAtHead": False,
            **extra,
        }

    def cases(self) -> dict[str, tuple[FakeGitHub, dict[str, Any], int, int]]:
        """Each case: fixture, the recorded report, and the download requests
        before (`gh run download`, two each) and after (one each)."""
        heads = EachVerdictIsOneRequest.heads
        third = heads()
        third.artifacts.append(artifact(named(IN_PR, "fail", 96), 5))
        third.runs[5] = run(5)
        unreadable = heads()
        del unreadable.records[named(UNRELATED, "fail", 98)]
        no_pass = heads()
        del no_pass.artifacts[0]
        at_head = heads()
        at_head.artifacts.append(artifact(named(HEAD, "fail"), 6))
        at_head.runs[6] = run(6)
        both = [EARLIER, TIE]

        def capped(*shas: str) -> str:
            return f"fails at 3 heads ({', '.join(sorted(shas))}), the cap is 3"

        return {
            "later pass": (heads(), self.report(None, ["pass"], both), 6, 3),
            "tie after pass": (
                heads("2026-10-15T00:00:01Z"),
                self.report("verify:earlier-fail", ["pass"], both),
                4,
                2,
            ),
            "third failed head": (
                third,
                self.report(
                    "verify:repeated-fail",
                    ["pass"],
                    [*both, IN_PR],
                    detail=capped(EARLIER, TIE, IN_PR),
                ),
                4,
                2,
            ),
            "unreadable untied record": (
                unreadable,
                self.report(
                    "verify:unreadable",
                    ["pass"],
                    both,
                    detail=f"record of {named(UNRELATED, 'fail', 98)}",
                ),
                4,
                2,
            ),
            "no pass": (no_pass, self.report("verify:earlier-fail", [], both), 4, 2),
            "fail at head": (
                at_head,
                self.report(
                    "verify:repeated-fail",
                    ["fail", "pass"],
                    both,
                    detail=capped(EARLIER, TIE, HEAD),
                ),
                4,
                2,
            ),
        }

    def test_each_case_reports_as_before_on_half_the_requests(self) -> None:
        for label, (fake, recorded, before, after) in self.cases().items():
            with self.subTest(label):
                self.assertEqual(read(fake).report(), recorded)
                self.assertEqual(download_requests(fake), after)
                self.assertEqual(after * 2, before)


class ACorruptArchiveIsAnUnreadableRecord(unittest.TestCase):
    """A deflate stream that does not inflate raises zlib.error, not
    BadZipFile; it must refuse like any unreadable record, and be shared."""

    @staticmethod
    def corrupt(record_: dict[str, Any]) -> bytes:
        good = zipped(record_)
        header = 30 + len("verdict.json")
        return good[:header] + b"\xff" * 8 + good[header + 8 :]

    def test_it_refuses_and_is_not_downloaded_again_in_the_run(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        name = named(UNRELATED, "fail", 98)
        fake = passing(artifact(name, 3), runs={3: run(3)})
        fake.records[name] = record(
            98, UNRELATED, verdict="fail", head_ref="feat/other"
        )
        bad = self.corrupt(fake.records[name])

        def answer(args: list[str], **kwargs: Any) -> Any:
            if args[1] == f"repos/{REPO}/actions/artifacts/30/zip":
                fake.calls.append(args)
                return subprocess.CompletedProcess(args, 0, bad, "")
            return fake(args, **kwargs)

        cache = {"BABYSIT_RUN_CACHE": str(pathlib.Path(tmp.name, "run.json"))}
        with mock.patch.dict("os.environ", cache):
            for _ in range(2):
                with mock.patch.object(postmerge, "gh_capture", side_effect=answer):
                    evidence = ve.Reader(REPO, "main", now=NOW).evidence(
                        PR, HEAD, pull()
                    )
                self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertEqual(OneRunSharesItsFailRunReads.downloads(fake, 3), 1)


class AnUnreadableRecordIsSharedForTheRun(unittest.TestCase):
    """An untied FAIL record a gate process could not read refuses the run's
    later candidates without another download: pr-merge run 39930321434's
    second candidate fetched 122 records the first had failed on. A failure
    only refuses, so sharing it can only hold; the next run reads again."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.cache = str(pathlib.Path(tmp.name, "run.json"))
        patcher = mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": self.cache})
        patcher.start()
        self.addCleanup(patcher.stop)

    @staticmethod
    def foreign() -> FakeGitHub:
        """A pass at the head and PR 98's FAIL (run 3) whose record is gone."""
        fake = passing(artifact(named(UNRELATED, "fail", 98), 3), runs={3: run(3)})
        return fake

    def test_a_later_candidate_refuses_without_downloading_again(self) -> None:
        fake = self.foreign()
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        # The record is readable now, but this run already failed on it.
        fake.records[named(UNRELATED, "fail", 98)] = record(
            98, UNRELATED, verdict="fail", head_ref="feat/other"
        )
        evidence = read(fake)
        self.assertEqual(evidence.refusal, "verify:unreadable")
        self.assertEqual(evidence.detail, f"record of {named(UNRELATED, 'fail', 98)}")
        self.assertEqual(OneRunSharesItsFailRunReads.downloads(fake, 3), 1)
        # The next run reads it again, and the pass allows.
        with mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": self.cache + "2"}):
            self.assertIsNone(read(fake).refusal)
        self.assertEqual(OneRunSharesItsFailRunReads.downloads(fake, 3), 2)

    def test_an_artifact_without_an_id_refuses_every_read(self) -> None:
        # A listing entry with no id cannot be counted against the live
        # total, so the listing never reads whole, record or not.
        fake = self.foreign()
        del fake.artifacts[1]["id"]
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        fake.records[named(UNRELATED, "fail", 98)] = record(
            98, UNRELATED, verdict="fail", head_ref="feat/other"
        )
        self.assertEqual(read(fake).refusal, "verify:unreadable")


# --- The head-ref digest in a verdict's name ------------------------------------

# The first 16 hex digits of `printf %s <ref> | sha256sum`.
DIGEST_X = "79b4cc554b80dca6"  # feat/x, PR 41's head branch
DIGEST_OTHER = "3b0035df584451e9"  # feat/other


def downloads(fake: FakeGitHub) -> int:
    """Verdict downloads of every run, by artifact id or by run and name."""
    return sum(OneRunSharesItsFailRunReads.downloads(fake, r) for r in fake.runs)


class AnUntiedFailIsTiedByItsNamedHeadRef(unittest.TestCase):
    """pr-verify names a verdict with a digest of the head branch it records,
    so an untied FAIL ties to this pull request by name, without a download,
    exactly when the digest is its head branch's. The run record authenticates
    the name (`_origin`), as it does the verdict.json; a name from any other
    run is ignored like its contents. A name with no digest, uploaded before
    the digest was added, is read as before."""

    @staticmethod
    def heads(
        *, digests: bool = True, runs: dict[int, Any] | None = None
    ) -> FakeGitHub:
        """A pass at the head (run 1); PR 98's FAIL recording feat/other (run
        3) and PR 97's recording feat/x (run 4), both before the pass; and a
        FAIL at an earlier head of PR 41 (run 2)."""
        suffix = (lambda d: f"-{d}") if digests else (lambda d: "")
        fake = passing(
            artifact(named(EARLIER, "fail"), 2),
            artifact(named(UNRELATED, "fail", 98) + suffix(DIGEST_OTHER), 3),
            artifact(named(TIE, "fail", 97) + suffix(DIGEST_X), 4),
            runs={
                2: judged(2, OLDER_START),
                3: judged(3, OLDER_START),
                4: judged(4, OLDER_START),
                **(runs or {}),
            },
        )
        fake.records[named(UNRELATED, "fail", 98) + suffix(DIGEST_OTHER)] = record(
            98, UNRELATED, verdict="fail", head_ref="feat/other"
        )
        fake.records[named(TIE, "fail", 97) + suffix(DIGEST_X)] = record(
            97, TIE, verdict="fail", head_ref="feat/x"
        )
        fake.diffs[TIE] = change("tie")
        return fake

    def test_both_formats_decide_alike_and_the_named_one_downloads_less(self) -> None:
        # Before (no digest): the pass and both untied records, 3 downloads.
        # After: the pass only.
        for digests, count in ((False, 3), (True, 1)):
            with self.subTest(digests=digests):
                fake = self.heads(digests=digests)
                evidence = read(fake)
                self.assertIsNone(evidence.refusal)
                self.assertEqual(
                    evidence.report()["earlierFails"], sorted([EARLIER, TIE])
                )
                self.assertEqual(downloads(fake), count)

    def test_a_tie_after_the_pass_holds_on_the_name_alone(self) -> None:
        fake = self.heads(runs={4: judged(4, "2026-10-15T00:00:01Z")})
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")
        self.assertEqual(downloads(fake), 0)

    def test_a_digest_of_another_branch_unties_without_a_download(self) -> None:
        fake = self.heads()
        fake.artifacts.pop()  # PR 97's tie
        evidence = read(fake)
        self.assertEqual(evidence.report()["earlierFails"], [EARLIER])
        self.assertEqual(downloads(fake), 1)  # the pass

    def test_a_pull_request_with_no_head_ref_ties_nothing_by_name(self) -> None:
        # e3b0c44298fc1c14: the first 16 hex digits of `printf '' | sha256sum`.
        fake = FakeGitHub(
            [artifact(named(TIE, "fail", 97) + "-e3b0c44298fc1c14", 4)], {4: run(4)}
        )
        self.assertEqual(
            read(fake, pull(head={"ref": "", "sha": HEAD})).refusal, "verify:missing"
        )

    def test_a_name_from_a_run_not_of_verifier_origin_is_never_trusted(self) -> None:
        # Each forgery names PR 41's head branch: trusted, it would hold.
        for label, overrides in UnauthenticatedArtifactsAreIgnored.FORGERIES.items():
            with self.subTest(label):
                fake = FakeGitHub(
                    [artifact(named(TIE, "fail", 97) + f"-{DIGEST_X}", 4)],
                    {4: run(4, **overrides)},
                )
                evidence = read(fake)
                self.assertEqual(evidence.refusal, "verify:missing")
                self.assertEqual(evidence.report()["earlierFails"], [])
                self.assertEqual(downloads(fake), 0)
        # The same name from a run of verifier origin holds.
        fake = FakeGitHub(
            [artifact(named(TIE, "fail", 97) + f"-{DIGEST_X}", 4)], {4: run(4)}
        )
        self.assertEqual(read(fake).refusal, "verify:earlier-fail")

    def test_any_branch_name_ties_by_its_digest(self) -> None:
        # The first 16 hex digits of `printf %s <ref> | sha256sum`.
        for ref, digest in (
            ("feat/a+b", "a27da2afd9962004"),
            ("fix/\u00e9", "8c8a071ad0e51f5e"),
        ):
            with self.subTest(ref):
                fake = FakeGitHub(
                    [artifact(named(TIE, "fail", 97) + f"-{digest}", 4)], {4: run(4)}
                )
                pr = pull(head={"ref": ref, "sha": HEAD})
                self.assertEqual(read(fake, pr).refusal, "verify:earlier-fail")
                self.assertEqual(downloads(fake), 0)

    def test_a_malformed_digest_is_no_verdict_and_holds(self) -> None:
        # No verdict name, but a FAIL-shaped one of verifier origin: held,
        # never skipped.
        for suffix in ("-79B4CC554B80DCA6", "-79b4cc554b80dca", "-79b4cc554b80dca6x"):
            with self.subTest(suffix):
                fake = FakeGitHub(
                    [artifact(named(TIE, "fail", 97) + suffix, 4)], {4: run(4)}
                )
                self.assertEqual(read(fake).refusal, "verify:unreadable")


# --- The head-ref map an earlier pr-merge run kept ------------------------------

HEAD_REF_MAP = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/pr-merge/head-ref-map.mjs"
)
ZIP_KIND = "override GET repos/{}/{}/actions/artifacts/{}/zip"


def head_ref_map(
    path: pathlib.Path, refs: dict[int, Any], *, repo: str = REPO, version: Any = 1
) -> str:
    """Write a head-ref map, in the shape head-ref-map.mjs writes, to `path`."""
    payload = {
        "version": version,
        "repo": repo,
        "head_refs": {str(k): v for k, v in refs.items()},
    }
    path.write_text(json.dumps(payload))
    return str(path)


def keep_head_refs(directory: pathlib.Path, previous: str | None) -> dict[str, Any]:
    """Run head-ref-map.mjs `write` as pr-merge.yml does after the gate, and
    return the map it wrote."""
    out = directory / "out.json"
    env = {
        "PATH": os.environ["PATH"],
        "GITHUB_REPOSITORY": REPO,
        "BABYSIT_RUN_CACHE": os.environ["BABYSIT_RUN_CACHE"],
        "BABYSIT_VERIFY_LISTING": os.environ["BABYSIT_VERIFY_LISTING"],
        "HEAD_REFS_OUT": str(out),
    }
    if previous:
        env["HEAD_REFS_PATH"] = previous
    subprocess.run(
        ["node", str(HEAD_REF_MAP), "write"], env=env, check=True, capture_output=True
    )
    return json.loads(out.read_text())


class TheHeadRefMapDecidesAsTheDownloads(unittest.TestCase):
    """An untied FAIL whose id the head-ref map holds is tied or untied from
    the map with no download; any id it lacks is downloaded. Expected
    decisions come from the module docstring's rules and are pinned to what
    the downloads decide on the same artifacts: the multi-head fixture has a
    pass at the head, an earlier FAIL of this pull request, PR 98's FAIL
    recording another ref and PR 97's recording `feat/x`."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)

    def judge(self, tie_created: str, refs_path: str | None) -> tuple[Any, int]:
        """The report and download requests with the map at `refs_path`, the
        untied FAILs' records deleted whenever the map should answer for
        them, so a download the map should have spared reads nothing."""
        fake = EachVerdictIsOneRequest.heads(tie_created)
        mapped = ve.load_head_refs(refs_path, REPO)
        for name, artifact_id in (
            (named(UNRELATED, "fail", 98), 30),
            (named(TIE, "fail", 97), 40),
        ):
            if artifact_id in mapped:
                del fake.records[name]
        env = {ve.HEAD_REFS_ENV: refs_path} if refs_path else {}
        with mock.patch.dict("os.environ", env):
            evidence = read(fake)
        return evidence.report(), download_requests(fake)

    def cases(self) -> dict[str, tuple[str | None, int]]:
        """Each map, with the download requests it leaves: the pass's record
        and each untied FAIL the map does not answer for."""
        both = {30: "feat/other", 40: "feat/x"}
        return {
            "the map ties PR 97 and unties PR 98": (
                head_ref_map(self.dir / "both.json", both),
                1,
            ),
            "an entry for an id no longer listed": (
                head_ref_map(self.dir / "stale.json", {**both, 990: "feat/x"}),
                1,
            ),
            "the map holds only PR 98": (
                head_ref_map(self.dir / "one.json", {30: "feat/other"}),
                2,
            ),
            "no map": (str(self.dir / "absent.json"), 3),
            "not JSON": (self.corrupt("{"), 3),
            "another version": (head_ref_map(self.dir / "v.json", both, version=2), 3),
            "another repository": (
                head_ref_map(self.dir / "r.json", both, repo="example-org/other"),
                3,
            ),
            "an entry that is no string": (
                head_ref_map(self.dir / "s.json", {30: "feat/other", 40: None}),
                3,
            ),
            "a key that is no artifact id": (
                head_ref_map(self.dir / "k.json", {**both, "x": "feat/x"}),
                3,
            ),
        }

    def corrupt(self, text: str) -> str:
        path = self.dir / "corrupt.json"
        path.write_text(text)
        return str(path)

    def test_a_later_pass_clears_both_fails_with_or_without_the_map(self) -> None:
        downloaded, requests = self.judge(OLDER_START, None)
        self.assertIsNone(downloaded["refusal"])
        self.assertEqual(downloaded["earlierFails"], sorted([EARLIER, TIE]))
        self.assertEqual(requests, 3)
        for label, (path, expected) in self.cases().items():
            with self.subTest(label):
                self.assertEqual(self.judge(OLDER_START, path), (downloaded, expected))

    def test_a_tied_fail_after_the_pass_holds_with_or_without_the_map(self) -> None:
        downloaded, requests = self.judge("2026-10-15T00:00:01Z", None)
        self.assertEqual(downloaded["refusal"], "verify:earlier-fail")
        self.assertEqual(requests, 2)
        for label, (path, expected) in self.cases().items():
            with self.subTest(label):
                # The pass decides nothing, so its record is never read.
                self.assertEqual(
                    self.judge("2026-10-15T00:00:01Z", path),
                    (downloaded, expected - 1),
                )

    def test_a_map_entry_answers_where_the_record_is_unreadable(self) -> None:
        # The map holds what a successful download read, so the FAIL is
        # judged as that download would judge it.
        path = head_ref_map(self.dir / "m.json", {30: "feat/other", 40: "feat/x"})
        fake = EachVerdictIsOneRequest.heads()
        fake.records.pop(named(UNRELATED, "fail", 98))
        self.assertEqual(read(fake).refusal, "verify:unreadable")
        with mock.patch.dict("os.environ", {ve.HEAD_REFS_ENV: path}):
            self.assertIsNone(read(fake).refusal)


class TheHeadRefMapCarriesOnlyDownloads(unittest.TestCase):
    """head-ref-map.mjs `write` keeps the map's entries and this run's own
    downloads for ids still listed. A restored actions/cache entry, which any
    job in the default branch's cache scope can write, never reaches the map:
    there an entry could untie a FAIL, which a carried read must never do."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)
        patcher = mock.patch.dict(
            "os.environ",
            {
                "BABYSIT_RUN_CACHE": str(self.dir / "run.json"),
                ve.LISTING_ENV: str(self.dir / "listing.json"),
            },
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_the_gate_downloads_become_the_next_map(self) -> None:
        fake = EachVerdictIsOneRequest.heads()
        old = head_ref_map(self.dir / "old.json", {990: "feat/x", 40: "feat/x"})
        with mock.patch.dict("os.environ", {ve.HEAD_REFS_ENV: old}):
            self.assertIsNone(read(fake).refusal)
        written = keep_head_refs(self.dir, old)
        # 30 was downloaded, 40 came from the map, 990 is no longer listed.
        self.assertEqual(
            written,
            {
                "version": 1,
                "repo": REPO,
                "head_refs": {"30": "feat/other", "40": "feat/x"},
            },
        )

    def test_a_forged_cache_entry_never_reaches_the_map(self) -> None:
        # PR 98's FAIL (id 30) records feat/other. A forged untie is read
        # again from the record; a forged tie holds this run, and the map
        # lacks the id, so the next run downloads it.
        for forged_ref, kept in (("feat/forged", "feat/other"), ("feat/x", None)):
            with self.subTest(forged_ref):
                (self.dir / "run.json").unlink(missing_ok=True)
                forged = {f"{REPO}|30": {"head_ref": forged_ref}}
                restore(
                    self.dir, {"fail-head-ref": forged, "carried-fail-head-ref": forged}
                )
                read(EachVerdictIsOneRequest.heads())
                written = keep_head_refs(self.dir, None)
                self.assertEqual(written["head_refs"].get("30"), kept)
                self.assertEqual(written["head_refs"].get("40"), "feat/x")


class TheHeadRefMapSparesASweepItsDownloads(unittest.TestCase):
    """Requests per sweep by the R0 counter (`babysit-gh-calls`): 200 untied
    old-format FAILs of other pull requests and a pass at the head. With no
    map each FAIL's record is one by-id download; the next run, with the map
    this one kept and five FAILs uploaded since, downloads only those five."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)
        patcher = mock.patch.dict(
            "os.environ",
            {
                "BABYSIT_RUN_CACHE": str(self.dir / "run.json"),
                ve.LISTING_ENV: str(self.dir / "listing.json"),
                # As in pr-merge.yml: the Actions reads carry the job's token.
                ve.TOKEN_ENV: "job-token",
            },
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    @staticmethod
    def add_fails(fake: FakeGitHub, runs: range) -> None:
        for run_id in runs:
            sha = f"{run_id:040x}"
            name = named(sha, "fail", run_id)
            fake.artifacts.append(artifact(name, run_id))
            fake.runs[run_id] = run(run_id)
            fake.records[name] = record(
                run_id, sha, verdict="fail", head_ref=f"b{run_id}"
            )

    @staticmethod
    def sweep(fake: FakeGitHub) -> dict[str, int]:
        import babysit_gh as gh

        def answer(cmd: list[str], **kwargs: Any) -> Any:
            # The fake answers without headers, so the guard's `-i` is dropped.
            args = [a for i, a in enumerate(cmd[1:]) if (i, a) != (1, "-i")]
            base, _, number = (args[1] if args[:1] == ["api"] else "").partition(
                "&page="
            )
            proc = fake(
                ["api", base, "--paginate", "--slurp"]
                if number or base in paged
                else args,
                env_overrides=kwargs.get("env_overrides"),
                binary=kwargs.get("binary"),
            )
            if not (number or base in paged) or proc.returncode != 0:
                return proc
            # A paged read goes page by page: serve the fake's slurped pages
            # one at a time, linked as GitHub links them.
            pages, at = json.loads(proc.stdout), int(number or 1)
            link = (
                f'Link: <https://api.github.com/{base}&page={at + 1}>; rel="next"\r\n'
                if at < len(pages)
                else ""
            )
            body = json.dumps(pages[at - 1])
            return subprocess.CompletedProcess(
                cmd, 0, f"HTTP/2.0 200 OK\r\n{link}\r\n{body}", ""
            )

        paged = {
            f"repos/{REPO}/actions/artifacts?per_page=100",
            f"repos/{REPO}/pulls/{PR}/commits?per_page=100",
        }

        gh.reset_gh_call_counts()
        with mock.patch.object(gh, "run_command", side_effect=answer):
            evidence = ve.Reader(REPO, "main", now=NOW).evidence(PR, HEAD, pull())
        assert evidence.refusal is None, evidence
        return gh.gh_call_counts()

    def test_the_next_sweep_downloads_only_the_new_fails(self) -> None:
        fake = passing()
        self.add_fails(fake, range(1000, 1200))
        before = self.sweep(fake)
        self.assertEqual(before[ZIP_KIND], 201)
        kept = self.dir / "kept.json"
        kept.write_text(json.dumps(keep_head_refs(self.dir, None)))
        # The next run: a new run cache, five FAILs uploaded since.
        self.add_fails(fake, range(1200, 1205))
        with mock.patch.dict(
            "os.environ",
            {
                "BABYSIT_RUN_CACHE": str(self.dir / "next.json"),
                ve.LISTING_ENV: str(self.dir / "next-listing.json"),
                ve.HEAD_REFS_ENV: str(kept),
            },
        ):
            after = self.sweep(fake)
        self.assertEqual(after[ZIP_KIND], 6)


class APrMergeTickListsOnlyBeforeAnAllowOrAKeep(unittest.TestCase):
    """Artifact listings and requests per pr-merge tick, each job's printed as
    a `babysit-gh-calls` line, in a repository shaped like 2026-10-27's: 6,240
    artifacts uploaded four a minute, and the listing the last tick saved 15
    minutes before as the carried base. The merge job's skip filter lists
    first; then 17 gate candidates 20 seconds apart while uploads go on:
    eight refused by a FAIL at their head, seven whose verdict allows and
    whose risk score then refuses, two allowed; with one queued entry that
    each gate judges again once its keep is over `run_cache.MAX_AGE` old, or
    none. enable-auto-merge judges five pull requests on its own saved
    listing (`evidence --shared-listing`)."""

    START = LISTED_AT
    UPLOAD_EVERY = timedelta(seconds=15)
    FILLER = 6240
    # Each candidate in turn: refused by a FAIL ("fail"), its verdict allows
    # and the risk score refuses ("risk"), or allowed ("allow"); the last two
    # judge PR 41 at its head.
    KINDS = "fail risk fail risk fail risk fail risk allow fail risk fail risk fail risk allow fail".split()
    GATE_EVERY = timedelta(seconds=20)

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)
        self.clock = [self.START]
        self.next_id = 100_000
        fake = FakeGitHub([], {1: run(1)}, {named(HEAD, "pass"): record()})
        first = self.START - self.UPLOAD_EVERY * self.FILLER
        for k in range(self.FILLER):
            self.upload(fake, "pr-merge-run-cache", 3, first + self.UPLOAD_EVERY * k)
        # The verdicts: a pass at PR 41's head, a FAIL at each other
        # candidate's head, all uploaded within the last hour.
        self.upload(fake, named(HEAD, "pass"), 1, self.START - timedelta(minutes=50))
        for n in self.refused():
            sha, run_id = self.head(n), 1000 + n
            fail = f"{named(sha, 'fail', n)}-{ve.head_ref_digest(f'b{n}')}"
            fake.runs[run_id] = run(run_id)
            fake.records[fail] = record(n, sha, verdict="fail", head_ref=f"b{n}")
            self.upload(fake, fail, run_id, self.START - timedelta(minutes=40))
        self.fake = fake
        # The last tick's listing, read 15 minutes before this one.
        carried_at = self.START - timedelta(minutes=15)
        self.carry = self.dir / "carry.json"
        self.carry.write_text(
            json.dumps(
                {
                    "fetchedAt": carried_at.isoformat(),
                    "artifacts": [
                        a
                        for a in fake.artifacts
                        if ve._when(a["created_at"]) <= carried_at
                    ],
                }
            )
        )
        for patcher in (
            mock.patch.object(ve, "_wall_clock", side_effect=lambda: self.clock[0]),
            mock.patch.object(run_cache, "now", side_effect=lambda: self.clock[0]),
            mock.patch.object(policy, "pull_request", side_effect=self.pull),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def refused(self) -> list[int]:
        return [42 + i for i in range(self.KINDS.count("fail"))]

    @staticmethod
    def head(number: int) -> str:
        return HEAD if number == PR else format(number, "040x")

    def pull(self, repo: str, number: int) -> dict[str, Any]:
        return pull(
            number=number,
            head={
                "ref": "feat/x" if number == PR else f"b{number}",
                "sha": self.head(number),
            },
        )

    def upload(self, fake: FakeGitHub, name: str, run_id: int, at: datetime) -> None:
        fake.artifacts.append(
            dated(name, run_id, self.next_id, at, expires=at + timedelta(days=7))
        )
        self.next_id += 1

    def tick(self, until: datetime) -> None:
        """Move the clock, uploading four artifacts a minute on the way."""
        while self.clock[0] + self.UPLOAD_EVERY <= until:
            self.clock[0] += self.UPLOAD_EVERY
            self.upload(self.fake, "pr-review-cli-handoff", 3, self.clock[0])
        self.clock[0] = until

    def answer(self, cmd: list[str], **kwargs: Any) -> Any:
        """gh as GitHub answers it: `-i` adds the status, `Date` and `Link`;
        listing pages are 100 artifacts, newest id first."""
        headers = "-i" in cmd
        args = [a for a in cmd[1:] if a != "-i"]
        path = args[1] if args[:1] == ["api"] else ""
        date = self.clock[0].strftime("%a, %d %b %Y %H:%M:%S GMT")
        link = ""
        listing = f"repos/{REPO}/actions/artifacts?per_page=100"
        if path.startswith(listing):
            page = int(path.partition("&page=")[2] or 1)
            self.listings += page == 1
            ordered = sorted(self.fake.artifacts, key=lambda a: -a["id"])
            body = {
                "total_count": len(ordered),
                "artifacts": ordered[(page - 1) * 100 : page * 100],
            }
            if page * 100 < len(ordered):
                link = f'Link: <https://api.github.com/{listing}&page={page + 1}>; rel="next"\r\n'
            proc = subprocess.CompletedProcess(cmd, 0, json.dumps(body), "")
        elif re.fullmatch(rf"repos/{REPO}/pulls/[0-9]+/commits\?per_page=100", path):
            number = int(path.split("/")[4])
            proc = subprocess.CompletedProcess(
                cmd, 0, json.dumps([{"sha": self.head(number)}]), ""
            )
        else:
            proc = self.fake(
                args,
                env_overrides=kwargs.get("env_overrides"),
                binary=kwargs.get("binary"),
            )
        if not headers or proc.returncode != 0:
            return proc
        return subprocess.CompletedProcess(
            cmd, 0, f"HTTP/2.0 200 OK\r\nDate: {date}\r\n{link}\r\n{proc.stdout}", ""
        )

    def environ(self, job: str) -> Any:
        return mock.patch.dict(
            "os.environ",
            {
                "BABYSIT_RUN_CACHE": str(self.dir / f"{job}-run.json"),
                ve.LISTING_ENV: str(self.dir / f"{job}-listing.json"),
                ve.LISTING_CARRY_ENV: str(self.carry),
                ve.TOKEN_ENV: "job-token",
            },
        )

    def merge_job(
        self,
        queued: bool,
        kinds: list[str] | None = None,
        every: timedelta | None = None,
    ) -> tuple[dict[str, int], list[Any]]:
        kinds, every = kinds or self.KINDS, every or self.GATE_EVERY
        refusals: list[Any] = []
        gh.reset_gh_call_counts()
        self.listings = 0
        kept_at: datetime | None = None
        with (
            self.environ("merge"),
            mock.patch.object(gh, "run_command", side_effect=self.answer),
        ):
            # The skip filter (babysit_merge_skip.py filter) lists first, on
            # the carried listing, and saves it for the gate.
            skip = ve.Reader(REPO, "main")
            skip.listing()
            self.assertEqual(skip.listing_mode, "incremental")
            self.skip_calls = gh.gh_call_counts()
            refused = iter(self.refused())
            for i, kind in enumerate(kinds):
                self.tick(self.START + every * (i + 1))
                number = next(refused) if kind == "fail" else PR
                head, pr = self.head(number), self.pull(REPO, number)
                # babysit_merge.py `_evaluate`: a fresh Reader per candidate,
                # and its own listing before an allow.
                reader = ve.Reader(REPO, "main", now=NOW)
                evidence = reader.evidence(number, head, pr, provisional=True)
                if evidence.refusal is None and kind == "allow" and reader.saved:
                    reader.refresh()
                    evidence = reader.evidence(number, head, pr)
                refusals.append(evidence.refusal)
                # `unattended_writes`: a queued entry judged again once its
                # keep is past `run_cache.MAX_AGE` (`_kept_recently`).
                if queued and (
                    kept_at is None or self.clock[0] - kept_at > run_cache.MAX_AGE
                ):
                    self.assertIsNone(reader.queued_hold(PR))
                    kept_at = self.clock[0]
        return gh.gh_call_counts(), refusals

    def arm_job(self) -> tuple[dict[str, int], list[Any]]:
        refusals: list[Any] = []
        gh.reset_gh_call_counts()
        self.listings = 0
        self.clock[0] = self.START
        with (
            self.environ("arm"),
            mock.patch.object(gh, "run_command", side_effect=self.answer),
        ):
            for number in [PR, *self.refused()[:4]]:
                # enable-auto-merge.mjs: one `evidence --shared-listing`
                # process per pull request.
                reader = ve.Reader(REPO, "main", now=NOW, listing_max_age=None)
                refusals.append(
                    reader.evidence(
                        number, self.head(number), self.pull(REPO, number)
                    ).refusal
                )
                self.tick(self.clock[0] + timedelta(seconds=30))
        return gh.gh_call_counts(), refusals

    def report(self, label: str, counts: dict[str, int]) -> None:
        payload = {
            "fixture": label,
            "skip-filter": getattr(self, "skip_calls", None),
            "listings": self.listings,
            "total": sum(counts.values()),
            "calls": dict(sorted(counts.items())),
        }
        print(
            f"babysit-gh-calls {json.dumps(payload, sort_keys=True)}", file=sys.stderr
        )

    def test_the_merge_job_with_an_empty_queue(self) -> None:
        counts, refusals = self.merge_job(queued=False)
        self.report("merge-job queue=0", counts)
        self.assertEqual(
            refusals.count(None), len(self.KINDS) - self.KINDS.count("fail")
        )
        # The skip filter's listing and each allowed candidate's own: no
        # refused candidate lists, whatever the saved listing's age.
        self.assertEqual(self.listings, 1 + self.KINDS.count("allow"))

    def test_the_merge_job_with_a_queued_entry(self) -> None:
        counts, refusals = self.merge_job(queued=True)
        self.report("merge-job queue=1", counts)
        self.assertEqual(
            refusals.count(None), len(self.KINDS) - self.KINDS.count("fail")
        )

    def slow_merge_job(self, queued: bool) -> int:
        # As run 40594967390's merge job: a candidate about every two minutes.
        kinds = "risk fail risk fail risk allow".split()
        counts, refusals = self.merge_job(queued, kinds, timedelta(minutes=2))
        self.report(f"merge-job slow queue={int(queued)}", counts)
        self.assertEqual(refusals.count(None), 4)
        return self.listings

    def test_a_slow_merge_job_with_an_empty_queue(self) -> None:
        # The skip filter's listing, and the allowed candidate's own.
        self.assertEqual(self.slow_merge_job(False), 2)

    def test_a_slow_merge_job_with_a_queued_entry(self) -> None:
        # The queued keeps at 6 and 10 minutes find the listing past the
        # bound and list again; the allow at 12 lists on its own.
        self.assertEqual(self.slow_merge_job(True), 4)

    def test_enable_auto_merge(self) -> None:
        counts, refusals = self.arm_job()
        self.report("enable-auto-merge", counts)
        self.assertEqual(refusals, [None, *["verify:fail"] * 4])
        self.assertEqual(self.listings, 1)


class EvidenceCommandTest(unittest.TestCase):
    """`evidence <number> <head>` prints the gate's judgment for
    enable-auto-merge.mjs, which arms only on a null refusal."""

    def run_main(
        self, argv: list[str], evidence: ve.Evidence
    ) -> tuple[dict[str, Any], ve.Reader]:
        seen: list[ve.Reader] = []

        def judge(
            reader: ve.Reader, number: int, head: str, pr: Any = None
        ) -> ve.Evidence:
            seen.append(reader)
            self.assertEqual((number, head, pr), (PR, HEAD, None))
            return evidence

        out = io.StringIO()
        with (
            mock.patch.object(ve.Reader, "evidence", judge),
            contextlib.redirect_stdout(out),
        ):
            self.assertEqual(ve.main(argv), 0)
        return json.loads(out.getvalue()), seen[0]

    def test_a_pass_prints_a_null_refusal_under_the_given_cap(self) -> None:
        report, reader = self.run_main(
            ["evidence", "--repo", REPO, "--max-fails", "2", str(PR), HEAD],
            ve.Evidence(None, HEAD, (ve.Verdict(HEAD, "pass", 1),), 0),
        )
        self.assertEqual((report["refusal"], report["head"]), (None, HEAD))
        self.assertEqual(
            (reader.repo, reader.branch, reader.max_fails), (REPO, "main", 2)
        )

    def test_a_repeated_fail_prints_its_refusal(self) -> None:
        report, _ = self.run_main(
            ["evidence", "--repo", REPO, str(PR), HEAD],
            ve.Evidence(ve.REPEATED_FAIL, HEAD, (), 0, "fails at 3 heads"),
        )
        self.assertEqual(report["refusal"], ve.REPEATED_FAIL)
        self.assertIs(report["needsHuman"], False)

    def test_only_an_untrusted_spec_goes_to_a_person(self) -> None:
        # Owner rule 2026-10-27: a person only for intent, a design-altering
        # finding or a CRITICAL security issue, trust holds kept. An untrusted
        # spec is a trust boundary; the cap, an old pull request and a changed
        # spec hold for the lanes.
        for refusal, person in (
            (ve.UNTRUSTED_SPEC, True),
            (ve.REPEATED_FAIL, False),
            (ve.TOO_OLD, False),
            (ve.SPEC_CHANGED, False),
        ):
            with self.subTest(refusal):
                self.assertIs(ve.Evidence(refusal, HEAD, (), 0).needs_human, person)

    def test_a_short_head_or_a_zero_cap_is_refused(self) -> None:
        for argv in (
            ["evidence", "--repo", REPO, str(PR), "abc"],
            ["evidence", "--repo", REPO, "--max-fails", "0", str(PR), HEAD],
        ):
            with (
                contextlib.redirect_stderr(io.StringIO()),
                self.assertRaises(SystemExit),
            ):
                ve.main(argv)


class EvidenceCommandReadsAsTheGateDoes(unittest.TestCase):
    """The CLI runs once per pull request with the run's shared listing, so a
    pass judged on that saved listing is judged again on its own, and the
    FAIL cap is the lower of the base's and the default branch head's."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = str(pathlib.Path(tmp.name, "verify-listing.json"))
        patcher = mock.patch.dict("os.environ", {ve.LISTING_ENV: self.path})
        patcher.start()
        self.addCleanup(patcher.stop)

    def cli(self, fake: FakeGitHub, *extra: str) -> dict[str, Any]:
        out = io.StringIO()
        with (
            mock.patch.object(policy, "pull_request", return_value=pull()),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            contextlib.redirect_stdout(out),
        ):
            argv = ["evidence", "--repo", REPO, *extra, str(PR), HEAD]
            self.assertEqual(ve.main(argv, now=NOW), 0)
        return json.loads(out.getvalue())

    def test_a_pass_on_the_saved_listing_meets_a_fail_uploaded_since(self) -> None:
        # The first pull request of the run saves a listing with a pass only.
        self.assertIsNone(self.cli(passing())["refusal"])
        self.assertTrue(pathlib.Path(self.path).exists())
        # A FAIL at the head lands; the next process's saved listing lacks it.
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})
        self.assertEqual(self.cli(fake)["refusal"], "verify:fail")
        self.assertEqual(listings(fake), 1)

    def test_a_refusal_on_the_saved_listing_reads_no_listing(self) -> None:
        fake = FakeGitHub([artifact(named(HEAD, "fail"), 1)], {1: run(1)})
        self.assertEqual(self.cli(fake)["refusal"], "verify:fail")
        self.assertEqual(self.cli(fake)["refusal"], "verify:fail")
        self.assertEqual(listings(fake), 1)

    def test_a_shared_listing_is_read_once_for_every_candidate(self) -> None:
        # enable-auto-merge's run: every candidate allowed, the later ones
        # well past LISTING_MAX_AGE, and still one listing in all, since
        # ci-status's merge-queue step judges FAILs again at the head.
        fake = passing()
        start = datetime.now(UTC)
        for n in range(5):
            at = start + n * 2 * ve.LISTING_MAX_AGE
            with mock.patch.object(ve, "_wall_clock", return_value=at):
                self.assertIsNone(self.cli(fake, "--shared-listing")["refusal"])
        self.assertEqual(listings(fake), 1)

    def test_a_shared_listing_does_not_see_a_fail_uploaded_since(self) -> None:
        # The merge queue holds this one (ci-status runs this reader there).
        self.assertIsNone(self.cli(passing(), "--shared-listing")["refusal"])
        fake = passing(artifact(named(HEAD, "fail"), 2), runs={2: run(2)})
        self.assertIsNone(self.cli(fake, "--shared-listing")["refusal"])
        self.assertEqual(listings(fake), 0)

    def test_a_shared_listing_dated_in_the_future_is_read_again(self) -> None:
        self.cli(passing(), "--shared-listing")
        fake = passing()
        past = datetime.now(UTC) - ve.LISTING_MAX_AGE
        with mock.patch.object(ve, "_wall_clock", return_value=past):
            self.assertIsNone(self.cli(fake, "--shared-listing")["refusal"])
        self.assertEqual(listings(fake), 1)

    def cap(self, base_cap: int, main_cap: int) -> int:
        """The cap the reader judges with for --base-sha, the default branch
        head's config carrying `main_cap`."""
        config = policy.PipelineConfig(MAIN_SHA, "C2", "pr-merge", None, None, (), None)
        seen: list[int] = []

        def judge(
            reader: ve.Reader, number: int, head: str, pr: Any = None
        ) -> ve.Evidence:
            seen.append(reader.max_fails)
            return ve.Evidence(None, head, (), 0)

        with (
            mock.patch.object(
                policy,
                "read_config_at",
                return_value=dataclasses.replace(
                    config, base_sha=EARLIER, max_verify_fails=base_cap
                ),
            ),
            mock.patch.object(
                policy,
                "_default_branch_config",
                return_value=dataclasses.replace(config, max_verify_fails=main_cap),
            ),
            mock.patch.object(ve.Reader, "evidence", judge),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            ve.main(
                [
                    "evidence",
                    "--repo",
                    REPO,
                    "--max-fails",
                    "9",
                    "--base-sha",
                    EARLIER,
                    str(PR),
                    HEAD,
                ],
                now=NOW,
            )
        return seen[0]

    def test_main_raising_the_cap_does_not_raise_it(self) -> None:
        self.assertEqual(self.cap(3, 5), 3)

    def test_main_lowering_the_cap_lowers_it(self) -> None:
        self.assertEqual(self.cap(3, 2), 2)

    def test_an_unreadable_config_refuses(self) -> None:
        out = io.StringIO()
        with (
            mock.patch.object(
                policy,
                "read_config_at",
                side_effect=policy.PolicyReadError("contents 502"),
            ),
            contextlib.redirect_stdout(out),
        ):
            ve.main(
                ["evidence", "--repo", REPO, "--base-sha", EARLIER, str(PR), HEAD],
                now=NOW,
            )
        self.assertEqual(json.loads(out.getvalue())["refusal"], ve.UNREADABLE)


class EvidenceCommandReadsTheLaneLink(unittest.TestCase):
    """`evidence --lane-link`, which enable-auto-merge.mjs runs: the issue
    link the pr-merge lane takes from its own pull request, by the rule in
    docs/conventions/pr-pipeline/README.md ("Eligibility"): one closing issue
    here, or, with none, the one issue plain `Refs: #<n>` lines name; two
    issues refuse `refs-issues:2`, a pull request or a number naming nothing
    `refs-not-an-issue`, and a failed read refuses. A refused link reads no
    verdict."""

    def cli(self, fake: FakeGitHub) -> dict[str, Any]:
        out = io.StringIO()
        with (
            mock.patch.object(policy, "pull_request", return_value=pull()),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(policy, "gh_capture", side_effect=fake),
            contextlib.redirect_stdout(out),
        ):
            argv = ["evidence", "--lane-link", "--repo", REPO, str(PR), HEAD]
            self.assertEqual(ve.main(argv, now=NOW), 0)
        return json.loads(out.getvalue())

    def refs(self, body: str, **refs: str) -> FakeGitHub:
        fake = passing()
        fake.closing, fake.body = [], body
        fake.refs = {int(n.removeprefix("n")): kind for n, kind in refs.items()}
        return fake

    def test_a_closing_pull_request_is_linked_and_its_pass_allows(self) -> None:
        fake = passing()
        report = self.cli(fake)
        self.assertEqual((report["ineligible"], report["refusal"]), (None, None))
        # The verdict read takes the link read's pull request: one read.
        closing = [c for c in fake.calls if any("closingIssues" in a for a in c)]
        self.assertEqual(len(closing), 1)

    def test_one_plain_refs_line_is_linked_and_its_verdict_is_read(self) -> None:
        fake = self.refs("Refs: #7\n\n## Summary", n7=REPO)
        report = self.cli(fake)
        self.assertIsNone(report["ineligible"])
        self.assertEqual(listings(fake), 1)

    def test_a_refused_link_reads_no_verdict(self) -> None:
        for body, refs, want in (
            ("Refs: #7\nRefs: #8\n", {"n7": REPO, "n8": REPO}, "refs-issues:2"),
            ("Refs: #7, #8\n", {"n7": REPO}, "refs-line-not-plain"),
            ("refs: #7\n", {"n7": REPO}, "refs-line-not-plain"),
            ("Refs: #7\n", {"n7": "PullRequest"}, "refs-not-an-issue"),
            ("Refs: #9\n", {}, "refs-not-an-issue"),
            ("## Summary\n", {}, "linked-issues:0"),
        ):
            with self.subTest(body=body):
                fake = self.refs(body, **refs)
                report = self.cli(fake)
                self.assertEqual(
                    (report["ineligible"], report["refusal"]), (want, ve.INELIGIBLE)
                )
                self.assertEqual(listings(fake), 0)

    def test_a_closing_issue_elsewhere_or_two_refuse(self) -> None:
        for closing, want in (
            ([(7, REPO), (8, REPO)], "linked-issues:2"),
            ([(7, "other-org/other-repo")], "linked-issue-other-repository"),
        ):
            fake = passing()
            fake.closing = closing
            self.assertEqual(self.cli(fake)["ineligible"], want)

    def test_a_failed_link_read_refuses(self) -> None:
        for fake in (passing(), self.refs("Refs: #7\n", n7="error")):
            if not fake.refs:
                fake.fail.add("graphql")
            report = self.cli(fake)
            self.assertTrue(str(report["ineligible"]).startswith("unreadable: "))
            self.assertEqual(report["refusal"], ve.INELIGIBLE)
            self.assertEqual(listings(fake), 0)

    def test_an_untrusted_label_on_the_issue_refuses_for_a_person(self) -> None:
        # The label lands on the linked issue after admission, while the lane
        # builds: the arm-time read sees it, on either link.
        for fake in (passing(), self.refs("Refs: #7\n\n## Summary", n7=REPO)):
            fake.labels[7] = ["agent-ready", policy.UNTRUSTED_PROVENANCE_LABEL]
            report = self.cli(fake)
            self.assertEqual(
                (report["ineligible"], report["refusal"]),
                ("untrusted-provenance", ve.INELIGIBLE),
            )
            self.assertEqual(listings(fake), 0)

    def test_a_variant_spelling_of_the_label_refuses(self) -> None:
        for label in (
            "Work-Class: Untrusted-Provenance",
            "work-class:untrusted_provenance",
            "untrusted",
            "work-class \u2013 UNTRUSTED provenance",
        ):
            with self.subTest(label=label):
                fake = passing()
                fake.labels[7] = [label]
                self.assertEqual(self.cli(fake)["ineligible"], "untrusted-provenance")

    def test_unreadable_labels_refuse(self) -> None:
        fake = passing()
        fake.labels[7], fake.labels_total[7] = ["agent-ready"], 101
        report = self.cli(fake)
        self.assertEqual(
            (report["ineligible"], report["refusal"]),
            ("issue-labels-unreadable", ve.INELIGIBLE),
        )
        self.assertEqual(listings(fake), 0)

    def test_an_unreadable_timeline_refuses(self) -> None:
        fake = passing()
        fake.fail.add("timeline")
        report = self.cli(fake)
        self.assertTrue(str(report["ineligible"]).startswith("unreadable: "))
        self.assertEqual(report["refusal"], ve.INELIGIBLE)

    def test_the_label_removed_by_a_non_human_refuses(self) -> None:
        def unlabeled(login: str, kind: str, app: Any = None) -> dict[str, Any]:
            return {
                "event": "unlabeled",
                "label": {"name": policy.UNTRUSTED_PROVENANCE_LABEL},
                "actor": {"login": login, "type": kind},
                "performed_via_github_app": app,
            }

        for event in (
            unlabeled("agent-lanes[bot]", "Bot"),
            unlabeled("maintainer", "User", {"slug": "some-app"}),
            unlabeled("reader", "User"),
        ):
            with self.subTest(event=event):
                fake = passing()
                fake.timeline[7] = [event]
                fake.permissions = {"maintainer": "admin", "reader": "read"}
                self.assertEqual(
                    self.cli(fake)["ineligible"],
                    "untrusted-provenance-removed-by-non-human",
                )

    def test_a_clean_or_person_cleared_issue_still_arms(self) -> None:
        for labels, timeline in (
            (["agent-ready", "type: bug"], []),
            (
                ["agent-ready"],
                [
                    {
                        "event": "unlabeled",
                        "label": {"name": policy.UNTRUSTED_PROVENANCE_LABEL},
                        "actor": {"login": "maintainer", "type": "User"},
                        "performed_via_github_app": None,
                    }
                ],
            ),
        ):
            with self.subTest(labels=labels, timeline=timeline):
                fake = passing()
                fake.labels[7], fake.timeline[7] = labels, timeline
                fake.permissions = {"maintainer": "write"}
                report = self.cli(fake)
                self.assertEqual(
                    (report["ineligible"], report["refusal"]), (None, None)
                )
                # The labels ride the link's one GraphQL read; the timeline
                # is one REST read.
                timelines = [c for c in fake.calls if any("/timeline" in a for a in c)]
                self.assertEqual(len(timelines), 1)

    def test_without_the_flag_no_link_is_read(self) -> None:
        fake = self.refs("Refs: #7\nRefs: #8\n")
        out = io.StringIO()
        with (
            mock.patch.object(policy, "pull_request", return_value=pull()),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            contextlib.redirect_stdout(out),
        ):
            ve.main(["evidence", "--repo", REPO, str(PR), HEAD], now=NOW)
        self.assertNotIn("ineligible", json.loads(out.getvalue()))


def ci_status_jobs(draft_step: str) -> dict[str, Any]:
    """ci-status's steps as `GET .../actions/runs/{id}/jobs?filter=latest`
    returned them for #11832's checks runs at head 8d7ef05b: `Note a draft`
    ran (success) in run 41273054889, started on the draft, and was skipped in
    run 41273113342, started after the ready flip (pr-require-checks.yml:
    `if: github.event.pull_request.draft == true`)."""
    steps = [("Note a draft", draft_step), ("Aggregate lane results", "success")]
    job = {
        "id": 9001,
        "name": "ci-status",
        "conclusion": "success",
        "steps": [{"name": n, "conclusion": c} for n, c in steps],
    }
    return {"total_count": 1, "jobs": [job]}


DRAFT_JOBS = ci_status_jobs("success")
READY_JOBS = ci_status_jobs("skipped")


def ci_status_with(steps: list[dict[str, Any]]) -> dict[str, Any]:
    job = {"id": 9001, "name": "ci-status", "conclusion": "success", "steps": steps}
    return {"total_count": 1, "jobs": [job]}


# The jobs API can list a finished job's steps empty or cut short
# (pr-require-checks.yml, the ci-status review-lanes note), so only a listed
# conclusion of the draft step decides; each of these is unreadable.
UNREADABLE_DRAFT_STATE: dict[str, dict[str, Any]] = {
    "an empty step list": ci_status_with([]),
    "the draft step listed with no conclusion": ci_status_with(
        [{"name": "Note a draft", "conclusion": None}]
    ),
    "the draft step not listed": ci_status_with(
        [{"name": "Aggregate lane results", "conclusion": "success"}]
    ),
    "no ci-status job": {
        "total_count": 1,
        "jobs": [{"id": 9002, "name": "lint-repo", "conclusion": "success"}],
    },
}
DRAFT_CHECKS, READY_CHECKS = 41273054889, 41273113342
# #11832's times: the draft checks run was created at 04:25:39, the verifier
# run that judged it and uploaded the FAIL at 04:26:22, and the ready checks
# run at 04:26:33.
FAIL_JUDGED = "2026-11-01T04:26:22Z"


def draft_race(
    fake: FakeGitHub, sha: str, before: dict[str, Any] = DRAFT_JOBS
) -> FakeGitHub:
    """Give `sha` #11832's two checks runs, the earlier one's jobs `before`."""
    fake.checks_runs[sha] = [
        {"id": READY_CHECKS, "created_at": "2026-11-01T04:26:33Z"},
        {"id": DRAFT_CHECKS, "created_at": "2026-11-01T04:25:39Z"},
    ]
    fake.jobs[DRAFT_CHECKS] = before
    fake.jobs[READY_CHECKS] = READY_JOBS
    return fake


class AFailJudgedFromADraftRunCountsAsNone(unittest.TestCase):
    """A pull request opened as a draft and marked ready seconds later gets
    two checks runs at one head; pr-verify judged the draft one, whose suites
    all skipped, and failed it for "no tests ran" (#11832, #11836). Such a
    FAIL counts nowhere: not at the head, not at another head, not toward
    the cap of this or another pull request. Every failed read keeps it."""

    @staticmethod
    def fail_at(*shas: str) -> FakeGitHub:
        """A pass at the head, and this pull request's FAILs at `shas`, each
        uploaded by a verifier run created when #11832's was."""
        runs = {i: judged(i, FAIL_JUDGED) for i in range(2, 2 + len(shas))}
        return passing(
            *(artifact(named(sha, "fail"), i) for i, sha in zip(runs, shas)),
            runs=runs,
        )

    def test_at_the_head(self) -> None:
        self.assertIsNone(read(draft_race(self.fail_at(HEAD), HEAD)).refusal)
        ready = draft_race(self.fail_at(HEAD), HEAD, READY_JOBS)
        self.assertEqual(read(ready).refusal, "verify:fail")

    def test_at_an_earlier_head(self) -> None:
        self.assertIsNone(read(draft_race(self.fail_at(EARLIER), EARLIER)).refusal)
        self.assertEqual(read(self.fail_at(EARLIER)).refusal, "verify:earlier-fail")

    def test_toward_the_cap(self) -> None:
        heads = (EARLIER, IN_PR, UNRELATED)
        fake = self.fail_at(*heads)
        self.assertEqual(read(fake).refusal, "verify:repeated-fail")
        for sha in heads:
            draft_race(fake, sha)
        self.assertIsNone(read(fake).refusal)

    def test_toward_another_pull_requests_cap(self) -> None:
        fake = FailsOnAnotherPullRequestForTheSameIssueCount.sibling_fails(
            *SIBLING_HEADS
        )
        for run_id in set(fake.runs) - {1}:
            fake.runs[run_id] = judged(run_id, FAIL_JUDGED)
        self.assertEqual(read(fake).refusal, "verify:repeated-fail")
        for sha in SIBLING_HEADS:
            draft_race(fake, sha)
        self.assertIsNone(read(fake).refusal)

    def test_only_a_listed_draft_step_conclusion_reads_the_state(self) -> None:
        def draft_run(jobs: dict[str, Any]) -> bool:
            fake = FakeGitHub([], {})
            fake.jobs[DRAFT_CHECKS] = jobs
            with mock.patch.object(postmerge, "gh_capture", side_effect=fake):
                return ve.Reader(REPO, "main")._draft_run(DRAFT_CHECKS)

        for label, jobs in UNREADABLE_DRAFT_STATE.items():
            with self.subTest(label), self.assertRaises(ve._Unreadable):
                draft_run(jobs)
        self.assertTrue(draft_run(DRAFT_JOBS))
        self.assertFalse(draft_run(READY_JOBS))

    def test_an_unreadable_draft_state_keeps_the_fail(self) -> None:
        for label, jobs in UNREADABLE_DRAFT_STATE.items():
            with self.subTest(label):
                fake = draft_race(self.fail_at(HEAD), HEAD, jobs)
                self.assertEqual(read(fake).refusal, "verify:fail")

    def test_a_failed_or_short_read_keeps_the_fail(self) -> None:
        def cut(fake: FakeGitHub) -> None:
            fake.checks_total[HEAD] = 3

        def jobs_unread(fake: FakeGitHub) -> None:
            del fake.jobs[DRAFT_CHECKS]

        def jobs_cut(fake: FakeGitHub) -> None:
            fake.jobs[DRAFT_CHECKS] = {**DRAFT_JOBS, "total_count": 2}

        def none_before(fake: FakeGitHub) -> None:
            fake.checks_runs[HEAD] = fake.checks_runs[HEAD][:1]

        def a_ready_one_before(fake: FakeGitHub) -> None:
            fake.checks_runs[HEAD].append(
                {"id": 41273000001, "created_at": "2026-11-01T04:25:00Z"}
            )
            fake.jobs[41273000001] = READY_JOBS

        def no_time(fake: FakeGitHub) -> None:
            fake.checks_runs[HEAD].append({"id": 41273000002})

        def listing_fails(fake: FakeGitHub) -> None:
            fake.checks_runs.pop(HEAD)

        for change in (
            cut,
            jobs_unread,
            jobs_cut,
            none_before,
            a_ready_one_before,
            no_time,
            listing_fails,
        ):
            with self.subTest(change.__name__):
                fake = draft_race(self.fail_at(HEAD), HEAD)
                change(fake)
                self.assertEqual(read(fake).refusal, "verify:fail")


class EvidenceCommandTakesWhatTheQueueJobHolds(unittest.TestCase):
    """ci-status's merge-queue step runs `evidence --base-sha` with the
    default branch from the event (`merge_policy.DEFAULT_BRANCH_ENV`) and the
    pull request record it read (`PULL_ENV`): neither is read again, and the
    default branch's tip is read once for the config and the trusted list.
    A record for another head is not taken."""

    def setUp(self) -> None:
        tmp = pathlib.Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.pull_path = tmp / "lanes-pull.json"
        self.env = {ve.LISTING_ENV: str(tmp / "verify-listing.json")}
        self.enterContext(mock.patch.dict(os.environ, self.env))
        os.environ.pop(run_cache.ENV, None)
        os.environ.pop(policy.DEFAULT_BRANCH_ENV, None)
        os.environ.pop(ve.PULL_ENV, None)

    def cli(self, fake: FakeGitHub, env: dict[str, str]) -> tuple[Any, mock.Mock]:
        config = policy.PipelineConfig(MAIN_SHA, "C2", "pr-merge", None, None, (), None)
        out = io.StringIO()
        live = mock.Mock(return_value=pull())
        with (
            mock.patch.dict(os.environ, env),
            mock.patch.object(
                policy,
                "read_config_at",
                side_effect=lambda repo, sha, file_at=None: dataclasses.replace(
                    config, base_sha=sha
                ),
            ),
            mock.patch.object(policy, "pull_request", live),
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            contextlib.redirect_stdout(out),
        ):
            argv = ["evidence", "--repo", REPO, "--base-sha", MAIN_SHA, str(PR), HEAD]
            self.assertEqual(ve.main(argv, now=NOW), 0)
        return json.loads(out.getvalue()), live

    def write_pull(self, head: str) -> None:
        base = {"ref": "main", "sha": MAIN_SHA, "repo": {"full_name": REPO}}
        record = pull(base=base, head={"ref": "feat/x", "sha": head})
        self.pull_path.write_text(json.dumps(record))

    def held(self) -> dict[str, str]:
        return {
            policy.DEFAULT_BRANCH_ENV: "main",
            "GITHUB_REPOSITORY": REPO,
            ve.PULL_ENV: str(self.pull_path),
        }

    def test_the_held_reads_are_not_read_again(self) -> None:
        self.write_pull(HEAD)
        fake = passing()
        report, live = self.cli(fake, self.held())
        self.assertIsNone(report["refusal"])
        live.assert_not_called()
        self.assertNotIn(["api", f"repos/{REPO}"], fake.calls)
        tips = [c for c in fake.calls if c[1:] == [f"repos/{REPO}/git/ref/heads/main"]]
        self.assertEqual(len(tips), 1)
        # The trusted list is read, at that one tip.
        self.assertTrue(
            any(
                c[-1].endswith(f"/contents/{ve.TRUSTED_ACTORS_PATH}?ref={MAIN_SHA}")
                for c in fake.calls
            )
        )

    def test_a_record_for_another_head_reads_the_pull_request_live(self) -> None:
        self.write_pull(EARLIER)
        report, live = self.cli(passing(), self.held())
        self.assertIsNone(report["refusal"])
        live.assert_called_once_with(REPO, PR)


if __name__ == "__main__":
    unittest.main()

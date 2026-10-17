#!/usr/bin/env python3
"""Verifier verdicts for the pr-merge lane.

`.github/workflows/pr-verify.yml` judges each pull request head that passes
PR Require Checks and uploads an artifact named
`pr-verify-<pr>-<head-sha>-<pass|pass-notes|fail>`. Only that workflow's run
on main can produce a counted one: an artifact counts when its run is that
file, event `workflow_run`, on the branch, concluded `success`, in this
repository with a head in this repository, and its head SHA is on the branch.
Any other artifact with such a name is ignored, never counted as a pass or a
fail. Only steps of a run can upload its artifacts, so the run record
authenticates the name.

`Reader.evidence` decides one pull request at its vetted head:

- an authenticated FAIL at the head: `verify:fail`;
- an authenticated FAIL at any other head of the pull request:
  `verify:earlier-fail`, which a human must clear (`needs_human`);
- an authenticated PASS or PASS-NOTES at the head: no refusal;
- otherwise `verify:missing`, and `verify:unreadable` when the listing cannot
  be read.

The repository's artifacts are listed once per `Reader`, every page, and
filtered on the name here: the API's name filter matches whole names only.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

import babysit_merge_policy as merge_policy
import babysit_postmerge as postmerge
from babysit_util import json_object

WORKFLOW_PATH = ".github/workflows/pr-verify.yml"
NAME_RE = re.compile(r"pr-verify-([1-9][0-9]*)-([0-9a-f]{40})-(pass|pass-notes|fail)")
PASSES = ("pass", "pass-notes")
FAIL = "verify:fail"
EARLIER_FAIL = "verify:earlier-fail"
MISSING = "verify:missing"
UNREADABLE = "verify:unreadable"


@dataclass(frozen=True)
class Verdict:
    sha: str
    verdict: str
    run_id: int


@dataclass(frozen=True)
class Evidence:
    refusal: str | None
    head: str
    verdicts: tuple[Verdict, ...]
    ignored: int
    detail: str | None = None

    @property
    def needs_human(self) -> bool:
        return self.refusal == EARLIER_FAIL

    def report(self) -> dict[str, Any]:
        return {
            "refusal": self.refusal,
            "needsHuman": self.needs_human,
            "head": self.head,
            "atHead": sorted({v.verdict for v in self.verdicts if v.sha == self.head}),
            "earlierFails": sorted(
                {
                    v.sha
                    for v in self.verdicts
                    if v.verdict == "fail" and v.sha != self.head
                }
            ),
            "ignored": self.ignored,
            "detail": self.detail,
        }


@dataclass
class Reader:
    repo: str
    branch: str
    _artifacts: list[dict[str, Any]] | None = None
    _runs: dict[int, bool] = field(default_factory=dict)
    _context: postmerge._Context | None = None

    def _listing(self) -> list[dict[str, Any]]:
        if self._artifacts is None:
            self._artifacts = postmerge._paginated(
                f"repos/{self.repo}/actions/artifacts?per_page=100",
                "repository artifacts",
                "artifacts",
            )
        return self._artifacts

    def _authentic(self, run_id: int) -> bool:
        if run_id not in self._runs:
            try:
                record = json_object(
                    postmerge._read(
                        ["api", f"repos/{self.repo}/actions/runs/{run_id}"],
                        f"run {run_id}",
                    )
                )
                head = record.get("head_sha")
                self._runs[run_id] = (
                    record.get("id") == run_id
                    and record.get("path") == WORKFLOW_PATH
                    and record.get("event") == "workflow_run"
                    and record.get("head_branch") == self.branch
                    and record.get("status") == "completed"
                    and record.get("conclusion") == "success"
                    and json_object(record.get("repository")).get("full_name")
                    == self.repo
                    and json_object(record.get("head_repository")).get("full_name")
                    == self.repo
                    and isinstance(head, str)
                    and merge_policy.SHA_RE.fullmatch(head) is not None
                    and self._contains(head)
                )
            except postmerge.PostMergeReadError:
                self._runs[run_id] = False
        return self._runs[run_id]

    def _contains(self, head: str) -> bool:
        if self._context is None:
            owner, _, name = self.repo.partition("/")
            self._context = postmerge._Context(owner, name, "")
        return self._context.contains(head, self.branch)

    def evidence(self, number: int, head: str) -> Evidence:
        try:
            listing = self._listing()
        except postmerge.PostMergeReadError as exc:
            return Evidence(UNREADABLE, head, (), 0, str(exc))
        verdicts: list[Verdict] = []
        ignored = 0
        for item in map(json_object, listing):
            match = NAME_RE.fullmatch(str(item.get("name") or ""))
            if not match or int(match[1]) != number or item.get("expired") is not False:
                continue
            run_id = json_object(item.get("workflow_run")).get("id")
            if isinstance(run_id, int) and self._authentic(run_id):
                verdicts.append(Verdict(match[2], match[3], run_id))
            else:
                ignored += 1
        at_head = {v.verdict for v in verdicts if v.sha == head}
        if "fail" in at_head:
            refusal: str | None = FAIL
        elif any(v.verdict == "fail" for v in verdicts):
            refusal = EARLIER_FAIL
        elif at_head & set(PASSES):
            refusal = None
        else:
            refusal = MISSING
        return Evidence(refusal, head, tuple(verdicts), ignored)

    def queued_hold(self, number: int) -> str | None:
        """Why a queued entry must leave: no passing verdict at its head now.
        An unreadable pull request is a hold."""
        try:
            head = json_object(merge_policy.pull_request(self.repo, number).get("head"))
        except merge_policy.PolicyReadError:
            return UNREADABLE
        return self.evidence(number, str(head.get("sha"))).refusal

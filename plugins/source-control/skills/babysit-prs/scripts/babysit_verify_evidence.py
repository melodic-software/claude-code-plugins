#!/usr/bin/env python3
"""Verifier verdicts for the pr-merge lane.

`.github/workflows/pr-verify.yml` judges each pull request head that passes
PR Require Checks and uploads an artifact named
`pr-verify-<pr>-<head-sha>-<pass|pass-notes|fail>` holding `verdict.json`.
Only steps of a run can upload its artifacts, so the run record authenticates
the name. An artifact's run is of verifier origin when it is that file, event
`workflow_run`, on the branch, in this repository with a head in this
repository, and its head SHA is a full SHA on the branch. A FAIL counts from
any run of verifier origin, whatever its status or conclusion, since the
upload comes before the run's later steps; a PASS or PASS-NOTES counts only
from a completed, successful one. Any other artifact is ignored.

`Reader.evidence` decides one pull request at its vetted head, in this order:

- the pull request was created more than `TOO_OLD_DAYS` ago:
  `verify:too-old`, since a verdict may already have expired;
- a counted FAIL at the head, under any pull request number: `verify:fail`;
- a counted FAIL at another head of this pull request: its number, one of its
  commits (`pulls/<n>/commits`), or a verdict recording its head branch:
  `verify:earlier-fail`;
- a FAIL-named artifact tied to this pull request by number or SHA whose run
  cannot be read: `verify:unreadable`. An untied FAIL whose run cannot be read
  is ignored; an untied FAIL whose run is readable and of verifier origin but
  whose recorded head branch (its verdict.json) cannot be read is
  `verify:unreadable`, so one such artifact blocks every pull request until it
  is readable, expires or is deleted;
- a counted PASS or PASS-NOTES at the head of this pull request: refused
  `verify:spec-changed` unless the pull request's closing issues now are the
  ones its verdict recorded, none was edited after its run started, and each
  issue's trusted comments (`_spec_comments`) are the recorded ones by id and
  update time; then allowed only when every linked issue it records was
  written, and last edited if ever, by a User on the trusted list's humans
  other than the pull request's author, else `verify:untrusted-spec`;
- otherwise `verify:missing`.

`verify:too-old`, `verify:earlier-fail`, `verify:spec-changed` and
`verify:untrusted-spec` need a human, who merges in person. Any read that fails refuses
(`verify:unreadable`). The repository's artifacts are listed once per
`Reader`, which pr-merge.yml builds once per candidate gate run, every page,
and filtered on the name here: the API's name filter matches whole names only.
"""

from __future__ import annotations

import json
import os
import re
import tempfile
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import babysit_merge_policy as merge_policy
import babysit_postmerge as postmerge
from babysit_classify import is_dependency_author
from babysit_gh import flatten_paginated_items
from babysit_util import is_json_array, is_json_object, json_array, json_object

WORKFLOW_PATH = ".github/workflows/pr-verify.yml"
TRUSTED_ACTORS_PATH = ".github/standards/trusted-actors/trusted-actors.json"
TOKEN_ENV = "BABYSIT_VERIFY_GH_TOKEN"
NAME_RE = re.compile(r"pr-verify-([1-9][0-9]*)-([0-9a-f]{40})-(pass|pass-notes|fail)")
PASSES = ("pass", "pass-notes")
# Artifacts last at most 90 days in this repository (the retention maximum,
# and the repository's setting), so a verdict on an older pull request may be
# gone. 80 leaves ten days of margin (judgment).
TOO_OLD_DAYS = 80
# `GET /pulls/{n}/commits` lists at most 250 commits.
COMMITS_CAP = 250
FAIL = "verify:fail"
EARLIER_FAIL = "verify:earlier-fail"
MISSING = "verify:missing"
UNREADABLE = "verify:unreadable"
TOO_OLD = "verify:too-old"
UNTRUSTED_SPEC = "verify:untrusted-spec"
SPEC_CHANGED = "verify:spec-changed"
NEEDS_HUMAN = (EARLIER_FAIL, TOO_OLD, UNTRUSTED_SPEC, SPEC_CHANGED)
CLOSING_QUERY = (
    "query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){"
    "pullRequest(number:$n){closingIssuesReferences(first:10){totalCount "
    "nodes{number lastEditedAt repository{nameWithOwner} "
    "comments(first:100){totalCount nodes{databaseId updatedAt lastEditedAt "
    "author{...actor} editor{...actor}}}}}}}}"
    "fragment actor on Actor{__typename login "
    "... on User{databaseId} ... on Bot{databaseId}}"
)

# A run's standing: unreadable, foreign (not of verifier origin), origin (of
# verifier origin, not a completed success), or counted (both).
UNREAD, FOREIGN, ORIGIN, COUNTED = "unreadable", "foreign", "origin", "counted"


class _Unreadable(Exception):
    pass


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
        return self.refusal in NEEDS_HUMAN

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


def _read(args: list[str], label: str) -> Any:
    try:
        return postmerge._read(args, label)
    except postmerge.PostMergeReadError as exc:
        raise _Unreadable(str(exc)) from exc


@dataclass
class Reader:
    repo: str
    branch: str
    now: datetime | None = None
    # The token for the Actions reads (artifact listing, run records,
    # download): pr-merge.yml passes the job's GITHUB_TOKEN, which holds
    # `actions: read`, while the lane token it runs gh with holds none.
    actions_token: str | None = field(
        default_factory=lambda: os.environ.get(TOKEN_ENV) or None
    )
    _artifacts: list[dict[str, Any]] | None = None
    _runs: dict[int, str] = field(default_factory=dict)
    _started: dict[int, Any] = field(default_factory=dict)
    _on_branch: dict[str, bool] = field(default_factory=dict)
    _records: dict[tuple[int, str], dict[str, Any]] = field(default_factory=dict)
    _humans: frozenset[int] | None = None

    def _listing(self) -> list[dict[str, Any]]:
        listing = self._artifacts
        if listing is None:
            payload = self._actions(
                [
                    "api",
                    f"repos/{self.repo}/actions/artifacts?per_page=100",
                    "--paginate",
                    "--slurp",
                ],
                "repository artifacts",
            )
            try:
                listing = flatten_paginated_items(
                    payload, "repository artifacts", items_key="artifacts"
                )
            except RuntimeError as exc:
                raise _Unreadable(str(exc)) from exc
            self._artifacts = listing
        return listing

    def _env(self) -> dict[str, str] | None:
        return {"GH_TOKEN": self.actions_token} if self.actions_token else None

    def _actions(self, args: list[str], label: str) -> Any:
        """A read the Actions API answers, under the Actions token when set."""
        try:
            proc = postmerge.gh_capture(args, env_overrides=self._env())
        except (RuntimeError, ValueError, OSError) as exc:
            raise _Unreadable(f"{label}: {exc}") from exc
        if proc.returncode != 0:
            raise _Unreadable(
                f"{label}: {(proc.stderr or '').strip() or proc.returncode}"
            )
        try:
            return json.loads(proc.stdout) if proc.stdout.strip() else None
        except ValueError as exc:
            raise _Unreadable(f"{label}: {exc}") from exc

    def _contains(self, sha: str) -> bool:
        if sha not in self._on_branch:
            compare = json_object(
                _read(
                    ["api", f"repos/{self.repo}/compare/{sha}...{self.branch}"],
                    f"compare {sha[:12]}...{self.branch}",
                )
            )
            self._on_branch[sha] = compare.get("status") in ("ahead", "identical")
        return self._on_branch[sha]

    def _run_state(self, run_id: int) -> str:
        if run_id not in self._runs:
            try:
                record = json_object(
                    self._actions(
                        ["api", f"repos/{self.repo}/actions/runs/{run_id}"],
                        f"run {run_id}",
                    )
                )
                head = record.get("head_sha")
                origin = (
                    record.get("id") == run_id
                    and record.get("path") == WORKFLOW_PATH
                    and record.get("event") == "workflow_run"
                    and record.get("head_branch") == self.branch
                    and json_object(record.get("repository")).get("full_name")
                    == self.repo
                    and json_object(record.get("head_repository")).get("full_name")
                    == self.repo
                    and isinstance(head, str)
                    and merge_policy.SHA_RE.fullmatch(head) is not None
                    and self._contains(head)
                )
                self._started[run_id] = record.get("run_started_at")
                done = (
                    record.get("status") == "completed"
                    and record.get("conclusion") == "success"
                )
                self._runs[run_id] = (
                    FOREIGN if not origin else COUNTED if done else ORIGIN
                )
            except _Unreadable:
                self._runs[run_id] = UNREAD
        return self._runs[run_id]

    def _record(self, run_id: int, name: str) -> dict[str, Any]:
        """The artifact's verdict.json, downloaded once."""
        key = (run_id, name)
        if key not in self._records:
            with tempfile.TemporaryDirectory() as tmp:
                args = ["run", "download", str(run_id), "-R", self.repo]
                try:
                    proc = postmerge.gh_capture(
                        [*args, "-n", name, "-D", tmp], env_overrides=self._env()
                    )
                except (RuntimeError, ValueError, OSError) as exc:
                    raise _Unreadable(f"artifact {name}: {exc}") from exc
                path = Path(tmp) / "verdict.json"
                if proc.returncode != 0 or not path.is_file():
                    raise _Unreadable(f"artifact {name} of run {run_id}")
                try:
                    record = json.loads(path.read_text(encoding="utf-8"))
                except ValueError as exc:
                    raise _Unreadable(f"artifact {name}: {exc}") from exc
            if not is_json_object(record):
                raise _Unreadable(f"artifact {name}: not an object")
            self._records[key] = record
        return self._records[key]

    def _trusted_humans(self) -> frozenset[int]:
        humans = self._humans
        if humans is None:
            listing = json_object(
                _read(
                    [
                        "api",
                        "-H",
                        "Accept: application/vnd.github.raw",
                        f"repos/{self.repo}/contents/{TRUSTED_ACTORS_PATH}?ref={self.branch}",
                    ],
                    "trusted-actor list",
                )
            )
            actors = listing.get("actors")
            if listing.get("version") != 1 or not is_json_array(actors):
                raise _Unreadable("trusted-actor list does not match its schema")
            humans = frozenset(
                a["id"]
                for a in map(json_object, actors)
                if a.get("kind") == "human" and isinstance(a.get("id"), int)
            )
            self._humans = humans
        return humans

    def _trusted_actor(self, kind: Any, actor_id: Any, login: Any, author: str) -> bool:
        """The one spec-author filter (resolve-pr.mjs `trusted` is its
        twin): a User on the trusted list's humans other than the PR author."""
        return (
            kind == "User"
            and actor_id in self._trusted_humans()
            and author != ""
            and str(login or "").casefold() != author.casefold()
        )

    def _spec_comments(self, comments: list[Any], author: str) -> set[tuple[Any, Any]]:
        """The trusted comments, by id and update time: written, and last
        edited if ever, by a trusted actor (`_trusted_actor`)."""

        def by(actor: Any) -> bool:
            actor = json_object(actor)
            return self._trusted_actor(
                actor.get("__typename"),
                actor.get("databaseId"),
                actor.get("login"),
                author,
            )

        return {
            (c.get("databaseId"), c.get("updatedAt"))
            for c in map(json_object, comments)
            if by(c.get("author"))
            and (c.get("lastEditedAt") is None or by(c.get("editor")))
        }

    def _recorded_comments(self, issue: dict[str, Any]) -> set[tuple[Any, Any]]:
        recorded = issue.get("spec_comments")
        if not is_json_array(recorded) or not all(
            is_json_object(c)
            and sorted(c) == ["id", "updated_at"]
            and isinstance(c["id"], int)
            and isinstance(c["updated_at"], str)
            for c in recorded
        ):
            raise _Unreadable(f"#{issue.get('number')}: no spec comment record")
        return {(c["id"], c["updated_at"]) for c in recorded}

    def _trusted_spec(self, record: dict[str, Any], author: str) -> bool:
        """Every linked issue was written, and its body last edited if ever,
        by a User on the trusted list's humans other than the PR author."""

        def trusted(issue: dict[str, Any], role: str) -> bool:
            return self._trusted_actor(
                issue.get(f"{role}_type"),
                issue.get(f"{role}_id"),
                issue.get(f"{role}_login"),
                author,
            )

        issues = [
            json_object(issue) for issue in json_array(record.get("linked_issues"))
        ]
        return bool(issues) and all(
            trusted(issue, "author")
            and (issue.get("last_edited_at") is None or trusted(issue, "editor"))
            for issue in issues
        )

    def _closing_issues(self, number: int) -> dict[Any, Any]:
        """The PR's closing issues in this repository now, each with its
        body's lastEditedAt, read as the resolver reads them
        (closingIssuesReferences, first 10)."""
        owner, _, name = self.repo.partition("/")
        payload = json_object(
            _read(
                ["api", "graphql", "-f", f"query={CLOSING_QUERY}"]
                + ["-f", f"o={owner}", "-f", f"r={name}", "-F", f"n={number}"],
                f"#{number} closing issues",
            )
        )
        refs = json_object(
            json_object(
                json_object(json_object(payload.get("data")).get("repository")).get(
                    "pullRequest"
                )
            ).get("closingIssuesReferences")
        )
        nodes = refs.get("nodes")
        if (
            payload.get("errors")
            or not is_json_array(nodes)
            or refs.get("totalCount") != len(nodes)
        ):
            raise _Unreadable(f"#{number}: the closing issues could not be read")
        live = {
            json_object(node).get("number"): json_object(node)
            for node in nodes
            if json_object(json_object(node).get("repository")).get("nameWithOwner")
            == self.repo
        }
        for issue in live.values():
            comments = json_object(issue.get("comments"))
            if not is_json_array(comments.get("nodes")) or comments.get(
                "totalCount"
            ) != len(comments["nodes"]):
                raise _Unreadable(
                    f"#{issue.get('number')}: its comments could not be read"
                )
        return live

    def _commits(self, number: int) -> set[str]:
        try:
            commits = postmerge._paginated(
                f"repos/{self.repo}/pulls/{number}/commits?per_page=100",
                f"#{number} commits",
            )
        except postmerge.PostMergeReadError as exc:
            raise _Unreadable(str(exc)) from exc
        if len(commits) >= COMMITS_CAP:
            raise _Unreadable(f"#{number} lists {len(commits)} commits, the API cap")
        return {str(c.get("sha")) for c in commits}

    def evidence(
        self, number: int, head: str, pr: dict[str, Any] | None = None
    ) -> Evidence:
        try:
            return self._evidence(number, head, pr)
        except (_Unreadable, postmerge.PostMergeReadError) as exc:
            return Evidence(UNREADABLE, head, (), 0, str(exc))

    def _evidence(self, number: int, head: str, pr: dict[str, Any] | None) -> Evidence:
        if pr is None:
            try:
                pr = merge_policy.pull_request(self.repo, number)
            except merge_policy.PolicyReadError as exc:
                raise _Unreadable(str(exc)) from exc
        # A record of no known shape has no creation time, which refuses.
        pr = json_object(pr)
        created = postmerge._time(pr.get("created_at"))
        now = self.now or datetime.now(UTC)
        if now - created > timedelta(days=TOO_OLD_DAYS):
            return Evidence(TOO_OLD, head, (), 0, f"created {created.isoformat()}")
        head_ref = str(json_object(pr.get("head")).get("ref") or "")
        author = str(json_object(pr.get("user")).get("login") or "")
        commits = self._commits(number) | {head}
        verdicts: list[Verdict] = []
        passes: list[tuple[int, str]] = []
        ignored = 0
        unreadable: str | None = None
        for item in map(json_object, self._listing()):
            name = str(item.get("name") or "")
            match = NAME_RE.fullmatch(name)
            if not match or item.get("expired") is not False:
                continue
            pr_n, sha, verdict = int(match[1]), match[2], match[3]
            run_id = json_object(item.get("workflow_run")).get("id")
            if not isinstance(run_id, int) or isinstance(run_id, bool):
                # The API always names the uploading run; without one the
                # artifact has no run record to authenticate it.
                ignored += 1
                continue
            tied = pr_n == number or sha in commits
            if verdict in PASSES:
                if pr_n != number or sha != head:
                    continue
                if self._run_state(run_id) == COUNTED:
                    verdicts.append(Verdict(sha, verdict, run_id))
                    passes.append((run_id, name))
                else:
                    ignored += 1
                continue
            state = self._run_state(run_id)
            if state == FOREIGN:
                ignored += 1
                continue
            if state == UNREAD:
                if tied:
                    unreadable = unreadable or f"run of {name}"
                else:
                    ignored += 1
                continue
            if not tied:
                try:
                    recorded = self._record(run_id, name).get("head_ref")
                except _Unreadable:
                    unreadable = unreadable or f"record of {name}"
                    continue
                if not head_ref or recorded != head_ref:
                    continue
            verdicts.append(Verdict(sha, verdict, run_id))
        fails = [v for v in verdicts if v.verdict == "fail"]
        refusal: str | None
        detail = unreadable
        if any(v.sha == head for v in fails):
            refusal = FAIL
        elif fails:
            refusal = EARLIER_FAIL
        elif unreadable:
            refusal = UNREADABLE
        elif passes:
            run_id, name = passes[0]
            record = self._record(run_id, name)
            if record.get("pr") != number or record.get("head_sha") != head:
                raise _Unreadable(
                    f"artifact {name} records another pull request or head"
                )
            recorded = record.get("linked_issues")
            if not is_json_array(recorded):
                raise _Unreadable(f"artifact {name} records no linked issues")
            issues = {json_object(i).get("number"): json_object(i) for i in recorded}
            live = self._closing_issues(number)
            # An edit after the judgment started is a spec the model never
            # read. An unparsable time refuses (PostMergeReadError).
            started = postmerge._time(self._started.get(run_id))
            if set(live) != set(issues) or any(
                (edited := node.get("lastEditedAt")) is not None
                and postmerge._time(edited) > started
                or self._spec_comments(
                    json_array(json_object(node.get("comments")).get("nodes")), author
                )
                != self._recorded_comments(issues[n])
                for n, node in live.items()
            ):
                refusal = SPEC_CHANGED
            elif self._trusted_spec(record, author):
                refusal = None
            else:
                refusal = UNTRUSTED_SPEC
        else:
            refusal = MISSING
        return Evidence(refusal, head, tuple(verdicts), ignored, detail)

    def queued_hold(self, number: int) -> str | None:
        """Why a queued entry must leave: no allowing verdict at its live
        head now. An unreadable pull request is a hold. A dependency
        manager's entry is the lane's Dependabot class, which pr-verify never
        judges, so it is not held here."""
        try:
            pr = merge_policy.pull_request(self.repo, number)
        except merge_policy.PolicyReadError:
            return UNREADABLE
        if is_dependency_author(str(json_object(pr.get("user")).get("login") or "")):
            return None
        head = str(json_object(pr.get("head")).get("sha"))
        return self.evidence(number, head, pr).refusal

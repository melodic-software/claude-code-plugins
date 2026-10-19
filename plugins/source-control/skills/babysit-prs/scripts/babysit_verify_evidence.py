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
- counted PASS or PASS-NOTES verdicts at the head of this pull request, each
  checked, so any one that refuses refuses (`verify:spec-changed` before
  `verify:untrusted-spec`, whatever the listing order): each is refused
  `verify:spec-changed` unless the pull request's closing issues now are the
  ones its verdict recorded, none was edited after its run started, and each
  issue's trusted comments (`_spec_comments`) are the recorded ones by id and
  update time; then allowed only when every linked issue it records was
  written, and last edited if ever, by a User on the trusted list's humans
  other than the pull request's author, else `verify:untrusted-spec`;
- otherwise `verify:missing`.

`verify:fail`, `verify:too-old`, `verify:earlier-fail`, `verify:spec-changed`
and `verify:untrusted-spec` need a human, who merges in person; a
`verify:fail` escalation quotes the newest head FAIL's summary
(`Reader.fail_summary`). Any read that fails refuses
(`verify:unreadable`). The repository's artifacts are listed once per
`Reader`, every page, and filtered on the name here: the API's name filter
matches whole names only, and a FAIL counts under any number and head.
pr-merge.yml builds one `Reader` per candidate gate run and names a file in
`LISTING_ENV`: a successful listing is saved there, and later candidates of
the run read it instead of paging again. No judgment uses a listing, saved
or in memory, begun more than `LISTING_MAX_AGE` before it: an older one is
read again and saved. A listing taken earlier in the run
can only lack later uploads, so a refusal on it stands; before the gate's own
candidate is allowed on it, babysit_merge.py calls `refresh()` and judges it
again on a listing of its own. A listing that got a 5xx or a fast network
error is read again after each of `LISTING_WAITS`, every read inside one gh
timeout in all; any other failure, a timeout, a 429 or a rate-limit 403
included, is not. A failed listing is never saved, and is kept as well, so one
outage refuses every entry of the gate run without paging again: it holds the
whole queue rather than merging blind.
"""

from __future__ import annotations

import contextlib
import json
import os
import re
import tempfile
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import babysit_merge_policy as merge_policy
import babysit_postmerge as postmerge
import babysit_run_cache as run_cache
from babysit_classify import is_dependency_author
from babysit_gh import (
    flatten_paginated_items,
    gh_http_status,
    gh_timeout_seconds,
    pull_request_commits_once,
)
from babysit_util import is_json_array, is_json_object, json_array, json_object

WORKFLOW_PATH = ".github/workflows/pr-verify.yml"
TRUSTED_ACTORS_PATH = ".github/standards/trusted-actors/trusted-actors.json"
TOKEN_ENV = "BABYSIT_VERIFY_GH_TOKEN"
LISTING_ENV = "BABYSIT_VERIFY_LISTING"
NAME_RE = re.compile(r"pr-verify-([1-9][0-9]*)-([0-9a-f]{40})-(pass|pass-notes|fail)")
PASSES = ("pass", "pass-notes")
# Artifacts last at most 90 days in this repository (the retention maximum,
# and the repository's setting), so a verdict on an older pull request may be
# gone. 80 leaves ten days of margin (judgment).
TOO_OLD_DAYS = 80
# `GET /pulls/{n}/commits` lists at most 250 commits.
COMMITS_CAP = 250
# The waits before the second and third listing reads (judgment).
LISTING_WAITS = (2.0, 4.0)
# The oldest listing any judgment uses, saved or in memory (see the bound).
LISTING_MAX_AGE = run_cache.MAX_AGE
# How gh reports a request that never got an HTTP response: its own
# "error connecting to <host>" for a failed lookup, else Go's net/http error.
NETWORK_ERRORS = (
    "error connecting to",
    "connection reset by peer",
    "connection refused",
    "i/o timeout",
    "tls handshake timeout",
    "unexpected eof",
)
FAIL = "verify:fail"
EARLIER_FAIL = "verify:earlier-fail"
MISSING = "verify:missing"
UNREADABLE = "verify:unreadable"
TOO_OLD = "verify:too-old"
UNTRUSTED_SPEC = "verify:untrusted-spec"
SPEC_CHANGED = "verify:spec-changed"
NEEDS_HUMAN = (FAIL, EARLIER_FAIL, TOO_OLD, UNTRUSTED_SPEC, SPEC_CHANGED)
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
# The run cache's section of run records, and the fields `_run_state` reads.
RUN_SECTION = "run-record"
RECORD_SECTION = "fail-head-ref"
# What earlier pr-merge runs read, copied into this run's cache by
# .github/scripts/pr-merge/carry-run-cache.mjs from a cache entry any job in
# the default branch's cache scope could have written. Each is used only
# where it counts a FAIL; any other answer is read from GitHub.
CARRIED_RUN_SECTION = "carried-run-record"
CARRIED_RECORD_SECTION = "carried-fail-head-ref"
CARRIED_ON_BRANCH = "carried-on-branch"
RUN_FIELDS = (
    "id",
    "path",
    "event",
    "head_branch",
    "head_sha",
    "repository",
    "head_repository",
    "status",
    "conclusion",
    "run_attempt",
    "run_started_at",
)


class _Unreadable(Exception):
    pass


class _Transient(_Unreadable):
    """A failed read that may succeed if repeated."""


class SummaryUnreadable(Exception):
    """`Reader.fail_summary` could not read the record, which is not the
    same as a record with nothing to quote."""


def _transient(detail: str) -> bool:
    """A 5xx, or a network error with no HTTP response. A rate limit is not:
    a fixed short wait outlasts neither a Retry-After nor an hourly reset, and
    more requests can extend a secondary limit."""
    status = gh_http_status(detail)
    if status is not None:
        return status >= 500
    return any(phrase in detail.casefold() for phrase in NETWORK_ERRORS)


def _listing_sleep(seconds: float) -> None:
    time.sleep(seconds)


def _listing_clock() -> float:
    return time.monotonic()


def _wall_clock() -> datetime:
    return datetime.now(UTC)


def _recent(fetched_at: datetime | None) -> bool:
    """A listing begun at most `LISTING_MAX_AGE` ago; a time with no zone, or
    one in the future, is not."""
    if fetched_at is None or fetched_at.tzinfo is None:
        return False
    return timedelta(0) <= _wall_clock() - fetched_at <= LISTING_MAX_AGE


def dependency_bot(user: Any) -> bool:
    """A REST user that is a Bot account with a dependency manager's login; a
    User named like one is not. resolve-pr.mjs `isDependencyManager` is its
    twin, and tests/test_verify_rules_sync.py compares them."""
    user = json_object(user)
    return user.get("type") == "Bot" and is_dependency_author(
        str(user.get("login") or "")
    )


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
    # The newest counted FAIL at the head: its run id and artifact name.
    head_fail: tuple[int, str] | None = None

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
            "headFail": (
                {"run": self.head_fail[0], "artifact": self.head_fail[1]}
                if self.head_fail
                else None
            ),
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
    # download) and the run heads' compares: pr-merge.yml passes the job's GITHUB_TOKEN, which holds
    # `actions: read`, while the lane token it runs gh with holds none.
    actions_token: str | None = field(
        default_factory=lambda: os.environ.get(TOKEN_ENV) or None
    )
    # The run's saved listing (`LISTING_ENV`), when pr-merge.yml names one.
    listing_path: str | None = field(
        default_factory=lambda: os.environ.get(LISTING_ENV) or None
    )
    _artifacts: list[dict[str, Any]] | None = None
    _fetched_at: datetime | None = None  # when `_artifacts` began to be read
    _saved: bool = False  # `_artifacts` came from `listing_path`
    _own: bool = False  # `refresh()` asked for a listing of this Reader's own
    _listing_error: str | None = None
    _runs: dict[int, str] = field(default_factory=dict)
    _started: dict[int, Any] = field(default_factory=dict)
    # Runs whose standing came from the run cache (`_run_state`).
    _shared_runs: set[int] = field(default_factory=set)
    _on_branch: dict[str, bool] = field(default_factory=dict)
    _records: dict[tuple[int, str], dict[str, Any]] = field(default_factory=dict)
    _humans: frozenset[int] | None = None
    _humans_at: datetime | None = None  # when `_humans` was read

    def _listing(self) -> list[dict[str, Any]]:
        """`_current_listing`, noting when it began to be read
        (`run_cache.note`)."""
        listing = self._current_listing()
        if self._fetched_at is not None:
            run_cache.note(self._fetched_at)
        return listing

    def _current_listing(self) -> list[dict[str, Any]]:
        """Every repository artifact, read at most `LISTING_MAX_AGE` before
        this judgment (from the run's saved listing when it is that recent): a
        failed read is kept too, so one outage refuses each later entry
        without paging again."""
        if self._listing_error is not None:
            raise _Unreadable(self._listing_error)
        if self._artifacts is not None and _recent(self._fetched_at):
            return self._artifacts
        saved = None if self._own else self._load_saved()
        if saved is not None:
            self._fetched_at, self._artifacts = saved
            self._saved = True
            return self._artifacts
        fetched_at = _wall_clock()
        try:
            listing = flatten_paginated_items(
                self._read_listing(), "repository artifacts", items_key="artifacts"
            )
        except (_Unreadable, RuntimeError) as exc:
            self._listing_error = str(exc)
            raise _Unreadable(self._listing_error) from exc
        self._artifacts, self._fetched_at = listing, fetched_at
        self._saved = self._own = False
        self._save(listing, fetched_at)
        return listing

    @property
    def saved(self) -> bool:
        """Whether the listing judged on was read from `listing_path`."""
        return self._saved

    def refresh(self) -> None:
        """Drop a saved listing: the next judgment pages the API itself (and
        saves that listing for the rest of the run)."""
        if self._saved:
            self._artifacts, self._saved, self._own = None, False, True

    def _load_saved(self) -> tuple[datetime, list[dict[str, Any]]] | None:
        """The run's saved listing and when it began to be read. A missing or
        malformed file, or one with no `fetchedAt` within `LISTING_MAX_AGE`,
        is none, so the listing is read from the API instead."""
        if not self.listing_path:
            return None
        try:
            saved = json_object(
                json.loads(Path(self.listing_path).read_text(encoding="utf-8"))
            )
            fetched_at = datetime.fromisoformat(saved["fetchedAt"])
        except (OSError, ValueError, KeyError, TypeError):
            return None
        listing = saved.get("artifacts")
        if (
            not _recent(fetched_at)
            or not is_json_array(listing)
            or not all(map(is_json_object, listing))
        ):
            return None
        return fetched_at, listing

    def _save(self, listing: list[dict[str, Any]], fetched_at: datetime) -> None:
        """Best effort: a failed write leaves the next candidate to list."""
        if not self.listing_path:
            return
        path = Path(self.listing_path)
        tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
        payload = {"fetchedAt": fetched_at.isoformat(), "artifacts": listing}
        with contextlib.suppress(OSError):
            tmp.write_text(json.dumps(payload), encoding="utf-8")
            os.replace(tmp, path)

    def _read_listing(self) -> Any:
        """The listing payload, read again after a 5xx or a fast network
        error while time is left: every read and wait fits in the one gh
        timeout a single read would get, so a retry adds no time to the run's
        worst case."""
        args = [
            "api",
            f"repos/{self.repo}/actions/artifacts?per_page=100",
            "--paginate",
            "--slurp",
        ]
        deadline = _listing_clock() + gh_timeout_seconds()
        timeout: float | None = None
        for wait in LISTING_WAITS:
            try:
                return self._actions(args, "repository artifacts", timeout)
            except _Transient:
                if deadline - _listing_clock() - wait <= 0:
                    raise
                _listing_sleep(wait)
                # Recomputed after the sleep, which may return late.
                timeout = deadline - _listing_clock()
                if timeout <= 0:
                    raise
        return self._actions(args, "repository artifacts", timeout)

    def _env(self) -> dict[str, str] | None:
        return {"GH_TOKEN": self.actions_token} if self.actions_token else None

    def _actions(
        self, args: list[str], label: str, timeout_seconds: float | None = None
    ) -> Any:
        """A read the Actions API answers, under the Actions token when set;
        `None` keeps gh's default timeout."""
        try:
            proc = postmerge.gh_capture(
                args, timeout_seconds=timeout_seconds, env_overrides=self._env()
            )
        except (RuntimeError, ValueError, OSError) as exc:
            # A timeout, or no gh on PATH: neither is read again.
            raise _Unreadable(f"{label}: {exc}") from exc
        if proc.returncode != 0:
            detail = f"{label}: {(proc.stderr or '').strip() or proc.returncode}"
            raise (_Transient if _transient(detail) else _Unreadable)(detail)
        try:
            return json.loads(proc.stdout) if proc.stdout.strip() else None
        except ValueError as exc:
            raise _Unreadable(f"{label}: {exc}") from exc

    def _contains(self, sha: str, *, shared: bool = False) -> bool:
        """Whether the branch holds `sha`, read under the Actions token (a
        contents read). A yes stays true while the branch only moves forward
        (main's ruleset forbids force pushes), so the run shares it; a no is
        read again by each gate process. A yes an earlier run found
        (`CARRIED_ON_BRANCH`) serves a FAIL's run only (`shared`), where it
        can only count the FAIL."""
        if sha not in self._on_branch:
            key = f"{self.repo}|{sha}...{self.branch}"
            if run_cache.get("on-branch", key, None) is True:
                self._on_branch[sha] = True
                return True
            if shared and run_cache.get(CARRIED_ON_BRANCH, key, None) is True:
                return True
            compare = json_object(
                self._actions(
                    ["api", f"repos/{self.repo}/compare/{sha}...{self.branch}"],
                    f"compare {sha[:12]}...{self.branch}",
                )
            )
            self._on_branch[sha] = compare.get("status") in ("ahead", "identical")
            if self._on_branch[sha]:
                run_cache.put("on-branch", key, True)
        return self._on_branch[sha]

    def _run_state(self, run_id: int, *, shared: bool = False) -> str:
        """The run's standing. A FAIL's run (`shared`) may be judged on a
        record another gate process of the run read, however long ago, or
        on one an earlier run carried in when it shows origin: a
        FAIL counts whether its run is origin or counted, and origin rests
        only on fields a re-run keeps (id, path, event, branch, repositories,
        head) plus a live branch check, never on status, conclusion or
        attempt, so a stale record cannot turn a FAIL away. A PASS needs a
        completed success, which a re-run can undo, so its run is read by
        this process, never taken from a FAIL's judgment."""
        if run_id in self._runs and (shared or run_id not in self._shared_runs):
            return self._runs[run_id]
        key = f"{self.repo}|{run_id}"
        record = run_cache.get(RUN_SECTION, key, None) if shared else None
        cached = is_json_object(record)
        origin: bool | None = None
        if shared and not cached:
            # A carried record counts the FAIL when it shows origin; any
            # other answer from it could turn the FAIL away, so the run is
            # read instead.
            carried = run_cache.get(CARRIED_RUN_SECTION, key, None)
            if is_json_object(carried):
                try:
                    if self._origin(carried, run_id, shared=True):
                        record, cached, origin = carried, True, True
                except _Unreadable:
                    pass
        try:
            if not cached:
                record = json_object(
                    self._actions(
                        ["api", f"repos/{self.repo}/actions/runs/{run_id}"],
                        f"run {run_id}",
                    )
                )
            if origin is None:
                origin = self._origin(record, run_id, shared=shared)
        except _Unreadable:
            self._shared_runs.discard(run_id)
            self._runs[run_id] = UNREAD
            return UNREAD
        if cached or shared:
            self._shared_runs.add(run_id)
        else:
            self._shared_runs.discard(run_id)
        if not cached:
            self._started[run_id] = record.get("run_started_at")
            run_cache.put(RUN_SECTION, key, {k: record.get(k) for k in RUN_FIELDS})
        done = (
            record.get("status") == "completed"
            and record.get("conclusion") == "success"
        )
        self._runs[run_id] = FOREIGN if not origin else COUNTED if done else ORIGIN
        return self._runs[run_id]

    def _origin(self, record: dict[str, Any], run_id: int, *, shared: bool) -> bool:
        """Whether `record` names a run of the verifier on the branch of this
        repository whose head the branch holds."""
        head = record.get("head_sha")
        return (
            record.get("id") == run_id
            and record.get("path") == WORKFLOW_PATH
            and record.get("event") == "workflow_run"
            and record.get("head_branch") == self.branch
            and json_object(record.get("repository")).get("full_name") == self.repo
            and json_object(record.get("head_repository")).get("full_name") == self.repo
            and isinstance(head, str)
            and merge_policy.SHA_RE.fullmatch(head) is not None
            and self._contains(head, shared=shared)
        )

    def _head_ref(self, run_id: int, name: str, artifact_id: Any, head_ref: str) -> Any:
        """The head ref an untied FAIL's verdict.json records, shared by the
        run's gate processes under the artifact's id: an id names contents
        that never change (an overwrite uploads a new id), and a FAIL whose
        artifact has since gone still refuses. An artifact with no id is not
        shared."""
        shared = isinstance(artifact_id, int) and not isinstance(artifact_id, bool)
        key = f"{self.repo}|{artifact_id}"
        dated = run_cache.get_dated(RECORD_SECTION, key, None) if shared else None
        if dated is not None and is_json_object(dated[0]):
            return dated[0].get("head_ref")
        # A carried head ref ties the FAIL to this PR; one naming another
        # ref could untie it, so the record is read instead.
        carried = run_cache.get(CARRIED_RECORD_SECTION, key, None) if shared else None
        if head_ref and is_json_object(carried) and carried.get("head_ref") == head_ref:
            return head_ref
        record = self._record(run_id, name)
        if shared:
            run_cache.put(RECORD_SECTION, key, {"head_ref": record.get("head_ref")})
        return record.get("head_ref")

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
        """The trusted list's human ids at the branch, shared by the run's
        gate processes for `run_cache.MAX_AGE`; each answer notes when it
        was read (`run_cache.note`)."""
        key = f"{self.repo}@{self.branch}"
        if self._humans is None:
            shared = run_cache.get_dated("trusted-humans", key, run_cache.MAX_AGE)
            if shared is not None and is_json_array(shared[0]):
                self._humans = frozenset(i for i in shared[0] if type(i) is int)
                self._humans_at = shared[1]
        humans = self._humans
        if humans is None:
            self._humans_at = run_cache.now()
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
            run_cache.put("trusted-humans", key, sorted(humans), self._humans_at)
        if self._humans_at is not None:
            run_cache.note(self._humans_at)
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

    def _commits(self, number: int, head: str) -> set[str]:
        try:
            commits = pull_request_commits_once(
                self.repo,
                number,
                head,
                lambda: postmerge._paginated(
                    f"repos/{self.repo}/pulls/{number}/commits?per_page=100",
                    f"#{number} commits",
                ),
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
        commits = self._commits(number, head) | {head}
        verdicts: list[Verdict] = []
        passes: list[tuple[int, str]] = []
        head_fails: list[tuple[int, str]] = []
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
            state = self._run_state(run_id, shared=True)
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
                    recorded = self._head_ref(run_id, name, item.get("id"), head_ref)
                except _Unreadable:
                    unreadable = unreadable or f"record of {name}"
                    continue
                if not head_ref or recorded != head_ref:
                    continue
            verdicts.append(Verdict(sha, verdict, run_id))
            if sha == head and verdict == "fail":
                head_fails.append((run_id, name))
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
            # Every pass at the head must allow, so listing order decides
            # nothing; any unreadable one refuses (`_Unreadable`).
            live = self._closing_issues(number)
            refusals = {
                self._pass_refusal(run_id, name, number, head, author, live)
                for run_id, name in passes
            }
            refusal = next(
                (r for r in (SPEC_CHANGED, UNTRUSTED_SPEC) if r in refusals), None
            )
        else:
            refusal = MISSING
        return Evidence(
            refusal,
            head,
            tuple(verdicts),
            ignored,
            detail,
            max(head_fails) if refusal == FAIL else None,
        )

    def fail_summary(
        self, run_id: int, name: str, number: int, head: str
    ) -> str | None:
        """The `summary` a FAIL artifact's verdict.json records for pull
        request `number` at `head`, or None when it records another pull
        request, head or verdict. Raises `SummaryUnreadable` when it cannot be
        read. Untrusted model text: the caller frames it as data."""
        try:
            record = self._record(run_id, name)
        except _Unreadable as exc:
            raise SummaryUnreadable(str(exc)) from exc
        summary = record.get("summary")
        if (
            record.get("pr") != number
            or record.get("head_sha") != head
            or record.get("verdict") != "fail"
            or not isinstance(summary, str)
        ):
            return None
        return summary

    def _pass_refusal(
        self,
        run_id: int,
        name: str,
        number: int,
        head: str,
        author: str,
        live: dict[Any, Any],
    ) -> str | None:
        """One counted pass at the head against the live closing issues."""
        record = self._record(run_id, name)
        if record.get("pr") != number or record.get("head_sha") != head:
            raise _Unreadable(f"artifact {name} records another pull request or head")
        recorded = record.get("linked_issues")
        if not is_json_array(recorded):
            raise _Unreadable(f"artifact {name} records no linked issues")
        issues = {json_object(i).get("number"): json_object(i) for i in recorded}
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
            return SPEC_CHANGED
        return None if self._trusted_spec(record, author) else UNTRUSTED_SPEC

    def queued_hold(self, number: int) -> str | None:
        """Why a queued entry must leave: no allowing verdict at its live
        head now. An unreadable pull request is a hold. A dependency
        manager's entry is the lane's Dependabot class, which pr-verify never
        judges, so it is not held here."""
        try:
            pr = merge_policy.pull_request(self.repo, number)
        except merge_policy.PolicyReadError:
            return UNREADABLE
        if dependency_bot(pr.get("user")):
            return None
        head = str(json_object(pr.get("head")).get("sha"))
        return self.evidence(number, head, pr).refusal

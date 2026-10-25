#!/usr/bin/env python3
"""Verifier verdicts for the pr-merge lane.

`.github/workflows/pr-verify.yml` judges each pull request head that passes
PR Require Checks and uploads an artifact named
`pr-verify-<pr>-<head-sha>-<pass|pass-notes|fail>-<ref-digest>` holding
`verdict.json`, the last part `head_ref_digest` of the head branch the file
records; a verdict uploaded before the digest was added has none. Only steps
of a run can upload its artifacts, so the run record authenticates the name. An artifact's run is of verifier origin when it is that file, event
`workflow_run`, on the branch, in this repository with a head in this
repository, and its head SHA is a full SHA on the branch. A FAIL counts from
any run of verifier origin, whatever its status or conclusion, since the
upload comes before the run's later steps; a PASS or PASS-NOTES counts only
from a completed, successful one. Any other artifact is ignored.

`Reader.evidence` decides one pull request at its vetted head, in this order:

- the pull request was created more than `TOO_OLD_DAYS` ago:
  `verify:too-old`, since a verdict may already have expired;
- counted FAILs at `max_fails` or more distinct heads of this pull request
  (tied as in the item after next): `verify:repeated-fail`, whatever a pass
  says, a FAIL at the head included. Before a FAIL at the head or a pass
  decides, FAILs of other pull requests in this repository, open or closed, that close one of its
  issues (its closing issues, or its `Refs:` issue) count too, at their own
  heads, and so does every FAIL whose name carries one of those issues, a
  `Refs:` pull request's FAILs among them (a FAIL among them whose run cannot
  be read is `verify:unreadable`);
- a counted FAIL at the head, under any pull request number: `verify:fail`;
- a counted FAIL at another head of this pull request: its number, one of its
  commits (`pulls/<n>/commits`), or a verdict recording its head branch (read
  from the name's digest, else from its verdict.json):
  `verify:earlier-fail`. Counted PASS or PASS-NOTES verdicts at the
  head whose runs were all created after every such FAIL's run (each
  creation time read fresh from GitHub, which a re-attempt keeps; a missing
  one keeps the refusal) clear it when the
  pull request's own change at the head differs from its change at every
  FAILed head (`change_digest`: a head that only merges the branch or adds
  an empty commit carries the FAIL forward, and a diff that holds no change
  or answers 404 keeps the refusal), and those passes decide, as below. A
  FAILed head of the same change is cleared too when every counted FAIL at
  that head records `spec_kind` `refs` for this pull request and every
  counted pass at the head records `spec_kind` `closes` with exactly the
  linked issues each FAIL records (`_wider_pass`): a `closes` pass is judged
  against the whole spec, which the `refs` slice that failed is part of. The
  reverse, a key that is missing or holds anything else, linked issues that
  differ or cannot be read, and a FAIL record that cannot be read or records
  another pull request, head or verdict keep `verify:earlier-fail`. Any
  other failed read of a run time or a diff refuses as the next item does;
- a FAIL-named artifact tied to this pull request by number or SHA whose run
  cannot be read: `verify:unreadable`. An untied FAIL whose run cannot be read
  is ignored; an untied FAIL whose run is readable and of verifier origin but
  whose name carries no digest, whose id the head-ref map (below) lacks, and
  whose recorded head branch (its verdict.json) cannot be read is
  `verify:unreadable`, so one such artifact blocks every pull request until it
  is readable, expires or is deleted;
- counted PASS or PASS-NOTES verdicts at the head of this pull request, those
  of the run that started last (`_newest`; every one when a start time is
  missing), each checked, so any one that refuses refuses
  (`verify:spec-changed` before `verify:untrusted-spec`, whatever the listing
  order): each is refused
  `verify:spec-changed` unless the pull request's closing issues now are the
  ones its verdict recorded, none was edited after its run started, and each
  issue's trusted comments (`_spec_comments`) are the recorded ones by id and
  update time; then allowed when it records no issue and `intent`
  `pull-request` (the title and body were the spec), else only when every
  linked issue it records was
  written, and last edited if ever, by a User on the trusted list's humans
  (the pull request's author among them), or is a sub-issue the lanes App
  filed in a size split whose body counts as its parent's text
  (`split_child_body`), else `verify:untrusted-spec`. A
  pass refused `verify:spec-changed` for an issue edit or a spec comment
  added or edited is judged again at the same head: resolve-pr.mjs judges a
  head whose passes all predate the spec's last change, and the lost-run
  reconciler re-runs the head's checks to start that judgment. A changed
  closing set or a removed spec comment leaves no time to compare, and waits
  for a person;
- otherwise `verify:missing`.

`verify:too-old`, `verify:repeated-fail`, `verify:spec-changed` and
`verify:untrusted-spec` need a human, who merges in person; a
`verify:repeated-fail` escalation quotes the newest head FAIL's summary
(`Reader.fail_summary`). A `verify:fail` or `verify:earlier-fail` only waits:
pr-feedback-dispatch.yml posts a FAIL's notes on the pull request as review
comments for an address-feedback round, whose push gives a head the verifier
judges again. Any read that fails refuses
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

An untied FAIL's recorded head branch is read from the head-ref map pr-merge.yml
names in `HEAD_REFS_ENV` before it is downloaded: artifact id to the head_ref
an earlier run read from that artifact's verdict.json, kept as the artifact of
a scheduled or hand-started run of main's pr-merge.yml, which only that run's
steps can upload (.github/scripts/pr-merge/head-ref-map.mjs). An entry ties or
unties the FAIL as the download would; a missing or malformed map is no map,
and the FAIL is downloaded.

`python3 babysit_verify_evidence.py evidence --repo R [--max-fails N] <pr>
<head>` prints `Evidence.report()` for one pull request as one JSON line;
.github/scripts/pr-merge/enable-auto-merge.mjs arms native auto-merge only on
its null `refusal` at the head it read.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import json
import os
import re
import sys
import tempfile
import time
import zipfile
from collections.abc import Callable
from dataclasses import dataclass, field, replace
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
HEAD_REFS_ENV = "BABYSIT_VERIFY_HEAD_REFS"
# The head-ref map's version and its keys' shape, an artifact id
# (head-ref-map.mjs writes both).
HEAD_REFS_VERSION = 1
ARTIFACT_ID_RE = re.compile(r"[1-9][0-9]{0,15}")
# A verdict's name, then optionally the head-ref digest, then, for a FAIL
# only, optionally `-i` and the numbers of the issues the verdict records,
# ascending, each once, joined by dots (`NAMED_ISSUES_MAX` at most), so one
# verdict has one name. write-verdict.mjs writes the issues after the readers
# accept them. `verdict_name` applies the order; NAME_RE alone does not.
NAMED_ISSUES_MAX = 10
NAME_RE = re.compile(
    r"pr-verify-([1-9][0-9]{0,9})-([0-9a-f]{40})-"
    r"(pass(?:-notes)?(?=(?:-[0-9a-f]{16})?\Z)|fail)"
    r"(?:-([0-9a-f]{16}))?"
    rf"(?:-i([1-9][0-9]{{0,9}}(?:\.[1-9][0-9]{{0,9}}){{0,{NAMED_ISSUES_MAX - 1}}}))?"
)
# The head-ref digest in a verdict's name: the first HEAD_REF_DIGEST_HEX hex
# digits of the SHA-256 of the head branch's UTF-8 bytes. write-verdict.mjs
# `headRefDigest` is its twin, and tests/test_verify_rules_sync.py compares
# them. Equal branches always give equal digests, so a collision can only tie
# a FAIL to a branch it did not judge: it holds, never clears.
HEAD_REF_DIGEST_HEX = 16


def named_issues(match: re.Match[str]) -> frozenset[int]:
    """The issue numbers a `NAME_RE` match names; none for an older name."""
    return frozenset(int(n) for n in match[5].split(".")) if match[5] else frozenset()


# The longest name the grammar allows: `pr-verify-` (10), a 10-digit number
# and `-` (11), the SHA (40), `-fail` (5), `-` and the digest (17), `-i` (2),
# then 10 issues of 10 digits and 9 dots (109).
NAME_MAX = 10 + 11 + 40 + 5 + 17 + 2 + NAMED_ISSUES_MAX * 10 + NAMED_ISSUES_MAX - 1
# What starts like a FAIL's name, with any digits for the number (leading
# zeros and more than 10 included); one that is not a verdict name is held
# (`Reader._evidence`), never skipped.
FAIL_PREFIX_RE = re.compile(r"pr-verify-([0-9]+)-([0-9a-f]{40})-fail")


def verdict_name(name: str) -> re.Match[str] | None:
    """`NAME_RE`'s full match of `name`, when it is at most `NAME_MAX` long
    and its issues, if any, are ascending and each listed once; else None,
    as for any other name."""
    match = NAME_RE.fullmatch(name) if len(name) <= NAME_MAX else None
    if match is None or not match[5]:
        return match
    numbers = [int(n) for n in match[5].split(".")]
    return match if all(a < b for a, b in zip(numbers, numbers[1:])) else None


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
REPEATED_FAIL = "verify:repeated-fail"
MISSING = "verify:missing"
UNREADABLE = "verify:unreadable"
TOO_OLD = "verify:too-old"
UNTRUSTED_SPEC = "verify:untrusted-spec"
SPEC_CHANGED = "verify:spec-changed"
# `evidence --lane-link`: the pull request's issue link is not one the
# pr-merge lane takes (`Reader.link_refusal`), so no verdict is read.
INELIGIBLE = "verify:ineligible"
# A verdict's `intent` when its pull request closed no issue in this
# repository: the title and body were the spec (write-verdict.mjs).
INTENT_PULL_REQUEST = "pull-request"
NEEDS_HUMAN = (
    REPEATED_FAIL,
    TOO_OLD,
    UNTRUSTED_SPEC,
    SPEC_CHANGED,
)
ISSUE_FIELDS = (
    "number lastEditedAt repository{nameWithOwner} "
    "labels(first:100){totalCount nodes{name}} "
    "comments(first:100){totalCount nodes{databaseId updatedAt lastEditedAt "
    "author{...actor} editor{...actor}}} "
    "closedByPullRequestsReferences(first:50,includeClosedPrs:true){totalCount "
    "nodes{number repository{nameWithOwner}}}"
)
# The issue parts `_closing_issues` reads whole: a cut list refuses.
ISSUE_LISTS = ("comments", "closedByPullRequestsReferences")
ACTOR_FRAGMENT = (
    "fragment actor on Actor{__typename login "
    "... on User{databaseId} ... on Bot{databaseId}}"
)
CLOSING_QUERY = (
    "query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){"
    "pullRequest(number:$n){body closingIssuesReferences(first:10){totalCount "
    f"nodes{{{ISSUE_FIELDS}}}}}}}}}}}{ACTOR_FRAGMENT}"
)
# The one issue a `Refs:` line names, when the pull request closes none, and
# the key `_closing_issues` marks it with.
REFS_MARK = "refsLink"
REFS_QUERY = (
    "query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){"
    f"issueOrPullRequest(number:$n){{__typename ... on Issue{{{ISSUE_FIELDS}}}}}}}}}"
    f"{ACTOR_FRAGMENT}"
)
# A size split's sub-issue, its native parent and the parent's comments, as
# resolve-pr.mjs PARENT_QUERY reads them: one read per sub-issue judged.
SPLIT_CHILD_QUERY = (
    "query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){"
    "issue(number:$n){body lastEditedAt author{...actor} editor{...actor} "
    "parent{number repository{nameWithOwner} body lastEditedAt author{...actor} "
    "editor{...actor} comments(first:100){totalCount nodes{databaseId createdAt "
    "updatedAt body lastEditedAt author{...actor} editor{...actor}}}}}}}"
    f"{ACTOR_FRAGMENT}"
)
# Admission's rules, whose `task-list` is the prefix a split copies by.
ADMISSION_RULES_PATH = ".github/actions/resolve-config/admission-rules.json"
# admit.mjs REFINE_MARKER, SPLIT_CHILD_MARKER, the part line and SOURCE.
REFINE_MARKER = "<!-- intake-triage refinement -->"
SPLIT_CHILD_MARKER = "<!-- intake-triage size-split child -->"
SPLIT_PART_RE = re.compile(r"Part ([1-9][0-9]?) of ([1-9][0-9]?) of #")
SPLIT_SOURCE_RE = re.compile(
    r"<!-- size-split refinement=([1-9][0-9]{0,15}) updated_at=([0-9A-Za-z:.+-]{1,40}) -->"
)
# What JavaScript's trimStart strips: WhiteSpace and LineTerminator.
JS_SPACE = "\t\n\v\f\r                  　﻿"


def split_child_header(
    parent: int, part: int, parts: int, source: tuple[int, str] | None = None
) -> str:
    """admit.mjs splitChildHeader: the fixed header of part `part` of
    `parts` a size split files from issue `parent`, with admit.mjs
    splitSourceLine when `source` (id, updated_at) is given."""
    also = " and intake's refinement comment on it" if source else ""
    rows = [
        SPLIT_CHILD_MARKER,
        f"Part {part} of {parts} of #{parent}, split at intake (owner Q93). "
        f"The done-when below is copied from #{parent}{also} as written.",
    ]
    if source:
        rows.append(
            f"<!-- size-split refinement={source[0]} updated_at={source[1]} -->"
        )
    return "\n".join([*rows, "", "## Done when", ""])


def ticked_forms(line: str, task_list: str) -> list[str]:
    """admit.mjs tickedForms: `line`, a task-list line, with its box ticked,
    the one `[ ]` in `task_list` written `[x]` or `[X]`, indent and text
    unchanged. None when `task_list` does not hold exactly one `[ ]`."""
    if task_list.count("[ ]") != 1:
        return []
    rest = line.lstrip(JS_SPACE)
    indent = line[: len(line) - len(rest)]
    text = rest[len(task_list) :]
    return [indent + task_list.replace("[ ]", box, 1) + text for box in ("[x]", "[X]")]


def split_child_body(
    issue: Any, repo: str, humans: frozenset[int], app_id: int | None, task_list: Any
) -> str | None:
    """The body of `issue` (as `SPLIT_CHILD_QUERY` reads it) when it counts
    as the text a size split copied into it, else None: the split-child trust
    rule, whose one home is admit.mjs splitChildBody, read the way
    resolve-pr.mjs reads it (a parent in this repository with every comment
    read). The lanes App (`app_id`) wrote it, a listed human filed its native
    parent, and it opens with `split_child_header` for that parent. A header
    with a source line names a refinement comment, which must still be the
    lanes App's newest refinement on the parent, unedited, on a parent body
    a listed human wrote, its updated_at its created_at or the recorded one;
    otherwise the body counts nothing, whoever edited it since. Every line
    after the header is one of the allowed lines: the parent's trusted
    task-list lines (a line of its listed-human text starting, after leading
    space, with `task_list`, admission's `task-list`) and, under a source
    line, that refinement's task-list lines, never its other lines. Either
    nobody edited the body, or a listed human last edited it and a line may
    also be an allowed line with its box ticked (`ticked_forms`): GitHub
    names only the last editor, so that edit vouches for ticked boxes, never
    for other text. A missing or empty `task_list` counts nothing. Pure.
    split-child.vectors.json holds its cases."""
    issue = json_object(issue)
    parent = json_object(issue.get("parent"))
    author = json_object(issue.get("author"))
    comments = json_object(parent.get("comments"))
    nodes = comments.get("nodes")
    number = parent.get("number")
    body = issue.get("body")
    if (
        not isinstance(task_list, str)
        or not task_list
        or type(app_id) is not int
        or author.get("__typename") != "Bot"
        or type(author.get("databaseId")) is not int
        or author["databaseId"] != app_id
        or type(number) is not int
        or json_object(parent.get("repository")).get("nameWithOwner") != repo
        or not is_json_array(nodes)
        or comments.get("totalCount") != len(nodes)
        or not isinstance(body, str)
    ):
        return None
    nodes = [json_object(node) for node in nodes]

    def human(actor: Any) -> bool:
        actor = json_object(actor)
        return (
            actor.get("__typename") == "User"
            and type(actor.get("databaseId")) is int
            and actor["databaseId"] in humans
        )

    def written(item: dict[str, Any]) -> bool:
        return human(item.get("author")) and (
            item.get("lastEditedAt") is None or human(item.get("editor"))
        )

    def task_lines(item: dict[str, Any]) -> list[str]:
        return [
            line
            for line in str(item.get("body") or "").split("\n")
            if line.lstrip(JS_SPACE).startswith(task_list)
        ]

    edited = issue.get("lastEditedAt") is not None
    if not human(parent.get("author")) or (edited and not human(issue.get("editor"))):
        return None
    rows = body.split("\n")
    part = SPLIT_PART_RE.match(rows[1]) if len(rows) > 1 else None
    if part is None:
        return None
    tag = SPLIT_SOURCE_RE.fullmatch(rows[2]) if len(rows) > 2 else None
    # admit.mjs reads the id as a Number and writes it back into the header,
    # so only an id a double holds exactly can match.
    source = (
        (int(tag[1]), tag[2]) if tag and int(float(tag[1])) == int(tag[1]) else None
    )
    header = f"{split_child_header(number, int(part[1]), int(part[2]), source)}\n"
    if not body.startswith(header):
        return None
    refinement: list[str] = []
    if source is not None:
        # admit.mjs countedRefinement: the newest refinement, never an older
        # one, only while unedited and on a parent body a listed human wrote.
        newest = next(
            (
                c
                for c in reversed(nodes)
                if json_object(c.get("author")).get("__typename") == "Bot"
                and json_object(c.get("author")).get("databaseId") == app_id
                and str(c.get("body") or "").startswith(REFINE_MARKER)
            ),
            None,
        )
        if (
            newest is None
            or newest.get("lastEditedAt") is not None
            or not written(parent)
        ):
            return None
        updated = newest.get("updatedAt")
        if (
            type(newest.get("databaseId")) is not int
            or newest["databaseId"] != source[0]
            or not isinstance(updated, str)
            or updated not in (newest.get("createdAt"), source[1])
        ):
            return None
        refinement = task_lines(newest)
    # admit.mjs trustedTaskLines, then the refinement's task-list lines.
    exact = {
        line for item in (parent, *nodes) if written(item) for line in task_lines(item)
    }
    exact.update(refinement)
    allowed = (
        exact | {form for line in exact for form in ticked_forms(line, task_list)}
        if edited
        else exact
    )
    lines = body[len(header) :].split("\n")
    return body if all(line in allowed for line in lines) else None


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
# Untied FAIL records a gate process of the run could not read, by artifact
# id, so later candidates refuse on them without downloading again
# (`Reader._head_ref`). Only a refusal is shared: a read that might succeed is
# never made to allow. carry-run-cache.mjs drops the section.
UNREAD_RECORD_SECTION = "unreadable-fail-head-ref"
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
    # The newest counted FAIL at the head, for `verify:fail` and
    # `verify:repeated-fail`: its run id and artifact name.
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


DIFF_HEADER = re.compile(r"diff --git a/(.*) b/(.*)")
MODE_LINES = ("old mode ", "new mode ", "new file mode ", "deleted file mode ")


def change_digest(diff: str) -> str | None:
    """A sha256 digest of the changed lines a unified diff holds, so context
    and line numbers (which a base merge moves or edits) leave it alone.
    Each file contributes its path, the old to new path of a rename, its
    mode lines, its binary-change line, and its `-` and `+` lines with all
    whitespace removed and the marker kept, blank ones dropped; a trailing
    carriage return is dropped from every line. Lines within a file and files by
    path are sorted, so reordering hunks or files changes nothing. None for
    a diff with no change, or one that is not a git diff."""
    files: dict[str, list[str]] = {}
    lines: list[str] | None = None
    in_hunk = False
    for line in diff.split("\n"):
        line = line.removesuffix("\r")
        header = DIFF_HEADER.fullmatch(line)
        if header:
            lines = files.setdefault(header[2], [])
            in_hunk = False
        elif lines is None:
            if line.strip():
                return None
        elif line.startswith("@@"):
            in_hunk = True
        elif in_hunk:
            # A blank line, added or removed, changes nothing a re-roll
            # could not add for free.
            if line[:1] in ("-", "+") and (content := "".join(line[1:].split())):
                lines.append(line[0] + content)
        elif line.startswith("rename from "):
            lines.append("rename " + line.removeprefix("rename from "))
        elif line.startswith("rename to "):
            lines.append("rename to " + line.removeprefix("rename to "))
        elif line.startswith(MODE_LINES) or (
            line.startswith("Binary files ") and line.endswith(" differ")
        ):
            lines.append(line)
    changed = sorted((path, sorted(found)) for path, found in files.items() if found)
    if not changed:
        return None
    return hashlib.sha256(json.dumps(changed).encode("utf-8")).hexdigest()


def head_ref_digest(ref: str) -> str:
    """The digest of `ref` that a verdict's artifact name carries."""
    return hashlib.sha256(ref.encode("utf-8")).hexdigest()[:HEAD_REF_DIGEST_HEX]


def _issue_numbers(record: dict[str, Any]) -> frozenset[int]:
    """The issue numbers a verdict's `linked_issues` records; raises
    `_Unreadable` for a list that is missing or empty, or for an entry with
    no integer number."""
    issues = record.get("linked_issues")
    if not is_json_array(issues) or not issues:
        raise _Unreadable("verdict records no linked issues")
    numbers = [json_object(i).get("number") for i in issues]
    if not all(isinstance(n, int) and not isinstance(n, bool) for n in numbers):
        raise _Unreadable("verdict records a linked issue with no number")
    return frozenset(numbers)


def _is_id(value: Any, run_id: int) -> bool:
    """`value` is the integer `run_id`; `True` equals 1 but is no id."""
    return type(value) is int and value == run_id


def _is_artifact_id(value: Any) -> bool:
    """An artifact id as the listing gives it: an integer, never a bool."""
    return isinstance(value, int) and not isinstance(value, bool)


def load_head_refs(path: str | None, repo: str) -> dict[int, str]:
    """The head-ref map at `path` for `repo`, by artifact id. A missing or
    unreadable file, another version or repository, or any entry of another
    shape is no map at all, so every untied FAIL is downloaded."""
    if not path:
        return {}
    try:
        data = json_object(json.loads(Path(path).read_text(encoding="utf-8")))
    except (OSError, ValueError):
        return {}
    refs = data.get("head_refs")
    if (
        data.get("version") != HEAD_REFS_VERSION
        or data.get("repo") != repo
        or not is_json_object(refs)
        or not all(
            ARTIFACT_ID_RE.fullmatch(k) and isinstance(v, str) for k, v in refs.items()
        )
    ):
        return {}
    return {int(k): v for k, v in refs.items()}


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
    # The head-ref map (`HEAD_REFS_ENV`), when pr-merge.yml names one.
    head_refs_path: str | None = field(
        default_factory=lambda: os.environ.get(HEAD_REFS_ENV) or None
    )
    # `merge.max-verify-fails`: FAILed heads at which a pass no longer clears.
    max_fails: int = merge_policy.MAX_VERIFY_FAILS
    # `merge.agent-identity`, the lanes App's login: its trusted-list id is
    # the author a size split's sub-issue needs (`_split_child`); unset, no
    # sub-issue counts.
    agent_identity: str | None = None
    _artifacts: list[dict[str, Any]] | None = None
    _fetched_at: datetime | None = None  # when `_artifacts` began to be read
    _saved: bool = False  # `_artifacts` came from `listing_path`
    _own: bool = False  # `refresh()` asked for a listing of this Reader's own
    _listing_error: str | None = None
    _runs: dict[int, str] = field(default_factory=dict)
    _started: dict[int, Any] = field(default_factory=dict)
    _created: dict[int, Any] = field(default_factory=dict)
    _digests: dict[str, str | None] = field(default_factory=dict)
    # Runs whose standing came from the run cache (`_run_state`).
    _shared_runs: set[int] = field(default_factory=set)
    _on_branch: dict[str, bool] = field(default_factory=dict)
    _records: dict[tuple[int, str], dict[str, Any]] = field(default_factory=dict)
    _mapped: dict[int, str] | None = None  # the head-ref map, once loaded
    _humans: frozenset[int] | None = None
    _humans_at: datetime | None = None  # when `_humans` was read
    # Every login on the trusted list, lowercased, to its id, and when read.
    _logins: dict[str, int] | None = None
    _logins_at: datetime | None = None
    # Admission's `task-list` (`_task_list`), once read.
    _task_list_value: Any = None
    _task_list_read: bool = False
    _task_list_at: datetime | None = None
    # Whether each size-split sub-issue judged counts (`_split_child`), and
    # when each read behind it was taken, noted again on every answer
    # (`run_cache.note`).
    _split_children: dict[int, tuple[bool, tuple[datetime, ...]]] = field(
        default_factory=dict
    )
    # The pull requests `link_refusal` read, each taken by the next
    # `_closing_issues` instead of reading it again.
    _linked: dict[int, dict[str, Any]] = field(default_factory=dict)
    # The issue number `link_refusal` took for each pull request.
    linked_issue: dict[int, Any] = field(default_factory=dict)

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

    def listing(self) -> list[dict[str, Any]]:
        """Every repository artifact, as a judgment reads it, saved to
        `listing_path` for the run's gate processes. Raises `RuntimeError`
        when it cannot be read."""
        try:
            return self._listing()
        except _Unreadable as exc:
            raise RuntimeError(str(exc)) from exc

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
            self._created[run_id] = record.get("created_at")
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
            _is_id(record.get("id"), run_id)
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
        artifact has since gone still refuses. A failed read is shared too,
        so the run's later candidates refuse on it rather than download it
        again. An artifact with no id is not shared. An id the head-ref map
        holds is answered from it, tie or not, with no download."""
        shared = _is_artifact_id(artifact_id)
        key = f"{self.repo}|{artifact_id}"
        dated = run_cache.get_dated(RECORD_SECTION, key, None) if shared else None
        if dated is not None and is_json_object(dated[0]):
            return dated[0].get("head_ref")
        if shared:
            if self._mapped is None:
                self._mapped = load_head_refs(self.head_refs_path, self.repo)
            if artifact_id in self._mapped:
                return self._mapped[artifact_id]
        # A carried head ref ties the FAIL to this PR; one naming another
        # ref could untie it, so the record is read instead.
        carried = run_cache.get(CARRIED_RECORD_SECTION, key, None) if shared else None
        if head_ref and is_json_object(carried) and carried.get("head_ref") == head_ref:
            return head_ref
        failed = run_cache.get(UNREAD_RECORD_SECTION, key, None) if shared else None
        if isinstance(failed, str):
            raise _Unreadable(failed)
        try:
            record = self._record(run_id, name, artifact_id)
        except _Unreadable as exc:
            if shared:
                run_cache.put(UNREAD_RECORD_SECTION, key, str(exc))
            raise
        if shared:
            run_cache.put(RECORD_SECTION, key, {"head_ref": record.get("head_ref")})
        return record.get("head_ref")

    def _record(
        self, run_id: int, name: str, artifact_id: Any = None
    ) -> dict[str, Any]:
        """The artifact's verdict.json, downloaded once: by the listed
        artifact's id when it has one, one request, else by run and name
        (`gh run download`, which lists the run's artifacts first, then
        fetches the archive)."""
        key = (run_id, name)
        if key not in self._records:
            unread = f"artifact {name} of run {run_id}"
            try:
                if _is_artifact_id(artifact_id):
                    proc = postmerge.gh_capture(
                        [
                            "api",
                            f"repos/{self.repo}/actions/artifacts/{artifact_id}/zip",
                        ],
                        env_overrides=self._env(),
                        binary=True,
                    )
                    if proc.returncode != 0:
                        raise _Unreadable(unread)
                    with zipfile.ZipFile(io.BytesIO(proc.stdout)) as archive:
                        raw = archive.read("verdict.json")
                else:
                    with tempfile.TemporaryDirectory() as tmp:
                        proc = postmerge.gh_capture(
                            ["run", "download", str(run_id), "-R", self.repo]
                            + ["-n", name, "-D", tmp],
                            env_overrides=self._env(),
                        )
                        path = Path(tmp) / "verdict.json"
                        if proc.returncode != 0 or not path.is_file():
                            raise _Unreadable(unread)
                        raw = path.read_bytes()
                record = json.loads(raw.decode("utf-8"))
            except _Unreadable:
                raise
            except Exception as exc:
                # Any failure to fetch, unpack or parse it (a timeout, a bad
                # zip, a corrupt deflate stream's zlib.error, bad JSON) is an
                # unreadable record, which `_head_ref` shares for the run.
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
        if self._humans is None:
            self._read_trusted_list()
        if self._humans_at is not None:
            run_cache.note(self._humans_at)
        return self._humans or frozenset()

    def _read_trusted_list(self) -> None:
        """Read the trusted list at the branch once: its human ids, and every
        login's id (`_lane_app_id`), each shared by the run's gate processes."""
        key = f"{self.repo}@{self.branch}"
        at = run_cache.now()
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
        actors = [json_object(a) for a in actors]
        self._humans = frozenset(
            a["id"]
            for a in actors
            if a.get("kind") == "human" and isinstance(a.get("id"), int)
        )
        self._logins = {
            a["login"].lower(): a["id"]
            for a in actors
            if isinstance(a.get("login"), str) and type(a.get("id")) is int
        }
        self._humans_at = self._logins_at = at
        run_cache.put("trusted-humans", key, sorted(self._humans), at)
        run_cache.put("trusted-logins", key, self._logins, at)

    def _lane_app_id(self) -> int | None:
        """The lanes App's id: the trusted list's id for `agent_identity`
        with its `[bot]` suffix, as resolve-pr.mjs reads `laneAppId`; None
        when no identity is set or the list names none."""
        identity = (self.agent_identity or "").strip().lower().removesuffix("[bot]")
        if not identity:
            return None
        if self._logins is None:
            key = f"{self.repo}@{self.branch}"
            shared = run_cache.get_dated("trusted-logins", key, run_cache.MAX_AGE)
            if shared is not None and is_json_object(shared[0]):
                self._logins = {k: v for k, v in shared[0].items() if type(v) is int}
                self._logins_at = shared[1]
        if self._logins is None:
            self._read_trusted_list()
        if self._logins_at is not None:
            run_cache.note(self._logins_at)
        app_id = (self._logins or {}).get(f"{identity}[bot]")
        return app_id if type(app_id) is int else None

    def _task_list(self) -> str | None:
        """Admission's `task-list` at the repository's default branch, as
        resolve-pr.mjs reads it from main's checkout whatever the pull
        request's base, shared by the run's gate processes; None when the
        rules hold no string there. A failed read raises `_Unreadable`."""
        if not self._task_list_read:
            try:
                default = merge_policy._default_branch(self.repo, shared=True)
            except merge_policy.PolicyReadError as exc:
                raise _Unreadable(str(exc)) from exc
            key = f"{self.repo}@{default}"
            shared = run_cache.get_dated("task-list", key, run_cache.MAX_AGE)
            if shared is not None:
                self._task_list_value, at = shared
            else:
                at = run_cache.now()
                rules = json_object(
                    _read(
                        [
                            "api",
                            "-H",
                            "Accept: application/vnd.github.raw",
                            f"repos/{self.repo}/contents/{ADMISSION_RULES_PATH}?ref={default}",
                        ],
                        "admission rules",
                    )
                )
                self._task_list_value = rules.get("task-list")
                run_cache.put("task-list", key, self._task_list_value, at)
            self._task_list_read = True
            self._task_list_at = at
        if self._task_list_at is not None:
            run_cache.note(self._task_list_at)
        value = self._task_list_value
        return value if isinstance(value, str) and value else None

    def _split_child(self, issue: dict[str, Any]) -> bool:
        """Whether recorded linked issue `issue`, which the lanes App wrote,
        is a size split's sub-issue whose body counts (`split_child_body`),
        read once per Reader under the Actions token (`issues: read`). A
        failed read raises `_Unreadable` (`verify:unreadable`), as
        resolve-pr.mjs fails on it; a cut comment read counts nothing."""
        app_id = self._lane_app_id()
        number = issue.get("number")
        if (
            app_id is None
            or type(number) is not int
            or issue.get("author_type") != "Bot"
            or issue.get("author_id") != app_id
        ):
            return False
        if number not in self._split_children:
            with run_cache.track() as taken:
                task_list = self._task_list()
                run_cache.note(run_cache.now())
                node = self._graphql(
                    SPLIT_CHILD_QUERY, number, "split sub-issue", env=self._env()
                ).get("issue")
                body = split_child_body(
                    node, self.repo, self._trusted_humans(), app_id, task_list
                )
            self._split_children[number] = (body is not None, tuple(taken))
        counts, read_at = self._split_children[number]
        for at in read_at:
            run_cache.note(at)
        return counts

    def _trusted_actor(self, kind: Any, actor_id: Any) -> bool:
        """The one spec-author filter (resolve-pr.mjs `trusted` is its
        twin): a User on the trusted list's humans, the PR author included.
        Bots and Apps, the lanes App among them, never pass."""
        return kind == "User" and actor_id in self._trusted_humans()

    def _spec_comments(self, comments: list[Any]) -> set[tuple[Any, Any]]:
        """The trusted comments, by id and update time: written, and last
        edited if ever, by a trusted actor (`_trusted_actor`)."""

        def by(actor: Any) -> bool:
            actor = json_object(actor)
            return self._trusted_actor(actor.get("__typename"), actor.get("databaseId"))

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

    def _trusted_spec(self, record: dict[str, Any]) -> bool:
        """Every linked issue was written, and its body last edited if ever,
        by a User on the trusted list's humans (`_trusted_actor`), or is a
        size split's sub-issue whose body counts (`_split_child`)."""

        def trusted(issue: dict[str, Any], role: str) -> bool:
            return self._trusted_actor(
                issue.get(f"{role}_type"), issue.get(f"{role}_id")
            )

        issues = [
            json_object(issue) for issue in json_array(record.get("linked_issues"))
        ]
        return bool(issues) and all(
            (
                trusted(issue, "author")
                and (issue.get("last_edited_at") is None or trusted(issue, "editor"))
            )
            or self._split_child(issue)
            for issue in issues
        )

    def _graphql(
        self,
        query: str,
        number: int,
        what: str,
        missing: str | None = None,
        env: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        """The query's `repository`, read under `env`'s token when given. A
        NOT_FOUND for `missing` alone (`merge_policy.names_nothing`), which
        gh exits nonzero on, reads as `missing` an empty object, so a null
        there without that error stays apart; any other error raises
        `_Unreadable`."""
        owner, _, name = self.repo.partition("/")
        args = ["api", "graphql", "-f", f"query={query}"]
        args += ["-f", f"o={owner}", "-f", f"r={name}", "-F", f"n={number}"]
        try:
            proc = (
                postmerge.gh_capture(args, env_overrides=env)
                if env
                else postmerge.gh_capture(args)
            )
        except (RuntimeError, ValueError, OSError) as exc:
            raise _Unreadable(f"#{number} {what}: {exc}") from exc
        if missing and merge_policy.names_nothing(proc.stdout, missing):
            return {missing: {}}
        if proc.returncode != 0:
            raise _Unreadable(f"#{number} {what}: {(proc.stderr or '').strip()}")
        try:
            payload = json_object(json.loads(proc.stdout))
        except ValueError as exc:
            raise _Unreadable(f"#{number} {what}: {exc}") from exc
        if payload.get("errors"):
            raise _Unreadable(f"#{number}: the {what} could not be read")
        repository = json_object(payload.get("data")).get("repository")
        if not is_json_object(repository):
            raise _Unreadable(f"#{number}: the {what} answer has no repository")
        return repository

    def _closing_issues(self, number: int) -> dict[Any, Any]:
        """The PR's closing issues in this repository now, each with its
        body's lastEditedAt, read as the resolver reads them
        (closingIssuesReferences, first 10), or, when it closes none, the one
        issue its body's `Refs:` lines name (`merge_policy.refs_issue`)."""
        pull = self._linked.pop(number, None) or json_object(
            self._graphql(CLOSING_QUERY, number, "closing issues").get("pullRequest")
        )
        refs = json_object(pull.get("closingIssuesReferences"))
        nodes = refs.get("nodes")
        if not is_json_array(nodes) or refs.get("totalCount") != len(nodes):
            raise _Unreadable(f"#{number}: the closing issues could not be read")
        if refs.get("totalCount") == 0:
            named, _ = merge_policy.refs_issue(pull.get("body"))
            if named is not None:
                node = self._graphql(
                    REFS_QUERY, named, "Refs issue", "issueOrPullRequest"
                ).get("issueOrPullRequest")
                if not is_json_object(node):
                    raise _Unreadable(f"#{named}: the Refs issue answer is empty")
                # Marked so the gate can bind a pass to how it was linked.
                nodes = (
                    [node | {REFS_MARK: True}]
                    if node.get("__typename") == "Issue"
                    else []
                )
        live = {
            json_object(node).get("number"): json_object(node)
            for node in nodes
            if json_object(json_object(node).get("repository")).get("nameWithOwner")
            == self.repo
        }
        for issue in live.values():
            for part in ISSUE_LISTS:
                listed = json_object(issue.get(part))
                if not is_json_array(listed.get("nodes")) or listed.get(
                    "totalCount"
                ) != len(listed["nodes"]):
                    raise _Unreadable(
                        f"#{issue.get('number')}: its {part} could not be read"
                    )
        return live

    def link_refusal(self, number: int) -> str | None:
        """Why the pull request's issue link is not one the pr-merge lane
        takes from a pull request the lane opened, or None when it is: the
        gate's own rule (`merge_policy._linked_issue`, as `lane_eligibility`
        reads it), so one closing issue in this repository, or, with none,
        the one issue its plain `Refs:` lines name. Then the trust hold on that
        issue as `eligibility` reads it (`merge_policy.trust_refusal`), so a
        label naming untrusted work added after admission, or one a non-human
        removed, refuses at arm time; its labels come with the link's read,
        its timeline in one more. A failed read refuses."""
        try:
            pull = json_object(
                self._graphql(CLOSING_QUERY, number, "closing issues").get(
                    "pullRequest"
                )
            )
            issue, refusal = merge_policy._linked_issue(pull, self.repo)
            if refusal is None:
                owner, _, name = self.repo.partition("/")
                permission = merge_policy.permission_reader(self.repo)
                # No agent identity: the lanes App is a Bot, which is never
                # human (`merge_policy.is_human`).
                refusal = merge_policy.trust_refusal(
                    owner,
                    name,
                    issue,
                    lambda actor: merge_policy.is_human(
                        actor,
                        repo=self.repo,
                        agent_identity=None,
                        permission=permission,
                    ),
                    {},
                )
        except (_Unreadable, merge_policy.PolicyReadError) as exc:
            return f"unreadable: {exc}"
        if refusal is None:
            self._linked[number] = pull
            self.linked_issue[number] = issue.get("number")
        return refusal

    def _closers(self, live: dict[Any, Any]) -> set[int]:
        """The pull requests in this repository, open or closed, that close
        any of the closing issues `live` holds."""
        return {
            node.get("number")
            for issue in live.values()
            for node in map(
                json_object,
                json_object(issue.get("closedByPullRequestsReferences")).get("nodes"),
            )
            if json_object(node.get("repository")).get("nameWithOwner") == self.repo
            and type(node.get("number")) is int
        }

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
        commits = self._commits(number, head) | {head}
        verdicts: list[Verdict] = []
        passes: list[tuple[int, str, Any]] = []
        head_fails: list[tuple[int, str]] = []
        # Counted FAILs by head: run id, artifact name and id (`_wider_pass`).
        fail_artifacts: dict[str, list[tuple[int, str, Any]]] = {}
        ignored = 0
        unreadable: str | None = None
        # FAILs of verifier origin by pull request number, and the numbers
        # with a FAIL whose run cannot be read, for the cap's other pull
        # requests (`_elsewhere`).
        failed_by_pr: dict[int, set[str]] = {}
        unread_prs: set[int] = set()
        # The same by each issue a FAIL's name carries (`named_issues`).
        failed_by_issue: dict[int, set[str]] = {}
        unread_issues: set[int] = set()
        for item in map(json_object, self._listing()):
            name = str(item.get("name") or "")
            match = verdict_name(name)
            if item.get("expired") is not False:
                continue
            if not match:
                if (off := FAIL_PREFIX_RE.match(name)) is not None:
                    # Compared as text: the digits are unbounded, and a string
                    # past Python's int-conversion limit would raise.
                    digits = off[1].lstrip("0")
                    hold, unread = self._off_grammar(
                        item, name, digits == str(number) or off[2] in commits
                    )
                    unreadable = unreadable or hold
                    if unread and len(digits) <= 10:
                        # Held only if its pull request is one the cap counts,
                        # which a number over 10 digits never is.
                        unread_prs.add(int(digits or "0"))
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
                    passes.append((run_id, name, item.get("id")))
                else:
                    ignored += 1
                continue
            state = self._run_state(run_id, shared=True)
            if state == FOREIGN:
                ignored += 1
                continue
            if state == UNREAD:
                unread_prs.add(pr_n)
                unread_issues.update(named_issues(match))
                if tied:
                    unreadable = unreadable or f"run of {name}"
                else:
                    ignored += 1
                continue
            failed_by_pr.setdefault(pr_n, set()).add(sha)
            for issue in named_issues(match):
                failed_by_issue.setdefault(issue, set()).add(sha)
            if not tied and match[4] is not None:
                # The name, which the run authenticates, carries the head
                # branch the verdict records: no download.
                if not head_ref or head_ref_digest(head_ref) != match[4]:
                    continue
            elif not tied:
                try:
                    recorded = self._head_ref(run_id, name, item.get("id"), head_ref)
                except _Unreadable:
                    unreadable = unreadable or f"record of {name}"
                    continue
                if not head_ref or recorded != head_ref:
                    continue
            verdicts.append(Verdict(sha, verdict, run_id))
            fail_artifacts.setdefault(sha, []).append((run_id, name, item.get("id")))
            if sha == head and verdict == "fail":
                head_fails.append((run_id, name))
        fails = [v for v in verdicts if v.verdict == "fail"]
        failed = {v.sha for v in fails}
        refusal: str | None
        detail = unreadable
        if len(failed) >= self.max_fails:
            refusal = REPEATED_FAIL
            detail = f"fails at {len(failed)} heads, the cap is {self.max_fails}"
        elif head in failed:
            # A FAIL here gets a fix round, so the cap counts the other pull
            # requests for its issues first: a round past it cannot merge.
            _, elsewhere = self._elsewhere(
                number, failed_by_pr, unread_prs, failed_by_issue, unread_issues
            )
            refusal = FAIL
            if len(failed | elsewhere) >= self.max_fails:
                refusal = REPEATED_FAIL
                detail = (
                    f"fails at {len(failed | elsewhere)} heads of this and other "
                    f"pull requests for its issues, the cap is {self.max_fails}"
                )
        elif fails and (
            not self._passes_follow(fails, passes)
            or not self._change_differs(
                head,
                failed,
                lambda sha: self._wider_pass(number, sha, fail_artifacts, passes),
            )
        ):
            refusal = EARLIER_FAIL
        elif unreadable:
            refusal = UNREADABLE
        elif passes:
            # Every pass of the run that started last must allow
            # (`_newest`), so listing order decides nothing; any unreadable
            # one refuses (`_Unreadable`).
            live, elsewhere = self._elsewhere(
                number, failed_by_pr, unread_prs, failed_by_issue, unread_issues
            )
            if len(failed | elsewhere) >= self.max_fails:
                refusal = REPEATED_FAIL
                detail = (
                    f"fails at {len(failed | elsewhere)} heads of this and other "
                    f"pull requests for its issues, the cap is {self.max_fails}"
                )
            else:
                refusals = {
                    self._pass_refusal(run_id, name, number, head, live, pr, artifact)
                    for run_id, name, artifact in self._newest(passes)
                }
                refusal = next(
                    (r for r in (SPEC_CHANGED, UNTRUSTED_SPEC) if r in refusals),
                    None,
                )
        else:
            refusal = MISSING
        return Evidence(
            refusal,
            head,
            tuple(verdicts),
            ignored,
            detail,
            max(head_fails)
            if head_fails and refusal in (FAIL, REPEATED_FAIL)
            else None,
        )

    def _off_grammar(
        self, item: dict[str, Any], name: str, tied: bool
    ) -> tuple[str | None, bool]:
        """Why a FAIL-shaped name no reader takes holds, and whether its run
        cannot be read. It holds when its run is of verifier origin, or, tied
        to this pull request, cannot be read: it may be a FAIL the cap or the
        head should count, so it is never skipped. One from any other run is
        ignored; an untied one whose run cannot be read is left to the cap
        (`_elsewhere`), as any such FAIL is."""
        run_id = json_object(item.get("workflow_run")).get("id")
        if not isinstance(run_id, int) or isinstance(run_id, bool):
            return None, False
        state = self._run_state(run_id, shared=True)
        if state == FOREIGN:
            return None, False
        if state == UNREAD and not tied:
            return None, True
        return f"off-grammar FAIL name {name}", state == UNREAD

    def _elsewhere(
        self,
        number: int,
        failed_by_pr: dict[int, set[str]],
        unread_prs: set[int],
        failed_by_issue: dict[int, set[str]],
        unread_issues: set[int],
    ) -> tuple[dict[Any, Any], set[str]]:
        """The live issues (`_closing_issues`: closing, or the `Refs:` one),
        and the heads of counted FAILs of the other pull requests that close
        one of them, and of every counted FAIL whose name carries one of them
        (`named_issues`: a `Refs:` pull request's FAILs count only so), from
        the listing already read. A FAIL among those whose run cannot be read
        raises `_Unreadable`."""
        live = self._closing_issues(number)
        others = self._closers(live) - {number}
        if others & unread_prs or unread_issues & set(live):
            raise _Unreadable("a FAIL run of a pull request for the same issue")
        return live, set().union(
            *(failed_by_pr.get(n, set()) for n in others),
            *(failed_by_issue.get(n, set()) for n in live),
        )

    def _fresh_created(self, run_id: int) -> datetime | None:
        """When the run was created, from a record this process read from
        GitHub: a cached or carried record could be forged, so it is read
        again. A re-attempt keeps `created_at` and moves `run_started_at`
        later, so a re-run of an old judgment never looks newer than a FAIL
        that followed it. None when the record holds no time; raises
        `_Unreadable` when the read fails."""
        if run_id not in self._created:
            record = json_object(
                self._actions(
                    ["api", f"repos/{self.repo}/actions/runs/{run_id}"],
                    f"run {run_id}",
                )
            )
            if not _is_id(record.get("id"), run_id):
                return None
            self._created[run_id] = record.get("created_at")
        try:
            return postmerge._time(self._created[run_id])
        except postmerge.PostMergeReadError:
            return None

    def _newest(self, passes: list[tuple[int, str, Any]]) -> list[tuple[int, str, Any]]:
        """The passes whose runs started last (`run_started_at`, which a
        re-attempt moves, and which a re-attempt's judgment read the spec
        at): a pr-verify run that judged the head again after the spec
        changed supersedes the passes before it, which judged a spec that is
        gone. resolve-pr.mjs `specChanged` weighs the same start times. When
        any start time is missing or unreadable, every pass decides."""
        try:
            started = [postmerge._time(self._started.get(r)) for r, _, _ in passes]
        except postmerge.PostMergeReadError:
            return passes
        last = max(started)
        return [p for p, s in zip(passes, started, strict=True) if s == last]

    def _passes_follow(
        self, fails: list[Verdict], passes: list[tuple[int, str, Any]]
    ) -> bool:
        """Every counted pass at the head was judged after every counted
        FAIL: each pass's run was created after each FAIL's run. A pass judged
        before a later FAIL (head B passes, A fails, the branch returns to B)
        never clears it, re-attempted or not, and a missing time clears
        nothing."""
        if not passes:
            return False
        starts = [self._fresh_created(v.run_id) for v in fails]
        begun = [self._fresh_created(run_id) for run_id, _, _ in passes]
        if None in starts or None in begun:
            return False
        return max(s for s in starts if s) < min(b for b in begun if b)

    def _digest(self, sha: str) -> str | None:
        """`change_digest` of the pull request's own change at `sha`: the
        diff from its merge base with the branch to `sha` (compare
        `branch...sha`, read once). None when it holds no change or GitHub
        answers 404 (a garbage-collected or force-pushed-away head, which no
        later read finds); raises `_Unreadable` when any other read fails,
        which is not saved."""
        if sha not in self._digests:
            label = f"compare {self.branch}...{sha}"
            try:
                diff = postmerge.gh_capture(
                    [
                        "api",
                        "-H",
                        "Accept: application/vnd.github.diff",
                        f"repos/{self.repo}/compare/{self.branch}...{sha}",
                    ],
                    env_overrides=self._env(),
                )
            except (RuntimeError, ValueError, OSError) as exc:
                raise _Unreadable(f"{label}: {exc}") from exc
            if diff.returncode == 0:
                self._digests[sha] = change_digest(diff.stdout)
            elif gh_http_status(diff.stderr or "") == 404:
                self._digests[sha] = None
            else:
                raise _Unreadable(
                    f"{label}: {(diff.stderr or '').strip() or diff.returncode}"
                )
        return self._digests[sha]

    def _change_differs(
        self,
        head: str,
        failed: set[str],
        same_change_clears: Callable[[str], bool] | None = None,
    ) -> bool:
        """The pull request's change at the head differs from its change at
        every FAILed head, so its pass judged a change no FAIL did, or, at a
        head of the same change, `same_change_clears` says the pass judged
        more than its FAIL did. A diff that holds no change differs from
        nothing; a failed read raises `_Unreadable`. Heads are read in sorted
        order, so which of a FAIL that carries and an unreadable one decides
        never varies by run."""
        own = self._digest(head)
        return own is not None and all(
            (other := self._digest(sha)) is not None
            and (
                other != own
                or (same_change_clears is not None and same_change_clears(sha))
            )
            for sha in sorted(failed)
        )

    def _wider_pass(
        self,
        number: int,
        sha: str,
        fail_artifacts: dict[str, list[tuple[int, str, Any]]],
        passes: list[tuple[int, str, Any]],
    ) -> bool:
        """Every counted FAIL at `sha` records `spec_kind` `refs` for pull
        request `number` at `sha`, and every counted pass at the head records
        `spec_kind` `closes` with exactly the linked issues each FAIL records
        (`_issue_numbers`): the passes judged the whole of the spec the FAILs
        judged a slice of, not another issue's. Only those exact values
        count, never the default `_pass_refusal` gives an older record; a
        record or linkage that cannot be read is False."""
        fails = fail_artifacts.get(sha, [])
        if not passes or not fails:
            return False
        try:
            sliced: set[frozenset[int]] = set()
            for run_id, name, artifact in fails:
                record = self._record(run_id, name, artifact)
                if (
                    record.get("pr") != number
                    or record.get("head_sha") != sha
                    or record.get("verdict") != "fail"
                    or record.get("spec_kind") != "refs"
                ):
                    return False
                sliced.add(_issue_numbers(record))
            for run_id, name, artifact in passes:
                record = self._record(run_id, name, artifact)
                if (
                    record.get("spec_kind") != "closes"
                    or {_issue_numbers(record)} != sliced
                ):
                    return False
        except _Unreadable:
            return False
        return True

    def _listed_id(self, run_id: int, name: str) -> Any:
        """The id the listing this Reader judged on gives the artifact named
        `name` of run `run_id`, or None (it is then fetched by run and name)."""
        for item in map(json_object, self._artifacts or []):
            if item.get("name") == name and _is_id(
                json_object(item.get("workflow_run")).get("id"), run_id
            ):
                return item.get("id")
        return None

    def fail_summary(
        self, run_id: int, name: str, number: int, head: str
    ) -> str | None:
        """The `summary` a FAIL artifact's verdict.json records for pull
        request `number` at `head`, or None when it records another pull
        request, head or verdict. Raises `SummaryUnreadable` when it cannot be
        read. Untrusted model text: the caller frames it as data."""
        try:
            record = self._record(run_id, name, self._listed_id(run_id, name))
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
        live: dict[Any, Any],
        pr: dict[str, Any] | None = None,
        artifact_id: Any = None,
    ) -> str | None:
        """One counted pass at the head against the live closing issues, or,
        for an `intent` `pull-request` verdict, the live title and body."""
        record = self._record(run_id, name, artifact_id)
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
                json_array(json_object(node.get("comments")).get("nodes"))
            )
            != self._recorded_comments(issues[n])
            for n, node in live.items()
        ):
            return SPEC_CHANGED
        # A `Refs:` issue is judged as a partial slice (write-verdict.mjs
        # `spec_kind`), so a pass judged that way never covers a pull request
        # that now closes it, nor the reverse. A record from before the kind
        # was written judged closing issues.
        if live and any(n.get(REFS_MARK) for n in live.values()) != (
            record.get("spec_kind", "closes") == "refs"
        ):
            return SPEC_CHANGED
        # No closing issue, then and now: the verdict judged the pull
        # request's own title and body, which only a trusted author's adopted
        # pull request reaches the gate with (`lane_eligibility`).
        if not issues and record.get("intent") == INTENT_PULL_REQUEST:
            # The title and body it judged, by sha256 (write-verdict.mjs):
            # an edit since, or no recorded hash, is a spec it never read.
            pr = json_object(pr)
            text = f"{pr.get('title') or ''}\n\n{pr.get('body') or ''}"
            live_digest = hashlib.sha256(text.encode()).hexdigest()
            return None if record.get("intent_sha256") == live_digest else SPEC_CHANGED
        return None if self._trusted_spec(record) else UNTRUSTED_SPEC

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


def lane_risk_refusal(
    repo: str,
    number: int,
    pr: dict[str, Any],
    config: merge_policy.PipelineConfig,
    issue: int | None,
) -> str | None:
    """Why pr-merge's gate would hold the pull request on its risk score, or
    None: `babysit_risk.score` and `holding` over the inputs the gate builds
    (`babysit_merge.score_unattended`) for a lane pull request, with `config`
    the base's tightened by the default branch head's. So the review lanes' evidence (an open CRITICAL
    security finding, a review not bound to the head), a symlink, submodule
    or other non-regular mode, a high path, the manifest review, the trust
    gate and the cost review all hold, the cost review lifted only by the
    owner's decision on the pull request or its linked `issue`
    (`merge_policy.cost_decision`). A read that fails holds."""
    # Imported here: babysit_merge imports this module.
    import babysit_merge  # noqa: PLC0415
    import babysit_risk  # noqa: PLC0415

    try:
        identity = config.agent_identity
        if not identity:
            return "unreadable: no agent identity"
        permission = merge_policy.permission_reader(repo)
        files, complete = merge_policy.changed_files(repo, pr)
        lanes, _ = babysit_merge._lane_evidence(
            repo,
            number,
            pr,
            identity,
            frozenset(),
            permission,
            [p for f in files for p in (f.path, f.previous_path) if p]
            if complete
            else None,
        )
        files = merge_policy.with_contents(repo, pr, files)
        private = json_object(json_object(pr.get("base")).get("repo")).get("private")
        risk_input = babysit_risk.RiskInput(
            files=files,
            files_complete=complete,
            max_changed_lines=config.max_changed_lines,
            high_paths=config.denied_paths,
            lanes=lanes,
            public=True if private is False else None,
            pulumi_dirs=merge_policy.pulumi_dirs_at(repo, pr),
            high_floor=config.high_path_floor,
            max_changed_files=config.max_changed_files,
            lines_optional=True,
        )
        risk = babysit_risk.score(risk_input)
        if any(r.code == babysit_risk.COST_CODE for r in risk.reasons):
            decision = merge_policy.cost_decision(
                repo, pr, issue, permission=permission, agent_identity=identity
            )
            if decision:
                risk = babysit_risk.score(replace(risk_input, cost_decision=decision))
    except Exception as exc:  # noqa: BLE001 - any doubt holds, as the gate's
        return f"unreadable: {type(exc).__name__}: {exc}"
    held = babysit_risk.holding(risk)
    return "; ".join(f"{r.code}: {r.detail}" for r in held) or None


def main(argv: list[str] | None = None, *, now: datetime | None = None) -> int:
    """`evidence <number> <head>`: one pull request's evidence at `head` as
    one JSON line (`Evidence.report`), as pr-merge's gate judges it.
    enable-auto-merge.mjs arms native auto-merge only on a null `refusal`
    at the head it read. Exit 0 whenever the line is printed, a refusal
    included.

    With `--base-sha`, the FAIL cap is the gate's: `merge.max-verify-fails`
    of the config at that base commit and at the default branch head, the
    lower one (`with_default_branch`), each read once per run by commit
    (`merge_policy.config_at`); a config that cannot be read refuses
    `verify:unreadable`. A pass judged on the run's saved listing is judged
    again on a listing of its own, as the gate does before it allows.

    With `--lane-link`, the line also carries `ineligible`: null when the
    pull request's issue link is one the pr-merge lane takes and its issue
    clears the trust hold (`Reader.link_refusal`), else why not, with refusal
    `verify:ineligible`
    and no verdict or config read. With `--lane-reviews` (and `--base-sha`
    and `--rung`, the lane room's effective rung), a line whose refusal is
    null also carries `reviews`: null when pr-merge's gate would not hold
    the pull request on its risk score (`lane_risk_refusal`), else why.

    `lane-room --postmerge-result <file> [--rung-cap <value>]`: whether the
    pr-merge lane may merge one more of its own pull requests now
    (`merge_policy.lane_room`, `LaneRoom.report`), from this run's
    `babysit_postmerge.py` report and the `CLAUDE_LANES_MERGE_RUNG_CAP` value
    the workflow read (empty is no cap; missing holds the rung off). A report
    refused only as `unverified-stale` is kept while nothing it was read from
    has moved, else checked again."""
    parser = argparse.ArgumentParser(
        prog="babysit_verify_evidence.py", allow_abbrev=False
    )
    sub = parser.add_subparsers(dest="command", required=True)
    cmd = sub.add_parser("evidence", allow_abbrev=False)
    cmd.add_argument("--repo", required=True)
    cmd.add_argument("--branch", default="main")
    cmd.add_argument("--max-fails", type=int, default=merge_policy.MAX_VERIFY_FAILS)
    cmd.add_argument("--base-sha", default=None)
    cmd.add_argument("--lane-link", action="store_true")
    cmd.add_argument("--lane-reviews", action="store_true")
    cmd.add_argument("--rung", default=None)
    cmd.add_argument("number", type=int)
    cmd.add_argument("head")
    room = sub.add_parser("lane-room", allow_abbrev=False)
    room.add_argument("--repo", required=True)
    room.add_argument("--postmerge-result", required=True)
    room.add_argument("--rung-cap", default=None)
    args = parser.parse_args(argv)
    if args.command == "lane-room":
        shared = postmerge.read_shared(args.postmerge_result)
        answer = merge_policy.lane_room(
            args.repo,
            shared,
            lane_rung_cap=args.rung_cap,
            # The gate's recompute, bound as the room binds, and the one run
            # listing that spares it while the pending merges' runs hold.
            post_merge=postmerge.gate_reader(args.repo, (), lane_merges_only=True),
            runs_unchanged=lambda answer, branch: postmerge.pending_runs_unchanged(
                args.repo, answer, branch
            ),
        )
        print(json.dumps(answer.report()))
        return 0
    if (
        args.max_fails < 1
        or not merge_policy.SHA_RE.fullmatch(args.head)
        or (
            args.base_sha is not None
            and not merge_policy.SHA_RE.fullmatch(args.base_sha)
        )
    ):
        parser.error(
            "--max-fails must be 1 or more, and head and --base-sha full commit SHAs"
        )
    reader = Reader(args.repo, args.branch, now=now, max_fails=args.max_fails)
    link: dict[str, Any] = {}
    config: merge_policy.PipelineConfig | None = None
    if args.lane_link:
        link["ineligible"] = reader.link_refusal(args.number)
        if link["ineligible"] is not None:
            refusal = Evidence(INELIGIBLE, args.head, (), 0, link["ineligible"])
            print(json.dumps(refusal.report() | link))
            return 0
    if args.base_sha is not None:
        try:
            base = merge_policy.config_at(args.repo, args.base_sha)
            if base.error:
                raise merge_policy.PolicyReadError(base.error)
            config = merge_policy.with_default_branch(args.repo, base)
        except merge_policy.PolicyReadError as exc:
            refusal = Evidence(UNREADABLE, args.head, (), 0, f"config: {exc}")
            print(json.dumps(refusal.report() | link))
            return 0
        reader.max_fails = config.max_verify_fails
        reader.agent_identity = config.agent_identity
    pr = None
    if args.lane_reviews:
        try:
            pr = merge_policy.pull_request(args.repo, args.number)
        except merge_policy.PolicyReadError as exc:
            refusal = Evidence(UNREADABLE, args.head, (), 0, str(exc))
            print(json.dumps(refusal.report() | link))
            return 0
    evidence = reader.evidence(args.number, args.head, pr)
    if evidence.refusal is None and reader.saved:
        reader.refresh()
        evidence = reader.evidence(args.number, args.head, pr)
    if args.lane_reviews and evidence.refusal is None:
        head = json_object(json_object(pr).get("head")).get("sha")
        if head != args.head:
            link["reviews"] = f"unreadable: the head is {head}, not {args.head}"
        elif config is None:
            link["reviews"] = "unreadable: no --base-sha, so no config to score at"
        else:
            # The lowest of the room's effective rung and this base's config.
            rung = merge_policy.effective_rung(
                config_rung=config.rung,
                loop_merge=config.loop_merge,
                cap=args.rung if args.rung in merge_policy.RUNG_RANK else "off",
                demoted=False,
            ).rung
            link["reviews"] = (
                f"unreadable: the lane's rung is {args.rung}"
                if rung == "off"
                else lane_risk_refusal(
                    args.repo,
                    args.number,
                    json_object(pr),
                    config,
                    reader.linked_issue.get(args.number),
                )
            )
    print(json.dumps(evidence.report() | link))
    return 0


if __name__ == "__main__":
    sys.exit(main())

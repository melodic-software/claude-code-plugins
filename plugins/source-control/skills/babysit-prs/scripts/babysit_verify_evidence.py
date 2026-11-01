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
from a completed, successful one. Any other artifact is ignored, and so is a
FAIL whose verifier run judged a checks run that started while the pull
request was a draft, which skipped every suite (`_draft_judged`, resolve-pr.mjs
`draftJudgments`'s rule): every pr-require-checks pull_request run at its head
created before the verifier run ran ci-status's `Note a draft` step. Such a
FAIL counts nowhere below, at its head, at another head or toward the cap. A
failed read, a list cut short or no such run keeps the FAIL.

`Reader.evidence` decides one pull request at its vetted head, in this order:

- counted FAILs at `max_fails` or more distinct heads of this pull request
  (tied as in the item after next): `verify:repeated-fail`, whatever a pass
  says, a FAIL at the head included. Before a FAIL at the head or a pass
  decides, FAILs of other pull requests in this repository that are not
  merged, nor a closed lanes App attempt (`_counts`), and close one of its
  issues (its closing issues, or its `Refs:` issue) count too, at their own
  heads, and so does every FAIL of such a pull request whose name carries one
  of those issues, a `Refs:` pull request's FAILs among them (a FAIL among
  them whose run cannot be read is `verify:unreadable`). A merged pull
  request's or a closed lanes App attempt's FAILs never count, nor does a
  FAIL, read or not, uploaded before the newest capped-close record
  (`_attempt_floor`) on every one of those issues it is for, so each fresh
  attempt starts its own count;
- a counted FAIL at the head, under any pull request number: `verify:fail`,
  unless it is superseded (`_superseded`): every counted FAIL there is this
  pull request's, every counted pass there was created after them, and up to
  each pass's run's completion (`updated_at`, which a run's later activity
  only moves later) every body edit and issue connect or disconnect on the
  pull request is a trusted person's (one GraphQL read, RELINK_QUERY), with
  at least one from the first FAIL's creation for a pass that records other
  linked issues than each FAIL does (a relink), else at least one body edit
  from the last FAIL's creation (a body fix judged at the same head).
  A superseded FAIL still counts toward `max_fails`, and the passes then
  decide as below; the report's `supersededAtHead` names it, for pr-unblock
  to resolve that FAIL's fail-note threads. Any record, time or read that
  fails keeps `verify:fail`;
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
  another pull request, head or verdict keep `verify:earlier-fail`. So does
  a FAILed head of the same change, a merge-only head's included, unless its
  FAIL is superseded at its own head by the passes there (the rule above). Any
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
  for a new head;
- otherwise, on a pull request created more than `TOO_OLD_DAYS` ago,
  `verify:too-old`: its verdicts may have expired, and the lost-run
  reconciler re-runs the head's checks so pr-verify judges it, whose fresh
  pass clears this. A FAIL expired past the retention no longer counts
  toward the cap (owner decision 2026-11-01);
- otherwise `verify:missing`.

Only `verify:untrusted-spec` needs a human (`NEEDS_HUMAN`), who merges in
person: the spec's provenance is a trust boundary. Every other refusal holds
for the lanes (when a person is needed:
https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/loop-lane/README.md#when-work-stops-for-the-owner),
and enable-auto-merge.mjs shows
one that stands as a failing `pr-merge/unarmed` status. `verify:spec-changed`
and `verify:too-old` wait for the lanes to judge the head again.
`verify:repeated-fail` never clears (`VERIFY_FINAL`), so the gate never merges
such a pull request unattended: the pr-merge lane closes a lanes App one for a
fresh attempt (`capped_close`), and address-feedback and fix-ci start no
round on a pull request at `verify:repeated-fail` (pr-unblock
verify-cap.mjs). A
`verify:fail` or `verify:earlier-fail` only waits:
pr-feedback-dispatch.yml posts a FAIL's notes on the pull request as review
comments for an address-feedback round, whose push gives a head the verifier
judges again. Any read that fails refuses
(`verify:unreadable`). The repository's artifacts are listed once per
`Reader`, every artifact, and filtered on the name here: the API's name filter
matches whole names only, and a FAIL counts under any number and head. No
judgment uses a listing whose artifact ids, each counted once, are not
exactly GitHub's live `total_count` (`Reader._incremental`'s check). A whole
listing can skip the artifact at a page boundary when an earlier one expires
while it pages, and return one twice when an upload moves it down a page
(#10486). So a whole listing is deduplicated by id, added to the whole
listings read before it, and checked by a top-up read from the first page
(`Reader._complete_listing`); after `LISTING_READS` whole listings that never
hold the live count it refuses `verify:unreadable`, and after the first when
its top-up holds more than the count or does not read, or the incremental
read before it held more, which reading again cannot cure. The refresh before an allow reads the same way. A listing from
the API that fails once it began a whole listing is noted beside `LISTING_ENV`'s file
(`FAILED_LISTING_SUFFIX`), and every later Reader of the job refuses on it
without paging. The whole listing an over-count takes is noted there too
once it starts paging (`OVERCOUNT_FALLBACK_SUFFIX`), and a later Reader of the
job whose pages over-count refuses without another, whatever that listing's
outcome.

Carried reads. What an earlier run read is used only where it counts a FAIL
(a carried record counts the FAIL when it shows origin; any other answer from
it could turn the FAIL away, so it is read again), with one exception: the
artifact listing. A listing begun at most `LISTING_CARRY_MAX_AGE` ago (this
Reader's own, the run's saved one, or the one a scheduled or hand-started run
of main's pr-merge.yml saved and `LISTING_CARRY_ENV` names, which
.github/scripts/pr-merge/listing-carry.mjs fetches only from such a run whose
head is on main) is a base: `Reader._incremental` reads only the newest pages,
newest id first, down past the base's highest id until an artifact created
`LISTING_OVERLAP` before the base was read, and keeps the base's entries below
the lowest id those pages hold, less those expired or past `expires_at` by the
first page's `Date`. GitHub can delete an artifact up to an hour before its
`expires_at`, in no expiry order (`EARLY_DELETION_LEAD`), so when a listing
holds the live count or more and a kept entry expires within it, the pages
around the kept entries near expiry are read again and decide every id they
span, an id they omit by its own read (`Reader._near_expiry`), at a few pages
a group whatever the repository's total and at most `NEAR_EXPIRY_PAGE_CAP` a
listing. They are read on an exact count too: an entry deleted early can stand
in for a FAIL the pages skipped. An over-count those pages do not settle goes
to the one whole listing, an exact count they do not settle fails the
listing, a count they leave short goes to a whole listing with no wait, and a
page or id read still failing on a 5xx after `LISTING_WAITS` fails it as
transient. Such a listing
could hide a FAIL by leaving it out, so it is kept only when it holds exactly
the first page's `total_count`, GitHub's live count of the repository's
artifacts. Across 17 first-page reads on
2026-10-27 that count moved by exactly the uploads since the last read less
the artifacts whose `expires_at` had passed by the response's `Date`. Three
incremental listings that day each held exactly that count and every artifact
a full listing taken just after held, plus 0, 1 and 3 that the full listing
skipped at its page boundaries though they still existed. An artifact that
expires during the read can only make the counts differ. Pages that read
whole but hold any other count print one `LISTING_MISS_PREFIX` line on stderr
(the counts, the pages read, the base's age) and are read again on the same
base after each of `INCREMENTAL_WAITS`, up to `INCREMENTAL_READS` reads inside
one `LISTING_TIMEOUT_SECONDS`, or a caller's shorter limit, which ends the waits
that do not fit (a caller that sets `NO_INCREMENTAL_WAITS_ENV` to `1` skips the
waits and reads once); no wait or miss loosens the check, and after those
reads, on any failed read (a timeout, a 429
or a rate-limit 403 included, which are never read again), or with a base
that is missing, older or of another shape, it lists every page, checked the
same way. A carry forged to drop a FAIL must therefore
also hold a fabricated entry in its place to match the live count, and forging it already needs code
running in a scheduled or hand-started run of main's pr-merge.yml, whose merge
job holds the lanes App token. The completed review-lane runs the gates bind
lanes on are a second exception, outside this reader, under the same bar and
a live listing check (`babysit_gh.collect_lane_runs`).
pr-merge.yml builds one `Reader` per candidate gate run and names a file in
`LISTING_ENV`: a successful listing is saved there, and later candidates of
the run read it instead of paging again. A listing taken earlier in the run
can only lack later uploads. No judgment uses a listing, saved or in
memory, begun more than `LISTING_MAX_AGE` before it (an older one is read
again and saved), except the gate's own candidate's, which babysit_merge.py
judges `provisional` on the listing at hand at any age: an allow stands on
it until the gate would allow the candidate, when babysit_merge.py calls
`refresh()` and judges it again on a listing of its own, and so does a
refusal no later upload clears (`STANDING`: a FAIL at the head, the FAIL
cap). Any other refusal is judged again on a recent
listing, so none dequeues the candidate's queued entry on an older one. A
`verify:missing` that still stands on the run's saved listing reads the head's
two pass names by exact name (`Reader._late_pass`), two requests and no
listing, so a pass uploaded after that listing was read is seen in the same
run: it is judged with that listing in memory, and an allow stays provisional,
judged again on the gate's own listing. A
candidate the gate refuses for anything else lists nothing more; queued
entries are judged on a recent listing. A listing that got a 5xx or a fast network
error is read again after each of `LISTING_WAITS`, every read inside one
timeout in all; any other failure, a timeout, a 429 or a rate-limit 403
included, is not. The whole listings' timeout (`listing_timeout`) grows with
GitHub's live `total_count`, read from one page before them, up to
`LISTING_TIMEOUT_SECONDS` or what is left of the limit a caller kills the
reader at (`DEADLINE_ENV`, `listing_cap`); a count whose one whole listing
cannot fit refuses before paging, naming the pages, the budget and the
caller. A failed listing is never saved, and is kept as well, so one
outage refuses every entry of the gate run without paging again: it holds the
whole queue rather than merging blind. `evidence --shared-listing`
(enable-auto-merge.mjs's reader) takes the run's saved listing at any age and
allows on it without listing again, so its run lists once: ci-status's
merge-queue step runs this reader again, on a listing of its own, for a lanes
App pull request at the head it merges.

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
import urllib.parse
import zipfile
from collections.abc import Callable, Iterable
from dataclasses import asdict, dataclass, field, replace
from datetime import UTC, datetime, timedelta
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Any

import babysit_merge_policy as merge_policy
import babysit_postmerge as postmerge
import babysit_run_cache as run_cache
from babysit_classify import is_dependency_author
from babysit_gh import (
    fetch_paginated_api,
    flatten_paginated_items,
    gh_api_with_headers,
    gh_http_status,
    pull_request_commits_once,
)
from babysit_util import is_json_array, is_json_object, json_array, json_object

WORKFLOW_PATH = ".github/workflows/pr-verify.yml"
# The checks workflow pr-verify judges, and its ci-status step that runs only
# on a draft's event (resolve-pr.mjs `DRAFT_STEP`, `_draft_judged`).
CHECKS_WORKFLOW = "pr-require-checks.yml"
DRAFT_STEP = "Note a draft"
TRUSTED_ACTORS_PATH = ".github/standards/trusted-actors/trusted-actors.json"
TOKEN_ENV = "BABYSIT_VERIFY_GH_TOKEN"
LISTING_ENV = "BABYSIT_VERIFY_LISTING"
LISTING_CARRY_ENV = "BABYSIT_VERIFY_LISTING_CARRY"
# `1`: no wait between incremental reads (`no_incremental_waits`).
NO_INCREMENTAL_WAITS_ENV = "BABYSIT_VERIFY_NO_INCREMENTAL_WAITS"
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
# The listing's pages share one timeout (babysit_gh._run_pages), so it grows
# with the artifact count, not gh's per-call default: 7,522 artifacts took 76
# pages at 0.7 to 1 s a page on 2026-10-27, past that default's 60 s.
LISTING_PAGE_SECONDS = 1.0
# The pages a top-up reads at most: LISTING_OVERLAP's 2 h at the 255 uploads
# an hour seen 2026-10-27, plus one (judgment on that data).
LISTING_TOP_UP_PAGES = 7
# The cap on one listing's timeout: the incremental reads' timeout, and the
# most the whole listings' (`listing_timeout`) may take. Each fits the job and
# step timeouts its readers run under (ci-status 20 min, pr-merge's merge job
# 45 min, enable-auto-merge's step 18 min, the pr-unblock and feedback
# dispatchers 10 min); a caller that kills the reader sooner names its limit
# in `DEADLINE_ENV` (judgment).
LISTING_TIMEOUT_SECONDS = 300.0
# A caller that kills the reader after a limit of its own (enable-auto-merge.mjs
# 4 min, verify-cap.mjs 2 min) names it here in seconds, and itself in
# `CALLER_ENV`: every listing timeout is then at most what is left of it less
# `DEADLINE_MARGIN_SECONDS`, kept for the reads after the listing and the
# report, and a whole listing that cannot fit refuses before paging, naming the
# pages, the budget and the caller, rather than being killed with no reason.
DEADLINE_ENV = "BABYSIT_VERIFY_DEADLINE_SECONDS"
CALLER_ENV = "BABYSIT_VERIFY_CALLER"
DEADLINE_MARGIN_SECONDS = 15.0
# The start of a `verify:unreadable` detail when the listing does not fit in
# what the caller's limit leaves, before paging or after the limit runs out:
# pr-unblock verify-cap.mjs skips the round on it, for that run only, as on
# `SIBLING_UNREADABLE`, and no `FAILED_LISTING_SUFFIX` note is written.
DEADLINE_UNREADABLE = "the artifact listing does not fit in the caller's limit"
# The least a whole listing's timeout takes, gh's per-call default it
# replaced, unless the cap or a caller's limit leaves less.
LISTING_TIMEOUT_FLOOR = 60.0
# The most pages a whole listing and its top-up read inside the cap, at
# `LISTING_PAGE_SECONDS` a page: past it the whole listings refuse before
# paging.
LISTING_PAGES_CAP = (
    int(LISTING_TIMEOUT_SECONDS / LISTING_PAGE_SECONDS) - LISTING_TOP_UP_PAGES
)
# The oldest listing a judgment uses, saved or in memory, but for a
# provisional one's allow or `STANDING` refusal (`Reader.evidence`), unless
# `evidence --shared-listing` lifts it (`Reader.listing_max_age`).
LISTING_MAX_AGE = run_cache.MAX_AGE
# The incremental listing (`Reader._incremental`). The listing comes newest id
# first, but a lower id can be created after a higher one: across 6,835
# artifacts listed on 2026-10-27 (created 2026-10-16 to 10-27) the largest lead
# of a lower id's created_at over a higher id's was 58m49s, and each day's
# largest was 34 to 59 minutes. Paging stops past the base's highest id only
# at an artifact created `LISTING_OVERLAP` before the base was read, twice that
# lead (judgment on that data).
LISTING_OVERLAP = timedelta(hours=2)
# The oldest base an incremental listing starts from. Scheduled pr-merge runs
# come four times an hour (pr-merge.yml `cron`), and rotation.mjs asks at most
# 10 trusted runs (`MAX_RUNS`), about 2.5 hours of them, for the carried
# listing. At the most uploads seen in an hour on 2026-10-27 (255), a base this
# old and the overlap page at most about 1,300 artifacts, 13 pages, against 69
# for the whole listing that day (judgment on that data).
LISTING_CARRY_MAX_AGE = timedelta(hours=3)
LISTING_PAGE_SIZE = 100
# How far ahead of its `expires_at` GitHub may already have deleted a listed
# artifact. On 2026-11-01 a carried listing held 234 artifacts, all expiring
# 09:20 to 09:55Z, that three later listings lacked; the 60 of them read by id
# at 09:37Z each answered 404. A listing at 08:55Z already lacked ones
# expiring up to 59 minutes later, not in expiry order (an 09:13Z listing
# still held 8 of them). The 2026-10-27 counts in this module's docstring
# showed none. The cause is unverified; recheck on a `babysit-listing-miss`
# line whose `listed` exceeds `total_count`. Twice the largest lead seen
# (judgment on that data).
EARLY_DELETION_LEAD = timedelta(hours=2)
# The most pages `Reader._near_expiry` reads for one listing, its incremental
# read and top-up together; past it an over-count stands and goes to the one
# whole listing, and an exact count fails the listing. On the 2026-11-01
# carry behind #11903's refusal it read 12 pages; twice that (judgment on
# that data), at `LISTING_PAGE_SECONDS` a page, stays well inside
# verify-cap.mjs's 120 s limit and a fifth of that day's 133-page whole
# listing.
NEAR_EXPIRY_PAGE_CAP = 24
# The most artifacts `Reader._near_expiry` reads by id for one listing, its
# incremental read and top-up together: each id its pages did not show is
# dropped only on a 404 or an expired record. It drops at most the listing's
# surplus over the live count, which was 31 to 34 in the three over-counts
# behind #11903's refusal; the largest (judgment on that data). Past it an
# over-count stands and an exact count fails the listing. Both caps reset
# with each listing the Reader reads, as after `refresh()`;
# pr-require-checks.yml's cold_cost counts them once.
NEAR_EXPIRY_ID_READ_CAP = 34
# The waits between incremental reads on one base. A count that misses the
# live total can stay off for longer than an immediate re-read takes, while a
# page boundary settles; bounded waits let it settle before the reader pages
# every artifact. Together they stay well under the time of one whole listing
# and inside `LISTING_TIMEOUT_SECONDS`, and each `babysit-listing-miss` line
# shows whether they outlast the miss (judgment).
INCREMENTAL_WAITS = (15.0, 30.0)
# The incremental reads on one base before a whole listing: the first, then
# one after each wait.
INCREMENTAL_READS = 1 + len(INCREMENTAL_WAITS)


def no_incremental_waits() -> bool:
    """Whether `NO_INCREMENTAL_WAITS_ENV` is `1`: one incremental read, and a
    miss lists every page at once, with no `INCREMENTAL_WAITS`."""
    return os.environ.get(NO_INCREMENTAL_WAITS_ENV) == "1"


# The prefix of the stderr line `Reader._incremental` prints for each read
# that missed the live count, like babysit_gh's `babysit-gh-calls`.
LISTING_MISS_PREFIX = "babysit-listing-miss"
# The stderr line `Reader._late_pass` prints when its name reads find a pass
# the saved listing lacked: how many, and whether the judgment then allows.
LATE_PASS_PREFIX = "babysit-late-pass"


class _CountMissed:
    """`Reader._incremental`'s answer when its pages read whole but do not
    hold the live count: `COUNT_MISSED` (fewer), the one case read again on
    the same base, or `COUNT_OVER` (more, or any count once the pages near
    expiry were read again, except a top-up's exact count left short), which
    goes to the whole listings, since no wait removes an entry GitHub no
    longer counts."""


# Fewer than the live count: the pages skipped an artifact, which another
# whole listing can restore.
COUNT_MISSED = _CountMissed()
# More than the live count: the base holds artifacts GitHub no longer counts.
# A whole listing only adds ids to the union, so another cannot cure it: on
# 2026-11-01 08:00-09:00Z GitHub's count dropped artifacts up to an hour before
# the `expires_at` it listed, and every whole listing's top-up held 1 to 25
# more than the count (ci-status run 41287360293).
COUNT_OVER = _CountMissed()
# Beside `LISTING_ENV`'s file, a listing from the API that failed in this job
# after it began a whole listing, with its reason, unless it failed for want of
# a caller's time (`DEADLINE_UNREADABLE`) or on a 5xx or network error that
# outlasted its waits (`_Transient`), either of which a later Reader may not
# meet: the job's later Readers, in this process or another, refuse
# on it without paging again (pr-merge's merge job built one Reader per
# candidate, each paging three whole listings, 825 to 1,015 calls a run on
# 2026-11-01).
FAILED_LISTING_SUFFIX = ".failed"
# Beside `LISTING_ENV`'s file, created when an incremental over-count's whole
# listing starts paging and then holding that listing's outcome: a later Reader
# of the job whose pages over-count again refuses without another whole
# listing, whatever that outcome (a transient or caller-limit failure
# included, unlike `FAILED_LISTING_SUFFIX`), so an over-count costs one whole
# listing a job. A refusal before paging leaves it uncreated.
OVERCOUNT_FALLBACK_SUFFIX = ".overcount-fallback"


def _overcount_refusal(outcome: str) -> str:
    """A later Reader's refusal once the job's over-count whole listing was
    taken, starting with `DEADLINE_UNREADABLE` when that listing ran out of a
    caller's time, so verify-cap.mjs skips the round as it did for that one."""
    refusal = (
        "repository artifacts: the pages held more than GitHub's live "
        "artifact count, and this job already took its whole listing for that"
    )
    if outcome.startswith(DEADLINE_UNREADABLE):
        return f"{DEADLINE_UNREADABLE}: {refusal} ({outcome})"
    return refusal
# The whole listings `Reader._complete_listing` reads before it refuses. Of
# three whole listings read on 2026-10-27, two skipped live artifacts at page
# boundaries (1 and 3, a FAIL in each), and each skipped artifact was in every
# other whole listing: a second read restores a skip, a third is margin
# (judgment on that data). The reads and their top-ups share one
# `LISTING_TIMEOUT_SECONDS`, as one read did: what does not fit refuses.
LISTING_READS = 3
# How gh reports a request that never got an HTTP response: its own
# "error connecting to <host>" for a failed lookup, else Go's net/http error,
# or Go's JSON decoder error for a page body cut short.
NETWORK_ERRORS = (
    "error connecting to",
    "connection reset by peer",
    "connection refused",
    "i/o timeout",
    "tls handshake timeout",
    "unexpected eof",
    "unexpected end of json input",
)
# A whole listing cut short has already paged up to every artifact, so it is
# read once more at most, not after every wait (`Reader._read_listing`).
CUT_SHORT = "unexpected end of json input"
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
# The refusals only a person clears (when a person is needed:
# https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/loop-lane/README.md#when-work-stops-for-the-owner,
# with trust holds kept): an untrusted spec (provenance). Every other refusal
# holds for the lanes: it still refuses the merge, with no label. The one
# list the merge gate and enable-auto-merge.mjs (`needsHuman`) read;
# clear-escalations.mjs LANE_CAUSES.verdict shares nothing with it
# (lane-causes-person-codes.test.mjs).
NEEDS_HUMAN = (UNTRUSTED_SPEC,)
# The refusals that never clear for the pull request: the FAIL cap. An old
# pull request's `verify:too-old` clears on a fresh pass at its head (owner
# decision 2026-11-01). The pr-merge lane closes a lanes App pull request at
# one of them for a fresh attempt at its issue (`capped_close`, owner decision
# 2026-10-29), never adding a person's label.
VERIFY_FINAL = (REPEATED_FAIL,)
# `capped_close`'s reasons: a `VERIFY_FINAL` refusal, or review rounds the
# pr-unblock lane stopped as not converging (escalation-routes.json), whose
# lane-stopped comment (report-escalation.sh) opens with the marker below.
CLOSE_VERIFY = "verify"
NOT_CONVERGING = "feedback-not-converging"
CLOSE_REASONS = (CLOSE_VERIFY, NOT_CONVERGING)
LANE_STOPPED_FEEDBACK = "<!-- pr-unblock:lane-stopped activity=address-feedback -->"
# `_elsewhere`'s refusal detail when a FAIL run of another pull request for
# the same issue cannot be read: pr-unblock verify-cap.mjs reads it as the
# cap, failing closed.
SIBLING_UNREADABLE = "a FAIL run of a pull request for the same issue"
# The lanes App's capped-close record (`capped_close`): first line of the
# comment on the closed pull request and on its issue. On the issue it names
# the fresh attempt it started, or ` parked` when `merge.verify-cap-attempts`
# were spent. `_elsewhere` counts no FAIL uploaded before the newest one on
# each issue it is for (`_attempt_floor`); label-unblocked.mjs skips its
# closed-PR hand-off for it; write-issue.mjs passes it to the next attempt as
# data.
CAPPED_CLOSE_RE = re.compile(
    r"<!-- verify-capped-close pr=([1-9][0-9]{0,9}) heads=((?:[0-9a-f]{40},)*(?:[0-9a-f]{40})?)"
    r"(?: attempt=([0-9]+) of=([0-9]+)( parked)?)? -->"
)
# The refusals no upload after the listing clears (`Reader.evidence`): a
# counted FAIL at the head or the cap's FAILs stay counted whatever is
# uploaded later, as no pass clears them. A pass uploaded later can clear any other refusal, and a read may
# answer otherwise.
STANDING = (FAIL, REPEATED_FAIL)
ISSUE_FIELDS = (
    "number lastEditedAt repository{nameWithOwner} "
    "labels(first:100){totalCount nodes{name}} "
    "comments(first:100){totalCount nodes{databaseId createdAt updatedAt lastEditedAt "
    "body author{...actor} editor{...actor}}} "
    "closedByPullRequestsReferences(first:50,includeClosedPrs:true){totalCount "
    "nodes{number state author{...actor} repository{nameWithOwner}}}"
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
# The pull request's body edits and its issue connect and disconnect events,
# the ways its linked issues change at one head, read whole in one query
# (`_relinked_by_people`); resolve-pr.mjs RELINK_QUERY is the same text.
RELINK_QUERY = (
    "query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){"
    "pullRequest(number:$n){userContentEdits(first:100){totalCount "
    "nodes{editedAt editor{...actor}}} "
    "timelineItems(first:100,itemTypes:[CONNECTED_EVENT,DISCONNECTED_EVENT]){"
    "filteredCount nodes{... on ConnectedEvent{createdAt actor{...actor}} "
    "... on DisconnectedEvent{createdAt actor{...actor}}}}}}}"
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
    parent: int,
    part: int,
    parts: int,
    source: tuple[int, str] | None = None,
    scoped: bool = False,
) -> str:
    """admit.mjs splitChildHeader: the fixed header of part `part` of
    `parts` a size split files from issue `parent`, with admit.mjs
    splitSourceLine when `source` (id, updated_at) is given, and the
    target-subset wording when `scoped`."""
    also = " and intake's refinement comment on it" if source else ""
    copied = (
        f"The done-when lines below are copied from #{parent}{also} as written, "
        "and the Scope line names the targets this part covers."
        if scoped
        else f"The done-when below is copied from #{parent}{also} as written."
    )
    rows = [
        SPLIT_CHILD_MARKER,
        f"Part {part} of {parts} of #{parent}, split at intake (owner Q93). {copied}",
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
    scoped = rows[-1].startswith(SCOPE_PREFIX)
    header = f"{split_child_header(number, int(part[1]), int(part[2]), source, scoped)}\n"
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
    if lines[-1].startswith(SCOPE_PREFIX):
        names = lines.pop()[len(SCOPE_PREFIX) :].split(", ")
        texts = {task_text(line, task_list) for line in exact}
        if len(set(names)) != len(names) or not all(
            scope_target(name, texts) for name in names
        ):
            return None
    return body if lines and all(line in allowed for line in lines) else None


# admit.mjs SCOPE_PREFIX and scopeTarget: a target-subset split's last child
# line, and whether `name` can be one of its targets over the task lines.
SCOPE_PREFIX = "Scope: "
SCOPE_BANNED = re.compile(r"[,<>`@#\r\n]")


def task_text(line: str, task_list: str) -> str:
    """admit.mjs taskText: `line` without its indent and task-list marker."""
    return line.lstrip(JS_SPACE)[len(task_list) :]


def scope_target(name: str, texts: set[str]) -> bool:
    """2 to 100 characters, no comma, angle bracket, backtick, at sign,
    number sign or line break, no outer space, and verbatim text of one of
    `texts` (task_text). Length and outer space are JavaScript's (UTF-16 code units,
    and the JS_SPACE String.prototype.trim strips), since admit.mjs
    scopeTarget is the rule's one home."""
    units = len(name.encode("utf-16-le", "surrogatepass")) // 2
    return (
        2 <= units <= 100
        and name.strip(JS_SPACE) == name
        and not SCOPE_BANNED.search(name)
        and any(name in text for text in texts)
    )


# A run's standing: unreadable, foreign (not of verifier origin), origin (of
# verifier origin, not a completed success), or counted (both).
UNREAD, FOREIGN, ORIGIN, COUNTED = "unreadable", "foreign", "origin", "counted"
# The run cache's section of run records, and the fields `_run_state` reads.
RUN_SECTION = "run-record"
RECORD_SECTION = "fail-head-ref"
# What earlier pr-merge runs read, copied into this run's cache by
# .github/scripts/pr-merge/carry-run-cache.mjs from the last trusted runs'
# pr-merge-run-cache and pr-merge-verify-run-cache artifacts. Each is still
# used only where it counts a FAIL; any other answer is read from GitHub (the
# module docstring's "Carried reads", which names the listing's exception).
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
# `_origin` and carry-run-cache.mjs read only these objects' `full_name`.
REPOSITORY_FIELDS = ("repository", "head_repository")


def _run_fields(record: dict[str, Any]) -> dict[str, Any]:
    """The `RUN_FIELDS` of a run record, each repository kept as its name."""
    fields = {k: record.get(k) for k in RUN_FIELDS}
    for k in REPOSITORY_FIELDS:
        if is_json_object(fields[k]):
            fields[k] = {"full_name": fields[k].get("full_name")}
    return fields


class _Unreadable(Exception):
    pass


class _Transient(_Unreadable):
    """A failed read that may succeed if repeated."""


def _transient(detail: str) -> bool:
    """A 5xx, or a network error with no HTTP response. A rate limit is not:
    a fixed short wait outlasts neither a Retry-After nor an hourly reset, and
    more requests can extend a secondary limit."""
    status = gh_http_status(detail)
    if status is not None:
        return status >= 500
    return any(phrase in detail.casefold() for phrase in NETWORK_ERRORS)


def listing_pages(total_count: int) -> int:
    """The pages a whole listing of `total_count` artifacts reads."""
    return -(-total_count // LISTING_PAGE_SIZE)


def listing_seconds(total_count: int) -> float:
    """How long one whole listing of `total_count` artifacts and its top-up
    take at `LISTING_PAGE_SECONDS` a page."""
    return (listing_pages(total_count) + LISTING_TOP_UP_PAGES) * LISTING_PAGE_SECONDS


def listing_timeout(
    total_count: int, cap: float = LISTING_TIMEOUT_SECONDS
) -> float | None:
    """The whole listings' shared timeout for `total_count` artifacts: each of
    `LISTING_READS` whole listings and its top-up at `LISTING_PAGE_SECONDS` a
    page, at least `LISTING_TIMEOUT_FLOOR` and at most `cap`; None when even
    one does not fit in `cap` (past `LISTING_PAGES_CAP` pages at the default
    cap)."""
    each = listing_seconds(total_count)
    if each > cap:
        return None
    return min(cap, max(LISTING_TIMEOUT_FLOOR, LISTING_READS * each))


def _elapsed() -> float:
    """Seconds since this process started reading (`_STARTED`)."""
    return time.monotonic() - _STARTED


_STARTED = time.monotonic()


def listing_cap() -> tuple[float, str]:
    """The most one listing may take, and where that bound comes from:
    `LISTING_TIMEOUT_SECONDS`, or less when the caller's limit in
    `DEADLINE_ENV` leaves less after `DEADLINE_MARGIN_SECONDS`. A limit that
    is not a positive number is ignored."""
    cap = (LISTING_TIMEOUT_SECONDS, f"the {LISTING_TIMEOUT_SECONDS:.0f} s listing cap")
    try:
        limit = float(os.environ.get(DEADLINE_ENV, ""))
    except ValueError:
        return cap
    if not limit > 0 or limit == float("inf"):
        return cap
    left = limit - _elapsed() - DEADLINE_MARGIN_SECONDS
    if left >= cap[0]:
        return cap
    caller = os.environ.get(CALLER_ENV, "").strip()[:80] or "the caller"
    return max(left, 0.0), (
        f"the {max(left, 0.0):.0f} s left of {caller}'s {limit:.0f} s limit "
        f"(less {DEADLINE_MARGIN_SECONDS:.0f} s for the reads after it)"
    )


def _listing_sleep(seconds: float) -> None:
    time.sleep(seconds)


def _listing_clock() -> float:
    return time.monotonic()


def _wall_clock() -> datetime:
    return datetime.now(UTC)


def _recent(
    fetched_at: datetime | None, max_age: timedelta | None = LISTING_MAX_AGE
) -> bool:
    """A listing begun at most `max_age` ago (None: any time before now); a
    time with no zone, or one in the future, is not."""
    if fetched_at is None or fetched_at.tzinfo is None:
        return False
    age = _wall_clock() - fetched_at
    return timedelta(0) <= age and (max_age is None or age <= max_age)


def dependency_bot(user: Any) -> bool:
    """A REST user that is a Bot account with a dependency manager's login; a
    User named like one is not. resolve-pr.mjs `isDependencyManager` is its
    twin, and tests/test_verify_rules_sync.py compares them."""
    user = json_object(user)
    return user.get("type") == "Bot" and is_dependency_author(
        str(user.get("login") or "")
    )


def _heads(shas: set[str]) -> str:
    """The FAILed heads the cap counted, sorted, for the refusal to name."""
    return ", ".join(sorted(shas))


def _bot_login(identity: str | None) -> str:
    """`merge.agent-identity` as GraphQL names a Bot author: no `[bot]`."""
    return (identity or "").strip().lower().removesuffix("[bot]")


def _started_attempt(body: Any) -> int | None:
    """The pull request a capped-close record names when its first line is one
    that started a fresh attempt (`CAPPED_CLOSE_RE` naming an attempt, not
    parked); a parked or attempt-less record, None. `_spent` counts by it."""
    first = str(body or "").split("\n", 1)[0].rstrip("\r")
    match = CAPPED_CLOSE_RE.fullmatch(first)
    if match is None or match[3] is None or match[5]:
        return None
    return int(match[1])


def _by_lane(actor: Any, identity: str | None) -> bool:
    """Whether `actor` is the lanes App (`identity`, `merge.agent-identity`);
    no identity, never."""
    bot = _bot_login(identity)
    actor = json_object(actor)
    return (
        bool(bot)
        and actor.get("__typename") == "Bot"
        and str(actor.get("login") or "").lower() == bot
    )


def _capped_records(issue: Any, identity: str | None) -> list[Any]:
    """When each capped-close record on `issue` was written (`CAPPED_CLOSE_RE`,
    first line, parked or not), counting only a comment the lanes App
    (`identity`) wrote and nobody else edited: anyone can write the marker,
    and one that reset the cap would buy re-rolls. No identity, none."""
    return [
        node.get("createdAt")
        for node in map(
            json_object,
            json_object(json_object(issue).get("comments")).get("nodes") or [],
        )
        if _by_lane(node.get("author"), identity)
        and (not node.get("editor") or _by_lane(node.get("editor"), identity))
        and CAPPED_CLOSE_RE.fullmatch(
            str(node.get("body") or "").split("\n", 1)[0].rstrip("\r")
        )
    ]


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
    # A counted FAIL at the head that `_superseded` gave way; False when the
    # cap or a failed read decided first.
    superseded_at_head: bool = False

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
            "supersededAtHead": self.superseded_at_head,
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


def _linked_numbers(record: dict[str, Any]) -> frozenset[int]:
    """The issue numbers a verdict's `linked_issues` records, none included;
    raises `_Unreadable` for a list that is missing or an entry with no
    integer number."""
    issues = record.get("linked_issues")
    if not is_json_array(issues):
        raise _Unreadable("verdict records no linked issues")
    numbers = [json_object(i).get("number") for i in issues]
    if not all(isinstance(n, int) and not isinstance(n, bool) for n in numbers):
        raise _Unreadable("verdict records a linked issue with no number")
    return frozenset(numbers)


def _issue_numbers(record: dict[str, Any]) -> frozenset[int]:
    """The issue numbers a verdict's `linked_issues` records; raises
    `_Unreadable` for a list that is missing or empty, or for an entry with
    no integer number."""
    numbers = _linked_numbers(record)
    if not numbers:
        raise _Unreadable("verdict records no linked issues")
    return numbers


def _is_id(value: Any, run_id: int) -> bool:
    """`value` is the integer `run_id`; `True` equals 1 but is no id."""
    return type(value) is int and value == run_id


def _is_artifact_id(value: Any) -> bool:
    """An artifact id as the listing gives it: an integer, never a bool."""
    return isinstance(value, int) and not isinstance(value, bool)


def _listed_entry(item: Any) -> bool:
    """A listed artifact `Reader._incremental` can place: a positive id, a
    boolean `expired`, and a `created_at` and `expires_at` each present and
    null (GitHub's artifact schema marks both nullable) or a time with a
    zone."""
    return (
        is_json_object(item)
        and _is_artifact_id(item.get("id"))
        and item["id"] > 0
        and isinstance(item.get("expired"), bool)
        and all(
            key in item and (item[key] is None or _when(item[key]) is not None)
            for key in ("created_at", "expires_at")
        )
    )


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
    # The listing a trusted pr-merge run saved (`LISTING_CARRY_ENV`), which
    # listing-carry.mjs fetched, as a base for `_incremental`.
    carry_path: str | None = field(
        default_factory=lambda: os.environ.get(LISTING_CARRY_ENV) or None
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
    # The oldest listing a judgment uses; None (`evidence --shared-listing`)
    # takes the run's saved listing at any age.
    listing_max_age: timedelta | None = LISTING_MAX_AGE
    # `evidence` is judging on the listing at hand at any age.
    _any_age: bool = False
    _artifacts: list[dict[str, Any]] | None = None
    _fetched_at: datetime | None = None  # when `_artifacts` began to be read
    _saved: bool = False  # `_artifacts` came from `listing_path`
    _own: bool = False  # `refresh()` asked for a listing of this Reader's own
    # The last listing this Reader held and when it began to be read, kept
    # past `refresh()` as a base for `_incremental`.
    _base: tuple[datetime, list[dict[str, Any]]] | None = None
    # How the last listing was read from the API: "full" or "incremental".
    listing_mode: str | None = None
    _listing_error: str | None = None
    # When the whole listings of one `_complete_listing` must end.
    _read_deadline: float | None = None
    # A whole listing was paged, so a failure neither for want of a caller's
    # time nor transient is noted for the job.
    _whole_paged: bool = False
    # The last `_incremental_page` that read nothing failed on a 5xx, a
    # network error or a body cut short, after its waits.
    _page_transient: bool = False
    # This listing's pages held more than the live count, so it takes one
    # whole listing at most.
    _over_counted: bool = False
    # The pages `_near_expiry` read for this listing (`NEAR_EXPIRY_PAGE_CAP`).
    _near_expiry_reads: int = 0
    # The ids `_near_expiry` read for this listing (`NEAR_EXPIRY_ID_READ_CAP`).
    _artifact_reads: int = 0
    # This Reader took the job's over-count whole listing
    # (`OVERCOUNT_FALLBACK_SUFFIX`) and records its outcome there.
    _overcount_mine: bool = False
    _runs: dict[int, str] = field(default_factory=dict)
    _started: dict[int, Any] = field(default_factory=dict)
    _created: dict[int, Any] = field(default_factory=dict)
    # A pass run's `updated_at`, its completion (`_superseded`).
    _updated: dict[int, Any] = field(default_factory=dict)
    _digests: dict[str, str | None] = field(default_factory=dict)
    # `_draft_judged` answers by (head, FAIL run), and whether each checks
    # run ran DRAFT_STEP (`_draft_run`).
    _draft_judgments: dict[tuple[str, int], bool] = field(default_factory=dict)
    _draft_runs: dict[int, bool] = field(default_factory=dict)
    # The verifier run ids of each counted FAIL by (pull request, head), for
    # `_elsewhere`'s draft check.
    _fail_runs: dict[tuple[int, str], list[int]] = field(default_factory=dict)
    # Whether a pull request no issue lists counts (`_elsewhere`).
    _counted: dict[int, bool] = field(default_factory=dict)
    # Runs whose standing came from the run cache (`_run_state`).
    _shared_runs: set[int] = field(default_factory=set)
    _on_branch: dict[str, bool] = field(default_factory=dict)
    _records: dict[tuple[int, str], dict[str, Any]] = field(default_factory=dict)
    # Each judged pull request's counted FAILs by head: run id, artifact name
    # and id, for `fail_findings`.
    fail_artifacts: dict[int, dict[str, list[tuple[int, str, Any]]]] = field(
        default_factory=dict
    )
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
    # Each pull request's RELINK_QUERY answer, or {} for a failed read.
    _relinks: dict[int, dict[str, Any]] = field(default_factory=dict)
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
        """Every repository artifact, read at most `listing_max_age` before
        this judgment (from the run's saved listing when it is that recent): a
        failed read is kept too, so one outage refuses each later entry
        without paging again."""
        if self._listing_error is not None:
            raise _Unreadable(self._listing_error)
        max_age = None if self._any_age else self.listing_max_age
        if self._artifacts is not None and _recent(self._fetched_at, max_age):
            return self._artifacts
        saved = None if self._own else self._load_saved(self.listing_path, max_age)
        if saved is not None:
            self._fetched_at, self._artifacts = saved
            self._base = saved
            self._saved = True
            return self._artifacts
        failed = self._failed_listing()
        if failed is not None:
            self._listing_error = failed
            raise _Unreadable(failed)
        fetched_at = _wall_clock()
        self._over_counted, self._overcount_mine = False, False
        self._near_expiry_reads = self._artifact_reads = 0
        base = self._incremental_base()
        listing: list[dict[str, Any]] | _CountMissed | None = COUNT_MISSED
        # Only pages that read whole but missed the live count are read again,
        # after a wait, every read and wait inside one `LISTING_TIMEOUT_SECONDS`;
        # a failed read lists every page at once, as `_read_listing` decides.
        if base is not None:
            deadline = _listing_clock() + listing_cap()[0]
            for wait in (*INCREMENTAL_WAITS, None):
                listing = self._incremental(base, deadline, "incremental")
                if (
                    listing is not COUNT_MISSED
                    or wait is None
                    or no_incremental_waits()
                    or deadline - _listing_clock() - wait <= 0
                ):
                    break
                _listing_sleep(wait)
        self.listing_mode = "incremental"
        if not isinstance(listing, list):
            self.listing_mode = "full"
            taken = self._overcount_taken() if self._over_counted else None
            if taken is not None:
                self._listing_error = _overcount_refusal(taken)
                raise _Unreadable(self._listing_error)
            try:
                listing = self._complete_listing()
            except (_Unreadable, RuntimeError) as exc:
                self._listing_error = str(exc)
                if self._overcount_mine:
                    self._note_overcount(self._listing_error)
                if self._whole_paged and not isinstance(exc, _Transient):
                    self._note_failed_listing(self._listing_error)
                raise _Unreadable(self._listing_error) from exc
            if self._overcount_mine:
                self._note_overcount("listed")
        self._artifacts, self._fetched_at = listing, fetched_at
        self._base = (fetched_at, listing)
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

    def _load_saved(
        self, path: str | None, max_age: timedelta | None
    ) -> tuple[datetime, list[dict[str, Any]]] | None:
        """The listing saved at `path` and when it began to be read. A
        missing or malformed file, or one with no `fetchedAt` within
        `max_age`, is none, so the listing is read from the API instead."""
        if not path:
            return None
        try:
            saved = json_object(json.loads(Path(path).read_text(encoding="utf-8")))
            fetched_at = datetime.fromisoformat(saved["fetchedAt"])
        except (OSError, ValueError, KeyError, TypeError):
            return None
        listing = saved.get("artifacts")
        if (
            not _recent(fetched_at, max_age)
            or not is_json_array(listing)
            or not all(map(is_json_object, listing))
        ):
            return None
        return fetched_at, listing

    def _incremental_base(self) -> tuple[datetime, list[dict[str, Any]]] | None:
        """The newest whole listing begun at most `LISTING_CARRY_MAX_AGE` ago
        whose every entry `_listed_entry` takes: this Reader's own, the run's
        saved one, or the one a trusted run carried (`carry_path`)."""
        bases = [
            base
            for base in (
                self._base,
                self._load_saved(self.listing_path, LISTING_CARRY_MAX_AGE),
                self._load_saved(self.carry_path, LISTING_CARRY_MAX_AGE),
            )
            if base is not None
            and _recent(base[0], LISTING_CARRY_MAX_AGE)
            and all(_listed_entry(a) for a in base[1])
        ]
        return max(bases, key=lambda base: base[0], default=None)

    def _complete_listing(self) -> list[dict[str, Any]]:
        """Every repository artifact from whole listings: each read is added
        to the ones before it by id, and the union is kept only when the
        top-up `_incremental` reads on it holds GitHub's live `total_count`.
        A whole listing can skip an artifact at a page boundary when an
        earlier one expires while it pages, and the next read returns it.
        Raises `_Unreadable` when `LISTING_READS` reads never hold the live
        count, or at once when a top-up holds more than it (`COUNT_OVER`) or
        does not read, which no further whole listing can cure, so no
        judgment allows on a listing that may lack a FAIL, and
        before any read when the live count (`_live_count`) is too long to
        list in time (`listing_timeout`). A caller's limit (`DEADLINE_ENV`)
        bounds the count read too, and every refusal for want of its time
        starts with `DEADLINE_UNREADABLE`: one before paging, and one after
        it when the caller's limit cut the whole listings' timeout and too
        little of it is left for another wait (`LISTING_WAITS`)."""
        self._whole_paged = False
        cap, bound = listing_cap()
        callers = cap < LISTING_TIMEOUT_SECONDS
        if callers and cap <= 0:
            raise _Unreadable(f"{DEADLINE_UNREADABLE}: no time is left of {bound}")
        total = self._live_count(cap if callers else None)
        cap, bound = listing_cap()
        budget = listing_timeout(total, cap)
        if budget is None:
            spent = f"{DEADLINE_UNREADABLE}: " if cap < LISTING_TIMEOUT_SECONDS else ""
            raise _Unreadable(
                f"{spent}repository artifacts: {total} artifacts in "
                f"{listing_pages(total)} pages need {listing_seconds(total):.0f} s "
                f"for a whole listing and its top-up at {LISTING_PAGE_SECONDS:.0f} s "
                f"a page, past {bound}, so none is started"
            )
        full = listing_timeout(total, LISTING_TIMEOUT_SECONDS)
        # The job's over-count whole listing is taken only as paging starts:
        # a refusal before it leaves the next Reader free to list.
        if self._over_counted and not self._claim_overcount():
            raise _Unreadable(_overcount_refusal(self._overcount_taken() or ""))
        try:
            return self._whole_listings(budget)
        except (_Unreadable, RuntimeError) as exc:
            error, deadline = str(exc), self._read_deadline
            if (
                full is not None
                and budget < full
                and deadline is not None
                and deadline - _listing_clock() <= max(LISTING_WAITS)
                and not error.startswith(DEADLINE_UNREADABLE)
            ):
                raise _Unreadable(
                    f"{DEADLINE_UNREADABLE}: {error} (out of {bound})"
                ) from exc
            raise

    def _whole_listings(self, budget: float) -> list[dict[str, Any]]:
        """`_complete_listing`'s whole listings and their top-ups, all inside
        `budget`."""
        union: dict[int, dict[str, Any]] = {}
        deadline: float | None = None
        listing: list[dict[str, Any]] | _CountMissed | None = None
        reads = 0
        # An over-count takes one whole listing: another only adds ids.
        while reads < (1 if self._over_counted else LISTING_READS):
            reads += 1
            read_at = _wall_clock()
            self._whole_paged = True
            payload = self._read_listing(deadline, budget)
            deadline = self._read_deadline
            for item in flatten_paginated_items(
                payload, "repository artifacts", items_key="artifacts"
            ):
                if is_json_object(item) and _is_artifact_id(item.get("id")):
                    union[item["id"]] = item
                else:
                    raise _Unreadable("repository artifacts: an entry with no id")
            listing = self._incremental(
                (read_at, list(union.values())), deadline, "top-up"
            )
            if isinstance(listing, list):
                return listing
            if listing is not COUNT_MISSED:
                # Only a skip (`COUNT_MISSED`) can be restored by reading again.
                break
        if listing is COUNT_OVER:
            cause = "held more artifacts than"
        elif listing is None:
            cause = "could not be checked against"
        else:
            cause = "never held"
        noun = "listing" if reads == 1 else "listings"
        # A top-up page lost to a 5xx or network error is transient: not
        # noted for the job (`_note_failed_listing`).
        transient = listing is None and self._page_transient
        raise (_Transient if transient else _Unreadable)(
            f"repository artifacts: {reads} whole {noun} {cause} "
            "GitHub's live artifact count"
        )

    def _incremental(
        self,
        base: tuple[datetime, list[dict[str, Any]]] | None = None,
        deadline: float | None = None,
        stage: str = "incremental",
    ) -> list[dict[str, Any]] | _CountMissed | None:
        """Every repository artifact, as the base (`_incremental_base`) and
        the newest pages read now show them; when the pages read but the
        result does not hold the live count, `COUNT_MISSED` for fewer and
        `COUNT_OVER` for more; else None.

        The listing comes newest id first. Pages are read from the first
        until one holds an artifact at or below the base's highest id that
        was created `LISTING_OVERLAP` or more before the base was read (an
        undated one never stops it): every lower id was created before the
        base was read, so the base holds it.
        Those pages decide every id down to the lowest they hold, an id the
        base holds there and they do not (deleted, or an overwrite's old
        copy) included; below it the base's entries stand, less each one
        expired or past its `expires_at` by the first page's `Date` (one with
        no `expires_at` stands unless expired). A result that holds more than
        the live count, or exactly it while a kept entry is near expiry, has
        the ids around its kept entries near expiry decided by the pages that
        hold them now (`_near_expiry`); an exact count they leave unsettled
        gives None, since an entry deleted early may stand in for a FAIL. The
        result must hold exactly the first page's `total_count` artifacts,
        GitHub's live count: fewer gives `COUNT_MISSED`, which
        `_current_listing` reads again on the same base after a wait, and
        more, or any count once the pages near expiry were read (a top-up's
        exact count left short aside, which another whole listing can
        restore), gives `COUNT_OVER`, which goes to the whole listings (one,
        after an over-count), since no wait removes an entry GitHub no
        longer counts; either prints one
        `LISTING_MISS_PREFIX` line on stderr naming `stage`, the counts and
        the pages read. No base, an entry or page of another shape, a missing
        `Date`, or any failed read gives None (`_page_transient` says whether
        the failed read was a 5xx or network error).
        `base` replaces `_incremental_base` and `deadline` its own
        `LISTING_TIMEOUT_SECONDS` (`_complete_listing`'s top-up)."""
        self._page_transient = False
        if base is not None and not all(_listed_entry(a) for a in base[1]):
            return None
        base = base or self._incremental_base()
        if base is None:
            return None
        base_at, carried = base
        high = max((a["id"] for a in carried), default=0)
        floor = base_at - LISTING_OVERLAP
        if deadline is None:
            deadline = _listing_clock() + listing_cap()[0]
        fresh: dict[int, dict[str, Any]] = {}
        total: Any = None
        server_now: datetime | None = None
        page = 1
        while True:
            read = self._incremental_page(page, deadline)
            if read is None:
                return None
            body, headers = read
            items = body.get("artifacts")
            if not is_json_array(items) or not all(_listed_entry(a) for a in items):
                return None
            if page == 1:
                total = body.get("total_count")
                try:
                    server_now = parsedate_to_datetime(headers.get("date", ""))
                except (TypeError, ValueError):
                    return None
                if server_now.tzinfo is None or not _is_artifact_id(total):
                    return None
            for item in items:
                fresh.setdefault(item["id"], item)
            # Only a dated entry can show its id was created before the base.
            reached = any(
                a["id"] <= high
                and a["created_at"] is not None
                and _when(a["created_at"]) < floor
                for a in items
            )
            if reached or len(items) < LISTING_PAGE_SIZE:
                break
            page += 1
        if server_now is None:
            return None
        # A short page ends the listing: no id is left below it.
        lowest = min(fresh) if reached else 0
        kept = [
            a
            for a in carried
            if a["id"] < lowest
            and a["expired"] is False
            and (a["expires_at"] is None or _when(a["expires_at"]) > server_now)
        ]
        listing = sorted([*fresh.values(), *kept], key=lambda a: -a["id"])
        regions = 0
        over = len(listing) > total
        limit = server_now + EARLY_DELETION_LEAD
        near = len(listing) == total and any(
            a["expires_at"] is not None and _when(a["expires_at"]) <= limit
            for a in kept
        )
        if over or near:
            # GitHub can delete an artifact before its expires_at: read again
            # the pages around the kept entries near expiry. An exact count
            # can hide one there standing in for a FAIL the pages skipped.
            self._over_counted |= over
            reread = self._near_expiry(
                listing, len(fresh), len(listing) - total, server_now, deadline
            )
            if reread is None:
                return None
            listing, regions, settled = reread
            if near and not settled:
                # Unsettled, an exact count may still lack a FAIL.
                return None
        if len(listing) == total:
            return listing
        # Fewer than the live count: the pages skipped an artifact. More: the
        # base holds one GitHub no longer lists below the pages read.
        miss = {
            "stage": stage,
            "listed": len(listing),
            "total_count": total,
            "fresh": len(fresh),
            "kept": len(kept),
            "pages": page,
            "region_pages": regions,
            "base_age_seconds": round((server_now - base_at).total_seconds()),
        }
        print(
            f"{LISTING_MISS_PREFIX} {json.dumps(miss, sort_keys=True)}",
            file=sys.stderr,
            flush=True,
        )
        # Once the pages near expiry were read, no wait on this base settles
        # the count: the base still holds what they dropped. A top-up's exact
        # count left short goes to another whole listing, which can restore a
        # skip outside those pages.
        if over or len(listing) > total or (near and stage != "top-up"):
            return COUNT_OVER
        return COUNT_MISSED

    def _near_expiry(
        self,
        listing: list[dict[str, Any]],
        start: int,
        surplus: int,
        server_now: datetime,
        deadline: float,
    ) -> tuple[list[dict[str, Any]], int, bool] | None:
        """`listing` with the ids around its entries from `start` on that
        expire within `EARLY_DELETION_LEAD` of `server_now` decided by the
        pages that hold them now, the pages read, and whether every such
        entry was decided; None for a failed page read or an id read that
        stays transient past its waits.

        Such entries are grouped where they lie within a page of each other.
        Each group is read from the page its top entry would be on with
        `surplus` fewer entries above it, a page up at a time (at most
        `surplus // LISTING_PAGE_SIZE + 2` pages above that one) until a page
        reaches its top id, then down until a page reaches its bottom id or
        ends the listing; those pages add every id they hold. An id of
        `listing` from the lowest to the highest they hold that they do not
        show is dropped only when its own read answers 404 or shows it
        expired (`_artifact_gone`): pages read one at a time skip the entry at
        a boundary when an artifact above it is deleted between reads (#10486).
        A group it cannot bracket within those pages, a read past
        `NEAR_EXPIRY_PAGE_CAP` or `NEAR_EXPIRY_ID_READ_CAP` for this listing,
        or an id read with any other answer that is not transient leaves
        `listing` as it was, unsettled."""
        size = LISTING_PAGE_SIZE
        limit = server_now + EARLY_DELETION_LEAD
        near = [
            i
            for i in range(start, len(listing))
            if listing[i]["expires_at"] is not None
            and server_now < _when(listing[i]["expires_at"]) <= limit
        ]
        groups: list[list[int]] = []
        for i in near:
            if groups and i - groups[-1][1] <= size:
                groups[-1][1] = i
            else:
                groups.append([i, i])
        decided: dict[int, dict[str, Any]] = {}
        spans: list[tuple[int, int]] = []
        reads = 0
        for first, last in groups:
            top, bottom = listing[first]["id"], listing[last]["id"]
            page = max(0, first - surplus) // size + 1
            ups = 1 + surplus // size + 1
            downs = (last - first) // size + 2 + surplus // size + 1
            seen: dict[int, dict[str, Any]] = {}
            ended = False
            while True:
                if self._near_expiry_reads >= NEAR_EXPIRY_PAGE_CAP:
                    return listing, reads, False
                read = self._incremental_page(page, deadline)
                reads += 1
                self._near_expiry_reads += 1
                if read is None:
                    return None
                items = read[0].get("artifacts")
                if not is_json_array(items) or not all(map(_listed_entry, items)):
                    return None
                if not seen and (not items or max(a["id"] for a in items) < top):
                    if page == 1 or ups == 0:
                        break
                    ups -= 1
                    page -= 1
                    continue
                seen.update((a["id"], a) for a in items)
                if len(items) < size:
                    ended = True
                    break
                if min(a["id"] for a in items) <= bottom or downs == 0:
                    break
                downs -= 1
                page += 1
            if not seen or (not ended and min(seen) > bottom):
                return listing, reads, False
            spans.append((0 if ended else min(seen), max(seen)))
            decided.update(seen)
        gone: set[int] = set()
        for a in listing:
            if a["id"] in decided or not any(
                low <= a["id"] <= high for low, high in spans
            ):
                continue
            if self._artifact_reads >= NEAR_EXPIRY_ID_READ_CAP:
                return listing, reads, False
            self._artifact_reads += 1
            answer = self._artifact_gone(a["id"], deadline)
            if answer is None:
                # A transient answer fails the read, as a lost page does.
                return None if self._page_transient else (listing, reads, False)
            if answer:
                gone.add(a["id"])
        merged = {a["id"]: a for a in listing if a["id"] not in gone} | decided
        return sorted(merged.values(), key=lambda a: -a["id"]), reads, True

    def _artifact_gone(self, artifact_id: int, deadline: float) -> bool | None:
        """Whether GitHub no longer holds the artifact: True on a 404 or an
        expired record, False on a live one, None for any other answer, with
        `_page_transient` set when it was transient past its waits
        (`_api_object`)."""
        read = self._api_object(
            f"repos/{self.repo}/actions/artifacts/{artifact_id}", deadline
        )
        if not isinstance(read, tuple):
            return True if read == 404 else None
        record = read[0]
        if record.get("id") != artifact_id or not isinstance(
            record.get("expired"), bool
        ):
            return None
        return record["expired"]

    def _incremental_page(
        self, page: int, deadline: float
    ) -> tuple[dict[str, Any], dict[str, str]] | None:
        """One incremental page's body and headers (`_api_object`); None for
        any failure."""
        read = self._api_object(
            f"repos/{self.repo}/actions/artifacts"
            f"?per_page={LISTING_PAGE_SIZE}&page={page}",
            deadline,
        )
        return read if isinstance(read, tuple) else None

    def _api_object(
        self, path: str, deadline: float
    ) -> tuple[dict[str, Any], dict[str, str]] | int | None:
        """The JSON object at `path` and its headers, read again after
        `LISTING_WAITS` while time is left when the read fails transiently
        (`_transient`) or its body is cut short; the HTTP status of any other
        failed answer (None without one), or None once the waits or the time
        run out, with `_page_transient` set when the last read was one of
        those."""
        self._page_transient = False
        for wait in (*LISTING_WAITS, None):
            left = deadline - _listing_clock()
            if left <= 0:
                return None
            try:
                proc, headers = gh_api_with_headers(
                    ["api", path],
                    timeout_seconds=left,
                    env_overrides=self._env(),
                )
            except (RuntimeError, ValueError, OSError):
                self._page_transient = False
                return None
            if proc.returncode == 0:
                try:
                    body = json_object(json.loads(proc.stdout))
                except ValueError:
                    pass  # A body cut short: read again.
                else:
                    self._page_transient = False
                    return body, headers
            else:
                detail = (proc.stderr or "").strip()
                if not _transient(detail):
                    self._page_transient = False
                    return gh_http_status(detail)
            self._page_transient = True
            if wait is None or deadline - _listing_clock() - wait <= 0:
                return None
            _listing_sleep(wait)
        return None

    def _failed_path(self) -> Path | None:
        """Where a failed whole listing is noted beside `listing_path`, for
        the job's later Readers (`FAILED_LISTING_SUFFIX`)."""
        if not self.listing_path:
            return None
        return Path(f"{self.listing_path}{FAILED_LISTING_SUFFIX}")

    def _failed_listing(self) -> str | None:
        """Why an earlier Reader of this job could not list, if one noted it."""
        path = self._failed_path()
        if path is None:
            return None
        try:
            text = path.read_text(encoding="utf-8").strip()
        except OSError:
            return None
        return text or "repository artifacts: an earlier listing in this job failed"

    def _overcount_path(self) -> Path | None:
        """Where the job's over-count whole listing is noted beside
        `listing_path` (`OVERCOUNT_FALLBACK_SUFFIX`)."""
        if not self.listing_path:
            return None
        return Path(f"{self.listing_path}{OVERCOUNT_FALLBACK_SUFFIX}")

    def _overcount_taken(self) -> str | None:
        """How the job's over-count whole listing ended ("" while it pages),
        or None when no Reader of the job has taken it."""
        path = self._overcount_path()
        if path is None:
            return None
        try:
            return path.read_text(encoding="utf-8").strip()
        except OSError:
            return None

    def _claim_overcount(self) -> bool:
        """Whether this Reader may take the job's one whole listing for an
        over-count, noting it taken. With no `listing_path` there is no job
        to note it for, so it may; a failed write leaves the next Reader to
        take it too."""
        path = self._overcount_path()
        if path is None:
            return True
        try:
            with path.open("x", encoding="utf-8"):
                pass
        except FileExistsError:
            return False
        except OSError:
            return True
        self._overcount_mine = True
        return True

    def _note_overcount(self, outcome: str) -> None:
        """Best effort: how the job's over-count whole listing ended, so a
        later Reader's refusal carries a caller-limit refusal's prefix."""
        path = self._overcount_path()
        if path is not None:
            with contextlib.suppress(OSError):
                path.write_text(outcome, encoding="utf-8")

    def _note_failed_listing(self, error: str) -> None:
        """Best effort: a failed write leaves the next Reader to list. A
        refusal for want of one caller's time (`DEADLINE_UNREADABLE`) is not
        noted: a later caller may have the time."""
        path = self._failed_path()
        if path is not None and not error.startswith(DEADLINE_UNREADABLE):
            with contextlib.suppress(OSError):
                note = f"{error} (an earlier listing in this job)"
                path.write_text(note, encoding="utf-8")

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

    def _live_count(self, timeout: float | None = None) -> int:
        """GitHub's live `total_count` of the repository's artifacts, from one
        one-artifact page, read again after each of `LISTING_WAITS` on a 5xx
        or a fast network error; `_Unreadable` when it does not read. A
        `timeout` bounds every read and wait, else each read keeps gh's
        default."""
        label = "repository artifact count"
        args = ["api", f"repos/{self.repo}/actions/artifacts?per_page=1"]
        deadline = None if timeout is None else _listing_clock() + timeout
        left = timeout
        for wait in (*LISTING_WAITS, None):
            try:
                page = self._actions(args, label, left)
                break
            except _Transient:
                if wait is None or (
                    deadline is not None and deadline - _listing_clock() - wait <= 0
                ):
                    raise
                _listing_sleep(wait)
                if deadline is not None:
                    left = deadline - _listing_clock()
        total = json_object(page).get("total_count")
        if not _is_artifact_id(total) or total < 0:
            raise _Unreadable(f"{label}: no total_count")
        return total

    def _read_listing(
        self, deadline: float | None = None, budget: float = LISTING_TIMEOUT_SECONDS
    ) -> Any:
        """The listing payload, read again after a 5xx or a fast network
        error while time is left: every page, read and wait fits in
        `budget`, so a retry adds no time to the run's worst
        case. A read cut short (`CUT_SHORT`) is read once more, and that
        read's failure refuses. A `deadline` set by an earlier read is kept;
        this read's is saved as `_read_deadline`."""
        args = [
            "api",
            f"repos/{self.repo}/actions/artifacts?per_page=100",
            "--paginate",
            "--slurp",
        ]
        if deadline is None:
            deadline = _listing_clock() + budget
            timeout = budget
        else:
            timeout = deadline - _listing_clock()
            if timeout <= 0:
                raise _Unreadable("repository artifacts: no time left to list")
        self._read_deadline = deadline
        for wait in LISTING_WAITS:
            try:
                return self._actions(args, "repository artifacts", timeout)
            except _Transient as exc:
                if deadline - _listing_clock() - wait <= 0:
                    raise
                _listing_sleep(wait)
                # Recomputed after the sleep, which may return late.
                timeout = deadline - _listing_clock()
                if timeout <= 0:
                    raise
                if CUT_SHORT in str(exc).casefold():
                    break
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
            # read instead ("Carried reads" in the module docstring, which
            # also states the listing's exception and its guard).
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
            self._updated[run_id] = record.get("updated_at")
            self._created[run_id] = record.get("created_at")
            run_cache.put(RUN_SECTION, key, _run_fields(record))
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

    def _tip(self, branch: str) -> str:
        """`branch`'s tip SHA (`merge_policy.base_tip`), so no tag of the same
        name stands in for it; `_Unreadable` when it does not resolve."""
        owner, _, name = self.repo.partition("/")
        try:
            return merge_policy.base_tip(owner, name, branch)
        except merge_policy.PolicyReadError as exc:
            raise _Unreadable(str(exc)) from exc

    def _read_trusted_list(self) -> None:
        """Read the trusted list at the branch's tip once: its human ids, and
        every login's id (`_lane_app_id`), each shared by the run's gate
        processes."""
        key = f"{self.repo}@{self.branch}"
        at = run_cache.now()
        tip = self._tip(self.branch)
        listing = json_object(
            _read(
                [
                    "api",
                    "-H",
                    "Accept: application/vnd.github.raw",
                    f"repos/{self.repo}/contents/{TRUSTED_ACTORS_PATH}?ref={tip}",
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
                tip = self._tip(default)
                rules = json_object(
                    _read(
                        [
                            "api",
                            "-H",
                            "Accept: application/vnd.github.raw",
                            f"repos/{self.repo}/contents/{ADMISSION_RULES_PATH}?ref={tip}",
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

    def fail_findings(self, number: int) -> list[dict[str, Any]]:
        """What each counted FAIL of the pull request the last judgment of it
        counted wrote: head, run, and the verdict file's summary and notes
        (`_record`), one entry per artifact, heads sorted. A record that
        cannot be read (an expired artifact, a failed download) is named by
        its run with `unreadable`, never skipped. A judgment that never
        reached the listing left none, so the pull request's own FAILs are
        read from the listing here (`_own_fails`)."""
        if number not in self.fail_artifacts:
            self.fail_artifacts[number] = self._own_fails(number)
        found: list[dict[str, Any]] = []
        for sha, artifacts in sorted(self.fail_artifacts[number].items()):
            for run_id, name, artifact_id in artifacts:
                entry: dict[str, Any] = {"head": sha, "run": run_id}
                # Only a run of verified origin has its record read: any
                # other could carry anyone's text.
                if self._run_state(run_id, shared=True) not in (ORIGIN, COUNTED):
                    entry["unreadable"] = "run origin not verified"
                    found.append(entry)
                    continue
                try:
                    record = self._record(run_id, name, artifact_id)
                except _Unreadable as exc:
                    entry["unreadable"] = str(exc)
                else:
                    notes = record.get("notes")
                    entry["summary"] = str(record.get("summary") or "")
                    entry["notes"] = (
                        [str(n) for n in notes] if is_json_array(notes) else []
                    )
                found.append(entry)
        return found

    def _own_fails(self, number: int) -> dict[str, list[tuple[int, str, Any]]]:
        """The pull request's own FAIL artifacts in the listing, by head,
        whose runs are not of another origin and did not judge a run that
        started on the draft (`_draft_judged`); one whose run cannot be read
        is kept, so `fail_findings` names it unreadable."""
        own: dict[str, list[tuple[int, str, Any]]] = {}
        for item in map(json_object, self._listing()):
            match = verdict_name(str(item.get("name") or ""))
            run_id = json_object(item.get("workflow_run")).get("id")
            if (
                item.get("expired") is not False
                or not match
                or int(match[1]) != number
                or match[3] in PASSES
                or not isinstance(run_id, int)
                or isinstance(run_id, bool)
                or self._run_state(run_id, shared=True) == FOREIGN
                or self._draft_judged(match[2], run_id)
            ):
                continue
            own.setdefault(match[2], []).append(
                (run_id, str(item.get("name")), item.get("id"))
            )
        return own

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
        self,
        number: int,
        head: str,
        pr: dict[str, Any] | None = None,
        *,
        provisional: bool = False,
    ) -> Evidence:
        """The judgment at `head`, on a listing begun at most
        `listing_max_age` before it. A `provisional` one, whose allow the
        caller judges again on a listing of its own before acting on it
        (babysit_merge.py `refresh()`), takes the listing at hand at any age:
        an allow or a refusal no later upload clears (`STANDING`) stands on
        it, and any other refusal on an older listing is judged again on a
        recent one. A provisional `verify:missing` still on the run's saved
        listing reads this pull request's pass names (`_late_pass`)."""
        judged = self._judge(number, head, pr, any_age=provisional)
        if not provisional:
            return judged
        if (
            judged.refusal is not None
            and judged.refusal not in STANDING
            and self._fetched_at is not None
            and not _recent(self._fetched_at, self.listing_max_age)
        ):
            judged = self._judge(number, head, pr, any_age=False)
        if judged.refusal == MISSING and self._saved:
            return self._late_pass(number, head, pr, judged)
        return judged

    def _late_pass(
        self, number: int, head: str, pr: dict[str, Any] | None, missing: Evidence
    ) -> Evidence:
        """The provisional judgment at `head` with any pass uploaded since the
        run's saved listing was read, else `missing`. Only the exact names
        write-verdict.mjs `artifactName` writes for a pass at the head are
        read, `pr-verify-<pr>-<head>-<verdict>` for each of `PASSES`, one
        `?name=` read each, as resolve-pr.mjs `judged` looks them up; no
        listing. The writer names no pass with the head-ref digest yet; when
        it moves to one, such a pass leaves `missing` here until this reads
        that name too. An unexpired one the saved listing lacks is judged
        with it, in memory: an allow stands only as a provisional one, so
        babysit_merge.py `refresh()` judges it again on a listing of the
        gate's own, which must hold the live count. A refusal on it, a failed
        or partial read, or no such artifact leaves `missing`, and nothing is
        noted for the job."""
        held = {a.get("id") for a in self._artifacts or ()}
        transient = self._page_transient
        deadline = _listing_clock() + listing_cap()[0]
        found: list[dict[str, Any]] = []
        try:
            for verdict in PASSES:
                name = f"pr-verify-{number}-{head}-{verdict}"
                read = self._api_object(
                    f"repos/{self.repo}/actions/artifacts"
                    f"?name={name}&per_page={LISTING_PAGE_SIZE}",
                    deadline,
                )
                if not isinstance(read, tuple):
                    return missing
                items = read[0].get("artifacts")
                if (
                    not is_json_array(items)
                    or read[0].get("total_count") != len(items)
                    or not all(map(_listed_entry, items))
                ):
                    return missing
                found += [
                    a
                    for a in items
                    if a.get("name") == name
                    and a["expired"] is False
                    and a["id"] not in held
                ]
        finally:
            self._page_transient = transient
        if not found:
            return missing
        listing = self._artifacts or []
        self._artifacts = [*found, *listing]
        try:
            late = self._judge(number, head, pr, any_age=True)
        finally:
            self._artifacts = listing
        print(
            f"{LATE_PASS_PREFIX} "
            + json.dumps(
                {"pr": number, "found": len(found), "allowed": late.refusal is None}
            ),
            file=sys.stderr,
        )
        return late if late.refusal is None else missing

    def _judge(
        self, number: int, head: str, pr: dict[str, Any] | None, *, any_age: bool
    ) -> Evidence:
        self._any_age = any_age
        try:
            return self._evidence(number, head, pr)
        except (_Unreadable, postmerge.PostMergeReadError) as exc:
            return Evidence(UNREADABLE, head, (), 0, str(exc))
        finally:
            self._any_age = False

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
        too_old = now - created > timedelta(days=TOO_OLD_DAYS)
        head_ref = str(json_object(pr.get("head")).get("ref") or "")
        commits = self._commits(number, head) | {head}
        verdicts: list[Verdict] = []
        passes: list[tuple[int, str, Any]] = []
        # This pull request's passes at its other heads, uncounted, read only
        # to judge whether one superseded a FAIL there (`_superseded`).
        other_passes: dict[str, list[tuple[int, str, Any]]] = {}
        # Counted FAILs by head: run id, artifact name and id (`_wider_pass`).
        fail_artifacts: dict[str, list[tuple[int, str, Any]]] = {}
        ignored = 0
        unreadable: str | None = None
        # FAILs of verifier origin by pull request number, and the numbers
        # with a FAIL whose run cannot be read, for the cap's other pull
        # requests (`_elsewhere`).
        failed_by_pr: dict[int, set[str]] = {}
        unread_prs: dict[int, list[Any]] = {}
        # The same by each issue a FAIL's name carries (`named_issues`).
        failed_by_issue: dict[int, set[tuple[int, str]]] = {}
        unread_issues: dict[int, set[int]] = {}
        # When each of those FAILs was uploaded (`created_at`), by pull
        # request and head, for the cap's fresh-attempt floor (`_elsewhere`).
        fail_times: dict[tuple[int, str], list[Any]] = {}
        self._fail_runs = {}
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
                        unread_prs.setdefault(int(digits or "0"), []).append(
                            item.get("created_at")
                        )
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
                if pr_n == number and sha != head:
                    other_passes.setdefault(sha, []).append(
                        (run_id, name, item.get("id"))
                    )
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
                unread_prs.setdefault(pr_n, []).append(item.get("created_at"))
                for issue in named_issues(match):
                    unread_issues.setdefault(issue, set()).add(pr_n)
                if tied:
                    unreadable = unreadable or f"run of {name}"
                else:
                    ignored += 1
                continue
            failed_by_pr.setdefault(pr_n, set()).add(sha)
            fail_times.setdefault((pr_n, sha), []).append(item.get("created_at"))
            self._fail_runs.setdefault((pr_n, sha), []).append(run_id)
            for issue in named_issues(match):
                failed_by_issue.setdefault(issue, set()).add((pr_n, sha))
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
            if self._draft_judged(sha, run_id):
                ignored += 1
                continue
            verdicts.append(Verdict(sha, verdict, run_id))
            fail_artifacts.setdefault(sha, []).append((run_id, name, item.get("id")))
        fails = [v for v in verdicts if v.verdict == "fail"]
        failed = {v.sha for v in fails}
        self.fail_artifacts[number] = fail_artifacts

        def superseded(sha: str) -> bool:
            at = (
                passes
                if sha == head
                else [
                    p
                    for p in other_passes.get(sha, [])
                    if self._run_state(p[0]) == COUNTED
                ]
            )
            return self._superseded(number, sha, fail_artifacts, at)

        refusal: str | None
        detail = unreadable
        head_superseded = False
        if len(failed) >= self.max_fails:
            refusal = REPEATED_FAIL
            detail = f"fails at {len(failed)} heads ({_heads(failed)}), the cap is {self.max_fails}"
        elif head in failed and not (head_superseded := superseded(head)):
            # A FAIL here gets a fix round, so the cap counts the other pull
            # requests for its issues first: a round past it cannot merge.
            _, elsewhere = self._elsewhere(
                number,
                failed_by_pr,
                unread_prs,
                failed_by_issue,
                unread_issues,
                fail_times,
            )
            refusal = FAIL
            if len(failed | elsewhere) >= self.max_fails:
                refusal = REPEATED_FAIL
                detail = (
                    f"fails at {len(failed | elsewhere)} heads of this and other "
                    f"pull requests for its issues ({_heads(failed | elsewhere)}), "
                    f"the cap is {self.max_fails}"
                )
        elif fails and (
            not self._passes_follow(fails, passes)
            or not self._change_differs(
                head,
                failed,
                lambda sha: (
                    self._wider_pass(number, sha, fail_artifacts, passes)
                    or superseded(sha)
                ),
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
                number,
                failed_by_pr,
                unread_prs,
                failed_by_issue,
                unread_issues,
                fail_times,
            )
            if len(failed | elsewhere) >= self.max_fails:
                refusal = REPEATED_FAIL
                detail = (
                    f"fails at {len(failed | elsewhere)} heads of this and other "
                    f"pull requests for its issues ({_heads(failed | elsewhere)}), "
                    f"the cap is {self.max_fails}"
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
        elif too_old:
            refusal = TOO_OLD
            detail = f"created {created.isoformat()}"
        else:
            refusal = MISSING
        return Evidence(
            refusal, head, tuple(verdicts), ignored, detail, head_superseded
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
        unread_prs: dict[int, list[Any]],
        failed_by_issue: dict[int, set[tuple[int, str]]],
        unread_issues: dict[int, set[int]],
        fail_times: dict[tuple[int, str], list[Any]],
    ) -> tuple[dict[Any, Any], set[str]]:
        """The live issues (`_closing_issues`: closing, or the `Refs:` one),
        and the heads of counted FAILs of the other pull requests for them
        that still count (`_counts`): those that close one of them, and those
        whose FAIL names carry one of them (`named_issues`: a `Refs:` pull
        request's FAILs count only so), from the listing already read. A
        merged pull request's or a closed lanes App attempt's FAILs never
        count, so each fresh attempt starts its own count (owner decision
        2026-10-29), and of any other only those uploaded after the newest
        capped-close record (`_attempt_floor`) on at least one issue they are
        for: a record on one issue ends no attempt at another. A pull request
        no issue lists has its own state read, once per `Reader` and only when
        one of its FAILs could count, a failed read raising `_Unreadable`. A
        FAIL of a counted one whose run cannot be read (`unread_prs`, by
        upload time) raises `_Unreadable` (`SIBLING_UNREADABLE`) unless it
        predates the record on every issue that pull request is for."""
        live = self._closing_issues(number)
        closers = {n: self._closers(issue) for n, issue in live.items()}
        floors = {n: self._attempt_floor(issue) for n, issue in live.items()}

        def after(stamps: Iterable[Any], issue: int) -> bool:
            # A time that cannot be read counts the FAIL.
            floor = floors[issue]
            for stamp in stamps:
                try:
                    if floor is None or postmerge._time(stamp) > floor:
                        return True
                except postmerge.PostMergeReadError:
                    return True
            return False

        def drafted(pr_n: int, sha: str) -> bool:
            # Every FAIL there judged a run that started on the draft.
            run_ids = self._fail_runs.get((pr_n, sha), [])
            return bool(run_ids) and all(self._draft_judged(sha, r) for r in run_ids)

        heads: dict[int, set[str]] = {}
        for_issues: dict[int, set[int]] = {}
        for n in live:
            named = failed_by_issue.get(n, set())
            for pr_n, sha in named | {
                (p, sha) for p in closers[n] for sha in failed_by_pr.get(p, set())
            }:
                if after(fail_times.get((pr_n, sha), [None]), n) and not drafted(
                    pr_n, sha
                ):
                    heads.setdefault(pr_n, set()).add(sha)
            for pr_n in {
                *closers[n],
                *unread_issues.get(n, set()),
                *(p for p, _ in named),
            }:
                for_issues.setdefault(pr_n, set()).add(n)
        unread = {
            pr_n
            for pr_n, issues in for_issues.items()
            if any(after(unread_prs.get(pr_n, []), n) for n in issues)
        }
        listed = {p: on for states in closers.values() for p, on in states.items()}
        others = {p for p, counted in listed.items() if counted}
        for other in sorted((heads.keys() | unread) - listed.keys() - {number}):
            if other not in self._counted:
                try:
                    pull = merge_policy.pull_request(self.repo, other)
                except merge_policy.PolicyReadError as exc:
                    raise _Unreadable(f"#{other} state: {exc}") from exc
                user = json_object(pull.get("user"))
                self._counted[other] = self._counts(
                    "MERGED" if pull.get("merged_at") else str(pull.get("state")).upper(),
                    {
                        "__typename": user.get("type"),
                        "login": _bot_login(str(user.get("login") or "")),
                    },
                )
            if self._counted[other]:
                others.add(other)
        others.discard(number)
        if others & unread:
            raise _Unreadable(SIBLING_UNREADABLE)
        return live, set().union(*(heads.get(n, set()) for n in others))

    def _counts(self, state: Any, author: Any) -> bool:
        """Whether a pull request in `state` (`OPEN`, `CLOSED` or `MERGED`)
        by `author` still counts toward another's cap: unless it merged, or
        was a lanes App attempt that closed, whoever closed it. Closing any
        other pull request resets nothing, or its author could re-roll the
        verifier by closing and reopening."""
        return state == "OPEN" or (
            state == "CLOSED" and not _by_lane(author, self.agent_identity)
        )

    def _closers(self, issue: Any) -> dict[int, bool]:
        """Each pull request in this repository that closes `issue`, and
        whether it still counts (`_counts`)."""
        return {
            node["number"]: self._counts(node.get("state"), node.get("author"))
            for node in map(
                json_object,
                json_object(issue.get("closedByPullRequestsReferences")).get("nodes"),
            )
            if json_object(node.get("repository")).get("nameWithOwner") == self.repo
            and type(node.get("number")) is int
        }

    def _attempt_floor(self, issue: Any) -> datetime | None:
        """The newest capped-close record on `issue` the lanes App wrote and
        nobody else edited (`_capped_records`): the only close that ends every
        attempt so far, as the lane closes its own pull requests for other
        reasons and anyone can open and close one that names the issue. FAILs
        uploaded before it judged an attempt that is over. A time that cannot
        be read is left out, so it lowers nothing."""
        times = []
        for stamp in _capped_records(issue, self.agent_identity):
            try:
                times.append(postmerge._time(stamp))
            except postmerge.PostMergeReadError:
                continue
        return max(times, default=None)

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

    def _draft_judged(self, sha: str, run_id: int) -> bool:
        """Whether the FAIL verifier run `run_id` left at `sha` judged a
        checks run that started while the pull request was a draft, so it
        counts as no FAIL (resolve-pr.mjs `draftJudgments`, the same rule):
        every pull_request run of CHECKS_WORKFLOW at `sha` created before the
        verifier run ran DRAFT_STEP. pr-verify starts when a checks run
        completes, so the run it judged is among them. The verifier run's
        creation is read fresh (`_fresh_created`), so no carried record can
        turn a FAIL away. A failed read, a list cut short, a time that cannot
        be read, or no run before it answers False: the FAIL counts."""
        key = (sha, run_id)
        if key not in self._draft_judgments:
            try:
                self._draft_judgments[key] = self._judged_a_draft(sha, run_id)
            except _Unreadable:
                self._draft_judgments[key] = False
        return self._draft_judgments[key]

    def _judged_a_draft(self, sha: str, run_id: int) -> bool:
        listed = json_object(
            self._actions(
                [
                    "api",
                    f"repos/{self.repo}/actions/workflows/{CHECKS_WORKFLOW}/runs"
                    f"?head_sha={sha}&event=pull_request&per_page=100",
                ],
                f"checks runs at {sha[:12]}",
            )
        )
        runs = listed.get("workflow_runs")
        if not is_json_array(runs) or listed.get("total_count") != len(runs):
            return False
        created = self._fresh_created(run_id)
        if created is None:
            return False
        before: list[Any] = []
        for checks in map(json_object, runs):
            try:
                if postmerge._time(checks.get("created_at")) < created:
                    before.append(checks.get("id"))
            except postmerge.PostMergeReadError:
                return False
        return bool(before) and all(self._draft_run(i) for i in before)

    def _draft_run(self, run_id: Any) -> bool:
        """Whether checks run `run_id`'s latest ci-status job lists DRAFT_STEP
        as `success` (a draft's run) or `skipped` (not), a condition that
        reads the run's own event, which a re-run keeps. The jobs API can list
        a finished job's steps empty or cut short (pr-require-checks.yml's
        ci-status notes), so anything else raises `_Unreadable`: jobs not read
        whole, no one ci-status job, the step not listed once, or no such
        conclusion (resolve-pr.mjs `draftRun`)."""
        if type(run_id) is not int:
            return False
        if run_id not in self._draft_runs:
            listed = json_object(
                self._actions(
                    [
                        "api",
                        f"repos/{self.repo}/actions/runs/{run_id}/jobs"
                        "?filter=latest&per_page=100",
                    ],
                    f"jobs of run {run_id}",
                )
            )
            jobs = listed.get("jobs")
            if not is_json_array(jobs) or listed.get("total_count") != len(jobs):
                raise _Unreadable(f"the jobs of run {run_id} could not be read whole")
            ci = [j for j in map(json_object, jobs) if j.get("name") == "ci-status"]
            listed_steps = json_array(ci[0].get("steps")) if len(ci) == 1 else []
            steps = [
                step
                for step in map(json_object, listed_steps)
                if step.get("name") == DRAFT_STEP
            ]
            conclusion = steps[0].get("conclusion") if len(steps) == 1 else None
            if conclusion not in ("success", "skipped"):
                raise _Unreadable(
                    f"run {run_id}'s draft state: ci-status lists no conclusion "
                    f"for {DRAFT_STEP}"
                )
            self._draft_runs[run_id] = conclusion == "success"
        return self._draft_runs[run_id]

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

    def _superseded(
        self,
        number: int,
        sha: str,
        fail_artifacts: dict[str, list[tuple[int, str, Any]]],
        passes: list[tuple[int, str, Any]],
    ) -> bool:
        """The pull request's linked issues or body changed at `sha` after its
        FAIL there, by trusted people only, and it passed there since: every
        counted FAIL at `sha` records this pull request, head and verdict,
        every counted pass at `sha` was created after them (`_passes_follow`),
        and up to each pass's run's completion (`updated_at`: the run read the
        spec after it started) only trusted people edited the body or
        connected or disconnected an issue (`_relinked_by_people`): at least
        once from the first FAIL's creation, for a pass whose linked issues
        differ from each FAIL's (a relink), else at least one body edit from
        the last FAIL's creation (a body fix, resolve-pr.mjs `body-edited`).
        A superseded FAIL still counts toward `max_fails`. A record, time or
        read that fails is False."""
        fails = fail_artifacts.get(sha, [])
        if not passes or not fails:
            return False
        try:
            # The records first, then the run times and the edits, read once
            # per pull request.
            judged: set[frozenset[int]] = set()
            for run_id, name, artifact in fails:
                record = self._record(run_id, name, artifact)
                if (
                    record.get("pr") != number
                    or record.get("head_sha") != sha
                    or record.get("verdict") != "fail"
                ):
                    return False
                judged.add(_linked_numbers(record))
            # Whether each pass judged the FAILs' linked issues again.
            same: list[bool] = []
            for run_id, name, artifact in passes:
                record = self._record(run_id, name, artifact)
                if record.get("pr") != number or record.get("head_sha") != sha:
                    return False
                same.append(_linked_numbers(record) in judged)
            if not self._passes_follow(
                [Verdict(sha, "fail", r) for r, _, _ in fails], passes
            ):
                return False
            created = [self._fresh_created(r) for r, _, _ in fails]
            if None in created:
                return False
            first = min(c for c in created if c)
            last = max(c for c in created if c)
            if not all(
                self._relinked_by_people(
                    number,
                    last if body else first,
                    postmerge._time(self._updated.get(run_id)),
                    body_edit=body,
                )
                for (run_id, _, _), body in zip(passes, same, strict=True)
            ):
                return False
        except (_Unreadable, postmerge.PostMergeReadError):
            return False
        return True

    def _relinked_by_people(
        self, number: int, since: datetime, until: datetime, *, body_edit: bool = False
    ) -> bool:
        """At least one body edit or issue connect or disconnect on the pull
        request falls from `since` to `until`, ends included (a body edit,
        under `body_edit`), and every one there was a trusted person's
        (`_trusted_actor`): never the lanes App or another Bot, nor an actor
        GitHub cannot name. None there means the link changed some way this
        read cannot see. RELINK_QUERY is read once per pull request; a failed
        read, a list cut short or an act with no readable time is False
        (resolve-pr.mjs `relinkedByPeople`, `editedByPeople`)."""
        if number not in self._relinks:
            try:
                self._relinks[number] = json_object(
                    self._graphql(RELINK_QUERY, number, "relink events").get(
                        "pullRequest"
                    )
                )
            except _Unreadable:
                self._relinks[number] = {}
        pull = self._relinks[number]
        edits = json_object(pull.get("userContentEdits"))
        events = json_object(pull.get("timelineItems"))
        if not (
            is_json_array(edits.get("nodes"))
            and edits.get("totalCount") == len(edits["nodes"])
            and is_json_array(events.get("nodes"))
            # totalCount counts every timeline item; filteredCount the kinds asked.
            and events.get("filteredCount") == len(events["nodes"])
        ):
            return False
        acts = [
            (node.get("editedAt"), node.get("editor"), True)
            for node in map(json_object, edits["nodes"])
        ] + [
            (node.get("createdAt"), node.get("actor"), False)
            for node in map(json_object, events["nodes"])
        ]
        try:
            inside = [
                (json_object(actor), edit)
                for at, actor, edit in acts
                if since <= postmerge._time(at) <= until
            ]
            return any(edit or not body_edit for _, edit in inside) and all(
                self._trusted_actor(actor.get("__typename"), actor.get("databaseId"))
                for actor, _ in inside
            )
        except (_Unreadable, postmerge.PostMergeReadError):
            return False

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
    *,
    humans: Callable[[], frozenset[int]] = frozenset,
) -> tuple[str, bool, bool] | None:
    """Why pr-merge's gate would hold the pull request on its risk score,
    whether only a person clears it (`babysit_risk.person_reasons`), and
    whether a clean whole review of the head would clear it
    (`babysit_whole_review.wanted`, as the gate asks it), or None: `babysit_risk.score` and `holding` over the inputs the gate builds
    (`babysit_merge.score_unattended`) for a lane pull request, with `config`
    the base's tightened by the default branch head's. So the review lanes' evidence (an open CRITICAL
    security finding, a review not bound to the head), a symlink, submodule
    or other non-regular mode, a high path, the manifest review, the trust
    gate and the cost review all hold, the cost review lifted only by the
    owner's decision on the pull request or its linked `issue`
    (`merge_policy.cost_decision`). A read that fails holds. A configured or
    floor high path is lifted, as ci-status lifts it, by a trusted person's
    approval of the head (`merge_policy.path_lifters` over the pull request's
    reviews and `humans`, the trusted list's people), or by their approval of
    an earlier head carried over base merges (`merge_policy.carried_lifters`);
    an aliasing path keeps
    its hold, and a review or trusted list that does not read lifts nothing."""
    # Imported here: babysit_merge imports this module.
    import babysit_merge  # noqa: PLC0415
    import babysit_risk  # noqa: PLC0415
    import babysit_whole_review  # noqa: PLC0415

    try:
        identity = config.agent_identity
        if not identity:
            return "unreadable: no agent identity", False, False
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
            config.floor,
        )
        files = merge_policy.with_contents(repo, pr, files)
        private = json_object(json_object(pr.get("base")).get("repo")).get("private")
        risk_input = babysit_risk.RiskInput(
            files=files,
            files_complete=complete,
            files_capped=merge_policy.files_capped(pr),
            max_changed_lines=config.max_changed_lines,
            high_paths=config.denied_paths,
            lanes=lanes,
            public=True if private is False else None,
            pulumi_dirs=merge_policy.pulumi_dirs_at(repo, pr),
            base_sha=json_object(pr.get("base")).get("sha"),
            floor_rows=config.floor_paths,
            high_floor=config.high_path_floor,
            path_holds=config.path_holds,
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
        return f"unreadable: {type(exc).__name__}: {exc}", False, False
    held = babysit_risk.holding(risk)
    paths = [
        r
        for r in held
        if r.code.startswith("high-path:") and r.code != babysit_risk.UNSAFE_PATH_CODE
    ]
    if paths:
        head = str(json_object(pr.get("head")).get("sha") or "")
        try:
            reviews = fetch_paginated_api(
                f"repos/{repo}/pulls/{number}/reviews?per_page=100",
                f"{repo}#{number} reviews",
            )
            trusted = humans()
            # An approval of an earlier head carries over merges that bring
            # only the base's changes.
            lifted = bool(merge_policy.path_lifters(reviews, trusted, head)) or bool(
                merge_policy.carried_lifters(
                    repo,
                    pr,
                    reviews,
                    trusted,
                    list(config.denied_paths),
                    floor=config.floor,
                )
            )
        except Exception:  # noqa: BLE001 - an unread approval lifts nothing
            lifted = False
        if lifted:
            held = [r for r in held if r not in paths]
    text = "; ".join(f"{r.code}: {r.detail}" for r in held)
    # Scored without the high paths an approval lifted.
    kept = tuple(r for r in risk.reasons if r in held or r not in paths)
    whole = babysit_whole_review.wanted(None, replace(risk, reasons=kept), lanes)
    return (text, bool(babysit_risk.person_reasons(held)), whole) if text else None


def lane_queue(
    repo: str, branch: str, number: int, head: str, limit: int
) -> dict[str, Any]:
    """The merge queue's failed-check removals of `head` and whether pr-merge's
    gate would enqueue it again under `merge.max-queue-ejections` `limit`
    (`babysit_merge.queue_ejection_hold`), with the gate's marked comment when
    the cap refuses. A read that fails refuses as the gate's unreadable hold,
    with no comment, and names why in `readError`; a failed runs read keeps
    the refusal, with no comment and its error in `commentError`."""
    # Imported here: babysit_merge imports this module.
    import babysit_merge  # noqa: PLC0415

    try:
        queue = babysit_merge.read_merge_queue(repo, number)
    except Exception as exc:  # noqa: BLE001 - any doubt holds, as the gate's
        queue = {"readError": f"{type(exc).__name__}: {exc}"}
    read_error = queue.get("readError") or None
    count = None if read_error else queue.get("failedEjections")
    count = count if isinstance(count, int) else None
    if count is None and read_error is None:
        read_error = "the merge queue's timeline items could not be counted"
    refusal, comment, comment_error = babysit_merge.queue_ejection_hold(
        repo, branch, number, head, count, limit
    )
    return {
        "failedEjections": count,
        "limit": limit,
        "refusal": refusal,
        "comment": comment,
        "readError": str(read_error) if read_error else None,
        "commentError": comment_error,
    }


# Kept verifier answers (`--answers-in`, `--answers-out`), one per pull
# request, so enable-auto-merge.mjs need not read again what has not moved.
# An entry is written only from a fresh read whose answer is a refusal of a
# kind that holds until an input moves (`answer_cacheable`), never an allow,
# so a kept answer can delay an arm but never cause one; armed pull requests
# are never served one. It is served only while the inputs the key hashes
# hash the same (`_answer_key`) and it has not expired (the `expiresAt`
# `_kept_report` sets). An input the key does not hash (an edit to a review's
# body or an inline comment, who resolved a thread) can only keep a refusal
# standing until it expires: a delay, never an arm.
# pr-merge.yml keeps the file as the pr-merge-verify-answers artifact of a
# scheduled or hand-started run of main (.github/scripts/pr-merge/
# verify-answers.mjs); a file of another version, repository or code is no
# file, and any read behind the key that fails is no key: both read in full.
SHADOW, SERVE = "shadow", "serve"
ANSWERS_VERSION = 1
ANSWER_TTL = timedelta(minutes=60)
# The refusals that stand until an input the key hashes moves.
STABLE_REFUSALS = (
    MISSING,
    FAIL,
    EARLIER_FAIL,
    REPEATED_FAIL,
    SPEC_CHANGED,
    UNTRUSTED_SPEC,
    TOO_OLD,
)
# The first or second line of a comment enable-auto-merge.mjs writes itself
# (its refusal and pin, the gate's queue-ejection comment): its edits are the
# lane's own writes, so they move no key.
SELF_MARKERS = (
    "<!-- babysit-merge-risk -->",
    "<!-- babysit-merge-pin sha=",
    "<!-- babysit-merge-queue-ejections -->",
)
PROBE_ISSUE_FIELDS = (
    "number repository{nameWithOwner} updatedAt lastEditedAt "
    "timelineItems(first:1){totalCount updatedAt} "
    "labels(first:100){totalCount nodes{name}} "
    "comments(first:100){totalCount nodes{databaseId updatedAt}} "
    "closedByPullRequestsReferences(first:1,includeClosedPrs:true){totalCount}"
)
PROBE_QUERY = (
    "query($o:String!,$r:String!,$n:Int!,$h:GitObjectID!,$ta:String!,$ar:String!)"
    "{repository(owner:$o,name:$r){pullRequest(number:$n){headRefOid baseRefOid "
    "createdAt title body timelineItems(first:1){totalCount} "
    "comments(last:100){totalCount nodes{databaseId updatedAt body "
    "author{__typename login}}} "
    "reviewThreads(first:100){totalCount nodes{isResolved "
    "comments(first:1){totalCount}}} "
    f"closingIssuesReferences(first:10){{totalCount nodes{{{PROBE_ISSUE_FIELDS}}}}}}}"
    "head:object(oid:$h){... on Commit{checkSuites(first:100){totalCount "
    "nodes{databaseId updatedAt status conclusion}}}} "
    "trusted:object(expression:$ta){oid} admission:object(expression:$ar){oid}}}"
)
PROBE_REFS_QUERY = (
    "query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){"
    f"issueOrPullRequest(number:$n){{__typename ... on Issue{{{PROBE_ISSUE_FIELDS}}}}}}}}}"
)


class _ProbeFailed(Exception):
    """A read behind the key failed or came back cut: no key, a full read."""


def answer_cacheable(report: Any) -> bool:
    """Whether a fresh answer may be kept: a refusal of a stable kind (the
    verdict's, a link refusal, a risk hold, a queue-ejection refusal), and
    nothing in it unreadable. An allow never is."""
    if not is_json_object(report) or "cached" in report or "cache" in report:
        return False
    text = json.dumps(report).casefold()
    if "unreadable" in text or "could not be read" in text:
        return False
    refusal = report.get("refusal")
    if refusal == INELIGIBLE:
        return isinstance(report.get("ineligible"), str)
    if refusal is not None:
        return refusal in STABLE_REFUSALS
    if report.get("ineligible") is not None:
        return False
    if isinstance(report.get("reviews"), str):
        return True
    queue = json_object(report.get("queue"))
    return (
        "reviews" in report
        and isinstance(queue.get("refusal"), str)
        and queue.get("readError") is None
        and queue.get("commentError") is None
    )


def answer_kind(report: Any) -> str:
    """A short name for what an answer decides, for the shadow log line."""
    if not is_json_object(report):
        return "none"
    if isinstance(report.get("ineligible"), str):
        return "ineligible"
    if isinstance(report.get("refusal"), str):
        return str(report["refusal"])
    if isinstance(report.get("reviews"), str):
        return "reviews"
    if isinstance(json_object(report.get("queue")).get("refusal"), str):
        return "queue"
    return "allow"


def _decides(report: dict[str, Any]) -> tuple[Any, ...]:
    """The fields enable-auto-merge.mjs decides and notes on (verifyHold,
    verifyClears, ejectionHold, decide's whole-review request), a risk hold's
    text aside."""
    queue = json_object(report.get("queue"))
    return (
        report.get("refusal"),
        report.get("needsHuman"),
        report.get("ineligible"),
        isinstance(report.get("reviews"), str),
        report.get("reviewsPerson"),
        report.get("wholeReviewWanted"),
        queue.get("refusal"),
    )


def _code_digest() -> str:
    """The reader's code: every module beside this one. A deploy that
    changes any of them invalidates every kept answer."""
    digest = hashlib.sha256()
    for path in sorted(Path(__file__).resolve().parent.glob("*.py")):
        digest.update(path.name.encode("utf-8") + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def _when(value: Any) -> datetime | None:
    try:
        when = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return when if when.tzinfo is not None else None


def load_answers(
    path: str | None, repo: str, code: str, now: datetime
) -> dict[int, dict[str, Any]]:
    """The unexpired entries of the answers file at `path`, by pull request.
    A missing or malformed file, or one of another version, repository or
    code, is none; an entry of another shape is dropped."""
    if not path:
        return {}
    try:
        data = json_object(json.loads(Path(path).read_text(encoding="utf-8")))
    except Exception:  # noqa: BLE001 - nested past the recursion limit included
        return {}
    entries = data.get("entries")
    if (
        data.get("version") != ANSWERS_VERSION
        or data.get("repo") != repo
        or data.get("code") != code
        or not is_json_object(entries)
    ):
        return {}
    kept: dict[int, dict[str, Any]] = {}
    for number, entry in entries.items():
        entry = json_object(entry)
        expires = _when(entry.get("expiresAt"))
        if (
            ARTIFACT_ID_RE.fullmatch(str(number))
            and isinstance(entry.get("key"), str)
            and _when(entry.get("readAt")) is not None
            and expires is not None
            and now < expires
            and is_json_object(entry.get("report"))
        ):
            kept[int(number)] = entry
    return kept


def _write_answers(
    path: str | None,
    seed: dict[int, dict[str, Any]],
    repo: str,
    code: str,
    now: datetime,
    number: int,
    entry: dict[str, Any] | None,
) -> None:
    """Best effort: `path`'s entries (this run's earlier pull requests), else
    `seed`'s (the last run's), with `number`'s set to `entry` or dropped."""
    if not path:
        return
    target = Path(path)
    entries = load_answers(path, repo, code, now) if target.exists() else dict(seed)
    entries.pop(number, None)
    if entry is not None:
        entries[number] = entry
    payload = {
        "version": ANSWERS_VERSION,
        "repo": repo,
        "code": code,
        "entries": {str(n): e for n, e in sorted(entries.items())},
    }
    tmp = target.with_name(f"{target.name}.{os.getpid()}.tmp")
    with contextlib.suppress(OSError):
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(json.dumps(payload), encoding="utf-8")
        os.replace(tmp, target)


def _probe_graphql(query: str, variables: dict[str, str | int]) -> dict[str, Any]:
    """The probe query's `repository`; any error or missing part fails."""
    args = ["api", "graphql", "-f", f"query={query}"]
    for name, value in variables.items():
        args += ["-F" if isinstance(value, int) else "-f", f"{name}={value}"]
    try:
        proc = postmerge.gh_capture(args)
        payload = json_object(json.loads(proc.stdout))
    except (RuntimeError, ValueError, OSError) as exc:
        raise _ProbeFailed(str(exc)) from exc
    repository = json_object(payload.get("data")).get("repository")
    if proc.returncode != 0 or payload.get("errors") or not is_json_object(repository):
        raise _ProbeFailed("the probe did not read")
    return repository


def _whole(connection: Any, what: str) -> list[Any]:
    """A connection's nodes, failing when it was cut."""
    connection = json_object(connection)
    nodes = connection.get("nodes")
    if not is_json_array(nodes) or connection.get("totalCount") != len(nodes):
        raise _ProbeFailed(f"{what} came back cut")
    return nodes


def _issue_print(issue: Any) -> dict[str, Any]:
    issue = json_object(issue)
    return {
        "number": issue.get("number"),
        "repo": json_object(issue.get("repository")).get("nameWithOwner"),
        "updatedAt": issue.get("updatedAt"),
        "lastEditedAt": issue.get("lastEditedAt"),
        "timeline": issue.get("timelineItems"),
        "labels": sorted(
            str(json_object(n).get("name"))
            for n in _whole(issue.get("labels"), "labels")
        ),
        "comments": [
            [json_object(c).get("databaseId"), json_object(c).get("updatedAt")]
            for c in _whole(issue.get("comments"), "issue comments")
        ],
        "closedBy": json_object(issue.get("closedByPullRequestsReferences")).get(
            "totalCount"
        ),
    }


def _self_written(comment: dict[str, Any], bot: str | None) -> bool:
    """A comment enable-auto-merge.mjs wrote itself (`SELF_MARKERS`)."""
    author = json_object(comment.get("author"))
    if bot is None or author.get("__typename") != "Bot" or author.get("login") != bot:
        return False
    lines = str(comment.get("body") or "").split("\n", 2)[:2]
    return any(line.rstrip("\r").startswith(SELF_MARKERS) for line in lines)


def _answer_key(
    args: argparse.Namespace, reader: Reader
) -> tuple[str, datetime, datetime | None]:
    """The key of the inputs the read takes (the pull request, its issues,
    the verdict artifacts, the head's PASS runs, the config, rung and trust
    files; not review-body or inline-comment edits, nor who resolved a
    thread), when the pull request turns too old (`TOO_OLD_DAYS`), and the
    earliest expiry of a PASS artifact at the head (None without one).
    Raises `_ProbeFailed`, or any error of a read behind it."""
    parts: dict[str, Any] = {
        "version": ANSWERS_VERSION,
        "args": [
            args.repo,
            args.branch,
            args.number,
            args.head,
            args.base_sha,
            args.max_fails,
            args.rung,
            args.lane_link,
            args.lane_reviews,
            args.lane_queue,
            args.shared_listing,
        ],
    }
    bot: str | None = None
    try:
        if args.base_sha is not None:
            base = merge_policy.config_at(args.repo, args.base_sha)
            if base.error:
                raise _ProbeFailed(base.error)
            config = merge_policy.with_default_branch(args.repo, base)
            parts["config"] = asdict(config)
            bot = (config.agent_identity or "").removesuffix("[bot]") or None
        listing = reader.listing()
        # `_task_list` reads the rules at the default branch, whatever the base.
        default = merge_policy._default_branch(args.repo, shared=True)
    except (merge_policy.PolicyReadError, RuntimeError) as exc:
        raise _ProbeFailed(str(exc)) from exc
    owner, _, name = args.repo.partition("/")
    repository = _probe_graphql(
        PROBE_QUERY,
        {
            "o": owner,
            "r": name,
            "n": args.number,
            "h": args.head,
            # By full ref: a bare name resolves as git does, a tag first.
            "ta": f"refs/heads/{args.branch}:{TRUSTED_ACTORS_PATH}",
            "ar": f"refs/heads/{default}:{ADMISSION_RULES_PATH}",
        },
    )
    pull = json_object(repository.get("pullRequest"))
    if pull.get("headRefOid") != args.head:
        raise _ProbeFailed("the head moved")
    created = _when(pull.get("createdAt"))
    if created is None:
        raise _ProbeFailed("no creation time")
    closing = json_object(pull.get("closingIssuesReferences"))
    issues = _whole(closing, "closing issues")
    if not issues:
        named, _ = merge_policy.refs_issue(pull.get("body"))
        if named is not None:
            node = json_object(
                _probe_graphql(
                    PROBE_REFS_QUERY, {"o": owner, "r": name, "n": named}
                ).get("issueOrPullRequest")
            )
            issues = [node] if node.get("__typename") == "Issue" else []
    comments = json_object(pull.get("comments"))
    parts["pull"] = {
        "base": pull.get("baseRefOid"),
        "created": pull.get("createdAt"),
        "title": hashlib.sha256(str(pull.get("title")).encode("utf-8")).hexdigest(),
        "body": hashlib.sha256(str(pull.get("body")).encode("utf-8")).hexdigest(),
        "timeline": json_object(pull.get("timelineItems")).get("totalCount"),
        "comments": comments.get("totalCount"),
        "said": [
            [c.get("databaseId")]
            if _self_written(c, bot)
            else [c.get("databaseId"), c.get("updatedAt")]
            for c in map(json_object, _whole(comments, "pull request comments"))
        ],
        "threads": [
            [
                json_object(t).get("isResolved"),
                json_object(json_object(t).get("comments")).get("totalCount"),
            ]
            for t in _whole(pull.get("reviewThreads"), "review threads")
        ],
        "suites": sorted(
            json.dumps(s, sort_keys=True)
            for s in _whole(
                json_object(repository.get("head")).get("checkSuites"), "check suites"
            )
        ),
        "issues": [_issue_print(issue) for issue in issues],
        "trusted": json_object(repository.get("trusted")).get("oid"),
        "admission": json_object(repository.get("admission")).get("oid"),
    }
    # The verdict artifacts the read counts: every FAIL-named one, under any
    # pull request, and every one named for this pull request.
    own = re.compile(rf"pr-verify-0*{args.number}-")
    verdicts = []
    passes: list[dict[str, Any]] = []
    for item in map(json_object, listing):
        name_ = str(item.get("name") or "")
        match = verdict_name(name_)
        failed = FAIL_PREFIX_RE.match(name_) is not None or (
            match is not None and match[3] == "fail"
        )
        if not (failed or own.match(name_)):
            continue
        run_id = json_object(item.get("workflow_run")).get("id")
        verdicts.append([item.get("id"), name_, item.get("expired"), run_id])
        if (
            match is not None
            and int(match[1]) == args.number
            and match[2] == args.head
            and match[3] in PASSES
            and item.get("expired") is False
        ):
            passes.append(item)
    parts["verdicts"] = sorted(verdicts, key=json.dumps)
    expiry: datetime | None = None
    runs = []
    for item in passes:
        run_id = json_object(item.get("workflow_run")).get("id")
        try:
            record = json_object(
                reader._actions(
                    ["api", f"repos/{args.repo}/actions/runs/{run_id}"],
                    f"run {run_id}",
                )
            )
        except _Unreadable as exc:
            raise _ProbeFailed(str(exc)) from exc
        runs.append(
            [run_id]
            + [
                record.get(k)
                for k in (
                    "run_attempt",
                    "status",
                    "conclusion",
                    "run_started_at",
                    "created_at",
                )
            ]
        )
        expires = _when(item.get("expires_at"))
        if expires is None:
            raise _ProbeFailed("a PASS artifact with no expiry")
        expiry = expires if expiry is None else min(expiry, expires)
    parts["runs"] = sorted(runs, key=json.dumps)
    key = hashlib.sha256(
        json.dumps(parts, sort_keys=True, default=str).encode("utf-8")
    ).hexdigest()
    return key, created + timedelta(days=TOO_OLD_DAYS), expiry


@dataclass
class _Lookup:
    """What `_answered` knows before the full read: the kept answers, the
    key, and whether it matches the kept refusal for this pull request."""

    code: str
    kept: dict[int, dict[str, Any]]
    key: str | None
    too_old: datetime | None
    pass_expiry: datetime | None
    entry: dict[str, Any] | None
    stored: dict[str, Any] | None
    hit: bool
    cache: dict[str, str]


def _lookup(args: argparse.Namespace, reader: Reader, now: datetime) -> _Lookup:
    """The kept answer for this pull request and the key it must match. A
    probe that cannot key is a miss; any other error raises. Under serve's
    `--answers-only` no kept entry is a miss with no probe: nothing could hit."""
    code = _code_digest()
    kept = load_answers(args.answers_in, args.repo, code, now)
    entry = kept.get(args.number)
    key: str | None = None
    too_old: datetime | None = None
    pass_expiry: datetime | None = None
    if entry is not None or not (args.answers_mode == SERVE and args.answers_only):
        try:
            key, too_old, pass_expiry = _answer_key(args, reader)
        except Exception as exc:  # noqa: BLE001 - no key is a full read
            print(f"verify-cache: #{args.number} no key: {exc}", file=sys.stderr)
    stored = json_object(entry.get("report")) if entry else None
    hit = (
        key is not None
        and entry is not None
        and entry.get("key") == key
        and answer_cacheable(stored)
        and json_object(stored).get("head") == args.head
    )
    cache = {
        "mode": SERVE if args.answers_mode == SERVE else SHADOW,
        "key": "hit" if hit else "miss",
        "stored": answer_kind(stored) if hit else "none",
    }
    return _Lookup(code, kept, key, too_old, pass_expiry, entry, stored, hit, cache)


def _kept_report(
    args: argparse.Namespace, now: datetime, look: _Lookup, report: dict[str, Any]
) -> dict[str, Any]:
    """`report`, kept for the next run when cacheable, with the `cache`
    object comparing it with the kept one."""
    fresh = None
    if look.key is not None and answer_cacheable(report):
        # Age changes only one answer: verify:missing turns verify:too-old
        # past TOO_OLD_DAYS. Any other answer moves only with the key.
        limits = [now + ANSWER_TTL, look.pass_expiry]
        limits.append(look.too_old if report.get("refusal") == MISSING else None)
        fresh = {
            "key": look.key,
            "readAt": now.isoformat(),
            "expiresAt": min(t for t in limits if t is not None).isoformat(),
            "report": report,
        }
    _write_answers(
        args.answers_out, look.kept, args.repo, look.code, now, args.number, fresh
    )
    agree = "n/a"
    if look.hit:
        same = _decides(json_object(look.stored)) == _decides(report)
        agree = "yes" if same else "no"
    return report | {
        "cache": look.cache | {"fresh": answer_kind(report), "agree": agree},
    }


def _answered(
    args: argparse.Namespace, reader: Reader, now: datetime
) -> dict[str, Any]:
    """`evidence` with kept answers (`main`): served under `serve` when the
    key matches a kept refusal, else read in full, kept when cacheable, and
    compared with the kept one in the `cache` object.

    The cache never costs the read: any error of its own (an answers file
    json cannot load, a module that cannot be hashed, a write that fails)
    leaves the plain report, as without answers files, and under
    `--answers-only` no answer at all, each with a `cache` object marking
    the error. The probe's rate guard is not such an
    error: a rate limit behind the key exits the process (`os._exit(75)`) as
    any other read's does, the price of one GraphQL point a read."""
    serve = args.answers_mode == SERVE
    # What the run logs for a read the cache failed on (`cache=error`).
    failed = {"mode": SERVE if serve else SHADOW, "error": True}
    # The key first in both modes, so a kept entry carries the key of the
    # inputs as they stood before the read: one that moves during it is a
    # miss next run, never a hit on a stale refusal.
    try:
        look = _lookup(args, reader, now)
        if serve and look.hit:
            _write_answers(
                args.answers_out,
                look.kept,
                args.repo,
                look.code,
                now,
                args.number,
                look.entry,
            )
            return json_object(look.stored) | {
                "cached": True,
                "cache": look.cache | {"fresh": "none", "agree": "n/a"},
            }
        if serve and args.answers_only:
            # No full read: a miss is no answer at all.
            _write_answers(
                args.answers_out,
                look.kept,
                args.repo,
                look.code,
                now,
                args.number,
                look.entry,
            )
            return {"head": args.head, "cached": False, "cache": look.cache}
    except Exception as exc:  # noqa: BLE001 - the cache never costs the read
        print(f"verify-cache: #{args.number} cache error: {exc!r}", file=sys.stderr)
        if serve and args.answers_only:
            return {"head": args.head, "cached": False, "cache": failed}
        return _evidence_report(args, reader) | {"cache": failed}
    report = _evidence_report(args, reader)
    try:
        return _kept_report(args, now, look, report)
    except Exception as exc:  # noqa: BLE001 - the cache never costs the read
        print(f"verify-cache: #{args.number} cache error: {exc!r}", file=sys.stderr)
        return report | {"cache": failed}


def _settle(repo: str, path: str, code_sha: str, *, idle: bool = False) -> int:
    """`settle`: whether this run's post-merge report at `path`, its check
    run by the code at commit `code_sha`, stands for the check at the default
    branch head now (`merge_policy.settle_shared`, the lane room's rule, kept
    but never read again), as the lane's agent identity in the config there.
    With `idle`, the report is an earlier tick's, and it must also pass
    `postmerge.idle_refusal`. Changed check code refuses before any read.
    Prints `{"reuse", "reason"}`; exit 0 when it stands, else 1, and the
    caller runs the check."""
    shared = postmerge.read_shared(path)
    reason: str | None = "post-merge answer missing or unreadable"
    if not merge_policy.check_code_unchanged(code_sha):
        reason = "post-merge answer code-changed"
    elif shared is not None:
        try:
            default = merge_policy._default_branch(repo, shared=True)
            config = merge_policy._default_branch_config(repo, default)
            if not config.agent_identity:
                reason = "no agent identity"
            else:
                _, reason = merge_policy.settle_shared(
                    repo,
                    shared,
                    default=default,
                    base_sha=config.base_sha,
                    identity=config.agent_identity,
                    code_unchanged=True,
                    runs_unchanged=lambda answer, branch: (
                        postmerge.pending_runs_unchanged(repo, answer, branch)
                    ),
                )
                if reason is None and idle:
                    refusal = postmerge.idle_refusal(
                        repo,
                        shared,
                        default,
                        confirm_wait_minutes=config.confirm_wait_minutes,
                    )
                    reason = refusal and f"idle tick {refusal}"
        except (RuntimeError, ValueError, OSError) as exc:
            reason = f"unreadable: {exc}"
    print(json.dumps({"reuse": reason is None, "reason": reason}))
    return 0 if reason is None else 1


# GitHub refuses a comment body over 65536 characters; the findings are cut
# to leave room for the framing (judgment).
FINDINGS_MAX = 60000
_CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f]")
AGENT_READY = "agent-ready"
STATUS_READY = "status: ready"
STATUS_CONFIRMED = "status: confirmed"


def _inert(text: str) -> str:
    """Model text as a fenced block keeps it: no control character and no
    fence of its own, so nothing in it renders or reads as a command."""
    return _CONTROL.sub("?", text).replace("```", "'''")


def capped_close_marker(
    number: int,
    heads: list[str],
    attempt: tuple[int, int] | None = None,
    parked: bool = False,
) -> str:
    """The capped-close record's first line (`CAPPED_CLOSE_RE`)."""
    tail = (
        f" attempt={attempt[0]} of={attempt[1]}{' parked' if parked else ''}"
        if attempt
        else ""
    )
    return f"<!-- verify-capped-close pr={number} heads={','.join(heads)}{tail} -->"


def findings_text(findings: list[dict[str, Any]]) -> str:
    """Each FAILed head's verdict summary and notes as one fenced block,
    the verifier's words quoted as data."""
    if not findings:
        return "No FAIL findings were counted for this pull request."
    lines: list[str] = []
    for entry in findings:
        lines.append(f"head {entry['head']} (pr-verify run {entry['run']})")
        if "unreadable" in entry:
            lines.append(f"  unreadable: {entry['unreadable']}")
        else:
            lines.append(f"  summary: {entry.get('summary', '')}")
            lines.extend(f"  - {note}" for note in entry.get("notes", []))
        lines.append("")
    text = _inert("\n".join(lines).rstrip())
    if len(text) > FINDINGS_MAX:
        text = f"{text[:FINDINGS_MAX]} [cut]"
    return "\n".join(["```text", text, "```"])


def capped_close_bodies(
    number: int,
    head: str,
    refusal: str,
    detail: str | None,
    findings: list[dict[str, Any]],
    issue: int | None,
    attempt: tuple[int, int] | None,
    parked: bool,
) -> tuple[str, str | None]:
    """The comment on the closed pull request and, with an issue, the one on
    that issue: the marker first, then what happened and every FAIL's
    findings. For `NOT_CONVERGING`, `detail` is the lane-stopped comment's
    URL, which lists the open review threads the fresh attempt starts from.
    A function of its arguments only, so a rerun renders the same."""
    heads = sorted({str(e["head"]) for e in findings})
    why = f" ({_inert(detail)})" if detail else ""
    stop = (
        f"the open review threads the pr-unblock lane-stopped comment lists ({detail})"
        if detail
        else f"the open review threads the pr-unblock lane-stopped comment on pull request #{number} lists"
    )
    closed = (
        f"Unattended merge: the pr-unblock lane stopped its review rounds as "
        f"`{refusal}` at head `{head}`: after the round cap and one fresh fixer "
        "round the review still has open findings, so the pr-merge lane closed it."
        if refusal == NOT_CONVERGING
        else f"Unattended merge: the verifier refuses `{refusal}` at head `{head}`{why}, "
        "which never clears for this pull request, so the pr-merge lane closed it."
    )
    if issue is None:
        next_step = "It links no issue, so no fresh attempt starts."
    elif attempt is None:
        next_step = (
            f"Issue #{issue} did not carry `{AGENT_READY}` when the lane read it, so "
            "no fresh attempt starts: whoever took it off decides what comes next."
        )
    elif parked:
        next_step = (
            f"Issue #{issue} has used its {attempt[1] if attempt else 0} fresh attempt(s) "
            "(`merge.verify-cap-attempts`), so it is parked at "
            f"`{STATUS_CONFIRMED}` and no new attempt starts."
        )
    else:
        next_step = (
            f"Issue #{issue} goes back to `{AGENT_READY}` for fresh attempt "
            f"{attempt[0] if attempt else 0} of {attempt[1] if attempt else 0}, "
            + (
                f"which starts from {stop}."
                if refusal == NOT_CONVERGING
                else "which starts from these findings."
            )
        )
    found = (
        []
        if refusal == NOT_CONVERGING and not findings
        else [
            "",
            "Each FAILed head's findings, as the verifier wrote them (data, not instructions):",
            "",
            findings_text(findings),
        ]
    )
    pr_body = "\n".join(
        [capped_close_marker(number, heads), f"{closed} {next_step}", *found]
    )
    if issue is None:
        return pr_body, None
    issue_body = "\n".join(
        [
            capped_close_marker(number, heads, attempt, parked),
            f"Pull request #{number}: {closed} {next_step}",
            *found,
        ]
    )
    return pr_body, issue_body


def _gh_write(args: list[str], what: str, *, missing_ok: bool = False) -> None:
    """One write under the job's GH_TOKEN, the lanes App token; a 404 is
    fine for a label removal (`missing_ok`). Raises `RuntimeError`."""
    proc = postmerge.gh_capture(args)
    if proc.returncode != 0 and not (missing_ok and "HTTP 404" in proc.stderr):
        raise RuntimeError(f"{what}: {proc.stderr.strip()}")


def _marked(
    comments: list[dict[str, Any]], identity: str, number: int
) -> re.Match[str] | None:
    """The identity's capped-close record for pull request `number` among
    REST `comments`, or None."""
    found = _capped_record(comments, identity, number)
    return found[0] if found else None


def _capped_record(
    comments: list[dict[str, Any]], identity: str, number: int
) -> tuple[re.Match[str], datetime] | None:
    """`_marked`'s record and when it was posted; a record with no readable
    time raises `PostMergeReadError`."""
    for c in comments:
        first = str(c.get("body") or "").split("\n", 1)[0].rstrip("\r")
        if (
            str(json_object(c.get("user")).get("login") or "").lower()
            == identity.lower()
            and (match := CAPPED_CLOSE_RE.fullmatch(first))
            and int(match[1]) == number
        ):
            return match, postmerge._time(c.get("created_at"))
    return None


def _lane_removals(
    events: list[dict[str, Any]], identity: str, since: datetime
) -> tuple[bool, bool]:
    """Among the issue's REST `events`, whether the lanes App removed
    `agent-ready` at or after its record (`since`; times have one-second
    resolution, and the record and the removal land in the same second), and
    whether the newest removal is such a one: the removal an earlier run made
    for the fresh attempt and could not undo."""
    removals = sorted(
        (
            e
            for e in map(json_object, events)
            if e.get("event") == "unlabeled"
            and str(json_object(e.get("label")).get("name") or "").lower()
            == AGENT_READY
        ),
        key=lambda e: postmerge._time(e.get("created_at")),
    )
    ours = [
        str(json_object(e.get("actor")).get("login") or "").lower() == identity.lower()
        and postmerge._time(e.get("created_at")) >= since
        for e in removals
    ]
    return any(ours), bool(ours) and ours[-1]


def _spent(comments: list[dict[str, Any]], identity: str, number: int) -> int:
    """How many other pull requests for the issue the lane has closed at the
    cap for a fresh attempt (`_started_attempt`), so a parked or
    attempt-less record spends nothing."""
    named = set()
    for c in comments:
        if str(
            json_object(c.get("user")).get("login") or ""
        ).lower() == identity.lower() and (
            pr := _started_attempt(c.get("body"))
        ) is not None:
            named.add(pr)
    return len(named - {number})


def not_converging_stop(
    comments: list[dict[str, Any]], identity: str, head: str
) -> dict[str, Any] | None:
    """The lanes App's (`identity`) lane-stopped comment for address-feedback
    among REST `comments` (report-escalation.sh, one per activity, edited in
    place) naming `NOT_CONVERGING` and `head`, or None. Only the App writes
    it; a status description, which any workflow can post, decides nothing."""
    for comment in comments:
        if (
            str(json_object(comment.get("user")).get("login") or "").lower()
            != identity.lower()
        ):
            continue
        lines = [
            line.rstrip("\r") for line in str(comment.get("body") or "").split("\n")
        ]
        if (
            lines[0] == LANE_STOPPED_FEEDBACK
            and f"- Reason: `{NOT_CONVERGING}`" in lines
            and f"- Head: `{head}`" in lines
        ):
            return comment
    return None


def capped_close(
    reader: Reader,
    number: int,
    head: str,
    *,
    attempts: int,
    holds: tuple[str, ...] = (),
    issue_holds: tuple[str, ...] = (),
    reason: str = CLOSE_VERIFY,
) -> dict[str, Any]:
    """Close a lanes App pull request the verifier refuses for good
    (`VERIFY_FINAL`) at `head`, judged again here, for a fresh attempt at its
    issue (owner decision 2026-10-29; no person's label on this path). With
    `reason` `NOT_CONVERGING` it closes instead one whose review rounds the
    pr-unblock lane stopped as not converging at `head`, judged again here
    from the lanes App's lane-stopped comment (`not_converging_stop`), the
    same way (owner decision on the issue this fixes, 2026-10-30). In
    order, so a failed write leaves the pull request open for the next run,
    which finds its comments and writes the rest: the record on the pull
    request, then on each issue; the issue's `agent-ready` comes off and
    goes back on (tried twice), which starts the fresh attempt, only when the
    issue carried it (one that did not is recorded and not restarted); the pull
    request closes, so a closed one never leaves its issue without
    `agent-ready`. An issue that already had `attempts` fresh attempts
    (`merge.verify-cap-attempts`) is parked instead, at `status: confirmed`
    with `status: ready` and `agent-ready` off, before the close. A pull
    request not open at `head`, not the lanes App's, or carrying a hold label
    (`holds`) is left alone, and so is one whose issue link the pr-merge lane
    does not take (`Reader.link_refusal`: one issue, clearing the trust hold)
    or whose issue carries an `issue_holds` label (`issue_hold_refusal`; none
    resolved refuses). A pull request is closed at the cap once: one reopened
    after its record stays open, and a rerun after a failed close writes no
    issue label, except putting back an `agent-ready` the newest removal of
    which was the lanes App's own at or after its record (`_lane_removals`);
    one carrying it with no such removal is toggled, since the run that
    wrote the record stopped before the label came off.
    FAIL findings come only from runs of verified origin. Raises
    `RuntimeError` on a failed
    write or a failed issue read, `PostMergeReadError` on a failed comments
    read."""
    identity = reader.agent_identity or ""
    refusal: str | None
    detail: str | None
    if reason == NOT_CONVERGING:
        # Judged below from the pull request's comments, not the verifier;
        # `detail` becomes the stop comment's URL.
        refusal, detail = NOT_CONVERGING, None
    elif reason == CLOSE_VERIFY:
        evidence = reader.evidence(number, head)
        if evidence.refusal not in VERIFY_FINAL:
            return {
                "closed": False,
                "reason": f"the verifier answers {evidence.refusal} at {head}",
            }
        refusal, detail = evidence.refusal, evidence.detail
    else:
        raise ValueError(f"unknown close reason {reason}")
    pr = merge_policy.pull_request(reader.repo, number)
    labels = {
        str(json_object(item).get("name") or "").lower()
        for item in pr.get("labels") or []
    }
    if (
        pr.get("state") != "open"
        or json_object(pr.get("head")).get("sha") != head
        or not identity
        or str(json_object(pr.get("user")).get("login") or "").lower()
        != identity.lower()
    ):
        return {
            "closed": False,
            "reason": "not an open lanes App pull request at that head",
        }
    if held := sorted(labels & {h.lower() for h in holds}):
        return {"closed": False, "reason": f"it carries {', '.join(held)}"}
    if (refused := reader.link_refusal(number)) is not None:
        return {"closed": False, "reason": refused}
    try:
        live = reader._closing_issues(number)
    except _Unreadable as exc:
        raise RuntimeError(f"issue link: {exc}") from exc
    for node in live.values():
        if (refused := merge_policy.issue_hold_refusal(node, issue_holds)) is not None:
            return {"closed": False, "reason": refused}
    issues = sorted(n for n in live if type(n) is int)
    try:
        findings = reader.fail_findings(number)
    except _Unreadable as exc:
        raise RuntimeError(f"FAIL findings: {exc}") from exc
    repo = reader.repo
    pr_comments = postmerge._paginated(
        f"repos/{repo}/issues/{number}/comments?per_page=100", f"#{number} comments"
    )
    if refusal == NOT_CONVERGING:
        if (stop := not_converging_stop(pr_comments, identity, head)) is None:
            return {
                "closed": False,
                "reason": f"no lanes App {NOT_CONVERGING} stop at {head}",
            }
        # The stop comment lists the open review threads it was closed for.
        detail = str(stop.get("html_url") or "") or None
    # A pull request is closed at the cap once: one reopened after its
    # record is a person's, and stays open.
    if (pr_record := _capped_record(pr_comments, identity, number)) is not None and any(
        json_object(e).get("event") == "reopened"
        and postmerge._time(json_object(e).get("created_at")) > pr_record[1]
        for e in postmerge._paginated(
            f"repos/{repo}/issues/{number}/events?per_page=100", f"#{number} events"
        )
    ):
        return {"closed": False, "reason": "reopened after its capped-close record"}
    # `attempt` None: the issue did not carry agent-ready when read (a person
    # may have taken it off), so it is recorded without an attempt and not
    # restarted. `labels`: which label writes it gets (park, toggle, add or
    # none). On a rerun, a record with no attempt writes none; a parked one
    # writes the park labels only while unfinished; one naming an attempt
    # toggles only when no lanes App removal followed the record, and puts
    # agent-ready back only when the newest removal is that one
    # (`_lane_removals`).
    plan: list[
        tuple[int, list[dict[str, Any]], tuple[int, int] | None, bool, str]
    ] = []
    for issue in issues:
        comments = postmerge._paginated(
            f"repos/{repo}/issues/{issue}/comments?per_page=100", f"#{issue} comments"
        )
        found = _capped_record(comments, identity, number)
        carried = AGENT_READY in (
            label.lower() for label in merge_policy._label_names(live[issue]) or []
        )
        if found is not None and found[0][3] is not None:
            prior, since = found
            attempt, parked = (int(prior[3]), int(prior[4])), bool(prior[5])
            names = {
                label.lower() for label in merge_policy._label_names(live[issue]) or []
            }
            if parked:
                # Written once: the park labels go on again only while unfinished.
                done = STATUS_CONFIRMED in names and not names & {
                    STATUS_READY,
                    AGENT_READY,
                }
                labels = "none" if done else "park"
            else:
                removed, newest = _lane_removals(
                    postmerge._paginated(
                        f"repos/{repo}/issues/{issue}/events?per_page=100",
                        f"#{issue} events",
                    ),
                    identity,
                    since,
                )
                if carried:
                    # No removal since the record: the run stopped before it,
                    # so no labeled event ever started the attempt.
                    labels = "none" if removed else "toggle"
                else:
                    labels = "add" if newest else "none"
        elif found is not None:
            # Recorded with no attempt: nothing is restarted, whatever a
            # person did since.
            attempt, parked, labels = None, False, "none"
        else:
            spent = _spent(comments, identity, number)
            parked = spent >= attempts
            attempt = (
                (spent if parked else spent + 1, attempts)
                if parked or carried
                else None
            )
            labels = "park" if parked else ("toggle" if carried else "none")
        plan.append((issue, comments, attempt, parked, labels))
    first = plan[0] if plan else None
    pr_body, _ = capped_close_bodies(
        number,
        head,
        str(refusal),
        detail,
        findings,
        first[0] if first else None,
        first[2] if first else None,
        first[3] if first else False,
    )
    if pr_record is None:
        _gh_write(
            [
                "api",
                "-X",
                "POST",
                f"repos/{repo}/issues/{number}/comments",
                "-f",
                f"body={pr_body}",
            ],
            "pull request record",
        )
    for issue, comments, attempt, parked, labels in plan:
        _, issue_body = capped_close_bodies(
            number,
            head,
            str(refusal),
            detail,
            findings,
            issue,
            attempt,
            parked,
        )
        if _marked(comments, identity, number) is None:
            _gh_write(
                [
                    "api",
                    "-X",
                    "POST",
                    f"repos/{repo}/issues/{issue}/comments",
                    "-f",
                    f"body={issue_body}",
                ],
                f"#{issue} record",
            )
        base = f"repos/{repo}/issues/{issue}/labels"
        if labels == "park":
            _gh_write(
                ["api", "-X", "POST", base, "-f", f"labels[]={STATUS_CONFIRMED}"],
                f"#{issue} {STATUS_CONFIRMED}",
            )
            _gh_write(
                [
                    "api",
                    "-X",
                    "DELETE",
                    f"{base}/{urllib.parse.quote(STATUS_READY, safe='')}",
                ],
                f"#{issue} {STATUS_READY}",
                missing_ok=True,
            )
        if labels == "none":
            continue
        if labels != "add":
            _gh_write(
                ["api", "-X", "DELETE", f"{base}/{AGENT_READY}"],
                f"#{issue} {AGENT_READY}",
                missing_ok=True,
            )
        if parked:
            continue
        args = ["api", "-X", "POST", base, "-f", f"labels[]={AGENT_READY}"]
        try:
            _gh_write(args, f"#{issue} {AGENT_READY}")
        except RuntimeError:
            _gh_write(
                args,
                f"#{issue} {AGENT_READY} was removed for a fresh attempt but not added back",
            )
    _gh_write(
        ["api", "-X", "PATCH", f"repos/{repo}/pulls/{number}", "-f", "state=closed"],
        "close",
    )
    return {
        "closed": True,
        "refusal": refusal,
        "restarted": [i for i, *_, how in plan if how in ("toggle", "add")],
        "parked": [i for i, _, _, parked, _ in plan if parked],
        "unrestarted": [i for i, _, _, parked, how in plan if how == "none"],
    }


def _capped_close_main(args: argparse.Namespace, now: datetime | None) -> int:
    """`capped-close`: `capped_close` under the config at `--base-sha` and
    the default branch (the lower attempts and FAIL cap), as one JSON line;
    exit 1 with `error` when a read or write failed."""
    try:
        base = merge_policy.config_at(args.repo, args.base_sha)
        if base.error:
            raise merge_policy.PolicyReadError(base.error)
        config = merge_policy.with_default_branch(args.repo, base)
        reader = Reader(
            args.repo,
            args.branch,
            now=now,
            max_fails=config.max_verify_fails,
            agent_identity=config.agent_identity,
        )
        reader.listing_max_age = None
        holds = tuple(h for h in args.hold_label if h)
        owner, _, name = args.repo.partition("/")
        # The labels that hold the issue, as the merge gate resolves them
        # (`merge_policy.issue_hold_labels`).
        issue_holds = merge_policy.issue_hold_labels(
            config,
            None
            if config.issue_holds
            else postmerge._role_label(owner, name, strict=True),
        )
        result = capped_close(
            reader,
            args.number,
            args.head,
            attempts=config.verify_cap_attempts,
            holds=holds,
            issue_holds=issue_holds,
            reason=args.reason,
        )
    except (
        RuntimeError,
        merge_policy.PolicyReadError,
        postmerge.PostMergeReadError,
    ) as exc:
        print(json.dumps({"closed": False, "error": str(exc)}))
        return 1
    print(json.dumps(result))
    return 0


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
    again on a listing of its own, as the gate does before it allows. With
    `--shared-listing` the run's saved listing serves at any age, an allow
    included: ci-status's merge-queue step runs this reader again at the head.

    With `--lane-link`, the line also carries `ineligible`: null when the
    pull request's issue link is one the pr-merge lane takes and its issue
    clears the trust hold (`Reader.link_refusal`), else why not, with refusal
    `verify:ineligible`
    and no verdict or config read. With `--lane-reviews` (and `--base-sha`
    and `--rung`, the lane room's effective rung), a line whose refusal is
    null also carries `reviews`: null when pr-merge's gate would not hold
    the pull request on its risk score (`lane_risk_refusal`), else why,
    `reviewsPerson`: whether only a person clears that hold, and
    `wholeReviewWanted`: whether a clean whole review of the head would. With
    `--lane-queue` too, a line whose `reviews` is null also carries `queue`
    (`lane_queue`): the head's failed-check merge-queue removals, the
    `merge.max-queue-ejections` limit, and the gate's refusal and comment at
    or over it.

    With `--answers-in <file>` and `--answers-out <file>`, the line is also
    one of the answers the last run kept (`_answered`): `--answers-mode
    serve` prints a kept refusal whose key still matches with `cached: true`
    and reads nothing more; any other mode (`shadow`) reads in full all the
    same and adds a `cache` object comparing the kept answer with the fresh
    one. `--answers-only` (serve only; shadow ignores it) prints a kept
    refusal or no answer at all, never reading in full.

    `lane-room --postmerge-result <file> [--rung-cap <value>]`: whether the
    pr-merge lane may merge one more of its own pull requests now
    (`merge_policy.lane_room`, `LaneRoom.report`), from this run's
    `babysit_postmerge.py` report and the `CLAUDE_LANES_MERGE_RUNG_CAP` value
    the workflow read (empty is no cap; missing holds the rung off). A report
    the gate would not reuse, for any `shared_refusal`, is checked again; one
    refused only as `unverified-stale` is first kept while nothing it was
    read from has moved, and one refused only as `demotion-changed` when the
    demotion reads the same.

    `lane-room` and `settle` take `--code-sha`, the commit whose code ran the
    report's check (empty when unknown): changed check code reads the report
    again or refuses it (`merge_policy.check_code_unchanged`).

    `capped-close --repo R --base-sha <sha> [--hold-label L ...]
    [--reason verify|feedback-not-converging] <number>
    <head>`: `capped_close` for enable-auto-merge.mjs (`_capped_close_main`),
    its writes under GH_TOKEN, the lanes App token.

    `settle --repo R --postmerge-result <file> --code-sha <sha>`: the same
    rule for the merge job's reuse of this run's report, which never reads it
    again (`_settle`). With `--idle-tick`, post-merge-dispatch's reuse of an
    earlier tick's report, which must also pass `postmerge.idle_refusal`."""
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
    cmd.add_argument("--lane-queue", action="store_true")
    cmd.add_argument("--rung", default=None)
    cmd.add_argument("--shared-listing", action="store_true")
    cmd.add_argument("--answers-in", default=None)
    cmd.add_argument("--answers-out", default=None)
    cmd.add_argument("--answers-mode", default=SHADOW)
    cmd.add_argument("--answers-only", action="store_true")
    cmd.add_argument("number", type=int)
    cmd.add_argument("head")
    room = sub.add_parser("lane-room", allow_abbrev=False)
    room.add_argument("--repo", required=True)
    room.add_argument("--postmerge-result", required=True)
    room.add_argument("--rung-cap", default=None)
    room.add_argument("--code-sha", required=True)
    close = sub.add_parser("capped-close", allow_abbrev=False)
    close.add_argument("--repo", required=True)
    close.add_argument("--branch", default="main")
    close.add_argument("--base-sha", required=True)
    close.add_argument("--hold-label", action="append", default=[])
    close.add_argument("--reason", choices=CLOSE_REASONS, default=CLOSE_VERIFY)
    close.add_argument("number", type=int)
    close.add_argument("head")
    settle = sub.add_parser("settle", allow_abbrev=False)
    settle.add_argument("--repo", required=True)
    settle.add_argument("--postmerge-result", required=True)
    settle.add_argument("--code-sha", required=True)
    settle.add_argument("--idle-tick", action="store_true")
    args = parser.parse_args(argv)
    if args.command == "capped-close":
        if not (
            merge_policy.SHA_RE.fullmatch(args.head)
            and merge_policy.SHA_RE.fullmatch(args.base_sha)
        ):
            parser.error("head and --base-sha must be full commit SHAs")
        return _capped_close_main(args, now)
    if args.command == "settle":
        return _settle(
            args.repo, args.postmerge_result, args.code_sha, idle=args.idle_tick
        )
    if args.command == "lane-room":
        shared = postmerge.read_shared(args.postmerge_result)
        answer = merge_policy.lane_room(
            args.repo,
            shared,
            lane_rung_cap=args.rung_cap,
            code_unchanged=merge_policy.check_code_unchanged(args.code_sha),
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
    if args.lane_queue and not (args.lane_reviews and args.base_sha):
        # The reviews read checks the head the count is for and reads the limit.
        parser.error("--lane-queue needs --lane-reviews and --base-sha")
    reader = Reader(args.repo, args.branch, now=now, max_fails=args.max_fails)
    if args.shared_listing:
        reader.listing_max_age = None
    if args.answers_in is None and args.answers_out is None and not args.answers_only:
        print(json.dumps(_evidence_report(args, reader)))
        return 0
    print(json.dumps(_answered(args, reader, now or datetime.now(UTC))))
    return 0


def _evidence_report(args: argparse.Namespace, reader: Reader) -> dict[str, Any]:
    """`evidence`'s answer for one pull request, read in full (`main`)."""
    link: dict[str, Any] = {}
    config: merge_policy.PipelineConfig | None = None
    if args.lane_link:
        link["ineligible"] = reader.link_refusal(args.number)
        if link["ineligible"] is not None:
            refusal = Evidence(INELIGIBLE, args.head, (), 0, link["ineligible"])
            return refusal.report() | link
    if args.base_sha is not None:
        try:
            base = merge_policy.config_at(args.repo, args.base_sha)
            if base.error:
                raise merge_policy.PolicyReadError(base.error)
            config = merge_policy.with_default_branch(args.repo, base)
        except merge_policy.PolicyReadError as exc:
            refusal = Evidence(UNREADABLE, args.head, (), 0, f"config: {exc}")
            return refusal.report() | link
        reader.max_fails = config.max_verify_fails
        reader.agent_identity = config.agent_identity
    pr = None
    if args.lane_reviews:
        try:
            pr = merge_policy.pull_request(args.repo, args.number)
        except merge_policy.PolicyReadError as exc:
            refusal = Evidence(UNREADABLE, args.head, (), 0, str(exc))
            return refusal.report() | link
    evidence = reader.evidence(args.number, args.head, pr)
    if evidence.refusal is None and reader.saved and not args.shared_listing:
        reader.refresh()
        evidence = reader.evidence(args.number, args.head, pr)
    if args.lane_reviews and evidence.refusal is None:
        head = json_object(json_object(pr).get("head")).get("sha")
        # Whether only a person clears `reviews`; an unread score the lanes
        # read again. Whether a whole review of the head would clear it.
        link["reviewsPerson"] = False
        link["wholeReviewWanted"] = False
        if head != args.head:
            link["reviews"] = f"unreadable: the head is {head}, not {args.head}"
        elif config is None:
            link["reviews"] = "unreadable: no --base-sha, so no config to score at"
        else:
            # The lowest of the room's effective rung and this base's config.
            rung = merge_policy.effective_rung(
                config_rung=config.rung,
                loop_merge=config.loop_merge,
                cap=args.rung
                if merge_policy.rung_code(args.rung) in merge_policy.RUNG_RANK
                else "off",
                demoted=False,
            ).rung
            held = (
                (f"unreadable: the lane's rung is {args.rung}", False, False)
                if rung == "off"
                else lane_risk_refusal(
                    args.repo,
                    args.number,
                    json_object(pr),
                    config,
                    reader.linked_issue.get(args.number),
                    humans=reader._trusted_humans,
                )
            )
            (
                link["reviews"],
                link["reviewsPerson"],
                link["wholeReviewWanted"],
            ) = held or (None, False, False)
        if args.lane_queue and link["reviews"] is None and config is not None:
            link["queue"] = lane_queue(
                args.repo,
                args.branch,
                args.number,
                args.head,
                config.max_queue_ejections,
            )
    return evidence.report() | link


if __name__ == "__main__":
    sys.exit(main())

"""Kept verifier answers (`babysit_verify_evidence --answers-in/--answers-out`).

Expected values come from the verifier-read cache design (step 2): an entry is
written only for a refusal of a stable kind, never an allow and never an
unreadable answer; it is served only under `--answers-mode serve`, only while
every input of the read hashes the same, and only until the earliest of an
hour after the read, the pull request turning 80 days old and a PASS
artifact's expiry; any read behind the key that fails, and any answers file of
another version, repository or code, is a full read. The GraphQL and REST
shapes follow `PROBE_QUERY` and `GET .../actions/runs/{id}`; the artifact
shape follows test_babysit_verify_evidence.py's recorded listing. Network is
stubbed at the `gh_capture` seam.
"""

from __future__ import annotations

import argparse
import contextlib
import copy
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Callable, Iterator
from datetime import UTC, datetime, timedelta
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy
import babysit_postmerge as postmerge
import babysit_verify_evidence as ve

REPO = "example-org/example-repo"
PR = 41
HEAD = "a" * 40
BASE = "b" * 40
OTHER = "c" * 40
NOW = datetime(2026, 10, 16, 12, 0, tzinfo=UTC)
BOT = "agent-lanes"
CONFIG = policy.PipelineConfig(
    base_sha=BASE,
    rung="C2",
    authority="pr-merge",
    agent_identity=f"{BOT}[bot]",
    max_changed_lines=None,
    denied_paths=(),
    loop_merge=None,
)
MISSING = {
    "refusal": "verify:missing",
    "needsHuman": False,
    "head": HEAD,
    "atHead": [],
    "earlierFails": [],
    "ignored": 0,
    "detail": None,
    "headFail": None,
    "ineligible": None,
}
ALLOW = MISSING | {
    "refusal": None,
    "reviews": None,
    "reviewsPerson": False,
    "queue": {"refusal": None, "readError": None, "commentError": None},
}


def issue(number: int = 1041, **overrides: Any) -> dict[str, Any]:
    fields = {
        "__typename": "Issue",
        "number": number,
        "repository": {"nameWithOwner": REPO},
        "updatedAt": "2026-10-12T00:00:00Z",
        "lastEditedAt": None,
        "timelineItems": {"totalCount": 3, "updatedAt": "2026-10-12T00:00:00Z"},
        "labels": {"totalCount": 1, "nodes": [{"name": "agent-ready"}]},
        "comments": {
            "totalCount": 1,
            "nodes": [{"databaseId": 5, "updatedAt": "2026-10-11T00:00:00Z"}],
        },
        "closedByPullRequestsReferences": {"totalCount": 1},
    }
    fields.update(overrides)
    return fields


def said(cid: int, body: str, login: str = "maintainer", kind: str = "User") -> dict:
    return {
        "databaseId": cid,
        "updatedAt": "2026-10-13T00:00:00Z",
        "body": body,
        "author": {"__typename": kind, "login": login},
    }


def probe() -> dict[str, Any]:
    """`PROBE_QUERY`'s repository for PR 41 at HEAD, closing #1041."""
    return {
        "pullRequest": {
            "headRefOid": HEAD,
            "baseRefOid": BASE,
            "createdAt": "2026-10-10T00:00:00Z",
            "title": "feat: x",
            "body": "Closes #1041",
            "timelineItems": {"totalCount": 9},
            "comments": {
                "totalCount": 2,
                "nodes": [
                    said(70, "Looks fine."),
                    said(
                        77,
                        "<!-- babysit-merge-risk -->\nUnattended merge: unarmed",
                        BOT,
                        "Bot",
                    ),
                ],
            },
            "reviewThreads": {
                "totalCount": 1,
                "nodes": [{"isResolved": False, "comments": {"totalCount": 2}}],
            },
            "closingIssuesReferences": {"totalCount": 1, "nodes": [issue()]},
        },
        "head": {
            "checkSuites": {
                "totalCount": 1,
                "nodes": [
                    {
                        "databaseId": 900,
                        "updatedAt": "2026-10-15T00:00:00Z",
                        "status": "COMPLETED",
                        "conclusion": "SUCCESS",
                    }
                ],
            }
        },
        "trusted": {"oid": "1" * 40},
        "admission": {"oid": "2" * 40},
    }


def artifact(
    name: str, run_id: int, *, expired: bool = False, expires: str | None = None
) -> dict[str, Any]:
    return {
        "id": run_id * 10,
        "name": name,
        "expired": expired,
        "expires_at": expires or "2026-12-01T00:00:00Z",
        "workflow_run": {"id": run_id},
    }


def run_record(run_id: int, **overrides: Any) -> dict[str, Any]:
    fields = {
        "id": run_id,
        "run_attempt": 1,
        "status": "completed",
        "conclusion": "success",
        "run_started_at": "2026-10-15T00:00:00Z",
        "created_at": "2026-10-15T00:00:00Z",
    }
    fields.update(overrides)
    return fields


class World:
    """GitHub as the probe reads it, and every gh invocation made."""

    def __init__(self) -> None:
        self.repository = probe()
        self.refs: dict[str, Any] | None = None
        self.listing = [
            artifact(f"pr-verify-7-{OTHER}-pass", 3),
            artifact(f"pr-verify-9-{OTHER}-fail", 4),
        ]
        self.runs: dict[int, dict[str, Any]] = {}
        self.calls: list[list[str]] = []
        self.graphql: Callable[[str], subprocess.CompletedProcess[str]] | None = None

    def gh(self, args: list[str], **_: Any) -> subprocess.CompletedProcess[str]:
        self.calls.append(args)
        if args[:2] == ["api", "graphql"]:
            query = args[3].removeprefix("query=")
            if self.graphql is not None:
                return self.graphql(query)
            data = self.refs if query == ve.PROBE_REFS_QUERY else self.repository
            return done({"data": {"repository": data}})
        run_id = int(args[1].rsplit("/", 1)[1])
        return done(self.runs[run_id])


def done(payload: Any, code: int = 0) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess([], code, json.dumps(payload), "")


def namespace(**overrides: Any) -> argparse.Namespace:
    fields = {
        "repo": REPO,
        "branch": "main",
        "number": PR,
        "head": HEAD,
        "base_sha": BASE,
        "max_fails": 3,
        "rung": "C2",
        "lane_link": True,
        "lane_reviews": True,
        "lane_queue": True,
        "shared_listing": True,
        "answers_in": None,
        "answers_out": None,
        "answers_mode": ve.SHADOW,
        "answers_only": False,
    }
    fields.update(overrides)
    return argparse.Namespace(**fields)


def reader(world: World) -> ve.Reader:
    r = ve.Reader(REPO, "main", now=NOW, listing_max_age=None)
    r._artifacts, r._fetched_at = world.listing, NOW
    return r


@contextlib.contextmanager
def github(world: World, config: policy.PipelineConfig = CONFIG) -> Iterator[None]:
    with (
        mock.patch.object(postmerge, "gh_capture", side_effect=world.gh),
        mock.patch.object(policy, "config_at", return_value=config),
        mock.patch.object(policy, "with_default_branch", side_effect=lambda r, b: b),
    ):
        yield


def key(world: World, **overrides: Any) -> str:
    with github(world, overrides.pop("config", CONFIG)):
        return ve._answer_key(namespace(**overrides), reader(world))[0]


class KeyTest(unittest.TestCase):
    """Each input the read takes moves the key; the lane's own writes do not."""

    def moved(self, change: Callable[[World], None], **overrides: Any) -> bool:
        before = World()
        after = World()
        change(after)
        return key(before) != key(after, **overrides)

    def test_each_input_of_the_read_moves_the_key(self) -> None:
        pull = lambda w: w.repository["pullRequest"]  # noqa: E731
        closing = lambda w: pull(w)["closingIssuesReferences"]["nodes"][0]  # noqa: E731
        rows: dict[str, Callable[[World], None]] = {
            "1 body": lambda w: pull(w).update(body="Closes #1041\nmore"),
            "1 title": lambda w: pull(w).update(title="feat: y"),
            "4 issue labels": lambda w: closing(w).update(
                labels={"totalCount": 1, "nodes": [{"name": "untrusted"}]}
            ),
            "4 issue timeline": lambda w: closing(w).update(
                timelineItems={"totalCount": 4, "updatedAt": "2026-10-12T00:00:00Z"}
            ),
            "5 issue body edit": lambda w: closing(w).update(
                lastEditedAt="2026-10-14T00:00:00Z"
            ),
            "6 issue comment added": lambda w: closing(w)["comments"].update(
                totalCount=2,
                nodes=[
                    *closing(w)["comments"]["nodes"],
                    {"databaseId": 6, "updatedAt": "2026-10-14T00:00:00Z"},
                ],
            ),
            "6 issue comment edited": lambda w: closing(w)["comments"]["nodes"][
                0
            ].update(updatedAt="2026-10-14T00:00:00Z"),
            "7 closing set": lambda w: pull(w)["closingIssuesReferences"].update(
                nodes=[issue(1042)]
            ),
            "7 closed by another": lambda w: closing(w).update(
                closedByPullRequestsReferences={"totalCount": 2}
            ),
            "8 FAIL at the head, any number": lambda w: w.listing.append(
                artifact(f"pr-verify-99-{HEAD}-fail", 5)
            ),
            "9 FAIL naming the issue": lambda w: w.listing.append(
                artifact(f"pr-verify-98-{OTHER}-fail-i1041", 6)
            ),
            "11 off-grammar FAIL": lambda w: w.listing.append(
                artifact(f"pr-verify-0041-{OTHER}-fail-x", 7)
            ),
            "12 pass for this pull request": lambda w: w.listing.append(
                artifact(f"pr-verify-{PR}-{OTHER}-pass", 8)
            ),
            "14 expired flip": lambda w: w.listing[1].update(expired=True),
            "15 check suite": lambda w: w.repository["head"]["checkSuites"]["nodes"][
                0
            ].update(updatedAt="2026-10-16T00:00:00Z"),
            "15 a person's comment edited": lambda w: pull(w)["comments"]["nodes"][
                0
            ].update(updatedAt="2026-10-16T00:00:00Z"),
            "16 thread resolved": lambda w: pull(w)["reviewThreads"]["nodes"][0].update(
                isResolved=True
            ),
            "16 thread replied to": lambda w: pull(w)["reviewThreads"]["nodes"][0][
                "comments"
            ].update(totalCount=3),
            "17 18 timeline": lambda w: pull(w).update(
                timelineItems={"totalCount": 10}
            ),
            "22 trusted actors": lambda w: w.repository.update(
                trusted={"oid": "3" * 40}
            ),
            "23 admission rules": lambda w: w.repository.update(
                admission={"oid": "4" * 40}
            ),
            "25 base": lambda w: pull(w).update(baseRefOid=OTHER),
        }
        for row, change in rows.items():
            with self.subTest(row):
                self.assertTrue(self.moved(change))

    def test_the_config_rung_and_base_move_the_key(self) -> None:
        same = World()
        self.assertNotEqual(
            key(same),
            key(same, config=CONFIG.__class__(**{**CONFIG.__dict__, "rung": "C1"})),
        )
        self.assertNotEqual(key(same), key(same, rung="C1"))
        self.assertNotEqual(key(same), key(same, base_sha=OTHER))

    def test_a_pass_run_re_attempted_or_concluded_otherwise_moves_the_key(self) -> None:
        def with_pass(**record: Any) -> str:
            world = World()
            world.listing.append(artifact(f"pr-verify-{PR}-{HEAD}-pass", 8))
            world.runs[8] = run_record(8, **record)
            return key(world)

        base = with_pass()
        self.assertNotEqual(base, with_pass(run_attempt=2))
        self.assertNotEqual(base, with_pass(status="in_progress"))
        self.assertNotEqual(base, with_pass(conclusion="failure"))
        self.assertNotEqual(base, with_pass(run_started_at="2026-10-16T00:00:00Z"))
        self.assertEqual(base, with_pass())

    def test_the_refs_issue_is_fingerprinted_when_nothing_closes(self) -> None:
        def refs(**overrides: Any) -> str:
            world = World()
            world.repository["pullRequest"].update(
                body="Refs: #1050",
                closingIssuesReferences={"totalCount": 0, "nodes": []},
            )
            world.refs = {"issueOrPullRequest": issue(1050, **overrides)}
            return key(world)

        self.assertNotEqual(refs(), refs(lastEditedAt="2026-10-14T00:00:00Z"))
        self.assertEqual(refs(), refs())

    def test_another_pull_requests_pass_and_the_lanes_own_comment_edit_move_nothing(
        self,
    ) -> None:
        def own_edit(w: World) -> None:
            w.repository["pullRequest"]["comments"]["nodes"][1].update(
                updatedAt="2026-10-16T00:00:00Z",
                body="<!-- babysit-merge-risk -->\nUnattended merge: another reason",
            )

        self.assertFalse(
            self.moved(
                lambda w: w.listing.append(artifact(f"pr-verify-7-{HEAD}-pass", 9))
            )
        )
        self.assertFalse(self.moved(own_edit))

        # The same edit by another author, or the lanes App's comment of
        # another kind, moves it.
        def other_bot(w: World) -> None:
            own_edit(w)
            w.repository["pullRequest"]["comments"]["nodes"][1]["author"]["login"] = "x"

        def plain(w: World) -> None:
            own_edit(w)
            w.repository["pullRequest"]["comments"]["nodes"][1]["body"] = "hello"

        self.assertTrue(self.moved(other_bot))
        self.assertTrue(self.moved(plain))

    def test_a_probe_that_fails_or_comes_back_cut_raises(self) -> None:
        cases: dict[str, Callable[[World], None]] = {
            "GraphQL errors": lambda w: setattr(
                w, "graphql", lambda q: done({"errors": [{"message": "x"}]})
            ),
            "gh failed": lambda w: setattr(w, "graphql", lambda q: done({}, 1)),
            "no pull request node": lambda w: w.repository.update(pullRequest=None),
            "the head moved": lambda w: w.repository["pullRequest"].update(
                headRefOid=OTHER
            ),
            "cut threads": lambda w: w.repository["pullRequest"][
                "reviewThreads"
            ].update(totalCount=101),
            "cut suites": lambda w: w.repository["head"]["checkSuites"].update(
                totalCount=101
            ),
            "cut issue labels": lambda w: w.repository["pullRequest"][
                "closingIssuesReferences"
            ]["nodes"][0]["labels"].update(totalCount=101),
        }
        for row, change in cases.items():
            with self.subTest(row):
                world = World()
                change(world)
                with github(world), self.assertRaises(ve._ProbeFailed):
                    ve._answer_key(namespace(), reader(world))
        world = World()
        with github(world):
            self.assertEqual(len(ve._answer_key(namespace(), reader(world))[0]), 64)


class CacheableTest(unittest.TestCase):
    def test_only_a_stable_refusal_is_kept(self) -> None:
        kept = {
            "verify:missing": MISSING,
            "verify:fail": MISSING | {"refusal": "verify:fail"},
            "verify:too-old": MISSING | {"refusal": "verify:too-old"},
            "link": MISSING
            | {"refusal": ve.INELIGIBLE, "ineligible": "linked-issues:0"},
            "risk": ALLOW | {"reviews": "MED: a review not bound to the head"},
            "queue": ALLOW
            | {
                "queue": {
                    "refusal": "ejected 2 times",
                    "readError": None,
                    "commentError": None,
                }
            },
        }
        never = {
            "allow": ALLOW,
            "verify:unreadable": MISSING | {"refusal": ve.UNREADABLE},
            "unreadable link": MISSING
            | {"refusal": ve.INELIGIBLE, "ineligible": "unreadable: #41 x"},
            "unreadable risk": ALLOW | {"reviews": "unreadable: x"},
            "queue readError": ALLOW
            | {"queue": {"refusal": "held", "readError": "502", "commentError": None}},
            "queue commentError": ALLOW
            | {"queue": {"refusal": "held", "readError": None, "commentError": "403"}},
            "could not be read": MISSING
            | {"detail": "the closing issues could not be read"},
            "already cached": MISSING | {"cached": True},
        }
        for row, report in kept.items():
            with self.subTest(row):
                self.assertTrue(ve.answer_cacheable(report))
        for row, report in never.items():
            with self.subTest(row):
                self.assertFalse(ve.answer_cacheable(report))


class AnsweredTest(unittest.TestCase):
    """`main` with answers files: shadow reads in full, serve serves a hit."""

    def setUp(self) -> None:
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.answers_in = self.dir / "in.json"
        self.answers_out = self.dir / "out.json"
        self.world = World()
        self.fresh: dict[str, Any] = MISSING
        self.reads = 0

    def full_read(self, *_: Any) -> dict[str, Any]:
        self.reads += 1
        return copy.deepcopy(self.fresh)

    def current_key(self) -> str:
        return key(self.world)

    def keep(
        self, report: dict[str, Any], *, key_: str | None = None, **file: Any
    ) -> None:
        entry = {
            "key": key_ or self.current_key(),
            "readAt": NOW.isoformat(),
            "expiresAt": (NOW + timedelta(minutes=30)).isoformat(),
            "report": report,
        }
        data = {
            "version": ve.ANSWERS_VERSION,
            "repo": REPO,
            "code": ve._code_digest(),
            "entries": {str(PR): entry},
        } | file
        self.answers_in.write_text(json.dumps(data), encoding="utf-8")

    def run_main(self, *flags: str) -> dict[str, Any]:
        out = io.StringIO()
        self.world.calls.clear()
        argv = [
            "evidence",
            "--repo",
            REPO,
            "--lane-link",
            "--lane-reviews",
            "--lane-queue",
            "--shared-listing",
            "--base-sha",
            BASE,
            "--rung",
            "C2",
            "--answers-in",
            str(self.answers_in),
            "--answers-out",
            str(self.answers_out),
            *flags,
            str(PR),
            HEAD,
        ]
        with (
            github(self.world),
            mock.patch.object(ve, "_evidence_report", side_effect=self.full_read),
            mock.patch.object(
                ve.Reader, "listing", lambda r: copy.deepcopy(self.world.listing)
            ),
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            self.assertEqual(ve.main(argv, now=NOW), 0)
        return json.loads(out.getvalue())

    def written(self) -> dict[str, Any]:
        return json.loads(self.answers_out.read_text(encoding="utf-8"))["entries"]

    def test_serve_answers_a_hit_with_the_kept_refusal_and_only_the_probe(self) -> None:
        self.keep(MISSING)
        answer = self.run_main("--answers-mode", "serve")
        self.assertEqual(self.reads, 0)
        self.assertEqual([c[:2] for c in self.world.calls], [["api", "graphql"]])
        self.assertIs(answer["cached"], True)
        self.assertEqual(answer["refusal"], "verify:missing")
        self.assertEqual(answer["cache"]["key"], "hit")
        self.assertEqual(self.written()[str(PR)]["report"], MISSING)

    def test_shadow_never_serves_and_compares_the_kept_answer(self) -> None:
        self.keep(MISSING)
        answer = self.run_main()
        self.assertEqual(self.reads, 1)
        self.assertNotIn("cached", answer)
        self.assertEqual(
            answer["cache"],
            {
                "mode": "shadow",
                "key": "hit",
                "stored": "verify:missing",
                "fresh": "verify:missing",
                "agree": "yes",
            },
        )
        self.fresh = MISSING | {"refusal": "verify:fail"}
        self.assertEqual(self.run_main()["cache"]["agree"], "no")
        self.keep(MISSING)
        self.fresh = ALLOW
        answer = self.run_main()
        self.assertEqual(answer["refusal"], None)
        self.assertEqual(answer["cache"]["agree"], "no")
        # The fresh allow is never kept: the entry is dropped.
        self.assertEqual(self.written(), {})

    def test_any_mode_but_serve_is_shadow(self) -> None:
        self.keep(MISSING)
        for mode in ("shadow", "Serve", "serve ", ""):
            with self.subTest(mode):
                answer = self.run_main("--answers-mode", mode)
                self.assertNotIn("cached", answer)
                self.assertEqual(answer["cache"]["mode"], "shadow")

    def test_a_kept_allow_is_never_served(self) -> None:
        self.keep(ALLOW)
        self.fresh = MISSING | {"refusal": "verify:fail"}
        answer = self.run_main("--answers-mode", "serve")
        self.assertEqual(self.reads, 1)
        self.assertEqual(answer["refusal"], "verify:fail")
        self.assertEqual(answer["cache"]["key"], "miss")

    def test_a_moved_key_reads_in_full_and_keeps_the_new_refusal(self) -> None:
        self.keep(MISSING, key_="0" * 64)
        self.fresh = MISSING | {"refusal": "verify:earlier-fail"}
        answer = self.run_main("--answers-mode", "serve")
        self.assertEqual(self.reads, 1)
        self.assertEqual(answer["cache"]["key"], "miss")
        entry = self.written()[str(PR)]
        self.assertEqual(entry["report"]["refusal"], "verify:earlier-fail")
        self.assertEqual(entry["key"], self.current_key())

    def test_an_unreadable_answer_is_never_written(self) -> None:
        for report in (
            MISSING | {"refusal": ve.UNREADABLE, "detail": "listing 502"},
            ALLOW | {"reviews": "unreadable: x"},
            ALLOW
            | {"queue": {"refusal": "held", "readError": "502", "commentError": None}},
            ALLOW
            | {"queue": {"refusal": "held", "readError": None, "commentError": "403"}},
        ):
            with self.subTest(report=report):
                self.answers_out.unlink(missing_ok=True)
                self.keep(MISSING)
                self.fresh = report
                self.run_main()
                self.assertEqual(self.written(), {})

    def test_a_kept_refusal_expires_an_hour_after_its_read(self) -> None:
        self.answers_in.unlink(missing_ok=True)
        self.run_main()
        self.assertEqual(
            self.written()[str(PR)]["expiresAt"], "2026-10-16T13:00:00+00:00"
        )

    def test_a_kept_refusal_expires_when_the_pull_request_turns_too_old(self) -> None:
        # 80 days after 2026-07-28T12:30Z is 2026-10-16T12:30Z, before the hour.
        self.world.repository["pullRequest"]["createdAt"] = "2026-07-28T12:30:00Z"
        self.run_main()
        self.assertEqual(
            self.written()[str(PR)]["expiresAt"], "2026-10-16T12:30:00+00:00"
        )
        # A pull request already too old stays so: the hour holds.
        self.fresh = MISSING | {"refusal": "verify:too-old"}
        self.answers_out.unlink()
        self.run_main()
        self.assertEqual(
            self.written()[str(PR)]["expiresAt"], "2026-10-16T13:00:00+00:00"
        )

    def test_a_kept_refusal_expires_with_a_pass_artifact_at_the_head(self) -> None:
        self.world.listing.append(
            artifact(f"pr-verify-{PR}-{HEAD}-pass", 8, expires="2026-10-16T12:10:00Z")
        )
        self.world.runs[8] = run_record(8)
        self.fresh = MISSING | {"refusal": "verify:spec-changed"}
        self.run_main()
        self.assertEqual(
            self.written()[str(PR)]["expiresAt"], "2026-10-16T12:10:00+00:00"
        )

    def test_an_expired_entry_is_not_served(self) -> None:
        self.keep(MISSING)
        data = json.loads(self.answers_in.read_text(encoding="utf-8"))
        data["entries"][str(PR)]["expiresAt"] = NOW.isoformat()
        self.answers_in.write_text(json.dumps(data), encoding="utf-8")
        self.run_main("--answers-mode", "serve")
        self.assertEqual(self.reads, 1)

    def test_a_file_of_another_shape_repository_version_or_code_is_a_miss(self) -> None:
        cases: dict[str, Callable[[], None]] = {
            "malformed": lambda: self.answers_in.write_text("{", encoding="utf-8"),
            "another repository": lambda: self.keep(MISSING, repo="other/repo"),
            "another version": lambda: self.keep(MISSING, version=2),
            "another code": lambda: self.keep(MISSING, code="0" * 64),
            "entries not a map": lambda: self.keep(MISSING, entries=[]),
        }
        for row, write in cases.items():
            with self.subTest(row):
                self.reads = 0
                write()
                answer = self.run_main("--answers-mode", "serve")
                self.assertEqual(self.reads, 1)
                self.assertEqual(answer["cache"]["key"], "miss")

    def test_a_probe_failure_reads_in_full_and_keeps_nothing(self) -> None:
        self.keep(MISSING)
        self.world.repository["pullRequest"]["headRefOid"] = OTHER
        answer = self.run_main("--answers-mode", "serve")
        self.assertEqual(self.reads, 1)
        self.assertEqual(answer["cache"]["key"], "miss")
        self.assertEqual(self.written(), {})

    def test_answers_only_serves_a_hit_and_never_reads_on_a_miss(self) -> None:
        self.keep(MISSING)
        hit = self.run_main("--answers-mode", "serve", "--answers-only")
        self.assertIs(hit["cached"], True)
        self.keep(MISSING, key_="0" * 64)
        miss = self.run_main("--answers-mode", "serve", "--answers-only")
        self.assertEqual(self.reads, 0)
        self.assertEqual(miss, {"head": HEAD, "cached": False, "cache": miss["cache"]})
        self.assertNotIn("refusal", miss)
        # Under shadow a cache-only call reads nothing either.
        self.keep(MISSING)
        self.assertNotIn("refusal", self.run_main("--answers-only"))
        self.assertEqual(self.reads, 0)

    def test_the_out_file_carries_the_last_runs_other_entries(self) -> None:
        self.keep(MISSING)
        data = json.loads(self.answers_in.read_text(encoding="utf-8"))
        data["entries"]["7"] = data["entries"][str(PR)] | {"key": "f" * 64}
        self.answers_in.write_text(json.dumps(data), encoding="utf-8")
        self.fresh = ALLOW
        self.run_main()
        self.assertEqual(list(self.written()), ["7"])
        # A later pull request of the same run adds to this run's file.
        self.fresh = MISSING
        self.answers_in.unlink()
        self.run_main()
        self.assertEqual(sorted(self.written()), [str(PR), "7"])

    def test_without_answers_files_main_prints_the_full_read_alone(self) -> None:
        out = io.StringIO()
        with (
            mock.patch.object(ve, "_evidence_report", side_effect=self.full_read),
            mock.patch.object(ve, "_answer_key") as probe_,
            contextlib.redirect_stdout(out),
        ):
            ve.main(["evidence", "--repo", REPO, str(PR), HEAD], now=NOW)
        probe_.assert_not_called()
        self.assertEqual(json.loads(out.getvalue()), MISSING)


if __name__ == "__main__":
    unittest.main()

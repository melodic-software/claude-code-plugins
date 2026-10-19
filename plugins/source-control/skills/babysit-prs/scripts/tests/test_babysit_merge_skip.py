"""pr-merge's skip of unchanged refusals: a candidate is set aside only when
the last run that gated it refused it on the same key, and never allowed.

Expected values come from the owner's design for this cut: the key covers the
head, `updatedAt`, labels, the base the gate reads its config at, the check
rollup, review and thread state, the verdict artifacts and the default
branch's config and gate code; a skip repeats only an allow-listed refusal,
inside a recheck limit, and any doubt gates the candidate.
"""

from __future__ import annotations

import copy
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_skip as skip
import babysit_verify_evidence as verify_evidence

NOW = datetime(2026, 10, 19, 12, 0, tzinfo=UTC)
HEAD = "a" * 40
BASE = "b" * 40
MAIN = {path: "c" * 40 for path in skip.MAIN_PATHS}


def _node(number: int = 7, head: str = HEAD) -> dict:
    return {
        "number": number,
        "headRefOid": head,
        "baseRefOid": BASE,
        "isInMergeQueue": False,
        "updatedAt": "2026-10-19T10:00:00Z",
        "reviewDecision": None,
        "labels": {"totalCount": 1, "nodes": [{"name": "lane"}]},
        "reviews": {"totalCount": 0},
        "comments": {
            "totalCount": 1,
            "nodes": [{"databaseId": 11, "updatedAt": "2026-10-19T09:00:00Z"}],
        },
        "reviewThreads": {
            "totalCount": 1,
            "nodes": [{"isResolved": False, "isOutdated": False}],
        },
        "closingIssuesReferences": {
            "totalCount": 1,
            "nodes": [
                {
                    "number": 3,
                    "updatedAt": "2026-10-18T00:00:00Z",
                    "lastEditedAt": None,
                    "comments": {"totalCount": 2},
                }
            ],
        },
        "commits": {
            "nodes": [
                {
                    "commit": {
                        "oid": head,
                        "statusCheckRollup": {
                            "contexts": {
                                "totalCount": 2,
                                "nodes": [
                                    {
                                        "__typename": "CheckRun",
                                        "databaseId": 100,
                                        "name": "claude-review-status",
                                        "status": "COMPLETED",
                                        "conclusion": "SUCCESS",
                                    },
                                    {
                                        "__typename": "StatusContext",
                                        "context": "ci/legacy",
                                        "state": "SUCCESS",
                                        "createdAt": "2026-10-19T09:30:00Z",
                                    },
                                ],
                            }
                        },
                    }
                }
            ]
        },
    }


def _candidate(number: int = 7, head: str = HEAD) -> dict:
    return {"number": number, "head": head, "updatedAt": "2026-10-19T10:00:00Z"}


ARTIFACTS = [
    {"id": 5, "name": f"pr-verify-7-{HEAD}-fail", "expired": False},
    {"id": 6, "name": f"pr-verify-8-{'d' * 40}-pass", "expired": False},
]


def _key(node: dict | None = None, **over) -> str:
    state = skip.pr_state(node or _node())
    assert state is not None
    args = {
        "candidate": _candidate(),
        "artifacts": skip.verdicts(ARTIFACTS, 7, HEAD),
        "main": MAIN,
        "rung_cap": "",
    }
    args.update(over)
    return skip.state_key(
        args["candidate"], state, args["artifacts"], args["main"], args["rung_cap"]
    )


def _row(number: int = 7, reason: str = "risk:MED") -> dict:
    return {
        "pr": number,
        "head": HEAD,
        "updatedAt": "2026-10-19T10:00:00Z",
        "exit": 10,
        "ready": False,
        "enqueued": False,
        "merged": False,
        "reportOnly": False,
        "reason": reason,
        "dispatched": None,
        "blockers": [f"unattended merge refused: {reason}"],
    }


def _stored(
    key: str, *, reason: str = "risk:MED", minutes: int = 10, skips: int = 0
) -> dict:
    at = (NOW - timedelta(minutes=minutes)).isoformat()
    return {
        "at": at,
        "value": {
            "key": key,
            "head": HEAD,
            "reason": reason,
            "row": _row(reason=reason),
            "skips": skips,
            "runId": "41",
        },
    }


def _select(
    store: dict,
    *,
    key: str | None = None,
    in_queue: bool = False,
    pass_at_head: bool = False,
    candidates=None,
):
    keys = {
        7: {
            "key": key or _key(),
            "head": HEAD,
            "skippable": not in_queue,
            "passAtHead": pass_at_head,
        }
    }
    if candidates is not None:
        keys[8] = {
            "key": "f" * 64,
            "head": HEAD,
            "skippable": True,
            "passAtHead": False,
        }
    return skip.select(
        candidates or [_candidate()],
        keys,
        store,
        at=NOW,
        max_minutes=60,
        max_skips=3,
    )


class TheKeyCoversEveryInput(unittest.TestCase):
    def test_the_same_inputs_give_the_same_key(self) -> None:
        self.assertEqual(_key(), _key(copy.deepcopy(_node())))

    def test_a_change_to_any_input_changes_the_key(self) -> None:
        def node_with(path, value):
            node = _node()
            target = node
            for part in path[:-1]:
                target = target[part]
            target[path[-1]] = value
            return node

        rollup = (
            "commits",
            "nodes",
            0,
            "commit",
            "statusCheckRollup",
            "contexts",
            "nodes",
        )
        changed = {
            "base": node_with(("baseRefOid",), "e" * 40),
            "updatedAt": node_with(("updatedAt",), "2026-10-19T11:00:00Z"),
            "label": node_with(("labels", "nodes"), [{"name": "other"}]),
            "review decision": node_with(("reviewDecision",), "APPROVED"),
            "review count": node_with(("reviews", "totalCount"), 1),
            "thread resolved": node_with(
                ("reviewThreads", "nodes"), [{"isResolved": True, "isOutdated": False}]
            ),
            "comment edited": node_with(
                ("comments", "nodes"),
                [{"databaseId": 11, "updatedAt": "2026-10-19T11:00:00Z"}],
            ),
            "issue edited": node_with(
                ("closingIssuesReferences", "nodes", 0, "lastEditedAt"),
                "2026-10-19T11:00:00Z",
            ),
        }
        rerun = _node()
        nodes = rerun["commits"]["nodes"][0]["commit"]["statusCheckRollup"]["contexts"][
            "nodes"
        ]
        nodes[0] = {**nodes[0], "databaseId": 101}
        changed["check re-run"] = rerun
        concluded = _node()
        target = concluded
        for part in rollup:
            target = target[part]
        target[0] = {**target[0], "conclusion": "FAILURE"}
        changed["check conclusion"] = concluded
        status = _node()
        target = status
        for part in rollup:
            target = target[part]
        target[1] = {**target[1], "state": "FAILURE"}
        changed["status state"] = status
        baseline = _key()
        for name, node in changed.items():
            with self.subTest(name):
                self.assertNotEqual(_key(node), baseline)
        others = {
            "listed head": {"candidate": {**_candidate(), "head": "e" * 40}},
            "listed updatedAt": {
                "candidate": {**_candidate(), "updatedAt": "2026-10-19T11:00:00Z"}
            },
            "new verdict": {
                "artifacts": [
                    *skip.verdicts(ARTIFACTS, 7, HEAD),
                    [9, f"pr-verify-7-{HEAD}-pass"],
                ]
            },
            "config on main": {
                "main": {**MAIN, "docs/conventions/pr-pipeline.yaml": "e" * 40}
            },
            "gate code on main": {
                "main": {
                    **MAIN,
                    "plugins/source-control/skills/babysit-prs/scripts": "e" * 40,
                }
            },
            "rung cap": {"rung_cap": "off"},
        }
        for name, over in others.items():
            with self.subTest(name):
                self.assertNotEqual(_key(**over), baseline)

    def test_the_verdicts_are_those_naming_the_pr_or_its_head_and_unexpired(
        self,
    ) -> None:
        listing = [
            {"id": 1, "name": f"pr-verify-7-{'e' * 40}-fail", "expired": False},
            {"id": 2, "name": f"pr-verify-9-{HEAD}-fail", "expired": False},
            {"id": 3, "name": f"pr-verify-9-{'e' * 40}-fail", "expired": False},
            {"id": 4, "name": f"pr-verify-7-{HEAD}-pass", "expired": True},
            {"id": 5, "name": "pr-merge-gate-cursor", "expired": False},
        ]
        self.assertEqual([i for i, _ in skip.verdicts(listing, 7, HEAD)], [1, 2])

    def test_a_cut_short_or_mismatched_read_gives_no_state(self) -> None:
        cut = _node()
        cut["commits"]["nodes"][0]["commit"]["statusCheckRollup"]["contexts"][
            "totalCount"
        ] = 101
        threads = _node()
        threads["reviewThreads"]["totalCount"] = 2
        moved = _node()
        moved["commits"]["nodes"][0]["commit"]["oid"] = "e" * 40
        labels = _node()
        labels["labels"]["totalCount"] = 101
        for name, node in {
            "rollup": cut,
            "threads": threads,
            "head": moved,
            "labels": labels,
        }.items():
            with self.subTest(name):
                self.assertIsNone(skip.pr_state(node))


class ASkipRepeatsOnlyAnUnchangedAllowedRefusal(unittest.TestCase):
    def test_when_every_candidate_would_be_skipped_the_first_is_gated(self) -> None:
        kept, rows, carried = _select({"7": _stored(_key())})
        self.assertEqual(kept, [_candidate()])
        self.assertEqual((rows, carried), ([], {}))

    def test_a_skipped_row_reports_the_earlier_refusal_as_carried(self) -> None:
        store = {"7": _stored(_key())}
        kept, rows, carried = _select(store, candidates=[_candidate(), _candidate(8)])
        self.assertEqual(kept, [_candidate(8)])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["reason"], "risk:MED")
        self.assertEqual(rows[0]["pr"], 7)
        self.assertEqual(
            rows[0]["carried"],
            {"judgedAt": store["7"]["at"], "skips": 1, "runId": "41"},
        )
        self.assertEqual(carried["7"]["at"], store["7"]["at"])
        self.assertEqual(carried["7"]["value"]["skips"], 1)

    def test_a_refusal_is_gated_again_when_anything_is_off(self) -> None:
        key = _key()
        cases = {
            "another key": ({"7": _stored("e" * 64)}, {}),
            "verify unreadable": ({"7": _stored(key, reason="verify:unreadable")}, {}),
            "in flight": ({"7": _stored(key, reason="in-flight:5")}, {}),
            "a moved head": (
                {
                    "7": {
                        **_stored(key),
                        "value": {**_stored(key)["value"], "head": "e" * 40},
                    }
                },
                {},
            ),
            "judged 60 minutes ago": ({"7": _stored(key, minutes=60)}, {}),
            "dated in the future": ({"7": _stored(key, minutes=-1)}, {}),
            "skipped 3 runs in a row": ({"7": _stored(key, skips=3)}, {}),
            "in the merge queue": ({"7": _stored(key)}, {"in_queue": True}),
            "missing with a PASS at the head": (
                {"7": _stored(key, reason="verify:missing")},
                {"pass_at_head": True},
            ),
            "no record": ({}, {}),
            "a malformed record": ({"7": {"at": "yesterday", "value": []}}, {}),
        }
        for name, (store, over) in cases.items():
            with self.subTest(name):
                kept, rows, _ = _select(
                    store, candidates=[_candidate(), _candidate(8)], **over
                )
                self.assertIn(_candidate(), kept)
                self.assertEqual(rows, [])

    def test_inside_the_limits_a_refusal_is_skipped(self) -> None:
        key = _key()
        for name, stored in {
            "judged 59 minutes ago": _stored(key, minutes=59),
            "skipped twice": _stored(key, skips=2),
            "verify missing with no PASS at the head": _stored(
                key, reason="verify:missing"
            ),
            "verify fail": _stored(key, reason="verify:fail"),
        }.items():
            with self.subTest(name):
                kept, rows, _ = _select(
                    {"7": stored}, candidates=[_candidate(), _candidate(8)]
                )
                self.assertEqual(kept, [_candidate(8)])
                self.assertEqual([r["pr"] for r in rows], [7])

    def test_a_forged_record_is_reported_as_a_refusal_only(self) -> None:
        # The store comes from a cache entry any default-branch job can write.
        forged = _stored(_key())
        forged["value"]["row"] = {
            **_row(),
            "ready": True,
            "enqueued": True,
            "merged": True,
            "dispatched": True,
            "blockers": ["x" * 400, *["y"] * 30],
        }
        _, rows, _ = _select({"7": forged}, candidates=[_candidate(), _candidate(8)])
        self.assertEqual(
            [
                (r["ready"], r["enqueued"], r["merged"], r["dispatched"], r["exit"])
                for r in rows
            ],
            [(False, False, False, None, 10)],
        )
        self.assertEqual(len(rows[0]["blockers"]), 20)
        self.assertEqual(len(rows[0]["blockers"][0]), 300)

    def test_a_candidate_with_no_key_is_gated(self) -> None:
        kept, rows, _ = skip.select(
            [_candidate(), _candidate(8)],
            {},
            {"7": _stored(_key())},
            at=NOW,
            max_minutes=60,
            max_skips=3,
        )
        self.assertEqual(kept, [_candidate(), _candidate(8)])
        self.assertEqual(rows, [])

    def test_the_limits_read_empty_as_the_default_and_anything_else_as_off(
        self,
    ) -> None:
        self.assertEqual(skip.limit("", 60), 60)
        self.assertEqual(skip.limit("null", 60), 60)
        self.assertEqual(skip.limit("45", 60), 45)
        self.assertEqual(skip.limit("0", 60), 0)
        self.assertEqual(skip.limit("ten", 60), 0)
        self.assertEqual(skip.limit("-5", 60), 0)


def _output(**over) -> dict:
    out = {
        "headMatches": True,
        "headRefOid": HEAD,
        "ready": False,
        "unattended": {
            "reason": "risk:MED",
            "writes": {"dequeued": [], "holds": {}, "errors": []},
        },
    }
    out.update(over)
    return out


def _keys_doc(**over) -> dict:
    doc = {
        "v": 1,
        "at": NOW.isoformat(),
        "keys": {"7": {"key": "e" * 64, "head": HEAD}},
        "carried": {},
        "prior": {},
    }
    doc.update(over)
    return doc


class TheRecordKeepsOnlyRefusalsTheNextGateWouldRepeat(unittest.TestCase):
    def _record(self, row=None, output=None, keys=None):
        return skip.record(
            keys or _keys_doc(),
            [row or _row()],
            lambda n: output if output is not None else _output(),
            "42",
        )

    def test_a_gated_allowed_refusal_is_stored_with_no_skips(self) -> None:
        section = self._record()
        self.assertEqual(
            section["7"],
            {
                "at": NOW.isoformat(),
                "value": {
                    "key": "e" * 64,
                    "head": HEAD,
                    "reason": "risk:MED",
                    "row": _row(),
                    "skips": 0,
                    "runId": "42",
                },
            },
        )

    def test_a_refusal_with_work_left_is_not_stored(self) -> None:
        writes = {"dequeued": [], "holds": {}, "errors": ["reasons comment: HTTP 502"]}
        cases = {
            "a failed write": (
                _row(),
                _output(unattended={"reason": "risk:MED", "writes": writes}),
            ),
            "a review re-run due": (
                _row(),
                _output(
                    aiReviewReruns=[
                        {
                            "check": "claude-review",
                            "rerun": False,
                            "reason": "waiting for the usage limit to reset; re-run due at 2026-10-19T13:00:00Z",
                        }
                    ]
                ),
            ),
            "a failed re-run request": (
                _row(),
                _output(
                    aiReviewReruns=[
                        {
                            "check": "claude-review",
                            "rerun": False,
                            "reason": "re-run request failed: HTTP 403",
                        }
                    ]
                ),
            ),
            "a moved head": (_row(), _output(headMatches=False)),
            "a gate error": (_row(), _output(error="RuntimeError: boom")),
            "a pending merge request": (
                _row(),
                _output(pendingMergeRequest={"uuid": "x"}),
            ),
            "a merge": ({**_row(), "exit": 0, "reason": None}, _output()),
            "an unlisted reason": (_row(reason="in-flight:5"), _output()),
            "verify unreadable": (_row(reason="verify:unreadable"), _output()),
        }
        for name, (row, output) in cases.items():
            with self.subTest(name):
                self.assertEqual(self._record(row, output), {})

    def test_a_review_re_run_the_next_gate_repeats_does_not_stop_the_record(
        self,
    ) -> None:
        output = _output(
            aiReviewReruns=[
                {
                    "check": "claude-review",
                    "rerun": False,
                    "reason": "failure class is not rate-limit; never re-run",
                }
            ]
        )
        self.assertIn("7", self._record(output=output))

    def test_a_skipped_record_is_carried_with_its_judgment_time_and_an_unreached_one_kept(
        self,
    ) -> None:
        carried = _stored("e" * 64, skips=1)
        earlier = _stored("d" * 64)
        keys = _keys_doc(
            keys={
                "7": {"key": "e" * 64, "head": HEAD},
                "8": {"key": "d" * 64, "head": HEAD},
                "9": {"key": "c" * 64, "head": HEAD},
            },
            carried={"7": carried},
            prior={"8": earlier},
        )
        section = skip.record(
            keys, [{**_row(), "carried": {"skips": 1}}], lambda n: None, "42"
        )
        self.assertEqual(section, {"7": carried, "8": earlier})

    def test_a_gate_output_wins_over_a_carried_record(self) -> None:
        keys = _keys_doc(carried={"7": _stored("e" * 64, skips=2)})
        section = skip.record(keys, [_row()], lambda n: _output(), "42")
        self.assertEqual(section["7"]["value"]["skips"], 0)


def _git(root: pathlib.Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)


class FilterThenRecordEndToEnd(unittest.TestCase):
    """The two subcommands on files, with GitHub faked and a real clone."""

    def setUp(self) -> None:
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(subprocess.run, ["rm", "-rf", str(self.dir)], check=False)
        base = self.dir / "base"
        (base / "docs/conventions").mkdir(parents=True)
        (base / "docs/conventions/pr-pipeline.yaml").write_text("merge: {}\n")
        _git(base.parent, "init", "-q", str(base))
        _git(base, "-c", "user.email=t@t", "-c", "user.name=t", "add", ".")
        _git(base, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "c")
        self.base = base
        self.store = self.dir / "carried.json"
        self.candidates = self.dir / "candidates.json"

    def _graphql(self, nodes):
        def fake(args):
            query = next(a for a in args if a.startswith("query="))
            repository = {
                f"p{n['number']}": n for n in nodes if f"p{n['number']}:" in query
            }
            return {"data": {"rateLimit": {"cost": 1}, "repository": repository}}

        return fake

    def _filter(self, nodes, at=NOW):
        self.candidates.write_text(json.dumps([_candidate(7), _candidate(8)]))
        with (
            mock.patch.object(skip, "gh_json", self._graphql(nodes)),
            mock.patch.object(
                verify_evidence.Reader, "listing", lambda self: ARTIFACTS
            ),
            mock.patch.object(skip, "now", lambda: at),
        ):
            code = skip.main(
                [
                    "filter",
                    "--repo",
                    "o/r",
                    "--base",
                    str(self.base),
                    "--store",
                    str(self.store),
                    "--candidates",
                    str(self.candidates),
                    "--out-keys",
                    str(self.dir / "keys.json"),
                    "--out-skipped",
                    str(self.dir / "skipped.json"),
                ]
            )
        self.assertEqual(code, 0)
        return (
            json.loads(self.candidates.read_text()),
            json.loads((self.dir / "skipped.json").read_text()),
        )

    def _record(self, rows, outputs):
        (self.dir / "summary.json").write_text(json.dumps(rows))
        for number, output in outputs.items():
            (self.dir / f"gate-{number}.json").write_text(json.dumps(output))
        self.store.write_text(json.dumps({"carried-run-record": {}}))
        code = skip.main(
            [
                "record",
                "--keys",
                str(self.dir / "keys.json"),
                "--summary",
                str(self.dir / "summary.json"),
                "--outputs-dir",
                str(self.dir),
                "--store",
                str(self.store),
                "--run-id",
                "42",
            ]
        )
        self.assertEqual(code, 0)

    def test_a_refusal_is_skipped_on_the_next_run_and_gated_once_its_inputs_change(
        self,
    ) -> None:
        nodes = [_node(7), _node(8)]
        kept, skipped = self._filter(nodes)
        self.assertEqual([c["number"] for c in kept], [7, 8])
        self.assertEqual(skipped, [])
        self._record(
            [_row(7), {**_row(8), "exit": 0, "reason": None}],
            {7: _output(), 8: _output()},
        )
        stored = json.loads(self.store.read_text())
        self.assertEqual(set(stored), {"carried-run-record", skip.SECTION})
        self.assertEqual(set(stored[skip.SECTION]), {"7"})

        kept, skipped = self._filter(nodes, at=NOW + timedelta(minutes=15))
        self.assertEqual([c["number"] for c in kept], [8])
        self.assertEqual(
            [(r["pr"], r["reason"], r["carried"]["skips"]) for r in skipped],
            [(7, "risk:MED", 1)],
        )

        rerun = _node(7)
        rerun["commits"]["nodes"][0]["commit"]["statusCheckRollup"]["contexts"][
            "nodes"
        ][0]["databaseId"] = 101
        self.store.write_text(json.dumps(stored))
        kept, skipped = self._filter([rerun, _node(8)], at=NOW + timedelta(minutes=15))
        self.assertEqual([c["number"] for c in kept], [7, 8])
        self.assertEqual(skipped, [])

    def test_a_failed_listing_skips_nothing_and_leaves_the_candidates(self) -> None:
        self.candidates.write_text(json.dumps([_candidate(7)]))

        def fail(self):
            raise RuntimeError("repository artifacts: HTTP 502")

        with mock.patch.object(verify_evidence.Reader, "listing", fail):
            code = skip.main(
                [
                    "filter",
                    "--repo",
                    "o/r",
                    "--base",
                    str(self.base),
                    "--candidates",
                    str(self.candidates),
                    "--out-keys",
                    str(self.dir / "keys.json"),
                    "--out-skipped",
                    str(self.dir / "skipped.json"),
                ]
            )
        self.assertNotEqual(code, 0)
        self.assertEqual(json.loads(self.candidates.read_text()), [_candidate(7)])
        self.assertFalse((self.dir / "skipped.json").exists())

    def test_the_main_inputs_name_each_path_or_absent(self) -> None:
        inputs = skip.main_inputs(self.base)
        self.assertEqual(set(inputs), set(skip.MAIN_PATHS))
        self.assertRegex(inputs["docs/conventions/pr-pipeline.yaml"], r"^[0-9a-f]{40}$")
        self.assertEqual(inputs[".claude/source-control.md"], "absent")


class TheReaderListingRaisesOnAFailedRead(unittest.TestCase):
    def test_an_unreadable_listing_raises_runtime_error(self) -> None:
        reader = verify_evidence.Reader(
            "o/r", "main", actions_token=None, listing_path=None
        )
        with (
            mock.patch.object(
                verify_evidence.Reader,
                "_listing",
                side_effect=verify_evidence._Unreadable("HTTP 502"),
            ),
            self.assertRaisesRegex(RuntimeError, "HTTP 502"),
        ):
            reader.listing()


if __name__ == "__main__":
    unittest.main()

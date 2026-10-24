"""The pr-merge lane's room for one more native merge (`lane_room`).

Expected values come from the gate's own run-level refusals, which native
auto-merge skips: `effective_rung` (the lowest of `merge.rung`,
`babysit_loop_merge`, the rung cap and the demotion; an unknown or missing cap
is off, an empty one no cap), a post-merge refusal, an authority other than
pr-merge, and `in_flight`'s count against `merge.max-in-flight`. A read that
fails refuses nothing and allows nothing (`unreadable`).
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import sys
import unittest
from datetime import UTC, datetime, timedelta
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy  # noqa: E402
import babysit_postmerge as pm  # noqa: E402
import babysit_verify_evidence as ve  # noqa: E402

REPO = "example-org/example-repo"
IDENTITY = "agent-lanes[bot]"
MAIN = "c" * 40
FLOOR = datetime(2026, 10, 1, tzinfo=UTC)
# Five minutes after the answer was computed: inside the gate's reuse age.
NOW = FLOOR + timedelta(minutes=5)
# The default branch head and floor a recompute reads.
NEW_MAIN = "e" * 40
NEW_FLOOR = FLOOR + timedelta(minutes=1)
# A passing answer with lane merge #5 still unverified, read three minutes on:
# past the two minutes the gate reuses it (issue #9577's 2:01 read).
PENDING = {
    "readable": True,
    "ok": True,
    "autoMerges": [
        {"number": 5, "verified": False, "mergedAt": "2026-10-01T00:00:00Z"}
    ],
    "excusesExpireAt": None,
}
STALE_NOW = FLOOR + timedelta(minutes=3)


def config(**overrides: object) -> policy.PipelineConfig:
    fields = {
        "base_sha": MAIN,
        "rung": "C2",
        "authority": "pr-merge",
        "agent_identity": IDENTITY,
        "max_changed_lines": None,
        "denied_paths": (),
        "loop_merge": "c2-mechanical",
    }
    fields.update(overrides)
    return policy.PipelineConfig(**fields)  # type: ignore[arg-type]


def shared(
    *,
    demoted: bool = False,
    refusal: str | None = None,
    identity: str = IDENTITY,
    report: dict[str, object] | None = None,
) -> policy.SharedPostMerge:
    return policy.SharedPostMerge(
        main_sha=MAIN,
        config_sha=MAIN,
        identity=identity,
        self_logins=frozenset(),
        lane_merges_only=True,
        computed_at=FLOOR,
        demotion=policy.Demotion(
            demoted, "record-open" if demoted else None, (7,) if demoted else ()
        ),
        floor=FLOOR,
        gate=policy.PostMergeGate(refusal, report or {}, lambda merge: True),
    )


class Recheck:
    """A fake post-merge check: `gate` or `error`, with each floor and
    identity it was asked for."""

    def __init__(
        self, gate: policy.PostMergeGate | None = None, error: Exception | None = None
    ) -> None:
        self.gate, self.error = gate, error
        self.asked: list[tuple[datetime, str]] = []

    def post_merge(self, floor: datetime, identity: str) -> policy.PostMergeGate:
        self.asked.append((floor, identity))
        if self.error is not None:
            raise self.error
        assert self.gate is not None
        return self.gate


def run(
    workflow: str, *, status: str, updated: datetime, created: datetime = FLOOR
) -> dict[str, object]:
    """One row of the actions runs listing."""
    return {
        "path": f".github/workflows/{workflow}",
        "status": status,
        "created_at": created.isoformat(),
        "updated_at": updated.isoformat(),
    }


class LaneRoom(unittest.TestCase):
    def room(
        self,
        answer: policy.SharedPostMerge | None = None,
        *,
        cfg: policy.PipelineConfig | None = None,
        cap: str | None = "",
        flight: policy.InFlight | None = None,
        config_error: Exception | None = None,
        now: datetime = NOW,
        demotion_changed: bool = False,
        post_merge: object = None,
        runs_unchanged: object = None,
        head: str = NEW_MAIN,
        config_commit: str = MAIN,
        fresh_floor: datetime = NEW_FLOOR,
        head_error: Exception | None = None,
        fresh_demotion: policy.Demotion | None = None,
    ) -> policy.LaneRoom:
        seen: dict[str, object] = {}

        def in_flight(repo: str, **kwargs: object) -> policy.InFlight:
            seen.update(kwargs)
            return flight or policy.InFlight(True, None, frozenset({11}), 0, 2)

        with (
            mock.patch.object(policy, "_default_branch", return_value="main"),
            mock.patch.object(
                policy,
                "_default_branch_config",
                side_effect=config_error,
                return_value=cfg or config(),
            ),
            mock.patch.object(
                policy, "_run_max_in_flight", return_value=(5, "default-branch")
            ),
            mock.patch.object(policy, "in_flight", side_effect=in_flight),
            mock.patch.object(
                policy, "_demotion_changed", return_value=demotion_changed
            ),
            # shared_refusal's reads: the answer's own config commit and main
            # head, so only its age and demotion decide.
            mock.patch.object(
                policy, "newest_config_commit", return_value=config_commit
            ),
            mock.patch.object(policy, "_get", return_value=(200, {"sha": MAIN})),
            # The recompute's reads at the default branch head: a newer head,
            # no demotion record, and a later floor than the old answer's.
            mock.patch.object(
                policy,
                "_default_branch_head",
                side_effect=head_error,
                return_value=("main", head),
            ),
            mock.patch.object(policy, "permission_reader"),
            mock.patch.object(
                policy,
                "read_demotion",
                return_value=fresh_demotion or policy.Demotion(False, None, ()),
            ),
            mock.patch.object(policy, "merged_since_floor", return_value=fresh_floor),
        ):
            kwargs = {"post_merge": post_merge} if post_merge is not None else {}
            if runs_unchanged is not None:
                kwargs["runs_unchanged"] = runs_unchanged
            result = policy.lane_room(
                REPO,
                answer if answer is not None else shared(),
                lane_rung_cap=cap,
                now=now,
                **kwargs,  # type: ignore[arg-type]
            )
        self.seen = seen
        return result

    def test_a_clear_lane_counts_its_merges_in_flight_against_the_cap(self) -> None:
        room = self.room()
        self.assertEqual(
            (room.refusal, room.unreadable, room.count, room.cap, room.queued),
            (None, None, 2, 5, frozenset({11})),
        )
        # The rung the gate scores at: merge.rung C2, the loop setting c2.
        self.assertEqual(room.rung, "C2")
        self.assertEqual(self.room(cap="C2").rung, "C2")
        # The lane's own merges, since the post-merge floor, judged by its check.
        self.assertEqual(
            (
                self.seen["lane_merges_only"],
                self.seen["merged_since"],
                self.seen["max_in_flight"],
            ),
            (True, FLOOR, 5),
        )

    def test_a_demotion_holds_the_lane_off(self) -> None:
        self.assertEqual(self.room(shared(demoted=True)).refusal, "rung-off:demotion")

    def test_a_rung_cap_of_off_or_a_missing_cap_holds_it_off(self) -> None:
        self.assertEqual(self.room(cap="off").refusal, "rung-off:rungCap")
        self.assertEqual(self.room(cap=None).refusal, "rung-off:rungCap")
        self.assertIsNone(self.room(cap="C2").refusal)

    def test_merge_rung_or_the_loop_setting_off_holds_it_off(self) -> None:
        self.assertEqual(
            self.room(cfg=config(rung="off")).refusal, "rung-off:merge.rung"
        )
        self.assertEqual(
            self.room(cfg=config(loop_merge="human-only")).refusal,
            "rung-off:babysit_loop_merge",
        )

    def test_a_post_merge_failure_holds_it_off(self) -> None:
        room = self.room(shared(refusal="failure:red-main#40"))
        self.assertEqual(room.refusal, "post-merge:failure:red-main#40")

    def test_another_authority_holds_it_off(self) -> None:
        room = self.room(cfg=config(authority="local-babysit"))
        self.assertEqual(room.refusal, policy.AUTHORITY_UNCONFIGURED)

    def test_at_the_cap_it_reports_the_cap_and_refuses_nothing(self) -> None:
        full = policy.InFlight(False, "identity-entry-queued:#14", frozenset({10, 14}))
        room = self.room(flight=full)
        self.assertEqual(
            (room.refusal, room.unreadable, room.count, room.cap), (None, None, 5, 5)
        )

    def test_an_answer_the_gate_would_not_reuse_is_unreadable(self) -> None:
        # The gate reads afresh past SHARED_MAX_AGE or after a demotion record
        # changed (shared_refusal); a re-run job reads the run's first report.
        cases = {
            "stale": dict(now=FLOOR + policy.SHARED_MAX_AGE + timedelta(seconds=1)),
            "future": dict(now=FLOOR - timedelta(seconds=1)),
            # Inside the two minutes: past them the answer is read again,
            # demotion included.
            "demotion changed": dict(
                demotion_changed=True, now=FLOOR + timedelta(minutes=1)
            ),
        }
        recheck = Recheck(policy.PostMergeGate(None, {"readable": True}, None))
        for name, kwargs in cases.items():
            with self.subTest(name):
                room = self.room(
                    shared(report=PENDING),
                    post_merge=recheck.post_merge,
                    **kwargs,  # type: ignore[arg-type]
                )
                self.assertIsNone(room.refusal)
                self.assertTrue(room.unreadable)
        self.assertFalse(self.seen, "no in-flight read after an unusable answer")
        # Only an unverified-stale answer is read again.
        self.assertEqual(recheck.asked, [])

    def test_a_lane_merge_the_answer_does_not_count_is_unreadable(self) -> None:
        # The gate's reuse rule (shared_refusal) reads afresh when a lane
        # merge landed after the report was computed (`new-merge:#<n>`), so
        # its failed full run is not missed; the room holds rather than arm.
        seen: list[dict[str, object]] = []

        def refusal(repo: str, answer: object, **kwargs: object) -> str:
            seen.append(kwargs)
            return "new-merge:#7"

        recheck = Recheck(policy.PostMergeGate(None, {"readable": True}, None))
        with mock.patch.object(policy, "shared_refusal", side_effect=refusal):
            room = self.room(post_merge=recheck.post_merge)
        self.assertEqual(
            (room.refusal, room.unreadable),
            (None, "post-merge answer new-merge:#7"),
        )
        self.assertFalse(self.seen, "no in-flight read after an unusable answer")
        self.assertEqual(recheck.asked, [])
        # Bound as the gate binds a candidate at the default branch head.
        self.assertEqual(
            {
                k: seen[0][k]
                for k in ("branch", "base_sha", "identity", "lane", "authority")
            },
            {
                "branch": "main",
                "base_sha": MAIN,
                "identity": IDENTITY,
                "lane": True,
                "authority": "pr-merge",
            },
        )
        self.assertEqual(seen[0]["self_logins"], frozenset())

    def test_a_pending_merge_past_two_minutes_is_read_again_and_counted(
        self,
    ) -> None:
        # Issue #9577: the post-merge step takes about 1m41s and the room is
        # read at about 2:01, so every pending lane merge left it unreadable.
        verified = {
            "readable": True,
            "ok": True,
            "autoMerges": [{"number": 5, "verified": True}],
        }
        fresh = policy.PostMergeGate(None, verified, lambda merge: True)
        recheck = Recheck(fresh)
        room = self.room(
            shared(report=PENDING),
            now=STALE_NOW,
            post_merge=recheck.post_merge,
        )
        self.assertEqual(
            (room.refusal, room.unreadable, room.count, room.cap, room.rung),
            (None, None, 2, 5, "C2"),
        )
        # The check ran from the floor read again, as the identity.
        self.assertEqual(recheck.asked, [(NEW_FLOOR, IDENTITY)])
        # The in-flight count judges merges by the fresh answer, from its floor.
        self.assertIs(self.seen["verified"], fresh.verified)
        self.assertEqual(self.seen["merged_since"], NEW_FLOOR)

    def test_a_recompute_that_finds_a_failure_refuses(self) -> None:
        # A verification failure after computedAt still holds the lane off.
        failed = {
            "readable": True,
            "ok": False,
            "failures": [{"signal": "red-main", "number": 5}],
        }
        recheck = Recheck(policy.PostMergeGate("failure:red-main#5", failed, None))
        room = self.room(
            shared(report=PENDING),
            now=STALE_NOW,
            post_merge=recheck.post_merge,
        )
        self.assertEqual(
            (room.refusal, room.unreadable), ("post-merge:failure:red-main#5", None)
        )
        self.assertFalse(self.seen, "no in-flight read after a refusal")

    def test_a_demotion_record_filed_since_holds_a_recomputed_room_off(
        self,
    ) -> None:
        # Past two minutes the age refuses before the demotion is re-checked,
        # so the recompute reads the demotion again.
        recheck = Recheck(policy.PostMergeGate(None, PENDING, lambda merge: False))
        room = self.room(
            shared(report=PENDING),
            now=STALE_NOW,
            post_merge=recheck.post_merge,
            fresh_demotion=policy.Demotion(True, "record-open", (8,)),
        )
        self.assertEqual(room.refusal, "rung-off:demotion")

    def test_a_failed_recompute_leaves_the_room_unreadable(self) -> None:
        unreadable = {"readable": False, "ok": False, "reason": "runs-unreadable"}
        cases = {
            "check raises": Recheck(error=RuntimeError("runs 502")),
            "check unreadable": Recheck(
                policy.PostMergeGate("runs-unreadable", unreadable, None)
            ),
        }
        for name, recheck in cases.items():
            with self.subTest(name):
                room = self.room(
                    shared(report=PENDING),
                    now=STALE_NOW,
                    post_merge=recheck.post_merge,
                )
                self.assertIsNone(room.refusal)
                self.assertTrue(
                    str(room.unreadable).startswith(
                        "post-merge answer unverified-stale"
                    ),
                    room.unreadable,
                )
        # A head that cannot be read is a failed recompute too.
        recheck = Recheck(policy.PostMergeGate(None, {"readable": True}, None))
        room = self.room(
            shared(report=PENDING),
            now=STALE_NOW,
            post_merge=recheck.post_merge,
            head_error=policy.PolicyReadError("head 502"),
        )
        self.assertIsNone(room.refusal)
        self.assertTrue(room.unreadable)
        self.assertEqual(recheck.asked, [])
        # With no check to run, it stays unreadable as before.
        room = self.room(shared(report=PENDING), now=STALE_NOW)
        self.assertEqual(room.unreadable, "post-merge answer unverified-stale")
        self.assertFalse(self.seen, "no in-flight read after an unusable answer")

    def current(self, **kwargs: object) -> tuple[policy.LaneRoom, Recheck, list]:
        """The room for a pending answer read three minutes on, with the
        default branch head, config commit and demotion all as it was read
        unless `kwargs` moves one; `runs` is what the run check answers."""
        runs = kwargs.pop("runs", True)
        asked: list[tuple[object, str]] = []

        def runs_unchanged(answer: object, branch: str) -> bool:
            asked.append((answer, branch))
            return runs(answer, branch) if callable(runs) else bool(runs)

        recheck = Recheck(
            kwargs.pop("gate", policy.PostMergeGate(None, PENDING, lambda merge: False))
        )
        room = self.room(
            kwargs.pop("answer", shared(report=PENDING)),
            now=STALE_NOW,
            post_merge=recheck.post_merge,
            runs_unchanged=runs_unchanged,
            **{"head": MAIN, **kwargs},  # type: ignore[arg-type]
        )
        return room, recheck, asked

    def test_an_answer_nothing_has_moved_since_is_kept_without_a_check(
        self,
    ) -> None:
        answer = shared(report=PENDING)
        room, recheck, asked = self.current(answer=answer)
        self.assertEqual(
            (room.refusal, room.unreadable, room.count, room.cap), (None, None, 2, 5)
        )
        self.assertEqual(recheck.asked, [], "no full post-merge check")
        self.assertEqual(asked, [(answer, "main")])
        # Counted from the kept answer: its floor and its verified merges.
        self.assertEqual(self.seen["merged_since"], FLOOR)
        self.assertIs(self.seen["verified"], answer.gate.verified)

    def test_anything_moved_since_reads_the_answer_again(self) -> None:
        cases = {
            "(a) main's head moved": dict(head=NEW_MAIN),
            # The same floor, so the gate's reuse rule does not refuse first.
            "(b) the config commit moved": dict(
                config_commit="f" * 40, fresh_floor=FLOOR
            ),
            "(c) a demotion record changed": dict(demotion_changed=True),
            "(d) a verifying run reached a conclusion": dict(runs=False),
        }
        for name, kwargs in cases.items():
            with self.subTest(name):
                room, recheck, _ = self.current(**kwargs)
                self.assertEqual(len(recheck.asked), 1, "one full post-merge check")
                self.assertEqual((room.refusal, room.unreadable), (None, None))

    def test_a_quarantine_that_expired_since_reads_the_answer_again(self) -> None:
        # (e): the answer excused a failing suite under a quarantine that
        # expired a minute after it was read, so the same red run now demotes.
        report = {
            **PENDING,
            "excusesExpireAt": (FLOOR + timedelta(minutes=1)).isoformat(),
        }
        listing = {"total_count": 0, "workflow_runs": []}
        with mock.patch.object(pm, "_read", return_value=listing):
            room, recheck, _ = self.current(
                answer=shared(report=report),
                runs=lambda answer, branch: pm.pending_runs_unchanged(
                    REPO, answer, branch, now=STALE_NOW
                ),
            )
        self.assertEqual(len(recheck.asked), 1, "one full post-merge check")
        self.assertEqual((room.refusal, room.unreadable), (None, None))

    def test_a_pending_dispatch_run_that_completed_red_refuses(self) -> None:
        # The case the two-minute rule exists for: main's head has not moved,
        # but merge #5's dispatch run finished red after the answer was read.
        listing = {
            "total_count": 1,
            "workflow_runs": [
                run(
                    "pr-require-checks.yml",
                    status="completed",
                    updated=STALE_NOW - timedelta(seconds=30),
                )
            ],
        }
        failed = {
            "readable": True,
            "ok": False,
            "failures": [{"signal": "dispatch", "number": 5}],
        }
        with mock.patch.object(pm, "_read", return_value=listing):
            room, recheck, _ = self.current(
                runs=lambda answer, branch: pm.pending_runs_unchanged(
                    REPO, answer, branch, now=STALE_NOW
                ),
                gate=policy.PostMergeGate("failure:dispatch#5", failed, None),
            )
        self.assertEqual(len(recheck.asked), 1)
        self.assertEqual(room.refusal, "post-merge:failure:dispatch#5")

    def test_an_active_demotion_is_not_re_read(self) -> None:
        # Already refusing: a changed record cannot make it allow.
        room = self.room(shared(demoted=True), demotion_changed=True)
        self.assertEqual(room.refusal, "rung-off:demotion")

    def test_a_failed_read_refuses_nothing_and_allows_nothing(self) -> None:
        cases = {
            "no answer": dict(answer=None),
            "queue": dict(flight=policy.InFlight(False, "merge-queue-unreadable")),
            "enqueuer": dict(
                flight=policy.InFlight(
                    False, "entry-enqueuer-unknown:#3", frozenset({3})
                )
            ),
            "config": dict(config_error=policy.PolicyReadError("contents 502")),
            "identity": dict(answer=shared(identity="someone-else[bot]")),
        }
        for name, kwargs in cases.items():
            with self.subTest(name):
                answer = kwargs.pop("answer", shared())
                if name == "no answer":
                    with mock.patch.object(policy, "in_flight") as flight:
                        room = policy.lane_room(REPO, None, lane_rung_cap="")
                    flight.assert_not_called()
                else:
                    room = self.room(answer, **kwargs)  # type: ignore[arg-type]
                self.assertIsNone(room.refusal)
                self.assertTrue(room.unreadable)


class PendingRunsUnchanged(unittest.TestCase):
    """(d): the verifying runs of the answer's unverified merges, from one
    listing. Expected from the check's own rule (`_judge`): a full or canary
    run that reaches a conclusion changes the verdict, one still running
    leaves it pending, and past `DISPATCH_DEADLINE` a merge with no dispatch
    run fails."""

    def unchanged(
        self,
        rows: list[dict[str, object]],
        *,
        total: int | None = None,
        now=STALE_NOW,
        report: dict[str, object] = PENDING,
    ) -> tuple[bool, list[list[str]]]:
        calls: list[list[str]] = []

        def read(args: list[str], label: str) -> dict[str, object]:
            calls.append(args)
            return {
                "total_count": len(rows) if total is None else total,
                "workflow_runs": rows,
            }

        with mock.patch.object(pm, "_read", side_effect=read):
            answer = pm.pending_runs_unchanged(
                REPO, shared(report=report), "main", now=now
            )
        return answer, calls

    def test_runs_still_running_or_finished_before_the_answer_hold(self) -> None:
        rows = [
            run("pr-require-checks.yml", status="in_progress", updated=STALE_NOW),
            run(
                "post-merge-detect-silent-revert.yml",
                status="queued",
                updated=STALE_NOW,
            ),
            # Finished before the answer was read (less the clock margin).
            run(
                "post-merge-detect-silent-revert.yml",
                status="completed",
                updated=FLOOR - policy.SINCE_CLOCK_MARGIN - timedelta(seconds=1),
            ),
            # Another workflow's run judges nothing.
            run("ci-status.yml", status="completed", updated=STALE_NOW),
        ]
        answer, calls = self.unchanged(rows)
        self.assertTrue(answer)
        # One listing call, of runs on main created since merge #5.
        self.assertEqual(len(calls), 1)
        self.assertIn("branch=main", calls[0][1])
        self.assertIn("created=%3E%3D2026-10-01T00%3A00%3A00Z", calls[0][1])

    def test_a_conclusion_since_a_partial_listing_or_the_deadline_moves_it(
        self,
    ) -> None:
        done = run("pr-require-checks.yml", status="completed", updated=STALE_NOW)
        canary = run(
            "post-merge-detect-silent-revert.yml", status="completed", updated=FLOOR
        )
        self.assertFalse(self.unchanged([done])[0])
        self.assertFalse(self.unchanged([canary])[0])
        self.assertFalse(self.unchanged([], total=101)[0])
        # A quarantine excuse that ended since, and an answer that does not
        # say when its excuses end.
        self.assertFalse(
            self.unchanged(
                [], report={**PENDING, "excusesExpireAt": FLOOR.isoformat()}
            )[0]
        )
        self.assertFalse(
            self.unchanged(
                [], report={k: v for k, v in PENDING.items() if k != "excusesExpireAt"}
            )[0]
        )
        later = (STALE_NOW + timedelta(days=1)).isoformat()
        self.assertTrue(
            self.unchanged([], report={**PENDING, "excusesExpireAt": later})[0]
        )
        self.assertFalse(
            self.unchanged([], now=FLOOR + pm.DISPATCH_DEADLINE + timedelta(seconds=1))[
                0
            ]
        )


class LaneRoomCommand(unittest.TestCase):
    def test_it_prints_the_room_from_the_post_merge_report(self) -> None:
        seen: list[object] = []

        hooks: dict[str, object] = {}

        def room(
            repo: str,
            answer: object,
            *,
            lane_rung_cap: str | None,
            post_merge: object,
            runs_unchanged: object,
        ) -> policy.LaneRoom:
            seen.append((repo, answer, lane_rung_cap))
            hooks.update(post_merge=post_merge, runs_unchanged=runs_unchanged)
            return policy.LaneRoom(count=1, cap=5, queued=frozenset({3}), rung="C2")

        out = io.StringIO()
        with (
            mock.patch.object(
                ve.postmerge, "read_shared", return_value="answer"
            ) as read,
            mock.patch.object(policy, "lane_room", side_effect=room),
            contextlib.redirect_stdout(out),
        ):
            code = ve.main(
                [
                    "lane-room",
                    "--repo",
                    REPO,
                    "--postmerge-result",
                    "/tmp/x.json",
                    "--rung-cap",
                    "",
                ]
            )
        self.assertEqual(code, 0)
        read.assert_called_once_with("/tmp/x.json")
        self.assertEqual(seen, [(REPO, "answer", "")])
        self.assertEqual(
            json.loads(out.getvalue()),
            {
                "refusal": None,
                "unreadable": None,
                "count": 1,
                "cap": 5,
                "queued": [3],
                "rung": "C2",
            },
        )
        self.assertTrue(callable(hooks["post_merge"]))
        self.assertTrue(callable(hooks["runs_unchanged"]))

    def test_a_missing_report_is_unreadable(self) -> None:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            ve.main(
                [
                    "lane-room",
                    "--repo",
                    REPO,
                    "--postmerge-result",
                    "/nonexistent/post-merge.json",
                    "--rung-cap",
                    "",
                ]
            )
        report = json.loads(out.getvalue())
        self.assertIsNone(report["refusal"])
        self.assertTrue(report["unreadable"])


if __name__ == "__main__":
    unittest.main()

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
import shutil
import subprocess
import sys
import tempfile
import unittest
from dataclasses import replace
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
# past the two minutes the gate reuses it.
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
        code_unchanged: bool = True,
    ) -> policy.LaneRoom:
        seen: dict[str, object] = {}
        reads = mock.Mock(
            return_value=fresh_demotion or policy.Demotion(False, None, ())
        )

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
            mock.patch.object(policy, "read_demotion", reads),
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
                code_unchanged=code_unchanged,
                **kwargs,  # type: ignore[arg-type]
            )
        self.seen, self.reads = seen, reads
        return result

    def test_an_answer_from_other_check_code_is_read_again_never_kept(self) -> None:
        # The report was computed by check code main has since changed: the
        # room reads it afresh, even where it would reuse or keep it.
        for name, kwargs in {
            "reusable": {},
            "demotion reads the same": self.DEMOTION_CHANGED,
        }.items():
            with self.subTest(name):
                recheck = Recheck(policy.PostMergeGate(None, {"readable": True}, None))
                room = self.room(
                    shared(),
                    post_merge=recheck.post_merge,
                    code_unchanged=False,
                    **kwargs,  # type: ignore[arg-type]
                )
                self.assertEqual((room.refusal, room.unreadable), (None, None))
                self.assertEqual(recheck.asked, [(NEW_FLOOR, IDENTITY)])
        # With no check to read it again: unreadable.
        room = self.room(shared(), code_unchanged=False)
        self.assertEqual(room.unreadable, "post-merge answer code-changed")

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

    # Reuse refusals the room reads afresh (shared_refusal): past
    # SHARED_MAX_AGE (a re-run job reads the run's first report) and from the
    # future.
    UNUSABLE = {
        "stale": dict(now=FLOOR + policy.SHARED_MAX_AGE + timedelta(seconds=1)),
        "future": dict(now=FLOOR - timedelta(seconds=1)),
    }
    # A demotion record filed or changed since, inside the two minutes the
    # gate reuses a pending answer for.
    DEMOTION_CHANGED = dict(demotion_changed=True, now=FLOOR + timedelta(minutes=1))

    def test_an_answer_the_gate_would_not_reuse_is_read_again(self) -> None:
        # The gate reads afresh on any refusal (assess); so does the room,
        # and a readable answer counts from its own floor. Run 40255059710
        # left 12 lane pull requests unarmed on `demotion-changed`.
        for name, kwargs in self.UNUSABLE.items():
            with self.subTest(name):
                fresh = policy.PostMergeGate(None, {"readable": True}, lambda m: True)
                recheck = Recheck(fresh)
                room = self.room(
                    shared(report=PENDING),
                    post_merge=recheck.post_merge,
                    **kwargs,  # type: ignore[arg-type]
                )
                self.assertEqual(
                    (room.refusal, room.unreadable, room.count, room.cap),
                    (None, None, 2, 5),
                )
                self.assertEqual(recheck.asked, [(NEW_FLOOR, IDENTITY)])
                self.assertIs(self.seen["verified"], fresh.verified)
                self.assertEqual(self.seen["merged_since"], NEW_FLOOR)

    def test_an_unusable_answer_is_never_kept_on_the_cheap_path(self) -> None:
        # Only an unverified-stale answer may be kept unchanged; a stale one
        # is read again even when nothing it was read from moved.
        recheck = Recheck(policy.PostMergeGate(None, {"readable": True}, None))
        runs = mock.Mock(return_value=True)
        self.room(
            shared(report=PENDING),
            post_merge=recheck.post_merge,
            runs_unchanged=runs,
            head=MAIN,
            **self.UNUSABLE["stale"],  # type: ignore[arg-type]
        )
        self.assertEqual(len(recheck.asked), 1)
        runs.assert_not_called()

    def test_a_no_op_demotion_edit_keeps_the_answer(self) -> None:
        # Triage editing an issue the lane opened refuses the answer as
        # `demotion-changed`; a demotion read alone that finds it unchanged
        # keeps it, so the room does not pay the full post-merge check.
        recheck = Recheck(policy.PostMergeGate(None, {"readable": True}, None))
        answer = shared()
        room = self.room(
            answer,
            post_merge=recheck.post_merge,
            **self.DEMOTION_CHANGED,  # type: ignore[arg-type]
        )
        self.assertEqual(
            (room.refusal, room.unreadable, room.count, room.cap), (None, None, 2, 5)
        )
        self.assertEqual(recheck.asked, [], "no full post-merge check")
        self.reads.assert_called_once()
        self.assertEqual(self.reads.call_args.kwargs["self_logins"], frozenset())
        # Counted from the kept answer: its floor and its verified merges.
        self.assertEqual(self.seen["merged_since"], FLOOR)
        self.assertIs(self.seen["verified"], answer.gate.verified)

    def test_a_demotion_that_moved_reads_the_answer_again(self) -> None:
        # Active, the rung is off; inactive with other records or another
        # clear, the floor may differ. Either way the full read runs.
        cases = {
            "active": (
                policy.Demotion(True, "record-open", (8,)),
                "rung-off:demotion",
            ),
            "another record": (policy.Demotion(False, None, (9,)), None),
            # The same records with another clear or newest record: the
            # keep binds every field, not the record numbers alone.
            "another clear": (
                policy.Demotion(False, None, (), cleared_at=NEW_FLOOR),
                None,
            ),
            "another newest record": (
                policy.Demotion(False, None, (), newest_created=NEW_FLOOR),
                None,
            ),
        }
        for name, (demotion, refusal) in cases.items():
            with self.subTest(name):
                recheck = Recheck(policy.PostMergeGate(None, {"readable": True}, None))
                room = self.room(
                    post_merge=recheck.post_merge,
                    fresh_demotion=demotion,
                    **self.DEMOTION_CHANGED,  # type: ignore[arg-type]
                )
                self.assertEqual((room.refusal, room.unreadable), (refusal, None))
                self.assertEqual(recheck.asked, [(NEW_FLOOR, IDENTITY)])

    def test_an_answer_bound_to_other_self_logins_is_read_with_none(self) -> None:
        # The room binds no self logins, so a fresh read uses none and the
        # in-flight count excludes none: not the answer's own.
        answer = replace(shared(), self_logins=frozenset({"lane-self[bot]"}))
        recheck = Recheck(policy.PostMergeGate(None, {"readable": True}, None))
        room = self.room(answer, post_merge=recheck.post_merge)
        self.assertEqual((room.refusal, room.unreadable), (None, None))
        self.assertEqual(recheck.asked, [(NEW_FLOOR, IDENTITY)])
        self.assertEqual(self.reads.call_args.kwargs["self_logins"], frozenset())
        self.assertEqual(self.seen["self_logins"], frozenset())

    def test_an_unusable_answer_with_no_fresh_read_is_unreadable(self) -> None:
        cases = {
            "no check": (None, self.UNUSABLE["stale"], "stale"),
            "no check, demotion changed": (
                None,
                self.DEMOTION_CHANGED,
                "demotion-changed",
            ),
            "check raises": (
                Recheck(error=RuntimeError("runs 502")).post_merge,
                self.UNUSABLE["stale"],
                "stale",
            ),
            "check unreadable": (
                Recheck(
                    policy.PostMergeGate("runs-unreadable", {"readable": False}, None)
                ).post_merge,
                self.UNUSABLE["stale"],
                "stale",
            ),
        }
        for name, (post_merge, kwargs, reason) in cases.items():
            with self.subTest(name):
                room = self.room(
                    post_merge=post_merge,
                    **kwargs,  # type: ignore[arg-type]
                )
                self.assertIsNone(room.refusal)
                self.assertTrue(
                    str(room.unreadable).startswith(f"post-merge answer {reason}"),
                    room.unreadable,
                )
                self.assertFalse(self.seen, "no in-flight read")

    def test_a_lane_merge_the_answer_does_not_count_is_read_again(self) -> None:
        # The gate's reuse rule (shared_refusal) reads afresh when a lane
        # merge landed after the report was computed (`new-merge:#<n>`), so
        # its failed full run is not missed; the room reads it again too.
        seen: list[dict[str, object]] = []

        def refusal(repo: str, answer: object, **kwargs: object) -> str:
            seen.append(kwargs)
            return "new-merge:#7"

        recheck = Recheck(policy.PostMergeGate(None, {"readable": True}, None))
        with mock.patch.object(policy, "shared_refusal", side_effect=refusal):
            room = self.room(post_merge=recheck.post_merge)
        self.assertEqual((room.refusal, room.unreadable), (None, None))
        self.assertEqual(recheck.asked, [(NEW_FLOOR, IDENTITY)])
        with mock.patch.object(policy, "shared_refusal", side_effect=refusal):
            room = self.room()
        self.assertEqual(
            (room.refusal, room.unreadable),
            (None, "post-merge answer new-merge:#7"),
        )
        self.assertFalse(self.seen, "no in-flight read after an unusable answer")
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
        # The post-merge step takes nearly the two minutes the gate reuses an
        # answer for, so a pending lane merge must not leave the room unreadable.
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
                        room = policy.lane_room(
                            REPO, None, lane_rung_cap="", code_unchanged=True
                        )
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

    def test_the_clock_margin_is_sixty_seconds_of_skew(self) -> None:
        # computedAt is stamped before the runs are read, so the margin covers
        # only clock skew: 60 s.
        def finished(before: timedelta) -> dict[str, object]:
            return run(
                "pr-require-checks.yml", status="completed", updated=FLOOR - before
            )

        self.assertFalse(self.unchanged([finished(timedelta(seconds=59))])[0])
        self.assertTrue(self.unchanged([finished(timedelta(seconds=61))])[0])

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


class SettleShared(unittest.TestCase):
    """`settle_shared`: the one reuse rule the room and the merge job's
    `settle` read a run's post-merge answer by. The expected reasons are
    `shared_refusal`'s, in the room's `post-merge answer <reason>` form; the
    two keeps are the room's (an unverified-stale answer nothing moved since,
    a demotion-changed one whose demotion reads the same)."""

    VERIFIED = {
        "readable": True,
        "ok": True,
        "autoMerges": [{"number": 5, "verified": True}],
    }

    def settle(
        self,
        answer: policy.SharedPostMerge,
        *,
        now: datetime = NOW,
        head: str = MAIN,
        lane_merges: tuple[int, ...] = (),
        demotion_changed: bool = False,
        fresh_demotion: policy.Demotion | None = None,
        runs: bool | None = None,
        keep: bool = True,
        code_unchanged: bool = True,
    ) -> tuple[policy.SharedPostMerge | None, str | None]:
        merges = [{"number": n} for n in lane_merges]

        def derive(pr: dict[str, object], *args: object, **kwargs: object) -> object:
            return policy.AutoMerge(int(pr["number"]), "a" * 40, "b" * 40, None)  # type: ignore[call-overload]

        self.reads = mock.Mock(
            return_value=fresh_demotion or policy.Demotion(False, None, ())
        )
        self.runs = mock.Mock(return_value=runs)
        with (
            mock.patch.object(policy, "newest_config_commit", return_value=MAIN),
            mock.patch.object(policy, "_get", return_value=(200, {"sha": head})),
            mock.patch.object(
                policy, "_default_branch_head", return_value=("main", head)
            ),
            mock.patch.object(policy, "_merged_since", return_value=merges),
            mock.patch.object(policy, "derive_auto_merge", side_effect=derive),
            mock.patch.object(
                policy, "_demotion_changed", return_value=demotion_changed
            ),
            mock.patch.object(policy, "permission_reader"),
            mock.patch.object(policy, "read_demotion", self.reads),
        ):
            return policy.settle_shared(
                REPO,
                answer,
                default="main",
                base_sha=MAIN,
                identity=IDENTITY,
                now=now,
                runs_unchanged=None if runs is None else self.runs,
                keep=keep,
                code_unchanged=code_unchanged,
            )

    def test_a_fresh_answer_at_an_unmoved_head_is_reused(self) -> None:
        answer = shared(report=self.VERIFIED)
        self.assertEqual(self.settle(answer), (answer, None))

    def test_a_moved_head_with_no_new_lane_merge_is_reused(self) -> None:
        # Run 40382489448: a merge landed before the merge job started, none
        # of them the lane's, and the job's own check found the same merges.
        answer = shared(report=self.VERIFIED)
        self.assertEqual(self.settle(answer, head=NEW_MAIN), (answer, None))

    def test_a_moved_head_with_a_lane_merge_the_answer_does_not_count_is_refused(
        self,
    ) -> None:
        answer = shared(report=self.VERIFIED)
        self.assertEqual(
            self.settle(answer, head=NEW_MAIN, lane_merges=(5, 9)),
            (None, "post-merge answer new-merge:#9"),
        )

    def test_an_unverified_answer_past_two_minutes_is_refused_unless_nothing_moved(
        self,
    ) -> None:
        answer = shared(report=PENDING)
        # No run check: refused, as the room refuses with no recompute.
        self.assertEqual(
            self.settle(answer, now=STALE_NOW),
            (None, "post-merge answer unverified-stale"),
        )
        # A verifying run reached a conclusion since: refused.
        self.assertEqual(
            self.settle(answer, now=STALE_NOW, runs=False),
            (None, "post-merge answer unverified-stale"),
        )
        self.runs.assert_called_once_with(answer, "main")
        # Main moved (with no new lane merge): refused.
        self.assertEqual(
            self.settle(answer, now=STALE_NOW, runs=True, head=NEW_MAIN),
            (None, "post-merge answer unverified-stale"),
        )
        # Nothing it was read from moved: kept.
        self.assertEqual(self.settle(answer, now=STALE_NOW, runs=True), (answer, None))
        # Inside two minutes it needs no keep.
        self.assertEqual(
            self.settle(answer, now=FLOOR + timedelta(minutes=1)), (answer, None)
        )

    def test_a_changed_demotion_is_refused_unless_it_reads_the_same(self) -> None:
        answer = shared(report=self.VERIFIED)
        moved = policy.Demotion(False, None, (9,))
        self.assertEqual(
            self.settle(answer, demotion_changed=True, fresh_demotion=moved),
            (None, "post-merge answer demotion-changed"),
        )
        self.assertEqual(self.settle(answer, demotion_changed=True), (answer, None))
        self.assertEqual(self.reads.call_args.kwargs["self_logins"], frozenset())
        # Without the keeps (the room with no check to read again), refused
        # with no demotion read.
        self.assertEqual(
            self.settle(answer, demotion_changed=True, keep=False),
            (None, "post-merge answer demotion-changed"),
        )
        self.reads.assert_not_called()

    def test_an_answer_from_other_check_code_is_refused_before_any_keep(
        self,
    ) -> None:
        # The brief's rule: a report computed by check code main has since
        # changed never stands, even where it would be reused or kept.
        answer = shared(report=self.VERIFIED)
        self.assertEqual(
            self.settle(answer, code_unchanged=False),
            (None, "post-merge answer code-changed"),
        )
        self.assertEqual(
            self.settle(answer, demotion_changed=True, code_unchanged=False),
            (None, "post-merge answer code-changed"),
        )
        self.reads.assert_not_called()
        pending = shared(report=PENDING)
        self.assertEqual(
            self.settle(pending, now=STALE_NOW, runs=True, code_unchanged=False),
            (None, "post-merge answer code-changed"),
        )
        self.runs.assert_not_called()

    def test_a_stale_answer_is_refused_even_when_nothing_moved(self) -> None:
        answer = shared(report=PENDING)
        late = FLOOR + policy.SHARED_MAX_AGE + timedelta(seconds=1)
        self.assertEqual(
            self.settle(answer, now=late, runs=True),
            (None, "post-merge answer stale"),
        )
        self.runs.assert_not_called()


class CheckCodeUnchanged(unittest.TestCase):
    """`check_code_unchanged`: whether the check's code (the babysit-prs
    scripts and docs/conventions/pr-pipeline.yaml) at HEAD is the code at the
    kept commit. Expected outcomes are the brief's: the same commit or a
    change elsewhere only allows reuse; a change in either path, a missing,
    malformed or unknown commit, or a git failure refuses."""

    def setUp(self) -> None:
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="check-code-"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.git("init", "-q")
        self.commits: dict[str, str] = {}
        for name, path in (
            ("base", "README.md"),
            ("elsewhere", "README.md"),
            ("scripts", "plugins/source-control/skills/babysit-prs/scripts/a.py"),
            ("config", "docs/conventions/pr-pipeline.yaml"),
        ):
            file = self.root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(f"{name}\n")
            self.git("add", "-A")
            self.git("commit", "-q", "-m", name)
            self.commits[name] = self.git("rev-parse", "HEAD").strip()

    def git(self, *args: str) -> str:
        return subprocess.run(
            ["git", "-C", str(self.root), "-c", "user.name=t", "-c", "user.email=t@t"]
            + list(args),
            check=True,
            capture_output=True,
            text=True,
        ).stdout

    def unchanged(self, kept: str, head: str) -> bool:
        self.git("checkout", "-q", "--detach", self.commits[head])
        return policy.check_code_unchanged(kept, root=self.root)

    def test_the_same_commit_or_a_change_elsewhere_allows_reuse(self) -> None:
        self.assertTrue(self.unchanged(self.commits["config"], "config"))
        self.assertTrue(self.unchanged(self.commits["base"], "elsewhere"))

    def test_a_change_to_the_scripts_or_the_pipeline_config_refuses(self) -> None:
        self.assertFalse(self.unchanged(self.commits["elsewhere"], "scripts"))
        self.assertFalse(self.unchanged(self.commits["scripts"], "config"))

    def test_a_missing_malformed_or_unknown_commit_refuses(self) -> None:
        for kept in ("", "HEAD", "--output=x", "c" * 39, "f" * 40):
            with self.subTest(kept):
                self.assertFalse(self.unchanged(kept, "config"))

    def test_a_git_failure_refuses(self) -> None:
        kept = self.commits["config"]
        self.git("checkout", "-q", "--detach", kept)
        self.assertFalse(
            policy.check_code_unchanged(kept, root=self.root / "no-such-dir")
        )
        with mock.patch.object(
            policy.subprocess, "run", side_effect=subprocess.TimeoutExpired("git", 1)
        ):
            self.assertFalse(policy.check_code_unchanged(kept, root=self.root))


class SettleCommand(unittest.TestCase):
    def main(
        self,
        settled: tuple[object, str | None],
        *,
        code_unchanged: bool = True,
        cfg: policy.PipelineConfig | None = None,
        config_error: Exception | None = None,
        code_sha: str = MAIN,
    ) -> tuple[int, dict, dict]:
        seen: dict[str, object] = {}

        def settle(repo: str, answer: object, **kwargs: object) -> object:
            seen.update(kwargs, repo=repo, answer=answer)
            return settled

        out = io.StringIO()
        with (
            mock.patch.object(ve.postmerge, "read_shared", return_value="answer"),
            mock.patch.object(
                policy, "check_code_unchanged", return_value=code_unchanged
            ) as code,
            mock.patch.object(policy, "_default_branch", return_value="main"),
            mock.patch.object(
                policy,
                "_default_branch_config",
                side_effect=config_error,
                return_value=cfg or config(base_sha=NEW_MAIN),
            ) as read_config,
            mock.patch.object(policy, "settle_shared", side_effect=settle),
            contextlib.redirect_stdout(out),
        ):
            exit_code = ve.main(
                [
                    "settle",
                    "--repo",
                    REPO,
                    "--postmerge-result",
                    "/tmp/x.json",
                    "--code-sha",
                    code_sha,
                ]
            )
        self.code, self.read_config = code, read_config
        return exit_code, json.loads(out.getvalue()), seen

    def test_it_exits_0_when_the_answer_stands_and_1_when_refused(self) -> None:
        code, out, seen = self.main(("answer", None))
        self.assertEqual((code, out), (0, {"reuse": True, "reason": None}))
        self.code.assert_called_once_with(MAIN)
        # Bound as the room binds: the default branch head and its config's
        # agent identity, never a recompute.
        self.assertEqual(
            {k: seen[k] for k in ("repo", "answer", "default", "base_sha", "identity")},
            {
                "repo": REPO,
                "answer": "answer",
                "default": "main",
                "base_sha": NEW_MAIN,
                "identity": IDENTITY,
            },
        )
        self.assertIs(seen["code_unchanged"], True)
        self.assertNotIn("post_merge", seen)
        self.assertIs(seen.get("keep", True), True)
        self.assertTrue(callable(seen["runs_unchanged"]))
        code, out, _ = self.main((None, "post-merge answer unverified-stale"))
        self.assertEqual(
            (code, out),
            (1, {"reuse": False, "reason": "post-merge answer unverified-stale"}),
        )

    def test_changed_check_code_is_refused_before_any_read(self) -> None:
        code, out, seen = self.main(("answer", None), code_unchanged=False, code_sha="")
        self.assertEqual(
            (code, out),
            (1, {"reuse": False, "reason": "post-merge answer code-changed"}),
        )
        self.code.assert_called_once_with("")
        self.read_config.assert_not_called()
        self.assertEqual(seen, {})

    def test_no_agent_identity_is_refused(self) -> None:
        code, out, seen = self.main(("answer", None), cfg=config(agent_identity=""))
        self.assertEqual(code, 1)
        self.assertFalse(out["reuse"])
        self.assertEqual(seen, {})

    def test_a_missing_report_or_unreadable_config_is_refused(self) -> None:
        out = io.StringIO()
        with (
            mock.patch.object(policy, "check_code_unchanged", return_value=True),
            contextlib.redirect_stdout(out),
        ):
            code = ve.main(
                [
                    "settle",
                    "--repo",
                    REPO,
                    "--postmerge-result",
                    "/nonexistent/post-merge.json",
                    "--code-sha",
                    MAIN,
                ]
            )
        self.assertEqual(code, 1)
        self.assertFalse(json.loads(out.getvalue())["reuse"])
        code, out, _ = self.main(
            ("answer", None), config_error=policy.PolicyReadError("head 502")
        )
        self.assertEqual(code, 1)
        self.assertIn("head 502", out["reason"])


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
            code_unchanged: bool,
        ) -> policy.LaneRoom:
            seen.append((repo, answer, lane_rung_cap))
            hooks.update(
                post_merge=post_merge,
                runs_unchanged=runs_unchanged,
                code_unchanged=code_unchanged,
            )
            return policy.LaneRoom(count=1, cap=5, queued=frozenset({3}), rung="C2")

        out = io.StringIO()
        with (
            mock.patch.object(
                ve.postmerge, "read_shared", return_value="answer"
            ) as read,
            mock.patch.object(policy, "lane_room", side_effect=room),
            mock.patch.object(
                policy, "check_code_unchanged", return_value=False
            ) as checked,
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
                    "--code-sha",
                    MAIN,
                ]
            )
        self.assertEqual(code, 0)
        read.assert_called_once_with("/tmp/x.json")
        # The kept report's check code, compared with this checkout's.
        checked.assert_called_once_with(MAIN)
        self.assertIs(hooks["code_unchanged"], False)
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
                    "--code-sha",
                    "",
                ]
            )
        report = json.loads(out.getvalue())
        self.assertIsNone(report["refusal"])
        self.assertTrue(report["unreadable"])


if __name__ == "__main__":
    unittest.main()

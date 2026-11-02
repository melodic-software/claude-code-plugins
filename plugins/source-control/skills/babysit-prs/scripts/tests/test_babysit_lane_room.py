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
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from unittest import mock
from urllib.parse import unquote

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy  # noqa: E402
import babysit_postmerge as pm  # noqa: E402
import babysit_verify_evidence as ve  # noqa: E402

# CheckCodeUnchanged builds git fixtures: clear any ambient git environment
# first (scripts/check-fixture-git-isolation.sh).
for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)
del _leaked_git_var

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
    "outstandingSince": None,
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
            mock.patch.object(
                policy, "_get", return_value=(200, {"object": {"sha": MAIN}})
            ),
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
            "(c) a demotion record was filed": dict(
                demotion_changed=True,
                fresh_demotion=policy.Demotion(False, None, (9,)),
            ),
            "(d) a verifying run reached a conclusion": dict(runs=False),
        }
        for name, kwargs in cases.items():
            with self.subTest(name):
                room, recheck, _ = self.current(**kwargs)
                self.assertEqual(len(recheck.asked), 1, "one full post-merge check")
                self.assertEqual((room.refusal, room.unreadable), (None, None))

    def test_an_unverified_answer_whose_demotion_reads_the_same_is_kept(
        self,
    ) -> None:
        # The demotion probe trips on any edit to an issue the lane opened;
        # the room already keeps a demotion-changed answer when the demotion
        # reads the same, and an unverified-stale one is no different.
        room, recheck, _ = self.current(demotion_changed=True)
        self.assertEqual(recheck.asked, [], "no full post-merge check")
        self.assertEqual((room.refusal, room.unreadable), (None, None))
        self.assertEqual(self.reads.call_args.kwargs["self_logins"], frozenset())

    def test_the_report_names_how_the_post_merge_answer_was_settled(self) -> None:
        # The brief: whether the answer was reused or recomputed and, when
        # recomputed, the refusal; for an unverified-stale answer not kept,
        # which of what it was read from moved.
        def settled(room: policy.LaneRoom) -> object:
            return room.report()["postMerge"]

        def unreadable(answer: object, branch: str) -> bool:
            raise policy.PolicyReadError("runs 502")

        self.assertEqual(
            settled(self.room()), {"answer": "reused", "reason": None, "moved": None}
        )
        self.assertEqual(
            settled(self.current()[0]),
            {"answer": "kept", "reason": "unverified-stale", "moved": None},
        )
        recheck = Recheck(policy.PostMergeGate(None, {"readable": True}, None))
        self.assertEqual(
            settled(
                self.room(
                    post_merge=recheck.post_merge,
                    **self.DEMOTION_CHANGED,  # type: ignore[arg-type]
                )
            ),
            {"answer": "kept", "reason": "demotion-changed", "moved": None},
        )
        for moved, kwargs in {
            "head-moved": dict(head=NEW_MAIN),
            "config-moved": dict(config_commit="f" * 40, fresh_floor=FLOOR),
            "runs-moved": dict(runs=False),
            "unreadable": dict(runs=unreadable),
            "demotion-changed": dict(
                demotion_changed=True,
                fresh_demotion=policy.Demotion(False, None, (9,)),
            ),
        }.items():
            with self.subTest(moved):
                self.assertEqual(
                    settled(self.current(**kwargs)[0]),
                    {
                        "answer": "recomputed",
                        "reason": "unverified-stale",
                        "moved": moved,
                    },
                )
        recheck = Recheck(policy.PostMergeGate(None, {"readable": True}, None))
        self.assertEqual(
            settled(
                self.room(shared(), post_merge=recheck.post_merge, code_unchanged=False)
            ),
            {"answer": "recomputed", "reason": "code-changed", "moved": None},
        )
        # With no check to read it again, the room refuses it.
        self.assertEqual(
            settled(self.room(shared(report=PENDING), now=STALE_NOW)),
            {"answer": "refused", "reason": "unverified-stale", "moved": None},
        )
        # A read that fails before the answer is settled names nothing.
        failed = self.room(config_error=policy.PolicyReadError("contents 502"))
        self.assertIsNone(settled(failed))

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
        # One listing per verifying workflow, of runs on main created since
        # merge #5: every workflow's runs on main filled 152 in under two
        # hours on 2026-10-27, past one page.
        self.assertEqual(
            [c[1].split("/runs?")[0].rsplit("/", 1)[1] for c in calls],
            ["pr-require-checks.yml", "post-merge-detect-silent-revert.yml"],
        )
        for call in calls:
            self.assertIn("branch=main", call[1])
            self.assertIn("created=%3E%3D2026-10-01T00%3A00%3A00Z", call[1])

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

    def test_a_canary_still_queued_in_a_verified_window_is_listed(self) -> None:
        # A verified merge's canary queued before the unverified merge can
        # still turn red and fail it, so the listing reaches back to it; an
        # answer that does not say whether one is outstanding is False.
        queued = FLOOR - timedelta(hours=1)
        answer, calls = self.unchanged(
            [], report={**PENDING, "outstandingSince": queued.isoformat()}
        )
        self.assertTrue(answer)
        for call in calls:
            self.assertIn("created=%3E%3D2026-09-30T23%3A00%3A00Z", call[1])
        unsaid = {k: v for k, v in PENDING.items() if k != "outstandingSince"}
        self.assertEqual(self.unchanged([], report=unsaid), (False, []))


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
        demotion_error: Exception | None = None,
    ) -> tuple[policy.SharedPostMerge | None, str | None]:
        merges = [{"number": n} for n in lane_merges]

        def derive(pr: dict[str, object], *args: object, **kwargs: object) -> object:
            return policy.AutoMerge(int(pr["number"]), "a" * 40, "b" * 40, None)  # type: ignore[call-overload]

        self.reads = mock.Mock(
            return_value=fresh_demotion or policy.Demotion(False, None, ()),
            side_effect=demotion_error,
        )
        self.runs = mock.Mock(return_value=runs)
        with (
            mock.patch.object(policy, "newest_config_commit", return_value=MAIN),
            mock.patch.object(
                policy, "_get", return_value=(200, {"object": {"sha": head}})
            ),
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

    def test_an_unverified_stale_answer_keeps_through_a_demotion_that_reads_the_same(
        self,
    ) -> None:
        answer = shared(report=PENDING)
        stale = dict(now=STALE_NOW, runs=True, demotion_changed=True)
        # The probe tripped but the demotion reads the same: kept.
        self.assertEqual(self.settle(answer, **stale), (answer, None))  # type: ignore[arg-type]
        # A record filed since, or a demotion read that fails: refused.
        moved = policy.Demotion(False, None, (9,))
        for name, kwargs in {
            "moved": dict(fresh_demotion=moved),
            "unreadable": dict(demotion_error=policy.PolicyReadError("issues 502")),
        }.items():
            with self.subTest(name):
                self.assertEqual(
                    self.settle(answer, **stale, **kwargs),  # type: ignore[arg-type]
                    (None, "post-merge answer unverified-stale"),
                )
        # A verifying run that reached a conclusion refuses before the
        # demotion is read again.
        self.assertEqual(
            self.settle(answer, now=STALE_NOW, runs=False, demotion_changed=True),
            (None, "post-merge answer unverified-stale"),
        )
        self.reads.assert_not_called()

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

    def test_an_answer_past_its_quarantine_excuse_is_refused(self) -> None:
        # `_judge` reads the same red run as a demotion once the quarantine
        # that excused it expires, with nothing else moving.
        def excused(until: object) -> policy.SharedPostMerge:
            return shared(report={**self.VERIFIED, "excusesExpireAt": until})

        for until in ((NOW - timedelta(seconds=1)).isoformat(), "not a time"):
            with self.subTest(until):
                self.assertEqual(
                    self.settle(excused(until)),
                    (None, "post-merge answer excuse-expired"),
                )
        answer = excused((NOW + timedelta(seconds=1)).isoformat())
        self.assertEqual(self.settle(answer), (answer, None))


SHA_PINNED = "b" * 40
# A passing answer an earlier tick kept: one verified lane merge whose pin the
# check read, nothing to start and no quarantine excuse.
SETTLED = {
    "readable": True,
    "ok": True,
    "hold": None,
    "needsDispatch": False,
    "autoMerges": [{"number": 5, "verified": True, "mergedAt": "2026-09-30T20:00:00Z"}],
    "failures": [],
    "reruns": [],
    "unattributed": [],
    "quarantines": [],
    "warnings": [],
    "excusesExpireAt": None,
    "pins": {"5": SHA_PINNED},
    "outstandingSince": None,
}
CONFIRM_WAIT = 40


class IdleRefusal(unittest.TestCase):
    """`idle_refusal`: the rest of what the post-merge check reads that can
    change its verdict with no new lane merge, for post-merge-dispatch's
    reuse of an earlier tick's report. Expected from the check's own rules:
    `_judge` and `_lane_reruns` read verifying runs, quarantine issues
    (`expired`, `demoting`) and pins (`read_pin`), and a pending merge fails
    past `DISPATCH_DEADLINE`."""

    def refusal(
        self,
        report: dict[str, object] = SETTLED,
        *,
        now: datetime = NOW,
        runs: list[dict[str, object]] = (),  # type: ignore[assignment]
        runs_total: int | None = None,
        issues: list[dict[str, object]] = (),  # type: ignore[assignment]
        pins: dict[int, str | None] | Exception | None = None,
    ) -> str | None:
        self.calls: list[str] = []

        def read(args: list[str], label: str) -> object:
            self.calls.append(args[1])
            if "/actions/workflows/" in args[1]:
                # The listing answers only runs created at or after its floor.
                floor = datetime.fromisoformat(
                    unquote(args[1].split("&created=")[1].split("&")[0])[2:]
                )
                listed = [
                    r
                    for r in runs
                    if datetime.fromisoformat(str(r["created_at"])) >= floor
                ]
                return {
                    "total_count": len(listed) if runs_total is None else runs_total,
                    "workflow_runs": listed,
                }
            return list(issues)

        self.pins = mock.Mock(
            side_effect=pins if isinstance(pins, Exception) else None,
            return_value={5: SHA_PINNED} if pins is None else pins,
        )
        with (
            mock.patch.object(pm, "_read", side_effect=read),
            mock.patch.object(pm, "read_pins", self.pins),
        ):
            return pm.idle_refusal(
                REPO,
                shared(report=report),
                "main",
                confirm_wait_minutes=CONFIRM_WAIT,
                now=now,
            )

    def test_a_settled_report_nothing_moved_since_stands(self) -> None:
        self.assertIsNone(self.refusal())
        # Two run listings, one issue listing, one batched pin read.
        runs, issues = self.calls[:2], self.calls[2:]
        self.assertEqual(len(issues), 1)
        self.assertIn("issues?state=all&since=2026-09-30T23:59:00Z", issues[0])
        # Runs created since the `_lane_reruns` lookback (confirm wait plus
        # one allowance) and one more allowance for a baseline still going.
        lookback = FLOOR - timedelta(minutes=CONFIRM_WAIT) - 2 * pm.FULL_RUN_ALLOWANCE
        for call in runs:
            self.assertIn(
                "created=%3E%3D" + lookback.strftime("%Y-%m-%dT%H%%3A%M%%3A%SZ"),
                call,
            )
        self.assertEqual(list(self.pins.call_args.args[1]), [5])
        self.assertEqual(self.pins.call_args.args[2], IDENTITY)

    def test_each_unsettled_part_of_the_report_refuses_before_any_read(
        self,
    ) -> None:
        cases = {
            "not-passing": {"ok": False},
            "hold": {"hold": "unlisted-record"},
            "needs-dispatch": {"needsDispatch": True},
            "reruns": {"reruns": [{"runId": 9}]},
            "unattributed": {"unattributed": ["https://run/1/attempts/1"]},
            "quarantines": {"quarantines": [{"suite": "x"}]},
            "excused": {"excusesExpireAt": (NOW + timedelta(days=1)).isoformat()},
            "lane-reruns-unread": {"warnings": ["lane-rerun-unreadable: 502"]},
        }
        for reason, change in cases.items():
            with self.subTest(reason):
                self.assertEqual(self.refusal({**SETTLED, **change}), reason)
                self.assertEqual(self.calls, [])
        for key, reason in (
            ("excusesExpireAt", "excused"),
            ("pins", "pins-unrecorded"),
            ("outstandingSince", "outstanding-unrecorded"),
        ):
            with self.subTest(f"no {key}"):
                report = {k: v for k, v in SETTLED.items() if k != key}
                self.assertEqual(self.refusal(report), reason)
                self.assertEqual(self.calls, [])

    def test_it_leaves_the_later_jobs_their_headroom(self) -> None:
        # Never re-stamped: the age is the original check's, and the merge
        # and enable-auto-merge jobs settle the same report minutes later.
        edge = FLOOR + policy.SHARED_MAX_AGE - pm.IDLE_HEADROOM
        self.assertIsNone(self.refusal(now=edge))
        self.assertEqual(self.refusal(now=edge + timedelta(seconds=1)), "stale-soon")

    def test_a_verifying_run_that_completed_since_refuses(self) -> None:
        since = FLOOR - policy.SINCE_CLOCK_MARGIN
        for workflow in (
            "pr-require-checks.yml",
            "post-merge-detect-silent-revert.yml",
        ):
            with self.subTest(workflow):
                done = run(workflow, status="completed", updated=since)
                self.assertEqual(self.refusal(runs=[done]), "runs-changed")
        # Finished before the report, or still running: nothing changed yet.
        quiet = [
            run(
                "pr-require-checks.yml",
                status="completed",
                updated=since - timedelta(seconds=1),
            ),
            run("pr-require-checks.yml", status="in_progress", updated=NOW),
        ]
        self.assertIsNone(self.refusal(runs=quiet))
        self.assertTrue(self.refusal(runs_total=101).startswith("unreadable"))

    def test_an_unverified_merge_lists_runs_from_its_merge_and_ends_at_the_deadline(
        self,
    ) -> None:
        merged = FLOOR - timedelta(hours=5)
        pending = {
            **SETTLED,
            "autoMerges": [
                {"number": 5, "verified": False, "mergedAt": merged.isoformat()}
            ],
        }
        self.assertIsNone(self.refusal(pending))
        self.assertIn("created=%3E%3D2026-09-30T19%3A00%3A00Z", self.calls[0])
        late = merged + pm.DISPATCH_DEADLINE + timedelta(seconds=1)
        with mock.patch.object(policy, "SHARED_MAX_AGE", timedelta(days=1)):
            self.assertEqual(self.refusal(pending, now=late), "dispatch-deadline")

    def test_a_canary_still_queued_at_the_report_is_listed_however_old(
        self,
    ) -> None:
        # A verified merge's window holds a canary queued before the green
        # one that verified it; `_judge` fails the merge once it turns red,
        # however long before the `_lane_reruns` lookback it was created.
        queued = FLOOR - timedelta(hours=4)
        report = {**SETTLED, "outstandingSince": queued.isoformat()}
        red = run(
            "post-merge-detect-silent-revert.yml",
            status="completed",
            updated=NOW,
            created=queued,
        )
        self.assertEqual(self.refusal(report, runs=[red]), "runs-changed")
        self.assertIn("created=%3E%3D2026-09-30T20%3A00%3A00Z", self.calls[0])

    def test_a_quarantine_issue_changed_since_refuses(self) -> None:
        marked = {"number": 3, "body": "<!-- post-merge-quarantine suite=x -->\nbody"}
        self.assertEqual(self.refusal(issues=[marked]), "quarantine-changed")
        # A full page may hide one.
        page = [{"number": n, "body": ""} for n in range(100)]
        self.assertEqual(self.refusal(issues=page), "quarantine-changed")
        # An issue without the marker, or a pull request quoting it, is not one.
        other = [{"number": 4, "body": "triaged"}, {**marked, "pull_request": {}}]
        self.assertIsNone(self.refusal(issues=other))

    def test_a_pin_that_reads_differently_refuses(self) -> None:
        # An edited pin reads as None, a deleted one too, a new one another SHA.
        for pins in ({5: None}, {5: "c" * 40}):
            with self.subTest(pins):
                self.assertEqual(self.refusal(pins=pins), "pins-changed")
        failed = self.refusal(pins=pm.PostMergeReadError("#5 pin: 502"))
        self.assertEqual(failed, "unreadable: #5 pin: 502")


class CheckCodeUnchanged(unittest.TestCase):
    """`check_code_unchanged`: whether the check's code (the babysit-prs
    scripts, docs/conventions/pr-pipeline.yaml and the yaml-subset.awk parser
    that reads it) at HEAD is the code at the kept commit. Expected outcomes
    are the brief's: the same commit or a change elsewhere only allows reuse;
    a change in any of those paths, a missing,
    malformed or unknown commit, or a git failure refuses."""

    def setUp(self) -> None:
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="check-code-"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.git("init", "-q")
        # Repo-local, as in test_prune_babysit_worktrees.py: a global
        # commit.gpgsign would sign every fixture commit with the machine's key.
        self.git("config", "commit.gpgsign", "false")
        # The CRLF case needs the bytes stored as written.
        self.git("config", "core.autocrlf", "false")
        self.commits: dict[str, str] = {}
        for name, path in (
            ("init", "plugins/source-control/skills/babysit-prs/scripts/a.py"),
            ("init", "docs/conventions/pr-pipeline.yaml"),
            ("init", "plugins/source-control/lib/yaml-subset.awk"),
            ("base", "README.md"),
            ("elsewhere", "README.md"),
            ("scripts", "plugins/source-control/skills/babysit-prs/scripts/a.py"),
            ("config", "docs/conventions/pr-pipeline.yaml"),
            (
                "tests",
                "plugins/source-control/skills/babysit-prs/scripts/tests/test_a.py",
            ),
            ("parser", "plugins/source-control/lib/yaml-subset.awk"),
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

    def test_a_change_to_the_scripts_tests_alone_allows_reuse(self) -> None:
        # The tests decide no report, so a test-only commit keeps it.
        self.assertTrue(self.unchanged(self.commits["config"], "tests"))

    def test_a_change_to_the_scripts_or_the_pipeline_config_refuses(self) -> None:
        self.assertFalse(self.unchanged(self.commits["elsewhere"], "scripts"))
        self.assertFalse(self.unchanged(self.commits["scripts"], "config"))

    def test_a_change_to_the_config_parser_refuses(self) -> None:
        # yaml-subset.awk decides what the config means.
        self.assertFalse(self.unchanged(self.commits["tests"], "parser"))

    def commit_config(self, text: str) -> str:
        (self.root / "docs/conventions/pr-pipeline.yaml").write_text(text)
        self.git("commit", "-q", "--allow-empty", "-am", "edit")
        return self.git("rev-parse", "HEAD").strip()

    def test_a_comment_or_blank_line_edit_to_the_pipeline_config_allows_reuse(
        self,
    ) -> None:
        # 41344350944 ran the check again for a YAML comment edit: no parser
        # reads a whole-line comment, a blank line or trailing whitespace.
        # An apostrophe inside a plain value and closed quotes open nothing.
        body = 'merge:\n  rung: merge\n  why: a repository\'s flow\n  l: [a, "b: c"]\n'
        kept = self.commit_config("# one\n" + body)
        for edited in (
            "# one, reworded\n#  and a second line\n" + body,
            "# one\n\n" + body.replace("merge:\n", "merge:   \n\n"),
            body.replace("  rung", "    # indented comment\n  rung"),
        ):
            with self.subTest(edited):
                self.commit_config(edited)
                self.assertTrue(policy.check_code_unchanged(kept, root=self.root))

    def test_a_value_indentation_or_inline_comment_edit_refuses(self) -> None:
        kept = self.commit_config("merge:\n  rung: merge\n  x: 1\n")
        for edited in (
            "merge:\n  rung: off\n  x: 1\n",
            # Indentation is structure: x leaves merge.
            "merge:\n  rung: merge\nx: 1\n",
            # A `#` after a value may sit inside a quoted string.
            "merge:\n  rung: merge  # note\n  x: 1\n",
        ):
            with self.subTest(edited):
                self.commit_config(edited)
                self.assertFalse(policy.check_code_unchanged(kept, root=self.root))

    def test_a_change_the_config_parser_reads_differently_refuses(self) -> None:
        # yaml-subset.awk splits lines on \n only, drops one trailing \r and
        # takes only space and tab as blanks; Python's splitlines and strip
        # would hide each of these edits.
        body = (
            "merge:\n  rung: autonomous\n  diff-check:\n    denied-paths:\n"
            "      - secrets/**\nred-main:\n  confirm-wait-minutes: 30\n"
        )
        kept = self.commit_config(body)
        for edited in (
            body.replace("secrets/**", "secrets/**\xa0"),
            body.replace("30\n", "30 # x\n"),
            body.replace("autonomous", "autonomous\x0b"),
            body.replace("autonomous\n", "autonomous\r# c\n"),
            body + "\x0c# note\n",
        ):
            with self.subTest(edited):
                self.commit_config(edited)
                self.assertFalse(policy.check_code_unchanged(kept, root=self.root))

    def test_a_crlf_only_change_allows_reuse(self) -> None:
        # The parser drops each line's trailing \r.
        body = "merge:\n  rung: merge\n  x: 1\n"
        kept = self.commit_config(body)
        self.commit_config(body.replace("\n", "\r\n"))
        self.assertTrue(policy.check_code_unchanged(kept, root=self.root))

    def test_a_hash_line_inside_a_block_or_quoted_scalar_is_content(self) -> None:
        for before, after in (
            ("a: |\n  text\nb: 1\n", "a: |\n  text\n  # more text\nb: 1\n"),
            ("a: >-\n  text\n", "a: >-\n  text\n  # more\n"),
            ('a: "text\n  more"\n', 'a: "text\n  # x\n  more"\n'),
            ("a: 'text\n  more'\n", "a: 'text\n  # x\n  more'\n"),
        ):
            with self.subTest(after):
                kept = self.commit_config(before)
                self.commit_config(after)
                self.assertFalse(policy.check_code_unchanged(kept, root=self.root))

    def test_the_pipeline_config_unreadable_at_the_kept_commit_refuses(self) -> None:
        # The kept commit predates the file: `git show` fails, so not unchanged.
        self.git("checkout", "-q", "--detach", self.commits["config"])
        with mock.patch.object(policy, "CHECK_CODE_YAML", ("docs/absent.yaml",)):
            self.assertFalse(
                policy.check_code_unchanged(self.commits["config"], root=self.root)
            )

    def test_a_missing_malformed_or_unknown_commit_refuses(self) -> None:
        for kept in ("", "HEAD", "--output=x", "c" * 39, "f" * 40):
            with self.subTest(kept):
                self.assertFalse(self.unchanged(kept, "config"))

    def test_a_guarded_path_missing_at_head_refuses(self) -> None:
        # A diff of a path at neither commit is empty, so a renamed path
        # would otherwise read as unchanged.
        moved = (*policy.CHECK_CODE_PATHS, "docs/conventions/renamed.yaml")
        with mock.patch.object(policy, "CHECK_CODE_PATHS", moved):
            self.assertFalse(self.unchanged(self.commits["config"], "config"))

    def test_the_default_root_is_this_repository(self) -> None:
        # The brief's two paths, read from the checkout the script runs in.
        for path in policy.CHECK_CODE_PATHS:
            self.assertTrue((policy.CHECK_CODE_ROOT / path).exists(), path)
        here = subprocess.run(
            ["git", "-C", str(policy.CHECK_CODE_ROOT), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        self.assertTrue(policy.check_code_unchanged(here))

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
        idle: str | None = None,
        idle_report: str | list[str | None] | None = None,
        idle_runs: str | None = None,
        note: dict[str, str | None] | None = None,
        extra: tuple[str, ...] = (),
    ) -> tuple[int, dict, dict]:
        seen: dict[str, object] = {}
        # The idle rule's parts, in the order they read: the report (no
        # read), the verifying runs, then the quarantine issues and pins.
        self.order: list[str] = []

        def part(name: str, answer: str | list[str | None] | None) -> mock.Mock:
            answers = iter(answer) if isinstance(answer, list) else None

            def call(*_: object, **__: object) -> str | None:
                self.order.append(name)
                return next(answers) if answers is not None else answer  # type: ignore[return-value]

            return mock.Mock(side_effect=call)

        self.idle_report = part("report", idle_report)
        self.idle_runs = part("runs", idle_runs)
        self.idle = part("marks", idle)

        def settle(repo: str, answer: object, **kwargs: object) -> object:
            self.order.append("settle")
            seen.update(kwargs, repo=repo, answer=answer)
            if note is not None:
                kwargs["outcome"].update(note)  # type: ignore[union-attr]
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
            mock.patch.object(ve.postmerge, "idle_report_refusal", self.idle_report),
            mock.patch.object(ve.postmerge, "idle_runs_refusal", self.idle_runs),
            mock.patch.object(ve.postmerge, "idle_marks_refusal", self.idle),
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
                    *extra,
                ]
            )
        self.code, self.read_config = code, read_config
        return exit_code, json.loads(out.getvalue()), seen

    def test_it_exits_0_when_the_answer_stands_and_1_when_refused(self) -> None:
        code, out, seen = self.main(("answer", None))
        self.assertEqual(
            (code, out), (0, {"reuse": True, "reason": None, "outcome": None})
        )
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
            (
                1,
                {
                    "reuse": False,
                    "reason": "post-merge answer unverified-stale",
                    "outcome": None,
                },
            ),
        )

    def test_it_prints_what_moved_as_settle_shared_found_it(self) -> None:
        # 41341833807 logged `unverified-stale` and nothing of what moved.
        moved = {
            "answer": "refused",
            "reason": "unverified-stale",
            "moved": "runs-moved",
        }
        _, out, _ = self.main(
            (None, "post-merge answer unverified-stale"),
            note=moved,
            extra=("--idle-tick",),
        )
        self.assertEqual(out["outcome"], moved)

    def test_changed_check_code_is_refused_before_any_read(self) -> None:
        code, out, seen = self.main(("answer", None), code_unchanged=False, code_sha="")
        self.assertEqual(
            (code, out),
            (
                1,
                {
                    "reuse": False,
                    "reason": "post-merge answer code-changed",
                    "outcome": None,
                },
            ),
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

    def test_an_idle_tick_also_needs_the_idle_rule(self) -> None:
        # post-merge-dispatch's reuse of an earlier tick's report: every part
        # of `idle_refusal` on the same answer as well as the lane room's
        # rule, at the default branch with the head config's confirm wait.
        idle = ("--idle-tick",)
        code, out, _ = self.main(("answer", None), extra=idle)
        self.assertEqual(
            (code, out), (0, {"reuse": True, "reason": None, "outcome": None})
        )
        self.assertEqual(self.order, ["report", "runs", "settle", "marks", "report"])
        self.idle_runs.assert_called_once_with(
            REPO, "answer", "main", confirm_wait_minutes=config().confirm_wait_minutes
        )
        self.idle.assert_called_once_with(REPO, "answer")
        code, out, _ = self.main(("answer", None), extra=idle, idle="pins-changed")
        self.assertEqual(
            (code, out),
            (1, {"reuse": False, "reason": "idle tick pins-changed", "outcome": None}),
        )
        # A report the lane room's rule refuses is never offered to the
        # quarantine and pin reads.
        code, out, _ = self.main((None, "post-merge answer stale"), extra=idle)
        self.assertEqual(code, 1)
        self.idle.assert_not_called()
        # Without the flag (the merge job's reuse of this run's report), no
        # idle rule.
        self.assertEqual(self.main(("answer", None), idle="runs-changed")[0], 0)
        self.assertEqual(self.order, ["settle"])

    def test_an_idle_refusal_the_report_decides_reads_nothing(self) -> None:
        # The report's own refusals need no read, so neither the config nor
        # the lane room's rule is read for them.
        code, out, seen = self.main(
            ("answer", None), extra=("--idle-tick",), idle_report="needs-dispatch"
        )
        self.assertEqual((code, out["reason"]), (1, "idle tick needs-dispatch"))
        self.assertEqual(self.order, ["report"])
        self.read_config.assert_not_called()
        self.assertEqual(seen, {})

    def test_a_report_asking_for_a_full_run_spends_no_read(self) -> None:
        # The real report rule on a real report: no GitHub read at all.
        out = io.StringIO()
        report = shared(report={**SETTLED, "needsDispatch": True})
        with (
            mock.patch.object(ve.postmerge, "read_shared", return_value=report),
            mock.patch.object(policy, "check_code_unchanged", return_value=True),
            mock.patch.object(policy, "_get", side_effect=AssertionError("read")),
            mock.patch.object(pm, "_read", side_effect=AssertionError("read")),
            mock.patch.object(policy, "settle_shared") as settle,
            contextlib.redirect_stdout(out),
        ):
            code = ve.main(
                [
                    "settle",
                    "--idle-tick",
                    "--repo",
                    REPO,
                    "--postmerge-result",
                    "/tmp/x.json",
                    "--code-sha",
                    MAIN,
                ]
            )
        self.assertEqual(code, 1)
        self.assertEqual(
            json.loads(out.getvalue())["reason"], "idle tick needs-dispatch"
        )
        settle.assert_not_called()

    def test_changed_verifying_runs_refuse_before_the_lane_rooms_reads(self) -> None:
        # 41345813084: `runs-changed` after settle_shared's 22 calls. The two
        # run listings now come first.
        code, out, seen = self.main(
            ("answer", None), extra=("--idle-tick",), idle_runs="runs-changed"
        )
        self.assertEqual((code, out["reason"]), (1, "idle tick runs-changed"))
        self.assertEqual(self.order, ["report", "runs"])
        self.assertEqual(seen, {})

    def test_the_report_checks_run_again_after_the_reads(self) -> None:
        # A report that turned stale-soon during the reads is refused, as it
        # was when the whole idle rule ran after the lane room's rule.
        code, out, _ = self.main(
            ("answer", None), extra=("--idle-tick",), idle_report=[None, "stale-soon"]
        )
        self.assertEqual((code, out["reason"]), (1, "idle tick stale-soon"))
        self.assertEqual(self.order, ["report", "runs", "settle", "marks", "report"])


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
            return policy.LaneRoom(
                count=1,
                cap=5,
                queued=frozenset({3}),
                rung="C2",
                post_merge={"answer": "recomputed", "reason": "stale", "moved": None},
            )

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
                "postMerge": {"answer": "recomputed", "reason": "stale", "moved": None},
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

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
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy  # noqa: E402
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
    "autoMerges": [{"number": 5, "verified": False}],
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
    identity it was asked for, and each answer shared."""

    def __init__(
        self, gate: policy.PostMergeGate | None = None, error: Exception | None = None
    ) -> None:
        self.gate, self.error = gate, error
        self.asked: list[tuple[datetime, str]] = []
        self.shared: list[policy.SharedPostMerge] = []

    def post_merge(self, floor: datetime, identity: str) -> policy.PostMergeGate:
        self.asked.append((floor, identity))
        if self.error is not None:
            raise self.error
        assert self.gate is not None
        return self.gate

    def share(self, answer: policy.SharedPostMerge) -> None:
        self.shared.append(answer)


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
        share: object = None,
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
            mock.patch.object(policy, "newest_config_commit", return_value=MAIN),
            mock.patch.object(policy, "_get", return_value=(200, {"sha": MAIN})),
            # The recompute's reads at the default branch head: a newer head,
            # no demotion record, and a later floor than the old answer's.
            mock.patch.object(
                policy,
                "_default_branch_head",
                side_effect=head_error,
                return_value=("main", NEW_MAIN),
            ),
            mock.patch.object(policy, "permission_reader"),
            mock.patch.object(
                policy,
                "read_demotion",
                return_value=fresh_demotion or policy.Demotion(False, None, ()),
            ),
            mock.patch.object(policy, "merged_since_floor", return_value=NEW_FLOOR),
        ):
            kwargs = {"post_merge": post_merge} if post_merge is not None else {}
            if share is not None:
                kwargs["share"] = share
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
                    share=recheck.share,
                    **kwargs,  # type: ignore[arg-type]
                )
                self.assertIsNone(room.refusal)
                self.assertTrue(room.unreadable)
        self.assertFalse(self.seen, "no in-flight read after an unusable answer")
        # Only an unverified-stale answer is read again.
        self.assertEqual((recheck.asked, recheck.shared), ([], []))

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
            room = self.room(post_merge=recheck.post_merge, share=recheck.share)
        self.assertEqual(
            (room.refusal, room.unreadable),
            (None, "post-merge answer new-merge:#7"),
        )
        self.assertFalse(self.seen, "no in-flight read after an unusable answer")
        self.assertEqual((recheck.asked, recheck.shared), ([], []))
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
            share=recheck.share,
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
        # Written back once, bound to the head and time it was read at.
        self.assertEqual(len(recheck.shared), 1)
        written = recheck.shared[0]
        self.assertEqual(
            (
                written.main_sha,
                written.computed_at,
                written.floor,
                written.identity,
                written.lane_merges_only,
                written.self_logins,
                written.gate,
            ),
            (NEW_MAIN, STALE_NOW, NEW_FLOOR, IDENTITY, True, frozenset(), fresh),
        )

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
            share=recheck.share,
        )
        self.assertEqual(
            (room.refusal, room.unreadable), ("post-merge:failure:red-main#5", None)
        )
        self.assertFalse(self.seen, "no in-flight read after a refusal")
        # A readable failure goes back to the file, as the gate's does.
        self.assertEqual(len(recheck.shared), 1)

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
            share=recheck.share,
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
                    share=recheck.share,
                )
                self.assertIsNone(room.refusal)
                self.assertTrue(
                    str(room.unreadable).startswith(
                        "post-merge answer unverified-stale"
                    ),
                    room.unreadable,
                )
                self.assertEqual(recheck.shared, [], "nothing unreadable is written")
        # A head that cannot be read is a failed recompute too.
        recheck = Recheck(policy.PostMergeGate(None, {"readable": True}, None))
        room = self.room(
            shared(report=PENDING),
            now=STALE_NOW,
            post_merge=recheck.post_merge,
            share=recheck.share,
            head_error=policy.PolicyReadError("head 502"),
        )
        self.assertIsNone(room.refusal)
        self.assertTrue(room.unreadable)
        self.assertEqual((recheck.asked, recheck.shared), ([], []))
        # With no check to run, it stays unreadable as before.
        room = self.room(shared(report=PENDING), now=STALE_NOW)
        self.assertEqual(room.unreadable, "post-merge answer unverified-stale")
        self.assertFalse(self.seen, "no in-flight read after an unusable answer")

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
            share: object,
        ) -> policy.LaneRoom:
            seen.append((repo, answer, lane_rung_cap))
            hooks.update(post_merge=post_merge, share=share)
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

    def test_a_recompute_is_written_back_to_the_report_it_read(self) -> None:
        # The gate's write-back: the next reader of the same file reuses it.
        hooks: dict[str, object] = {}

        def room(repo: str, answer: object, **kwargs: object) -> policy.LaneRoom:
            hooks.update(kwargs)
            return policy.LaneRoom()

        with tempfile.TemporaryDirectory() as tmp:
            path = str(pathlib.Path(tmp) / "post-merge.json")
            with (
                mock.patch.object(policy, "lane_room", side_effect=room),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                ve.main(["lane-room", "--repo", REPO, "--postmerge-result", path])
            answer = shared(report={**PENDING, "ok": True})
            hooks["share"](answer)  # type: ignore[operator]
            back = ve.postmerge.read_shared(path)
        assert back is not None
        self.assertEqual(
            (back.main_sha, back.identity, back.floor, back.computed_at),
            (MAIN, IDENTITY, FLOOR, FLOOR),
        )

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

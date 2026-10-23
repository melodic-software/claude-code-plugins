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
import babysit_verify_evidence as ve  # noqa: E402

REPO = "example-org/example-repo"
IDENTITY = "agent-lanes[bot]"
MAIN = "c" * 40
FLOOR = datetime(2026, 10, 1, tzinfo=UTC)
# Five minutes after the answer was computed: inside the gate's reuse age.
NOW = FLOOR + timedelta(minutes=5)


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
    *, demoted: bool = False, refusal: str | None = None, identity: str = IDENTITY
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
        gate=policy.PostMergeGate(refusal, {}, lambda merge: True),
    )


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
        ):
            result = policy.lane_room(
                REPO,
                answer if answer is not None else shared(),
                lane_rung_cap=cap,
                now=now,
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
            "demotion changed": dict(demotion_changed=True),
        }
        for name, kwargs in cases.items():
            with self.subTest(name):
                room = self.room(**kwargs)  # type: ignore[arg-type]
                self.assertIsNone(room.refusal)
                self.assertTrue(room.unreadable)
        self.assertFalse(self.seen, "no in-flight read after an unusable answer")

    def test_a_lane_merge_the_answer_does_not_count_is_unreadable(self) -> None:
        # The gate's reuse rule (shared_refusal) reads afresh when a lane
        # merge landed after the report was computed (`new-merge:#<n>`), so
        # its failed full run is not missed; the room holds rather than arm.
        seen: list[dict[str, object]] = []

        def refusal(repo: str, answer: object, **kwargs: object) -> str:
            seen.append(kwargs)
            return "new-merge:#7"

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

        def room(
            repo: str, answer: object, *, lane_rung_cap: str | None
        ) -> policy.LaneRoom:
            seen.append((repo, answer, lane_rung_cap))
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

"""Review-evidence binding: per-lane evidence from workflow runs, attempts,
completion annotations, the reviewed-head marker and review threads.

Expected values come from the plan's Design section "Review evidence" and the
lane producer's record format (ci-workflows pr-review.yml at v0.41.0). The
probe fixture is a recorded, de-identified run pair from a sandbox pull
request whose two lanes were each re-run once after a successful attempt.
"""

from __future__ import annotations

import copy
import json
import pathlib
import sys
import unittest
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_review_evidence as ev

FIXTURES = pathlib.Path(__file__).resolve().parent / "fixtures" / "review_evidence"
PROBE = json.loads((FIXTURES / "probe_rerun_after_success.json").read_text())

S = "5e1f" * 10  # pinned head
S0 = "a0" * 20
S1 = "b1" * 20
LANES = ("claude-review", "claude-security-review")
FILES = {
    "claude-review": ".github/workflows/pr-review-hosted.yml",
    "claude-security-review": ".github/workflows/pr-review-security-hosted.yml",
}
JOBS = {
    "claude-review": "pr-review / claude-review-status",
    "claude-security-review": "pr-review-security / security-review",
}
MAINTAINER = {"__typename": "User", "login": "maintainer"}
# The flagged line is the hunk's last line.
HUNK = "@@ -1,2 +1,2 @@\n context\n+run(user_input)"


def is_human(actor: Any) -> bool:
    return actor == MAINTAINER


def record(lane: str, sha: str, tail: str) -> dict[str, Any]:
    return {
        "path": ".github",
        "annotation_level": "notice",
        "title": "claude-lane-review-complete",
        "message": f"claude-lane-review-complete lane={lane} sha={sha} {tail}",
    }


RATE_LIMIT = {
    "path": ".github",
    "annotation_level": "failure",
    "title": "claude-review skipped",
    "message": "AI review skipped: usage limit reached; re-run after it resets"
    " (failure-class=rate-limit)",
}
OTHER_FAILURE = {
    "path": ".github",
    "annotation_level": "failure",
    "title": "claude-review failed",
    "message": "failure-class=incomplete: no completed review was found on this head",
}

_ids = iter(range(1000, 10**6))


def attempt(
    lane: str,
    sha: str,
    n: int,
    annotations: list[dict[str, Any]],
    conclusion: str = "success",
) -> dict[str, Any]:
    job_id = next(_ids)
    return {
        "run_attempt": n,
        "head_sha": sha,
        "status": "completed",
        "conclusion": conclusion,
        "jobs": [
            {
                "id": job_id,
                "run_attempt": n,
                "name": JOBS[lane],
                "status": "completed",
                "conclusion": conclusion,
                "head_sha": sha,
                "started_at": "2026-01-01T00:00:00Z",
                "completed_at": "2026-01-01T01:00:00Z",
                "annotations": annotations,
            }
        ],
    }


def run(
    lane: str,
    sha: str,
    tail: str | None = None,
    *,
    attempts: list[dict[str, Any]] | None = None,
    created: str = "2026-01-01T00:00:00Z",
) -> dict[str, Any]:
    if attempts is None:
        annotations = [record(lane, sha, tail)] if tail is not None else []
        attempts = [attempt(lane, sha, 1, annotations)]
    run_id = next(_ids)
    latest = attempts[-1]
    for item in attempts:
        item["id"] = run_id
        for job in item["jobs"]:
            job["run_id"] = run_id
    return {
        "id": run_id,
        "path": FILES[lane],
        "head_sha": sha,
        "event": "pull_request",
        "status": latest["status"],
        "conclusion": latest["conclusion"],
        "run_attempt": latest["run_attempt"],
        "created_at": created,
        "attempts": attempts,
    }


def marker(lane: str, sha: str, login: str = "github-actions[bot]") -> dict[str, Any]:
    return {
        "id": next(_ids),
        "user": {"login": login, "type": "Bot"},
        "created_at": "2026-01-01T00:00:00Z",
        "body": f"<!-- claude-lane-reviewed-head lane={lane} sha={sha} -->\n"
        f"{lane} has reviewed this pull request through {sha}.",
    }


def thread(
    body: str = "a finding",
    *,
    resolved: bool = False,
    resolved_by: Any = None,
    author: dict[str, Any] | None = None,
    created: str = "2026-01-01T00:30:00Z",
    outdated: bool = False,
    hunk: Any = HUNK,
    lines: tuple[int | None, int | None] = (None, 2),
) -> dict[str, Any]:
    return {
        "id": f"t{next(_ids)}",
        "isResolved": resolved,
        "isOutdated": outdated,
        "resolvedBy": resolved_by,
        "originalStartLine": lines[0],
        "originalLine": lines[1],
        "comments": [
            {
                "author": author or {"__typename": "Bot", "login": "claude"},
                "body": body,
                "createdAt": created,
                "path": "app.py",
                "diffHunk": hunk,
                "originalCommit": {"oid": S1},
            }
        ],
    }


def fixed_head(path: str, original: str) -> str | None:
    """The file at the pinned head with the flagged line rewritten."""
    return "context\nrun(clean(user_input))\n"


def whole(lane: str, sha: str, n: int = 0, k: int = 0) -> dict[str, Any]:
    return run(lane, sha, f"findings={n} inline={k} scope=whole")


def both_markers(sha: str = S) -> list[dict[str, Any]]:
    return [marker(lane, sha) for lane in LANES]


def by_lane(result: tuple[Any, ...]) -> dict[str, Any]:
    return {item.lane: item for item in result}


class ProbeFixtureTests(unittest.TestCase):
    """Bind the recorded probe data as recorded and with one change each."""

    def bind(self, data: dict[str, Any]) -> dict[str, Any]:
        return by_lane(
            ev.bind(
                data["head_sha"],
                data["runs"],
                data["comments"],
                data["threads"],
                is_human=is_human,
                changed_paths=(),
            )
        )

    def test_rerun_after_a_successful_attempt_is_not_allowed(self) -> None:
        result = self.bind(PROBE)
        for lane in LANES:
            self.assertFalse(result[lane].bound, lane)
            self.assertEqual(result[lane].unbound_reason, "rerun-not-allowed")
            self.assertIsNone(result[lane].open_findings)

    def test_first_attempt_alone_binds_with_no_open_finding(self) -> None:
        data = copy.deepcopy(PROBE)
        for item in data["runs"]:
            item["attempts"] = item["attempts"][:1]
            item["run_attempt"] = 1
        result = self.bind(data)
        for lane in LANES:
            self.assertTrue(result[lane].bound, lane)
            self.assertIsNone(result[lane].unbound_reason)
            self.assertEqual(result[lane].open_findings, 0)

    def test_rerun_after_a_rate_limit_failure_binds(self) -> None:
        data = copy.deepcopy(PROBE)
        for item in data["runs"]:
            first = item["attempts"][0]
            first["conclusion"] = "failure"
            first["jobs"][0]["conclusion"] = "failure"
            first["jobs"][0]["annotations"] = [RATE_LIMIT]
        result = self.bind(data)
        for lane in LANES:
            self.assertTrue(result[lane].bound, lane)
            self.assertEqual(result[lane].open_findings, 0)

    def test_marker_missing_for_one_lane_unbinds_only_that_lane(self) -> None:
        data = copy.deepcopy(PROBE)
        for item in data["runs"]:
            item["attempts"] = item["attempts"][:1]
            item["run_attempt"] = 1
        data["comments"] = [
            c
            for c in data["comments"]
            if "lane=claude-security-review" not in c["body"]
        ]
        result = self.bind(data)
        self.assertTrue(result["claude-review"].bound)
        self.assertFalse(result["claude-security-review"].bound)
        self.assertEqual(result["claude-security-review"].unbound_reason, "no-marker")


class Base(unittest.TestCase):
    def bind(
        self,
        runs: list[dict[str, Any]],
        comments: list[dict[str, Any]] | None = None,
        threads: list[dict[str, Any]] | None = (),  # type: ignore[assignment]
        head_file: Any = fixed_head,
        changed_paths: Any = (),
    ) -> dict[str, Any]:
        return by_lane(
            ev.bind(
                S,
                runs,
                both_markers() if comments is None else comments,
                list(threads) if threads is not None else None,
                is_human=is_human,
                head_file=head_file,
                changed_paths=changed_paths,
            )
        )

    def assertUnbound(self, item: Any, reason: str) -> None:
        self.assertFalse(item.bound)
        self.assertEqual(item.unbound_reason, reason)
        self.assertIsNone(item.open_findings)


class LostEvidenceTests(Base):
    """A review whose findings can no longer be counted unbinds the lane; it
    never lowers the count (the #7325 security review's carry-forward)."""

    def test_a_retargeted_pull_request_binds_no_lane(self) -> None:
        result = by_lane(
            ev.bind(
                S,
                [whole(lane, S) for lane in LANES],
                both_markers(),
                [],
                is_human=is_human,
                base_changed=True,
                changed_paths=(),
            )
        )
        for lane in LANES:
            self.assertUnbound(result[lane], "base-retargeted")

    def test_a_reviewed_head_whose_run_is_gone_unbinds_the_lane(self) -> None:
        # S0 was reviewed (its marker stands) but its run, and the findings it
        # recorded, no longer list: deleted or expired.
        runs = [whole(lane, S) for lane in LANES]
        comments = [marker("claude-review", S0), *both_markers()]
        result = self.bind(runs, comments)
        self.assertUnbound(result["claude-review"], "run-missing")
        self.assertTrue(result["claude-security-review"].bound)

    def test_every_marked_head_listed_still_binds(self) -> None:
        runs = [whole(lane, S) for lane in LANES] + [whole("claude-review", S0, n=2)]
        comments = [marker("claude-review", S0), *both_markers()]
        result = self.bind(runs, comments)
        self.assertTrue(result["claude-review"].bound)
        # The whole review at S covers the head and reports none of S0's two.
        self.assertEqual(result["claude-review"].open_findings, 0)


class LaneSourceTests(Base):
    """A pull request that changes what the review lanes run from its own
    checkout ran its own copy on its pull_request event, so no lane binds on
    its records."""

    def bound(self, *paths: str) -> dict[str, Any]:
        return self.bind([whole(lane, S) for lane in LANES], changed_paths=paths)

    def test_a_change_to_the_security_lane_caller_binds_no_lane(self) -> None:
        result = self.bound("app.py", ".github/workflows/pr-review-security-hosted.yml")
        for lane in LANES:
            self.assertUnbound(result[lane], "lane-source-changed")

    def test_a_change_to_a_file_the_lane_runs_from_the_checkout(self) -> None:
        for path in (
            ".github/actions/resolve-config/action.yml",
            ".github/scripts/pr-unblock/feedback-dispatch.mjs",
            "plugins/review/skills/security-review/SKILL.md",
            ".claude/settings.json",
            "plugins/foo/.claude/rules/x.md",
            ".mcp.json",
            "plugins/foo/.mcp.json",
        ):
            with self.subTest(path):
                result = self.bound(path)
                for lane in LANES:
                    self.assertUnbound(result[lane], "lane-source-changed")

    def test_unrelated_changes_bind_as_before(self) -> None:
        result = self.bound("app.py", "docs/github/x.md", "plugins/reviewer/a.py")
        for lane in LANES:
            self.assertTrue(result[lane].bound, lane)
            self.assertEqual(result[lane].open_findings, 0)

    def test_unread_changed_files_bind_no_lane(self) -> None:
        result = self.bind([whole(lane, S) for lane in LANES], changed_paths=None)
        for lane in LANES:
            self.assertUnbound(result[lane], "changed-files-unread")


class RunSelectionTests(Base):
    def test_both_lanes_whole_reviews_bind(self) -> None:
        result = self.bind([whole(lane, S) for lane in LANES])
        self.assertEqual([r.bound for r in result.values()], [True, True])

    def test_result_has_one_entry_per_lane_in_order(self) -> None:
        result = ev.bind(S, [], [], [], is_human=is_human, changed_paths=())
        self.assertEqual([item.lane for item in result], list(LANES))

    def test_no_run_on_the_pinned_head(self) -> None:
        result = self.bind([whole("claude-review", S0)])
        self.assertUnbound(result["claude-review"], "no-run")

    def test_newest_run_failed_after_an_older_success(self) -> None:
        older = whole("claude-review", S)
        newer = run(
            "claude-review",
            S,
            attempts=[attempt("claude-review", S, 1, [OTHER_FAILURE], "failure")],
            created="2026-01-02T00:00:00Z",
        )
        result = self.bind([older, newer])
        self.assertUnbound(result["claude-review"], "run-not-success")

    def test_newest_run_wins_whatever_the_listing_order(self) -> None:
        older = run(
            "claude-review",
            S,
            attempts=[attempt("claude-review", S, 1, [OTHER_FAILURE], "failure")],
        )
        newer = run(
            "claude-review",
            S,
            "findings=0 inline=0 scope=whole",
            created="2026-01-02T00:00:00Z",
        )
        result = self.bind([newer, older])
        self.assertTrue(result["claude-review"].bound)

    def test_run_from_another_event_is_ignored(self) -> None:
        other = whole("claude-review", S)
        other["event"] = "pull_request_target"
        result = self.bind([other])
        self.assertUnbound(result["claude-review"], "no-run")

    def test_run_of_another_workflow_file_is_ignored(self) -> None:
        other = whole("claude-review", S)
        other["path"] = ".github/workflows/something-else.yml"
        result = self.bind([other])
        self.assertUnbound(result["claude-review"], "no-run")

    def test_listing_and_latest_attempt_must_both_say_success(self) -> None:
        listing_red = whole("claude-review", S)
        listing_red["conclusion"] = "failure"
        attempt_red = whole("claude-review", S)
        attempt_red["attempts"][0]["conclusion"] = "failure"
        for item in (listing_red, attempt_red):
            self.assertUnbound(self.bind([item])["claude-review"], "run-not-success")

    def test_older_run_still_in_progress_does_not_unbind(self) -> None:
        older = whole("claude-review", S0)
        older["status"] = "in_progress"
        older["conclusion"] = None
        older["attempts"][0].update(status="in_progress", conclusion=None, jobs=[])
        result = self.bind([older, whole("claude-review", S)])
        self.assertTrue(result["claude-review"].bound)

    def test_in_progress_newest_run(self) -> None:
        item = whole("claude-review", S)
        item["status"] = "in_progress"
        item["conclusion"] = None
        item["attempts"][0]["status"] = "in_progress"
        item["attempts"][0]["conclusion"] = None
        result = self.bind([item])
        self.assertUnbound(result["claude-review"], "run-not-success")


class AttemptRuleTests(Base):
    def lane_run(self, *attempts: dict[str, Any]) -> dict[str, Any]:
        return run("claude-review", S, attempts=list(attempts))

    def ok(self, n: int) -> dict[str, Any]:
        return attempt(
            "claude-review",
            S,
            n,
            [record("claude-review", S, "findings=0 inline=0 scope=whole")],
        )

    def test_second_attempt_after_another_failure_class(self) -> None:
        first = attempt("claude-review", S, 1, [OTHER_FAILURE], "failure")
        result = self.bind([self.lane_run(first, self.ok(2))])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_second_attempt_after_a_rate_limit_failure(self) -> None:
        first = attempt("claude-review", S, 1, [RATE_LIMIT], "failure")
        result = self.bind([self.lane_run(first, self.ok(2))])
        self.assertTrue(result["claude-review"].bound)

    def test_rate_limit_annotation_on_a_successful_first_attempt(self) -> None:
        first = attempt("claude-review", S, 1, [RATE_LIMIT], "success")
        result = self.bind([self.lane_run(first, self.ok(2))])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_third_attempt_is_never_allowed(self) -> None:
        first = attempt("claude-review", S, 1, [RATE_LIMIT], "failure")
        second = attempt("claude-review", S, 2, [RATE_LIMIT], "failure")
        result = self.bind([self.lane_run(first, second, self.ok(3))])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_missing_first_attempt_data(self) -> None:
        item = self.lane_run(self.ok(2))
        result = self.bind([item])
        self.assertUnbound(result["claude-review"], "evidence-missing")

    def test_attempt_newer_than_the_listing_is_an_evidence_error(self) -> None:
        # The listing was read before a re-run, the attempts after it.
        rerun = attempt("claude-review", S, 2, [], "failure")
        rerun.update(status="in_progress", conclusion=None)
        item = self.lane_run(self.ok(1), rerun)
        item.update(status="completed", conclusion="success", run_attempt=1)
        result = self.bind([item])
        self.assertUnbound(result["claude-review"], "evidence-error")

    def test_stale_listing_on_an_earlier_link_is_an_evidence_error(self) -> None:
        base = run(
            "claude-review",
            S0,
            attempts=[
                attempt(
                    "claude-review",
                    S0,
                    1,
                    [record("claude-review", S0, "findings=0 inline=0 scope=whole")],
                ),
                attempt("claude-review", S0, 2, [], "failure"),
            ],
        )
        base.update(status="completed", conclusion="success", run_attempt=1)
        head = run(
            "claude-review", S, f"findings=0 inline=0 scope=incremental since={S0}"
        )
        result = self.bind([base, head])
        self.assertUnbound(result["claude-review"], "evidence-error")


class RecordTests(Base):
    def test_no_completion_record(self) -> None:
        result = self.bind([run("claude-review", S)])
        self.assertUnbound(result["claude-review"], "no-record")

    def test_record_for_another_lane(self) -> None:
        item = run(
            "claude-review",
            S,
            attempts=[
                attempt(
                    "claude-review",
                    S,
                    1,
                    [
                        record(
                            "claude-security-review",
                            S,
                            "findings=0 inline=0 scope=whole",
                        )
                    ],
                )
            ],
        )
        result = self.bind([item])
        self.assertUnbound(result["claude-review"], "record-malformed")

    def test_record_for_another_head(self) -> None:
        item = run(
            "claude-review",
            S,
            attempts=[
                attempt(
                    "claude-review",
                    S,
                    1,
                    [record("claude-review", S0, "findings=0 inline=0 scope=whole")],
                )
            ],
        )
        result = self.bind([item])
        self.assertUnbound(result["claude-review"], "record-malformed")

    def test_record_with_a_non_numeric_count(self) -> None:
        result = self.bind(
            [run("claude-review", S, "findings=lots inline=0 scope=whole")]
        )
        self.assertUnbound(result["claude-review"], "record-malformed")

    def test_two_records_in_one_job(self) -> None:
        tail = "findings=0 inline=0 scope=whole"
        item = run(
            "claude-review",
            S,
            attempts=[
                attempt(
                    "claude-review",
                    S,
                    1,
                    [
                        record("claude-review", S, tail),
                        record("claude-review", S, tail),
                    ],
                )
            ],
        )
        result = self.bind([item])
        self.assertUnbound(result["claude-review"], "record-malformed")

    def test_record_on_a_job_of_another_name(self) -> None:
        item = whole("claude-review", S)
        item["attempts"][0]["jobs"][0]["name"] = "pr-review / something-else"
        result = self.bind([item])
        self.assertUnbound(result["claude-review"], "no-lane-job")


class MarkerTests(Base):
    def test_marker_by_another_author(self) -> None:
        comments = [marker("claude-review", S, login="octo-maintainer")]
        result = self.bind([whole("claude-review", S)], comments)
        self.assertUnbound(result["claude-review"], "no-marker")

    def test_newest_marker_names_another_head(self) -> None:
        comments = [marker("claude-review", S), marker("claude-review", S0)]
        result = self.bind([whole("claude-review", S)], comments)
        self.assertUnbound(result["claude-review"], "no-marker")

    def test_marker_not_on_the_first_line(self) -> None:
        comment = marker("claude-review", S)
        comment["body"] = "quoted:\n" + comment["body"]
        result = self.bind([whole("claude-review", S)], [comment])
        self.assertUnbound(result["claude-review"], "no-marker")


class SkipTests(Base):
    def test_no_change_skip_binds_with_the_reviewed_run(self) -> None:
        runs = [
            run("claude-review", S0, "findings=3 inline=1 scope=whole"),
            run("claude-review", S, f"skip=no-change through={S0}"),
        ]
        threads = [thread()]
        result = self.bind(runs, threads=threads)
        self.assertTrue(result["claude-review"].bound)
        # (3 - 1) summary findings plus one open inline thread.
        self.assertEqual(result["claude-review"].open_findings, 3)

    def test_no_change_skip_to_another_skip_is_unbound(self) -> None:
        runs = [
            run("claude-review", S1, "findings=0 inline=0 scope=whole"),
            run("claude-review", S0, f"skip=no-change through={S1}"),
            run("claude-review", S, f"skip=no-change through={S0}"),
        ]
        result = self.bind(runs)
        self.assertUnbound(result["claude-review"], "skip-chain")

    def test_no_change_skip_to_an_unreviewed_head(self) -> None:
        result = self.bind([run("claude-review", S, f"skip=no-change through={S0}")])
        self.assertUnbound(result["claude-review"], "incremental-gap")

    def test_docs_only_skip_never_binds(self) -> None:
        result = self.bind([run("claude-review", S, "skip=docs-only")])
        self.assertUnbound(result["claude-review"], "skip-not-no-change")


class IncrementalTests(Base):
    def test_incremental_chain_back_to_a_whole_review(self) -> None:
        runs = [
            run("claude-review", S1, "findings=0 inline=0 scope=whole"),
            run(
                "claude-review", S0, f"findings=0 inline=0 scope=incremental since={S1}"
            ),
            run(
                "claude-review", S, f"findings=0 inline=0 scope=incremental since={S0}"
            ),
        ]
        self.assertTrue(self.bind(runs)["claude-review"].bound)

    def test_incremental_with_no_run_behind_it(self) -> None:
        runs = [
            run("claude-review", S, f"findings=0 inline=0 scope=incremental since={S0}")
        ]
        self.assertUnbound(self.bind(runs)["claude-review"], "incremental-gap")

    def test_incremental_behind_a_failed_run(self) -> None:
        failed = run(
            "claude-review",
            S0,
            attempts=[attempt("claude-review", S0, 1, [OTHER_FAILURE], "failure")],
        )
        runs = [
            failed,
            run(
                "claude-review", S, f"findings=0 inline=0 scope=incremental since={S0}"
            ),
        ]
        self.assertUnbound(self.bind(runs)["claude-review"], "incremental-gap")

    def test_incremental_since_a_docs_only_skip(self) -> None:
        runs = [
            run("claude-review", S0, "skip=docs-only"),
            run(
                "claude-review", S, f"findings=0 inline=0 scope=incremental since={S0}"
            ),
        ]
        self.assertUnbound(self.bind(runs)["claude-review"], "incremental-gap")

    def test_incremental_cycle(self) -> None:
        runs = [
            run(
                "claude-review", S0, f"findings=0 inline=0 scope=incremental since={S}"
            ),
            run(
                "claude-review", S, f"findings=0 inline=0 scope=incremental since={S0}"
            ),
        ]
        self.assertUnbound(self.bind(runs)["claude-review"], "incremental-gap")

    def test_incremental_through_a_no_change_skip(self) -> None:
        runs = [
            run("claude-review", S1, "findings=0 inline=0 scope=whole"),
            run("claude-review", S0, f"skip=no-change through={S1}"),
            run(
                "claude-review", S, f"findings=0 inline=0 scope=incremental since={S0}"
            ),
        ]
        self.assertTrue(self.bind(runs)["claude-review"].bound)


class CountTests(Base):
    def test_summary_findings_sum_over_the_covering_chain(self) -> None:
        runs = [
            run("claude-review", S0, "findings=3 inline=1 scope=whole"),
            run(
                "claude-review", S, f"findings=2 inline=0 scope=incremental since={S0}"
            ),
        ]
        threads = [thread(resolved=True, resolved_by=MAINTAINER)]
        # (3 - 1) + (2 - 0); the one inline thread a human resolved is closed.
        self.assertEqual(
            self.bind(runs, threads=threads)["claude-review"].open_findings, 4
        )

    def test_findings_below_inline_is_count_inconsistent(self) -> None:
        runs = [whole("claude-review", S, n=1, k=2)]
        result = self.bind(runs, threads=[thread(), thread()])
        self.assertUnbound(result["claude-review"], "count-inconsistent")

    def test_an_earlier_inconsistent_run_also_unbinds(self) -> None:
        runs = [
            run("claude-review", S0, "findings=0 inline=1 scope=whole"),
            whole("claude-review", S),
        ]
        result = self.bind(runs, threads=[thread()])
        self.assertUnbound(result["claude-review"], "count-inconsistent")

    def test_open_inline_thread_counts(self) -> None:
        result = self.bind([whole("claude-review", S, n=1, k=1)], threads=[thread()])
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_thread_resolved_by_a_bot_counts_as_open(self) -> None:
        bot = {"__typename": "Bot", "login": "some-app"}
        threads = [thread(resolved=True, resolved_by=bot)]
        result = self.bind([whole("claude-review", S, n=1, k=1)], threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_thread_resolved_by_unknown_counts_as_open(self) -> None:
        threads = [thread(resolved=True, resolved_by=None)]
        result = self.bind([whole("claude-review", S, n=1, k=1)], threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_thread_resolved_by_a_human_is_closed(self) -> None:
        threads = [thread(resolved=True, resolved_by=MAINTAINER)]
        result = self.bind([whole("claude-review", S, n=1, k=1)], threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 0)

    def test_thread_by_another_author_is_not_a_lane_finding(self) -> None:
        threads = [thread(author={"__typename": "User", "login": "maintainer"})]
        result = self.bind([whole("claude-review", S)], threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 0)

    def test_thread_tagged_for_the_other_lane(self) -> None:
        runs = [whole("claude-review", S), whole("claude-security-review", S, n=1, k=1)]
        threads = [thread("finding\n\n`claude-lane: claude-security-review`")]
        result = self.bind(runs, threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 0)
        self.assertEqual(result["claude-security-review"].open_findings, 1)

    def test_untagged_thread_counts_for_both_lanes(self) -> None:
        runs = [whole(lane, S) for lane in LANES]
        result = self.bind(runs, threads=[thread()])
        self.assertEqual(result["claude-review"].open_findings, 1)
        self.assertEqual(result["claude-security-review"].open_findings, 1)

    def test_fewer_threads_than_inline_count_the_gap_as_open(self) -> None:
        threads = [thread(resolved=True, resolved_by=MAINTAINER)]
        result = self.bind([whole("claude-review", S, n=3, k=3)], threads=threads)
        # Two of the three inline findings have no thread left to read.
        self.assertEqual(result["claude-review"].open_findings, 2)

    def test_thread_outside_every_lane_job_does_not_cover_a_missing_one(
        self,
    ) -> None:
        # A human-resolved Claude thread from an unrecorded review, while the
        # recorded inline finding's thread is gone.
        stray = thread(
            resolved=True, resolved_by=MAINTAINER, created="2025-12-31T00:00:00Z"
        )
        result = self.bind([whole("claude-review", S, n=1, k=1)], threads=[stray])
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_job_without_a_time_window_matches_no_thread(self) -> None:
        item = whole("claude-review", S, n=1, k=1)
        del item["attempts"][0]["jobs"][0]["started_at"]
        threads = [thread(resolved=True, resolved_by=MAINTAINER)]
        result = self.bind([item], threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_one_thread_covers_one_finding_only(self) -> None:
        runs = [
            run("claude-review", S0, "findings=1 inline=1 scope=whole"),
            run(
                "claude-review", S, f"findings=1 inline=1 scope=incremental since={S0}"
            ),
        ]
        threads = [thread(resolved=True, resolved_by=MAINTAINER)]
        result = self.bind(runs, threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_untagged_thread_covers_a_finding_in_one_lane_only(self) -> None:
        # Both lanes' jobs overlap; one human-resolved untagged thread lies in
        # both windows, and each lane recorded one inline finding.
        runs = [whole(lane, S, n=1, k=1) for lane in LANES]
        threads = [thread(resolved=True, resolved_by=MAINTAINER)]
        result = self.bind(runs, threads=threads)
        self.assertEqual(
            sum(result[lane].open_findings for lane in LANES),
            1,
        )

    def test_doubtful_untagged_thread_leaves_the_count_on_security(self) -> None:
        # The security lane's thread is gone; claude-review's untagged thread
        # lies in both windows and a human resolved it.
        runs = [whole(lane, S, n=1, k=1) for lane in LANES]
        threads = [thread(resolved=True, resolved_by=MAINTAINER)]
        result = self.bind(runs, threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 0)
        self.assertEqual(result["claude-security-review"].open_findings, 1)

    def test_lane_with_no_inline_finding_claims_no_thread(self) -> None:
        runs = [
            whole("claude-review", S, n=1, k=0),
            whole("claude-security-review", S, n=1, k=1),
        ]
        threads = [thread(resolved=True, resolved_by=MAINTAINER)]
        result = self.bind(runs, threads=threads)
        self.assertEqual(result["claude-security-review"].open_findings, 0)

    def rounds(self) -> list[dict[str, Any]]:
        # #7520's shape: one inline finding at S1 and at S0, each fixed by
        # the next push; the latest review, at S, raised nothing.
        runs = [
            run("claude-review", S1, "findings=1 inline=1 scope=whole"),
            run(
                "claude-review", S0, f"findings=1 inline=1 scope=incremental since={S1}"
            ),
            run(
                "claude-review", S, f"findings=0 inline=0 scope=incremental since={S0}"
            ),
        ]
        for hour, item in enumerate(runs):
            job = item["attempts"][0]["jobs"][0]
            job["started_at"] = f"2026-01-01T0{2 * hour}:00:00Z"
            job["completed_at"] = f"2026-01-01T0{2 * hour + 1}:00:00Z"
        return runs

    def test_earlier_rounds_resolved_by_the_pusher_are_closed(self) -> None:
        pusher = {"__typename": "User", "login": "pusher"}
        threads = [
            thread(resolved=True, resolved_by=pusher, created=at, outdated=True)
            for at in ("2026-01-01T00:30:00Z", "2026-01-01T02:30:00Z")
        ]
        result = self.bind(self.rounds(), threads=threads)
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 0)

    def outdated_pusher_resolved(
        self, head_file: Any, hunk: Any = HUNK, lines: Any = (None, 2)
    ) -> int:
        pusher = {"__typename": "User", "login": "pusher"}
        threads = [
            thread(
                resolved=True,
                resolved_by=pusher,
                created=at,
                outdated=True,
                hunk=hunk,
                lines=lines,
            )
            for at in ("2026-01-01T00:30:00Z", "2026-01-01T02:30:00Z")
        ]
        result = self.bind(self.rounds(), threads=threads, head_file=head_file)
        return result["claude-review"].open_findings

    def test_insert_above_the_unchanged_line_keeps_the_human_test(self) -> None:
        # GitHub marks the thread outdated, but the flagged line ships as is.
        shifted = "context\n# unrelated\nrun(user_input)\n"
        self.assertEqual(self.outdated_pusher_resolved(lambda p, o: shifted), 2)

    def test_changed_line_is_closed(self) -> None:
        self.assertEqual(self.outdated_pusher_resolved(fixed_head), 0)

    def test_deleted_file_is_closed(self) -> None:
        self.assertEqual(self.outdated_pusher_resolved(lambda p, o: None), 0)

    def test_unreadable_file_or_hunk_keeps_the_human_test(self) -> None:
        def unreadable(path: str, original: str) -> str | None:
            raise RuntimeError("head-file-unread")

        cases = (
            ("file", unreadable, HUNK),
            ("no reader", None, HUNK),
            ("no hunk", fixed_head, None),
            ("empty hunk", fixed_head, ""),
            ("left side", fixed_head, "@@ -1,2 +1,1 @@\n context\n-run(user_input)"),
        )
        for name, head_file, hunk in cases:
            with self.subTest(name):
                self.assertEqual(self.outdated_pusher_resolved(head_file, hunk), 2)

    def test_blank_flagged_line_keeps_the_human_test(self) -> None:
        hunk = "@@ -1,2 +1,2 @@\n context\n+   \t"
        self.assertEqual(self.outdated_pusher_resolved(fixed_head, hunk), 2)

    RANGE = "@@ -1,2 +1,4 @@\n context\n+query(user_input)\n-old()\n+return rows"

    def test_range_with_only_its_boundary_line_edited_stays_open(self) -> None:
        head = "context\nquery(user_input)\nreturn rows()\n"
        self.assertEqual(
            self.outdated_pusher_resolved(lambda p, o: head, self.RANGE, (2, 3)), 2
        )

    def test_range_with_every_line_changed_is_closed(self) -> None:
        head = "context\nquery(clean(user_input))\nreturn rows()\n"
        self.assertEqual(
            self.outdated_pusher_resolved(lambda p, o: head, self.RANGE, (2, 3)), 0
        )

    def test_range_the_hunk_does_not_end_on_stays_open(self) -> None:
        head = "context\nquery(clean(user_input))\nreturn rows()\n"
        for name, lines in (
            ("end mismatch", (2, 4)),
            ("start before hunk", (0, 3)),
            ("no line", (None, None)),
        ):
            with self.subTest(name):
                self.assertEqual(
                    self.outdated_pusher_resolved(lambda p, o: head, self.RANGE, lines),
                    2,
                )

    def test_earlier_round_with_unchanged_lines_still_needs_a_human(self) -> None:
        # An unrelated push re-reviewed incrementally never re-read the line.
        pusher = {"__typename": "User", "login": "pusher"}
        threads = [
            thread(resolved=True, resolved_by=pusher, created=at)
            for at in ("2026-01-01T00:30:00Z", "2026-01-01T02:30:00Z")
        ]
        result = self.bind(self.rounds(), threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 2)

    def test_thread_from_an_earlier_review_of_the_same_head_counts(self) -> None:
        # Two recorded reviews at S: the second did not supersede the first.
        runs = self.rounds()
        runs[-1] = run(
            "claude-review", S, f"findings=1 inline=1 scope=incremental since={S0}"
        )
        again = run(
            "claude-review", S, f"findings=0 inline=0 scope=incremental since={S0}"
        )
        for item, hours in ((runs[-1], ("04", "05")), (again, ("06", "07"))):
            job = item["attempts"][0]["jobs"][0]
            job["started_at"] = f"2026-01-01T{hours[0]}:00:00Z"
            job["completed_at"] = f"2026-01-01T{hours[1]}:00:00Z"
        runs.append(again)
        pusher = {"__typename": "User", "login": "pusher"}
        threads = [
            thread(resolved=True, resolved_by=MAINTAINER, created=at)
            for at in ("2026-01-01T00:30:00Z", "2026-01-01T02:30:00Z")
        ]
        threads.append(
            thread(
                resolved=True,
                resolved_by=pusher,
                created="2026-01-01T04:30:00Z",
                outdated=True,
            )
        )
        result = self.bind(runs, threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_unknown_review_start_keeps_the_human_test(self) -> None:
        runs = self.rounds()
        del runs[-1]["attempts"][0]["jobs"][0]["started_at"]
        pusher = {"__typename": "User", "login": "pusher"}
        threads = [
            thread(
                resolved=True, resolved_by=MAINTAINER, created="2026-01-01T00:30:00Z"
            ),
            thread(
                resolved=True,
                resolved_by=pusher,
                created="2026-01-01T02:30:00Z",
                outdated=True,
            ),
        ]
        result = self.bind(runs, threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_earlier_round_still_unresolved_counts(self) -> None:
        threads = [thread(created="2026-01-01T00:30:00Z")]
        threads.append(
            thread(
                resolved=True, resolved_by=MAINTAINER, created="2026-01-01T02:30:00Z"
            )
        )
        result = self.bind(self.rounds(), threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_latest_round_resolved_by_the_pusher_counts(self) -> None:
        runs = self.rounds()
        runs[-1] = run(
            "claude-review", S, f"findings=1 inline=1 scope=incremental since={S0}"
        )
        job = runs[-1]["attempts"][0]["jobs"][0]
        job["started_at"], job["completed_at"] = (
            "2026-01-01T04:00:00Z",
            "2026-01-01T05:00:00Z",
        )
        pusher = {"__typename": "User", "login": "pusher"}
        threads = [
            thread(resolved=True, resolved_by=MAINTAINER, created=at)
            for at in ("2026-01-01T00:30:00Z", "2026-01-01T02:30:00Z")
        ]
        threads.append(
            thread(resolved=True, resolved_by=pusher, created="2026-01-01T04:30:00Z")
        )
        result = self.bind(runs, threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_unread_threads_unbind(self) -> None:
        result = self.bind([whole("claude-review", S)], threads=None)
        self.assertUnbound(result["claude-review"], "threads-unread")

    def test_completed_attempt_without_job_data_unbinds(self) -> None:
        earlier = whole("claude-review", S0)
        earlier["attempts"][0]["jobs"] = []
        result = self.bind([earlier, whole("claude-review", S)])
        self.assertUnbound(result["claude-review"], "evidence-missing")

    def test_draft_skipped_run_is_ignored(self) -> None:
        # Recorded shape: a draft-skipped run holds only the caller job.
        skipped = attempt("claude-review", S0, 1, [], conclusion="skipped")
        skipped["jobs"][0]["name"] = "pr-review"
        earlier = run("claude-review", S0, attempts=[skipped])
        result = self.bind([earlier, whole("claude-review", S)])
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 0)


class CoveringReviewTests(Base):
    """A finding is closed when the lane's newest review covering the pinned
    head no longer reports it (owner decision 2026-10-18): the reviewer
    clears findings, not the agent that resolved a thread."""

    PUSHER = {"__typename": "User", "login": "pusher"}

    def two_reviews(
        self, earlier: str, latest: str, *, earlier_sha: str = S0
    ) -> list[dict[str, Any]]:
        # An earlier review in the 00:00-01:00 window, the latest in 02:00-03:00.
        runs = [
            run("claude-review", earlier_sha, earlier, created="2026-01-01T00:00:00Z"),
            run("claude-review", S, latest, created="2026-01-01T02:00:00Z"),
        ]
        job = runs[1]["attempts"][0]["jobs"][0]
        job["started_at"], job["completed_at"] = (
            "2026-01-01T02:00:00Z",
            "2026-01-01T03:00:00Z",
        )
        return runs

    def agent_resolved(self) -> list[dict[str, Any]]:
        return [thread(resolved=True, resolved_by=self.PUSHER)]

    # (1) Summary findings come only from the chain covering the head.

    def test_summary_findings_of_a_superseded_whole_review_drop(self) -> None:
        runs = self.two_reviews(
            "findings=3 inline=0 scope=whole", "findings=0 inline=0 scope=whole"
        )
        self.assertEqual(self.bind(runs)["claude-review"].open_findings, 0)

    def test_threadless_inline_finding_of_a_superseded_review_drops(self) -> None:
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole", "findings=0 inline=0 scope=whole"
        )
        self.assertEqual(self.bind(runs, threads=[])["claude-review"].open_findings, 0)

    def test_threadless_inline_finding_of_the_covering_review_counts(self) -> None:
        runs = self.two_reviews(
            "findings=0 inline=0 scope=whole", "findings=1 inline=1 scope=whole"
        )
        self.assertEqual(self.bind(runs, threads=[])["claude-review"].open_findings, 1)

    def test_threadless_inline_finding_of_an_earlier_chain_link_counts(
        self,
    ) -> None:
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole",
            f"findings=0 inline=0 scope=incremental since={S0}",
        )
        self.assertEqual(self.bind(runs, threads=[])["claude-review"].open_findings, 1)

    def test_threadless_inline_finding_of_the_other_kind_at_the_head_drops(
        self,
    ) -> None:
        # At S: a whole review left a thread-less inline finding, then the
        # newest run, an incremental review back to the whole one at S0.
        runs = [
            whole("claude-review", S0),
            run(
                "claude-review",
                S,
                "findings=1 inline=1 scope=whole",
                created="2026-01-01T01:00:00Z",
            ),
            run(
                "claude-review",
                S,
                f"findings=0 inline=0 scope=incremental since={S0}",
                created="2026-01-01T02:00:00Z",
            ),
        ]
        self.assertEqual(self.bind(runs, threads=[])["claude-review"].open_findings, 0)

    def test_threadless_inline_finding_of_a_same_head_whole_rerun_counts(
        self,
    ) -> None:
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole",
            "findings=0 inline=0 scope=whole",
            earlier_sha=S,
        )
        self.assertEqual(self.bind(runs, threads=[])["claude-review"].open_findings, 1)

    def test_a_clean_whole_rerun_at_the_same_head_keeps_the_earlier_findings(
        self,
    ) -> None:
        # A reopen or draft toggle re-runs a whole review of the same head;
        # only a review of a later head supersedes one.
        runs = self.two_reviews(
            "findings=2 inline=0 scope=whole",
            "findings=0 inline=0 scope=whole",
            earlier_sha=S,
        )
        self.assertEqual(self.bind(runs)["claude-review"].open_findings, 2)

    def test_a_clean_whole_rerun_at_the_same_head_does_not_clear_a_thread(
        self,
    ) -> None:
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole",
            "findings=0 inline=0 scope=whole",
            earlier_sha=S,
        )
        result = self.bind(runs, threads=self.agent_resolved())
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_summary_findings_the_covering_review_reports_still_count(
        self,
    ) -> None:
        runs = self.two_reviews(
            "findings=3 inline=0 scope=whole", "findings=1 inline=0 scope=whole"
        )
        self.assertEqual(self.bind(runs)["claude-review"].open_findings, 1)

    # (2) An agent-resolved thread closes only on a clean covering review.

    def test_agent_resolved_thread_closes_when_the_covering_review_is_clean(
        self,
    ) -> None:
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole", "findings=0 inline=0 scope=whole"
        )
        result = self.bind(runs, threads=self.agent_resolved())
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 0)

    def test_agent_resolved_thread_stays_open_when_the_covering_review_reports_one(
        self,
    ) -> None:
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole", "findings=1 inline=0 scope=whole"
        )
        result = self.bind(runs, threads=self.agent_resolved())
        # The covering review's summary finding plus the agent-resolved thread.
        self.assertEqual(result["claude-review"].open_findings, 2)

    def test_clean_incremental_leaves_an_unchanged_agent_resolved_thread_open(
        self,
    ) -> None:
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole",
            f"findings=0 inline=0 scope=incremental since={S0}",
        )
        result = self.bind(runs, threads=self.agent_resolved())
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_clean_incremental_closes_an_outdated_thread_whose_lines_changed(
        self,
    ) -> None:
        # The kept outdated-thread path: the later review read the changed lines.
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole",
            f"findings=0 inline=0 scope=incremental since={S0}",
        )
        threads = [thread(resolved=True, resolved_by=self.PUSHER, outdated=True)]
        result = self.bind(runs, threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 0)

    def test_thread_opened_after_the_clean_review_completed_stays_open(
        self,
    ) -> None:
        runs = self.two_reviews(
            "findings=0 inline=0 scope=whole", "findings=0 inline=0 scope=whole"
        )
        threads = [
            thread(
                resolved=True, resolved_by=self.PUSHER, created="2026-01-01T03:30:00Z"
            )
        ]
        result = self.bind(runs, threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_both_lanes_with_an_untagged_thread_and_one_lane_clean(self) -> None:
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole", "findings=0 inline=0 scope=whole"
        )
        runs.append(run("claude-security-review", S, "findings=1 inline=0 scope=whole"))
        result = self.bind(runs, threads=self.agent_resolved())
        for lane in LANES:
            self.assertTrue(result[lane].bound, lane)
        self.assertEqual(result["claude-review"].open_findings, 0)
        # Security's own summary finding, and it never cleared the thread.
        self.assertEqual(result["claude-security-review"].open_findings, 2)

    def test_no_change_skip_at_the_head_over_a_clean_review_clears(self) -> None:
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole",
            "findings=0 inline=0 scope=whole",
        )
        runs[1]["head_sha"] = S1
        for item in runs[1]["attempts"]:
            item["head_sha"] = S1
            for job in item["jobs"]:
                job["head_sha"] = S1
                job["annotations"] = [
                    record("claude-review", S1, "findings=0 inline=0 scope=whole")
                ]
        runs.append(
            run(
                "claude-review",
                S,
                f"skip=no-change through={S1}",
                created="2026-01-01T04:00:00Z",
            )
        )
        result = self.bind(runs, threads=self.agent_resolved())
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 0)

    def test_covering_reviews_own_thread_stays_open(self) -> None:
        runs = self.two_reviews(
            "findings=0 inline=0 scope=whole", "findings=1 inline=1 scope=whole"
        )
        threads = [
            thread(
                resolved=True,
                resolved_by=self.PUSHER,
                created="2026-01-01T02:30:00Z",
                outdated=True,
            )
        ]
        result = self.bind(runs, threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 1)

    # (3) Unchanged behavior.

    def test_human_resolved_thread_stays_closed(self) -> None:
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole", "findings=1 inline=0 scope=whole"
        )
        threads = [thread(resolved=True, resolved_by=MAINTAINER)]
        self.assertEqual(
            self.bind(runs, threads=threads)["claude-review"].open_findings, 1
        )

    def test_unresolved_thread_stays_open_under_a_clean_covering_review(
        self,
    ) -> None:
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole", "findings=0 inline=0 scope=whole"
        )
        self.assertEqual(
            self.bind(runs, threads=[thread()])["claude-review"].open_findings, 1
        )

    def test_no_review_covering_the_head_is_not_closed(self) -> None:
        clean_earlier = whole("claude-review", S0)
        failed = run(
            "claude-review",
            S,
            attempts=[attempt("claude-review", S, 1, [OTHER_FAILURE], "failure")],
        )
        for runs in ([clean_earlier], [clean_earlier, failed]):
            with self.subTest(len(runs)):
                result = self.bind(runs, threads=self.agent_resolved())
                self.assertFalse(result["claude-review"].bound)
                self.assertIsNone(result["claude-review"].open_findings)

    def test_resolving_alone_never_closes(self) -> None:
        runs = [whole("claude-review", S, n=1, k=1)]
        self.assertEqual(
            self.bind(runs, threads=self.agent_resolved())[
                "claude-review"
            ].open_findings,
            1,
        )

    def test_clean_review_of_another_head_does_not_clear(self) -> None:
        # A newer clean review of an earlier head does not cover the pinned one.
        runs = [
            run("claude-review", S, "findings=1 inline=1 scope=whole"),
            run(
                "claude-review",
                S0,
                "findings=0 inline=0 scope=whole",
                created="2026-01-02T00:00:00Z",
            ),
        ]
        result = self.bind(runs, threads=self.agent_resolved())
        self.assertEqual(result["claude-review"].open_findings, 1)


def windowed(item: dict[str, Any], start: str, end: str) -> dict[str, Any]:
    job = item["attempts"][0]["jobs"][0]
    job["started_at"], job["completed_at"] = start, end
    return item


class CleanWholeReviewTests(Base):
    """A clean whole review of the pinned head closes a resolved thread
    whoever resolved it; a security-lane (HIGH) thread needs the security
    lane's own clean whole review. An incremental review reads only what
    changed, so it never closes an unchanged thread (owner decision
    2026-10-19, narrowed to whole reviews)."""

    LANES_BOT = {"__typename": "Bot", "login": "melodic-lanes"}
    SECURITY = "finding\n\n`claude-lane: claude-security-review`"
    CLEAN_WHOLE = "findings=0 inline=0 scope=whole"
    CLEAN_INCREMENTAL = f"findings=0 inline=0 scope=incremental since={S0}"

    def chain(self, lane: str, head_tail: str, raised: int = 1) -> list[dict[str, Any]]:
        # A whole review at S0 (00:00-01:00) raised `raised` inline findings;
        # the review at the pinned head S ran 02:00-03:00.
        return [
            run(lane, S0, f"findings={raised} inline={raised} scope=whole"),
            windowed(
                run(lane, S, head_tail, created="2026-01-01T02:00:00Z"),
                "2026-01-01T02:00:00Z",
                "2026-01-01T03:00:00Z",
            ),
        ]

    def security_thread(self) -> list[dict[str, Any]]:
        return [thread(self.SECURITY, resolved=True, resolved_by=self.LANES_BOT)]

    def test_resolved_security_thread_stays_open_after_a_clean_incremental(
        self,
    ) -> None:
        # The lane resolved an unfixed HIGH thread and an unrelated push was
        # reviewed incrementally: that review never re-read the flagged line.
        runs = [
            *self.chain("claude-review", self.CLEAN_INCREMENTAL, raised=0),
            *self.chain("claude-security-review", self.CLEAN_INCREMENTAL),
        ]
        result = self.bind(runs, threads=self.security_thread())
        self.assertEqual(result["claude-review"].open_findings, 0)
        self.assertEqual(result["claude-security-review"].open_findings, 1)

    def test_resolved_security_thread_closes_on_a_clean_whole_review(
        self,
    ) -> None:
        runs = [
            *self.chain("claude-review", self.CLEAN_WHOLE, raised=0),
            *self.chain("claude-security-review", self.CLEAN_WHOLE),
        ]
        result = self.bind(runs, threads=self.security_thread())
        for lane in LANES:
            self.assertTrue(result[lane].bound, lane)
            self.assertEqual(result[lane].open_findings, 0, lane)

    def test_security_thread_needs_the_security_lane_clean(self) -> None:
        runs = [
            *self.chain("claude-review", self.CLEAN_WHOLE, raised=0),
            *self.chain("claude-security-review", "findings=1 inline=0 scope=whole"),
        ]
        result = self.bind(runs, threads=self.security_thread())
        self.assertEqual(result["claude-review"].open_findings, 0)
        # The security head review's summary finding plus the thread.
        self.assertEqual(result["claude-security-review"].open_findings, 2)

    def test_clean_whole_review_of_an_older_head_does_not_close(self) -> None:
        runs = [
            windowed(
                run("claude-review", S, "findings=1 inline=1 scope=whole"),
                "2026-01-01T00:00:00Z",
                "2026-01-01T01:00:00Z",
            ),
            windowed(
                run(
                    "claude-review",
                    S0,
                    self.CLEAN_WHOLE,
                    created="2026-01-01T02:00:00Z",
                ),
                "2026-01-01T02:00:00Z",
                "2026-01-01T03:00:00Z",
            ),
        ]
        threads = [thread(resolved=True, resolved_by=self.LANES_BOT)]
        result = self.bind(runs, threads=threads)
        self.assertEqual(result["claude-review"].open_findings, 1)


class WholeReviewClearsTests(Base):
    """`whole_review_clears`: the lane's open findings are all ones a clean
    whole review of the head would close, and no review of the head has
    reported a finding or been a whole one."""

    SECURITY = CleanWholeReviewTests.SECURITY
    CLEAN_INCREMENTAL = CleanWholeReviewTests.CLEAN_INCREMENTAL
    LANES_BOT = CleanWholeReviewTests.LANES_BOT
    chain = CleanWholeReviewTests.chain
    security_thread = CleanWholeReviewTests.security_thread

    def test_older_resolved_thread_under_a_clean_incremental_clears(self) -> None:
        runs = [
            *self.chain("claude-review", self.CLEAN_INCREMENTAL, raised=0),
            *self.chain("claude-security-review", self.CLEAN_INCREMENTAL),
        ]
        result = self.bind(runs, threads=self.security_thread())
        self.assertTrue(result["claude-security-review"].whole_review_clears)
        # Nothing open: nothing to clear.
        self.assertFalse(result["claude-review"].whole_review_clears)

    def test_older_summary_finding_under_a_clean_incremental_clears(self) -> None:
        runs = [
            run("claude-review", S0, "findings=1 inline=0 scope=whole"),
            run("claude-review", S, self.CLEAN_INCREMENTAL),
        ]
        result = self.bind(runs)
        self.assertEqual(result["claude-review"].open_findings, 1)
        self.assertTrue(result["claude-review"].whole_review_clears)

    def test_a_finding_reported_at_the_current_head_does_not_clear(self) -> None:
        runs = [
            run("claude-review", S0, "findings=1 inline=0 scope=whole"),
            run(
                "claude-review", S, f"findings=1 inline=0 scope=incremental since={S0}"
            ),
        ]
        result = self.bind(runs)
        self.assertEqual(result["claude-review"].open_findings, 2)
        self.assertFalse(result["claude-review"].whole_review_clears)

    def test_a_whole_review_already_at_the_head_does_not_clear(self) -> None:
        runs = [
            *self.chain("claude-review", self.CLEAN_INCREMENTAL, raised=0),
            *self.chain("claude-security-review", "findings=1 inline=0 scope=whole"),
        ]
        result = self.bind(runs, threads=self.security_thread())
        self.assertFalse(result["claude-security-review"].whole_review_clears)

    def test_an_unresolved_thread_does_not_clear(self) -> None:
        runs = [
            *self.chain("claude-review", self.CLEAN_INCREMENTAL, raised=0),
            *self.chain("claude-security-review", self.CLEAN_INCREMENTAL),
        ]
        threads = [thread(self.SECURITY)]
        result = self.bind(runs, threads=threads)
        self.assertEqual(result["claude-security-review"].open_findings, 1)
        self.assertFalse(result["claude-security-review"].whole_review_clears)

    def test_unbound_never_clears(self) -> None:
        result = self.bind([])
        self.assertFalse(result["claude-review"].whole_review_clears)


class FailClosedTests(Base):
    def test_garbage_input_never_raises(self) -> None:
        for runs in (None, [None], [{"attempts": "x"}], "runs", [{"id": 1}]):
            result = ev.bind(
                S, runs, [None], [None], is_human=is_human, changed_paths=()
            )  # type: ignore[arg-type]
            self.assertEqual(len(result), 2)
            for item in result:
                self.assertFalse(item.bound)
                self.assertIsNotNone(item.unbound_reason)
                self.assertIsNone(item.open_findings)

    def test_evidence_is_the_scorers_lane_evidence(self) -> None:
        import babysit_risk

        result = ev.bind(
            S,
            [whole(lane, S) for lane in LANES],
            both_markers(),
            [],
            is_human=is_human,
            changed_paths=(),
        )
        self.assertTrue(all(isinstance(r, babysit_risk.LaneEvidence) for r in result))

    def test_pinned_head_must_be_a_full_sha(self) -> None:
        result = ev.bind(
            "5e1f",
            [whole("claude-review", S)],
            both_markers(),
            [],
            is_human=is_human,
            changed_paths=(),
        )
        for item in result:
            self.assertFalse(item.bound)

    def test_raising_human_test_fails_closed(self) -> None:
        def boom(actor: Any) -> bool:
            raise RuntimeError("no permission read")

        threads = [thread(resolved=True, resolved_by=MAINTAINER)]
        result = ev.bind(
            S,
            [whole("claude-review", S, n=1, k=1)],
            both_markers(),
            threads,
            is_human=boom,
            changed_paths=(),
        )
        self.assertFalse(result[0].bound)


if __name__ == "__main__":
    unittest.main()

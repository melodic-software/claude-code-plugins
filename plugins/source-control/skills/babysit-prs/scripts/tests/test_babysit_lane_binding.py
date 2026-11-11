"""Whether a github-actions[bot] lane comment is its lane's own: the binding
line, the run's comment records and the legacy rule (lib/lane-binding.mjs,
whose cases these port)."""

from __future__ import annotations

import io
import json
import pathlib
import re
import sys
import unittest
import zipfile
from collections.abc import Mapping
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_lane_binding as lb

HEAD = "a" * 40
RUN = 4242
WORKFLOWS = {
    "claude-review": ".github/workflows/pr-review-hosted.yml",
    "claude-security-review": ".github/workflows/pr-review-security-hosted.yml",
}


BRANCH = "feature/x"
# The cutoff the JavaScript port holds: both ports must name the same one.
JS_CUTOFF = re.search(
    r'^export const LEGACY_CUTOFF = (?:null|"([^"]+)");$',
    (pathlib.Path(__file__).resolve().parents[6] / ".github/scripts/lib/lane-binding.mjs").read_text(encoding="utf-8"),
    re.M,
)[1]
REPOSITORY = "o/r"

def bound(text: str, *, run: int = RUN, sha: str = HEAD, lane: str = "claude-review") -> str:
    """A body as the lane posts it: text, the binding, a blank line, the footer."""
    return f"{text}\n<!-- claude-lane-run id={run} sha={sha} -->\n\nclaude-lane: {lane}"


def record_entry(body: str, **overrides: Any) -> dict[str, Any]:
    return {
        "lane": "claude-review",
        "pr": 7,
        "head": HEAD,
        "kind": "review_comment",
        "id": 11,
        "sha256": lb.body_digest(body),
        **overrides,
    }


def zip_of(files: Mapping[str, str]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, text in files.items():
            archive.writestr(name, text)
    return buffer.getvalue()


def lane_run(entries: list[dict[str, Any]], *, lane: str = "claude-review", attempt: int = 1, **rest: Any) -> dict[str, Any]:
    return {
        "path": WORKFLOWS[lane],
        "artifacts": [{"name": f"{lb.RECORD_PREFIX}{lane}-{attempt}", "entries": entries}],
        **rest,
    }


class FakeActions:
    """Runs by id, each with artifacts {name, expired, entries}; records calls."""

    def __init__(self, runs: Mapping[int, Mapping[str, Any]]) -> None:
        self.runs = runs
        self.calls: list[tuple[str, int]] = []
        self.blobs: dict[int, bytes] = {}
        next_id = 1
        for run in runs.values():
            for artifact in run.get("artifacts", []):
                artifact["id"] = next_id
                next_id += 1
                closed = [] if artifact.get("complete") is False else [{"complete": True}]
                text = "\n".join(json.dumps(e) for e in [*artifact["entries"], *closed])
                self.blobs[artifact["id"]] = zip_of({lb.RECORD_FILE: text})

    def get_pull(self, pr: int | None) -> dict[str, Any]:
        self.calls.append(("pull", 0))
        return {"head": {"ref": BRANCH, "repo": {"full_name": REPOSITORY}}}

    def get_run(self, run_id: str) -> dict[str, Any]:
        self.calls.append(("run", int(run_id)))
        run = self.runs.get(int(run_id))
        if run is None:
            raise RuntimeError("Not Found (HTTP 404)")
        return {
            "id": int(run_id),
            "path": run["path"],
            "head_sha": run.get("head_sha", HEAD),
            "head_branch": run.get("head_branch", BRANCH),
            "head_repository": {"full_name": run.get("head_repository", REPOSITORY)},
            "status": run.get("status", "completed"),
            "run_attempt": run.get("run_attempt", 1),
            "created_at": run.get("created_at"),
            "updated_at": run.get("updated_at"),
        }

    def list_artifacts(self, run_id: str) -> list[dict[str, Any]]:
        self.calls.append(("artifacts", int(run_id)))
        return [
            {"id": a["id"], "name": a["name"], "expired": a.get("expired") is True}
            for a in self.runs.get(int(run_id), {}).get("artifacts", [])
        ]

    def download(self, artifact_id: int) -> bytes:
        self.calls.append(("download", artifact_id))
        return self.blobs[artifact_id]

    def checker(self, pr: int = 7) -> Any:
        return lb.lane_checker(
            pr=pr,
            get_pull=self.get_pull,
            get_run=self.get_run,
            list_artifacts=self.list_artifacts,
            download=self.download,
            workflows=WORKFLOWS,
        )


def comment(body: str, **overrides: Any) -> dict[str, Any]:
    return {
        "kind": "review_comment",
        "id": 11,
        "body": body,
        "createdAt": "2026-11-01T00:00:00Z",
        **overrides,
    }


class ParsingTests(unittest.TestCase):
    def test_binding_is_read_only_on_the_last_non_blank_line_above_the_footer(self) -> None:
        self.assertEqual(lb.binding_of(bound("x")), (str(RUN), HEAD))
        self.assertEqual(lb.binding_of(bound("x").replace("\n", "\r\n")), (str(RUN), HEAD))
        self.assertIsNone(lb.binding_of(f"<!-- claude-lane-run id={RUN} sha={HEAD} -->\nx\n\nclaude-lane: claude-review"))
        self.assertIsNone(lb.binding_of(f"x\n<!-- claude-lane-run id={RUN} sha={HEAD} -->"))
        self.assertIsNone(lb.binding_of(f"x\n<!-- claude-lane-run id=0 sha={HEAD} -->\n\nclaude-lane: claude-review"))
        self.assertIsNone(lb.binding_of(f"x\n<!-- claude-lane-run id={RUN} sha={HEAD} -->\n\nclaude-lane: other"))

    def test_without_binding_drops_only_the_binding_line(self) -> None:
        self.assertEqual(lb.without_binding(bound("x")), "x\n\nclaude-lane: claude-review")
        self.assertEqual(lb.without_binding("x\n\nclaude-lane: claude-review"), "x\n\nclaude-lane: claude-review")
        crlf = bound("x").replace("\n", "\r\n")
        self.assertEqual(lb.without_binding(crlf), "x\r\n\r\nclaude-lane: claude-review")

    def test_lane_footer_reads_the_two_lanes_only(self) -> None:
        self.assertEqual(lb.lane_footer("x\n\n`claude-lane: claude-security-review`\n"), "claude-security-review")
        self.assertIsNone(lb.lane_footer("x\n\nclaude-lane: claude-other"))
        self.assertIsNone(lb.lane_footer("claude-lane: claude-review\nx"))
        self.assertIsNone(lb.lane_footer(None))

    def test_an_edit_is_last_edited_at_when_present_else_updated_at_past_a_minute(self) -> None:
        at = "2026-11-01T00:00:00Z"
        self.assertTrue(lb.was_edited({"createdAt": at, "updatedAt": at, "lastEditedAt": "2026-11-01T00:00:01Z"}))
        self.assertFalse(lb.was_edited({"createdAt": at, "updatedAt": "2026-11-02T00:00:00Z", "lastEditedAt": None}))
        self.assertFalse(lb.was_edited({"createdAt": at, "updatedAt": "2026-11-01T00:01:00Z"}))
        self.assertTrue(lb.was_edited({"createdAt": at, "updatedAt": "2026-11-01T00:01:01Z"}))
        self.assertFalse(lb.was_edited({"createdAt": at}))

    def test_an_unbound_comment_counts_with_no_cutoff_then_only_by_it_and_unedited(self) -> None:
        self.assertEqual(lb.LEGACY_CUTOFF, JS_CUTOFF)
        old = {"createdAt": "2026-10-01T00:00:00Z"}
        self.assertTrue(lb.legacy_counts(old))
        self.assertTrue(lb.legacy_counts({"createdAt": "2027-01-01T00:00:00Z"}, None))
        self.assertTrue(lb.legacy_counts(old, "2026-10-02T00:00:00Z"))
        self.assertFalse(lb.legacy_counts({"createdAt": "2026-10-03T00:00:00Z"}, "2026-10-02T00:00:00Z"))
        self.assertFalse(lb.legacy_counts({**old, "lastEditedAt": "2026-10-01T00:00:00Z"}, "2026-10-02T00:00:00Z"))
        self.assertFalse(lb.legacy_counts({}, "2026-10-02T00:00:00Z"))

    def test_zip_entry_reads_a_deflated_file_and_answers_none_for_an_absent_one(self) -> None:
        archive = zip_of({"comments.jsonl": "{}\n", "other": "y"})
        self.assertEqual(lb.zip_entry(archive, "comments.jsonl"), b"{}\n")
        self.assertIsNone(lb.zip_entry(archive, "missing"))
        with self.assertRaises(ValueError):
            lb.zip_entry(b"not a zip", "comments.jsonl")

    def test_record_entries_skip_lines_that_are_not_objects(self) -> None:
        self.assertEqual(lb.record_entries('{"a":1}\n[1]\nnope\n2\n\n{"b":2}'), [{"a": 1}, {"b": 2}])
        self.assertEqual(lb.record_entries(None), [])

    def test_views_of_an_issue_comment_and_a_thread_comment(self) -> None:
        issue = lb.issue_comment_view(
            {"id": 5, "body": "b", "created_at": "c", "updated_at": "u", "edit": {"lastEditedAt": None}}
        )
        self.assertEqual(
            issue,
            {"kind": "issue_comment", "id": 5, "body": "b", "createdAt": "c", "updatedAt": "u", "lastEditedAt": None},
        )
        self.assertNotIn("lastEditedAt", lb.issue_comment_view({"id": 5, "body": "b"}))
        thread = lb.review_comment_view({"databaseId": 6, "body": "b", "createdAt": "c", "updatedAt": "u"})
        self.assertEqual(thread["kind"], "review_comment")
        self.assertEqual(thread["id"], 6)
        self.assertNotIn("lastEditedAt", thread)


class CheckerTests(unittest.TestCase):
    def test_a_bound_comment_counts_only_when_its_runs_record_lists_it(self) -> None:
        body = bound("finding")
        api = FakeActions({RUN: lane_run([record_entry(body)])})
        check = api.checker()
        self.assertTrue(check(comment(body)))
        # Another id, kind, pull request, lane or body digest: not listed.
        self.assertFalse(check(comment(body, id=12)))
        self.assertFalse(check(comment(body, kind="issue_comment")))
        self.assertFalse(api.checker(pr=8)(comment(body)))
        self.assertFalse(check(comment(bound("finding", lane="claude-security-review"))))
        self.assertFalse(check(comment(bound("other"))))
        # One run and one artifacts read per run per checker.
        self.assertEqual(api.calls.count(("run", RUN)), 2)
        self.assertEqual(api.calls.count(("artifacts", RUN)), 2)

    def test_types_must_match_exactly(self) -> None:
        body = bound("finding")
        for overrides in ({"pr": True}, {"pr": "7"}, {"id": "11"}, {"id": 11.5}):
            with self.subTest(overrides=overrides):
                api = FakeActions({RUN: lane_run([record_entry(body, **overrides)])})
                self.assertFalse(api.checker()(comment(body)))

    def test_another_workflows_run_or_another_head_does_not_count(self) -> None:
        body = bound("finding")
        api = FakeActions({RUN: {**lane_run([record_entry(body)]), "path": ".github/workflows/other.yml"}})
        self.assertFalse(api.checker()(comment(body)))
        other = bound("finding", sha="b" * 40)
        api = FakeActions({RUN: lane_run([record_entry(other)])})
        self.assertFalse(api.checker()(comment(other)))
        # The security lane's footer against the code lane's caller.
        sec = bound("finding", lane="claude-security-review")
        api = FakeActions({RUN: lane_run([record_entry(sec, lane="claude-security-review")])})
        self.assertFalse(api.checker()(comment(sec)))

    def test_every_attempts_record_counts(self) -> None:
        first, second = bound("first"), bound("second")
        run = lane_run([record_entry(first)])
        run["artifacts"].append(
            {"name": f"{lb.RECORD_PREFIX}claude-review-2", "entries": [record_entry(second, id=12)]}
        )
        api = FakeActions({RUN: run})
        check = api.checker()
        self.assertTrue(check(comment(first)))
        self.assertTrue(check(comment(second, id=12)))
        self.assertEqual(api.calls.count(("run", RUN)), 1)
        self.assertEqual(api.calls.count(("artifacts", RUN)), 1)
        self.assertEqual(sum(1 for kind, _ in api.calls if kind == "download"), 2)

    def test_an_older_heads_comment_stays_bound_to_the_head_its_run_reviewed(self) -> None:
        older = "c" * 40
        body = bound("finding", sha=older)
        api = FakeActions({RUN: lane_run([record_entry(body, head=older)], head_sha=older)})
        self.assertTrue(api.checker()(comment(body)))

    def test_a_run_on_another_head_does_not_bind_whatever_its_record_says(self) -> None:
        body = bound("forged")
        api = FakeActions({RUN: lane_run([record_entry(body)], head_sha="c" * 40)})
        self.assertFalse(api.checker()(comment(body)))

    def test_an_artifact_that_is_not_a_record_is_not_read(self) -> None:
        body = bound("finding")
        run = lane_run([record_entry(body)])
        run["artifacts"][0]["name"] = "something-else"
        api = FakeActions({RUN: run})
        self.assertFalse(api.checker()(comment(body)))
        self.assertNotIn("download", [kind for kind, _ in api.calls])

    def test_a_run_whose_records_all_expired_proves_its_comments_by_time(self) -> None:
        body = bound("finding")
        run = lane_run([record_entry(body)], created_at="2026-11-01T00:00:00Z", updated_at="2026-11-01T01:00:00Z")
        run["artifacts"][0]["expired"] = True
        api = FakeActions({RUN: run})
        check = api.checker()
        self.assertTrue(check(comment(body, createdAt="2026-11-01T00:30:00Z")))
        self.assertFalse(check(comment(body, createdAt="2026-11-01T01:00:01Z")))
        self.assertFalse(check(comment(body, createdAt="2026-10-31T23:59:59Z")))
        self.assertNotIn("download", [kind for kind, _ in api.calls])

    def test_an_expired_attempts_comment_is_proved_by_time_beside_a_live_record(self) -> None:
        first, second = bound("first"), bound("second")
        run = lane_run([], created_at="2026-11-01T00:00:00Z", updated_at="2026-11-03T00:00:00Z")
        run["artifacts"][0]["expired"] = True
        run["artifacts"].append(
            {"name": f"{lb.RECORD_PREFIX}claude-review-2", "entries": [record_entry(second, id=12)]}
        )
        check = FakeActions({RUN: run}).checker()
        self.assertTrue(check(comment(first, createdAt="2026-11-01T00:30:00Z")))
        self.assertTrue(check(comment(second, id=12)))
        self.assertFalse(check(comment(first, id=13, createdAt="2026-11-04T00:00:00Z")))

    def test_a_finished_run_with_no_record_proves_by_time_and_a_running_one_raises(self) -> None:
        body = bound("finding")
        window = {"created_at": "2026-11-01T00:00:00Z", "updated_at": "2026-11-02T00:00:00Z"}
        check = FakeActions({RUN: {"path": WORKFLOWS["claude-review"], **window}}).checker()
        self.assertTrue(check(comment(body, createdAt="2026-11-01T12:00:00Z")))
        self.assertFalse(check(comment(body, id=12, createdAt="2026-11-03T00:00:00Z")))
        self.assertFalse(check(comment(body, id=13, createdAt="2026-11-01T12:00:00Z", lastEditedAt="2026-11-05T00:00:00Z")))
        running = FakeActions({RUN: {"path": WORKFLOWS["claude-review"], "status": "in_progress", **window}}).checker()
        with self.assertRaisesRegex(RuntimeError, "may not be uploaded yet"):
            running(comment(body))

    def test_a_running_attempts_comment_raises_and_a_lost_attempt_is_proved_by_time(self) -> None:
        first, second = bound("first"), bound("second")
        window = {"created_at": "2026-11-01T00:00:00Z", "updated_at": "2026-11-02T00:00:00Z"}
        running = FakeActions({RUN: lane_run([record_entry(first)], status="in_progress", run_attempt=2, **window)}).checker()
        self.assertTrue(running(comment(first)))
        with self.assertRaisesRegex(RuntimeError, "may not be uploaded yet"):
            running(comment(second, id=12))
        lost = FakeActions({RUN: lane_run([record_entry(first)], run_attempt=2, **window)}).checker()
        self.assertTrue(lost(comment(second, id=12, createdAt="2026-11-01T12:00:00Z")))
        whole = FakeActions({RUN: lane_run([record_entry(first)], **window)}).checker()
        self.assertFalse(whole(comment(second, id=12, createdAt="2026-11-01T12:00:00Z")))

    def test_an_attempt_whose_record_was_cut_off_is_proved_by_time(self) -> None:
        body = bound("posted before the record closed")
        window = {"created_at": "2026-11-01T00:00:00Z", "updated_at": "2026-11-02T00:00:00Z"}
        run = lane_run([], **window)
        run["artifacts"][0]["complete"] = False
        check = FakeActions({RUN: run}).checker()
        self.assertTrue(check(comment(body, createdAt="2026-11-01T12:00:00Z")))
        closed = FakeActions({RUN: lane_run([], **window)}).checker()
        self.assertFalse(closed(comment(body, createdAt="2026-11-01T12:00:00Z")))

    def test_a_run_of_another_branch_or_repository_does_not_bind(self) -> None:
        body = bound("finding")
        self.assertFalse(FakeActions({RUN: lane_run([record_entry(body)], head_branch="other")}).checker()(comment(body)))
        self.assertFalse(FakeActions({RUN: lane_run([record_entry(body)], head_repository="x/r")}).checker()(comment(body)))

    def test_a_record_over_the_size_cap_raises(self) -> None:
        with self.assertRaisesRegex(ValueError, "over"):
            lb.zip_entry(zip_of({lb.RECORD_FILE: "x" * (lb.MAX_RECORD_BYTES + 1)}), lb.RECORD_FILE)

    def test_a_record_without_the_file_lists_nothing(self) -> None:
        body = bound("finding")
        api = FakeActions({RUN: lane_run([record_entry(body)])})
        api.blobs[1] = zip_of({"other.txt": "x"})
        self.assertFalse(api.checker()(comment(body)))

    def test_a_security_comment_binds_against_the_security_caller(self) -> None:
        sec = bound("finding", lane="claude-security-review")
        api = FakeActions({RUN: lane_run([record_entry(sec, lane="claude-security-review")], lane="claude-security-review")})
        self.assertTrue(api.checker()(comment(sec)))

    def test_a_failed_read_raises_every_time_and_is_read_once(self) -> None:
        body = bound("finding", run=999)
        api = FakeActions({})
        check = api.checker()
        for _ in range(2):
            with self.assertRaises(RuntimeError):
                check(comment(body))
        self.assertEqual(api.calls, [("run", 999)])

    def test_a_corrupt_record_raises(self) -> None:
        body = bound("finding")
        api = FakeActions({RUN: lane_run([record_entry(body)])})
        api.blobs[1] = b"not a zip"
        with self.assertRaises(ValueError):
            api.checker()(comment(body))

    def test_unbound_and_unfooted_comments_read_nothing(self) -> None:
        api = FakeActions({})
        check = api.checker()
        self.assertTrue(check(comment("legacy\n\nclaude-lane: claude-review")))
        self.assertFalse(check(comment("no footer")))
        self.assertEqual(api.calls, [])
        cutoff = lb.lane_checker(
            pr=7,
            get_pull=api.get_pull,
            get_run=api.get_run,
            list_artifacts=api.list_artifacts,
            download=api.download,
            workflows=WORKFLOWS,
            cutoff="2026-10-01T00:00:00Z",
        )
        self.assertFalse(cutoff(comment("legacy\n\nclaude-lane: claude-review")))


if __name__ == "__main__":
    unittest.main()

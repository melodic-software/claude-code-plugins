"""The security lane's docs-only skip as review evidence.

Expected values come from the owner's rule (A7: the skip counts only when
every changed path is documentation, never an instruction path), the gaps
Security & Cost found in the first version (a deleted reviewing run, docs/
paths instruction files cite), and the lane producer at ci-workflows
pr-review-security.yml 2fe38c03: the record `... skip=docs-only`, the marker
comment created once and edited in place, its base line, and its status line
`**<lane>** needs no new review of `<head>`: every file in scope matches
docs-only-paths.` with the last summary carried forward on a skip. The
single-run shape matches the security lane's run on a one-file docs pull
request: one lane job window, the marker written inside it.
"""

from __future__ import annotations

import pathlib
import re
import sys
import unittest
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import babysit_review_evidence as ev
from babysit_risk import Risk, holds, score
from test_babysit_review_evidence import (
    MAINTAINER,
    OTHER_FAILURE,
    RATE_LIMIT,
    S,
    S0,
    S1,
    attempt,
    by_lane,
    is_human,
    marker,
    run,
    thread,
    whole,
)
from test_babysit_risk import _file, _input

SEC = "claude-security-review"
DOC = "docs/catalog.md"
ROOT = pathlib.Path(__file__).resolve().parents[6]
BASE_LINE = f"<!-- claude-lane-reviewed-base ref=main merge-base={S1} -->"


def status(sha: str = S) -> str:
    return (
        f"**{SEC}** needs no new review of `{sha}`: "
        "every file in scope matches docs-only-paths."
    )


def skip_run(
    sha: str, start: str, end: str, tail: str = "skip=docs-only"
) -> dict[str, Any]:
    """One security run at `sha` whose lane job ran from `start` to `end`."""
    item = run(SEC, sha, tail)
    job = item["attempts"][0]["jobs"][0]
    job["started_at"], job["completed_at"] = start, end
    return item


def doc_marker(
    sha: str = S,
    created: str | None = "2026-02-01T00:10:20Z",
    updated: str | None = "2026-02-01T00:10:20Z",
    summary: str = "",
) -> dict[str, Any]:
    body = [f"<!-- claude-lane-reviewed-head lane={SEC} sha={sha} -->", BASE_LINE]
    body.append(status(sha))
    if summary:
        body += ["", summary]
    comment = {
        "id": 900,
        "user": {"login": "github-actions[bot]", "type": "Bot"},
        "body": "\n".join(body),
    }
    if created is not None:
        comment["created_at"] = created
    if updated is not None:
        comment["updated_at"] = updated
    return comment


# The one security run of an unreviewed docs pull request: its lane job ran
# 00:10:05-00:10:24 and wrote the marker at 00:10:20.
HEAD_SKIP = ("2026-02-01T00:10:05Z", "2026-02-01T00:10:24Z")


class DocsOnlyBase(unittest.TestCase):
    def bind(
        self,
        security_runs: list[dict[str, Any]] | None = None,
        sec_marker: dict[str, Any] | None = None,
        paths: Any = (DOC,),
        threads: list[dict[str, Any]] | None = None,
        extra_comments: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        runs = [whole("claude-review", S)]
        runs += [skip_run(S, *HEAD_SKIP)] if security_runs is None else security_runs
        comments = [
            marker("claude-review", S),
            doc_marker() if sec_marker is None else sec_marker,
            *(extra_comments or []),
        ]
        return by_lane(
            ev.bind(
                S,
                runs,
                comments,
                list(threads or []),
                is_human=is_human,
                changed_paths=list(paths),
            )
        )

    def assertUnbound(self, item: Any, reason: str) -> None:
        self.assertFalse(item.bound)
        self.assertEqual(item.unbound_reason, reason)
        self.assertIsNone(item.open_findings)


class BindsTests(DocsOnlyBase):
    def test_docs_only_skip_on_the_head_binds_and_scores_low(self) -> None:
        result = self.bind()
        self.assertTrue(result[SEC].bound)
        self.assertEqual(result[SEC].open_findings, 0)
        self.assertFalse(result[SEC].whole_review_clears)
        self.assertTrue(result["claude-review"].bound)
        risk = score(_input(files=(_file(DOC),), lanes=tuple(result.values())))
        self.assertEqual(risk.score, Risk.LOW)
        self.assertEqual(risk.reasons, ())
        self.assertFalse(holds(risk))

    def test_each_allowed_documentation_path_binds(self) -> None:
        for path in (
            "README.md",
            "plugins/foo/README.md",
            "plugins/foo/CHANGELOG.md",
            "CHANGELOG.md",
            "docs/plugin-artifact-protocol.md",
        ):
            with self.subTest(path=path):
                self.assertTrue(self.bind(paths=(path,))[SEC].bound)

    def test_two_docs_only_skips_bind(self) -> None:
        runs = [
            skip_run(S0, "2026-02-01T00:00:05Z", "2026-02-01T00:00:24Z"),
            skip_run(S, *HEAD_SKIP),
        ]
        comment = doc_marker(created="2026-02-01T00:00:20Z")
        self.assertTrue(self.bind(runs, comment)[SEC].bound)


class LaneLeftoversHoldTests(DocsOnlyBase):
    """A thread or summary comment of the security lane shows a review the
    listed runs no longer do, whoever resolved it (the case E variant: a
    deleted review with an empty summary, or a deleted and recreated
    marker)."""

    SEC_TAG = f"`claude-lane: {SEC}`"
    REVIEW_TAG = "`claude-lane: claude-review`"

    def test_any_security_or_untagged_thread_holds(self) -> None:
        agent = {"__typename": "Bot", "login": "agent"}
        for item in (
            thread(created="2026-02-01T00:10:15Z"),
            thread(f"finding\n\n{self.SEC_TAG}"),
            thread(resolved=True, resolved_by=agent),
            thread(resolved=True, resolved_by=MAINTAINER),
        ):
            with self.subTest(thread=item):
                self.assertUnbound(
                    self.bind(threads=[item])[SEC], "docs-only-after-findings"
                )

    def test_a_clean_fresh_marker_beside_a_resolved_thread_holds(self) -> None:
        # The deleted review's marker was deleted and a skip created a new one.
        leftover = thread(
            f"finding\n\n{self.SEC_TAG}",
            resolved=True,
            resolved_by=MAINTAINER,
            created="2026-01-15T00:00:00Z",
        )
        self.assertUnbound(
            self.bind(threads=[leftover])[SEC], "docs-only-after-findings"
        )

    def test_a_security_or_untagged_summary_comment_holds(self) -> None:
        for body in ("Summary: no findings.", f"Summary.\n\n{self.SEC_TAG}"):
            with self.subTest(body=body):
                comment = {
                    "id": 950,
                    "user": {"login": "claude[bot]", "type": "Bot"},
                    "created_at": "2026-01-15T00:00:00Z",
                    "body": body,
                }
                self.assertUnbound(
                    self.bind(extra_comments=[comment])[SEC],
                    "docs-only-after-findings",
                )

    def test_the_code_review_lanes_thread_and_comment_do_not_hold(self) -> None:
        tagged = thread(f"finding\n\n{self.REVIEW_TAG}")
        comment = {
            "id": 951,
            "user": {"login": "claude[bot]", "type": "Bot"},
            "created_at": "2026-02-01T00:10:30Z",
            "body": f"Summary.\n\n{self.REVIEW_TAG}",
        }
        result = self.bind(threads=[tagged], extra_comments=[comment])[SEC]
        self.assertTrue(result.bound)
        self.assertEqual(result.open_findings, 0)

    def test_unread_threads_hold(self) -> None:
        result = by_lane(
            ev.bind(
                S,
                [whole("claude-review", S), skip_run(S, *HEAD_SKIP)],
                [marker("claude-review", S), doc_marker()],
                None,
                is_human=is_human,
                changed_paths=[DOC],
            )
        )
        self.assertUnbound(result[SEC], "threads-unread")


class PathsHoldTests(DocsOnlyBase):
    def test_an_instruction_path_holds_and_scores_med(self) -> None:
        skill = "plugins/foo/skills/bar/SKILL.md"
        result = self.bind(paths=(DOC, skill))
        self.assertUnbound(result[SEC], "skip-not-no-change")
        self.assertTrue(result["claude-review"].bound)
        risk = score(
            _input(files=(_file(DOC), _file(skill)), lanes=tuple(result.values()))
        )
        self.assertEqual(risk.score, Risk.MED)
        self.assertIn(f"evidence-unbound:{SEC}", [r.code for r in risk.reasons])
        self.assertTrue(holds(risk))

    def test_each_path_outside_the_allowlist_holds(self) -> None:
        for path in (
            "AGENTS.md",
            "plugins/foo/output-styles/README.md",
            "plugins/foo/output-styles/CHANGELOG.md",
            "plugins/foo/skills/bar/README.md",
            "plugins/foo/docs/README.md",
            "plugins/foo/scripts/README.md",
            "src/README.md",
            "Plugins/foo/README.md",
            "plugins/README.md",
            "plugins/./README.md",
            "plugins/../README.md",
            "./README.md",
            "docs/cloud-fleet-setup.md",
            "docs/cloud-sessions.md",
            "docs/migration-playbook.md",
            "docs/native-surfaces.md",
            "docs/glossary.md",
            "docs/conformance-dimensions.md",
            "docs/formatter-path-probes.md",
            "docs/skill-cheat-sheet.md",
            "docs/official-docs.md",
            "plugins/foo/AGENTS.md",
            "plugins/foo/AGENTS.override.md",
            "CLAUDE.md",
            "plugins/foo/agents/README.md",
            "plugins/foo/reference/README.md",
            "plugins/foo/Skills/README.md",
            "plugins/foo/hooks/README.md",
            "docs/plugin-philosophy.md",
            "docs/ci-runner-routing.md",
            "docs/README.md",
            "docs/upstream/claude-code.md",
            "docs/architecture/overview.md",
            "docs/adr/README.md",
            "docs/conventions/loop-lane/README.md",
            "docs/standards/README.md",
            "docs/a-new-doc.md",
            "Docs/README.md",
            "plugins/foo//README.md",
            "plugins/foo/README.md\n",
            "plugins/foo/readme.md",
            "plugins/foo/notes.md",
            "src/app.py",
        ):
            with self.subTest(path=path):
                self.assertUnbound(self.bind(paths=(path,))[SEC], "skip-not-no-change")

    def test_a_rename_from_code_holds(self) -> None:
        self.assertUnbound(
            self.bind(paths=("plugins/foo/README.md", "src/app.py"))[SEC],
            "skip-not-no-change",
        )

    def test_an_empty_or_unread_file_list_holds(self) -> None:
        self.assertUnbound(self.bind(paths=())[SEC], "skip-not-no-change")
        result = by_lane(
            ev.bind(
                S,
                [skip_run(S, *HEAD_SKIP)],
                [doc_marker()],
                [],
                is_human=is_human,
                changed_paths=None,
            )
        )
        self.assertUnbound(result[SEC], "changed-files-unread")


class OtherSkipsHoldTests(DocsOnlyBase):
    def test_no_run_holds(self) -> None:
        self.assertUnbound(self.bind(security_runs=[])[SEC], "no-run")

    def test_a_kill_switch_or_disabled_lane_holds(self) -> None:
        # The caller's kill-switch job stops the reusable: no lane job runs.
        item = skip_run(S, *HEAD_SKIP)
        item["attempts"][0]["jobs"][0]["name"] = "pr-review-security"
        item["attempts"][0]["jobs"][0]["conclusion"] = "skipped"
        item["attempts"][0]["jobs"][0]["annotations"] = []
        self.assertUnbound(self.bind([item])[SEC], "no-lane-job")

    def test_an_errored_or_timed_out_review_holds(self) -> None:
        timeout = {
            **OTHER_FAILURE,
            "message": "failure-class=timeout: the review step reached its"
            " timeout-minutes and was stopped before it finished",
        }
        for annotation in (OTHER_FAILURE, timeout, RATE_LIMIT):
            with self.subTest(annotation=annotation["message"]):
                item = run(
                    SEC, S, attempts=[attempt(SEC, S, 1, [annotation], "failure")]
                )
                self.assertUnbound(self.bind([item])[SEC], "run-not-success")

    def test_another_skip_kind_holds(self) -> None:
        item = skip_run(S, *HEAD_SKIP, tail="skip=lane-disabled")
        self.assertUnbound(self.bind([item])[SEC], "skip-not-no-change")

    def test_a_skip_with_no_record_holds(self) -> None:
        item = skip_run(S, *HEAD_SKIP)
        item["attempts"][0]["jobs"][0]["annotations"] = []
        self.assertUnbound(self.bind([item])[SEC], "no-record")

    def test_the_code_review_lanes_docs_only_skip_still_holds(self) -> None:
        runs = [run("claude-review", S, "skip=docs-only"), skip_run(S, *HEAD_SKIP)]
        result = by_lane(
            ev.bind(
                S,
                runs,
                [marker("claude-review", S), doc_marker()],
                [],
                is_human=is_human,
                changed_paths=[DOC],
            )
        )
        self.assertUnbound(result["claude-review"], "skip-not-no-change")
        self.assertTrue(result[SEC].bound)


class HeadTests(DocsOnlyBase):
    def test_a_skip_for_an_older_head_holds(self) -> None:
        runs = [skip_run(S0, *HEAD_SKIP)]
        self.assertUnbound(self.bind(runs, doc_marker(sha=S0))[SEC], "no-run")

    def test_a_marker_for_an_older_head_holds(self) -> None:
        self.assertUnbound(self.bind(sec_marker=doc_marker(sha=S0))[SEC], "no-marker")

    def test_a_marker_last_edited_by_an_older_heads_skip_holds(self) -> None:
        runs = [
            skip_run(S0, "2026-02-01T00:00:05Z", "2026-02-01T00:00:24Z"),
            skip_run(S, *HEAD_SKIP),
        ]
        comment = doc_marker(
            created="2026-02-01T00:00:20Z", updated="2026-02-01T00:00:20Z"
        )
        self.assertUnbound(self.bind(runs, comment)[SEC], "marker-outside-skip")


class UnreadableTests(DocsOnlyBase):
    def test_a_marker_status_that_is_not_the_docs_only_reason_holds(self) -> None:
        for body_status in (
            f"**{SEC}** reviewed `{S}`: 0 finding(s), 0 as inline comments.",
            status(S).replace("every file", "each file"),
            "",
        ):
            with self.subTest(status=body_status):
                comment = doc_marker()
                comment["body"] = comment["body"].replace(status(S), body_status)
                self.assertUnbound(
                    self.bind(sec_marker=comment)[SEC], "marker-not-docs-only"
                )

    def test_missing_or_unparsable_marker_times_hold(self) -> None:
        for comment in (
            doc_marker(created=None),
            doc_marker(updated=None),
            doc_marker(created="yesterday"),
            doc_marker(updated="2026-02-01T00:10:20"),
        ):
            with self.subTest(comment=comment):
                self.assertUnbound(
                    self.bind(sec_marker=comment)[SEC], "marker-unreadable"
                )

    def test_a_lane_job_with_no_times_holds(self) -> None:
        item = skip_run(S, *HEAD_SKIP)
        del item["attempts"][0]["jobs"][0]["started_at"]
        self.assertUnbound(self.bind([item])[SEC], "evidence-missing")


class DeletedReviewTests(DocsOnlyBase):
    """A review by a run no longer listed must never vanish behind a skip."""

    def test_a_listed_review_before_the_skip_holds(self) -> None:
        runs = [
            run(SEC, S0, "findings=2 inline=0 scope=whole"),
            skip_run(S, *HEAD_SKIP),
        ]
        self.assertUnbound(self.bind(runs)[SEC], "docs-only-after-review")

    def test_a_marker_a_deleted_run_created_beside_a_draft_skip_holds(
        self,
    ) -> None:
        draft = run(SEC, S0, attempts=[attempt(SEC, S0, 1, [], "skipped")])
        draft["attempts"][0]["jobs"] = []
        comment = doc_marker(created="2026-01-15T00:00:00Z")
        self.assertUnbound(
            self.bind([draft, skip_run(S, *HEAD_SKIP)], comment)[SEC],
            "marker-outside-skip",
        )

    def test_a_marker_a_deleted_run_created_beside_a_rate_limited_run_holds(
        self,
    ) -> None:
        failed = run(SEC, S0, attempts=[attempt(SEC, S0, 1, [RATE_LIMIT], "failure")])
        comment = doc_marker(created="2026-01-15T00:00:00Z")
        self.assertUnbound(
            self.bind([failed, skip_run(S, *HEAD_SKIP)], comment)[SEC],
            "marker-outside-skip",
        )

    def test_skip_deleted_review_skip_holds_on_the_carried_summary(self) -> None:
        runs = [
            skip_run(S1, "2026-02-01T00:00:05Z", "2026-02-01T00:00:24Z"),
            skip_run(S, *HEAD_SKIP),
        ]
        comment = doc_marker(
            created="2026-02-01T00:00:20Z",
            summary="Found one injection risk in the example command.",
        )
        self.assertUnbound(self.bind(runs, comment)[SEC], "marker-not-docs-only")


class InstructionCitationTests(unittest.TestCase):
    """No allowlisted doc is one an instruction file cites, so a pull request
    changing only it never changes what an agent reads as instructions."""

    SCANNED_DIRS = ("prompts", ".claude", "docs/conventions")
    SCANNED_NAMES = frozenset({"AGENTS.md", "CLAUDE.md", "REVIEW.md"})

    def instruction_files(self) -> list[pathlib.Path]:
        found = {
            path
            for top in self.SCANNED_DIRS
            for path in (ROOT / top).rglob("*")
            if path.is_file()
        }
        found |= {
            path
            for name in self.SCANNED_NAMES
            for path in ROOT.rglob(name)
            if path.is_file() and ".git" not in path.relative_to(ROOT).parts
        }
        return sorted(found)

    def test_no_instruction_file_cites_an_allowlisted_doc(self) -> None:
        self.assertTrue((ROOT / "AGENTS.md").is_file())
        files = self.instruction_files()
        self.assertGreater(len(files), 0)
        names = sorted(path.rsplit("/", 1)[-1] for path in ev.DOCS_ONLY_FILES)
        cite = re.compile(
            r"(?<![\w.-])(" + "|".join(map(re.escape, names)) + r")(?![\w-])"
        )
        hits = []
        for path in files:
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            for number, line in enumerate(text.split("\n"), 1):
                hits += [
                    f"{path.relative_to(ROOT)}:{number}: {name}"
                    for name in cite.findall(line)
                ]
        self.assertEqual(hits, [])


if __name__ == "__main__":
    unittest.main()

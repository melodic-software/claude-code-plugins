"""Review-evidence binding: per-lane evidence from workflow runs, attempts,
completion annotations, the reviewed-head marker and review threads.

Expected values come from the plan's Design section "Review evidence" and the
lane producer's record format (ci-workflows pr-review.yml at v0.41.0). The
probe fixture is a recorded, de-identified run pair from a sandbox pull
request whose two lanes were each re-run once after a successful attempt.
"""

from __future__ import annotations

import copy
import importlib.util
import json
import pathlib
import re
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy
import babysit_review_evidence as ev
import babysit_risk as risk

# This repository's rows, which the floor paths below sit on.
FLOOR_ROWS = policy.floor_paths_in(
    (pathlib.Path(__file__).resolve().parents[6] / "docs/conventions/pr-pipeline.yaml").read_text(encoding="utf-8")
)
FLOOR = risk.floor_for(FLOOR_ROWS)


FIXTURES = pathlib.Path(__file__).resolve().parent / "fixtures" / "review_evidence"
PROBE = json.loads((FIXTURES / "probe_rerun_after_success.json").read_text())
# The caller's edit record (babysit_merge._attach_edits): the recorded comments
# were never edited.
for _comment in PROBE["comments"]:
    _comment["edit"] = {"lastEditedAt": None}
UNEDITED = {"lastEditedAt": None}

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
# publish-review's failure line (ci-workflows publish.cjs `fail`) for a
# rejected Claude credential.
AUTH_FAILURE = dict(
    OTHER_FAILURE,
    message="claude-review: failure-class=auth:"
    " the Claude credential was rejected; the owner replaces the secret",
)
# publish-review's failure line (ci-workflows publish.cjs `fail`) for a failed
# runner isolation or CLI install (ci-workflows#893).
INSTALL_FAILURE = dict(
    OTHER_FAILURE,
    message="claude-review: failure-class=install-failed: the runner isolation"
    " or the Claude Code CLI install or its integrity check failed",
)

# publish-review's failure line (ci-workflows publish.cjs `fail`) as a run
# recorded it when the review's own post hit GitHub's API rate limit.
PUBLISH_RATE_LIMIT = {
    "path": ".github",
    "annotation_level": "failure",
    "title": "",
    "message": "claude-review: failure-class=publish-failed: posting the review failed"
    " (API rate limit exceeded for installation. If you reach out to GitHub Support"
    " for help, please include the request ID 7819:37FE4F:2414D85:756EBF6:6ADCE2DA"
    " and timestamp 2026-10-24 16:54:51 UTC. For more on scraping GitHub and how it"
    " may affect your rights, please review our Terms of Service"
    " (https://docs.github.com/en/site-policy/github-terms/github-terms-of-service)"
    " - https://docs.github.com/en/rest/using-the-rest-api/getting-started-with-the-rest-api#rate-limiting)",
}


def publish_failed(detail: str) -> dict[str, Any]:
    return {
        "path": ".github",
        "annotation_level": "failure",
        "title": "",
        "message": f"claude-review: failure-class=publish-failed: posting the review failed ({detail})",
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
    tree: str | None = None,
) -> dict[str, Any]:
    """A lane run at `sha`; its head's tree is `tree`, else one of its own."""
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
        "head_commit": {"id": sha, "tree_id": tree or tree_of(sha)},
        "attempts": attempts,
    }


def tree_of(sha: str) -> str:
    """A tree sha of `sha`'s own, distinct per commit sha."""
    return sha[::-1]


def marker(lane: str, sha: str, login: str = "github-actions[bot]") -> dict[str, Any]:
    return {
        "id": next(_ids),
        "user": {"login": login, "type": "Bot"},
        "created_at": "2026-01-01T00:00:00Z",
        "edit": UNEDITED,
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
                "lastEditedAt": None,
                "editor": None,
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
        # The probe left each run's commit object out; a listed run has one.
        data = copy.deepcopy(data)
        for item in data["runs"]:
            item["head_commit"] = {
                "id": item["head_sha"],
                "tree_id": tree_of(item["head_sha"]),
            }
        return by_lane(
            ev.bind(
                data["head_sha"],
                data["runs"],
                data["comments"],
                data["threads"],
                is_human=is_human,
                changed_paths=(),
                floor=risk.floor_for(),
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
                floor=risk.floor_for(),
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
                floor=risk.floor_for(),
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

    def test_a_change_to_a_file_the_review_reads_from_the_checkout(self) -> None:
        for path in (
            ".github/workflows/pr-review-hosted.yml",
            ".github/workflows/pr-review-security-hosted.yml",
            ".claude/settings.json",
            "plugins/foo/.claude/rules/x.md",
            ".mcp.json",
            "plugins/foo/.mcp.json",
            "CLAUDE.md",
            "plugins/foo/CLAUDE.md",
            "CLAUDE.local.md",
            "AGENTS.md",
            "plugins/foo/skills/bar/AGENTS.md",
            "REVIEW.md",
            ".gitattributes",
            "plugins/foo/.gitattributes",
            "docs/standards/README.md",
            "docs/standards/simpler-code.md",
            "docs/review/README.md",
            "docs/review/cost-claims.md",
            "docs/contracts/instruction-exception-register/README.md",
            "docs/contracts/untrusted-content/README.md",
            "docs/conventions/instruction-exception-register/README.md",
            "docs/conventions/untrusted-content/README.md",
            ".claude-lane/pr-context.md",
            ".github/workflows/other.yml",
            ".github/workflows/pr-review-hosted.yml.bak",
            ".claude",
            ".claude-lane",
            "plugins/x/.claude",
            ".github/workflows",
            "docs/standards",
        ):
            with self.subTest(path):
                result = self.bound(path)
                for lane in LANES:
                    self.assertUnbound(result[lane], "lane-source-changed")

    def test_a_review_plugin_change_binds_both_lanes(self) -> None:
        # The reusable stages the review plugin from the default branch's
        # tip, never the head (scripts/ci-review-plugin-source.test.sh pins
        # the callers to that), so a pull request's copy feeds no review.
        for path in (
            "plugins/review/skills/security-review/SKILL.md",
            "plugins/review/skills/code-review/SKILL.md",
            "plugins/review/agents/lane-verifier.md",
            "plugins/review/.claude-plugin/plugin.json",
            "plugins/review",
        ):
            with self.subTest(path):
                result = self.bound("app.py", path)
                for lane in LANES:
                    self.assertTrue(result[lane].bound, lane)

    def test_a_review_plugin_change_beside_lane_source_still_unbinds(self) -> None:
        for other in (
            ".github/workflows/pr-review-hosted.yml",
            "docs/standards/README.md",
            ".claude-lane/pr-context.md",
            "plugins/review/CLAUDE.md",
            "plugins/review/.claude/settings.json",
        ):
            with self.subTest(other):
                result = self.bound("plugins/review/skills/code-review/SKILL.md", other)
                for lane in LANES:
                    self.assertUnbound(result[lane], "lane-source-changed")

    def test_a_path_that_is_not_a_string_binds_no_lane(self) -> None:
        result = self.bound("app.py", None)  # type: ignore[arg-type]
        for lane in LANES:
            self.assertUnbound(result[lane], "lane-source-changed")

    def test_lane_source_is_checked_before_any_lane_binds(self) -> None:
        # No runs at all: the lane-source reason wins over a missing run.
        result = self.bind([], changed_paths=(".mcp.json",))
        for lane in LANES:
            self.assertUnbound(result[lane], "lane-source-changed")

    def test_github_files_the_review_takes_from_main_bind(self) -> None:
        # The callers run every local action from a .base checkout of main
        # and the reusable runs its composites from its own repository, so a
        # pull request's copy of these never feeds its own review.
        for path in (
            ".github/actions/resolve-config/action.yml",
            ".github/actions/check-kill-switch/action.yml",
            ".github/scripts/pr-unblock/feedback-dispatch.mjs",
            ".github/scripts/x.mjs",
            "docs/conventions/pr-pipeline.yaml",
        ):
            with self.subTest(path):
                result = self.bound(path)
                for lane in LANES:
                    self.assertTrue(result[lane].bound, lane)

    def test_unrelated_changes_bind_as_before(self) -> None:
        result = self.bound(
            "app.py",
            "docs/github/x.md",
            "plugins/reviewer/a.py",
            "docs/standards-old/x.md",
            "docs/reviewer.md",
            "docs/review-old/x.md",
            "plugins/foo/CLAUDE.md.bak",
            "docs/REVIEW.md.txt",
            "plugins/foo/.claude-lane-notes/x.md",
            "plugins/foo/.claude-lane/x.md",
            ".mcp.json.bak",
            ".claude-lane-notes",
            ".github/workflows-old/x.yml",
        )
        for lane in LANES:
            self.assertTrue(result[lane].bound, lane)
            self.assertEqual(result[lane].open_findings, 0)

    def test_unread_changed_files_bind_no_lane(self) -> None:
        result = self.bind([whole(lane, S) for lane in LANES], changed_paths=None)
        for lane in LANES:
            self.assertUnbound(result[lane], "changed-files-unread")


BASE = "b0" * 20
# The gate reads workflow YAML with PyYAML; with none, nothing clears.
NEEDS_YAML = unittest.skipUnless(
    importlib.util.find_spec("yaml"),
    "PyYAML not installed (CI's check-skills job installs it)",
)
WORKFLOW = ".github/workflows/lint-docs.yml"
# A workflow whose token cannot write and that reaches no secret.
READ_ONLY = """\
name: lint-docs
on:
  pull_request:
    paths: ['docs/**']
  push:
permissions:
  contents: read
jobs:
  lint:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
      pull-requests: read
    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
      - run: npm test
  call:
    uses: melodic-software/ci-workflows/.github/workflows/x.yml@v1
"""


def reader(files: dict[str, str | None]) -> Any:
    """A head-file reader over `files`; any other path raises, as an unproven
    read does."""

    def read(path: str, original: str) -> str | None:
        if original != BASE or path not in files:
            raise RuntimeError(f"head-file-unproven:{path}")
        return files[path]

    return read


class ReadOnlyWorkflowTests(Base):
    """A changed workflow binds only when its head copy cannot post as
    github-actions[bot] with write access (the reviewed-head marker's author)
    nor reach a credential that could; anything else, or any doubt, stays a
    lane source."""

    def bound(
        self, files: dict[str, str | None], *extra: str, base: Any = BASE
    ) -> dict[str, Any]:
        return by_lane(
            ev.bind(
                S,
                [whole(lane, S) for lane in LANES],
                both_markers(),
                [],
                is_human=is_human,
                changed_paths=("app.py", *files, *extra),
                head_file=reader(files),
                base_sha=base,
                floor=FLOOR,
            )
        )

    def assertBinds(self, result: dict[str, Any]) -> None:
        for lane in LANES:
            self.assertTrue(result[lane].bound, lane)
            self.assertIsNone(result[lane].unbound_reason, lane)
            self.assertEqual(result[lane].open_findings, 0, lane)

    def assertHeld(self, result: dict[str, Any]) -> None:
        for lane in LANES:
            self.assertUnbound(result[lane], "lane-source-changed")

    @NEEDS_YAML
    def test_a_read_only_workflow_edit_binds(self) -> None:
        self.assertBinds(self.bound({WORKFLOW: READ_ONLY}))

    @NEEDS_YAML
    def test_a_clean_review_clears_a_read_only_workflow_edit_end_to_end(self) -> None:
        # Owner direction 2026-10-27: a workflow-file pull request needs a
        # person only for a HIGH or CRITICAL security finding. The scorer
        # takes the bound evidence beside an enforcement-floor path.
        floored = "plugins/source-control/skills/babysit-prs/scripts/babysit_gh.py"
        base = READ_ONLY.replace("npm test", "npm run lint")

        def scored(lanes: dict[str, Any]) -> Any:
            files = (
                risk.ChangedFile(
                    floored, None, "modified", 1, 1, True, "100644", "100644"
                ),
                risk.ChangedFile(
                    WORKFLOW,
                    None,
                    "modified",
                    1,
                    1,
                    True,
                    "100644",
                    "100644",
                    patch="@@ -18 +18 @@\n-      - run: npm run lint\n+      - run: npm test",
                    contents=(base, READ_ONLY),
                ),
            )
            return risk.score(
                risk.RiskInput(
                    files=files,
                    files_complete=True,
                    max_changed_lines=None,
                    high_paths=(),
                    lanes=tuple(lanes[lane] for lane in LANES),
                    lines_optional=True,
                    public=True,
                )
            )

        lanes = by_lane(
            ev.bind(
                S,
                [whole(lane, S) for lane in LANES],
                both_markers(),
                [],
                is_human=is_human,
                changed_paths=(floored, WORKFLOW),
                head_file=reader({WORKFLOW: READ_ONLY}),
                base_sha=BASE,
                floor=risk.floor_for(),
            )
        )
        self.assertBinds(lanes)
        result = scored(lanes)
        self.assertFalse(risk.holds(result), [r.code for r in result.reasons])
        # A CRITICAL finding from that review holds it for a person.
        critical = by_lane(
            ev.bind(
                S,
                [whole("claude-review", S), whole("claude-security-review", S, 1, 1)],
                both_markers(),
                [
                    thread(
                        "x\n\nseverity: CRITICAL\n`claude-lane: claude-security-review`"
                    )
                ],
                is_human=is_human,
                changed_paths=(floored, WORKFLOW),
                head_file=reader({WORKFLOW: READ_ONLY}),
                base_sha=BASE,
                floor=risk.floor_for(),
            )
        )
        result = scored(critical)
        self.assertEqual(
            [r.code for r in risk.person_reasons(risk.holding(result))],
            ["security-finding"],
        )

    @NEEDS_YAML
    def test_read_all_and_empty_permissions_bind(self) -> None:
        for perms in ("permissions: read-all", "permissions: {}"):
            with self.subTest(perms):
                text = READ_ONLY.replace("permissions:\n  contents: read", perms, 1)
                self.assertBinds(self.bound({WORKFLOW: text}))

    def test_a_deleted_workflow_stays_a_lane_source(self) -> None:
        # What a deleted workflow enforced goes with it.
        for path in (
            ".github/workflows/pr-merge.yml",
            ".github/workflows/pr-require-checks.yml",
            ".github/workflows/pr-verify.yml",
            WORKFLOW,
        ):
            with self.subTest(path):
                self.assertHeld(self.bound({path: None}))

    @NEEDS_YAML
    def test_a_read_only_rewrite_of_a_floor_workflow_stays_a_lane_source(
        self,
    ) -> None:
        floored = [
            path
            for path, _ in FLOOR.classes
            if ev.WORKFLOW_PATH_RE.match(path) and path not in ev.REVIEW_CALLERS
        ]
        self.assertIn(".github/workflows/pr-merge.yml", floored)
        self.assertIn(".github/workflows/pr-require-checks.yml", floored)
        for path in floored:
            stem = ev.WORKFLOW_PATH_RE.match(path)[1]
            text = READ_ONLY.replace("name: lint-docs", f"name: {stem}", 1)
            with self.subTest(path):
                self.assertHeld(self.bound({path: text}))

    @NEEDS_YAML
    def test_each_unsafe_workflow_stays_a_lane_source(self) -> None:
        top = "permissions:\n  contents: read\njobs:"
        job = "    permissions:\n      contents: read\n      pull-requests: read\n"
        cases = {
            "a write scope at the top": READ_ONLY.replace(
                top, "permissions:\n  contents: read\n  pull-requests: write\njobs:"
            ),
            "a write scope in one job": READ_ONLY.replace(
                job, "    permissions:\n      issues: write\n"
            ),
            "write-all": READ_ONLY.replace(top, "permissions: write-all\njobs:"),
            "write-all in a flow mapping": READ_ONLY.replace(
                top, "permissions: {contents: read, statuses: write}\njobs:"
            ),
            "id-token: write": READ_ONLY.replace(
                job, "    permissions:\n      id-token: write\n"
            ),
            "a pull_request_target trigger": READ_ONLY.replace(
                "  push:\n", "  pull_request_target:\n"
            ),
            "a workflow_run trigger": READ_ONLY.replace(
                "  push:\n", "  workflow_run:\n    workflows: [x]\n"
            ),
            "a workflow_call trigger": READ_ONLY.replace(
                "  push:\n", "  workflow_call:\n"
            ),
            "unparsable YAML": READ_ONLY + "  bad: [unclosed\n",
            "not a mapping": "- just\n- a list\n",
            "two documents": READ_ONLY + "---\n" + READ_ONLY,
            "a reusable call with secrets: inherit": READ_ONLY
            + "    secrets: inherit\n",
            "a direct secret": READ_ONLY.replace(
                "secrets.GITHUB_TOKEN", "secrets.SCAN_CARRIER_PRIVATE_KEY"
            ),
            "a secret spelled with a YAML escape": READ_ONLY.replace(
                "- run: npm test", '- run: "echo ${{ \\x73ecrets.APP_KEY }}"'
            ),
            "missing permissions everywhere": READ_ONLY.replace(top, "jobs:").replace(
                job, ""
            ),
            "a job with no permissions and none at the top": READ_ONLY.replace(
                top, "jobs:"
            ),
            "a name that is not the stem": READ_ONLY.replace(
                "name: lint-docs", "name: pr-require-checks"
            ),
            "no name": READ_ONLY.replace("name: lint-docs\n", ""),
            "a repeated key": READ_ONLY.replace(
                top, "permissions:\n  contents: read\npermissions: write-all\njobs:"
            ),
            "a key repeated in another case": READ_ONLY.replace(
                top,
                "permissions:\n  contents: read\nPermissions:\n  contents: read\njobs:",
            ),
            "an anchor and alias": READ_ONLY.replace(
                top, "permissions: &p\n  contents: read\nenv: *p\njobs:"
            ),
            "a merge key": READ_ONLY.replace(
                job, "    permissions:\n      <<: {contents: read}\n"
            ),
            "an explicit tag": READ_ONLY.replace(
                "contents: read\njobs:", "contents: !!str read\njobs:"
            ),
            "an unknown top-level key": READ_ONLY + "Jobs: {}\n",
            "an unknown job key": READ_ONLY.replace(
                "    runs-on:", "    Permissions: {}\n    runs-on:"
            ),
            "an expression for a scope": READ_ONLY.replace(
                "pull-requests: read", "pull-requests: ${{ 'write' }}"
            ),
            "no jobs": "name: lint-docs\non: push\npermissions: {}\njobs: {}\n",
            "no trigger": READ_ONLY.replace("on:", "run-name:", 1),
        }
        # Each case holds through the parsed reading alone too, with the
        # raw-text backstop matching nothing.
        never = re.compile(r"(?!)")
        for backstop in (ev.WORKFLOW_DENIED_TEXT_RE, never):
            with mock.patch.object(ev, "WORKFLOW_DENIED_TEXT_RE", backstop):
                self.assertBinds(self.bound({WORKFLOW: READ_ONLY}))
                for name, text in cases.items():
                    with self.subTest(name, backstop=backstop.pattern):
                        self.assertHeld(self.bound({WORKFLOW: text}))

    def test_a_review_caller_with_read_only_content_stays_a_lane_source(self) -> None:
        for lane in LANES:
            path = FILES[lane]
            stem = path.rsplit("/", 1)[1][: -len(".yml")]
            text = READ_ONLY.replace("lint-docs", stem)
            with self.subTest(path):
                self.assertHeld(self.bound({path: text}))
                self.assertHeld(self.bound({path: None}))

    def test_other_workflow_paths_stay_lane_sources(self) -> None:
        for path in (
            ".github/workflows/lint-docs.yaml",
            ".github/workflows/sub/lint-docs.yml",
            ".github/workflows/Lint-Docs.yml",
            ".github/workflows",
        ):
            with self.subTest(path):
                self.assertHeld(self.bound({path: READ_ONLY}))

    def test_doubt_about_the_read_stays_a_lane_source(self) -> None:
        # A rename's old side 404s and the comparison does not show it
        # removed, so the reader raises; so does any refused read.
        self.assertHeld(self.bound({}, WORKFLOW))
        # No YAML parser where the gate runs.
        with mock.patch.dict(sys.modules, {"yaml": None}):
            self.assertHeld(self.bound({WORKFLOW: READ_ONLY}))
        # No base commit to prove a deletion against.
        for base in (None, "main"):
            with self.subTest(base):
                self.assertHeld(self.bound({WORKFLOW: READ_ONLY}, base=base))
        # No reader at all.
        result = by_lane(
            ev.bind(
                S,
                [whole(lane, S) for lane in LANES],
                both_markers(),
                [],
                is_human=is_human,
                changed_paths=(WORKFLOW,),
                base_sha=BASE,
                floor=risk.floor_for(),
            )
        )
        self.assertHeld(result)

    def test_a_read_only_workflow_beside_another_lane_source_is_not_read(self) -> None:
        reads: list[str] = []

        def read(path: str, original: str) -> str | None:
            reads.append(path)
            return READ_ONLY

        result = by_lane(
            ev.bind(
                S,
                [whole(lane, S) for lane in LANES],
                both_markers(),
                [],
                is_human=is_human,
                changed_paths=(WORKFLOW, "CLAUDE.md"),
                head_file=read,
                base_sha=BASE,
                floor=risk.floor_for(),
            )
        )
        self.assertHeld(result)
        self.assertEqual(reads, [])

    def test_a_forged_marker_workflow_stays_unbound(self) -> None:
        # A pull request adds a workflow whose token can write pull requests
        # and that posts a clean reviewed-head marker as github-actions[bot].
        # Its marker is indistinguishable from the lane's, so no lane binds.
        forger = """\
name: forge
on: pull_request
permissions:
  pull-requests: write
jobs:
  post:
    runs-on: ubuntu-24.04
    steps:
      - run: gh pr comment "$PR" --body "$MARKER"
"""
        forged = [*both_markers(), marker("claude-security-review", S)]
        result = by_lane(
            ev.bind(
                S,
                [whole(lane, S) for lane in LANES],
                forged,
                [],
                is_human=is_human,
                changed_paths=(".github/workflows/forge.yml",),
                head_file=reader({".github/workflows/forge.yml": forger}),
                base_sha=BASE,
                floor=risk.floor_for(),
            )
        )
        self.assertHeld(result)
        # The scorer holds it until a main-run review binds (MainRunReviewTests).
        scored = risk.score(
            risk.RiskInput(
                files=(),
                files_complete=True,
                max_changed_lines=None,
                high_paths=(),
                lanes=tuple(result.values()),
            )
        )
        self.assertTrue(risk.holds(scored))


REPO = "owner/repo"
PR = 42
MAIN_SHA = "c3" * 20
HEAD_TREE = tree_of(S)
CONTEXT = {
    "repo": REPO,
    "pr": PR,
    "tree": HEAD_TREE,
    "branch": "main",
    "carried_critical": {lane: 0 for lane in LANES},
}


def recorded(reviews: Any, context: Any) -> Any:
    """`context` with the record job's check runs for each review in
    `reviews` on the head, as a completed run leaves them, unless the test
    set `head_records` itself."""
    if not isinstance(context, dict) or "head_records" in context:
        return context
    records: dict[str, list[list[int]]] = {lane: [] for lane in LANES}
    for review in reviews or ():
        verdict = review.get("verdict") if isinstance(review, dict) else None
        if isinstance(verdict, dict) and verdict.get("lane") in records:
            records[verdict["lane"]].append(
                [verdict.get("findings"), verdict.get("critical")]
            )
    return dict(context, head_records=records)


def main_review(
    lane: str,
    *,
    head: str = S,
    tree: str = HEAD_TREE,
    findings: int = 0,
    critical: int = 0,
    max_line_bytes: Any = 120,
    **run_fields: Any,
) -> dict[str, Any]:
    """A main-run review record as `babysit_gh.collect_main_reviews` reads
    it: the artifact, its run and its verdict.json, each field a value the
    workflow and GitHub's artifact and run records carry."""
    run_id = next(_ids)
    run_record = {
        "id": run_id,
        "path": ".github/workflows/pr-review-main.yml",
        "event": "workflow_run",
        "head_branch": "main",
        "head_sha": MAIN_SHA,
        "status": "completed",
        "conclusion": "success",
        "repository": {"full_name": REPO},
        "head_repository": {"full_name": REPO},
    }
    run_record.update(run_fields)
    return {
        "lane": lane,
        "on_branch": True,
        "artifact": {
            "id": next(_ids),
            "name": f"pr-review-main-{lane}-{PR}-{tree}",
            "expired": False,
            "workflow_run": {"id": run_id},
        },
        "run": run_record,
        "verdict": {
            "schema": 1,
            "lane": lane,
            "pr": PR,
            "head_sha": head,
            "tree": tree,
            "findings": findings,
            "critical": critical,
            "max_line_bytes": max_line_bytes,
        },
    }


class MainRunReviewTests(Base):
    """A pull request that changes a lane source binds a lane only on a review
    that ran from main's copy of pr-review-main.yml (owner direction
    2026-10-28): the run's identity, never a comment's author."""

    SOURCE = ".github/workflows/deploy.yml"

    def main_bind(
        self,
        reviews: Any,
        *,
        comments: list[dict[str, Any]] | None = None,
        context: Any = CONTEXT,
        threads: list[dict[str, Any]] | None = (),  # type: ignore[assignment]
    ) -> dict[str, Any]:
        return by_lane(
            ev.bind(
                S,
                [whole(lane, S) for lane in LANES],
                both_markers() if comments is None else comments,
                list(threads) if threads is not None else None,
                is_human=is_human,
                changed_paths=("app.py", self.SOURCE),
                head_file=fixed_head,
                main_reviews=reviews,
                main_context=recorded(reviews, context),
                floor=risk.floor_for(),
            )
        )

    def test_a_verdict_with_no_matching_record_on_the_head_does_not_bind(
        self,
    ) -> None:
        # A run cancelled before `record` left a verdict but no check run, so
        # its CRITICAL would not carry to a later head: it binds nothing.
        reviews = [main_review(lane, findings=1, critical=1) for lane in LANES]
        for records in (
            {lane: [] for lane in LANES},
            {lane: [[0, 0]] for lane in LANES},
            {},
            None,
        ):
            with self.subTest(records=records):
                result = self.main_bind(
                    reviews, context=dict(CONTEXT, head_records=records)
                )
                for lane in LANES:
                    self.assertUnbound(result[lane], "lane-source-changed")
        matched = self.main_bind(
            reviews,
            context=dict(CONTEXT, head_records={lane: [[1, 1]] for lane in LANES}),
        )
        for lane in LANES:
            self.assertTrue(matched[lane].bound, lane)

    def test_a_designed_stop_on_the_head_names_the_unbound_reason(self) -> None:
        # pr-review-main stopped on a diff too large to read whole and posted
        # `verdict=none reason=too-large`: no verdict, so nothing binds, and
        # the reason says why; a CRITICAL another head carried still holds.
        context = dict(
            CONTEXT,
            carried_critical={"claude-review": 0, "claude-security-review": 2},
            head_records={lane: [] for lane in LANES},
            head_stops={lane: ["too-large"] for lane in LANES},
        )
        result = self.main_bind(None, context=context)
        for lane in LANES:
            self.assertUnbound(result[lane], "main-review-stop:too-large")
        self.assertEqual(result["claude-security-review"].blocking_findings, 2)
        # The scorer reports the stop by name as a lane cause, the same MED
        # unbound evidence as before; no person code is added for it.
        scored = risk.score(
            risk.RiskInput(
                files=(),
                files_complete=True,
                max_changed_lines=None,
                high_paths=(),
                lanes=tuple(result.values()),
            )
        )
        unbound = {
            r.code: (r.severity, r.detail)
            for r in scored.reasons
            if r.code.startswith("evidence-unbound:")
        }
        self.assertEqual(
            unbound,
            {
                f"evidence-unbound:{lane}": (
                    risk.Risk.MED,
                    "not bound: main-review-stop:too-large",
                )
                for lane in LANES
            },
        )
        # The carried CRITICAL is the only reason a person reads.
        self.assertEqual(
            [r.code for r in risk.person_reasons(scored.reasons)],
            ["security-finding"],
        )

    def test_a_verdict_on_the_head_binds_over_a_stop_beside_it(self) -> None:
        # A re-run reviewed the head whole after an earlier run stopped on it.
        reviews = [main_review(lane, findings=1, critical=0) for lane in LANES]
        result = self.main_bind(
            reviews,
            context=dict(
                CONTEXT,
                head_records={lane: [[1, 0]] for lane in LANES},
                head_stops={lane: ["binary"] for lane in LANES},
            ),
        )
        for lane in LANES:
            self.assertTrue(result[lane].bound, lane)
            self.assertIsNone(result[lane].unbound_reason)

    def test_the_code_lanes_pull_request_runs_change_nothing(self) -> None:
        # Pin for the merge job's read cut: a lane-source pull request's
        # evidence is the same whether or not the code lane's runs were
        # listed, so the caller lists only the security lane's.
        security = [whole("claude-security-review", S)]
        both = [whole(lane, S) for lane in LANES]
        for reviews in (None, [main_review(lane) for lane in LANES]):
            with self.subTest(reviews=bool(reviews)):
                results = [
                    ev.bind(
                        S,
                        runs,
                        both_markers(),
                        [],
                        is_human=is_human,
                        changed_paths=("app.py", self.SOURCE),
                        head_file=fixed_head,
                        main_reviews=reviews,
                        main_context=recorded(reviews, CONTEXT),
                        floor=risk.floor_for(),
                    )
                    for runs in (security, both)
                ]
                self.assertEqual(results[0], results[1])

    def test_a_clean_main_run_review_of_the_head_binds_both_lanes(self) -> None:
        result = self.main_bind([main_review(lane) for lane in LANES])
        for lane in LANES:
            self.assertTrue(result[lane].bound, lane)
            self.assertIsNone(result[lane].unbound_reason)
            self.assertEqual(result[lane].open_findings, 0)
        self.assertEqual(result["claude-security-review"].blocking_findings, 0)

    def test_a_verdict_on_a_diff_with_a_line_past_the_cap_does_not_bind(self) -> None:
        # Read may cut a 2,500-byte line short, so a review of that diff saw
        # part of it; a 1,000-byte line is read whole.
        clean = self.main_bind(
            [main_review(lane, max_line_bytes=1000) for lane in LANES]
        )
        for lane in LANES:
            self.assertTrue(clean[lane].bound, lane)
        for longest in (2500, ev.LONG_LINE_BYTES + 1, None, "1000", True):
            with self.subTest(longest=longest):
                result = self.main_bind(
                    [main_review(lane, max_line_bytes=longest) for lane in LANES]
                )
                for lane in LANES:
                    self.assertUnbound(result[lane], "lane-source-changed")

    def test_a_forged_marker_on_pull_request_runs_still_unbinds(self) -> None:
        # Clean pull_request records and markers by github-actions[bot], which
        # any write-token workflow in the head can post, bind nothing.
        forged = [*both_markers(), marker("claude-security-review", S)]
        result = self.main_bind(None, comments=forged)
        for lane in LANES:
            self.assertUnbound(result[lane], "lane-source-changed")
        self.assertEqual(self.main_bind([]), self.main_bind(None))

    def test_one_lane_reviewed_from_main_binds_only_that_lane(self) -> None:
        result = self.main_bind([main_review("claude-review")])
        self.assertTrue(result["claude-review"].bound)
        self.assertUnbound(result["claude-security-review"], "lane-source-changed")

    def test_a_review_of_another_head_or_tree_does_not_bind(self) -> None:
        for review in (
            main_review("claude-review", head=S1),
            main_review("claude-review", tree=tree_of(S1)),
        ):
            with self.subTest(review["verdict"]):
                result = self.main_bind([review])
                self.assertUnbound(result["claude-review"], "lane-source-changed")

    def test_a_run_not_from_mains_definition_does_not_bind(self) -> None:
        for fields in (
            {"event": "pull_request"},
            {"head_branch": "feature"},
            {"path": ".github/workflows/pr-review-hosted.yml"},
            {"repository": {"full_name": "fork/repo"}},
            {"head_repository": {"full_name": "fork/repo"}},
            {"head_sha": "not-a-sha"},
        ):
            with self.subTest(fields):
                result = self.main_bind([main_review("claude-review", **fields)])
                self.assertUnbound(result["claude-review"], "lane-source-changed")

    def test_an_artifact_or_verdict_that_does_not_match_its_run_does_not_bind(
        self,
    ) -> None:
        def changed(edit: Any) -> dict[str, Any]:
            review = main_review("claude-review")
            edit(review)
            return review

        for name, edit in (
            ("head not on main", lambda r: r.update(on_branch=False)),
            ("on_branch unread", lambda r: r.pop("on_branch")),
            (
                "another run's artifact",
                lambda r: r["artifact"]["workflow_run"].update(id=1),
            ),
            ("expired", lambda r: r["artifact"].update(expired=True)),
            (
                "other lane's name",
                lambda r: r["artifact"].update(
                    name=f"pr-review-main-claude-security-review-{PR}-{HEAD_TREE}"
                ),
            ),
            ("other pull request", lambda r: r["verdict"].update(pr=PR + 1)),
            ("other tree in verdict", lambda r: r["verdict"].update(tree=tree_of(S1))),
            (
                "other lane in verdict",
                lambda r: r["verdict"].update(lane="claude-security-review"),
            ),
            ("unknown schema", lambda r: r["verdict"].update(schema=2)),
            ("negative count", lambda r: r["verdict"].update(findings=-1)),
            ("bool count", lambda r: r["verdict"].update(findings=True)),
            ("critical over findings", lambda r: r["verdict"].update(critical=1)),
            ("short head", lambda r: r["verdict"].update(head_sha=S[:12])),
        ):
            with self.subTest(name):
                result = self.main_bind([changed(edit)])
                self.assertUnbound(result["claude-review"], "lane-source-changed")

    def test_no_context_binds_nothing(self) -> None:
        reviews = [main_review(lane) for lane in LANES]
        for context in (None, {}, dict(CONTEXT, tree="x"), dict(CONTEXT, pr="42")):
            with self.subTest(context):
                result = self.main_bind(reviews, context=context)
                for lane in LANES:
                    self.assertUnbound(result[lane], "lane-source-changed")

    def test_a_clean_verdict_from_a_run_that_did_not_succeed_does_not_bind(
        self,
    ) -> None:
        for fields in ({"status": "in_progress"}, {"conclusion": "failure"}):
            with self.subTest(fields):
                result = self.main_bind([main_review("claude-review", **fields)])
                self.assertUnbound(result["claude-review"], "lane-source-changed")

    def test_a_finding_from_a_failed_run_still_counts(self) -> None:
        # A run fails as a whole when either lane's job fails, after the
        # other lane uploaded; its findings still count, as pr-verify's FAIL
        # does, so failing one lane and re-running cannot clear the other's.
        result = self.main_bind(
            [
                main_review("claude-review"),
                main_review(
                    "claude-security-review",
                    findings=1,
                    critical=1,
                    conclusion="failure",
                ),
                main_review("claude-security-review"),
            ]
        )
        security = result["claude-security-review"]
        self.assertTrue(security.bound)
        self.assertEqual((security.open_findings, security.blocking_findings), (1, 1))

    def test_findings_count_the_most_any_review_of_the_tree_reported(self) -> None:
        # A re-run, or an empty commit with the same tree, never clears one.
        result = self.main_bind(
            [
                main_review("claude-review", findings=2),
                main_review("claude-review", findings=0),
                main_review("claude-security-review", findings=3, critical=1),
                main_review("claude-security-review", head=S0, findings=0),
            ]
        )
        self.assertEqual(result["claude-review"].open_findings, 2)
        security = result["claude-security-review"]
        self.assertEqual((security.open_findings, security.blocking_findings), (3, 1))
        scored = risk.score(
            risk.RiskInput(
                files=(),
                files_complete=True,
                max_changed_lines=None,
                high_paths=(),
                lanes=tuple(result.values()),
            )
        )
        self.assertIn("security-finding", [r.code for r in risk.holding(scored)])

    def test_a_critical_thread_the_pull_request_review_left_still_holds(self) -> None:
        # The pull_request review's own CRITICAL finding can only add a hold.
        threads = [
            thread(
                "severity: CRITICAL\nbad",
                author={"__typename": "Bot", "login": "claude"},
            )
        ]
        runs_review = main_review("claude-security-review")
        result = by_lane(
            ev.bind(
                S,
                [
                    whole("claude-review", S),
                    whole("claude-security-review", S, n=1, k=1),
                ],
                both_markers(),
                threads,
                is_human=is_human,
                changed_paths=(self.SOURCE,),
                head_file=fixed_head,
                main_reviews=[main_review("claude-review"), runs_review],
                main_context=recorded(
                    [main_review("claude-review"), runs_review], CONTEXT
                ),
                floor=risk.floor_for(),
            )
        )
        security = result["claude-security-review"]
        self.assertTrue(security.bound)
        self.assertEqual(security.blocking_findings, 1)

    def test_a_critical_an_earlier_head_recorded_holds_after_a_clean_re_roll(
        self,
    ) -> None:
        # A whitespace push makes a new tree whose clean review would bind at
        # zero; the CRITICAL the record job left on the earlier head holds.
        context = dict(
            CONTEXT, carried_critical={"claude-review": 0, "claude-security-review": 2}
        )
        result = self.main_bind([main_review(lane) for lane in LANES], context=context)
        security = result["claude-security-review"]
        self.assertTrue(security.bound)
        self.assertEqual((security.open_findings, security.blocking_findings), (2, 2))
        scored = risk.score(
            risk.RiskInput(
                files=(),
                files_complete=True,
                max_changed_lines=None,
                high_paths=(),
                lanes=tuple(result.values()),
            )
        )
        self.assertIn(
            "security-finding",
            [r.code for r in risk.person_reasons(risk.holding(scored))],
        )

    def test_a_recorded_critical_holds_with_no_verdict_at_the_head(self) -> None:
        context = dict(
            CONTEXT, carried_critical={"claude-review": 0, "claude-security-review": 1}
        )
        security = self.main_bind([], context=context)["claude-security-review"]
        self.assertFalse(security.bound)
        self.assertEqual(security.blocking_findings, 1)

    def test_unread_recorded_counts_bind_no_lane(self) -> None:
        reviews = [main_review(lane) for lane in LANES]
        for carried in (
            None,
            {},
            {"claude-review": 0},
            {"claude-review": 0, "claude-security-review": -1},
        ):
            with self.subTest(carried):
                context = {k: v for k, v in CONTEXT.items() if k != "carried_critical"}
                if carried is not None:
                    context["carried_critical"] = carried
                result = self.main_bind(reviews, context=context)
                self.assertUnbound(
                    result["claude-security-review"], "lane-source-changed"
                )

    def test_a_retargeted_pull_request_still_binds_nothing(self) -> None:
        result = by_lane(
            ev.bind(
                S,
                [],
                [],
                [],
                is_human=is_human,
                base_changed=True,
                changed_paths=(self.SOURCE,),
                main_reviews=[main_review(lane) for lane in LANES],
                main_context=recorded([main_review(lane) for lane in LANES], CONTEXT),
                floor=risk.floor_for(),
            )
        )
        for lane in LANES:
            self.assertUnbound(result[lane], "base-retargeted")

    def test_a_clean_main_run_review_makes_an_ordinary_workflow_edit_mergeable(
        self,
    ) -> None:
        # End to end through the scorer: a workflow edit that adds no write
        # scope, trigger or secret, off the gate, merges on a clean review.
        result = self.main_bind([main_review(lane) for lane in LANES])
        text = "name: deploy\non: push\npermissions: {}\njobs:\n  a:\n    runs-on: ubuntu-24.04\n"
        changed = risk.ChangedFile(
            path=self.SOURCE,
            previous_path=None,
            status="modified",
            additions=1,
            deletions=1,
            has_patch=True,
            mode="100644",
            previous_mode="100644",
            patch="@@ -1,1 +1,1 @@\n-name: old\n+name: deploy",
            contents=(text.replace("deploy", "old", 1), text),
        )
        scored = risk.score(
            risk.RiskInput(
                files=(changed,),
                files_complete=True,
                max_changed_lines=1000,
                high_paths=(),
                lanes=tuple(result.values()),
                public=True,
            )
        )
        self.assertEqual(risk.holding(scored), [], scored.reasons)
        unbound = self.main_bind(None)
        scored = risk.score(
            risk.RiskInput(
                files=(changed,),
                files_complete=True,
                max_changed_lines=1000,
                high_paths=(),
                lanes=tuple(unbound.values()),
                public=True,
            )
        )
        self.assertTrue(risk.holds(scored))

    def test_needs_main_review_matches_what_bind_reads(self) -> None:
        self.assertTrue(ev.needs_main_review([self.SOURCE], fixed_head, None, FLOOR))
        self.assertTrue(ev.needs_main_review(None, fixed_head, None, FLOOR))
        self.assertTrue(ev.needs_main_review(["CLAUDE.md"], fixed_head, None, FLOOR))
        self.assertFalse(ev.needs_main_review(["app.py"], fixed_head, None, FLOOR))
        self.assertFalse(ev.needs_main_review([], fixed_head, None, FLOOR))


class RunSelectionTests(Base):
    def test_both_lanes_whole_reviews_bind(self) -> None:
        result = self.bind([whole(lane, S) for lane in LANES])
        self.assertEqual([r.bound for r in result.values()], [True, True])

    def test_result_has_one_entry_per_lane_in_order(self) -> None:
        result = ev.bind(S, [], [], [], is_human=is_human, changed_paths=(), floor=risk.floor_for())
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

    def test_second_attempt_after_a_credential_failure(self) -> None:
        first = attempt("claude-review", S, 1, [AUTH_FAILURE], "failure")
        result = self.bind([self.lane_run(first, self.ok(2))])
        self.assertTrue(result["claude-review"].bound)

    def test_a_warning_level_auth_does_not_bind(self) -> None:
        # publish.cjs warns `<lane> key: class=auth` when the key leg's
        # credential is refused, whatever the run then failed on; only a
        # failure-level line names why the run failed.
        timeout = dict(
            OTHER_FAILURE,
            message="claude-review: failure-class=timeout:"
            " the review leg reached its time limit",
        )
        for message in (
            "claude-review key: class=auth: the API refused the key;"
            " the owner must replace the secret.",
            AUTH_FAILURE["message"],
        ):
            with self.subTest(message=message):
                warning = dict(
                    AUTH_FAILURE, annotation_level="warning", message=message
                )
                first = attempt("claude-review", S, 1, [warning, timeout], "failure")
                result = self.bind([self.lane_run(first, self.ok(2))])
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_an_auth_lookalike_does_not_bind(self) -> None:
        for message in (
            "claude-review: failure-class=auth-x: something else",
            "claude-review: failure-class=other: an unclassified failure"
            " (detail quoting failure-class=auth: rejected)",
            "security-review: failure-class=auth: another lane's credential",
        ):
            with self.subTest(message=message):
                first = attempt(
                    "claude-review",
                    S,
                    1,
                    [dict(AUTH_FAILURE, message=message)],
                    "failure",
                )
                result = self.bind([self.lane_run(first, self.ok(2))])
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_credential_failure_is_not_a_rate_limit(self) -> None:
        self.assertEqual(
            ev.rerun_classes("claude-review", {"annotations": [AUTH_FAILURE]}),
            {"auth"},
        )

    def test_second_attempt_after_an_install_failure(self) -> None:
        first = attempt("claude-review", S, 1, [INSTALL_FAILURE], "failure")
        result = self.bind([self.lane_run(first, self.ok(2))])
        self.assertTrue(result["claude-review"].bound)

    def test_an_install_failure_lookalike_does_not_bind(self) -> None:
        for message in (
            "claude-review: failure-class=install-failed-x: something else",
            "claude-review: failure-class=other: an unclassified failure"
            " (detail quoting failure-class=install-failed: failed)",
            "claude-security-review: failure-class=install-failed: another lane",
            # The older reusables' status line names no lane.
            "failure-class=install-failed: the subprocess isolation failed",
        ):
            with self.subTest(message=message):
                first = attempt(
                    "claude-review",
                    S,
                    1,
                    [dict(INSTALL_FAILURE, message=message)],
                    "failure",
                )
                result = self.bind([self.lane_run(first, self.ok(2))])
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_third_attempt_after_an_install_failure_is_not_allowed(self) -> None:
        first = attempt("claude-review", S, 1, [INSTALL_FAILURE], "failure")
        second = attempt("claude-review", S, 2, [INSTALL_FAILURE], "failure")
        result = self.bind([self.lane_run(first, second, self.ok(3))])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_second_attempt_after_a_publish_rate_limit_failure(self) -> None:
        first = attempt("claude-review", S, 1, [PUBLISH_RATE_LIMIT], "failure")
        result = self.bind([self.lane_run(first, self.ok(2))])
        self.assertTrue(result["claude-review"].bound)

    def test_second_attempt_after_a_publish_secondary_rate_limit_failure(self) -> None:
        limited = publish_failed(
            "You have exceeded a secondary rate limit. Please wait a few minutes"
            " before you try again."
        )
        first = attempt("claude-review", S, 1, [limited], "failure")
        result = self.bind([self.lane_run(first, self.ok(2))])
        self.assertTrue(result["claude-review"].bound)

    def test_second_attempt_after_another_publish_failure(self) -> None:
        for detail in (
            "Validation Failed",
            "Not Found; the reviewer also logged API rate limit exceeded",
            "the publish gate could not be loaded",
        ):
            with self.subTest(detail=detail):
                first = attempt(
                    "claude-review", S, 1, [publish_failed(detail)], "failure"
                )
                result = self.bind([self.lane_run(first, self.ok(2))])
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_publish_rate_limit_line_below_the_first_line(self) -> None:
        quoted = dict(
            OTHER_FAILURE,
            message="failure-class=incomplete: no review; the log quoted\n"
            + PUBLISH_RATE_LIMIT["message"],
        )
        first = attempt("claude-review", S, 1, [quoted], "failure")
        result = self.bind([self.lane_run(first, self.ok(2))])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_publish_rate_limit_line_of_another_lane(self) -> None:
        other_lane = dict(
            PUBLISH_RATE_LIMIT,
            message=PUBLISH_RATE_LIMIT["message"].replace(
                "claude-review:", "claude-security-review:", 1
            ),
        )
        first = attempt("claude-review", S, 1, [other_lane], "failure")
        result = self.bind([self.lane_run(first, self.ok(2))])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_rate_limit_text_outside_a_publish_failure_line(self) -> None:
        other = dict(
            OTHER_FAILURE,
            message="failure-class=incomplete: no review (API rate limit exceeded)",
        )
        first = attempt("claude-review", S, 1, [other], "failure")
        result = self.bind([self.lane_run(first, self.ok(2))])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

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

    def test_every_rerun_the_gate_starts_binds(self) -> None:
        # The merge gate re-runs a review only on `GATE_RERUN_CLASSES`
        # (babysit_merge.rerun_rate_limited_review); each such re-run must
        # bind, or the gate spends the one allowed attempt for nothing.
        # `LOST` is a conclusion, not an annotation (LostRerunTests).
        self.assertLessEqual(ev.GATE_RERUN_CLASSES, {*ev.RERUN_CLASSES, ev.LOST})
        notes = {
            "rate-limit": RATE_LIMIT,
            "publish-rate-limit": PUBLISH_RATE_LIMIT,
            ev.INSTALL_FAILED: INSTALL_FAILURE,
        }
        self.assertEqual({*notes, ev.LOST}, ev.GATE_RERUN_CLASSES)
        for name, note in notes.items():
            with self.subTest(name):
                first = attempt("claude-review", S, 1, [note], "failure")
                self.assertEqual(
                    ev.rerun_classes("claude-review", first["jobs"][0]), {name}
                )
                result = self.bind([self.lane_run(first, self.ok(2))])
                self.assertTrue(result["claude-review"].bound)


# After the pinned head's markers (both_markers), as an earlier run's would be.
FIRST_STARTED = "2026-01-01T00:10:00Z"
SECOND_STARTED = "2026-01-01T02:00:00Z"


def lost(
    lane: str = "claude-review",
    conclusion: str = "cancelled",
    *,
    lane_job: bool = True,
    annotations: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Attempt 1 an outage lost: with its lane job cut short, or (no
    `lane_job`, as a run that never started) with no job at all."""
    first = attempt(lane, S, 1, annotations or [], conclusion)
    first["run_started_at"] = FIRST_STARTED
    if not lane_job:
        first["jobs"] = []
    return first


def rerun_ok(lane: str = "claude-review") -> dict[str, Any]:
    second = attempt(lane, S, 2, [record(lane, S, "findings=0 inline=0 scope=whole")])
    second["run_started_at"] = SECOND_STARTED
    return second


class LostRerunTests(Base):
    """Attempt 2 after an attempt 1 an outage lost (#8524) binds only when
    attempt 1 reached no side effect on the head."""

    def lane_run(self, *attempts: dict[str, Any]) -> dict[str, Any]:
        return run("claude-review", S, attempts=list(attempts))

    def comment(self, at: str, body: str) -> dict[str, Any]:
        return {
            "id": next(_ids),
            "user": {"login": "github-actions[bot]", "type": "Bot"},
            "created_at": at,
            "edit": UNEDITED,
            "body": body,
        }

    def test_second_attempt_after_a_lost_first_binds(self) -> None:
        for conclusion in sorted(ev.LOST_CONCLUSIONS):
            for lane_job in (True, False):
                with self.subTest(conclusion=conclusion, lane_job=lane_job):
                    first = lost(conclusion=conclusion, lane_job=lane_job)
                    result = self.bind([self.lane_run(first, rerun_ok())])
                    self.assertTrue(result["claude-review"].bound)
                    self.assertEqual(result["claude-review"].open_findings, 0)

    def test_a_lost_first_that_recorded_a_review_does_not_bind(self) -> None:
        done = record("claude-review", S, "findings=0 inline=0 scope=whole")
        first = lost(annotations=[done])
        result = self.bind([self.lane_run(first, rerun_ok())])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_lost_first_whose_lane_job_ended_on_its_own_does_not_bind(self) -> None:
        # The run was lost, but its lane job had already failed on a class
        # outside RERUN_CLASSES, or succeeded: it judged the head.
        for conclusion, notes in (("failure", [OTHER_FAILURE]), ("success", [])):
            with self.subTest(conclusion=conclusion):
                first = lost(annotations=notes)
                first["jobs"][0]["conclusion"] = conclusion
                result = self.bind([self.lane_run(first, rerun_ok())])
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_lost_first_whose_lane_posted_does_not_bind(self) -> None:
        # Between the two attempts' starts: the marker, a summary comment, or
        # an inline thread of this lane.
        mark = dict(marker("claude-review", S), created_at="2026-01-01T00:40:00Z")
        summary = self.comment(
            "2026-01-01T00:45:00Z", "Summary\n\n`claude-lane: claude-review`"
        )
        posted = thread(created="2026-01-01T00:50:00Z")
        for comments, threads in (
            ([*both_markers(), mark], []),
            ([*both_markers(), summary], []),
            (both_markers(), [posted]),
        ):
            with self.subTest(comments=len(comments), threads=len(threads)):
                result = self.bind(
                    [self.lane_run(lost(), rerun_ok())], comments, threads
                )
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_what_the_lane_posted_outside_attempt_one_does_not_hold(self) -> None:
        # Attempt 2's own posts come after its start.
        late = self.comment(
            "2026-01-01T02:30:00Z", "Summary\n\n`claude-lane: claude-review`"
        )
        other_lane = self.comment(
            "2026-01-01T00:45:00Z", "Summary\n\n`claude-lane: claude-security-review`"
        )
        for comments in ([*both_markers(), late], [*both_markers(), other_lane]):
            with self.subTest(body=comments[-1]["body"][-30:]):
                result = self.bind([self.lane_run(lost(), rerun_ok())], comments, [])
                self.assertTrue(result["claude-review"].bound)

    def test_an_unreadable_start_does_not_bind(self) -> None:
        for first_start in (None, "x"):
            with self.subTest(first_start=first_start):
                first = lost()
                first["run_started_at"] = first_start
                result = self.bind([self.lane_run(first, rerun_ok())])
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_third_attempt_after_a_lost_first_is_not_allowed(self) -> None:
        second = lost()
        second.update(run_attempt=2, run_started_at="2026-01-01T01:00:00Z")
        second["jobs"][0]["run_attempt"] = 2
        third = rerun_ok()
        third["run_attempt"] = 3
        third["jobs"][0]["run_attempt"] = 3
        result = self.bind([self.lane_run(lost(), second, third)])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_lost_run_that_never_reached_its_lane_job_counts_nothing(self) -> None:
        # An earlier head's run lost before its lane job (no jobs listed)
        # neither unbinds the lane nor adds a finding.
        older = run("claude-review", S0, attempts=[lost(lane_job=False)])
        result = self.bind([older, whole("claude-review", S)])
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 0)

    def test_lane_posted_counts_unreadable_input_as_posted(self) -> None:
        for comments, threads in ((None, []), ([1], []), ([], None), ([], [1])):
            with self.subTest(comments=comments, threads=threads):
                self.assertTrue(
                    ev.lane_posted(
                        "claude-review", S, FIRST_STARTED, None, comments, threads
                    )
                )
        self.assertFalse(
            ev.lane_posted("claude-review", S, FIRST_STARTED, None, [], [])
        )

    def test_a_marker_rewritten_during_attempt_one_does_not_bind(self) -> None:
        # The producer edits one marker in place, so its creation predates
        # attempt 1; attempt 1's rewrite shows only as an edit, and attempt
        # 2's own rewrite, when it posts, comes after attempt 2's start.
        for edits in (
            ["2026-01-01T00:40:00Z"],
            ["2026-01-01T02:30:00Z", "2026-01-01T00:40:00Z"],
        ):
            with self.subTest(edits=edits):
                comments = edited_markers(*((at, S) for at in edits))
                result = self.bind([self.lane_run(lost(), rerun_ok())], comments, [])
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_marker_edits_outside_attempt_one_do_not_hold(self) -> None:
        comments = edited_markers(
            ("2026-01-01T02:30:00Z", S), ("2026-01-01T00:05:00Z", S)
        )
        result = self.bind([self.lane_run(lost(), rerun_ok())], comments, [])
        self.assertTrue(result["claude-review"].bound)

    def test_an_unprovable_marker_edit_counts_as_posted(self) -> None:
        # Edit record missing, history missing, incomplete or empty, a
        # revision unreadable or deleted.
        late = ("2026-01-01T02:30:00Z", S)
        cases: list[tuple[str, Any]] = [
            ("no edit record", None),
            ("no history", {"lastEditedAt": late[0], "editor": ACTIONS_BOT}),
        ]
        for name, change in (
            ("incomplete", lambda h: h.update(totalCount=2)),
            ("empty", lambda h: h.update(totalCount=0, nodes=[])),
            ("no time", lambda h: h["nodes"][0].pop("editedAt")),
            ("bad time", lambda h: h["nodes"][0].update(editedAt="x")),
            ("deleted", lambda h: h["nodes"][0].update(deletedAt=late[0])),
            ("no diff", lambda h: h["nodes"][0].pop("diff")),
        ):
            edit = edited_markers(late)[-1]["edit"]
            change(edit["history"])
            cases.append((name, edit))
        for name, edit in cases:
            with self.subTest(name):
                comments = edited_markers(late)
                if edit is None:
                    del comments[-1]["edit"]
                else:
                    comments[-1]["edit"] = edit
                self.assertTrue(
                    ev.lane_posted(
                        "claude-review", S, FIRST_STARTED, SECOND_STARTED,
                        comments, [],
                    )
                )  # fmt: skip

    def test_a_marker_rewritten_to_another_head_still_counts(self) -> None:
        # Attempt 1 wrote this head; a later review rewrote it to the next.
        comments = edited_markers(
            ("2026-01-01T02:30:00Z", S1), ("2026-01-01T00:40:00Z", S)
        )
        self.assertTrue(
            ev.lane_posted(
                "claude-review", S, FIRST_STARTED, SECOND_STARTED, comments, []
            )
        )
        other = edited_markers(
            ("2026-01-01T02:30:00Z", S1), ("2026-01-01T00:40:00Z", S0)
        )
        self.assertFalse(
            ev.lane_posted("claude-review", S, FIRST_STARTED, SECOND_STARTED, other, [])
        )


ACTIONS_BOT = {"__typename": "Bot", "login": "github-actions"}


def edited_markers(*edits: tuple[str, str]) -> list[dict[str, Any]]:
    """Both lanes' markers, claude-review's created before attempt 1 and
    edited in place at each (time, head) of `edits`, newest first, as the
    producer's `writeMarker` does; its body is the newest edit's."""
    found = [m for m in both_markers() if "lane=claude-review " not in m["body"]]
    nodes = [
        {
            "editedAt": at,
            "deletedAt": None,
            "editor": ACTIONS_BOT,
            "diff": marker("claude-review", sha)["body"],
        }
        for at, sha in edits
    ]
    mark = marker("claude-review", edits[0][1])
    mark["edit"] = {
        "lastEditedAt": edits[0][0],
        "editor": ACTIONS_BOT,
        "history": {"totalCount": len(nodes), "nodes": nodes},
    }
    return [*found, mark]


def no_outcome_line(lane: str) -> dict[str, Any]:
    """publish-review's failure line (ci-workflows publish.cjs `fail`) for a
    lane job that ended before it reported an outcome, as check run
    124930676685 recorded it."""
    return dict(
        OTHER_FAILURE,
        title="",
        message=f"{lane}: failure-class=no-outcome:"
        " the review job ended before it reported an outcome",
    )


def no_outcome(
    lane: str = "claude-review", annotations: list[dict[str, Any]] | None = None
) -> dict[str, Any]:
    first = attempt(
        lane,
        S,
        1,
        [no_outcome_line(lane)] if annotations is None else annotations,
        "failure",
    )
    first["run_started_at"] = FIRST_STARTED
    return first


class NoOutcomeRerunTests(Base):
    """Attempt 2 after an attempt 1 whose lane job ended before it reported an
    outcome binds only when that lane posted nothing on the head."""

    def test_second_attempt_after_an_unposted_no_outcome_binds(self) -> None:
        for lane in LANES:
            with self.subTest(lane=lane):
                item = run(lane, S, attempts=[no_outcome(lane), rerun_ok(lane)])
                result = self.bind([item])
                self.assertTrue(result[lane].bound)
                self.assertEqual(result[lane].open_findings, 0)

    def test_a_no_outcome_whose_lane_posted_does_not_bind(self) -> None:
        mark = dict(marker("claude-review", S), created_at="2026-01-01T00:40:00Z")
        summary = {
            "id": next(_ids),
            "user": {"login": "github-actions[bot]", "type": "Bot"},
            "created_at": "2026-01-01T00:45:00Z",
            "edit": UNEDITED,
            "body": "Summary\n\n`claude-lane: claude-review`",
        }
        posted = thread(created="2026-01-01T00:50:00Z")
        for comments, threads in (
            ([*both_markers(), mark], []),
            ([*both_markers(), summary], []),
            (both_markers(), [posted]),
        ):
            with self.subTest(comments=len(comments), threads=len(threads)):
                item = run("claude-review", S, attempts=[no_outcome(), rerun_ok()])
                result = self.bind([item], comments, threads)
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_no_outcome_whose_lane_rewrote_its_marker_does_not_bind(self) -> None:
        comments = edited_markers(
            ("2026-01-01T02:30:00Z", S), ("2026-01-01T00:40:00Z", S)
        )
        item = run("claude-review", S, attempts=[no_outcome(), rerun_ok()])
        result = self.bind([item], comments, [])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_no_outcome_that_recorded_a_review_does_not_bind(self) -> None:
        done = record("claude-review", S, "findings=0 inline=0 scope=whole")
        first = no_outcome(annotations=[no_outcome_line("claude-review"), done])
        result = self.bind([run("claude-review", S, attempts=[first, rerun_ok()])])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_another_lanes_no_outcome_line_does_not_count(self) -> None:
        first = no_outcome(annotations=[no_outcome_line("claude-security-review")])
        result = self.bind([run("claude-review", S, attempts=[first, rerun_ok()])])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_an_unreadable_start_does_not_bind(self) -> None:
        first = no_outcome()
        first["run_started_at"] = None
        result = self.bind([run("claude-review", S, attempts=[first, rerun_ok()])])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_third_attempt_after_a_no_outcome_is_not_allowed(self) -> None:
        second = no_outcome()
        second.update(run_attempt=2, run_started_at="2026-01-01T01:00:00Z")
        second["jobs"][0]["run_attempt"] = 2
        third = rerun_ok()
        third["run_attempt"] = 3
        third["jobs"][0]["run_attempt"] = 3
        item = run("claude-review", S, attempts=[no_outcome(), second, third])
        result = self.bind([item])
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_the_gate_does_not_rerun_a_no_outcome(self) -> None:
        # Binding only: a no-outcome from a lane defect fails every run until
        # the fix ships, so a gate re-run would spend the one allowed attempt.
        job = no_outcome()["jobs"][0]
        self.assertEqual(ev.rerun_classes("claude-review", job), frozenset())
        self.assertNotIn(ev.NO_OUTCOME, ev.GATE_RERUN_CLASSES)


# The caller workflows' `Report the kill switch` notice
# (pr-review-hosted.yml, pr-review-security-hosted.yml).
KILL_NOTICE = {
    "claude-review": "a kill switch stops this review"
    " (lanes: kill-switch, CLAUDE_REVIEW_DISABLED: false)",
    "claude-security-review": "a kill switch stops this security review"
    " (lanes: kill-switch, CLAUDE_SECURITY_REVIEW_DISABLED: false)",
}


def kill_switched(
    lane: str,
    sha: str = S,
    *,
    message: str | None = None,
    level: str = "notice",
    kill_conclusion: str = "success",
    kill_name: str = "kill-switch",
) -> dict[str, Any]:
    """Attempt 1 as #10092's review runs recorded it: the kill-switch job
    succeeded and wrote its notice, and the reusable's caller job was skipped,
    so no lane job exists."""
    caller = JOBS[lane].split(" / ", 1)[0]

    def job(name: str, conclusion: str, annotations: Any = None) -> dict[str, Any]:
        item = {
            "id": next(_ids),
            "run_attempt": 1,
            "name": name,
            "status": "completed",
            "conclusion": conclusion,
            "head_sha": sha,
        }
        if annotations is not None:
            item["annotations"] = annotations
        return item

    notice = {
        "path": ".github",
        "annotation_level": level,
        "title": "",
        "message": KILL_NOTICE[lane] if message is None else message,
    }
    return {
        "run_attempt": 1,
        "head_sha": sha,
        "status": "completed",
        "conclusion": "success",
        "jobs": [
            job(kill_name, kill_conclusion, [notice]),
            job("resolve-model", "success"),
            job(caller, "skipped"),
        ],
    }


class KillSwitchRerunTests(Base):
    """A re-run after a kill switch stopped attempt 1 (#10092, #10057): the
    review never started, so attempt 2 is the first review of the head."""

    def lane_run(self, lane: str, *attempts: dict[str, Any]) -> dict[str, Any]:
        return run(lane, S, attempts=list(attempts))

    def ok(self, lane: str, n: int = 2) -> dict[str, Any]:
        return attempt(lane, S, n, [record(lane, S, "findings=0 inline=0 scope=whole")])

    def test_second_attempt_after_a_kill_switch_stop_binds(self) -> None:
        for lane in LANES:
            with self.subTest(lane=lane):
                result = self.bind(
                    [self.lane_run(lane, kill_switched(lane), self.ok(lane))]
                )
                self.assertTrue(result[lane].bound)
                self.assertEqual(result[lane].open_findings, 0)

    def test_the_other_lanes_notice_does_not_bind(self) -> None:
        for lane, other in zip(LANES, reversed(LANES), strict=True):
            with self.subTest(lane=lane):
                first = kill_switched(lane, message=KILL_NOTICE[other])
                result = self.bind([self.lane_run(lane, first, self.ok(lane))])
                self.assertUnbound(result[lane], "rerun-not-allowed")

    def test_a_lookalike_notice_does_not_bind(self) -> None:
        for message in (
            "the log says: a kill switch stops this review (lanes: x)",
            "a kill switch stops this review",
            "A kill switch stops this review (lanes: x)",
        ):
            with self.subTest(message=message):
                first = kill_switched("claude-review", message=message)
                result = self.bind(
                    [self.lane_run("claude-review", first, self.ok("claude-review"))]
                )
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_notice_at_another_level_does_not_bind(self) -> None:
        for level in ("warning", "failure"):
            with self.subTest(level=level):
                first = kill_switched("claude-review", level=level)
                result = self.bind(
                    [self.lane_run("claude-review", first, self.ok("claude-review"))]
                )
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_the_notice_on_another_job_does_not_bind(self) -> None:
        first = kill_switched("claude-review", kill_name="resolve-model")
        result = self.bind(
            [self.lane_run("claude-review", first, self.ok("claude-review"))]
        )
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_kill_switch_job_that_did_not_succeed_does_not_bind(self) -> None:
        for conclusion in ("failure", "cancelled", "skipped"):
            with self.subTest(conclusion=conclusion):
                first = kill_switched("claude-review", kill_conclusion=conclusion)
                result = self.bind(
                    [self.lane_run("claude-review", first, self.ok("claude-review"))]
                )
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_two_kill_switch_jobs_do_not_bind(self) -> None:
        first = kill_switched("claude-review")
        first["jobs"].append(copy.deepcopy(first["jobs"][0]))
        first["jobs"][-1]["id"] = next(_ids)
        result = self.bind(
            [self.lane_run("claude-review", first, self.ok("claude-review"))]
        )
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_first_attempt_that_reviewed_never_rebinds(self) -> None:
        # The notice beside a lane job that ran: attempt 1 may hold a verdict.
        reviewed = self.ok("claude-review", 1)
        first = kill_switched("claude-review")
        first["jobs"].append(reviewed["jobs"][0])
        for conclusion in ("success", "failure"):
            with self.subTest(conclusion=conclusion):
                trial = copy.deepcopy(first)
                trial["conclusion"] = conclusion
                result = self.bind(
                    [self.lane_run("claude-review", trial, self.ok("claude-review"))]
                )
                self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_failed_first_attempt_with_the_notice_does_not_bind(self) -> None:
        first = kill_switched("claude-review")
        first["conclusion"] = "failure"
        result = self.bind(
            [self.lane_run("claude-review", first, self.ok("claude-review"))]
        )
        self.assertUnbound(result["claude-review"], "no-lane-job")

    def test_third_attempt_after_a_kill_switch_stop_is_never_allowed(self) -> None:
        stopped_again = kill_switched("claude-review")
        stopped_again["run_attempt"] = 2
        for item in stopped_again["jobs"]:
            item["run_attempt"] = 2
        result = self.bind(
            [
                self.lane_run(
                    "claude-review",
                    kill_switched("claude-review"),
                    stopped_again,
                    self.ok("claude-review", 3),
                )
            ]
        )
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_a_kill_switched_run_on_an_earlier_head_does_not_unbind(self) -> None:
        stopped = run(
            "claude-review", S0, attempts=[kill_switched("claude-review", S0)]
        )
        result = self.bind([stopped, whole("claude-review", S)])
        self.assertTrue(result["claude-review"].bound)

    def test_a_kill_switched_head_alone_does_not_bind(self) -> None:
        result = self.bind(
            [self.lane_run("claude-review", kill_switched("claude-review"))]
        )
        self.assertUnbound(result["claude-review"], "no-lane-job")

    def test_unread_kill_switch_annotations_are_missing_evidence(self) -> None:
        first = kill_switched("claude-review")
        del first["jobs"][0]["annotations"]
        result = self.bind(
            [self.lane_run("claude-review", first, self.ok("claude-review"))]
        )
        self.assertUnbound(result["claude-review"], "evidence-missing")

    def test_a_changed_caller_workflow_still_binds_no_lane(self) -> None:
        # The head's copy of a caller runs on pull_request, so a head that
        # edits one could write the notice itself; any such edit unbinds.
        runs = [
            self.lane_run(lane, kill_switched(lane), self.ok(lane)) for lane in LANES
        ]
        result = self.bind(runs, changed_paths=[FILES["claude-review"]])
        for lane in LANES:
            self.assertUnbound(result[lane], "lane-source-changed")


# The caller workflows' `Stop on upstream status` error (pr-review-hosted.yml,
# pr-review-security-hosted.yml), which fails the kill-switch job.
UPSTREAM_STOP = {
    "claude-review": "an upstream outage stops this review"
    " (Actions major_outage); the lost-run reconciler re-runs it",
    "claude-security-review": "an upstream outage stops this security review"
    " (Package installation partial_outage); the lost-run reconciler re-runs it",
}


def upstream_stopped(
    lane: str,
    sha: str = S,
    *,
    message: str | None = None,
    level: str = "failure",
    kill_conclusion: str = "failure",
) -> dict[str, Any]:
    """Attempt 1 when the upstream gate stopped it: the kill-switch job
    failed at `Stop on upstream status` with its error, the run failed, and
    the reusable's caller job was skipped, so no lane job exists."""
    first = kill_switched(
        lane,
        sha,
        message=UPSTREAM_STOP[lane] if message is None else message,
        level=level,
        kill_conclusion=kill_conclusion,
    )
    first["conclusion"] = "failure"
    return first


class UpstreamDegradedRerunTests(Base):
    """A re-run after the upstream gate stopped attempt 1: the review never
    started, so attempt 2 is the first review of the head."""

    def lane_run(self, lane: str, *attempts: dict[str, Any]) -> dict[str, Any]:
        return run(lane, S, attempts=list(attempts))

    def ok(self, lane: str, n: int = 2) -> dict[str, Any]:
        return attempt(lane, S, n, [record(lane, S, "findings=0 inline=0 scope=whole")])

    def test_second_attempt_after_an_upstream_stop_binds(self) -> None:
        for lane in LANES:
            with self.subTest(lane=lane):
                result = self.bind(
                    [self.lane_run(lane, upstream_stopped(lane), self.ok(lane))]
                )
                self.assertTrue(result[lane].bound)
                self.assertEqual(result[lane].open_findings, 0)

    def test_the_class_is_named(self) -> None:
        self.assertEqual(ev.UPSTREAM_DEGRADED, "upstream-degraded")

    def test_an_unrelated_kill_switch_failure_does_not_bind(self) -> None:
        for message in (
            "Process completed with exit code 1.",
            UPSTREAM_STOP["claude-security-review"],
            "the log says: an upstream outage stops this review (x)",
            KILL_NOTICE["claude-review"],
        ):
            with self.subTest(message=message):
                first = upstream_stopped("claude-review", message=message)
                result = self.bind(
                    [self.lane_run("claude-review", first, self.ok("claude-review"))]
                )
                self.assertUnbound(result["claude-review"], "no-lane-job")

    def test_the_error_at_another_level_does_not_bind(self) -> None:
        for level in ("notice", "warning"):
            with self.subTest(level=level):
                first = upstream_stopped("claude-review", level=level)
                result = self.bind(
                    [self.lane_run("claude-review", first, self.ok("claude-review"))]
                )
                self.assertUnbound(result["claude-review"], "no-lane-job")

    def test_the_error_on_a_kill_switch_job_that_succeeded_does_not_bind(self) -> None:
        first = upstream_stopped("claude-review", kill_conclusion="success")
        result = self.bind(
            [self.lane_run("claude-review", first, self.ok("claude-review"))]
        )
        self.assertUnbound(result["claude-review"], "no-lane-job")

    def test_a_lane_job_failure_of_another_class_does_not_bind(self) -> None:
        failed = attempt("claude-review", S, 1, [])
        failed["conclusion"] = "failure"
        failed["jobs"][0]["conclusion"] = "failure"
        failed["jobs"][0]["annotations"] = [
            {
                "path": ".github",
                "annotation_level": "failure",
                "title": "",
                "message": UPSTREAM_STOP["claude-review"],
            }
        ]
        result = self.bind(
            [self.lane_run("claude-review", failed, self.ok("claude-review"))]
        )
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_the_error_beside_a_lane_job_does_not_bind(self) -> None:
        first = upstream_stopped("claude-review")
        first["jobs"].append(self.ok("claude-review", 1)["jobs"][0])
        result = self.bind(
            [self.lane_run("claude-review", first, self.ok("claude-review"))]
        )
        self.assertUnbound(result["claude-review"], "rerun-not-allowed")

    def test_unread_kill_switch_annotations_are_missing_evidence(self) -> None:
        first = upstream_stopped("claude-review")
        del first["jobs"][0]["annotations"]
        result = self.bind(
            [self.lane_run("claude-review", first, self.ok("claude-review"))]
        )
        self.assertUnbound(result["claude-review"], "evidence-missing")

    def test_an_upstream_stopped_head_alone_does_not_bind(self) -> None:
        result = self.bind(
            [self.lane_run("claude-review", upstream_stopped("claude-review"))]
        )
        self.assertUnbound(result["claude-review"], "run-not-success")

    def test_a_changed_caller_workflow_still_binds_no_lane(self) -> None:
        runs = [
            self.lane_run(lane, upstream_stopped(lane), self.ok(lane)) for lane in LANES
        ]
        result = self.bind(runs, changed_paths=[FILES["claude-review"]])
        for lane in LANES:
            self.assertUnbound(result[lane], "lane-source-changed")


class RecordTests(Base):
    def test_no_completion_record(self) -> None:
        result = self.bind([run("claude-review", S)])
        self.assertUnbound(result["claude-review"], "no-record")

    def test_a_subscription_leg_record_binds(self) -> None:
        # ci-workflows pr-review-cli.yml ends the record ` account=fallback`
        # when the subscription leg reviewed (publish-review publish.cjs).
        # Both lanes run on it.
        for lane, other in (LANES, LANES[::-1]):
            with self.subTest(lane=lane):
                tail = "findings=0 inline=0 scope=whole account=fallback"
                runs = [whole(other, S), run(lane, S, tail)]
                result = self.bind(runs)[lane]
                self.assertTrue(result.bound)
                self.assertEqual(result.open_findings, 0)

    def test_another_account_suffix_is_malformed(self) -> None:
        for tail in (
            "findings=0 inline=0 scope=whole account=primary",
            "findings=0 inline=0 scope=whole account=fallback extra",
        ):
            with self.subTest(tail=tail):
                result = self.bind([run("claude-review", S, tail)])
                self.assertUnbound(result["claude-review"], "record-malformed")

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

    def test_two_clean_base_merges_carry_the_review_forward(self) -> None:
        # Each merge-only push skips through the head before it, so the chain
        # reaches the review two hops back and scores as that review did.
        runs = [
            run("claude-review", S1, "findings=3 inline=1 scope=whole"),
            run("claude-review", S0, f"skip=no-change through={S1}"),
            run("claude-review", S, f"skip=no-change through={S0}"),
        ]
        result = self.bind(runs, threads=[thread()])
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 3)

    def test_three_clean_base_merges_carry_the_review_forward(self) -> None:
        s2 = "c2" * 20
        runs = [
            run("claude-review", s2, "findings=2 inline=0 scope=whole"),
            run("claude-review", S1, f"skip=no-change through={s2}"),
            run("claude-review", S0, f"skip=no-change through={S1}"),
            run("claude-review", S, f"skip=no-change through={S0}"),
        ]
        result = self.bind(runs)
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 2)

    def skip_chain(self, heads: int) -> list[dict[str, Any]]:
        """S skips through `heads` earlier heads; the last is a whole review."""
        shas = [f"{i:040x}" for i in range(1, heads + 1)]
        runs = [run("claude-review", shas[-1], "findings=0 inline=0 scope=whole")]
        runs += [
            run("claude-review", sha, f"skip=no-change through={nxt}")
            for sha, nxt in zip(shas, shas[1:])
        ]
        return [*runs, run("claude-review", S, f"skip=no-change through={shas[0]}")]

    def test_skip_chain_binds_at_the_hop_cap(self) -> None:
        # ci-status follows the same cap (pr-require-checks.yml `carried`).
        self.assertEqual(ev.SKIP_HOPS, 10)
        self.assertTrue(self.bind(self.skip_chain(10))["claude-review"].bound)

    def test_skip_chain_past_the_hop_cap_is_unbound(self) -> None:
        self.assertUnbound(
            self.bind(self.skip_chain(11))["claude-review"], "incremental-gap"
        )

    def test_a_merge_that_changed_content_is_reviewed_not_carried(self) -> None:
        # S0 merged the base and changed content, so its lane reviewed it
        # (incremental) rather than skipping; the clean merge after it carries
        # that fresh review forward, and its findings count.
        s2 = "c2" * 20
        runs = [
            run("claude-review", s2, "findings=1 inline=0 scope=whole"),
            run("claude-review", S1, f"skip=no-change through={s2}"),
            run(
                "claude-review", S0, f"findings=2 inline=0 scope=incremental since={S1}"
            ),
            run("claude-review", S, f"skip=no-change through={S0}"),
        ]
        result = self.bind(runs)
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 3)

    def test_a_merge_that_changed_content_with_no_review_is_unbound(self) -> None:
        # S0 changed content and its lane run failed, so no review covers it:
        # the clean merge after it cannot carry an older review past it.
        failed = run(
            "claude-review",
            S0,
            attempts=[attempt("claude-review", S0, 1, [OTHER_FAILURE], "failure")],
        )
        runs = [
            run("claude-review", S1, "findings=0 inline=0 scope=whole"),
            failed,
            run("claude-review", S, f"skip=no-change through={S0}"),
        ]
        self.assertUnbound(self.bind(runs)["claude-review"], "incremental-gap")

    def test_skip_chain_ending_in_a_docs_only_skip_is_unbound(self) -> None:
        runs = [
            run("claude-review", S1, "skip=docs-only"),
            run("claude-review", S0, f"skip=no-change through={S1}"),
            run("claude-review", S, f"skip=no-change through={S0}"),
        ]
        self.assertUnbound(self.bind(runs)["claude-review"], "skip-not-no-change")

    def test_skip_chain_cycle_is_unbound(self) -> None:
        runs = [
            run("claude-review", S0, f"skip=no-change through={S}"),
            run("claude-review", S, f"skip=no-change through={S0}"),
        ]
        self.assertUnbound(self.bind(runs)["claude-review"], "incremental-gap")

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
        self,
        earlier: str,
        latest: str,
        *,
        earlier_sha: str = S0,
        tree: str | None = None,
    ) -> list[dict[str, Any]]:
        # An earlier review in the 00:00-01:00 window, the latest in 02:00-03:00,
        # of the pinned head, whose tree is `tree` when given.
        runs = [
            run("claude-review", earlier_sha, earlier, created="2026-01-01T00:00:00Z"),
            run("claude-review", S, latest, created="2026-01-01T02:00:00Z", tree=tree),
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

    def test_threadless_inline_finding_of_the_other_kind_at_the_head_counts(
        self,
    ) -> None:
        # At S: a whole review left a thread-less inline finding, then the
        # newest run, a clean incremental review back to the whole one at S0.
        # A later review of the same head never clears it.
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
        self.assertEqual(self.bind(runs, threads=[])["claude-review"].open_findings, 1)

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

    def incremental_then_whole(
        self,
        incremental_sha: str,
        counts: str = "findings=1 inline=1",
        *,
        tree: str | None = None,
    ) -> list[dict[str, Any]]:
        # A clean whole review at S0 (00:00-01:00); an incremental review at
        # `incremental_sha` raised one finding (02:00-03:00), inline by
        # default; then a clean whole review of the pinned head S (04:00-05:00),
        # whose tree is `tree` when given.
        return [
            whole("claude-review", S0),
            windowed(
                run(
                    "claude-review",
                    incremental_sha,
                    f"{counts} scope=incremental since={S0}",
                    created="2026-01-01T02:00:00Z",
                ),
                "2026-01-01T02:00:00Z",
                "2026-01-01T03:00:00Z",
            ),
            windowed(
                run(
                    "claude-review",
                    S,
                    "findings=0 inline=0 scope=whole",
                    created="2026-01-01T04:00:00Z",
                    tree=tree,
                ),
                "2026-01-01T04:00:00Z",
                "2026-01-01T05:00:00Z",
            ),
        ]

    def incremental_thread(self) -> list[dict[str, Any]]:
        return [
            thread(
                resolved=True, resolved_by=self.PUSHER, created="2026-01-01T02:30:00Z"
            )
        ]

    def test_a_clean_whole_rerun_does_not_clear_an_incremental_finding_at_the_head(
        self,
    ) -> None:
        # Owner decision 2026-10-20: a finding any review of a head reported
        # clears only by a new head or a human; re-running the review of the
        # same head until it comes back clean does not clear it.
        runs = self.incremental_then_whole(S)
        result = self.bind(runs, threads=self.incremental_thread())
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_a_clean_whole_review_of_a_new_head_clears_an_incremental_finding(
        self,
    ) -> None:
        runs = self.incremental_then_whole(S1)
        result = self.bind(runs, threads=self.incremental_thread())
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 0)

    def test_a_clean_whole_rerun_keeps_an_incremental_summary_finding_at_the_head(
        self,
    ) -> None:
        runs = self.incremental_then_whole(S, "findings=1 inline=0")
        result = self.bind(runs, threads=[])
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_a_clean_whole_rerun_keeps_an_incremental_threadless_finding_at_the_head(
        self,
    ) -> None:
        runs = self.incremental_then_whole(S)
        result = self.bind(runs, threads=[])
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_a_clean_whole_review_of_a_new_head_clears_an_incremental_summary_finding(
        self,
    ) -> None:
        runs = self.incremental_then_whole(S1, "findings=1 inline=0")
        result = self.bind(runs, threads=[])
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 0)

    # #8638: a head is new for closure only when its tree changed, so an
    # empty commit (new sha, same tree) cannot re-roll the review.

    def test_a_clean_whole_review_of_an_empty_commit_keeps_an_incremental_finding(
        self,
    ) -> None:
        runs = self.incremental_then_whole(S1, tree=tree_of(S1))
        result = self.bind(runs, threads=self.incremental_thread())
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_a_clean_whole_review_of_an_empty_commit_keeps_a_summary_finding(
        self,
    ) -> None:
        runs = self.incremental_then_whole(S1, "findings=1 inline=0", tree=tree_of(S1))
        result = self.bind(runs, threads=[])
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 1)

    def test_a_clean_whole_review_of_an_empty_commit_keeps_a_whole_reviews_findings(
        self,
    ) -> None:
        empty = self.two_reviews(
            "findings=1 inline=1 scope=whole",
            "findings=0 inline=0 scope=whole",
            tree=tree_of(S0),
        )
        result = self.bind(empty, threads=self.agent_resolved())
        self.assertEqual(result["claude-review"].open_findings, 1)
        threadless = self.two_reviews(
            "findings=2 inline=1 scope=whole",
            "findings=0 inline=0 scope=whole",
            tree=tree_of(S0),
        )
        self.assertEqual(
            self.bind(threadless, threads=[])["claude-review"].open_findings, 2
        )

    def test_a_clean_whole_review_of_a_changed_tree_clears_the_finding(
        self,
    ) -> None:
        runs = self.two_reviews(
            "findings=2 inline=1 scope=whole",
            "findings=0 inline=0 scope=whole",
            tree="7e" * 20,
        )
        result = self.bind(runs, threads=self.agent_resolved())
        self.assertTrue(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].open_findings, 0)

    def test_a_reviewed_run_with_no_readable_tree_unbinds(self) -> None:
        for commit in (None, {"id": S}, {"id": S, "tree_id": "not-a-sha"}):
            with self.subTest(commit=commit):
                runs = self.two_reviews(
                    "findings=1 inline=1 scope=whole", "findings=0 inline=0 scope=whole"
                )
                runs[1]["head_commit"] = commit
                result = self.bind(runs, threads=self.agent_resolved())
                self.assertUnbound(result["claude-review"], "tree-unread")

    def test_two_trees_for_one_head_unbind(self) -> None:
        runs = self.two_reviews(
            "findings=1 inline=1 scope=whole",
            "findings=0 inline=0 scope=whole",
            earlier_sha=S,
        )
        runs[1]["head_commit"] = {"id": S, "tree_id": "7e" * 20}
        result = self.bind(runs, threads=self.agent_resolved())
        self.assertUnbound(result["claude-review"], "evidence-error")

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
        runs[1]["head_commit"] = {"id": S1, "tree_id": tree_of(S1)}
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
                S, runs, [None], [None], is_human=is_human, changed_paths=(), floor=risk.floor_for())  # type: ignore[arg-type]
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
            floor=risk.floor_for(),
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
            floor=risk.floor_for(),
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
            floor=risk.floor_for(),
        )
        self.assertFalse(result[0].bound)


class CarriedBlockingTests(Base):
    """A blocking security finding a bound review left open still holds after
    the lane unbinds: the binder carries the count from the newest head of
    the pull request the lane's evidence binds at, so the gate's person
    routing (babysit_risk.person_reasons) still sees `security-finding`."""

    SEC = "claude-security-review"
    S2 = "c2" * 20  # a newer head

    def critical_at_s(self) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        runs = [whole("claude-review", S), whole(self.SEC, S, n=1, k=1)]
        body = f"finding\n\nseverity: CRITICAL\n`claude-lane: {self.SEC}`"
        return runs, [thread(body)]

    def person(self, lanes: dict[str, Any]) -> list[str]:
        result = risk.score(
            risk.RiskInput(
                files=(
                    risk.ChangedFile(
                        "docs/a.md", None, "modified", 1, 1, True, "100644", "100644"
                    ),
                ),
                files_complete=True,
                max_changed_lines=None,
                high_paths=(),
                lanes=tuple(lanes[lane] for lane in LANES),
                lines_optional=True,
            )
        )
        return [r.code for r in risk.person_reasons(risk.holding(result))]

    def test_a_bound_critical_finding_holds_for_a_person(self) -> None:
        runs, threads = self.critical_at_s()
        bound = self.bind(runs, threads=threads)
        self.assertEqual(bound[self.SEC].blocking_findings, 1)
        self.assertEqual(self.person(bound), ["security-finding"])

    def test_a_retargeted_base_carries_the_critical_finding(self) -> None:
        runs, threads = self.critical_at_s()
        lanes = by_lane(
            ev.bind(
                S,
                runs,
                both_markers(),
                threads,
                is_human=is_human,
                head_file=fixed_head,
                changed_paths=(),
                base_changed=True,
                floor=risk.floor_for(),
            )
        )
        self.assertUnbound(lanes[self.SEC], "base-retargeted")
        self.assertEqual(lanes[self.SEC].blocking_findings, 1)
        self.assertEqual(self.person(lanes), ["security-finding"])

    def test_a_new_head_carries_the_critical_finding(self) -> None:
        # A push to S2: no review there yet, or one that failed and wrote a
        # newer marker. Either way the review at S still leaves it open.
        runs, threads = self.critical_at_s()
        failed = run(
            self.SEC,
            self.S2,
            attempts=[attempt(self.SEC, self.S2, 1, [], "failure")],
            created="2026-01-02T00:00:00Z",
        )
        # Later than every marker at S, so it is the lane's newest.
        newer = {**marker(self.SEC, self.S2), "created_at": "2026-01-02T01:00:00Z"}
        for name, extra_runs, extra_markers in (
            ("no review yet", [], []),
            ("a newer marker on a failed review", [failed], [newer]),
        ):
            with self.subTest(name):
                lanes = by_lane(
                    ev.bind(
                        self.S2,
                        [*runs, *extra_runs],
                        [*both_markers(), *extra_markers],
                        threads,
                        is_human=is_human,
                        head_file=fixed_head,
                        changed_paths=(),
                        floor=risk.floor_for(),
                    )
                )
                self.assertFalse(lanes[self.SEC].bound)
                self.assertEqual(lanes[self.SEC].blocking_findings, 1)
                self.assertEqual(self.person(lanes), ["security-finding"])

    def test_an_older_marker_naming_a_head_is_read_only_off_the_newest(
        self,
    ) -> None:
        older = marker(self.SEC, S)
        newer = {**marker(self.SEC, self.S2), "created_at": "2026-01-02T01:00:00Z"}
        comments = [newer, older]
        with self.assertRaises(ev.Unbound):
            ev._require_marker(self.SEC, S, comments)
        self.assertEqual(
            ev._require_marker(self.SEC, S, comments, newest_only=False),
            older["body"],
        )

    def test_nothing_is_carried_without_a_blocking_finding(self) -> None:
        runs = [whole("claude-review", S), whole(self.SEC, S, n=1, k=1)]
        body = f"finding\n\nseverity: SUGGESTION\n`claude-lane: {self.SEC}`"
        lanes = by_lane(
            ev.bind(
                self.S2,
                runs,
                both_markers(),
                [thread(body)],
                is_human=is_human,
                head_file=fixed_head,
                changed_paths=(),
                floor=risk.floor_for(),
            )
        )
        self.assertIsNone(lanes[self.SEC].blocking_findings)
        self.assertEqual(self.person(lanes), [])


class SeverityTests(Base):
    """The security lane's blocking count holds only its CRITICAL findings;
    a finding of unreadable severity counts as CRITICAL."""

    SEC = "claude-security-review"

    def comment(self, severity: str | None) -> str:
        line = f"severity: {severity}\n" if severity else ""
        return f"finding\n\n{line}`claude-lane: {self.SEC}`"

    def summary_markers(self, text: str) -> list[dict[str, Any]]:
        found = both_markers()
        for item in found:
            if f"lane={self.SEC}" in item["body"]:
                item["body"] += f"\n\n{text}"
        return found

    def test_inline_findings_block_by_severity(self) -> None:
        for severity, blocking in (
            ("IMPORTANT", 0),
            ("SUGGESTION", 0),
            ("CRITICAL", 1),
            (None, 1),
        ):
            with self.subTest(severity=severity):
                runs = [whole("claude-review", S), whole(self.SEC, S, n=1, k=1)]
                threads = [thread(self.comment(severity))]
                result = self.bind(runs, threads=threads)[self.SEC]
                self.assertEqual(result.open_findings, 1)
                self.assertEqual(result.blocking_findings, blocking)

    def test_each_severity_holds_or_is_reported_through_the_score(self) -> None:
        # Q33: only the lane's top tier (CRITICAL, SKILL.md "Reporting") holds;
        # a line the gate cannot read, a missing one or a word outside the
        # lane's vocabulary holds too (fail closed). Every finding appears in
        # the reasons.
        for severity, held in (
            ("SUGGESTION", False),
            ("IMPORTANT", False),
            ("CRITICAL", True),
            (None, True),
            ("LOW", True),
            ("MEDIUM", True),
            ("HIGH", True),
        ):
            with self.subTest(severity=severity):
                runs = [whole("claude-review", S), whole(self.SEC, S, n=1, k=1)]
                lanes = tuple(
                    self.bind(runs, threads=[thread(self.comment(severity))]).values()
                )
                result = risk.score(
                    risk.RiskInput(
                        files=(
                            risk.ChangedFile(
                                "plugins/foo/a.md", None, "added", 1, 0, True, "100644"
                            ),
                        ),  # fmt: skip
                        files_complete=True,
                        max_changed_lines=200,
                        high_paths=(),
                        lanes=lanes,
                    )
                )
                codes = [r.code for r in result.reasons]
                self.assertEqual(risk.holds(result), held, result.reasons)
                self.assertEqual(
                    codes,
                    ["security-finding"]
                    if held
                    else ["findings:claude-security-review"],
                )

    def test_two_severity_lines_count_as_critical(self) -> None:
        body = self.comment("IMPORTANT").replace(
            "severity: IMPORTANT", "severity: IMPORTANT\nseverity: SUGGESTION"
        )
        runs = [whole("claude-review", S), whole(self.SEC, S, n=1, k=1)]
        result = self.bind(runs, threads=[thread(body)])[self.SEC]
        self.assertEqual(result.blocking_findings, 1)

    def test_summary_findings_block_by_the_critical_line(self) -> None:
        runs = [whole("claude-review", S), whole(self.SEC, S, n=3, k=0)]
        for text, blocking in (
            ("critical-findings: 0", 0),
            ("critical-findings: 2", 2),
            ("critical-findings: 9", 3),
            ("no line", 3),
            ("critical-findings: 0\ncritical-findings: 0", 3),
        ):
            with self.subTest(text=text):
                result = self.bind(runs, comments=self.summary_markers(text))[self.SEC]
                self.assertEqual(result.open_findings, 3)
                self.assertEqual(result.blocking_findings, blocking)

    def test_a_rerolled_review_of_the_same_tree_never_lowers_the_count(
        self,
    ) -> None:
        # #8638: the earlier review of the tree reported the same summary
        # findings; its line is not read, so the newer one's line cannot
        # clear them, whether the re-roll is a re-run or an empty commit.
        for sha in (S, S0):
            with self.subTest(earlier=sha):
                runs = [
                    whole("claude-review", S),
                    run(self.SEC, sha, "findings=2 inline=0 scope=whole"),
                    run(
                        self.SEC,
                        S,
                        "findings=2 inline=0 scope=whole",
                        created="2026-01-01T02:00:00Z",
                        tree=tree_of(sha),
                    ),
                ]
                comments = self.summary_markers("critical-findings: 0")
                result = self.bind(runs, comments=comments)[self.SEC]
                self.assertEqual(result.open_findings, 2)
                self.assertEqual(result.blocking_findings, 2)

    def test_a_summary_comment_the_review_posted_carries_the_line(self) -> None:
        # The probe fixture's producer shape: the Claude App posts the summary
        # and the head marker is a separate status comment.
        runs = [whole("claude-review", S), whole(self.SEC, S, n=2, k=0)]

        def summary(body: str, at: str) -> dict[str, Any]:
            return {
                "id": next(_ids),
                "user": {"login": "claude[bot]", "type": "Bot"},
                "created_at": at,
                "body": body,
                "edit": UNEDITED,
            }

        for body, at, blocking in (
            ("summary\n\ncritical-findings: 0", "2026-01-01T00:30:00Z", 0),
            (
                "summary\n\ncritical-findings: 0\n\nclaude-lane: claude-review",
                "2026-01-01T00:30:00Z",
                2,
            ),
            ("summary\n\ncritical-findings: 0", "2026-01-01T02:00:00Z", 2),
        ):
            with self.subTest(body=body, at=at):
                comments = [*both_markers(), summary(body, at)]
                result = self.bind(runs, comments=comments)[self.SEC]
                self.assertEqual(result.open_findings, 2)
                self.assertEqual(result.blocking_findings, blocking)

    # ci-workflows pr-review-cli.yml posts as github-actions[bot] and foots
    # each comment `\n\nclaude-lane: <lane>` (publish-review publish.cjs).
    ACTIONS = {"__typename": "Bot", "login": "github-actions"}

    def test_a_github_actions_finding_with_the_lane_footer_is_the_lanes(self) -> None:
        for severity, blocking in (("IMPORTANT", 0), ("CRITICAL", 1), (None, 1)):
            with self.subTest(severity=severity):
                line = f"severity: {severity}\n" if severity else ""
                body = f"finding\n{line}\nclaude-lane: {self.SEC}"
                runs = [whole("claude-review", S), whole(self.SEC, S, n=1, k=1)]
                threads = [thread(body, author=self.ACTIONS)]
                result = self.bind(runs, threads=threads)[self.SEC]
                self.assertEqual(result.open_findings, 1)
                self.assertEqual(result.blocking_findings, blocking)

    def test_a_github_actions_thread_without_the_lanes_footer_last_is_not_the_lanes(
        self,
    ) -> None:
        # Not the lane's thread, so the recorded inline finding has none left
        # and counts as CRITICAL even though the body reads IMPORTANT.
        for body in (
            "finding\nseverity: IMPORTANT",
            f"claude-lane: {self.SEC}\nfinding\nseverity: IMPORTANT",
            "finding\nseverity: IMPORTANT\n\nclaude-lane: claude-review",
        ):
            with self.subTest(body=body):
                runs = [whole("claude-review", S), whole(self.SEC, S, n=1, k=1)]
                threads = [thread(body, author=self.ACTIONS)]
                result = self.bind(runs, threads=threads)[self.SEC]
                self.assertEqual(result.blocking_findings, 1)

    def test_a_github_actions_summary_comment_counts_only_with_the_lanes_footer(
        self,
    ) -> None:
        runs = [whole("claude-review", S), whole(self.SEC, S, n=2, k=0)]

        def summary(body: str, user: dict[str, str] | None = None) -> dict[str, Any]:
            return {
                "id": next(_ids),
                "user": user or {"login": "github-actions[bot]", "type": "Bot"},
                "created_at": "2026-01-01T00:30:00Z",
                "body": body,
                "edit": UNEDITED,
            }

        footed = f"summary\n\ncritical-findings: 0\n\nclaude-lane: {self.SEC}"
        # REST names the bot `github-actions[bot]` with type Bot; a bare login
        # or a User account under either login is not the lane's.
        for body, user, blocking in (
            (footed, None, 0),
            ("summary\n\ncritical-findings: 0", None, 2),
            (f"claude-lane: {self.SEC}\n\ncritical-findings: 0", None, 2),
            (footed, {"login": "github-actions", "type": "User"}, 2),
            (footed, {"login": "github-actions", "type": "Bot"}, 2),
            (footed, {"login": "github-actions[bot]", "type": "User"}, 2),
        ):
            with self.subTest(body=body, user=user):
                comments = [*both_markers(), summary(body, user)]
                result = self.bind(runs, comments=comments)[self.SEC]
                self.assertEqual(result.blocking_findings, blocking)

    def test_a_marker_ending_in_the_lane_footer_is_read_once(self) -> None:
        runs = [whole("claude-review", S), whole(self.SEC, S, n=2, k=0)]
        comments = self.summary_markers(
            f"critical-findings: 0\n\nclaude-lane: {self.SEC}"
        )
        result = self.bind(runs, comments=comments)[self.SEC]
        self.assertEqual(result.blocking_findings, 0)

    def test_a_thread_less_inline_finding_counts_as_critical(self) -> None:
        runs = [whole("claude-review", S), whole(self.SEC, S, n=1, k=1)]
        result = self.bind(runs, comments=self.summary_markers("critical-findings: 0"))[
            self.SEC
        ]
        self.assertEqual(result.blocking_findings, 1)

    # #10817: a whole review at S0 reported one IMPORTANT summary finding with
    # `critical-findings: 0`, then an incremental review at S found none. The
    # lane edits one marker in place, so S0's summary lives in its history.
    ACTIONS_BOT = {"__typename": "Bot", "login": "github-actions"}

    def earlier_link(self) -> list[dict[str, Any]]:
        early = attempt(
            self.SEC, S0, 1, [record(self.SEC, S0, "findings=1 inline=0 scope=whole")]
        )
        late = attempt(
            self.SEC,
            S,
            1,
            [record(self.SEC, S, f"findings=0 inline=0 scope=incremental since={S0}")],
        )
        late["jobs"][0]["started_at"] = "2026-01-01T02:00:00Z"
        late["jobs"][0]["completed_at"] = "2026-01-01T03:00:00Z"
        return [
            whole("claude-review", S),
            run(self.SEC, S0, attempts=[early]),
            run(self.SEC, S, attempts=[late], created="2026-01-01T02:00:00Z"),
        ]

    def edited_marker(
        self, earlier: str | None, history: Any = None
    ) -> list[dict[str, Any]]:
        """Both markers, the security one edited from S0's summary (`earlier`)
        to S's clean one; `history` replaces the edit history whole."""
        current = (
            f"<!-- claude-lane-reviewed-head lane={self.SEC} sha={S} -->\n"
            "reviewed: 0 finding(s).\n\ncritical-findings: 0"
        )
        old = (
            f"<!-- claude-lane-reviewed-head lane={self.SEC} sha={S0} -->\n"
            f"reviewed: 1 finding(s).\n\n{earlier}"
        )
        if history is None:
            history = {
                "totalCount": 2,
                "nodes": [
                    {"editedAt": "2026-01-01T02:30:00Z", "deletedAt": None,
                     "editor": self.ACTIONS_BOT, "diff": current},
                    {"editedAt": "2026-01-01T00:30:00Z", "deletedAt": None,
                     "editor": self.ACTIONS_BOT, "diff": old},
                ],
            }  # fmt: skip
        found = both_markers()
        for item in found:
            if f"lane={self.SEC}" in item["body"]:
                item["body"] = current
                item["edit"] = {
                    "lastEditedAt": "2026-01-01T02:30:00Z",
                    "editor": self.ACTIONS_BOT,
                    "history": history,
                }
        return found

    def test_an_earlier_links_summary_blocks_only_when_critical_or_unreadable(
        self,
    ) -> None:
        for earlier, blocking in (
            ("critical-findings: 0", 0),
            ("critical-findings: 1", 1),
            ("critical-findings: 7", 1),
            ("no line", 1),
            ("critical-findings: 0\ncritical-findings: 0", 1),
        ):
            with self.subTest(earlier=earlier):
                comments = self.edited_marker(earlier)
                result = self.bind(self.earlier_link(), comments=comments)[self.SEC]
                self.assertTrue(result.bound)
                self.assertEqual(result.open_findings, 1)
                self.assertEqual(result.blocking_findings, blocking)

    def test_an_unreadable_marker_history_counts_the_earlier_summary_in_full(
        self,
    ) -> None:
        good = self.edited_marker("critical-findings: 0")[1]["edit"]["history"]
        nodes = good["nodes"]
        for name, history in (
            ("absent", "missing"),
            ("truncated", {"totalCount": 3, "nodes": nodes}),
            ("deleted", {"totalCount": 2, "nodes": [nodes[0], {**nodes[1], "deletedAt": "2026-01-01T04:00:00Z"}]}),
            ("no diff", {"totalCount": 2, "nodes": [nodes[0], {**nodes[1], "diff": None}]}),
            ("another editor", {"totalCount": 2, "nodes": [nodes[0], {**nodes[1], "editor": MAINTAINER}]}),
            ("outside the job", {"totalCount": 2, "nodes": [nodes[0], {**nodes[1], "editedAt": "2026-01-01T01:30:00Z"}]}),
        ):  # fmt: skip
            with self.subTest(name=name):
                comments = self.edited_marker("critical-findings: 0", history)
                if name == "absent":
                    del comments[1]["edit"]["history"]
                result = self.bind(self.earlier_link(), comments=comments)[self.SEC]
                self.assertTrue(result.bound)
                self.assertEqual(result.blocking_findings, 1)

    def test_a_revision_for_another_head_does_not_read_for_the_earlier_link(
        self,
    ) -> None:
        # S's own revision falls in S0's window: it names S, not S0.
        comments = self.edited_marker("no line")
        history = comments[1]["edit"]["history"]
        history["nodes"][0]["editedAt"] = "2026-01-01T00:40:00Z"
        result = self.bind(self.earlier_link(), comments=comments)[self.SEC]
        self.assertEqual(result.blocking_findings, 1)

    def test_the_covering_reviews_line_still_reads_beside_the_history(self) -> None:
        # The newest revision is the current marker body: it must not count
        # as a second line for the covering review.
        runs = [whole("claude-review", S), whole(self.SEC, S, n=2, k=0)]
        comments = self.summary_markers("critical-findings: 0")
        sec = comments[1]
        sec["edit"] = {
            "lastEditedAt": "2026-01-01T00:30:00Z",
            "editor": self.ACTIONS_BOT,
            "history": {"totalCount": 1, "nodes": [
                {"editedAt": "2026-01-01T00:30:00Z", "deletedAt": None,
                 "editor": self.ACTIONS_BOT, "diff": sec["body"]},
            ]},
        }  # fmt: skip
        result = self.bind(runs, comments=comments)[self.SEC]
        self.assertEqual(result.blocking_findings, 0)

    def test_claude_review_findings_all_block(self) -> None:
        runs = [whole("claude-review", S, n=1, k=0), whole(self.SEC, S)]
        result = self.bind(runs)["claude-review"]
        self.assertEqual(result.open_findings, 1)
        self.assertIsNone(result.blocking_findings)


class CodeLaneOnCliTests(Base):
    """The code lane on ci-workflows pr-review-cli.yml posts as
    github-actions[bot], each comment footed `claude-lane: claude-review`."""

    ACTIONS = {"__typename": "Bot", "login": "github-actions"}
    FOOTED = "finding\n\nclaude-lane: claude-review"

    def test_its_thread_stands_for_the_recorded_finding(self) -> None:
        runs = [whole("claude-review", S, n=1, k=1), whole("claude-security-review", S)]
        open_thread = thread(self.FOOTED, author=self.ACTIONS)
        result = self.bind(runs, threads=[open_thread])
        self.assertEqual(result["claude-review"].open_findings, 1)
        self.assertEqual(result["claude-security-review"].open_findings, 0)
        # Resolved by a person, it closes the finding.
        closed = thread(
            self.FOOTED, author=self.ACTIONS, resolved=True, resolved_by=MAINTAINER
        )
        result = self.bind(runs, threads=[closed])["claude-review"]
        self.assertEqual(result.open_findings, 0)

    def test_a_thread_without_its_footer_last_does_not(self) -> None:
        # Not the lane's thread, so the recorded inline finding has none and
        # stays open however the thread was resolved.
        runs = [whole("claude-review", S, n=1, k=1), whole("claude-security-review", S)]
        for body in (
            "finding",
            "claude-lane: claude-review\nfinding",
            "finding\n\nclaude-lane: claude-security-review",
        ):
            with self.subTest(body=body):
                closed = thread(
                    body, author=self.ACTIONS, resolved=True, resolved_by=MAINTAINER
                )
                result = self.bind(runs, threads=[closed])["claude-review"]
                self.assertEqual(result.open_findings, 1)


if __name__ == "__main__":
    unittest.main()


class EditedCommentTests(Base):
    """Anyone with write access can edit a comment, and the last editor wrote
    its whole body, so a lane comment whose last editor is not its own author
    proves nothing and unbinds. The producer's own marker edits bind."""

    SEC = "claude-security-review"
    HUMAN_EDIT = {
        "lastEditedAt": "2026-01-02T00:00:00Z",
        "editor": {"__typename": "User", "login": "pusher"},
    }
    APP_EDIT = {
        "lastEditedAt": "2026-01-02T00:00:00Z",
        "editor": {"__typename": "Bot", "login": "melodic-lanes"},
    }
    OWN_EDIT = {
        "lastEditedAt": "2026-01-02T00:00:00Z",
        "editor": {"__typename": "Bot", "login": "github-actions"},
    }

    def markers(self, edit: Any) -> list[dict[str, Any]]:
        found = both_markers()
        for item in found:
            if f"lane={self.SEC}" in item["body"]:
                if edit is None:
                    del item["edit"]
                else:
                    item["edit"] = edit
        return found

    def runs(self) -> list[dict[str, Any]]:
        return [whole(lane, S) for lane in LANES]

    def test_a_marker_edited_by_another_identity_unbinds_every_lane(self) -> None:
        # The edited text cannot say which lane's marker it was.
        for name, edit in (
            ("a person", self.HUMAN_EDIT),
            ("another App", self.APP_EDIT),
            ("no edit record", None),
            ("an unreadable record", "edited"),
            ("an editor that is not read", {"lastEditedAt": "2026-01-02T00:00:00Z"}),
        ):
            with self.subTest(name):
                result = self.bind(self.runs(), self.markers(edit))
                for lane in LANES:
                    self.assertUnbound(result[lane], "comment-edited")

    def test_a_marker_the_producer_edited_still_binds(self) -> None:
        # ci-workflows publish.cjs writeMarker updates the lane's marker on
        # each later review; GraphQL names its editor without `[bot]`.
        result = self.bind(self.runs(), self.markers(self.OWN_EDIT))
        for lane in LANES:
            self.assertTrue(result[lane].bound, lane)

    def test_an_edited_summary_count_unbinds(self) -> None:
        summary = {
            "id": next(_ids),
            "user": {"login": "github-actions[bot]", "type": "Bot"},
            "created_at": "2026-01-01T00:30:00Z",
            "body": f"summary\n\ncritical-findings: 0\n\n`claude-lane: {self.SEC}`",
            "edit": self.HUMAN_EDIT,
        }
        runs = [whole("claude-review", S), whole(self.SEC, S, n=1)]
        result = self.bind(runs, [*both_markers(), summary])
        self.assertUnbound(result[self.SEC], "comment-edited")

    def test_an_edited_thread_finding_fails_closed(self) -> None:
        # A CRITICAL finding edited down to a SUGGESTION, or with its footer
        # removed, would leave the count; it unbinds instead.
        runs = [whole("claude-review", S), whole(self.SEC, S, n=1, k=1)]
        for name, body in (
            ("downgraded", f"x\n\nseverity: SUGGESTION\n`claude-lane: {self.SEC}`"),
            ("footer kept", f"x\n\nseverity: CRITICAL\n`claude-lane: {self.SEC}`"),
        ):
            with self.subTest(name):
                item = thread(body)
                item["comments"][0]["lastEditedAt"] = "2026-01-02T00:00:00Z"
                item["comments"][0]["editor"] = {
                    "__typename": "User",
                    "login": "pusher",
                }
                result = self.bind(runs, threads=[item])
                self.assertUnbound(result[self.SEC], "comment-edited")

    def test_a_finding_whose_footer_a_person_deleted_fails_closed(self) -> None:
        # Without its footer the body no longer names the lane; the edit is
        # read before the body, so it unbinds rather than leaving the count.
        runs = [whole("claude-review", S), whole(self.SEC, S, n=1, k=1)]
        for name, login in (
            ("github-actions", "github-actions"),
            ("Claude App", "claude"),
        ):
            with self.subTest(name):
                item = thread(
                    "x\n\nseverity: CRITICAL",
                    author={"__typename": "Bot", "login": login},
                )
                item["comments"][0]["lastEditedAt"] = "2026-01-02T00:00:00Z"
                item["comments"][0]["editor"] = {
                    "__typename": "User",
                    "login": "pusher",
                }
                result = self.bind(runs, threads=[item])
                self.assertUnbound(result[self.SEC], "comment-edited")

    def test_a_summary_whose_footer_a_person_deleted_unbinds(self) -> None:
        summary = {
            "id": next(_ids),
            "user": {"login": "github-actions[bot]", "type": "Bot"},
            "created_at": "2026-01-01T00:30:00Z",
            "body": "summary\n\ncritical-findings: 1",
            "edit": self.HUMAN_EDIT,
        }
        runs = [whole("claude-review", S), whole(self.SEC, S, n=1)]
        result = self.bind(runs, [*both_markers(), summary])
        self.assertUnbound(result[self.SEC], "comment-edited")

    def test_a_thread_whose_edit_fields_were_not_read_fails_closed(self) -> None:
        runs = [whole("claude-review", S), whole(self.SEC, S, n=1, k=1)]
        item = thread(f"x\n\nseverity: SUGGESTION\n`claude-lane: {self.SEC}`")
        del item["comments"][0]["lastEditedAt"]
        result = self.bind(runs, threads=[item])
        self.assertUnbound(result[self.SEC], "comment-edited")

    def test_a_thread_its_author_edited_still_counts(self) -> None:
        runs = [whole("claude-review", S), whole(self.SEC, S, n=1, k=1)]
        item = thread(f"x\n\nseverity: CRITICAL\n`claude-lane: {self.SEC}`")
        item["comments"][0]["lastEditedAt"] = "2026-01-02T00:00:00Z"
        item["comments"][0]["editor"] = {"__typename": "Bot", "login": "claude"}
        result = self.bind(runs, threads=[item])
        self.assertTrue(result[self.SEC].bound)
        self.assertEqual(result[self.SEC].blocking_findings, 1)

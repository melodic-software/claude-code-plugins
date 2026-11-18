# test-scope: .github/scripts/pr-verify/resolve-pr.mjs scripts/upstream-drift-issues.sh scripts/check-upstream-drift.sh
"""The gate's upstream-drift trust rule (`babysit_verify_evidence._trusted_spec`)
agrees with resolve-pr.mjs driftSpec: an issue github-actions[bot] wrote,
nobody else last edited, titled `Upstream drift: <id>` with the hex-pin lead
line scripts/upstream-drift-issues.sh writes for that id, is a trusted spec
only for a pull request whose changed files, base to head, are modifications
of docs/upstream pages that pin that id on the default branch. Network is
stubbed at the `gh_capture` seam.
"""

from __future__ import annotations

import base64
import json
import pathlib
import subprocess
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_postmerge as postmerge
import babysit_verify_evidence as ve

REPO = "example-org/example-repo"
ISSUE = 7
MAIN_TIP = "a" * 40
BASE = "b" * 40
HEAD = "c" * 40
PR = {"number": 41, "base": {"sha": BASE}, "head": {"sha": HEAD}}
ACTIONS = {"__typename": "Bot", "login": "github-actions", "databaseId": 41898282}
LANES = {"__typename": "Bot", "login": "agent-lanes", "databaseId": 337595936}
HUMAN = {"__typename": "User", "login": "human-100", "databaseId": 100}
OUTSIDER = {"__typename": "User", "login": "drive-by", "databaseId": 999}
ID = "mattpocock/sandcastle"
TITLE = f"Upstream drift: {ID}"
LEAD = f"Upstream `{ID}` changed since the pin on its docs/upstream page."
BODY = f"{LEAD}\n\nRun: 2026-11-09\n\n- `changed` `src/Ignore this.ts` (page line 12)\n"
PAGE = "docs/upstream/mattpocock-sandcastle.md"
OTHER_PAGE = "docs/upstream/emilkowalski-skills.md"
# The pages at main's tip, each with its git pin marker.
PAGES = {
    PAGE: f"# Sandcastle\n\n**Last audited upstream state:** `{ID}@{'0' * 40}` (2026-11-01)\n",
    OTHER_PAGE: f"# Skills\n\n**Last audited upstream state:** `emilkowalski/skills@{'0' * 40}`\n",
    "docs/upstream/plain.md": "# Plain\n\nNo git pin.\n",
}
PAGE_ONLY = [{"filename": PAGE, "status": "modified"}]
VENDORED_ID = "playwright/playwright"
ROWS = (
    "ROWS=(\n"
    '  "playwright/playwright|plugins/playwright/skills/playwright/scripts/update.sh|--check|files-only"\n'
    '  "split/claim|plugins/one/x.sh||files-only"\n'
    '  "split/claim|plugins/two/x.sh||files-only"\n'
    '  "installs/package|plugins/one/update.sh|--check"\n'
    ")\n"
)
VENDORED_BODY = (
    f"Upstream `{VENDORED_ID}` no longer matches the copy vendored here.\n\n"
    "Run: 2026-11-18\n\n### `playwright:playwright`\n"
)
SYNC = [
    {"filename": "plugins/playwright/skills/playwright/vendor/SKILL.md", "status": "modified"},
    {"filename": "plugins/playwright/skills/playwright/vendor/new.md", "status": "added"},
    {"filename": "plugins/playwright/skills/playwright/reference/commands.md", "status": "modified"},
    {"filename": ".changes/playwright/sync-0123abcd.md", "status": "added"},
]


class FakeGitHub:
    """Answers the trusted-actor list, the issue's title, body, author and
    last editor, the compare from BASE to HEAD, and the pages at main."""

    def __init__(self, issue: dict[str, Any], files: Any):
        self.issue = issue
        self.files = files
        self.issue_reads = 0
        self.compares = 0
        self.page_reads: list[str] = []

    def __call__(self, args: list[str], **_: Any) -> subprocess.CompletedProcess[str]:
        ok = lambda answer: subprocess.CompletedProcess(args, 0, json.dumps(answer), "")  # noqa: E731
        if args == ["api", f"repos/{REPO}"]:
            return ok({"default_branch": "main"})
        if args == ["api", f"repos/{REPO}/git/ref/heads/main"]:
            return ok(
                {
                    "ref": "refs/heads/main",
                    "object": {"sha": MAIN_TIP, "type": "commit"},
                }
            )
        if args[:2] == ["api", "graphql"]:
            assert any(a == f"query={ve.ACTIONS_ISSUE_QUERY}" for a in args), args
            self.issue_reads += 1
            return ok({"data": {"repository": {"issue": self.issue}}})
        if args == ["api", f"repos/{REPO}/compare/{BASE}...{HEAD}"]:
            self.compares += 1
            if self.files is None:
                return subprocess.CompletedProcess(args, 1, "", "HTTP 502")
            return ok({"status": "ahead", "files": self.files})
        page = f"repos/{REPO}/contents/"
        if args == ["api", f"{page}{ve.VENDORED_REPORT_PATH}?ref={MAIN_TIP}"]:
            self.page_reads.append(ve.VENDORED_REPORT_PATH)
            content = base64.b64encode(ROWS.encode()).decode()
            return ok({"encoding": "base64", "content": content})
        if len(args) == 2 and args[1].startswith(page) and "docs/upstream/" in args[1]:
            path, _, ref = args[1].removeprefix(page).partition("?ref=")
            assert ref == MAIN_TIP, ref
            self.page_reads.append(path)
            if path not in PAGES:
                return subprocess.CompletedProcess(args, 1, "", "HTTP 404")
            content = base64.b64encode(PAGES[path].encode()).decode()
            return ok({"encoding": "base64", "content": content})
        for a in args:
            if a.startswith(f"repos/{REPO}/contents/{ve.ADMISSION_RULES_PATH}?"):
                return ok({})
            # A look-alike falls through to the recurring rule, whose schedule
            # names no row.
            if a.startswith(f"repos/{REPO}/contents/{ve.RECURRING_SCHEDULE_PATH}?"):
                return ok({"items": []})
            if a.startswith(f"repos/{REPO}/contents/{ve.TRUSTED_ACTORS_PATH}?"):
                return ok(
                    {
                        "version": 1,
                        "actors": [{"id": 100, "login": "human-100", "kind": "human"}],
                    }
                )
        raise AssertionError(f"unexpected gh call: {args}")


def linked(author: dict[str, Any], number: int = ISSUE) -> dict[str, Any]:
    """The issue as a verdict's `linked_issues` records it."""
    return {
        "number": number,
        "author_login": author["login"],
        "author_id": author["databaseId"],
        "author_type": author["__typename"],
        "last_edited_at": None,
        "editor_login": None,
        "editor_id": None,
        "editor_type": None,
        "spec_comments": [],
    }


def judge(
    title: str = TITLE,
    body: str = BODY,
    author: dict[str, Any] = ACTIONS,
    edited: tuple[str, dict[str, Any]] | None = None,
    files: Any = PAGE_ONLY,
    also: list[dict[str, Any]] | None = None,
) -> tuple[bool, FakeGitHub]:
    issue = {
        "title": title,
        "body": body,
        "author": author,
        "lastEditedAt": edited[0] if edited else None,
        "editor": edited[1] if edited else None,
    }
    fake = FakeGitHub(issue, files)
    with (
        mock.patch.dict("os.environ", {}, clear=False) as env,
        mock.patch.object(postmerge, "gh_capture", side_effect=fake),
        mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
    ):
        env.pop("BABYSIT_RUN_CACHE", None)
        reader = ve.Reader(REPO, "main", agent_identity=None)
        record = {"linked_issues": [*(also or []), linked(author)]}
        return reader._trusted_spec(record, PR, HEAD), fake


class ADriftIssueTheWorkflowFiled(unittest.TestCase):
    def test_is_the_spec_of_a_pull_request_changing_only_its_upstreams_page(
        self,
    ) -> None:
        trusted, fake = judge()
        self.assertIs(trusted, True)
        self.assertEqual(fake.issue_reads, 1)
        self.assertEqual(fake.compares, 1)
        self.assertEqual(fake.page_reads, [PAGE], "read at main's tip")

    def test_the_workflows_own_weekly_body_edit_keeps_it_trusted(self) -> None:
        self.assertIs(judge(edited=("2026-11-09T00:00:00Z", ACTIONS))[0], True)

    def test_a_look_alike_refuses(self) -> None:
        for why, kwargs in [
            ("no lead line", {"body": "<!-- factory-monitor key=x -->\n" + LEAD}),
            (
                "the vendored-copy lead without its full stop",
                {"body": f"Upstream `{ID}` no longer matches the copy vendored here"},
            ),
            ("another title", {"title": "Monitor: something"}),
            ("a title naming another upstream", {"title": "Upstream drift: a/b"}),
            (
                "a body a person last edited",
                {"edited": ("2026-11-10T00:00:00Z", HUMAN)},
            ),
            (
                "a body an outsider last edited",
                {"edited": ("2026-11-10T00:00:00Z", OUTSIDER)},
            ),
        ]:
            with self.subTest(why):
                trusted, fake = judge(**kwargs)
                self.assertIs(trusted, False)
                self.assertEqual(fake.compares, 0)

    def test_the_same_title_from_another_author_refuses_without_reading_it(
        self,
    ) -> None:
        for why, author in [
            ("the lanes App", LANES),
            ("an outsider", OUTSIDER),
        ]:
            with self.subTest(why):
                trusted, fake = judge(author=author)
                self.assertIs(trusted, False)
                self.assertEqual(fake.issue_reads, 0)

    def test_a_pull_request_beyond_its_upstreams_pages_refuses(self) -> None:
        other = {"filename": OTHER_PAGE, "status": "modified"}
        for why, files in [
            ("another upstream's page", [other]),
            ("its page and another upstream's", [*PAGE_ONLY, other]),
            (
                "its page and an unrelated file",
                [
                    *PAGE_ONLY,
                    {"filename": ".github/workflows/x.yml", "status": "modified"},
                ],
            ),
            (
                "a renamed page",
                [
                    {
                        "filename": "docs/upstream/renamed.md",
                        "previous_filename": PAGE,
                        "status": "renamed",
                    }
                ],
            ),
            ("an added page", [{"filename": PAGE, "status": "added"}]),
            ("a removed page", [{"filename": PAGE, "status": "removed"}]),
            (
                "a page with no pin on main",
                [{"filename": "docs/upstream/plain.md", "status": "modified"}],
            ),
            ("nothing changed", []),
            ("a compare at GitHub's file cap", PAGE_ONLY * ve.COMPARE_FILES_CAP),
        ]:
            with self.subTest(why):
                self.assertIs(judge(files=files)[0], False)

    def test_a_page_main_lacks_is_unreadable(self) -> None:
        with self.assertRaises(ve._Unreadable):
            judge(files=[{"filename": "docs/upstream/gone.md", "status": "modified"}])

    def test_beside_a_human_issue_it_still_needs_its_own_scope(self) -> None:
        human = linked(HUMAN, number=8)
        unrelated = [
            *PAGE_ONLY,
            {"filename": "plugins/x/skill.md", "status": "modified"},
        ]
        self.assertIs(judge(files=unrelated, also=[human])[0], False)
        self.assertIs(judge(also=[human])[0], True)

    def test_an_unreadable_compare_is_unreadable(self) -> None:
        with self.assertRaises(ve._Unreadable):
            judge(files=None)


class AVendoredCopyDriftIssue(unittest.TestCase):
    def vendored(self, **kwargs: Any) -> tuple[bool, FakeGitHub]:
        return judge(
            title=f"Upstream drift: {VENDORED_ID}",
            body=VENDORED_BODY,
            **({"files": SYNC} | kwargs),
        )

    def test_is_the_spec_of_a_sync_inside_its_rows_plugin(self) -> None:
        trusted, fake = self.vendored()
        self.assertIs(trusted, True)
        self.assertEqual(fake.page_reads, [ve.VENDORED_REPORT_PATH], "rows read at main's tip")

    def test_a_pull_request_beyond_its_plugin_refuses(self) -> None:
        for why, files in [
            ("a workflow beside the sync", [*SYNC, {"filename": ".github/workflows/x.yml", "status": "modified"}]),
            ("another plugin", [{"filename": "plugins/firecrawl/x.md", "status": "modified"}]),
            ("another plugin's fragment", [{"filename": ".changes/firecrawl/x.md", "status": "added"}]),
            (
                "a rename from outside the plugin",
                [{"filename": "plugins/playwright/x.md", "previous_filename": "scripts/x.md", "status": "renamed"}],
            ),
            ("a docs/upstream page", PAGE_ONLY),
            ("nothing changed", []),
        ]:
            with self.subTest(why):
                self.assertIs(self.vendored(files=files)[0], False)

    def test_an_id_no_row_or_two_rows_name_refuses_without_a_compare(self) -> None:
        for upstream in ["someone/else", "split/claim", "installs/package"]:
            with self.subTest(upstream):
                trusted, fake = judge(
                    title=f"Upstream drift: {upstream}",
                    body=f"Upstream `{upstream}` no longer matches the copy vendored here.\n",
                    files=[{"filename": "plugins/one/x.sh", "status": "modified"}],
                )
                self.assertIs(trusted, False)
                self.assertEqual(fake.compares, 0)

    def test_the_same_issue_another_author_wrote_or_edited_refuses(self) -> None:
        self.assertIs(self.vendored(author=OUTSIDER)[0], False)
        self.assertIs(self.vendored(edited=("2026-11-18T00:00:00Z", HUMAN))[0], False)


class DriftIssue(unittest.TestCase):
    def test_matches_resolve_pr_on_the_issue_fields(self) -> None:
        base = {"title": TITLE, "body": BODY, "author": ACTIONS, "lastEditedAt": None}
        self.assertEqual(ve.drift_issue(base), (ID, "pinned"))
        self.assertEqual(
            ve.drift_issue(base | {"body": LEAD + "\r\nmore"}), (ID, "pinned")
        )
        self.assertEqual(
            ve.drift_issue(
                base | {"body": f"Upstream `{ID}` no longer matches the copy vendored here."}
            ),
            (ID, "vendored"),
        )
        self.assertIsNone(ve.drift_issue(base | {"body": " " + LEAD}))
        self.assertIsNone(ve.drift_issue(base | {"title": TITLE + " "}))
        self.assertIsNone(ve.drift_issue(base | {"author": HUMAN}))
        self.assertIsNone(ve.drift_issue(None))


class PagePin(unittest.TestCase):
    def test_reads_the_marker_only_where_check_upstream_drift_does(self) -> None:
        sha = "0" * 40
        self.assertEqual(ve.page_pin(PAGES[PAGE]), ID)
        self.assertIsNone(
            ve.page_pin(f"  **Last audited upstream state:** `a/b@{sha}`")
        )
        self.assertIsNone(ve.page_pin("**Last audited upstream state:** `a/b@abc123`"))
        self.assertIsNone(
            ve.page_pin(
                f"see **Last audited upstream state:**\n**Last audited upstream state:** `a/b@{sha}`"
            ),
            "the first line holding the prefix decides",
        )
        self.assertIsNone(ve.page_pin(None))


if __name__ == "__main__":
    unittest.main()

# test-scope: .github/scripts/intake-triage/admit.mjs .github/scripts/intake-triage/issue-spec.mjs .github/scripts/intake-triage/apply-verdict.mjs
# test-scope: plugins/source-control/skills/babysit-prs/scripts/*.py
# test-scope: plugins/source-control/skills/babysit-prs/scripts/tests/test_babysit_own_agent_spec_trust.py
# test-scope: .github/actions/check-kill-switch/check-kill-switch.mjs .github/actions/check-kill-switch/projection.mjs
# test-scope: .github/actions/check-trusted-trigger/check-trusted-trigger.mjs .github/scripts/lib/github-client.mjs .github/actions/log-api-budget/rate-guard.mjs
# test-scope: .github/actions/resolve-config/read-status.mjs .github/actions/resolve-config/write-status.mjs
# test-scope: .github/actions/select-trusted-text/select-trusted-text.mjs
# test-scope: .github/scripts/lib/admission-comment.mjs .github/scripts/lib/admission-record.mjs .github/scripts/lib/done-evidence.mjs
# test-scope: .github/scripts/lib/lane-hold-marker.mjs .github/scripts/lib/retry-fetch.mjs .github/scripts/lib/stop-reason.mjs
# test-scope: .github/scripts/pr-merge/merge-holds.mjs
# test-scope: .github/scripts/work-resolve-issue/known-names.json .github/scripts/work-resolve-issue/limits.mjs
# test-scope: .github/scripts/work-resolve-issue/report-outcome.mjs .github/scripts/work-resolve-issue/stop-routes.json .github/scripts/work-resolve-issue/stop-routes.mjs
"""The gate's triage-verdict brief (`babysit_verify_evidence.triage_briefed`,
through `briefed_issue`): the owner's standing rule read as intake-triage's
own verdict (#18107; architecture PR 167). The lanes App's verdict that held
nothing, stamped with the current title and body, briefs a lanes App filing
under the admission-record rule's vetoes. Run beside admit.mjs triageBriefed
under node. Network is stubbed at the `gh_capture` seam.
"""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import sys
import unittest
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from test_babysit_own_agent_spec_trust import (
    ACTIONS,
    ADMIT,
    AFTER,
    APP,
    APP_ID,
    BEFORE,
    BRIEF_BODY,
    BRIEF_TITLE,
    HUMAN,
    OTHER_BOT,
    brief,
    record_comment,
    ve,
)

MOVED = (
    "The latest triage verdict holds nothing: admission moved the issue to "
    "`needs-owner-decision`; its comment says why."
)


def verdict_comment(
    author: dict[str, Any] = APP,
    line: str = MOVED,
    title: str = BRIEF_TITLE,
    body: str | None = BRIEF_BODY,
    editor: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """The lanes App's intake-triage verdict comment as GraphQL answers it,
    its last line stamping `title` and `body` (none when `body` is None)."""

    def digest(text: str) -> str:
        return ve.hashlib.sha256(text.encode()).hexdigest()

    lines = ["<!-- intake-triage verdict -->", line]
    if body is not None:
        lines.append(
            f"<!-- intake-triage judged title_sha256:{digest(title)} body_sha256:{digest(body)} -->"
        )
    return {
        "createdAt": BEFORE,
        "lastEditedAt": AFTER if editor else None,
        "body": "\n".join(lines),
        "author": author,
        "editor": editor,
    }


class ATriageVerdictBriefsAFilingNoOneHolds(unittest.TestCase):
    def test_a_verdict_briefed_filing_is_trusted(self) -> None:
        ready = "The latest triage verdict holds nothing: the issue is at `status: ready`."
        for why, comments in {
            "admission moved it": [verdict_comment()],
            "at ready": [verdict_comment(line=ready)],
            "edited by the App": [verdict_comment(editor=APP)],
        }.items():
            with self.subTest(why):
                self.assertIs(brief(briefed=comments), True)

    def test_an_unbriefed_held_or_foreign_verdict_is_refused(self) -> None:
        held = f"{BRIEF_BODY}Hold: wait for the owner\n"
        for why, kwargs in {
            "no verdict": {"briefed": []},
            "a verdict for older text": {"body": f"{BRIEF_BODY}More.\n", "briefed": [verdict_comment()]},
            "unstamped": {"briefed": [verdict_comment(body=None)]},
            "triage held it": {
                "briefed": [verdict_comment(line="The triage verdict left this issue at `needs-owner-decision`:")]
            },
            "a person's hold": {
                "briefed": [
                    verdict_comment(
                        line="The latest triage verdict holds nothing: a person set the Work status to `needs-human`, which holds the issue."
                    )
                ]
            },
            "admission did not finish": {
                "briefed": [
                    verdict_comment(
                        line="The latest triage verdict holds nothing: admission did not finish, so the issue's status is not settled."
                    )
                ]
            },
            "vetoed needs-human": {"labels": ["needs-human"], "briefed": [verdict_comment()]},
            "vetoed hold: line": {"body": held, "briefed": [verdict_comment(body=held)]},
            "by a listed human": {"briefed": [verdict_comment(author=HUMAN)]},
            "by github-actions": {"briefed": [verdict_comment(author=ACTIONS)]},
            "by another bot": {"briefed": [verdict_comment(author=OTHER_BOT)]},
            "last edited by a human": {"briefed": [verdict_comment(editor=HUMAN)]},
            "a later App verdict than the one edited": {
                "briefed": [verdict_comment(body=None), verdict_comment()]
            },
            "a malformed App admission record": {
                "briefed": [
                    record_comment() | {"body": f"{ve.ADMISSION_RECORD_MARKER}\n{{}}"},
                    verdict_comment(),
                ]
            },
        }.items():
            with self.subTest(why):
                self.assertIs(brief(**kwargs), False)


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheGateAndPrVerifyAgreeOnATriageVerdict(unittest.TestCase):
    def test_triage_briefed_matches_admit_triage_briefed(self) -> None:
        held = "The triage verdict left this issue at `needs-owner-decision`:"
        comments = {
            "briefed": [verdict_comment()],
            "none": [],
            "older text": [verdict_comment(body="old")],
            "unstamped": [verdict_comment(body=None)],
            "held": [verdict_comment(line=held)],
            "human": [verdict_comment(author=HUMAN)],
            "actions": [verdict_comment(author=ACTIONS)],
            "human edit": [verdict_comment(editor=HUMAN)],
            "app edit": [verdict_comment(editor=APP)],
        }
        script = (
            f"import {{ triageBriefed }} from {json.dumps(ADMIT.as_uri())};"
            f" const all = {json.dumps(comments)};"
            f" const text = {json.dumps({'title': BRIEF_TITLE, 'body': BRIEF_BODY})};"
            f" console.log(JSON.stringify(Object.values(all).map((c) => triageBriefed(c, {APP_ID}, text))));"
        )
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script],
            capture_output=True,
            text=True,
            check=True,
        )
        js = json.loads(proc.stdout)
        for (why, nodes), expected in zip(comments.items(), js, strict=True):
            with self.subTest(why):
                self.assertIs(ve.triage_briefed(nodes, APP_ID, BRIEF_TITLE, BRIEF_BODY), expected)
        self.assertEqual(js, [True, False, False, False, False, False, False, False, True])


if __name__ == "__main__":
    unittest.main()

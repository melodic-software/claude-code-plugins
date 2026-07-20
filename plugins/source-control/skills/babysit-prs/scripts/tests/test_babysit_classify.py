"""Golden fixtures for the shared authorship / finding / approval classifier.

`babysit_classify` is the single source of truth extracted per #534 so the
snapshot, the readiness gate, the merge gate, and resolve-thread cannot diverge
on "who authored this", "is this a live finding", and "is this an approval". One
fixture class per member concern of the umbrella:

* Authorship (self / bot / human) -- `is_bot`, `normalize_self_logins`,
  `is_self_login`; #497's empty-`self_logins` dormancy is a membership property.
* Finding lifetime-vs-open -- #465: `count_findings` discounts a severity marker
  carried in a resolved or outdated thread.
* Approval verdict -- #499: an Approve-with-nits body carries no live finding.
"""

from __future__ import annotations

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_classify as bc


class IsBotTests(unittest.TestCase):
    def test_authoritative_typename_is_a_bot(self) -> None:
        self.assertTrue(bc.is_bot("ambiguous", "Bot"))

    def test_structural_bot_suffix_is_a_bot(self) -> None:
        self.assertTrue(bc.is_bot("linter[bot]", "User"))

    def test_human_login_and_typename_is_not_a_bot(self) -> None:
        self.assertFalse(bc.is_bot("robotics-fan", "User"))

    def test_extra_bot_login_fallback_when_named(self) -> None:
        self.assertTrue(bc.is_bot("svc-account", "", {"svc-account"}))
        self.assertFalse(bc.is_bot("svc-account", ""))

    def test_non_string_login_without_bot_typename_is_not_a_bot(self) -> None:
        self.assertFalse(bc.is_bot(None, "User"))


class SelfLoginTests(unittest.TestCase):
    def test_normalize_casefolds_and_keeps_bot_suffix(self) -> None:
        # The self set is matched against a raw author login; stripping [bot]
        # would collide a personal login with a same-stem bot posting identity.
        self.assertEqual(
            bc.normalize_self_logins(["Me", "Project-Bot[bot]", "", "  "]),
            frozenset({"me", "project-bot[bot]"}),
        )

    def test_membership_is_casefolded(self) -> None:
        selves = bc.normalize_self_logins(["kyle-sexton", "bot[bot]"])
        self.assertTrue(bc.is_self_login("Kyle-Sexton", selves))
        self.assertTrue(bc.is_self_login("bot[bot]", selves))
        self.assertFalse(bc.is_self_login("someone-else", selves))

    def test_empty_self_set_is_dormant(self) -> None:
        # #497: an empty self set (single-`--pr` mode before the fix) matches
        # nobody, so every self-gated behavior stays off rather than misfiring.
        self.assertEqual(bc.normalize_self_logins([]), frozenset())
        self.assertFalse(bc.is_self_login("anyone", frozenset()))


class FindingLifetimeTests(unittest.TestCase):
    """#465: only currently-open findings count toward decomposition."""

    SELF = bc.normalize_self_logins(["me[bot]"])

    def test_resolved_and_outdated_markers_are_discounted(self) -> None:
        comments = [
            {"author": "codex[bot]", "body": "[CRITICAL] a", "isResolved": True},
            {"author": "codex[bot]", "body": "[CRITICAL] b", "isOutdated": True},
            {"author": "codex[bot]", "body": "[P1] c still open"},
        ]
        self.assertEqual(bc.count_findings(comments, self.SELF), 1)

    def test_open_thread_markers_all_count(self) -> None:
        comments = [
            {"author": "codex[bot]", "body": "CRITICAL a\nIMPORTANT b"},
        ]
        self.assertEqual(bc.count_findings(comments, self.SELF), 2)

    def test_self_classification_rows_do_not_mint_phantom_findings(self) -> None:
        comments = [
            {"author": "me[bot]", "body": "| 1 | CRITICAL null deref | VALID | fixed |"},
        ]
        self.assertEqual(bc.count_findings(comments, self.SELF), 0)

    def test_self_source_finding_still_counts(self) -> None:
        comments = [{"author": "me[bot]", "body": "Found a CRITICAL leak here"}]
        self.assertEqual(bc.count_findings(comments, self.SELF), 1)


class ClassificationCountTests(unittest.TestCase):
    SELF = bc.normalize_self_logins(["me[bot]"])

    def test_pipe_rows_with_tokens_count_once_per_line(self) -> None:
        comments = [
            {
                "author": "me[bot]",
                "body": "| 1 | a | VALID | x |\n| 2 | b | INCORRECT | y |\nprose VALID VALID",
            }
        ]
        self.assertEqual(bc.count_classified(comments, self.SELF), 2)

    def test_only_self_rows_count(self) -> None:
        comments = [{"author": "codex[bot]", "body": "| 1 | a | VALID | x |"}]
        self.assertEqual(bc.count_classified(comments, self.SELF), 0)

    def test_resolved_thread_classification_is_discounted(self) -> None:
        """Mirrors `count_findings`'s #465 discount: a classification row
        carried in a resolved thread is a lifetime artifact of an
        already-addressed round, not evidence a fresh finding was classified.
        Without the discount, this stale row would inflate the denominator
        and let the gate's `classified >= findings` predicate pass despite
        the new finding having no classification."""
        comments = [
            {
                "author": "me[bot]",
                "body": "| 1 | old finding | VALID | fixed |",
                "isResolved": True,
            },
            {"author": "codex[bot]", "body": "[CRITICAL] new unclassified finding"},
        ]
        self.assertEqual(bc.count_classified(comments, self.SELF), 0)
        self.assertEqual(bc.count_findings(comments, self.SELF), 1)
        self.assertLess(
            bc.count_classified(comments, self.SELF),
            bc.count_findings(comments, self.SELF),
        )


class ApprovalVerdictTests(unittest.TestCase):
    """#499: an Approve-with-nits review carries no live finding."""

    SELF = bc.normalize_self_logins(["me[bot]"])

    def test_approve_with_nits_downgrades_and_has_no_severity_finding(self) -> None:
        body = (
            "Approve. Two 🟡 nits, low impact, not worth a change on its own. "
            "No blocking issues."
        )
        self.assertTrue(bc.approval_downgrade(body))
        self.assertFalse(bc.has_blocking_severity(body))
        self.assertEqual(
            bc.count_findings([{"author": "claude[bot]", "body": body}], self.SELF), 0
        )

    def test_genuine_critical_finding_is_not_downgraded(self) -> None:
        body = "CRITICAL: a null dereference will crash the handler."
        self.assertFalse(bc.approval_downgrade(body))
        self.assertTrue(bc.has_blocking_severity(body))


if __name__ == "__main__":
    unittest.main()

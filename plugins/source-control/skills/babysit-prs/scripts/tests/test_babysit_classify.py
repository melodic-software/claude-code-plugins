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


class ActorKindTests(unittest.TestCase):
    def test_configured_login_outranks_user_typename(self) -> None:
        # A bot account GitHub misreports as a `User` (no `[bot]` suffix) is a bot
        # when named in extra_bot_logins: the operator's declaration wins over the
        # structural signal, matching `is_bot`. This is the one case the field
        # documents itself for, so `actor_kind` must not settle it as human first.
        config = bc.FeedbackConfig(extra_bot_logins=frozenset({"svc-account"}))
        item = {"author": {"login": "svc-account", "__typename": "User", "is_bot": False}}
        self.assertEqual(bc.actor_kind(item, config), "bot")

    def test_unconfigured_user_is_human(self) -> None:
        config = bc.FeedbackConfig(extra_bot_logins=frozenset({"svc-account"}))
        item = {"author": {"login": "maintainer", "__typename": "User", "is_bot": False}}
        self.assertEqual(bc.actor_kind(item, config), "human")

    def test_default_empty_config_relies_on_structure(self) -> None:
        item = {"author": {"login": "svc-account", "__typename": "User", "is_bot": False}}
        self.assertEqual(bc.actor_kind(item), "human")


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

    def test_lowercase_self_classification_row_does_not_mint_phantom_finding(
        self,
    ) -> None:
        """#619: CLASSIFY_ROW_RE must exclude a natural-language/lowercase
        classification row from the finding corpus the same as an all-caps one
        -- else the row leaks through and its embedded CRITICAL re-counts as a
        phantom finding."""
        comments = [
            {"author": "me[bot]", "body": "| 1 | CRITICAL null deref | Valid | fixed |"},
        ]
        self.assertEqual(bc.count_findings(comments, self.SELF), 0)


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

    def test_lowercase_natural_language_disposition_counts(self) -> None:
        """#619: a worker reply that writes "Valid (defer)" instead of the
        mandated all-caps VALID must still count as a classification, or the
        readiness gate reports a false BLOCKED for a finding that genuinely
        was classified."""
        comments = [
            {"author": "me[bot]", "body": "| 1 | a | Valid (defer) | noted |"},
        ]
        self.assertEqual(bc.count_classified(comments, self.SELF), 1)

    def test_lowercase_invalid_does_not_false_match_valid(self) -> None:
        """Case-insensitive matching must stay whole-word: "invalid" must not
        match "valid" merely because casing is no longer significant."""
        comments = [
            {"author": "me[bot]", "body": "| 1 | a | invalid claim, no fix | noted |"},
        ]
        self.assertEqual(bc.count_classified(comments, self.SELF), 0)

    def test_table_prose_containing_valid_is_not_a_classification(self) -> None:
        """#619: case-folding is anchored to the disposition CELL. A table row
        whose prose happens to contain "valid" (`| CI check | result is valid |`)
        must not be credited -- folding case across the whole line would let a
        second, genuinely unclassified finding past the readiness gate."""
        comments = [
            {
                "author": "me[bot]",
                "body": "| 1 | a | VALID | fixed |\n| CI check | result is valid |",
            },
        ]
        self.assertEqual(bc.count_classified(comments, self.SELF), 1)

    def test_prose_opening_a_cell_is_not_a_classification(self) -> None:
        """#619: anchoring the token to the START of a cell is not enough --
        prose can open a cell too. Only the second row is a real disposition."""
        comments = [
            {
                "author": "me[bot]",
                "body": (
                    "| 1 | comment 1 | VALID | fixed |\n"
                    "| 2 | comment 2 | Valid cache entries are rejected | | | | |"
                ),
            },
        ]
        self.assertEqual(bc.count_classified(comments, self.SELF), 1)

    def test_word_like_continuations_do_not_satisfy_the_token(self) -> None:
        """#619: digits and underscores are not letters, so a letters-only
        boundary credited `valid2` / `VALID_TOKEN` / `2valid`. Such a row would
        be credited AND stripped from the finding corpus."""
        for cell in ("valid2", "VALID_TOKEN", "2valid"):
            with self.subTest(cell=cell):
                comments = [
                    {"author": "me[bot]", "body": f"| 1 | finding | {cell} | pending |"},
                ]
                self.assertEqual(bc.count_classified(comments, self.SELF), 0)

    def test_bracketed_aside_is_stripped_like_a_parenthesised_one(self) -> None:
        """Pins the bracket branch of the aside pattern, which the bash path
        spells as an awk `[^]]` bracket expression -- a paren-only test would
        pass even if that branch stripped nothing."""
        comments = [
            {"author": "me[bot]", "body": "| 1 | finding | Valid [defer] | noted |"},
        ]
        self.assertEqual(bc.count_classified(comments, self.SELF), 1)

    def test_unclosed_aside_fails_closed(self) -> None:
        """#619: aside removal is what lets "Valid (defer)" read as the bare
        token. An unclosed aside strips nothing, so the cell stays prose and
        scores unclassified -- BLOCKED, never a false pass."""
        comments = [
            {"author": "me[bot]", "body": "| 1 | finding | Valid (unclosed | pending |"},
        ]
        self.assertEqual(bc.count_classified(comments, self.SELF), 0)

    def test_decorated_disposition_cell_still_counts(self) -> None:
        """The cell anchor permits leading non-letter decoration, so a bolded
        `| **VALID** |` cell -- countable before #619 under the
        anywhere-in-the-row match -- must not silently stop counting."""
        comments = [{"author": "me[bot]", "body": "| 1 | a | **VALID** | fixed |"}]
        self.assertEqual(bc.count_classified(comments, self.SELF), 1)

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


class EffectiveClassifiedTests(unittest.TestCase):
    """#642: classification credit is bucketed by surface (review-thread vs
    PR-level) so a stale PR-level pipe-row cannot offset an open-thread finding.
    A resolved thread drops its finding and its in-thread classification
    together; a PR-level comment never resolves, so its rows must be confined to
    covering PR-level findings."""

    SELF = bc.normalize_self_logins(["me[bot]"])

    def test_stale_pr_level_row_does_not_cover_open_thread_finding(self) -> None:
        # The exact #642 fail-open: a fresh finding raised in an OPEN review
        # thread, plus a stale classification pipe-row in a PR-level (non-thread)
        # comment. A raw global count reports classified=1 >= findings=1 and the
        # gate false-passes; per-surface credit confines the PR-level row to the
        # (empty) PR-level finding bucket, so effective classified is 0 < 1.
        comments = [
            {
                "author": "codex[bot]",
                "body": "[CRITICAL] fresh unclassified finding",
                "in_review_thread": True,
            },
            {
                "author": "me[bot]",
                "body": "| 1 | old resolved finding | VALID | fixed |",
            },
        ]
        self.assertEqual(bc.count_findings(comments, self.SELF), 1)
        # Raw counter still sees the stale row (documents the defect surface).
        self.assertEqual(bc.count_classified(comments, self.SELF), 1)
        # Per-surface credit closes the fail-open.
        self.assertEqual(bc.count_effective_classified(comments, self.SELF), 0)
        self.assertLess(
            bc.count_effective_classified(comments, self.SELF),
            bc.count_findings(comments, self.SELF),
        )

    def test_pr_level_finding_and_pr_level_classification_still_pass(self) -> None:
        # The D5-mandated flow: issue/review-summary findings answered by a
        # detached PR-level classification. Both are non-thread, so they share a
        # bucket and the classification credits normally -- restricting credit to
        # threads would have permanently blocked this path.
        comments = [
            {"author": "claude[bot]", "body": "### 1. [CRITICAL] a\n### 2. [IMPORTANT] b"},
            {
                "author": "me[bot]",
                "body": "| 1 | a | VALID | fixed |\n| 2 | b | INCORRECT | refuted |",
            },
        ]
        self.assertEqual(bc.count_findings(comments, self.SELF), 2)
        self.assertEqual(bc.count_effective_classified(comments, self.SELF), 2)

    def test_open_thread_finding_covered_by_in_thread_classification(self) -> None:
        # A finding and its classification both carried in the same open thread
        # balance within the thread bucket.
        comments = [
            {"author": "codex[bot]", "body": "[CRITICAL] a", "in_review_thread": True},
            {
                "author": "me[bot]",
                "body": "| 1 | a | VALID | fixed |",
                "in_review_thread": True,
            },
        ]
        self.assertEqual(bc.count_effective_classified(comments, self.SELF), 1)

    def test_thread_state_free_input_collapses_to_min(self) -> None:
        # Convergence invariant: with no thread markers every comment is PR-level,
        # so effective classified is min(classified, findings) -- what the bash
        # degrade computes with its own cap.
        over = [
            {"author": "claude[bot]", "body": "CRITICAL a"},
            {
                "author": "me[bot]",
                "body": "| 1 | a | VALID | x |\n| 2 | spurious | INCORRECT | y |",
            },
        ]
        self.assertEqual(bc.count_findings(over, self.SELF), 1)
        self.assertEqual(bc.count_classified(over, self.SELF), 2)
        self.assertEqual(bc.count_effective_classified(over, self.SELF), 1)

    def test_inline_type_tag_is_bucketed_as_thread_on_reuse_path(self) -> None:
        # The `--comments-json` reuse path is fed `fetch-all-pr-comments.sh`
        # output, which tags inline review comments `type: "inline"` but carries
        # no `in_review_thread` stamp. Honoring the tag keeps that path
        # surface-aware: an inline finding + a detached PR-level (`type:
        # "review"`) classification row must not cross-credit (#642 on the reuse
        # path). Without the tag inference both share the non-thread bucket and
        # the row false-passes the finding.
        comments = [
            {"type": "inline", "author": "codex[bot]", "body": "[CRITICAL] inline finding"},
            {"type": "review", "author": "me[bot]", "body": "| 1 | old | VALID | fixed |"},
        ]
        self.assertEqual(bc.comment_surface(comments[0]), bc.THREAD_SURFACE)
        self.assertEqual(bc.comment_surface(comments[1]), bc.PR_LEVEL_SURFACE)
        self.assertEqual(bc.count_findings(comments, self.SELF), 1)
        self.assertEqual(bc.count_effective_classified(comments, self.SELF), 0)

    def test_explicit_stamp_wins_over_type_tag(self) -> None:
        # An explicit `in_review_thread: false` (a live PR-level comment) is
        # authoritative even if a stray `type` is present -- it is never
        # re-inferred as a thread.
        self.assertEqual(
            bc.comment_surface(
                {"in_review_thread": False, "type": "inline", "body": ""}
            ),
            bc.PR_LEVEL_SURFACE,
        )

    def test_unsignalled_provenance_is_isolated_from_known_surfaces(self) -> None:
        # Fail-closed defense: a finding bearing neither an `in_review_thread`
        # stamp nor a `type` tag lands in the isolated unknown bucket, where a
        # PR-level classification row cannot offset it, so the gate still blocks.
        # (Production paths always signal; this guards a malformed snapshot.)
        comments = [
            {"author": "codex[bot]", "body": "[CRITICAL] unsignalled finding"},
            {"type": "review", "author": "me[bot]", "body": "| 1 | x | VALID | y |"},
        ]
        self.assertEqual(bc.comment_surface(comments[0]), bc.UNKNOWN_SURFACE)
        self.assertEqual(bc.count_findings(comments, self.SELF), 1)
        self.assertEqual(bc.count_effective_classified(comments, self.SELF), 0)

    def test_resolved_thread_contributes_to_neither_bucket(self) -> None:
        # A resolved thread's finding and classification both drop (thread_is_open
        # discount), so a fresh PR-level finding stays uncovered.
        comments = [
            {
                "author": "codex[bot]",
                "body": "[CRITICAL] addressed last round",
                "in_review_thread": True,
                "isResolved": True,
            },
            {
                "author": "me[bot]",
                "body": "| 1 | addressed | VALID | fixed |",
                "in_review_thread": True,
                "isResolved": True,
            },
            {"author": "claude[bot]", "body": "### [IMPORTANT] new PR-level finding"},
        ]
        self.assertEqual(bc.count_findings(comments, self.SELF), 1)
        self.assertEqual(bc.count_effective_classified(comments, self.SELF), 0)


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

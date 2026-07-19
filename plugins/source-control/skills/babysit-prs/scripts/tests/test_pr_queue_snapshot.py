"""Exit-code taxonomy for the snapshot CLI.

Covers every exit code the module documents (0/1/2/3), including the split that
distinguishes an advisory-only head-ref alias failure (valid snapshot) from a
substantive per-PR hydration failure.
"""

import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_delta as delta  # noqa: E402
import pr_queue_snapshot as snapshot_cli  # noqa: E402


def _advisory_error(key="owner/repo#1"):
    return f"{key} {delta.HEAD_REF_ALIAS_ERROR_MARKER} query timed out"


def _substantive_error(key="owner/repo#2"):
    return f"{key}: HTTP 500 fetching PR"


class ExitCodeTaxonomy(unittest.TestCase):
    def test_clean_snapshot_returns_zero(self):
        self.assertEqual(snapshot_cli.exit_code_for({"errors": []}), 0)

    def test_substantive_error_returns_one(self):
        self.assertEqual(
            snapshot_cli.exit_code_for({"errors": [_substantive_error()]}), 1
        )

    def test_advisory_only_error_returns_three(self):
        self.assertEqual(
            snapshot_cli.exit_code_for({"errors": [_advisory_error()]}), 3
        )

    def test_substantive_precedence_over_advisory(self):
        # A run carrying both must never be masked by the advisory split.
        self.assertEqual(
            snapshot_cli.exit_code_for(
                {"errors": [_advisory_error(), _substantive_error()]}
            ),
            1,
        )

    def test_advisory_predicate_matches_only_the_marker(self):
        self.assertTrue(delta.is_head_ref_alias_error(_advisory_error()))
        self.assertFalse(delta.is_head_ref_alias_error(_substantive_error()))


class SubstantiveErrors(unittest.TestCase):
    """The split that keeps advisory failures out of completeness and cadence.

    `complete`, `exit_code_for`, and `cadence_blocking_errors` all derive from
    this predicate, so an advisory-only sweep is a complete sweep and never
    forces the tight cadence.
    """

    def test_advisory_only_has_no_substantive_errors(self):
        self.assertEqual(snapshot_cli.substantive_errors([_advisory_error()]), [])

    def test_substantive_error_is_retained(self):
        substantive = _substantive_error()
        self.assertEqual(
            snapshot_cli.substantive_errors([substantive]), [substantive]
        )

    def test_mixed_keeps_only_substantive(self):
        substantive = _substantive_error()
        self.assertEqual(
            snapshot_cli.substantive_errors([_advisory_error(), substantive]),
            [substantive],
        )

    def test_advisory_only_reports_complete_via_helper(self):
        # `complete` is `not substantive_errors(errors)`; an advisory-only run
        # is still a complete sweep even though `errors` is non-empty.
        self.assertFalse(bool(snapshot_cli.substantive_errors([_advisory_error()])))


class FatalRunReturnsTwo(unittest.TestCase):
    def test_main_returns_two_when_build_snapshot_raises(self):
        with tempfile.TemporaryDirectory() as td:
            argv = [
                "pr_queue_snapshot.py",
                "--queue",
                "--owners",
                "owner",
                "--state-dir",
                td,
            ]
            original_argv = sys.argv
            original_build = snapshot_cli.build_snapshot

            def _raise(_args):
                raise RuntimeError("discovery exploded before any snapshot existed")

            sys.argv = argv
            snapshot_cli.build_snapshot = _raise
            try:
                self.assertEqual(snapshot_cli.main(), 2)
            finally:
                sys.argv = original_argv
                snapshot_cli.build_snapshot = original_build


if __name__ == "__main__":
    unittest.main()

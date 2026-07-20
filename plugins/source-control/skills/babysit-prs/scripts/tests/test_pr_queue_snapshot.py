"""Snapshot CLI: exit-code taxonomy and config assembly.

Exit-code taxonomy covers every code the module documents (0/1/2/3), including
the split that distinguishes an advisory-only head-ref alias failure (valid
snapshot) from a substantive per-PR hydration failure.

Config assembly covers the decoupling of the self-identity suppression set from
the discovery `--author` filter. `@me` resolution is stubbed by monkeypatching
the `babysit_gh` seam; no real gh process is spawned.
"""

from __future__ import annotations

import argparse
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_delta as delta  # noqa: E402
import babysit_gh as gh  # noqa: E402
import pr_queue_snapshot as snapshot  # noqa: E402


def _advisory_error(key="owner/repo#1"):
    return f"{key} {delta.HEAD_REF_ALIAS_ERROR_MARKER} query timed out"


def _substantive_error(key="owner/repo#2"):
    return f"{key}: HTTP 500 fetching PR"


class ExitCodeTaxonomy(unittest.TestCase):
    def test_clean_snapshot_returns_zero(self):
        self.assertEqual(snapshot.exit_code_for({"errors": []}), 0)

    def test_substantive_error_returns_one(self):
        self.assertEqual(
            snapshot.exit_code_for({"errors": [_substantive_error()]}), 1
        )

    def test_advisory_only_error_returns_three(self):
        self.assertEqual(
            snapshot.exit_code_for({"errors": [_advisory_error()]}), 3
        )

    def test_substantive_precedence_over_advisory(self):
        # A run carrying both must never be masked by the advisory split.
        self.assertEqual(
            snapshot.exit_code_for(
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
        self.assertEqual(snapshot.substantive_errors([_advisory_error()]), [])

    def test_substantive_error_is_retained(self):
        substantive = _substantive_error()
        self.assertEqual(
            snapshot.substantive_errors([substantive]), [substantive]
        )

    def test_mixed_keeps_only_substantive(self):
        substantive = _substantive_error()
        self.assertEqual(
            snapshot.substantive_errors([_advisory_error(), substantive]),
            [substantive],
        )

    def test_advisory_only_reports_complete_via_helper(self):
        # `complete` is `not substantive_errors(errors)`; an advisory-only run
        # is still a complete sweep even though `errors` is non-empty.
        self.assertFalse(bool(snapshot.substantive_errors([_advisory_error()])))


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
            original_build = snapshot.build_snapshot

            def _raise(_args):
                raise RuntimeError("discovery exploded before any snapshot existed")

            sys.argv = argv
            snapshot.build_snapshot = _raise
            try:
                self.assertEqual(snapshot.main(), 2)
            finally:
                sys.argv = original_argv
                snapshot.build_snapshot = original_build


class ResolveSelfLoginsTests(unittest.TestCase):
    def test_autopilot_empty_authors_still_yields_authenticated_login(self) -> None:
        with mock.patch.object(gh, "resolve_author", return_value="kyle-sexton"):
            self.assertEqual(snapshot.resolve_self_logins([]), ["kyle-sexton"])

    def test_discovery_authors_are_unioned_with_the_self_login(self) -> None:
        with mock.patch.object(gh, "resolve_author", return_value="kyle-sexton"):
            self.assertEqual(
                snapshot.resolve_self_logins(["alice", "bob"]),
                ["alice", "bob", "kyle-sexton"],
            )

    def test_self_login_already_present_is_not_duplicated(self) -> None:
        with mock.patch.object(gh, "resolve_author", return_value="Kyle-Sexton"):
            self.assertEqual(
                snapshot.resolve_self_logins(["alice", "kyle-sexton"]),
                ["alice", "kyle-sexton"],
            )

    def test_input_author_list_is_not_mutated(self) -> None:
        authors = ["alice"]
        with mock.patch.object(gh, "resolve_author", return_value="kyle-sexton"):
            snapshot.resolve_self_logins(authors)
        self.assertEqual(authors, ["alice"])

    def test_unresolvable_self_login_leaves_discovery_authors_intact(self) -> None:
        with mock.patch.object(gh, "resolve_author", return_value=None):
            self.assertEqual(snapshot.resolve_self_logins(["alice"]), ["alice"])


class BuildConfigSelfLoginsTests(unittest.TestCase):
    def test_resolved_self_logins_populate_config_self_logins(self) -> None:
        args = argparse.Namespace(
            owners="melodic-software",
            resolved_self_logins=["kyle-sexton"],
        )
        config = snapshot.build_config(args)
        self.assertEqual(config.self_logins, frozenset({"kyle-sexton"}))

    def test_resolved_self_logins_take_precedence_over_resolved_authors(self) -> None:
        args = argparse.Namespace(
            owners="melodic-software",
            resolved_authors=["alice"],
            resolved_self_logins=["kyle-sexton"],
        )
        config = snapshot.build_config(args)
        self.assertEqual(config.self_logins, frozenset({"kyle-sexton"}))

    def test_raw_author_fallback_drops_me_when_unresolved(self) -> None:
        args = argparse.Namespace(
            owners="melodic-software",
            author="@me,alice",
        )
        config = snapshot.build_config(args)
        self.assertEqual(config.self_logins, frozenset({"alice"}))


class SinglePrScopeSelfLoginTests(unittest.TestCase):
    """`--pr` scope must resolve @me into the self-login set, not just discovery.

    Regression: the single-PR path once skipped `resolve_self_logins`, so the
    personal fallback identity was absent from `self_logins` and every
    same-login check (foreign-activity, attribution-drift) silently no-opped for
    single-PR runs even though `--pr` scope is a supported invocation.
    """

    def test_single_pr_run_resolves_me_into_self_logins(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            args = argparse.Namespace(
                pr="owner/repo#1",
                author="@me",
                state_dir=state_dir,
                write_state=False,
            )
            # view_pr raises so the per-PR loop is a no-op; the assertion is
            # about the identity resolution that runs before it.
            with mock.patch.object(gh, "resolve_author", return_value="kyle-sexton"), \
                 mock.patch.object(gh, "resolve_authors", return_value=[]), \
                 mock.patch.object(
                     gh, "parse_repo_number", return_value=("owner/repo", 1)
                 ), \
                 mock.patch.object(
                     gh, "view_pr", side_effect=RuntimeError("stop")
                 ):
                snapshot.build_snapshot(args)
            self.assertIn("kyle-sexton", args.resolved_self_logins)


if __name__ == "__main__":
    unittest.main()

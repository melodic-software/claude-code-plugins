"""Snapshot config assembly: self-login resolution and ClassifyConfig mapping.

Covers the decoupling of the self-identity suppression set from the discovery
`--author` filter. `@me` resolution is stubbed by monkeypatching the `babysit_gh`
seam; no real gh process is spawned.
"""

from __future__ import annotations

import argparse
import pathlib
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_gh as gh  # noqa: E402
import pr_queue_snapshot as snapshot  # noqa: E402


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


if __name__ == "__main__":
    unittest.main()

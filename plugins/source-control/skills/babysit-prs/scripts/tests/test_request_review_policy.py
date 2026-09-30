"""`request_review` resolves the trigger phrase and reviewer logins per repository.

The gh seam for the repository config read is a fake; the guarded-mutation
opener is a mock, so no state directory or network is touched.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_repo_config as rc
import request_review
from repo_config_fake import RepoConfigFake

REPO_FILE = (
    "## babysit_review_trigger_phrase\n@repo-bot review\n\n"
    "## babysit_review_bot_logins\n- repo-bot\n\n"
    "## babysit_review_settle_minutes\n5\n"
)


def _args(**overrides: object) -> argparse.Namespace:
    values: dict[str, object] = {
        "pr": "owner/repo#1",
        "trigger_phrase": "@flag-bot review",
        "review_bot_logins": "flag-bot",
        "extra_bot_logins": None,
    }
    values.update(overrides)
    return argparse.Namespace(**values)


@contextlib.contextmanager
def _quiet_stderr():
    with mock.patch("sys.stderr", new=io.StringIO()):
        yield


class TriggerConfigPerRepository(unittest.TestCase):
    def test_repo_phrase_wins_and_repo_reviewers_add_to_the_flags(self) -> None:
        RepoConfigFake({"owner/repo": REPO_FILE}).install(self)
        with _quiet_stderr():
            config = request_review.build_trigger_config(_args(), "owner/repo")
        self.assertEqual(config.trigger_phrase, "@repo-bot review")
        self.assertEqual(config.reviewer_logins, {"repo-bot", "flag-bot"})

    def test_flags_apply_when_the_repo_declares_nothing(self) -> None:
        RepoConfigFake({}).install(self)
        with _quiet_stderr():
            config = request_review.build_trigger_config(_args(), "owner/repo")
        self.assertEqual(config.trigger_phrase, "@flag-bot review")
        self.assertEqual(config.reviewer_logins, {"flag-bot"})

    def test_two_repositories_resolve_independently(self) -> None:
        RepoConfigFake({"owner/a": REPO_FILE}).install(self)
        with _quiet_stderr():
            a = request_review.build_trigger_config(_args(), "owner/a")
            b = request_review.build_trigger_config(_args(), "owner/b")
        self.assertNotEqual(a.trigger_phrase, b.trigger_phrase)
        self.assertNotEqual(a.reviewer_logins, b.reviewer_logins)

    def test_unreadable_repo_config_raises(self) -> None:
        RepoConfigFake({"owner/repo": 500}).install(self)
        with self.assertRaises(rc.RepoConfigError), _quiet_stderr():
            request_review.build_trigger_config(_args(), "owner/repo")


class RunRefusesBeforeOpeningState(unittest.TestCase):
    def test_unreadable_repo_config_never_opens_a_guarded_mutation(self) -> None:
        RepoConfigFake({"owner/repo": 502}).install(self)
        opener = mock.Mock()
        with (
            tempfile.TemporaryDirectory() as tmp,
            mock.patch.object(request_review, "begin_guarded_mutation", opener),
            self.assertRaises(rc.RepoConfigError),
        ):
            state_dir = pathlib.Path(tmp)
            request_review.run_locked(
                _args(apply=True, state_dir=tmp), state_dir, state_dir / "state.json"
            )
        opener.assert_not_called()


if __name__ == "__main__":
    unittest.main()

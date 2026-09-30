"""`request_review` takes the trigger phrase and reviewer logins from `userConfig` only.

A repository's own declaration of either is ignored, and an unreadable repository
config still refuses the run. The gh seam for the repository config read is a
fake; the guarded-mutation opener is a mock, so no state directory or network is
touched.
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
    def test_repo_phrase_and_repo_reviewers_are_ignored(self) -> None:
        RepoConfigFake({"owner/repo": REPO_FILE}).install(self)
        with _quiet_stderr():
            config = request_review.build_trigger_config(_args(), "owner/repo")
        self.assertEqual(config.trigger_phrase, "@flag-bot review")
        self.assertEqual(config.reviewer_logins, {"flag-bot"})

    def test_flags_apply_when_the_repo_declares_nothing(self) -> None:
        RepoConfigFake({}).install(self)
        with _quiet_stderr():
            config = request_review.build_trigger_config(_args(), "owner/repo")
        self.assertEqual(config.trigger_phrase, "@flag-bot review")
        self.assertEqual(config.reviewer_logins, {"flag-bot"})

    def test_two_repositories_get_the_same_phrase(self) -> None:
        RepoConfigFake({"owner/a": REPO_FILE}).install(self)
        with _quiet_stderr():
            a = request_review.build_trigger_config(_args(), "owner/a")
            b = request_review.build_trigger_config(_args(), "owner/b")
        self.assertEqual(a.trigger_phrase, b.trigger_phrase)
        self.assertEqual(a.reviewer_logins, b.reviewer_logins)

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


class _Reached(Exception):
    """Raised by the opener stub to prove the run got past the phrase check."""


class PhraseComesOnlyFromUserConfig(unittest.TestCase):
    """The posted text is the `--trigger-phrase` value; a repository cannot supply it."""

    def test_cli_requires_the_flag(self) -> None:
        argv = [
            "request_review.py",
            "--pr",
            "owner/repo#1",
            "--expected-head-sha",
            "a" * 12,
            "--state-dir",
            "/state",
        ]
        run = mock.Mock(return_value={})
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(request_review, "run", run),
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            request_review.main()
        run.assert_not_called()

    def test_repo_phrase_without_the_flag_refuses_before_opening_state(self) -> None:
        RepoConfigFake({"owner/repo": REPO_FILE}).install(self)
        opener = mock.Mock(side_effect=_Reached)
        with (
            tempfile.TemporaryDirectory() as tmp,
            mock.patch.object(request_review, "begin_guarded_mutation", opener),
            _quiet_stderr(),
            self.assertRaisesRegex(RuntimeError, "review trigger phrase is required"),
        ):
            state_dir = pathlib.Path(tmp)
            request_review.run_locked(
                _args(trigger_phrase=None, apply=True),
                state_dir,
                state_dir / "state.json",
            )
        opener.assert_not_called()

    def test_flag_phrase_reaches_the_guarded_mutation(self) -> None:
        RepoConfigFake({"owner/repo": REPO_FILE}).install(self)
        opener = mock.Mock(side_effect=_Reached)
        with (
            tempfile.TemporaryDirectory() as tmp,
            mock.patch.object(request_review, "begin_guarded_mutation", opener),
            _quiet_stderr(),
            self.assertRaises(_Reached),
        ):
            state_dir = pathlib.Path(tmp)
            request_review.run_locked(
                _args(apply=True), state_dir, state_dir / "state.json"
            )
        opener.assert_called_once()


if __name__ == "__main__":
    unittest.main()

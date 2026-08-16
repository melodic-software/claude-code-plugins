# Positive fixture (Python): one planted defect per rule.
from unittest.mock import MagicMock

from subject import add, notify


def test_add_runs():
    add(2, 3)


def test_add_matches_itself():
    assert add(2, 3) == add(2, 3)


def test_notify_calls_mailer():
    mailer = MagicMock()
    notify(mailer)
    mailer.send.assert_called_once()

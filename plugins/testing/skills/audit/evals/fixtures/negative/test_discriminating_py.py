# Negative fixture (Python): genuinely discriminating tests — zero findings.
import pytest

from subject import add, divide, notify


def test_add():
    assert add(2, 3) == 5


def test_divide_by_zero():
    # exception oracle, no assert keyword
    with pytest.raises(ZeroDivisionError):
        divide(1, 0)


@pytest.mark.skip(reason="not implemented yet")
def test_pending():
    add(0, 0)


def test_notify_records_and_calls(mocker):
    # mock interaction PLUS a real value assertion — not a mock-only oracle
    mailer = mocker.Mock()
    receipt = notify(mailer)
    mailer.send.assert_called_once()
    assert receipt.total == 42

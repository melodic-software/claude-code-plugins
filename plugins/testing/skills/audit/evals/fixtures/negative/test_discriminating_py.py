import pytest

from subject import add, cumsum, divide, notify


def test_add():
    assert add(2, 3) == 5


def test_divide_by_zero():
    # uses pytest.raises instead of an assert statement
    with pytest.raises(ZeroDivisionError):
        divide(1, 0)


@pytest.mark.skip(reason="not implemented yet")
def test_pending():
    add(0, 0)


def test_notify_records_and_calls(mocker):
    # mock interaction and a value assertion
    mailer = mocker.Mock()
    receipt = notify(mailer)
    mailer.send.assert_called_once()
    assert receipt.total == 42


def test_callback_flag(mocker):
    # value assertion on an attribute named like a mock property (.called_back)
    mailer = mocker.Mock()
    receipt = notify(mailer)
    mailer.send.assert_called_once()
    assert receipt.called_back is True


def test_cumsum_recurrence():
    # expectation built from the same callee with different arguments
    assert cumsum(4) == cumsum(3) + 4

from checkout import total


def test_total_adds_shipping():
    assert total([10, 5], shipping=3) == 18

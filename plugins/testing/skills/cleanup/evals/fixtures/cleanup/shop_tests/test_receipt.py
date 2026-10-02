import time
import unittest

from shop.checkout import order_total


class ReceiptTest(unittest.TestCase):
    def test_total_is_computed_quickly(self):
        start = time.monotonic()
        # 50 and 10 are below the threshold: 60 + 12 = 72.
        self.assertEqual(order_total([50, 10]), 72.0)
        self.assertLess(time.monotonic() - start, 1.0)


if __name__ == "__main__":
    unittest.main()

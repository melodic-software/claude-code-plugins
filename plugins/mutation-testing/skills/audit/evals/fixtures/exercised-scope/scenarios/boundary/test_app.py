import unittest

from app import price_with_tax


class PriceWithTaxTest(unittest.TestCase):
    def test_large_order_gets_discount_then_tax(self):
        # 1000 less 10% is 900; 900 plus 20% tax is 1080.
        self.assertEqual(price_with_tax(1000), 1080.0)


if __name__ == "__main__":
    unittest.main()

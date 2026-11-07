import unittest

from app import price_with_tax


class PriceWithTaxTest(unittest.TestCase):
    def test_small_order_pays_tax_without_discount(self):
        # 50 is below the discount threshold; 50 plus 20% tax is 60.
        self.assertEqual(price_with_tax(50), 60.0)


if __name__ == "__main__":
    unittest.main()

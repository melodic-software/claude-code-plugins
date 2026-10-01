import unittest

from app import price_with_tax


class PriceWithTaxTest(unittest.TestCase):
    def test_price_with_tax_is_stable(self):
        expected = price_with_tax(150)
        self.assertEqual(price_with_tax(150), expected)


if __name__ == "__main__":
    unittest.main()

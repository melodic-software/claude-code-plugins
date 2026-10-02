import unittest

from app import price_with_tax


class PriceWithTaxTest(unittest.TestCase):
    def test_price_with_tax_runs(self):
        price_with_tax(150)


if __name__ == "__main__":
    unittest.main()

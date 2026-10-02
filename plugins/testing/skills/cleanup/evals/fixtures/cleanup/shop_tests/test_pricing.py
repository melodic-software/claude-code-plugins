import unittest

from shop.pricing import Product, price_with_tax


class PricingTest(unittest.TestCase):
    def test_price_is_consistent(self):
        self.assertEqual(price_with_tax(150), price_with_tax(150))

    def test_small_order_pays_tax_without_discount(self):
        # 50 is below the discount threshold; 50 plus 20% tax is 60.
        self.assertEqual(price_with_tax(50), 60.0)

    def test_product_name(self):
        self.assertIsNotNone(Product("lamp").name)


if __name__ == "__main__":
    unittest.main()

import unittest

from shop.handlers import ShippingHandler


class ShippingHandlerTest(unittest.TestCase):
    def test_heavy_parcel_fee(self):
        ShippingHandler().fee(25)


if __name__ == "__main__":
    unittest.main()

TAX_RATE = 0.2
DISCOUNT_THRESHOLD = 100
DISCOUNT_RATE = 0.1


def price_with_tax(amount):
    if amount > DISCOUNT_THRESHOLD:
        amount = amount * (1 - DISCOUNT_RATE)
    amount = amount * (1 + TAX_RATE)
    return round(amount, 2)

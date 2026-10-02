from shop.pricing import price_with_tax


def order_total(amounts):
    return round(sum(price_with_tax(a) for a in amounts), 2)

# Checkout

## Parts

- The checkout page, `shop/checkout/page.py`

## Sub-features

None

## Entry points

- The Checkout button on /cart: driven

## Reset

`python3 shop/reset.py --orders`

## Drive

1. Open http://127.0.0.1:8080/cart and press Checkout.
2. Type the coupon code `HERON-12` into the coupon field and press Apply.
3. Read the order total shown under the coupon field.

## Gotchas

- The total updates a moment after Apply; read it once the spinner is gone.

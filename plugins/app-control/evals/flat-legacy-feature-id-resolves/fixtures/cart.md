# Cart

A user collects items before paying.

## Reset

Delete `shop/data/carts.db` and restart the app.

## States

- empty: the basket shows `Your cart is empty`
- filled: the basket lists each item with a quantity

## Entry points

- the `Add to cart` button on a product page
- `POST /api/cart/items`

## Drive

- Open `/cart`, add the first item, open the basket.

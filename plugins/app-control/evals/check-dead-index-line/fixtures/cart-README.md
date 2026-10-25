# Cart

A shopper adds an item and sees it in the cart.

## Parts

- add: the item appears in the cart with quantity 1

## Sub-features

none

## Entry points

- the `Add to cart` button on a product page: driven

## Reset

Delete `shop/data/cart.db` and restart the app.

## Drive

- Open `/products/1`, choose `Add to cart`, then open `/cart`.

## Gotchas

- The cart is per browser session; a fresh browser starts empty.

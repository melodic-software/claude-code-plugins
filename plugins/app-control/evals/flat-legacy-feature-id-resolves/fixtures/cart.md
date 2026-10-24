# Cart

## Reset

`python3 shop/reset.py --carts`

## States

- Empty: the page reads "Your cart is empty".
- Filled: one row per item.

## Entry points

- The cart icon in the header

## Drive

1. Open http://127.0.0.1:8080/ and press the cart icon.
2. Add the item with SKU `HERON-23` from the suggestions row.
3. Read the item count on the cart icon.

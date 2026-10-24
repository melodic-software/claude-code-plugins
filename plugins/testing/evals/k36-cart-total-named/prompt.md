---
description: "The k36-cart-total task with the testing:write skill named in the prompt, so the with-arm loads it whether or not its description would trigger: counts tests that cannot fail and records whether a refactor step ran after the tests went green. The refactor grader is a probe of the TDD cadence, not a quality bar"
tags: [testing, write, tdd, refactor-probe]
runs: 3
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Bash, Edit, Write, Skill]
expected_outcome: "Adds total_cents and apply_coupon to cart.py with unittest tests in tests/test_cart.py that check each criterion against stated values, runs the suite until it passes, and tidies the code with the suite still passing"
---

This repository has a small `Cart` class in `cart.py` and its unit tests in `tests/test_cart.py`.
Run the tests with `python3 -m unittest discover -s tests -t .`. Use the `testing:write` skill if
you have it.

Add two methods to `Cart`, with unit tests in `tests/test_cart.py`:

- `total_cents()` returns the order total in cents.
- `apply_coupon(code)` applies a coupon code to the cart.

Acceptance criteria:

1. An empty cart totals 0.
2. The total is the sum of `unit_price_cents * qty` over every line.
3. A line with a quantity of 10 or more gets 10% off that line, rounded half up to a whole cent
   (11 units at 1005 cents total 9950, not 9949).
4. The coupon `SAVE5` takes 500 cents off a total of 5000 cents or more, after line discounts, and
   does nothing below 5000.
5. Any other coupon code raises `ValueError`, and the cart is unchanged.

The work is done when every criterion has a test and the whole suite passes.

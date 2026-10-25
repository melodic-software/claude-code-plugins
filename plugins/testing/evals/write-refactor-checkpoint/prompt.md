---
description: "The k36-cart-total task with no testing config layer and the testing:write skill named: tdd_refactor_step resolves to its default, on, and the skill reports a Refactor checkpoint line after green, so a skipped Refactor step shows in the reply"
tags: [testing, write, tdd, settings, refactor-checkpoint]
runs: 3
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Bash, Edit, Write, Skill]
expected_outcome: "Resolves tdd_refactor_step=on from the default, adds total_cents and apply_coupon with unittest tests that check each criterion, runs the suite until it passes, and ends with a Settings line and at least one line beginning 'Refactor checkpoint:' that names what was tidied or why nothing needed it"
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
   (15 units at 3 cents total 41, not 40).
4. The coupon `SAVE5` takes 500 cents off a total of 5000 cents or more, after line discounts, and
   does nothing below 5000.
5. Any other coupon code raises `ValueError`, and the cart is unchanged.

The work is done when every criterion has a test and the whole suite passes.

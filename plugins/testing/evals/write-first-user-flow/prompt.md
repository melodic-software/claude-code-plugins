---
description: "A command-line feature with acceptance criteria, first_test: user-flow in docs/conventions/testing.yaml, and the testing:write skill named: the first test file written is the end-to-end command test, before any unit test"
tags: [testing, write, tdd, settings, first-test]
runs: 3
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Bash, Edit, Write, Skill]
expected_outcome: "Resolves first_test=user-flow from docs/conventions/testing.yaml, writes tests/test_cli.py, which runs the total command, before touching tests/test_cart.py, adds the command and the Cart method, runs the suite until it passes, and ends with a Settings line naming that file"
---

This repository has a small `Cart` class in `cart.py` with unit tests in `tests/test_cart.py`, and
a `shop.py` command line that has no commands yet. Run the tests with
`python3 -m unittest discover -s tests -t .`. Use the `testing:write` skill if you have it.

Add a `total` command: `python3 shop.py total <cart-file>` reads a cart file holding one line per
item, `sku,unit_price_cents,qty`, and prints the order total in cents. Compute the total in a new
`Cart.total_cents()` method.

Acceptance criteria:

1. An empty cart file prints `0`.
2. The total is the sum of `unit_price_cents * qty` over every line.
3. A line with a quantity of 10 or more gets 10% off that line, rounded half up to a whole cent
   (15 units at 3 cents total 41, not 40).
4. A malformed line prints an error naming its line number to stderr and exits with status 1.

Put the end-to-end test that runs the command in `tests/test_cli.py` and the unit tests of `Cart`
in `tests/test_cart.py`. The work is done when every criterion has a test and the whole suite
passes.

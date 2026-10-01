# Expected outcomes: cleanup fixture

What `/testing:cleanup shop_tests` must do over this fixture. The cleanup evals grade against this file.

## Setup per run

The fixture is committed on `main`; the run happens on a feature branch with a clean tree. The
`testing` and `mutation-testing` plugins are installed, and `.claude/mutation-testing.md` sets
`tool: manual` with `test-command: python -m unittest {tests}`. The user names
`shop_tests/test_receipt.py::test_total_is_computed_quickly` as flaky unless a case says otherwise.
`shop_tests/checkout.test.sh.fixture` is copied to `shop_tests/checkout.test.sh` first; the suffix
keeps this repository's own test runner from running it as a suite.

## Scanner findings (step 1)

| Location | Rule |
|---|---|
| `shop_tests/test_handlers.py:7` | `testing/audit/rule-zero-assertion` |
| `shop_tests/test_pricing.py:8` | `testing/audit/rule-recomputed-expectation` |
| `shop_tests/test_pricing.py:15` | `testing/audit/rule-weak-oracle` (report-only) |
| `shop_tests/checkout.test.sh:1` | `testing/audit/rule-zero-assertion` (`bash-harness`, `block_model: file`) |

`test_small_order_pays_tax_without_discount` has no finding and is not a candidate: it is kept.

## Decisions (steps 4-5)

| Test | Row | Why | Action |
|---|---|---|---|
| `test_total_is_computed_quickly` | 1 | named flaky | `@unittest.skip("test-change: quarantined <today + 7 days>: flaky, ...")`, applied before the recording run |
| `test_price_is_consistent` | 2 | CF (recomputed expectation) and K: `shop/checkout.py:5` calls `price_with_tax` | rewrite to `self.assertEqual(price_with_tax(150), 162.0)`: 150 is above the threshold, 150 x 0.9 = 135, plus 20% tax = 162 |
| `test_product_name` | 4 | CF (weak oracle, defect quoted) and a positive no-contract statement: `Product.name` is a trivial getter returning the constructor argument (`shop/pricing.py:17-19`) | deletion proposed, applied only on the user's yes |
| `test_heavy_parcel_fee` | 2 | CF (zero assertion) and K: `ShippingHandler` is reached through the `register("shipping")` registry (`shop/handlers.py:12`, `:20-21`), a lookup by string that a search for callers misses | rewrite to `self.assertEqual(ShippingHandler().fee(25), 15)`; never a deletion |
| `checkout.test.sh` | 2 | CF (zero assertion), whole-file test | rewrite: check the printed total equals `60.0` and exit non-zero otherwise; never a deletion or merge |

## Gate (steps 3 and 6)

With the quarantine applied, the recording run's K0 includes the `price_with_tax` mutants on lines
7, 9 and 10 that `test_small_order_pays_tax_without_discount` kills (line 8 survives: no detected
input is above the threshold). With the rewrites applied and the deletion not approved, the replay
loses none of them: `Gate: pass`. The line 8 mutant becomes killed by the rewritten
`test_price_is_consistent`, a gain.

A lost kill: if `test_small_order_pays_tax_without_discount` is changed during the batch to
`self.assertGreater(price_with_tax(50), 0)`, the line 7 and line 9 mutants survive the replay,
`Gate: block`, and the candidate change listed for both is `shop_tests/test_pricing.py`, the batch's
changed test that imports `shop/pricing.py`.

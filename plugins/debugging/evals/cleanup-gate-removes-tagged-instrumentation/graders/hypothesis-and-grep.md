---
type: llm
focus: trace
---

PASS if, after the last edit that removed instrumentation, the session (1) searched the source for the `[DEBUG-a4f2]` tag and the search found nothing, (2) ran `repro_checkout.py` and it exited 0, and (3) ran the `test_checkout` regression test and it passed; and the final reply states the confirmed cause (the price lookup lower-cased an upper-case SKU, so `PRICES[sku.lower()]` raised KeyError) as text for the commit message or PR description.

FAIL if any of the tag search, the `repro_checkout.py` run, or the regression-test run happened only before the removal edits or not at all, if the search still found tagged lines, if the loop or the test did not pass, or if the reply never states the cause for the commit or PR record.

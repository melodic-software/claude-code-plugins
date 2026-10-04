---
type: llm
focus: { source: file, path: retry.py }
---

PASS if every behavior in this retry.py exists on one of the two sides being combined: main's rename of `max_retries` to `max_attempts` (field and loop bound), and feature's `backoff_jitter` field defaulting to 0.0 plus `random.uniform(0, options.backoff_jitter)` added to the exponential delay. Renaming the feature's uses of the old name to `max_attempts` counts as combining, not inventing.

FAIL if the file adds anything neither side had: a new option or parameter, a changed default, a different backoff formula, a cap on the delay, logging, or a new exception type. FAIL if either side's behavior is missing.

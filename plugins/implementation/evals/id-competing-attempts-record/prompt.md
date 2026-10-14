---
description: "Competing attempts selection: the run summary writes one record line per passing attempt in the exact template 'attempt <n>: chosen by <rule clause>' / 'attempt <n>: set aside by <rule clause>', picks by the plan's rule clause that decides, and gives the failed attempt no record line."
tags: [implement-dispatch, concise-rollout, competing-attempts, read-only]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The selection record has 'attempt 3: chosen by' and 'attempt 1: set aside by' lines whose clause is the rule's no-new-dependency clause, and no 'attempt 2:' line; attempt 2's verifier gaps, if mentioned, are reported apart."
---

/implementation:implement-dispatch phase-2 Don't dispatch anything, don't read files and don't run commands. Phase 2's competing attempts already ran and their verifiers returned; print the selection record for the run summary, then stop.

The plan (approved, interactive run): phase 2, "half-even rounding in `billing/invoice.py`", is marked `multi-shape` in the routing table's `Attempts` column, and three attempts ran. Its selection rule: "Prefer the attempt that adds no new dependency; among those, prefer the one with the fewest changed lines."

Verifier returns against phase 2's acceptance criteria, each attempt's diff taken from the commit the phase started at:

- attempt 1 (branch `feat/invoice-rounding-attempt-1`): PASS on every criterion. Adds the `py-moneyed` package to `requirements.txt`; 31 changed lines.
- attempt 2 (branch `feat/invoice-rounding-attempt-2`): FAIL. Criterion 2 failed: `round_total(2.665)` returned 2.67, expected 2.66.
- attempt 3 (branch `feat/invoice-rounding-attempt-3`): PASS on every criterion. Uses the standard library's `decimal` module, no new dependency; 48 changed lines.

---
outcome: early-exit
tier: B
---

# Design resolution: sonnet-5-5-adoption

Tier B. Three of the four change sites are documentation pointers (Tier C). The fourth is a
localized contract tweak to one CLI script, so no `/planning:design` run is needed.

## Type sketch: `check-usage-limit-reset.py`

- New optional flag `--received <ISO-8601 with offset or Z>`: when the limit message was shown.
- `parse_reset(text, *, now=None, received=None) -> datetime`.
  - With `received`, the reset is the first occurrence of the stated wall-clock time, in the
    stated zone, that is at or after `received`. The message's own day is the anchor, so a time
    already past on that day resolves to the next day.
  - Without `received`, behavior is unchanged: today's wall time anchored on `now`, plus the
    existing pm-before-noon rule.
- Exit codes 0-3 keep their meanings. No new exit code.

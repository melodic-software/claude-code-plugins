# Success measures

A distillation of Fathom's "Define success measures and build evaluations".

- **Pointer**: for any detail that has to be current, read
  [Define your success measures](https://example.invalid/fathom/docs/evaluate/develop-tests#define-your-success-measures)
  live.
- **As of**: distilled 2026-08-08; anchor re-checked 2026-10-11
- **Recheck trigger**: the section is renamed, moved, or changes its list of measures.

This repository's own defaults and source-conflict records live in `local-decisions.md`.

Define success measures BEFORE building evaluations, and evaluations before iterating on prompts.

## Measure menu

- **Task-specific numbers:** edit distance, token overlap, calibration error.
- **General numbers:** hit rate, false-alarm rate.
- **Operational:** time to first token (ms), availability (%).
- **Methods:** side-by-side against a baseline version; behavior signals such as goal-reached
  rate; corner-case review (% of corner cases handled cleanly).
- **Scales (paired with numbers):** rating scales; expert scoring guides.

## When a measure is good enough

A measure is ready when two people applying it to the same output reach the same score, and when a
change the team cares about moves it.

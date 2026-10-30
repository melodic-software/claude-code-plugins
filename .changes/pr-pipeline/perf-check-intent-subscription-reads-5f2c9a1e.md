---
bump: patch
---

### Changed

- pr-verify's `check-intent` hands its resolved pull request, spec and trusted PR text to
  `check-intent-subscription` in one `reads` job output, written before the model runs, so a
  handoff no longer repeats the resolver's and select-trusted-text's reads. The subscription job
  still runs the trigger gate, whose head must match the carried one, and reads everything again
  when the output is missing, malformed, too large, or from another run attempt.

---
bump: patch
---

### Fixed

- **`research`: a sidecar abstract must quote one of its claims, and the index must mirror it
  unchanged.** An abstract that named no claim ID escaped the restatement check, so a seed abstract
  could drop its claim's exception in both the sidecar and its index copy. Now
  `scripts/check-restatement-labels.py` fails a sidecar that declares a claim with an `id:` but
  whose abstract quotes none of its claims as `M1: "<claim>"`, and fails an index abstract bullet,
  `- <section>: <abstract>`, that is missing or differs from the sidecar's value byte for byte.
  Table rows that restate a claim with no ID, and index lead-ins whose scope outruns their
  pointers, stay with the verifier under row 12
  ([#13200](https://github.com/melodic-software/claude-code-plugins/issues/13200)).

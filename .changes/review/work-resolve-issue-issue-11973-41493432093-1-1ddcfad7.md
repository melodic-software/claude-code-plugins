---
bump: major
---

### Removed

- The unused `ratchet_offer` setting leaves the review plugin: its plugin option, its key in `schemas/review.schema.json` and its rows in the README and `reference/config.md`. A `docs/conventions/review.yaml` that still sets it gets an unknown-key WARN from `/review:setup check`, and its other keys still count; delete the line to clear it. To keep ratchet offers off, set `ratchet_offer` on the corrections plugin (its plugin option or `docs/conventions/corrections.yaml`).

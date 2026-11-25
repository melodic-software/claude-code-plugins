---
bump: patch
---

### Fixed

- `save_point.py fill` and `amend` check American spelling with one `typos` run per call instead of one per slot, so a shape-4 `fill` takes about a quarter of the time.
- `hop_chain.py --budget` generates its chains through `save_point.main` in-process instead of a new interpreter per call, which brings the `hop_chain.test.sh` suite from about 100 s to under 20 s with the same checks.

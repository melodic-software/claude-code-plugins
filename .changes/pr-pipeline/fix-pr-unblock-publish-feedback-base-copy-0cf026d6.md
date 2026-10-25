---
bump: patch
---

### Fixed

- pr-unblock's publish-feedback step loads again. It runs from a copy of `.github/scripts/pr-unblock/` alone, and the adjudicator module it imports had started loading `request-budget.mjs`, whose `.github/actions` imports do not resolve from that copy, so every address-feedback run failed at publish with `ERR_MODULE_NOT_FOUND`. `adjudicate-feedback.mjs` now loads `request-budget.mjs` only in its `prepare` command, which runs from the full base checkout.

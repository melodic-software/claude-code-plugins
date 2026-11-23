---
bump: patch
---

### Added

- Eval case `evals/ro-vendor-caller-auto-delegation-off/`: a Caller contract request with `vendors.auto_delegation` off makes `/multi-agent:route vendors` stop after `route.sh` and return only `run here`, with no board fetch, no `vendor-decide`, no `delegate` run and no vendor recommendation.

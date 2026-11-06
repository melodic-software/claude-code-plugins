---
bump: minor
---

### Added

- A `verification` level and per-skill `verification_skills` in `docs/conventions/session-flow.yaml`, read from the default branch by `lib/read-verification.sh`. `/session-flow:orchestrate` skips imperative 3 verifier under `light` and `off` in a primed session, and `/session-flow:workflow pre-pr` step 2 never dispatches the fresh-context reviewer under `light` and `off` and always does under `strict`.

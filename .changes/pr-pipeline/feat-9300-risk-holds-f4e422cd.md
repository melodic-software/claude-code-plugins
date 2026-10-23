---
bump: minor
---

### Changed

- Merge authority: a review flag holds only for a cost increase, a trusted-actor widening or a CRITICAL security finding; other open findings are reported. New **Trusted-actor widening** rule: a change that adds or widens an entry in `trusted-actors.json` waits for the owner whatever `high-path-floor` says; a pure removal merges.

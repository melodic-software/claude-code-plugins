---
bump: patch
---

### Changed

- pr-unblock skips its API-key calls (resolve-conflicts, address-feedback, review-dependency and fix-ci) while `vars.CLAUDE_API_KEYS_DISABLED` is `true`. Each handoff job then reads no check posted, as for a key the credit read skipped, and the subscription call starts directly. An unblock round no longer spends the key call's runner setup, GitHub reads and job hop before the subscription leg works. With the switch off the chain is unchanged; fix-ci-rung-up keeps its key call.

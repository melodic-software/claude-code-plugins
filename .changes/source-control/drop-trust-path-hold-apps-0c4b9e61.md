---
bump: none
---

Test-only: the merge-holds sync test checks that the trust-path hold's `apps` is non-empty instead of naming `melodic-agent[bot]`, and checks ci-status's exempt-author patterns as the generator writes them with path holds on and the Dependabot-only guard it adds with them off; the plugin ships no change.

---
bump: none
---

ci-status's two merge-queue author checks call the hold config's merge-holds.mjs authorSkip through one verify_judged helper in place of two copies of the rule in jq; which authors they judge is unchanged.

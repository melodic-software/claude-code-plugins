---
bump: patch
---

### Added

- A new test checks each escalation event class in `guardrails.md` against the stop rule. `gate-failure`, `verification-divergence`, `admission-rejection` and `demotion` stop for a person only under the stop rule. `structural-plan-approval` stops only on an intent or primary-design change, and `untrusted-provenance` always stops. The test also checks that `check-security-binding.mjs` requires a route for every class, and that `merge_policy.C5` (untrusted-provenance work) stays `human`.

---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/harness-config.yaml`, read from the default branch by `lib/read-verification.sh`. Under `light` and `off`, `/harness-config:audit-automation-gaps` dispatches neither its refusal gate nor its implementation reviewer and lists candidates as `unverified`; `/harness-config:audit-instructions` skips its Phase C verifiers, `/harness-config:audit-pass` its apply-verify and main-session verification, and `/harness-config:audit-prompting-postures` its Phase D verifier, each recording `verification: skipped (<level>)` and marking results `(unverified)`.

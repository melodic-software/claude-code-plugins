---
bump: major
---

### Changed

- The bundled enforcement-ladder copy is now 3.0.0: five tiers, with a new Tier 3 Verification (`runtime-verification`, and `formal-verification` as opt-in) between static analysis and guidance, so Guidance is now tier 4 and Human only tier 5. The rung id `semgrep-rule` is renamed `syntax-pattern-rule` and is read as an alias, with a printed notice, through 3.x. `custom-analyzer` and `architecture-test` are defined by capability, and the ladder adds a Proportion section and an Order of work section.

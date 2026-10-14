---
bump: minor
---

### Changed

- The `code-reviewer` and `security-reviewer` agents are shorter: the model-pin explanation shrinks to its pointer record, the Fowler smell definitions go (the smell names and house extensions stay), and rationale beside kept rules is cut. Every review rule, gate and output field stays.
- `quality-gate`'s body is shorter (harness rationale and purpose prose cut), and `fanout`'s hub drops its spoke-path rationale.
- The `quality-gate`, `ratchet` and `explain-change` descriptions are shorter, with one trigger per use. `quality-gate`'s no longer routes plan-reach and rename questions to other plugins, and `explain-change`'s drops the "explain this change" and "PR explainer" phrases. `fanout` and `audit-enforceability` get a shorter lead and keep their trigger phrases. `setup`'s description is a one-line summary, since it is user-invoked.

### Added

- An outcome eval case, `qg-security-search-sqli`, that reaches `quality-gate` security mode and the `security-reviewer` agent, and frozen trigger-probe sets under `probes/` for five skills.

### Fixed

- The `guard-removal-*` eval prompts say no pull request is open, so a sandbox without forge access no longer stops the review on an unresolved base; the `guard-removal-short-title` judge accepts any short title as the example.

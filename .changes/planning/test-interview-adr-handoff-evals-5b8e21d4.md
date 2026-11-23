---
bump: patch
---

### Added

- Eval cases `interview-adr-handoff-auto` and `interview-adr-handoff-off` grade the interview's
  Decision record step by `domain_docs`: under `auto` a resolved, hard-to-reverse decision that
  weighed an alternative goes to `/architecture:adr`; under `off` it does not, and its register
  row records an ADR candidate. Each case loads an `architecture` stand-in so only the setting
  decides the handoff.

---
bump: patch
---

### Changed

- The agent brief's acceptance-criteria rule names one more form to avoid: where CI selects test
  suites by the paths a change touches, a check that a suite the change does not reach passes in
  its CI can never be proven, because that run never happens.

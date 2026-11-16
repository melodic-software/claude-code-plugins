---
bump: minor
---

### Added

- `/prototype:pressure-test vendor-fit` checks whether an outside service does what the rules need.
  The logic module stays pure; a thin adapter behind the app's own port is the only file that
  calls the vendor's sandbox, with sandbox keys from the environment and synthetic records only,
  never production credentials or regulated data. The terminal shell shows each check passing or
  failing, and the durable note records the verdict. Eval case `pt-vendor-fit-no-sandbox-key`.

### Changed

- `/prototype:explore-directions` keeps every write stubbed by default. When the question names a
  write's behavior, that write may go to the vendor's sandbox on the real stack, stated at the top
  of the prototype, never against production or regulated data. Eval case
  `ed-write-behavior-sandbox`.

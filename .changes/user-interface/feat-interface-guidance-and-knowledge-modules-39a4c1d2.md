---
bump: minor
---

### Added

- `/user-interface:audit` reviews a diff the way a design engineer would, leading with a verdict and a Before, After, Why table and naming what needs a real device, applies the plain-language copy rules at every scope, and its `launch` scope adds a pre-launch sweep: recon, a leftovers pass (dev tools, scaffolding routes, debug output, secrets, stale markers), a Ship or Not yet verdict, and the keyboard, screen reader, form, theme and phone checks a person still has to run.

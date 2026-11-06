---
bump: minor
---

### Added

- A hub's `## Mask` may hand off to its driving tool's control skill with the single line ``The driving tool's `## Mask`.``. The target is the `.md` path in the first code span on the hub's `Driving tool:` line, resolved beside the copy of the hub that was read (its project directory, or a plugin hub's repository), never the checkout under test, and under drive's `--trusted-root` inside the trusted root. The target's `values:` sources resolve against its own `config/` and `cli/`. A target that cannot be read leaves every capture `not-checked`.
- A `values:` `cli/` source may print exactly one line, `none: <reason>`, and exit 0, and then resolves with no values. A non-zero exit, empty output or any other line beside it still leaves the source unresolved. `report.json` records each such source in the new `values_none` field (`source`, `reason`).
- `/app-control:map check` follows the hand-off and runs `mask-missing` against the target, and reports a target that cannot be read.

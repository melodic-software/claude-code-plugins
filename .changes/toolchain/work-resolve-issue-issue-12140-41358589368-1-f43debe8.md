---
bump: minor
---

### Added

- `/toolchain:ratchet` has a per-file mode. `add --per-file` records one ceiling per file, `check` fails a file above its ceiling even when the total fell, and `propose-tighten` lowers each file's ceiling as its count falls.
- The skill states the lint rollout rule: a mechanical fix gets a codemod and then error severity, otherwise a per-file baseline at error severity (the linter's native baseline where one exists, the ratchet's per-file mode otherwise), and warn severity only as a step with an end date in the ceilings entry.
- Break glass: an inline `ratchet-break-glass(<counter>)` comment with a reason, an expiry and the approving person holds one violation above a file's ceiling. One missing a field or past its expiry fails the check. The ceilings file's `break_glass` key turns it on or off, and the new `ratchet_break_glass` option (default off, so a repository opts in) sets that key for a file that has none.

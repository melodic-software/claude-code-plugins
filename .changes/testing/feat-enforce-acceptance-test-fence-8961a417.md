---
bump: minor
---

### Changed

- `/testing:write` blind-author mode shows the user one plain-language line per acceptance test before committing it, and adds an opt-in `Edit` deny rule on the acceptance-test directory for the implementer's run; the empty-diff check stays the gate, since a deny does not stop a script writing files.

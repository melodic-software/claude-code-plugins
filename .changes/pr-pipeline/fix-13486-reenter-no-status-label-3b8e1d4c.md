---
bump: patch
---

### Fixed

- `intake-reenter` no longer takes the answered `status:` label off an issue, and a failed run no longer puts it back: it writes no label. Work status at `needs-triage` is the claim, so a run that reads it dispatches nothing, even on an issue that still carries a `status: needs-decision` or `status: needs-info` label.

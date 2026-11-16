---
bump: minor
---

### Added

- `record-decision` Step 3: a citation sweep lists, by `file:line`, every tracked line citing the retired record's identifier or path, and proposes pointing each at the new record or dropping it, applied in the same change behind the same yes. It runs for every `adr_retirement` value and for a partial reversal, where only citations of the reversed part change.
- `record-decision audit`: each retire candidate lists the lines citing it; the audit stays read-only.
- `record-decision` Step 4: after a record is written, it offers one pointer comment at the code the decision governs, citing the record in the repository's own form, and writes it only after a yes.

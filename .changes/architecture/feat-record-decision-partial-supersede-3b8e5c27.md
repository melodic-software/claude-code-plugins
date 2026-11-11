---
bump: minor
---

### Added

- `record-decision` Step 3: when a new decision reverses only part of a record, the old file stays whatever `adr_retirement` says, and after a yes its status becomes superseded in part by the new identifier, naming the part, in the words and form the existing records use.
- `record-decision`: a changed decision gets a new record, never an amendment inside the accepted one; an accepted record is edited in place only to rename a term or set its status. No structured status or supersedes fields are added.
- Two invocation probes for editing an ADR and for a partial reversal.

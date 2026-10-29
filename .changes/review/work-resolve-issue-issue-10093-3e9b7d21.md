---
bump: patch
---

### Changed

- `/review:security-review` opens each inline comment for a `manifest <field>: flag` with that flag's summary line, `manifest <field>: flag, <reason>`, and puts its severity line last above the footer. The pr-unblock lane matches that first line to find a `dependencies` flag it may settle without a person.

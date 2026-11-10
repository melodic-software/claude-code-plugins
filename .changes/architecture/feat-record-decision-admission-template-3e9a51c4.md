---
bump: minor
---

### Added

- `/architecture:record-decision` ships a default template, `templates/adr.md` (title, status, a few sentences of context, decision and why, Considered options when alternatives were weighed, optional Consequences), and recommends it when a repository has no ADR convention. It still writes nothing until the human chooses, and a repository's own convention always wins.
- Two optional decision-record settings, `adr_template` and `adr_extra_triggers`, resolved through the four-layer cascade (`userConfig` for the template, the team `<home>/architecture.yaml`, the personal `<home>/architecture.local.yaml`), with a schema in `schemas/architecture.schema.json`.

### Changed

- The ADR admission test now requires a real alternative that was weighed, plus at least one of: hard to reverse, shapes the system's structure, shapes a key quality attribute such as security, privacy or performance, or a team's extra trigger. Surprising without context is a reason to write the record, no longer a gate. The test lives only in this skill; callers hand decisions to it.
- `/architecture:record-decision` names `/domain-driven-design:ubiquitous-language` for term definitions, and the interview, plan close-out and `remove-comments` handoffs in its Composition table.

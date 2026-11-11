---
bump: minor
---

### Added

- `audit` step 5: code names that look like an existing term's concept but are neither the term nor its `Avoid:` words are reported with a count and `file:line`, each proposed as a new `Avoid:` word through `curate`. Duplicated logic stays with `/code-metrics:audit-duplication`.
- `curate` removal reports every surviving reference to a removed term (bold mentions in other entries, the glossary index, docs), and its report names where each removed term's meaning went.
- `curate` names `CODEOWNERS` on the glossary path as the route for a team that wants a domain owner to review glossary changes; there is no reviewer setting.
- New eval case `cl-audit-unrecorded-synonym`, and three invocation probes for codebase terminology, a named glossary file and the domain model.

### Changed

- Glossary contract: an `Avoid:` line holds only other names for the same concept; a word with its own meaning gets its own entry or stays off. `audit` reports a hit on such a word as a candidate entry, not drift.
- `audit`'s Implementation group also names a constant or setting that lives in code, and its cut-sentence suggestion adds operating detail to user docs or command help.
- Description adds 'tidy our codebase terminology' and 'the terms in our domain model' as triggers.

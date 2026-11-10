---
bump: minor
---

### Added

- Glossary contract: a term is used bare inside its own bounded context and qualified by its context wherever contexts meet (the glossary index, integration code, cross-context docs).
- Glossary contract: a concept tenants rename on their own screens keeps one model term, recorded as `Shown to users as: configurable per tenant`; tenant words are configuration, never synonyms or `Avoid:` words.
- `curate` weighs candidate terms in order: domain experts, then the code's existing usage, then published domain standards as inputs, never authority, researched through `/discovery:research` when none is known. Users' differing words go on `Shown to users as:`.

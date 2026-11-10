---
bump: minor
---

### Added

- `/code-tidying:remove-comments` treats deleted rationale for one of the repository's own decisions that names the alternative it beat as an ADR candidate: an interactive run with the `architecture` plugin hands it to `/architecture:record-decision`, which applies the admission test; otherwise the report lists it under a new "ADR candidates" heading. The reshape flag still applies.

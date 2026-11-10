---
bump: minor
---

### Added

- `/code-tidying:remove-comments` treats deleted rationale for one of the repository's own decisions that names the alternative it beat as an ADR candidate, under the `necessary` and `none` postures. The report lists it under a new "ADR candidates" heading, and in an interactive run with the `architecture` plugin the orchestrating skill (not the `comment-reviewer` agent) hands each one to `/architecture:record-decision`, which applies the admission test. The reshape flag still applies.

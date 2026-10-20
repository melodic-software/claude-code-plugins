---
bump: patch
---

### Fixed

- Team settings now resolve a `research_paths`, `persona_paths` or `output_home` entry that does not exist yet through its deepest existing ancestor before the root, dot and outside-the-project checks, so a committed link to the project root can no longer carry `rootlink/.claude` or `rootlink/.github/workflows` into a dot directory. `rootlink/new` stays allowed.

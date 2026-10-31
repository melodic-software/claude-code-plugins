---
bump: minor
---

### Added

- `/developer-experience:setup` `check` step 5 runs the new `lib/check-convention-facts.mjs` on the conventions file first. It lists each `every`, `all`, `always`, `never` or `each` claim outside `## Not yet` with its line, for the model to verify against the repository alongside its own reading.

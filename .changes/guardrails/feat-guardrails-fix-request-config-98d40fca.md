---
bump: minor
---

### Added

- `fix_request_post` (`block` default, `allow`) in a repository's tracked `docs/conventions/guardrails.yaml` sets whether `block-fix-request-post` blocks the PR-fix lane fix request there. Under `allow` the guard lets the post through. An untracked file, a missing key, a file that does not parse, or any other value keeps it blocking. New schema: `schemas/guardrails.schema.json`.

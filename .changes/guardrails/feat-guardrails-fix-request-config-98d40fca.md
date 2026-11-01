---
bump: minor
---

### Added

- `fix_request_post` (`block` default, `allow`) in `docs/conventions/guardrails.yaml` on a repository's default branch (`origin/HEAD`, never the working tree, so a session cannot lift the guard with an edit and `git add`) sets whether `block-fix-request-post` blocks the PR-fix lane fix request there. Under `allow` the guard lets the post through. No such ref or file, a missing key, a file that does not parse, or any other value keeps it blocking. New schema: `schemas/guardrails.schema.json`.

---
bump: minor
---

### Added

- `fix_request_post` (`block` default, `allow`) in `docs/conventions/guardrails.yaml` sets whether `block-fix-request-post` blocks the PR-fix lane fix request for sessions working in that repository. It is read from the session's repository at its local `origin/HEAD`, never the working tree or index, so an edit and `git add` do not lift it. Under `allow` the guard lets the post through, whichever repository it targets. No such ref or file, a missing key, a file that does not parse, or any other value keeps it blocking. The hook's known gaps name what still lifts it: a rewritten local `origin/HEAD`. New schema: `schemas/guardrails.schema.json`.

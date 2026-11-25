---
bump: minor
---

### Added

- `skills/triage/schemas/ci-verdict.schema.json`: the one shape of a `/work-items:triage --ci` verdict, with an optional `type` (the issue's Issue Type). A lane passes it as the run's output schema, narrowing the dimension keys and the type to enums, and `check-ci-verdict.mjs` reads it, so the shape is defined once.
- `check-ci-verdict.mjs --schema <path>` holds a verdict to a runner's narrowed copy of that schema; a `type` on a copy that leaves `type` out is reported as an unknown field.

### Changed

- `/work-items:triage --issue <n> --ci` returns its verdict as structured output and runs no script: the lane checks it with `check-ci-verdict.mjs` and `set-dimensions.sh --dry-run`. The run reads the open-issue and merged-pull-request lists from `issue.json` for its duplicate and blocker checks, and the repository's `## Triage rules` in `docs/conventions/work-items.md` when present.

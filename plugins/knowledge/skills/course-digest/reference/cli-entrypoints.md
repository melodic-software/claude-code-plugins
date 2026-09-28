# Course-digest CLI entrypoints call `main()` at import

Recorded park for
[#3421](https://github.com/melodic-software/claude-code-plugins/issues/3421),
a deepening candidate that would guard Node CLI entrypoints so import is
side-effect-free and tests drive each CLI through argv.

## Decision

**Park. Do not hoist.** The six course-digest extraction CLIs keep calling
`main()` at import. Sibling `video-digest` already ships `isMainModule`;
applying it here plus argv-driven CLI tests is unpaid.

- **Option A (taken):** no unpaid hoist. Importing any of the six files still
  runs `main()`. Pass-through helper extractions stay. `ai-briefing`'s
  `emit-slides-data.js` is the seventh entrypoint and is parked in that
  plugin's `skills/generate/reference/build-pipeline.md`.
- **Option B (declined):** guard each entrypoint (`isMainModule` /
  `import.meta.url`) and add usage, argument-validation, and artifact tests
  driven through argv; retire single-assertion extractions the CLI test now
  covers.

**Claim:** six course-digest Node CLIs call `main()` at import, so nothing
defined in those files can be exercised from a test without also launching the
CLI. `video-digest` already owns `isMainModule` in
`skills/video-digest/extraction/lib/cli-entrypoint.js`. Rolling that guard and
CLI-level tests onto course-digest is unpaid.
**Basis:** origin/main as of this record.
`analyze-code-repo.js` and `validate-extraction.js` end with bare `main();`.
`build-course-json.js`, `discover-resources.js`, `download-resources.js`, and
`extract-course.js` end with `main().catch(...)`.
`plugins/knowledge/skills/course-digest/extraction/` holds 37 `.js` files
against 10 `.test.js`. Commits 1e919f91a (#3398) and cd331b728 (#3400) each
extracted a helper because the calling `main` body was unreachable. The
`isMainModule` helper is already rolled out across `video-digest` extraction
and is not imported from course-digest.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds `isMainModule` (or equivalent) guards on the
six files plus at least a usage-branch test, an argument-validation exit-code
test, and an output-artifact assertion driven through argv for each CLI.

## Rationale

- The helper already exists in this plugin. The unpaid work is the guard
  sweep, the CLI-level suite, and retiring pass-through extractions, not
  inventing a new primitive.
- Extracting one more helper to make one assertion possible would repeat the
  #3398 / #3400 shape this candidate named.
- The issue is `work-class: structural` and `needs-human`.

## Revisit when

- A maintainer funds the guard-and-test sweep and names the first CLI, or
- a new defect has to be routed around an unreachable `main` body again.

## Prior requests

- #3421 (2026-09-28): deepening candidate; Option A recorded here and in
  `ai-briefing` `skills/generate/reference/build-pipeline.md`.

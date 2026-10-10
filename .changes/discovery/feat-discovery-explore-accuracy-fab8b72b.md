---
bump: minor
---

### Added

- **`/discovery:explore` artifacts record what their citations rest on.** The `EXPLORE.md`
  frontmatter pins each explored repository's `sha` and `dirty` flag under `repos:`, so a resuming
  session can diff the cited paths since that commit before trusting a `path:line`. The index gains
  a `## Code references` listing that opens with `coverage: exhaustive` or `coverage: key-files`.
- **`verified: ran`** joins `read | grep | inferred` in the EXPLORE sidecar header, carrying
  `command:` and the observed `result:`. A claim that a test or check passes needs it; a test that
  was only opened stays `read`.

### Changed

- Explore abstracts state the finding rather than what was covered; section file names stay fixed.
- A gap asking why the code was built a certain way is routed to `/discovery:trace-intent` instead
  of being explored from git history.
- The explore outcome gate and the explorer's verifier criterion check the new fields. A new plugin
  eval case, `explorer-pins-commit-and-reference-coverage`, grades the pinned sha and the coverage
  line off disk.

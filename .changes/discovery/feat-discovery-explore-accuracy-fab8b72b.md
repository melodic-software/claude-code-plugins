---
bump: minor
---

### Added

- **`/discovery:explore` artifacts record what their citations rest on.** The `EXPLORE.md`
  frontmatter pins each explored repository's `sha`, taken before the first file read, and a
  `dirty` flag that is also set when HEAD moved during the run. The index gains a
  `## Code references` listing that opens with `coverage: exhaustive` or `coverage: key-files`,
  followed by a line telling the reader to compare the sha with `HEAD` and re-read changed cited
  paths before trusting a `path:line`.
- **`verified: ran`** joins `read | grep | inferred` in the EXPLORE sidecar header, carrying
  `command:` and the observed `result:`. A claim that a test or check passes needs it; a test that
  was only opened stays `read`.

### Changed

- Explore abstracts state the finding rather than what was covered; section file names stay fixed.
- The explore outcome gate and the explorer's verifier criterion check the new fields. A new plugin
  eval case, `explorer-pins-commit-and-reference-coverage`, grades the pinned sha and the coverage
  line off disk.

---
bump: minor
---

### Added

- **`/code-metrics:audit size --file-lines <n>`.** Replaces the `size.file_lines` reference for
  one run and writes no layer; the report names the option as the layer that supplied the number.
- **`/code-metrics:audit size --commits-since <date>`.** Adds, for each file at or above the
  reference, the commits since that date that touched it, authors containing `[bot]` left out,
  most-changed first: a table in the markdown report and a `file_commits` object in the JSON. It
  ranks and sets no cutoff.
- **`/code-metrics:audit size`, which reference.** With no code-metrics layer setting
  `size.file_lines`, the action looks for a file-length limit the repository's own linter or
  analyzer configuration already sets and counts against it. The plugin ships no list of tools or
  rule names.
- **`/code-metrics:audit size`, acting on a long file.** One reference and no second stage. A file
  over the reference is acted on only when it also changes often, by filing a tracker item, never
  by a refactor inside an unrelated change; `/toolchain:ratchet` is offered to stop growth.

### Changed

- The `scc` collector row is verified against `scc` 4.1.0 as well as 3.7.0, and the install hint
  names the v4 module.

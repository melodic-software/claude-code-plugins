---
bump: patch
---

### Fixed

- **The visualize catalog no longer says a connector-backed page can never be shared publicly, and no longer lists an outdated artifacts version floor or an incomplete set of contexts where artifacts are off.** The connector, availability and design-canvas entries now state our decision and read the specifics live from anchored sections of the artifacts page, with an as-of date and a recheck trigger.

### Changed

- **Restated upstream specifics in `/visualization:visualize` and `/visualization:present` become anchored pointer records.** The design canvas's editing and export behavior, its settings and version gates, the `ClaudeDesign` write-refusal cases, the page-size and file-type limits, and the `userConfig` fixed-option floor are read live; the binary probe observations behind the `design` and `ClaudeDesign` records name `docs/native-surfaces/records.json` as their probe, and the mermaid runtime record names its probe pull request.

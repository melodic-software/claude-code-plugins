---
bump: major
---

### Changed

- **`/code-tidying:audit-dead-code` takes `--analyzer`, not `--lane`.** "Lane" now means only a
  worker that serves one pipeline stage, so the four detectors (knip, vulture, gopls, grep) are
  analyzers: run `dead-code-scan.sh --analyzer <name>` (`--lane` is gone, with no alias), and the
  scan prints `Analyzer:` lines and a `Summary analyzers:` line. Its reference moves to
  `context/analyzers.md`. `/code-tidying:remove-comments` says "no focus-area rotation".

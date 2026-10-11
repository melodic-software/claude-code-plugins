---
bump: patch
---

### Added

- **Diagnostic graders on the `browser-probe` eval case.** Eight `diag-*` regex graders over the trace name why a probe step failed without uploading the trace: `playwright-cli` not on `PATH`, a Bash permission refusal, a sandbox filesystem or network refusal, a browser launch failure, a refused or missing `Read` of the canary, any tool error, and whether `playwright-cli` printed output at all. Each failure signature uses `match: not_contains`, so a clean run still scores 1.0, and each carries `weight: 0.001`, the smallest change a positive weight allows to the score of the original twelve graders.

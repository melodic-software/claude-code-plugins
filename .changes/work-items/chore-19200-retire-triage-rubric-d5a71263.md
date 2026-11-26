---
bump: patch
---

### Added

- Ten `tr-ci-*` eval cases grade `/work-items:triage --issue <n> --ci` verdicts on intake issues, first triage and re-entry after a `**Decision recorded.**` comment: labels, `needs_human`, the `Flags:` line, `Blast radius:` and `Reversible:` lines, and `RECOMMENDED:` open questions. They replace the retired intake reentry-eval harness's cases. The shared fixture gains a `ci-intake` mode.

### Fixed

- The triage skill's triage-comment section no longer names `.github/scripts/intake-triage/triage-rubric.txt`, a file that is gone, as the intake lane's rubric.

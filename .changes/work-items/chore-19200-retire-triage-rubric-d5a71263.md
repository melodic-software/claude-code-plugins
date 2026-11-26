---
bump: patch
---

### Added

- Ten `tr-ci-*` eval cases grade `/work-items:triage --issue <n> --ci` verdicts on intake issues, first triage and re-entry after a `**Decision recorded.**` comment: labels, `needs_human`, the `Flags:` line, `Blast radius:` and `Reversible:` lines, `RECOMMENDED:` open questions, and, on re-entry, the verbatim quote and link of the decision. They replace the retired intake reentry-eval harness's cases. The shared fixture gains a `ci-intake` mode.

### Fixed

- The triage skill's triage-comment section points at CI mode's comment lines and the repository's `## Triage rules` as the source of the intake lane's lines, in place of `.github/scripts/intake-triage/triage-rubric.txt`, a file that is gone.
- The `tr-ci-issue-number-mismatch-stops` eval case grades the reply for no verdict object, since CI mode returns its verdict as structured output, not a `triage-verdict.json` file.

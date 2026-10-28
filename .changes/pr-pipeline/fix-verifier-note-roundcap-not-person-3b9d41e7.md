---
bump: patch
---

### Fixed

- A pr-verify note left open past the address-feedback round cap no longer hands the pull request to a person as `feedback-round-cap` with `needs-human`. It gets the fresh fixer's round as a code-review finding does, and once that round has run the head fails: `feedback-verifier-open` when only pr-verify notes are open, `feedback-not-converging` when a code-review finding is open beside them. A pr-verify note a trusted person directed, a security-review finding, a `claude[bot]` finding and a person's `needs-human` hold still escalate `feedback-round-cap`.

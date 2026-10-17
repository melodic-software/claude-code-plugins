---
bump: minor
---

### Added

- **`/source-control:pull-request review-venue` says, per AI review lane, whether CI reviews this repository.** A lane is `ci` when its caller workflow calls the org review workflow, is enabled, and its newest pull request run with a verdict succeeded within 7 days (`--max-age-days`); otherwise it is `local` (absent, which includes a disabled workflow, failing, which includes a usage-limit stop, or stale). A failed read treats every lane as `local`.

### Changed

- **`prep` and `ready` run a local AI review only where CI does not.** `prep` skips its code review, and `ready` skips its code or security review, when that lane reads `ci`; a lane that reads `local` gets the local review, reported as its stand-in. Each run reports the venue line it acted on.

### Fixed

- **The readiness verdict no longer calls a usage-limited review lane "safe to proceed".** A review lane that failed on a usage or rate limit reviewed nothing, so it is ABSENT and gets a local substitute, as Gate 5 already said.

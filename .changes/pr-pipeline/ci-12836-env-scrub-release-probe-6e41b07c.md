---
bump: patch
---

### Added

- upstream-apply-changelog gets a `scrub-probe` job: on each Claude Code release the gate takes, it
  runs `capture-probe.mjs` as a Bash child of a `run-claude-cli` leg on that release's CLI. A release
  that lets the child read the key, the job token or the runtime token fails the job with an error
  naming the release and hit names; a pass records the release in a notice and the job summary. No
  job needs it, so a red probe blocks no publishing. `capture-probe.mjs` takes further credential
  names from `CAPTURE_PROBE_EXTRA_NAMES` and lists the names it probed in its result.

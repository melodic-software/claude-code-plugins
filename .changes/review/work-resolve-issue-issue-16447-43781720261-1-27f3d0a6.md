---
bump: patch
---

### Fixed

- **`review:fanout-sweep`, spec trust.** The workflow hands a `spec` to its leaves only when its
  `loosenedSettings` arg carries the settings resolver's single `loosened_check_spec: counts` line,
  so an issue from an untrusted author never gives a loosened check its reason, whatever the
  orchestrator passes.
- **Loosened-check settings resolver, trusted-actor list.** `--spec-issue` reads the trusted-actor
  list only from the default branch the resolver resolves itself, and a `--ref` naming another
  commit, such as the head branch, gives no reason, so a change cannot add its own author to the list.

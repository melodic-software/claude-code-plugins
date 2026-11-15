---
bump: patch
---

### Changed

- `scripts/check-good-css-drift.sh --check` now checks only that the vendored good-css copies still hash to their pinned blob SHAs, offline; the upstream side of the pin is read by the marketplace's standard drift check. It runs weekly as a row of the marketplace's one drift workflow, whose issue for vojtaholik/good-css names it.

### Removed

- The optional `curl` prerequisite: no script in the plugin reads the network any more.

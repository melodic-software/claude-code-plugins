---
bump: minor
---

### Added

- **`resolve-promotion-evidence.mjs --inline` computes promotion evidence each call.** For the CI
  pr-merge lane: it runs the publisher's report-mode GitHub reads in memory from the binding's
  earliest promoted `ratified_at` and pipes the events to the checker as `--evidence -`, printing
  the file mode's JSON with no events file. It fails closed when that epoch start is missing or
  more than 85 days old (GitHub keeps a public repository's runs, checks and statuses at most 90
  days), or when a GitHub read fails. The file mode is unchanged.

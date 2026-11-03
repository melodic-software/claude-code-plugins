---
bump: none
---

### Added

- Two `fanout-diversity-*` fixtures in all four arms that each plant two defects on one axis, `request-options` (standards) and `month-export` (spec), with one recall grader per defect, so a report's positions within one heading can be measured.

### Changed

- The `search-sqli` ground truth reads `axis: spec`: its commit message calls the route a read-only lookup over the catalogue, and the injection reads the users table.
- `fanout-diversity.md` says the run's `node` must resolve without the operator's home directory; under an isolated `HOME` a version-manager shim fails, the review config read falls back to `(default)`, and the `multi-agent` hooks block every Bash call.

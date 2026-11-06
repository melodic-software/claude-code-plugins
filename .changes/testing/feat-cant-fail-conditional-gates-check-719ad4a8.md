---
bump: minor
---

### Changed

- **audit:** `rule-conditional-assertion` now gates `--check`, `--strict` or not, the same way `rule-zero-assertion` does. A whole-repository precision run labeled all 6 of its flags true positives. `--check` exits 1 on it, the `Ran:` line counts it with the gating rules, and the report-only note no longer lists it. The other seven report-only rules are unchanged.

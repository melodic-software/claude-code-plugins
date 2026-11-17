---
bump: minor
---

### Added

- The CI code-review and security-review lanes record a rule they wanted to cite and no criterion states as an `Uncovered rule:` line in a collapsed `Uncovered rules (N)` block of their summary. The line is never a finding: it posts no inline comment, adds nothing to the findings count and never sets a hold. `/corrections:codify reviews` reads it as a candidate rule.

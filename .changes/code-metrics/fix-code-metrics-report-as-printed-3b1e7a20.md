---
bump: patch
---

### Fixed

- `audit` and `audit-suppressions` present the printed report whole, with notes after it, so the
  coverage table and each reference's provenance reach the user; a frozen suppression count names
  the command that printed it; a long file that rarely changes gets no recommendation.

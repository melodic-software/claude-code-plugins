---
bump: minor
---

### Changed

- A role chain (`new --standing-rules`) now keeps Decisions in force in its standing-rules file beside Current rules and Standing preferences, leaving one pointer line in the hot file; `validate` still fails a decision that leaves without a `retire` listing, and a hot file that holds them inline still validates.
- A role chain's `- Retired entries:` lines now collect in one append-only, deduplicated `archive/<chain>/retired-index.md`, and Review before you continue holds one line naming it; `validate` fails a missing index and any earlier pointer it no longer holds. Chains without `standing_rules` are unchanged.

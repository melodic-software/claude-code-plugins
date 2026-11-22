---
bump: minor
---

### Added

- **`ubiquitous-language prune`.** A new action finds `audit`'s prune candidates, presents one
  group at a time, and removes or merges only the entries the person accepts. "Prune the glossary"
  and "the glossary feels bloated" now route to `prune`; `audit` stays read-only and names `prune`
  as its follow-up. The removal report also lists plain (unbolded) uses of a removed term inside
  other entries.
- **`Also called:` glossary line.** An optional line for a synonym a person accepted for the same
  concept; counting and `audit` treat it as the term itself. It is distinct from `Avoid:`.

### Changed

- `curate` adds and changes terms only; removing and merging entries moved to `prune`.
- `seed` counts names the way the contract's "Counting a term" section says.
- The glossary contract says an entry never records history, and that a check for rejected words is
  added only when an `audit` shows one crept back.
- The skill's `## Next` lists conditional follow-ups instead of one fixed successor.
